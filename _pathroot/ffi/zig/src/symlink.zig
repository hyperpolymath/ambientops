// symlink.zig
// Pure Zig FFI implementation for POSIX symlink operations
// SPDX-License-Identifier: PMPL-1.0

const std = @import("std");
const os = std.os;

/// Maximum path length per POSIX standard
const MAX_PATH_LEN: usize = 4096;

/// Read symbolic link target
/// Returns number of bytes written to buffer, or negative errno on error
export fn zig_readlink(
    path_ptr: [*:0]const u8,
    buffer_ptr: [*]u8,
    buffer_size: c_int,
) callconv(.C) c_int {
    // Validate inputs
    if (buffer_size <= 0 or buffer_size > MAX_PATH_LEN) {
        return -@as(c_int, @intFromEnum(std.posix.E.INVAL));
    }

    const path = std.mem.span(path_ptr);
    const buffer = buffer_ptr[0..@as(usize, @intCast(buffer_size))];

    // Call POSIX readlink
    const result = std.posix.readlink(path, buffer) catch |err| {
        return -@as(c_int, @intCast(@intFromError(err)));
    };

    return @as(c_int, @intCast(result.len));
}

/// Create symbolic link
/// Returns 0 on success, negative errno on error
export fn zig_symlink(
    target_ptr: [*:0]const u8,
    target_len: c_int,
    linkpath_ptr: [*:0]const u8,
    linkpath_len: c_int,
) callconv(.C) c_int {
    // Validate inputs
    if (target_len <= 0 or target_len > MAX_PATH_LEN) {
        return -@as(c_int, @intFromEnum(std.posix.E.INVAL));
    }
    if (linkpath_len <= 0 or linkpath_len > MAX_PATH_LEN) {
        return -@as(c_int, @intFromEnum(std.posix.E.INVAL));
    }

    const target = std.mem.span(target_ptr);
    const linkpath = std.mem.span(linkpath_ptr);

    // Call POSIX symlink
    std.posix.symlink(target, linkpath) catch |err| {
        return -@as(c_int, @intCast(@intFromError(err)));
    };

    return 0;
}

/// Zig ABI verification tests
test "zig_readlink basic functionality" {
    const testing = std.testing;

    // Create a test symlink
    const target = "/tmp/zig_test_target";
    const link = "/tmp/zig_test_link";

    // Clean up any existing test files
    std.fs.cwd().deleteFile(link) catch {};
    std.fs.cwd().deleteFile(target) catch {};

    // Create target file
    const file = try std.fs.cwd().createFile(target, .{});
    file.close();

    // Create symlink
    try std.posix.symlink(target, link);

    // Test readlink
    var buffer: [MAX_PATH_LEN]u8 = undefined;
    const result = zig_readlink(link, &buffer, MAX_PATH_LEN);

    try testing.expect(result > 0);
    try testing.expectEqualStrings(target, buffer[0..@as(usize, @intCast(result))]);

    // Cleanup
    try std.fs.cwd().deleteFile(link);
    try std.fs.cwd().deleteFile(target);
}

test "zig_symlink basic functionality" {
    const testing = std.testing;

    const target = "/tmp/zig_symlink_target";
    const link = "/tmp/zig_symlink_link";

    // Cleanup
    std.fs.cwd().deleteFile(link) catch {};
    std.fs.cwd().deleteFile(target) catch {};

    // Create target
    const file = try std.fs.cwd().createFile(target, .{});
    file.close();

    // Test symlink creation
    const result = zig_symlink(target, @as(c_int, @intCast(target.len)),
                                link, @as(c_int, @intCast(link.len)));

    try testing.expectEqual(@as(c_int, 0), result);

    // Verify symlink exists
    const stat = try std.fs.cwd().statFile(link);
    try testing.expect(stat.kind == .sym_link);

    // Cleanup
    try std.fs.cwd().deleteFile(link);
    try std.fs.cwd().deleteFile(target);
}

test "path length validation" {
    const testing = std.testing;

    // Test invalid buffer size
    var buffer: [1]u8 = undefined;
    const result = zig_readlink("/tmp/test", &buffer, -1);
    try testing.expect(result < 0);
}
