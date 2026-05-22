// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// capture.zig — Safe diagnostic capture modules.
//
// Ported from capture.v (2026-04-17).
//
// HIGH-004: PII redaction applied to every captured byte before writing.
// CRIT-004: Uses string matching (not regex) — same approach as the V original.
// HIGH-006: All file writes go through atomicWriteFile.
//
// All capture operations are best-effort and non-destructive.  A failed
// capture module is logged and skipped; it never aborts the run.

const std = @import("std");
const utils = @import("utils");
const incident_mod = @import("incident");

/// Result of running a single capture module.
pub const CaptureResult = struct {
    name: []const u8,
    success: bool,
    output: []const u8,
    error_msg: []const u8,
    /// Duration in milliseconds.
    duration_ms: i64,
};

/// A set of shell commands collected under one logical name.
pub const CaptureModule = struct {
    name: []const u8,
    display_name: []const u8,
    commands: []const []const u8,
};

// =============================================================================
// PII redaction
// =============================================================================

const sensitive_keys = [_][]const u8{
    "password", "passwd", "pwd", "secret", "token",
    "api_key",  "api-key", "apikey",
    "auth_token", "auth-token", "authtoken",
    "access_token", "access-token", "accesstoken",
    "private_key", "private-key", "privatekey",
    "aws_secret", "aws-secret",
    "bearer",
};

const sensitive_prefixes = [_][]const u8{
    "akia", "abia", "acca", "asia",
    "ghp_", "gho_", "ghu_", "ghs_", "ghr_",
};

/// Redact PII from the full `content` string.  Returns an allocated copy.
pub fn redactPii(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    var lines = std.ArrayList([]u8).empty;
    defer {
        for (lines.items) |l| allocator.free(l);
        lines.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, content, '\n');
    while (iter.next()) |line| {
        const redacted = try redactLine(allocator, line);
        try lines.append(allocator, redacted);
    }

    return std.mem.join(allocator, "\n", lines.items);
}

fn redactLine(allocator: std.mem.Allocator, line: []const u8) ![]u8 {
    var current = try allocator.dupe(u8, line);

    const lower = try std.ascii.allocLowerString(allocator, current);
    defer allocator.free(lower);

    for (sensitive_keys) |key| {
        if (std.mem.indexOf(u8, lower, key) != null) {
            const tmp_eq = try redactAfterKey(allocator, current, key, '=');
            allocator.free(current);
            current = tmp_eq;

            const lower2 = try std.ascii.allocLowerString(allocator, current);
            defer allocator.free(lower2);
            const tmp_col = try redactAfterKey(allocator, current, key, ':');
            allocator.free(current);
            current = tmp_col;
        }
    }

    const lower3 = try std.ascii.allocLowerString(allocator, current);
    defer allocator.free(lower3);
    for (sensitive_prefixes) |prefix| {
        if (std.mem.indexOf(u8, lower3, prefix) != null) {
            const tmp = try redactTokenPrefix(allocator, current, prefix);
            allocator.free(current);
            current = tmp;
        }
    }

    const lower4 = try std.ascii.allocLowerString(allocator, current);
    defer allocator.free(lower4);
    if (std.mem.indexOf(u8, lower4, "-----begin") != null and
        std.mem.indexOf(u8, lower4, "private key") != null)
    {
        allocator.free(current);
        current = try allocator.dupe(u8, "[REDACTED PRIVATE KEY BLOCK]");
    }

    const tmp_ssn = try redactSsn(allocator, current);
    allocator.free(current);
    current = tmp_ssn;

    const tmp_email = try redactEmails(allocator, current);
    allocator.free(current);
    current = tmp_email;

    return current;
}

fn redactAfterKey(
    allocator: std.mem.Allocator,
    line: []const u8,
    key: []const u8,
    sep: u8,
) ![]u8 {
    const lower = try std.ascii.allocLowerString(allocator, line);
    defer allocator.free(lower);

    const key_pos = std.mem.indexOf(u8, lower, key) orelse return allocator.dupe(u8, line);
    const rest = lower[key_pos + key.len ..];
    const sep_pos = std.mem.indexOfScalar(u8, rest, sep) orelse return allocator.dupe(u8, line);

    var value_start = key_pos + key.len + sep_pos + 1;
    if (value_start >= line.len) return allocator.dupe(u8, line);

    while (value_start < line.len and (line[value_start] == ' ' or line[value_start] == '\t')) {
        value_start += 1;
    }

    var end = value_start;
    while (end < line.len and line[end] != ' ' and line[end] != '\t' and
        line[end] != '\n' and line[end] != '\r')
    {
        end += 1;
    }

    if (end > value_start) {
        return std.mem.concat(allocator, u8, &.{ line[0..value_start], "[REDACTED]", line[end..] });
    }
    return allocator.dupe(u8, line);
}

fn redactTokenPrefix(
    allocator: std.mem.Allocator,
    line: []const u8,
    prefix: []const u8,
) ![]u8 {
    const lower = try std.ascii.allocLowerString(allocator, line);
    defer allocator.free(lower);

    const pos = std.mem.indexOf(u8, lower, prefix) orelse return allocator.dupe(u8, line);
    var end = pos + prefix.len;
    while (end < line.len) {
        const c = line[end];
        const is_token_char = std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
        if (!is_token_char) break;
        end += 1;
    }
    if (end > pos + prefix.len) {
        return std.mem.concat(allocator, u8, &.{ line[0..pos], "[REDACTED]", line[end..] });
    }
    return allocator.dupe(u8, line);
}

fn redactSsn(allocator: std.mem.Allocator, line: []const u8) ![]u8 {
    if (line.len < 11) return allocator.dupe(u8, line);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i + 10 < line.len) {
        if (std.ascii.isDigit(line[i]) and
            std.ascii.isDigit(line[i + 1]) and
            std.ascii.isDigit(line[i + 2]) and
            line[i + 3] == '-' and
            std.ascii.isDigit(line[i + 4]) and
            std.ascii.isDigit(line[i + 5]) and
            line[i + 6] == '-' and
            std.ascii.isDigit(line[i + 7]) and
            std.ascii.isDigit(line[i + 8]) and
            std.ascii.isDigit(line[i + 9]) and
            std.ascii.isDigit(line[i + 10]))
        {
            try out.appendSlice(allocator, "[REDACTED-SSN]");
            i += 11;
        } else {
            try out.append(allocator, line[i]);
            i += 1;
        }
    }
    while (i < line.len) : (i += 1) try out.append(allocator, line[i]);
    return out.toOwnedSlice(allocator);
}

fn redactEmails(allocator: std.mem.Allocator, line: []const u8) ![]u8 {
    const at_pos = std.mem.indexOfScalar(u8, line, '@') orelse return allocator.dupe(u8, line);

    var start = at_pos;
    while (start > 0 and isEmailChar(line[start - 1])) {
        start -= 1;
    }

    var end = at_pos + 1;
    var has_dot = false;
    while (end < line.len) {
        const c = line[end];
        if (c == '.') {
            has_dot = true;
            end += 1;
        } else if (isEmailChar(c)) {
            end += 1;
        } else break;
    }

    if (has_dot and end > at_pos + 3 and start < at_pos) {
        return std.mem.concat(allocator, u8, &.{ line[0..start], "[REDACTED-EMAIL]", line[end..] });
    }
    return allocator.dupe(u8, line);
}

fn isEmailChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or
        c == '-' or c == '+' or c == '%';
}

// =============================================================================
// Platform-specific command lists
// =============================================================================

const builtin = @import("builtin");

fn getOsVersionCommands() []const []const u8 {
    return switch (builtin.os.tag) {
        .linux => &.{
            "cat /etc/os-release",
            "uname -a",
            "hostnamectl 2>/dev/null || true",
        },
        .macos => &.{ "sw_vers", "uname -a" },
        .windows => &.{
            "systeminfo | findstr /B /C:\"OS\"",
            "ver",
        },
        else => &.{"uname -a"},
    };
}

fn getUptimeCommands() []const []const u8 {
    return switch (builtin.os.tag) {
        .linux => &.{ "uptime", "cat /proc/uptime" },
        .macos => &.{"uptime"},
        .windows => &.{"net statistics workstation | find \"Statistics\""},
        else => &.{"uptime"},
    };
}

fn getDiskCommands() []const []const u8 {
    return switch (builtin.os.tag) {
        .linux => &.{
            "df -h",
            "df -i",
            "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null || true",
        },
        .macos => &.{ "df -h", "diskutil list" },
        .windows => &.{"wmic logicaldisk get size,freespace,caption"},
        else => &.{"df -h"},
    };
}

fn getMemoryCommands() []const []const u8 {
    return switch (builtin.os.tag) {
        .linux => &.{ "free -h", "cat /proc/meminfo | head -20" },
        .macos => &.{ "vm_stat", "top -l 1 | head -10" },
        .windows => &.{"systeminfo | findstr Memory"},
        else => &.{},
    };
}

fn getNetworkCommands() []const []const u8 {
    return switch (builtin.os.tag) {
        .linux => &.{
            "ip addr show 2>/dev/null || ifconfig",
            "ip route show 2>/dev/null || route -n",
            "ss -tuln 2>/dev/null || netstat -tuln",
        },
        .macos => &.{
            "ifconfig",
            "netstat -rn",
            "netstat -an | head -50",
        },
        .windows => &.{
            "ipconfig /all",
            "netstat -an | findstr LISTENING",
        },
        else => &.{},
    };
}

fn getProcessCommands() []const []const u8 {
    return switch (builtin.os.tag) {
        .linux => &.{
            "ps aux --sort=-%mem | head -20",
            "ps aux --sort=-%cpu | head -20",
        },
        .macos => &.{
            "ps aux | head -20",
            "top -l 1 -o mem | head -20",
        },
        .windows => &.{"tasklist /V | findstr /V \"N/A\""},
        else => &.{"ps aux | head -20"},
    };
}

// =============================================================================
// Capture execution
// =============================================================================

/// Run all capture modules and append CommandLog entries to `incident`.
pub fn captureDiagnostics(
    allocator: std.mem.Allocator,
    incident: *incident_mod.Incident,
    config: incident_mod.Config,
) void {
    const modules = [_]CaptureModule{
        .{ .name = "os_version", .display_name = "OS Version", .commands = getOsVersionCommands() },
        .{ .name = "uptime", .display_name = "System Uptime", .commands = getUptimeCommands() },
        .{ .name = "disk_free", .display_name = "Disk Space", .commands = getDiskCommands() },
        .{ .name = "memory", .display_name = "Memory Status", .commands = getMemoryCommands() },
        .{ .name = "network_summary", .display_name = "Network Summary", .commands = getNetworkCommands() },
        .{ .name = "process_summary", .display_name = "Process Summary", .commands = getProcessCommands() },
    };

    for (modules) |mod| {
        const result = runCaptureModule(allocator, mod, incident, config);
        defer allocator.free(result.output);
        defer allocator.free(result.error_msg);

        if (result.success) {
            std.debug.print("  \x1b[32m✓\x1b[0m {s}\n", .{mod.display_name});
        } else {
            std.debug.print("  \x1b[33m○\x1b[0m {s} (skipped)\n", .{mod.display_name});
        }

        var ts_buf: [32]u8 = undefined;
        const now_ts = utils.formatRfc3339(std.time.milliTimestamp(), &ts_buf);

        const cmd_log = incident_mod.CommandLog{
            .name = allocator.dupe(u8, mod.name) catch continue,
            .command = std.mem.join(allocator, " | ", mod.commands) catch continue,
            .started_at = allocator.dupe(u8, now_ts) catch continue,
            .ended_at = allocator.dupe(u8, now_ts) catch continue,
            .exit_code = if (result.success) 0 else 1,
            .output_len = result.output.len,
        };
        incident.commands.append(allocator, cmd_log) catch continue;
    }

    incident_mod.updateIncidentJson(incident, config);
}

fn runCaptureModule(
    allocator: std.mem.Allocator,
    mod: CaptureModule,
    incident: *const incident_mod.Incident,
    config: incident_mod.Config,
) CaptureResult {
    const start_ms = std.time.milliTimestamp();
    var outputs = std.ArrayList(u8).empty;
    defer outputs.deinit(allocator);
    var success = false;

    for (mod.commands) |cmd| {
        if (config.dry_run) {
            const line = std.fmt.allocPrint(allocator, "[DRY-RUN] Would execute: {s}\n", .{cmd}) catch continue;
            defer allocator.free(line);
            outputs.appendSlice(allocator, line) catch {};
            success = true;
            continue;
        }

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "/bin/sh", "-c", cmd },
        }) catch continue;
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term == .Exited and result.term.Exited == 0) {
            const hdr = std.fmt.allocPrint(allocator, "=== {s} ===\n{s}\n\n", .{ cmd, result.stdout }) catch continue;
            defer allocator.free(hdr);
            outputs.appendSlice(allocator, hdr) catch {};
            success = true;
        }
    }

    const raw = outputs.toOwnedSlice(allocator) catch return CaptureResult{
        .name = mod.name,
        .success = false,
        .output = allocator.dupe(u8, "") catch "",
        .error_msg = allocator.dupe(u8, "OOM in capture") catch "",
        .duration_ms = 0,
    };
    defer allocator.free(raw);

    // HIGH-004: Redact PII before writing or returning.
    const output = redactPii(allocator, raw) catch allocator.dupe(u8, raw) catch "";

    const duration_ms = std.time.milliTimestamp() - start_ms;

    // Write log file (best-effort).
    if (!config.dry_run and output.len > 0) {
        const log_name = std.fmt.allocPrint(allocator, "{s}.log", .{mod.name}) catch "";
        defer allocator.free(log_name);
        if (log_name.len > 0) {
            const log_path = std.fs.path.join(allocator, &.{ incident.logs_path, log_name }) catch "";
            defer allocator.free(log_path);
            if (log_path.len > 0) {
                utils.atomicWriteFile(allocator, log_path, output) catch |err| {
                    utils.logError(allocator, incident.logs_path, "capture", "Failed to write log", &.{
                        .{ .key = "module", .value = mod.name },
                        .{ .key = "error", .value = @errorName(err) },
                    });
                    return CaptureResult{
                        .name = mod.name,
                        .success = false,
                        .output = allocator.dupe(u8, "") catch "",
                        .error_msg = std.fmt.allocPrint(allocator, "Failed to write log: {}", .{err}) catch "",
                        .duration_ms = duration_ms,
                    };
                };
            }
        }
    }

    return CaptureResult{
        .name = mod.name,
        .success = success,
        .output = output,
        .error_msg = allocator.dupe(u8, "") catch "",
        .duration_ms = duration_ms,
    };
}

// =============================================================================
// Tests
// =============================================================================

test "CaptureResult can be constructed" {
    const r = CaptureResult{
        .name = "test",
        .success = true,
        .output = "hello",
        .error_msg = "",
        .duration_ms = 42,
    };
    try std.testing.expect(r.success);
    try std.testing.expectEqual(@as(i64, 42), r.duration_ms);
}

test "redactPii removes known sensitive keys" {
    const alloc = std.testing.allocator;
    const input = "password=supersecret and more";
    const out = try redactPii(alloc, input);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "supersecret") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "[REDACTED]") != null);
}

test "redactPii handles SSN pattern" {
    const alloc = std.testing.allocator;
    const input = "SSN: 123-45-6789 end";
    const out = try redactPii(alloc, input);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "123-45-6789") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "[REDACTED-SSN]") != null);
}

test "redactPii redacts email addresses" {
    const alloc = std.testing.allocator;
    const input = "contact user@example.com now";
    const out = try redactPii(alloc, input);
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "user@example.com") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "[REDACTED-EMAIL]") != null);
}

test "os version commands non-empty" {
    const cmds = getOsVersionCommands();
    try std.testing.expect(cmds.len > 0);
}

test "uptime commands non-empty" {
    const cmds = getUptimeCommands();
    try std.testing.expect(cmds.len > 0);
}

test "process commands non-empty" {
    const cmds = getProcessCommands();
    try std.testing.expect(cmds.len > 0);
}
