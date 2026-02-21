// SPDX-License-Identifier: AGPL-3.0-or-later
//! FileSystem trait definition

const std = @import("std");
const main = @import("main.zig");
const Error = main.Error;
const Stat = main.Stat;
const DirIterator = main.DirIterator;
const Mode = main.Mode;

/// FileSystem interface (Zig trait pattern)
pub const FileSystem = struct {
    /// Required operations
    getattr: *const fn (path: []const u8) Error!Stat,
    readdir: *const fn (path: []const u8) Error!DirIterator,
    read: *const fn (path: []const u8, buf: []u8, offset: u64) Error!usize,

    /// Optional operations
    write: ?*const fn (path: []const u8, data: []const u8, offset: u64) Error!usize = null,
    create: ?*const fn (path: []const u8, mode: Mode) Error!void = null,
    unlink: ?*const fn (path: []const u8) Error!void = null,
    mkdir: ?*const fn (path: []const u8, mode: Mode) Error!void = null,
    rmdir: ?*const fn (path: []const u8) Error!void = null,
    rename: ?*const fn (old: []const u8, new: []const u8) Error!void = null,
    truncate: ?*const fn (path: []const u8, size: u64) Error!void = null,
    open: ?*const fn (path: []const u8, flags: u32) Error!u64 = null,
    release: ?*const fn (path: []const u8, fh: u64) void = null,
    fsync: ?*const fn (path: []const u8, datasync: bool, fh: u64) Error!void = null,
    flush: ?*const fn (path: []const u8, fh: u64) Error!void = null,
    statfs: ?*const fn (path: []const u8) Error!StatFs = null,
    readlink: ?*const fn (path: []const u8) Error![]const u8 = null,
    symlink: ?*const fn (target: []const u8, link: []const u8) Error!void = null,
    link: ?*const fn (old: []const u8, new: []const u8) Error!void = null,
    chmod: ?*const fn (path: []const u8, mode: Mode) Error!void = null,
    chown: ?*const fn (path: []const u8, uid: u32, gid: u32) Error!void = null,
    utimens: ?*const fn (path: []const u8, atime: i64, mtime: i64) Error!void = null,

    /// User data pointer
    userdata: ?*anyopaque = null,
};

pub const StatFs = struct {
    blocks: u64,
    bfree: u64,
    bavail: u64,
    files: u64,
    ffree: u64,
    bsize: u32,
    namelen: u32,
};
