// SPDX-License-Identifier: AGPL-3.0-or-later
//! Hello World FUSE filesystem example

const std = @import("std");
const fuse = @import("fuse");

const hello_str = "Hello, FUSE!\n";

fn getattr(path: []const u8) fuse.Error!fuse.Stat {
    if (std.mem.eql(u8, path, "/")) {
        return .{
            .mode = .{
                .permissions = 0o755,
                .sticky = false,
                .setgid = false,
                .setuid = false,
                .file_type = .directory,
            },
            .size = 0,
            .atime = 0,
            .mtime = 0,
            .ctime = 0,
            .uid = 0,
            .gid = 0,
            .nlink = 2,
            .ino = 1,
        };
    } else if (std.mem.eql(u8, path, "/hello")) {
        return .{
            .mode = .{
                .permissions = 0o444,
                .sticky = false,
                .setgid = false,
                .setuid = false,
                .file_type = .regular,
            },
            .size = hello_str.len,
            .atime = 0,
            .mtime = 0,
            .ctime = 0,
            .uid = 0,
            .gid = 0,
            .nlink = 1,
            .ino = 2,
        };
    }
    return fuse.Error.FileNotFound;
}

fn readdir(path: []const u8) fuse.Error!fuse.DirIterator {
    if (!std.mem.eql(u8, path, "/")) {
        return fuse.Error.NotADirectory;
    }

    const entries = [_]fuse.DirEntry{
        .{ .name = ".", .ino = 1, .mode = undefined },
        .{ .name = "..", .ino = 1, .mode = undefined },
        .{ .name = "hello", .ino = 2, .mode = undefined },
    };

    return .{ .entries = &entries, .index = 0 };
}

fn read(path: []const u8, buf: []u8, offset: u64) fuse.Error!usize {
    if (!std.mem.eql(u8, path, "/hello")) {
        return fuse.Error.FileNotFound;
    }

    if (offset >= hello_str.len) return 0;

    const len = @min(buf.len, hello_str.len - offset);
    @memcpy(buf[0..len], hello_str[offset..][0..len]);
    return len;
}

pub fn main() !void {
    const fs = fuse.FileSystem{
        .getattr = getattr,
        .readdir = readdir,
        .read = read,
    };

    const args = try std.process.argsAlloc(std.heap.page_allocator);
    defer std.process.argsFree(std.heap.page_allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <mountpoint>\n", .{args[0]});
        return;
    }

    std.debug.print("Mounting hello filesystem at {s}\n", .{args[1]});
    try fuse.mount(args[1], fs, .{});
}
