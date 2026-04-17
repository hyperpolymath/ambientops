// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// boot_guardian.zig — Boot health monitoring, loop detection, PCIe error scanning.
//
// Addresses CC-002 (unsafe shutdowns) and CC-003 (PCIe link failures causing
// boot loops).
//
// Boot events are tracked in a persistent JSON stamp file.  On each boot the
// guardian appends the current timestamp.  When too many boots occur within a
// short window a loop is flagged and safe-mode recommendations are emitted.
//
// Corresponds to: src/boot_guardian.v

const std = @import("std");
const utils = @import("utils");
const incident = @import("incident");

// ── Configuration ─────────────────────────────────────────────────────────────

pub const BOOT_LOOP_THRESHOLD: usize = 5;
pub const BOOT_LOOP_WINDOW_SECS: i64 = 600;
pub const DEFAULT_STAMP_PATH: []const u8 = "/var/lib/ambientops/boot-guardian/stamps.json";

// ── Types ─────────────────────────────────────────────────────────────────────

pub const BootStamp = struct {
    timestamp: []const u8,
    kernel: []const u8,
    epoch_seconds: i64,
    boot_id: []const u8,
};

pub const BootStampFile = struct {
    stamps: std.ArrayList(BootStamp),
    safe_mode: bool,
    loop_count: usize,

    pub fn deinit(self: *BootStampFile, allocator: std.mem.Allocator) void {
        for (self.stamps.items) |s| {
            allocator.free(s.timestamp);
            allocator.free(s.kernel);
            allocator.free(s.boot_id);
        }
        self.stamps.deinit(allocator);
    }
};

pub const PcieLinkError = struct {
    device: []const u8,
    message: []const u8,
    severity: []const u8,
};

pub const BootGuardianReport = struct {
    schema_version: []const u8,
    check_time: []const u8,
    boot_loop_detected: bool,
    recent_boot_count: usize,
    window_seconds: i64,
    threshold: usize,
    safe_mode_recommended: bool,
    pcie_link_errors: std.ArrayList(PcieLinkError),
    recent_stamps: std.ArrayList(BootStamp),

    pub fn deinit(self: *BootGuardianReport, allocator: std.mem.Allocator) void {
        allocator.free(self.check_time);
        for (self.pcie_link_errors.items) |e| {
            allocator.free(e.device);
            allocator.free(e.message);
            allocator.free(e.severity);
        }
        self.pcie_link_errors.deinit(allocator);
        for (self.recent_stamps.items) |s| {
            allocator.free(s.timestamp);
            allocator.free(s.kernel);
            allocator.free(s.boot_id);
        }
        self.recent_stamps.deinit(allocator);
    }
};

// ── Boot recording ────────────────────────────────────────────────────────────

/// Append the current boot to the stamp file.  Idempotent.
pub fn recordBoot(
    allocator: std.mem.Allocator,
    stamp_path: []const u8,
    dry_run: bool,
) !BootStampFile {
    var stamps = try loadStamps(allocator, stamp_path);
    errdefer stamps.deinit(allocator);

    const current_boot_id = try readBootId(allocator);
    defer allocator.free(current_boot_id);

    if (current_boot_id.len > 0) {
        for (stamps.stamps.items) |s| {
            if (std.mem.eql(u8, s.boot_id, current_boot_id)) return stamps;
        }
    }

    const now = std.time.timestamp();
    const ts = try utils.rfc3339FromEpoch(allocator, now);
    errdefer allocator.free(ts);
    const kern = try utils.getKernelVersion(allocator);
    errdefer allocator.free(kern);
    const bid = try allocator.dupe(u8, current_boot_id);
    errdefer allocator.free(bid);

    try stamps.stamps.append(allocator, BootStamp{
        .timestamp = ts,
        .kernel = kern,
        .epoch_seconds = now,
        .boot_id = bid,
    });

    // Prune stamps older than 24 h.
    const cutoff = now - 86400;
    var keep = std.ArrayList(BootStamp){};
    errdefer keep.deinit(allocator);
    for (stamps.stamps.items) |s| {
        if (s.epoch_seconds > cutoff) {
            try keep.append(allocator, s);
        } else {
            allocator.free(s.timestamp);
            allocator.free(s.kernel);
            allocator.free(s.boot_id);
        }
    }
    stamps.stamps.deinit(allocator);
    stamps.stamps = keep;

    if (dry_run) {
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would record boot stamp: {s}\n", .{ts});
        return stamps;
    }

    try saveStamps(allocator, stamp_path, stamps);
    return stamps;
}

/// Examine recent stamps and return a BootGuardianReport.
pub fn checkBootLoop(
    allocator: std.mem.Allocator,
    stamp_path: []const u8,
) !BootGuardianReport {
    var stamps = try loadStamps(allocator, stamp_path);
    defer stamps.deinit(allocator);

    const now = std.time.timestamp();
    const cutoff = now - BOOT_LOOP_WINDOW_SECS;

    var recent = std.ArrayList(BootStamp){};
    errdefer {
        for (recent.items) |s| {
            allocator.free(s.timestamp);
            allocator.free(s.kernel);
            allocator.free(s.boot_id);
        }
        recent.deinit(allocator);
    }
    for (stamps.stamps.items) |s| {
        if (s.epoch_seconds > cutoff) {
            try recent.append(allocator, BootStamp{
                .timestamp = try allocator.dupe(u8, s.timestamp),
                .kernel = try allocator.dupe(u8, s.kernel),
                .epoch_seconds = s.epoch_seconds,
                .boot_id = try allocator.dupe(u8, s.boot_id),
            });
        }
    }

    const loop_detected = recent.items.len >= BOOT_LOOP_THRESHOLD;

    var pcie_errors = try scanPcieLinkErrors(allocator);
    errdefer {
        for (pcie_errors.items) |e| {
            allocator.free(e.device);
            allocator.free(e.message);
            allocator.free(e.severity);
        }
        pcie_errors.deinit(allocator);
    }

    const safe_mode = loop_detected and
        (pcie_errors.items.len > 0 or recent.items.len >= BOOT_LOOP_THRESHOLD * 2);

    const check_time = try utils.rfc3339FromEpoch(allocator, now);
    errdefer allocator.free(check_time);

    return BootGuardianReport{
        .schema_version = utils.SCHEMA_VERSION,
        .check_time = check_time,
        .boot_loop_detected = loop_detected,
        .recent_boot_count = recent.items.len,
        .window_seconds = BOOT_LOOP_WINDOW_SECS,
        .threshold = BOOT_LOOP_THRESHOLD,
        .safe_mode_recommended = safe_mode,
        .pcie_link_errors = pcie_errors,
        .recent_stamps = recent,
    };
}

// ── PCIe error scanning (CC-003) ──────────────────────────────────────────────

fn scanPcieLinkErrors(allocator: std.mem.Allocator) !std.ArrayList(PcieLinkError) {
    var errors = std.ArrayList(PcieLinkError){};

    if (@import("builtin").target.os.tag != .linux) return errors;

    const r = utils.runShell(
        allocator,
        "dmesg 2>/dev/null | grep -i 'pcie\\|pcieport\\|link down\\|link training\\|AER' | tail -20",
    ) catch return errors;
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);

    if (r.exit_code == 0) {
        var lines = std.mem.splitScalar(u8, r.stdout, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            const redacted = try @import("capture").redactPii(allocator, trimmed);
            errdefer allocator.free(redacted);

            const severity = try allocator.dupe(u8, classifyPcieSeverity(trimmed));
            errdefer allocator.free(severity);

            const dev = try extractPcieDevice(allocator, trimmed);
            errdefer allocator.free(dev);

            try errors.append(allocator, PcieLinkError{
                .device = dev,
                .message = redacted,
                .severity = severity,
            });
        }
    }

    const aer = try scanAerCounters(allocator);
    // Transfer ownership of AER entries into errors list.
    for (aer.items) |e| {
        try errors.append(allocator, e);
    }
    // Only deinit the ArrayList wrapper; items are now owned by errors.
    var aer_copy = aer;
    aer_copy.deinit(allocator);

    return errors;
}

fn classifyPcieSeverity(line: []const u8) []const u8 {
    if (containsAsciiCi(line, "fatal") or containsAsciiCi(line, "link down")) return "critical";
    if (containsAsciiCi(line, "error") or containsAsciiCi(line, "uncorrectable")) return "error";
    return "warning";
}

fn containsAsciiCi(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (needle, 0..) |nc, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}

fn extractPcieDevice(allocator: std.mem.Allocator, line: []const u8) ![]u8 {
    if (line.len >= 7) {
        var i: usize = 0;
        while (i + 7 <= line.len) : (i += 1) {
            if (isHexChar(line[i]) and isHexChar(line[i + 1]) and
                line[i + 2] == ':' and
                isHexChar(line[i + 3]) and isHexChar(line[i + 4]) and
                line[i + 5] == '.' and
                isHexChar(line[i + 6]))
            {
                return allocator.dupe(u8, line[i .. i + 7]);
            }
        }
    }
    return allocator.dupe(u8, "unknown");
}

fn isHexChar(c: u8) bool {
    return (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn scanAerCounters(allocator: std.mem.Allocator) !std.ArrayList(PcieLinkError) {
    var errors = std.ArrayList(PcieLinkError){};

    const pci_path = "/sys/bus/pci/devices";
    var pci_dir = std.fs.cwd().openDir(pci_path, .{ .iterate = true }) catch return errors;
    defer pci_dir.close();

    var iter = pci_dir.iterate();
    while (iter.next() catch null) |entry| {
        const aer_path = try std.fmt.allocPrint(allocator, "{s}/{s}/aer_dev_fatal", .{
            pci_path, entry.name,
        });
        defer allocator.free(aer_path);

        const content_raw = blk: {
            const f = std.fs.cwd().openFile(aer_path, .{}) catch continue;
            defer f.close();
            break :blk f.readToEndAlloc(allocator, 64 * 1024) catch continue;
        };
        defer allocator.free(content_raw);

        var lines = std.mem.splitScalar(u8, content_raw, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r\n");
            if (trimmed.len == 0) continue;

            var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
            var first: ?[]const u8 = null;
            var last: ?[]const u8 = null;
            while (parts.next()) |part| {
                if (first == null) first = part;
                last = part;
            }
            if (first != null and last != null) {
                const count = std.fmt.parseInt(u64, last.?, 10) catch 0;
                if (count > 0) {
                    const msg = try std.fmt.allocPrint(
                        allocator,
                        "AER fatal error: {s} (count: {d})",
                        .{ first.?, count },
                    );
                    errdefer allocator.free(msg);
                    try errors.append(allocator, PcieLinkError{
                        .device = try allocator.dupe(u8, entry.name),
                        .message = msg,
                        .severity = "critical",
                    });
                }
            }
        }
    }

    return errors;
}

// ── Persistence ───────────────────────────────────────────────────────────────

fn loadStamps(allocator: std.mem.Allocator, path: []const u8) !BootStampFile {
    const empty = BootStampFile{
        .stamps = std.ArrayList(BootStamp){},
        .safe_mode = false,
        .loop_count = 0,
    };

    const content = blk: {
        const f = std.fs.cwd().openFile(path, .{}) catch return empty;
        defer f.close();
        break :blk f.readToEndAlloc(allocator, 1 * 1024 * 1024) catch return empty;
    };
    defer allocator.free(content);

    return parseStampFile(allocator, content) catch empty;
}

fn parseStampFile(allocator: std.mem.Allocator, content: []const u8) !BootStampFile {
    var result = BootStampFile{
        .stamps = std.ArrayList(BootStamp){},
        .safe_mode = false,
        .loop_count = 0,
    };
    errdefer result.deinit(allocator);

    var remaining = content;
    while (std.mem.indexOf(u8, remaining, "\"epoch_seconds\"") != null) {
        const epoch_pos = std.mem.indexOf(u8, remaining, "\"epoch_seconds\"").?;
        remaining = remaining[epoch_pos + 15 ..];
        const colon = std.mem.indexOfScalar(u8, remaining, ':') orelse break;
        remaining = remaining[colon + 1 ..];
        const digits_start = std.mem.indexOfAny(u8, remaining, "0123456789") orelse break;
        remaining = remaining[digits_start..];
        var digits_end: usize = 0;
        while (digits_end < remaining.len and std.ascii.isDigit(remaining[digits_end])) digits_end += 1;
        const epoch_secs = std.fmt.parseInt(i64, remaining[0..digits_end], 10) catch {
            remaining = remaining[digits_end..];
            continue;
        };
        remaining = remaining[digits_end..];

        const ts = try utils.rfc3339FromEpoch(allocator, epoch_secs);
        try result.stamps.append(allocator, BootStamp{
            .timestamp = ts,
            .kernel = try allocator.dupe(u8, ""),
            .epoch_seconds = epoch_secs,
            .boot_id = try allocator.dupe(u8, ""),
        });
    }

    return result;
}

fn saveStamps(
    allocator: std.mem.Allocator,
    path: []const u8,
    stamps: BootStampFile,
) !void {
    const dir = std.fs.path.dirname(path) orelse ".";
    std.fs.cwd().makePath(dir) catch {};

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const w = buf.writer(allocator);
    try w.writeAll("{\n");
    try w.print("  \"safe_mode\": {s},\n", .{if (stamps.safe_mode) "true" else "false"});
    try w.print("  \"loop_count\": {d},\n", .{stamps.loop_count});
    try w.writeAll("  \"stamps\": [");

    for (stamps.stamps.items, 0..) |s, i| {
        if (i > 0) try w.writeByte(',');
        try w.print(
            "\n    {{\"timestamp\":\"{s}\",\"kernel\":\"{s}\",\"epoch_seconds\":{d},\"boot_id\":\"{s}\"}}",
            .{ s.timestamp, s.kernel, s.epoch_seconds, s.boot_id },
        );
    }
    if (stamps.stamps.items.len > 0) try w.writeByte('\n') else try w.writeByte(' ');
    try w.writeAll("]\n}\n");

    try utils.atomicWriteFile(allocator, path, buf.items);
}

fn readBootId(allocator: std.mem.Allocator) ![]u8 {
    if (@import("builtin").target.os.tag != .linux) return allocator.dupe(u8, "");
    const f = std.fs.cwd().openFile("/proc/sys/kernel/random/boot_id", .{}) catch
        return allocator.dupe(u8, "");
    defer f.close();
    const raw = try f.readToEndAlloc(allocator, 64);
    defer allocator.free(raw);
    return allocator.dupe(u8, std.mem.trim(u8, raw, " \t\r\n"));
}

// ── CLI integration ───────────────────────────────────────────────────────────

pub const BootGuardianArgs = struct {
    stamp_path: []const u8 = DEFAULT_STAMP_PATH,
    dry_run: bool = false,
    record: bool = false,
    check_only: bool = false,
    json_output: bool = false,
};

pub fn runBootGuardian(
    allocator: std.mem.Allocator,
    args: BootGuardianArgs,
) !void {
    if (args.record) {
        const stamps = recordBoot(allocator, args.stamp_path, args.dry_run) catch |e| {
            utils.eprint("\x1b[31m[ERROR]\x1b[0m Failed to record boot: {s}\n", .{@errorName(e)});
            return error.BootRecordFailed;
        };
        var s = stamps;
        defer s.deinit(allocator);
        utils.print("\x1b[32m[OK]\x1b[0m Boot recorded ({d} stamps in history)\n", .{s.stamps.items.len});
    }

    if (args.check_only or !args.record) {
        var report = try checkBootLoop(allocator, args.stamp_path);
        defer report.deinit(allocator);

        if (args.json_output) {
            utils.print(
                "{{\"schema_version\":\"{s}\",\"check_time\":\"{s}\",\"boot_loop_detected\":{s},\"recent_boot_count\":{d},\"window_seconds\":{d},\"threshold\":{d},\"safe_mode_recommended\":{s}}}\n",
                .{
                    report.schema_version,
                    report.check_time,
                    if (report.boot_loop_detected) "true" else "false",
                    report.recent_boot_count,
                    report.window_seconds,
                    report.threshold,
                    if (report.safe_mode_recommended) "true" else "false",
                },
            );
            return;
        }

        utils.print("\n\x1b[34m╔══════════════════════════════════════════╗\x1b[0m\n", .{});
        utils.print("\x1b[34m║\x1b[0m       \x1b[1mBOOT GUARDIAN\x1b[0m                      \x1b[34m║\x1b[0m\n", .{});
        utils.print("\x1b[34m╚══════════════════════════════════════════╝\x1b[0m\n\n", .{});

        if (report.boot_loop_detected) {
            utils.print("\x1b[31m[ALERT]\x1b[0m Boot loop detected!\n", .{});
            utils.print("  {d} boots in the last {d} minutes (threshold: {d})\n", .{
                report.recent_boot_count,
                @divTrunc(report.window_seconds, 60),
                report.threshold,
            });
        } else {
            utils.print("\x1b[32m[OK]\x1b[0m No boot loop detected\n", .{});
            utils.print("  {d} boots in the last {d} minutes\n", .{
                report.recent_boot_count,
                @divTrunc(report.window_seconds, 60),
            });
        }

        if (report.pcie_link_errors.items.len > 0) {
            utils.print("\n\x1b[33m[WARN]\x1b[0m PCIe link errors detected:\n", .{});
            for (report.pcie_link_errors.items) |e| {
                const color = if (std.mem.eql(u8, e.severity, "critical")) "\x1b[31m" else "\x1b[33m";
                utils.print("  {s}[{s}]\x1b[0m {s}: {s}\n", .{
                    color, e.severity, e.device, e.message,
                });
            }
        }

        if (report.safe_mode_recommended) {
            utils.print("\n\x1b[31m╔══════════════════════════════════════════╗\x1b[0m\n", .{});
            utils.print("\x1b[31m║\x1b[0m  \x1b[1mSAFE MODE RECOMMENDED\x1b[0m                    \x1b[31m║\x1b[0m\n", .{});
            utils.print("\x1b[31m║\x1b[0m  Boot loop + PCIe errors detected.         \x1b[31m║\x1b[0m\n", .{});
            utils.print("\x1b[31m║\x1b[0m  Consider booting with:                    \x1b[31m║\x1b[0m\n", .{});
            utils.print("\x1b[31m║\x1b[0m    pci=noaer pci=nomsi                     \x1b[31m║\x1b[0m\n", .{});
            utils.print("\x1b[31m╚══════════════════════════════════════════╝\x1b[0m\n", .{});
        }
    }
}
