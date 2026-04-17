// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// incident.zig — Incident-bundle creation and management.
//
// Ported from incident.v (2026-04-17).
//
// HIGH-005: Incident IDs embed nanoseconds + 4-hex random suffix to prevent
//           collisions when the process is called in a tight loop.
// COULD-001: Correlation IDs (corr-XXXXXXXX) for cross-tool tracing.
// HIGH-006: All file writes go through atomicWriteFile.

const std = @import("std");
const utils = @import("utils");

/// Runtime configuration (mirrors V `Config` struct).
pub const Config = struct {
    quick_backup_dest: []const u8 = "",
    dry_run: bool = false,
    verbose: bool = false,
};

/// Per-command execution log entry.
pub const CommandLog = struct {
    name: []const u8,
    command: []const u8,
    started_at: []const u8,
    ended_at: []const u8,
    exit_code: i32,
    output_len: usize,
};

/// Platform snapshot embedded in the envelope.
pub const PlatformInfo = struct {
    os: []const u8,
    arch: []const u8,
    kernel: []const u8,
};

/// Trigger metadata embedded in the envelope.
pub const TriggerInfo = struct {
    version: []const u8,
    dry_run: bool,
    args: []const u8,
};

/// Top-level JSON envelope written to `incident.json`.
pub const IncidentEnvelope = struct {
    schema_version: []const u8,
    id: []const u8,
    correlation_id: []const u8,
    created_at: []const u8,
    hostname: []const u8,
    username: []const u8,
    working_dir: []const u8,
    platform: PlatformInfo,
    trigger: TriggerInfo,
    commands: []const CommandLog,
};

/// Live incident state carried through the run.
/// Owns `id`, `correlation_id`, `path`, `logs_path` — caller must call deinit.
pub const Incident = struct {
    allocator: std.mem.Allocator,
    id: []const u8,
    correlation_id: []const u8,
    path: []const u8,
    logs_path: []const u8,
    created_at_ms: i64,
    commands: std.ArrayList(CommandLog),

    pub fn deinit(self: *Incident) void {
        self.allocator.free(self.id);
        self.allocator.free(self.correlation_id);
        self.allocator.free(self.path);
        self.allocator.free(self.logs_path);
        for (self.commands.items) |*cmd| {
            self.allocator.free(cmd.name);
            self.allocator.free(cmd.command);
            self.allocator.free(cmd.started_at);
            self.allocator.free(cmd.ended_at);
        }
        self.commands.deinit(self.allocator);
    }
};

// =============================================================================
// Public API
// =============================================================================

pub const CreateError = error{
    AlreadyExists,
    MkdirFailed,
    WriteFailed,
    OutOfMemory,
};

/// Create the incident bundle directory tree and write the initial
/// `incident.json`.  In dry-run mode the directory is *not* created.
pub fn createIncidentBundle(
    allocator: std.mem.Allocator,
    config: Config,
) CreateError!Incident {
    const now_ms = std.time.milliTimestamp();
    const now_ns = std.time.nanoTimestamp();

    var ts_buf: [16]u8 = undefined;
    const ts = buildTimestampId(now_ms, &ts_buf);

    var rand_raw: [2]u8 = undefined;
    std.crypto.random.bytes(&rand_raw);
    const hex_suffix_arr = std.fmt.bytesToHex(rand_raw, .lower);

    const nanos_within_sec: u64 = @intCast(@rem(@abs(now_ns), 1_000_000_000));

    const incident_id = std.fmt.allocPrint(
        allocator,
        "incident-{s}-{d:0>9}-{s}",
        .{ ts, nanos_within_sec, hex_suffix_arr },
    ) catch return CreateError.OutOfMemory;
    errdefer allocator.free(incident_id);

    var corr_raw: [4]u8 = undefined;
    std.crypto.random.bytes(&corr_raw);
    const correlation_id = std.fmt.allocPrint(
        allocator,
        "corr-{s}",
        .{std.fmt.bytesToHex(corr_raw, .lower)},
    ) catch return CreateError.OutOfMemory;
    errdefer allocator.free(correlation_id);

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.process.getCwd(&cwd_buf) catch "";

    const incident_path = std.fs.path.join(allocator, &.{ cwd, incident_id }) catch
        return CreateError.OutOfMemory;
    errdefer allocator.free(incident_path);

    const logs_path = std.fs.path.join(allocator, &.{ incident_path, "logs" }) catch
        return CreateError.OutOfMemory;
    errdefer allocator.free(logs_path);

    if (config.dry_run) {
        const cyan = "\x1b[36m";
        const reset = "\x1b[0m";
        std.debug.print("{s}[DRY-RUN]{s} Would create: {s}\n", .{ cyan, reset, incident_path });
        std.debug.print("{s}[DRY-RUN]{s} Would create: {s}\n", .{ cyan, reset, logs_path });
        std.debug.print("{s}[DRY-RUN]{s} Correlation ID: {s}\n", .{ cyan, reset, correlation_id });
        return Incident{
            .allocator = allocator,
            .id = incident_id,
            .correlation_id = correlation_id,
            .path = incident_path,
            .logs_path = logs_path,
            .created_at_ms = now_ms,
            .commands = std.ArrayList(CommandLog).empty,
        };
    }

    if (std.fs.accessAbsolute(incident_path, .{})) |_| {
        return CreateError.AlreadyExists;
    } else |_| {}

    std.fs.makeDirAbsolute(incident_path) catch return CreateError.MkdirFailed;
    std.fs.makeDirAbsolute(logs_path) catch return CreateError.MkdirFailed;

    var incident = Incident{
        .allocator = allocator,
        .id = incident_id,
        .correlation_id = correlation_id,
        .path = incident_path,
        .logs_path = logs_path,
        .created_at_ms = now_ms,
        .commands = std.ArrayList(CommandLog).empty,
    };

    writeIncidentJson(&incident, config) catch return CreateError.WriteFailed;
    return incident;
}

/// (Re-)write `incident.json` with the current state of the incident.
pub fn writeIncidentJson(incident: *const Incident, config: Config) !void {
    var ts_buf: [32]u8 = undefined;
    const created_at = utils.formatRfc3339(incident.created_at_ms, &ts_buf);

    var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&hostname_buf) catch "unknown";

    const username = std.posix.getenv("USER") orelse "";

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.process.getCwd(&cwd_buf) catch "";

    var args_buf = std.ArrayList(u8).empty;
    defer args_buf.deinit(incident.allocator);
    var arg_iter = try std.process.argsWithAllocator(incident.allocator);
    defer arg_iter.deinit();
    var first = true;
    while (arg_iter.next()) |arg| {
        if (!first) try args_buf.append(incident.allocator, ' ');
        try args_buf.appendSlice(incident.allocator, arg);
        first = false;
    }

    const kernel = utils.getKernelVersion(incident.allocator);
    defer incident.allocator.free(kernel);

    const envelope = IncidentEnvelope{
        .schema_version = utils.schema_version,
        .id = incident.id,
        .correlation_id = incident.correlation_id,
        .created_at = created_at,
        .hostname = hostname,
        .username = username,
        .working_dir = cwd,
        .platform = .{
            .os = utils.getOsName(),
            .arch = utils.getArch(),
            .kernel = kernel,
        },
        .trigger = .{
            .version = app_version,
            .dry_run = config.dry_run,
            .args = args_buf.items,
        },
        .commands = incident.commands.items,
    };

    if (config.dry_run) {
        std.debug.print("\x1b[36m[DRY-RUN]\x1b[0m Would write incident.json\n", .{});
        return;
    }

    const json_path = try std.fs.path.join(incident.allocator, &.{ incident.path, "incident.json" });
    defer incident.allocator.free(json_path);

    const json_bytes = try std.json.Stringify.valueAlloc(
        incident.allocator,
        envelope,
        .{ .whitespace = .indent_2 },
    );
    defer incident.allocator.free(json_bytes);

    try utils.atomicWriteFile(incident.allocator, json_path, json_bytes);
}

/// Update `incident.json` in-place.  Silently warns on failure.
pub fn updateIncidentJson(incident: *const Incident, config: Config) void {
    if (config.dry_run) return;
    writeIncidentJson(incident, config) catch |err| {
        std.debug.print("\x1b[33m[WARN]\x1b[0m Could not update incident.json: {}\n", .{err});
    };
}

/// Write `receipt.adoc` into the incident bundle directory.
pub fn writeReceipt(incident: *const Incident, config: Config) !void {
    const receipt_path = try std.fs.path.join(
        incident.allocator,
        &.{ incident.path, "receipt.adoc" },
    );
    defer incident.allocator.free(receipt_path);

    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(incident.allocator);
    const w = buf.writer(incident.allocator);

    var ts_buf: [32]u8 = undefined;
    const created_at = utils.formatRfc3339(incident.created_at_ms, &ts_buf);

    var hostname_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname = std.posix.gethostname(&hostname_buf) catch "unknown";

    try w.writeAll(
        \\= Incident Receipt
        \\:icons: font
        \\:toc:
        \\
        \\== Summary
        \\
        \\|===
        \\|Field |Value
        \\
        \\
    );
    try w.print("|Incident ID\n|`{s}`\n\n", .{incident.id});
    try w.print("|Created\n|{s}\n\n", .{created_at});
    try w.print("|Hostname\n|{s}\n\n", .{hostname});
    try w.print("|Platform\n|{s} ({s})\n\n", .{ utils.getOsName(), utils.getArch() });
    try w.print("|Dry Run\n|{}\n|===\n\n", .{config.dry_run});

    try w.writeAll("== Commands Executed\n\n");
    if (incident.commands.items.len == 0) {
        try w.writeAll("_No commands logged._\n");
    } else {
        try w.writeAll("|===\n|Command |Exit Code |Output Size\n\n");
        for (incident.commands.items) |cmd| {
            try w.print("|{s}\n|{d}\n|{d} bytes\n\n", .{ cmd.name, cmd.exit_code, cmd.output_len });
        }
        try w.writeAll("|===\n");
    }

    try w.writeAll("\n== Log Files\n\n");
    if (config.dry_run) {
        try w.writeAll("_Dry run - no log files created._\n");
    } else {
        var log_dir = std.fs.openDirAbsolute(incident.logs_path, .{ .iterate = true }) catch {
            try w.writeAll("_No log files._\n");
            return writeReceiptFinish(&buf, receipt_path, config, incident.allocator);
        };
        defer log_dir.close();
        var it = log_dir.iterate();
        var any = false;
        while (it.next() catch null) |entry| {
            try w.print("* `logs/{s}`\n", .{entry.name});
            any = true;
        }
        if (!any) try w.writeAll("_No log files._\n");
    }

    try w.writeAll(
        \\
        \\== Next Steps
        \\
        \\1. Review the captured diagnostics in the `logs/` directory
        \\2. If issues persist, run specialized tools:
        \\   - `psa crisis --incident <incident_path>`
        \\   - `big-up scan --incident <incident_path>`
        \\3. Report findings via feedback-o-tron
        \\
        \\== License
        \\
        \\PMPL-1.0-or-later
        \\
    );

    try writeReceiptFinish(&buf, receipt_path, config, incident.allocator);
}

fn writeReceiptFinish(
    buf: *std.ArrayList(u8),
    receipt_path: []const u8,
    config: Config,
    allocator: std.mem.Allocator,
) !void {
    if (config.dry_run) {
        std.debug.print("\x1b[36m[DRY-RUN]\x1b[0m Would write receipt.adoc\n", .{});
        return;
    }
    try utils.atomicWriteFile(allocator, receipt_path, buf.items);
    std.debug.print("\x1b[32m[OK]\x1b[0m Written receipt.adoc\n", .{});
}

// =============================================================================
// Internal helpers
// =============================================================================

fn buildTimestampId(ms: i64, buf: []u8) []const u8 {
    const secs: u64 = @intCast(@divTrunc(ms, 1000));
    const epoch_s = std.time.epoch.EpochSeconds{ .secs = secs };
    const year_day = epoch_s.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch_s.getDaySeconds();
    return std.fmt.bufPrint(buf, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    }) catch buf[0..0];
}

pub const app_version: []const u8 = "0.1.0";
pub const app_name: []const u8 = "emergency-button";

// =============================================================================
// Tests
// =============================================================================

test "incident id starts with 'incident-'" {
    const alloc = std.testing.allocator;
    const config = Config{ .dry_run = true };
    var incident = try createIncidentBundle(alloc, config);
    defer incident.deinit();
    try std.testing.expect(std.mem.startsWith(u8, incident.id, "incident-"));
}

test "correlation id starts with 'corr-' and is 13 chars" {
    const alloc = std.testing.allocator;
    const config = Config{ .dry_run = true };
    var incident = try createIncidentBundle(alloc, config);
    defer incident.deinit();
    try std.testing.expect(std.mem.startsWith(u8, incident.correlation_id, "corr-"));
    try std.testing.expectEqual(@as(usize, 13), incident.correlation_id.len);
}

test "platform info values are non-empty" {
    const os_name = utils.getOsName();
    const arch = utils.getArch();
    try std.testing.expect(os_name.len > 0);
    try std.testing.expect(arch.len > 0);
}

test "command log can be appended to incident" {
    const alloc = std.testing.allocator;
    const config = Config{ .dry_run = true };
    var incident = try createIncidentBundle(alloc, config);
    defer incident.deinit();

    const cmd = CommandLog{
        .name = try alloc.dupe(u8, "uname"),
        .command = try alloc.dupe(u8, "uname -a"),
        .started_at = try alloc.dupe(u8, "2026-01-02T20:00:00.000Z"),
        .ended_at = try alloc.dupe(u8, "2026-01-02T20:00:01.000Z"),
        .exit_code = 0,
        .output_len = 128,
    };
    try incident.commands.append(alloc, cmd);
    try std.testing.expectEqual(@as(usize, 1), incident.commands.items.len);
    try std.testing.expectEqual(@as(i32, 0), incident.commands.items[0].exit_code);
}
