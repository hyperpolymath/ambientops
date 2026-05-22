// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// utils.zig — Shared utilities for emergency-room.
//
// Provides:
//   - atomicWriteFile: write to a temp file and rename (POSIX-atomic).
//   - atomicAppendFile: read-existing + append + atomicWriteFile.
//   - Structured log helpers: logInfo, logWarn, logError, logDebug.
//   - SCHEMA_VERSION constant.
//
// Corresponds to: src/utils.v (HIGH-006, HIGH-008).
//
// Safety contract:
//   - No hidden allocations; every function that allocates takes an
//     explicit std.mem.Allocator.
//   - On error paths all temporary resources are freed via errdefer /
//     defer before returning the error union.
//   - No @panic in reachable paths; all errors propagate as error values.

const std = @import("std");

pub const SCHEMA_VERSION: []const u8 = "1.0.0";

// ── Terminal output helpers ───────────────────────────────────────────────────
// std.io.getStdOut() was removed in Zig 0.15.2.  Use std.posix.write directly.

/// Write a formatted string to stdout.  Truncates silently if the message
/// exceeds 8 KiB; this is only used for human-readable terminal output, not
/// for structured data (which always goes through atomicWriteFile).
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = std.posix.write(std.posix.STDOUT_FILENO, msg) catch {};
}

/// Write a formatted string to stderr.
pub fn eprint(comptime fmt: []const u8, args: anytype) void {
    var buf: [8192]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = std.posix.write(std.posix.STDERR_FILENO, msg) catch {};
}

// ── Atomic file write ────────────────────────────────────────────────────────

/// Write `content` to `path` atomically by staging through a sibling temp file.
/// The temp file lives in the same directory so the rename is on-filesystem
/// (required for POSIX rename(2) atomicity).
///
/// Errors are returned; no @panic.
pub fn atomicWriteFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    content: []const u8,
) !void {
    // Derive the directory part of path.
    const dir_path = std.fs.path.dirname(path) orelse ".";
    const base = std.fs.path.basename(path);

    // Generate a random 8-hex-char suffix for the temp filename.
    var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
    const rand_val = rng.random().int(u32);
    const temp_name = try std.fmt.allocPrint(
        allocator,
        ".{s}.{x:0>8}.tmp",
        .{ base, rand_val },
    );
    defer allocator.free(temp_name);

    const temp_path = try std.fs.path.join(allocator, &.{ dir_path, temp_name });
    defer allocator.free(temp_path);

    // Write content to temp file.
    {
        const f = try std.fs.cwd().createFile(temp_path, .{});
        // Ensure temp file is removed on any error after creation.
        errdefer std.fs.cwd().deleteFile(temp_path) catch {};
        defer f.close();
        try f.writeAll(content);
    }

    // Rename temp → final (atomic on POSIX).
    std.fs.cwd().rename(temp_path, path) catch |err| {
        // Attempt cleanup; ignore secondary error.
        std.fs.cwd().deleteFile(temp_path) catch {};
        return err;
    };
}

/// Read existing content at `path` (empty string if missing), append `content`,
/// then atomicWriteFile the combined result.
pub fn atomicAppendFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    content: []const u8,
) !void {
    const existing: []u8 = blk: {
        const f = std.fs.cwd().openFile(path, .{}) catch |e| {
            if (e == error.FileNotFound) break :blk try allocator.alloc(u8, 0);
            return e;
        };
        defer f.close();
        break :blk try f.readToEndAlloc(allocator, 16 * 1024 * 1024);
    };
    defer allocator.free(existing);

    const combined = try std.fmt.allocPrint(allocator, "{s}{s}", .{ existing, content });
    defer allocator.free(combined);

    try atomicWriteFile(allocator, path, combined);
}

// ── Structured logging ────────────────────────────────────────────────────────

/// Key-value context pair for structured log entries.
pub const LogContext = struct {
    key: []const u8,
    value: []const u8,
};

/// Write a structured log line to `{logs_path}/structured.log`.
/// Format mirrors the V implementation:
///   ts=<rfc3339> level=<level> component=<component> msg="<escaped>" key="val" …
///
/// Best-effort: if the write fails the error is silently swallowed so that
/// logging never interrupts the main error-handling path.
pub fn logStructured(
    allocator: std.mem.Allocator,
    logs_path: []const u8,
    level: []const u8,
    component: []const u8,
    message: []const u8,
    context: []const LogContext,
) void {
    logStructuredInner(allocator, logs_path, level, component, message, context) catch {};
}

fn logStructuredInner(
    allocator: std.mem.Allocator,
    logs_path: []const u8,
    level: []const u8,
    component: []const u8,
    message: []const u8,
    context: []const LogContext,
) !void {
    const ts = try rfc3339Now(allocator);
    defer allocator.free(ts);

    // Escape message: replace " with \" and newlines with \n.
    const esc_msg = try escapeForLog(allocator, message);
    defer allocator.free(esc_msg);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const writer = buf.writer(allocator);
    try writer.print(
        "ts={s} level={s} component={s} msg=\"{s}\"",
        .{ ts, level, component, esc_msg },
    );

    for (context) |kv| {
        const esc_val = try escapeForLog(allocator, kv.value);
        defer allocator.free(esc_val);
        try writer.print(" {s}=\"{s}\"", .{ kv.key, esc_val });
    }
    try writer.writeByte('\n');

    const log_file = try std.fs.path.join(allocator, &.{ logs_path, "structured.log" });
    defer allocator.free(log_file);

    try atomicAppendFile(allocator, log_file, buf.items);
}

fn escapeForLog(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    // Upper-bound: each byte might become 2 bytes (\ + char).
    var out = try std.ArrayList(u8).initCapacity(allocator, s.len);
    errdefer out.deinit(allocator);
    for (s) |c| {
        if (c == '"') {
            try out.appendSlice(allocator, "\\\"");
        } else if (c == '\n') {
            try out.appendSlice(allocator, "\\n");
        } else {
            try out.append(allocator, c);
        }
    }
    return out.toOwnedSlice(allocator);
}

/// Convenience wrappers matching the V API.
pub fn logInfo(
    allocator: std.mem.Allocator,
    logs_path: []const u8,
    component: []const u8,
    message: []const u8,
) void {
    logStructured(allocator, logs_path, "info", component, message, &.{});
}

pub fn logWarn(
    allocator: std.mem.Allocator,
    logs_path: []const u8,
    component: []const u8,
    message: []const u8,
) void {
    logStructured(allocator, logs_path, "warn", component, message, &.{});
}

pub fn logError(
    allocator: std.mem.Allocator,
    logs_path: []const u8,
    component: []const u8,
    message: []const u8,
    context: []const LogContext,
) void {
    logStructured(allocator, logs_path, "error", component, message, context);
}

pub fn logDebug(
    allocator: std.mem.Allocator,
    logs_path: []const u8,
    component: []const u8,
    message: []const u8,
) void {
    logStructured(allocator, logs_path, "debug", component, message, &.{});
}

// ── RFC 3339 timestamp ────────────────────────────────────────────────────────

/// Return the current UTC time as an RFC 3339 string.
/// Caller owns the returned slice (allocator).
pub fn rfc3339Now(allocator: std.mem.Allocator) ![]u8 {
    const epoch_secs = std.time.timestamp();
    return rfc3339FromEpoch(allocator, epoch_secs);
}

/// Format `epoch_secs` (Unix seconds, UTC) as RFC 3339.
pub fn rfc3339FromEpoch(allocator: std.mem.Allocator, epoch_secs: i64) ![]u8 {
    const es = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(if (epoch_secs < 0) 0 else epoch_secs)) };
    const day = es.getEpochDay();
    const ymd = day.calculateYearDay();
    const year_day = ymd.calculateMonthDay();
    const day_secs = es.getDaySeconds();

    return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        ymd.year,
        @intFromEnum(year_day.month),
        year_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
    });
}

// ── Platform helpers ──────────────────────────────────────────────────────────

/// Return a human-readable OS name matching the V `get_os_name()` output.
pub fn getOsName() []const u8 {
    return switch (@import("builtin").target.os.tag) {
        .linux => "Linux",
        .macos => "macOS",
        .windows => "Windows",
        else => "Unknown",
    };
}

/// Return the CPU architecture string matching the V `get_arch()` output.
pub fn getArch() []const u8 {
    return switch (@import("builtin").target.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        .x86 => "i386",
        else => "unknown",
    };
}

/// Return the kernel version string (best-effort; "unknown" on non-Linux).
/// Caller owns returned slice.
pub fn getKernelVersion(allocator: std.mem.Allocator) ![]u8 {
    if (@import("builtin").target.os.tag != .linux and
        @import("builtin").target.os.tag != .macos) return allocator.dupe(u8, "unknown");

    const result = try runCommand(allocator, &.{ "uname", "-r" });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.exit_code == 0) {
        const trimmed = std.mem.trimRight(u8, result.stdout, " \t\r\n");
        return allocator.dupe(u8, trimmed);
    }
    return allocator.dupe(u8, "unknown");
}

// ── Command execution ─────────────────────────────────────────────────────────

pub const CommandResult = struct {
    stdout: []u8,
    stderr: []u8,
    exit_code: u8,
};

/// Run an external command and collect stdout/stderr.
/// Caller frees `result.stdout` and `result.stderr`.
pub fn runCommand(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) !CommandResult {
    var child = std.process.Child.init(argv, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 4 * 1024 * 1024);
    errdefer allocator.free(stdout);
    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1 * 1024 * 1024);
    errdefer allocator.free(stderr);

    const term = try child.wait();
    const code: u8 = switch (term) {
        .Exited => |c| c,
        else => 1,
    };

    return CommandResult{
        .stdout = stdout,
        .stderr = stderr,
        .exit_code = code,
    };
}

/// Run a shell command string via /bin/sh -c.
pub fn runShell(
    allocator: std.mem.Allocator,
    cmd: []const u8,
) !CommandResult {
    return runCommand(allocator, &.{ "/bin/sh", "-c", cmd });
}

// ── Hex generation ────────────────────────────────────────────────────────────

/// Generate `n` random hex bytes as a lowercase string.
/// Caller owns the returned slice.
pub fn randomHex(allocator: std.mem.Allocator, n: usize) ![]u8 {
    var rng = std.Random.DefaultPrng.init(@as(u64, @intCast(std.time.nanoTimestamp())));
    const bytes = try allocator.alloc(u8, n);
    defer allocator.free(bytes);
    rng.random().bytes(bytes);

    const hex_out = try allocator.alloc(u8, n * 2);
    errdefer allocator.free(hex_out);
    const digits = "0123456789abcdef";
    for (bytes, 0..) |b, i| {
        hex_out[i * 2]     = digits[b >> 4];
        hex_out[i * 2 + 1] = digits[b & 0x0f];
    }
    return hex_out;
}
