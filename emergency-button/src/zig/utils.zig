// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// utils.zig — Shared utilities for emergency-button.
//
// Ported from utils.v (2026-04-17).  All public V functions have working
// equivalents here.
//
// HIGH-006: Atomic file writes use temp-file + rename so a mid-write crash
//           cannot leave truncated data.
// HIGH-008: Structured logging to incident/logs/structured.log.

const std = @import("std");

/// Schema version for all output envelopes.
pub const schema_version: []const u8 = "1.0.0";

// =============================================================================
// Atomic file I/O
// =============================================================================

/// Write `content` to `path` atomically using a sibling temp file + rename.
/// Preserves the same-filesystem guarantee required for POSIX rename(2).
pub fn atomicWriteFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    content: []const u8,
) !void {
    const dir_path = std.fs.path.dirname(path) orelse ".";
    const base = std.fs.path.basename(path);

    var rand_bytes: [4]u8 = undefined;
    std.crypto.random.bytes(&rand_bytes);
    const hex = std.fmt.bytesToHex(rand_bytes, .lower);

    const temp_name = try std.fmt.allocPrint(
        allocator,
        ".{s}.{s}.tmp",
        .{ base, hex },
    );
    defer allocator.free(temp_name);

    const temp_path = try std.fs.path.join(allocator, &.{ dir_path, temp_name });
    defer allocator.free(temp_path);

    {
        const f = std.fs.createFileAbsolute(temp_path, .{}) catch |err| return err;
        defer f.close();
        try f.writeAll(content);
    }

    std.fs.renameAbsolute(temp_path, path) catch |err| {
        std.fs.deleteFileAbsolute(temp_path) catch {};
        return err;
    };
}

/// Read the existing file content (empty if absent), append `content`,
/// then atomic-write the result.
pub fn atomicAppendFile(
    allocator: std.mem.Allocator,
    path: []const u8,
    content: []const u8,
) !void {
    const existing_bytes = if (std.fs.openFileAbsolute(path, .{})) |f| blk: {
        defer f.close();
        break :blk try f.readToEndAlloc(allocator, 64 * 1024 * 1024);
    } else |_| try allocator.dupe(u8, "");
    defer allocator.free(existing_bytes);

    const combined = try std.mem.concat(allocator, u8, &.{ existing_bytes, content });
    defer allocator.free(combined);

    try atomicWriteFile(allocator, path, combined);
}

// =============================================================================
// Structured logging
// =============================================================================

pub const LogEntry = struct {
    timestamp: []const u8,
    level: []const u8,
    component: []const u8,
    message: []const u8,
    context: []const KV,

    pub const KV = struct { key: []const u8, value: []const u8 };
};

pub fn formatLogEntry(allocator: std.mem.Allocator, entry: LogEntry) ![]u8 {
    var parts = std.ArrayList(u8).empty;

    try parts.appendSlice(allocator, "ts=");
    try parts.appendSlice(allocator, entry.timestamp);
    try parts.appendSlice(allocator, " level=");
    try parts.appendSlice(allocator, entry.level);
    try parts.appendSlice(allocator, " component=");
    try parts.appendSlice(allocator, entry.component);

    const esc_msg = try escapeLogfmt(allocator, entry.message);
    defer allocator.free(esc_msg);

    const msg_part = try std.fmt.allocPrint(allocator, " msg=\"{s}\"", .{esc_msg});
    defer allocator.free(msg_part);
    try parts.appendSlice(allocator, msg_part);

    for (entry.context) |kv| {
        const esc_val = try escapeLogfmt(allocator, kv.value);
        defer allocator.free(esc_val);
        const kv_part = try std.fmt.allocPrint(allocator, " {s}=\"{s}\"", .{ kv.key, esc_val });
        defer allocator.free(kv_part);
        try parts.appendSlice(allocator, kv_part);
    }

    return parts.toOwnedSlice(allocator);
}

fn escapeLogfmt(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    for (s) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\n' => try out.appendSlice(allocator, "\\n"),
            else => try out.append(allocator, c),
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn logStructured(
    allocator: std.mem.Allocator,
    logs_path: []const u8,
    level: []const u8,
    component: []const u8,
    message: []const u8,
    context: []const LogEntry.KV,
) void {
    logStructuredImpl(allocator, logs_path, level, component, message, context) catch {};
}

fn logStructuredImpl(
    allocator: std.mem.Allocator,
    logs_path: []const u8,
    level: []const u8,
    component: []const u8,
    message: []const u8,
    context: []const LogEntry.KV,
) !void {
    var ts_buf: [32]u8 = undefined;
    const ts = formatRfc3339(std.time.milliTimestamp(), &ts_buf);

    const entry = LogEntry{
        .timestamp = ts,
        .level = level,
        .component = component,
        .message = message,
        .context = context,
    };

    const line_text = try formatLogEntry(allocator, entry);
    defer allocator.free(line_text);

    const with_newline = try std.mem.concat(allocator, u8, &.{ line_text, "\n" });
    defer allocator.free(with_newline);

    const log_file = try std.fs.path.join(allocator, &.{ logs_path, "structured.log" });
    defer allocator.free(log_file);

    try atomicAppendFile(allocator, log_file, with_newline);
}

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
    context: []const LogEntry.KV,
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

// =============================================================================
// Time formatting
// =============================================================================

pub fn formatRfc3339(ms: i64, buf: []u8) []const u8 {
    const secs: u64 = @intCast(@divTrunc(ms, 1000));
    const millis: u32 = @intCast(@mod(@abs(ms), 1000));
    const epoch_s = std.time.epoch.EpochSeconds{ .secs = secs };
    const year_day = epoch_s.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_secs = epoch_s.getDaySeconds();

    const written = std.fmt.bufPrint(buf, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>3}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_secs.getHoursIntoDay(),
        day_secs.getMinutesIntoHour(),
        day_secs.getSecondsIntoMinute(),
        millis,
    }) catch buf[0..0];
    return written;
}

// =============================================================================
// Platform detection
// =============================================================================

pub fn getOsName() []const u8 {
    return switch (builtin.os.tag) {
        .linux => "Linux",
        .macos => "macOS",
        .windows => "Windows",
        else => "Unknown",
    };
}

pub fn getArch() []const u8 {
    return switch (builtin.cpu.arch) {
        .x86_64 => "x86_64",
        .aarch64 => "arm64",
        .x86 => "i386",
        else => "unknown",
    };
}

/// Best-effort kernel version string.  Returns "unknown" if the query fails.
/// Returned slice is allocated; caller must free.
pub fn getKernelVersion(allocator: std.mem.Allocator) []const u8 {
    const cmd: []const []const u8 = switch (builtin.os.tag) {
        .linux, .macos => &.{ "uname", "-r" },
        .windows => &.{ "cmd", "/c", "ver" },
        else => return allocator.dupe(u8, "unknown") catch "unknown",
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = cmd,
    }) catch return allocator.dupe(u8, "unknown") catch "unknown";
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term == .Exited and result.term.Exited == 0) {
        const trimmed = std.mem.trim(u8, result.stdout, &std.ascii.whitespace);
        return allocator.dupe(u8, trimmed) catch "unknown";
    }
    return allocator.dupe(u8, "unknown") catch "unknown";
}

const builtin = @import("builtin");

// =============================================================================
// Tests
// =============================================================================

test "schema_version is semver" {
    try std.testing.expect(std.mem.count(u8, schema_version, ".") >= 1);
}

test "formatRfc3339 produces ISO 8601 shape" {
    var buf: [32]u8 = undefined;
    const s = formatRfc3339(0, &buf);
    try std.testing.expect(s.len >= 20);
    try std.testing.expect(std.mem.indexOfScalar(u8, s, 'T') != null);
}

test "escapeLogfmt escapes quotes and newlines" {
    const alloc = std.testing.allocator;
    const out = try escapeLogfmt(alloc, "say \"hello\"\nbye");
    defer alloc.free(out);
    try std.testing.expectEqualStrings("say \\\"hello\\\"\\nbye", out);
}
