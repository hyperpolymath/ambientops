// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// capture.zig — Safe diagnostic capture modules.
//
// Best-effort, non-destructive data collection.
// PII redaction applied to all captured output (HIGH-004).
// Atomic file writes to prevent corruption (HIGH-006).
//
// Corresponds to: src/capture.v

const std = @import("std");
const utils = @import("utils");

// ── PII redaction ─────────────────────────────────────────────────────────────

const SENSITIVE_KEYS = [_][]const u8{
    "password", "passwd", "pwd",      "secret",      "token",
    "api_key",  "api-key", "apikey",
    "auth_token", "auth-token", "authtoken",
    "access_token", "access-token", "accesstoken",
    "private_key",  "private-key",  "privatekey",
    "aws_secret", "aws-secret",
    "bearer",
};

const SENSITIVE_PREFIXES = [_][]const u8{
    "akia", "abia", "acca", "asia",          // AWS keys
    "ghp_", "gho_", "ghu_", "ghs_", "ghr_", // GitHub tokens
};

/// Redact PII from `content`.  Caller owns returned slice.
pub fn redactPii(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    var lines = std.ArrayList([]u8){};
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
    const lower = try std.ascii.allocLowerString(allocator, line);
    defer allocator.free(lower);

    var current = try allocator.dupe(u8, line);

    // Sensitive key=value / key: value patterns.
    for (SENSITIVE_KEYS) |key| {
        if (std.mem.indexOf(u8, lower, key) != null) {
            var tmp = try redactAfterKey(allocator, current, key, '=');
            allocator.free(current);
            current = tmp;
            tmp = try redactAfterKey(allocator, current, key, ':');
            allocator.free(current);
            current = tmp;
        }
    }

    // Token-prefix patterns.
    const lower2 = try std.ascii.allocLowerString(allocator, current);
    defer allocator.free(lower2);
    for (SENSITIVE_PREFIXES) |prefix| {
        if (std.mem.indexOf(u8, lower2, prefix) != null) {
            const tmp = try redactTokenPrefix(allocator, current, prefix);
            allocator.free(current);
            current = tmp;
        }
    }

    // Private key block marker.
    const lower3 = try std.ascii.allocLowerString(allocator, current);
    defer allocator.free(lower3);
    if (std.mem.indexOf(u8, lower3, "-----begin") != null and
        std.mem.indexOf(u8, lower3, "private key") != null)
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

/// Redact the value that follows `key` + `sep` on the same line.
fn redactAfterKey(
    allocator: std.mem.Allocator,
    line: []const u8,
    key: []const u8,
    sep: u8,
) ![]u8 {
    const lower = try std.ascii.allocLowerString(allocator, line);
    defer allocator.free(lower);

    const key_pos = std.mem.indexOf(u8, lower, key) orelse return allocator.dupe(u8, line);
    const rest = line[key_pos + key.len ..];
    const sep_pos = std.mem.indexOfScalar(u8, rest, sep) orelse return allocator.dupe(u8, line);

    var value_start = key_pos + key.len + sep_pos + 1;
    if (value_start >= line.len) return allocator.dupe(u8, line);

    // Skip whitespace.
    while (value_start < line.len and (line[value_start] == ' ' or line[value_start] == '\t')) {
        value_start += 1;
    }

    // Find end of value token.
    var value_end = value_start;
    while (value_end < line.len) {
        const c = line[value_end];
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') break;
        value_end += 1;
    }

    if (value_end <= value_start) return allocator.dupe(u8, line);

    return std.fmt.allocPrint(allocator, "{s}[REDACTED]{s}", .{
        line[0..value_start],
        line[value_end..],
    });
}

/// Redact tokens that start with a known sensitive prefix.
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
        const is_tok = std.ascii.isAlphanumeric(c) or c == '_' or c == '-';
        if (!is_tok) break;
        end += 1;
    }

    if (end <= pos + prefix.len) return allocator.dupe(u8, line);

    return std.fmt.allocPrint(allocator, "{s}[REDACTED]{s}", .{
        line[0..pos],
        line[end..],
    });
}

/// Redact SSN patterns (###-##-####).
fn redactSsn(allocator: std.mem.Allocator, line: []const u8) ![]u8 {
    if (line.len < 11) return allocator.dupe(u8, line);

    var result = try allocator.dupe(u8, line);
    var i: usize = 0;

    while (i + 10 < result.len) {
        if (std.ascii.isDigit(result[i]) and
            std.ascii.isDigit(result[i + 1]) and
            std.ascii.isDigit(result[i + 2]) and
            result[i + 3] == '-' and
            std.ascii.isDigit(result[i + 4]) and
            std.ascii.isDigit(result[i + 5]) and
            result[i + 6] == '-' and
            std.ascii.isDigit(result[i + 7]) and
            std.ascii.isDigit(result[i + 8]) and
            std.ascii.isDigit(result[i + 9]) and
            std.ascii.isDigit(result[i + 10]))
        {
            const new = try std.fmt.allocPrint(allocator, "{s}[REDACTED-SSN]{s}", .{
                result[0..i],
                result[i + 11 ..],
            });
            allocator.free(result);
            result = new;
            i += 14; // len("[REDACTED-SSN]")
        } else {
            i += 1;
        }
    }

    return result;
}

fn isEmailChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-' or c == '+' or c == '%';
}

/// Redact email addresses (word@word.word).
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
        } else {
            break;
        }
    }

    if (!has_dot or end <= at_pos + 3 or start >= at_pos) {
        return allocator.dupe(u8, line);
    }

    return std.fmt.allocPrint(allocator, "{s}[REDACTED-EMAIL]{s}", .{
        line[0..start],
        line[end..],
    });
}

// ── Capture module types ──────────────────────────────────────────────────────

pub const CaptureResult = struct {
    name: []const u8,
    success: bool,
    output: []const u8,
    error_msg: []const u8,
    duration_ms: i64,
};

pub const CaptureModule = struct {
    name: []const u8,
    display_name: []const u8,
    commands: []const []const u8,
};

// ── Platform command lists ────────────────────────────────────────────────────

const IS_LINUX = @import("builtin").target.os.tag == .linux;
const IS_MACOS = @import("builtin").target.os.tag == .macos;
const IS_WINDOWS = @import("builtin").target.os.tag == .windows;

pub fn getOsVersionCommands() []const []const u8 {
    if (IS_LINUX) return &.{
        "cat /etc/os-release",
        "uname -a",
        "hostnamectl 2>/dev/null || true",
    };
    if (IS_MACOS) return &.{ "sw_vers", "uname -a" };
    if (IS_WINDOWS) return &.{
        "systeminfo | findstr /B /C:\"OS\"",
        "ver",
    };
    return &.{"uname -a"};
}

pub fn getUptimeCommands() []const []const u8 {
    if (IS_LINUX) return &.{ "uptime", "cat /proc/uptime" };
    if (IS_MACOS) return &.{"uptime"};
    if (IS_WINDOWS) return &.{"net statistics workstation | find \"Statistics\""};
    return &.{"uptime"};
}

pub fn getDiskCommands() []const []const u8 {
    if (IS_LINUX) return &.{
        "df -h",
        "df -i",
        "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT 2>/dev/null || true",
    };
    if (IS_MACOS) return &.{ "df -h", "diskutil list" };
    if (IS_WINDOWS) return &.{"wmic logicaldisk get size,freespace,caption"};
    return &.{"df -h"};
}

pub fn getMemoryCommands() []const []const u8 {
    if (IS_LINUX) return &.{ "free -h", "cat /proc/meminfo | head -20" };
    if (IS_MACOS) return &.{ "vm_stat", "top -l 1 | head -10" };
    if (IS_WINDOWS) return &.{"systeminfo | findstr Memory"};
    return &.{};
}

pub fn getNetworkCommands() []const []const u8 {
    if (IS_LINUX) return &.{
        "ip addr show 2>/dev/null || ifconfig",
        "ip route show 2>/dev/null || route -n",
        "ss -tuln 2>/dev/null || netstat -tuln",
    };
    if (IS_MACOS) return &.{ "ifconfig", "netstat -rn", "netstat -an | head -50" };
    if (IS_WINDOWS) return &.{ "ipconfig /all", "netstat -an | findstr LISTENING" };
    return &.{};
}

pub fn getProcessCommands() []const []const u8 {
    if (IS_LINUX) return &.{
        "ps aux --sort=-%mem | head -20",
        "ps aux --sort=-%cpu | head -20",
    };
    if (IS_MACOS) return &.{ "ps aux | head -20", "top -l 1 -o mem | head -20" };
    if (IS_WINDOWS) return &.{"tasklist /V | findstr /V \"N/A\""};
    return &.{"ps aux | head -20"};
}

// ── RunCaptureModule ──────────────────────────────────────────────────────────

/// Run a single capture module.  Returns owned CaptureResult.
/// All string fields inside the result are owned by `allocator`.
pub fn runCaptureModule(
    allocator: std.mem.Allocator,
    mod: CaptureModule,
    logs_path: []const u8,
    dry_run: bool,
) !CaptureResult {
    const start_ns = std.time.nanoTimestamp();

    var outputs = std.ArrayList(u8){};
    defer outputs.deinit(allocator);

    var success = false;

    for (mod.commands) |cmd| {
        if (dry_run) {
            const line = try std.fmt.allocPrint(allocator, "[DRY-RUN] Would execute: {s}\n", .{cmd});
            defer allocator.free(line);
            try outputs.appendSlice(allocator, line);
            success = true;
            continue;
        }

        const result = utils.runShell(allocator, cmd) catch |e| {
            const msg = try std.fmt.allocPrint(allocator, "[WARN] Could not run '{s}': {s}\n", .{ cmd, @errorName(e) });
            defer allocator.free(msg);
            try outputs.appendSlice(allocator, msg);
            continue;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.exit_code == 0) {
            const header = try std.fmt.allocPrint(allocator, "=== {s} ===\n", .{cmd});
            defer allocator.free(header);
            try outputs.appendSlice(allocator, header);
            try outputs.appendSlice(allocator, result.stdout);
            try outputs.appendSlice(allocator, "\n");
            success = true;
        }
    }

    const duration_ms = @divTrunc(std.time.nanoTimestamp() - start_ns, std.time.ns_per_ms);

    // Apply PII redaction (HIGH-004).
    const raw = outputs.items;
    const output = try redactPii(allocator, raw);
    errdefer allocator.free(output);

    // Write log file atomically (HIGH-006).
    if (!dry_run and output.len > 0) {
        const log_file = try std.fs.path.join(allocator, &.{ logs_path, try std.fmt.allocPrint(allocator, "{s}.log", .{mod.name}) });
        defer allocator.free(log_file);

        utils.atomicWriteFile(allocator, log_file, output) catch |e| {
            utils.logError(allocator, logs_path, "capture", "Failed to write log", &.{
                .{ .key = "module", .value = mod.name },
                .{ .key = "error", .value = @errorName(e) },
            });
            return CaptureResult{
                .name = mod.name,
                .success = false,
                .output = output,
                .error_msg = try std.fmt.allocPrint(allocator, "Failed to write log: {s}", .{@errorName(e)}),
                .duration_ms = @intCast(duration_ms),
            };
        };
    }

    return CaptureResult{
        .name = mod.name,
        .success = success,
        .output = output,
        .error_msg = try allocator.dupe(u8, ""),
        .duration_ms = @intCast(duration_ms),
    };
}
