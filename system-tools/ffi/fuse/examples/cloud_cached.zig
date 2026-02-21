// SPDX-License-Identifier: AGPL-3.0-or-later
//! Cloud filesystem with caching example

const std = @import("std");
const fuse = @import("fuse");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create cloud filesystem with rate limiting
    var cloud_fs = try fuse.cloud.CloudFs.init(allocator, .{
        .read = dummyRead,
        .write = dummyWrite,
        .getattr = dummyGetattr,
        .readdir = dummyReaddir,
        .userdata = null,
    }, .{
        .tps = 4, // Dropbox-safe
        .burst = 1,
        .cache_mode = .writes,
        .cache_max_age = 72 * std.time.ns_per_hour,
    });
    defer cloud_fs.deinit();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <mountpoint>\n", .{args[0]});
        return;
    }

    std.debug.print("Mounting cloud filesystem at {s}\n", .{args[1]});
    std.debug.print("Rate limit: 4 TPS, Cache mode: writes\n", .{});

    try fuse.mount(args[1], cloud_fs.toFileSystem(), .{
        .allow_other = true,
        .auto_unmount = true,
    });
}

fn dummyRead(path: []const u8, buf: []u8, offset: u64) fuse.Error!usize {
    _ = path;
    _ = buf;
    _ = offset;
    return 0;
}

fn dummyWrite(path: []const u8, data: []const u8, offset: u64) fuse.Error!usize {
    _ = path;
    _ = data;
    _ = offset;
    return 0;
}

fn dummyGetattr(path: []const u8) fuse.Error!fuse.Stat {
    _ = path;
    return fuse.Error.FileNotFound;
}

fn dummyReaddir(path: []const u8) fuse.Error!fuse.DirIterator {
    _ = path;
    return .{ .entries = &.{}, .index = 0 };
}
