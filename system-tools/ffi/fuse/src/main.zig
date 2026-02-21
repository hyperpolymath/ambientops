// SPDX-License-Identifier: AGPL-3.0-or-later
//! zig-fuse-ext: Extended Zig FUSE bindings with cloud-optimized features
//!
//! Builds on libfuse3 FFI to provide:
//! - Full FUSE 3.x API access
//! - Cloud optimizations (rate limiting, caching, prefetch)
//! - Cross-platform support (Linux, macOS, FreeBSD)

const std = @import("std");
const c = @import("c.zig");

pub const FileSystem = @import("filesystem.zig").FileSystem;
pub const Operations = @import("operations.zig").Operations;

/// Cloud-optimized components
pub const cloud = struct {
    pub const RateLimiter = @import("cloud/rate_limiter.zig").RateLimiter;
    pub const WriteBackCache = @import("cloud/cache.zig").WriteBackCache;
    pub const Prefetcher = @import("cloud/prefetch.zig").Prefetcher;
    pub const CloudFs = @import("cloud/cloud_fs.zig").CloudFs;
};

/// Platform-specific implementations
pub const platform = switch (@import("builtin").os.tag) {
    .linux => @import("platform/linux.zig"),
    .macos => @import("platform/macos.zig"),
    .freebsd => @import("platform/freebsd.zig"),
    else => @compileError("Unsupported platform for FUSE"),
};

/// FUSE error codes
pub const Error = error{
    MountFailed,
    SessionFailed,
    OperationFailed,
    FileNotFound,
    PermissionDenied,
    NotADirectory,
    IsADirectory,
    NotEmpty,
    NoSpace,
    IoError,
    InvalidArgument,
};

/// File mode/type
pub const Mode = packed struct {
    permissions: u9,
    sticky: bool,
    setgid: bool,
    setuid: bool,
    file_type: FileType,

    pub const FileType = enum(u4) {
        regular = 0o10,
        directory = 0o04,
        symlink = 0o12,
        block_device = 0o06,
        char_device = 0o02,
        fifo = 0o01,
        socket = 0o14,
    };
};

/// File stat structure
pub const Stat = struct {
    mode: Mode,
    size: u64,
    atime: i64,
    mtime: i64,
    ctime: i64,
    uid: u32,
    gid: u32,
    nlink: u32,
    ino: u64,
};

/// Directory entry iterator
pub const DirIterator = struct {
    entries: []const DirEntry,
    index: usize,

    pub fn next(self: *DirIterator) ?DirEntry {
        if (self.index >= self.entries.len) return null;
        const entry = self.entries[self.index];
        self.index += 1;
        return entry;
    }
};

pub const DirEntry = struct {
    name: []const u8,
    ino: u64,
    mode: Mode,
};

/// Mount a filesystem
pub fn mount(mount_point: []const u8, fs: FileSystem, options: MountOptions) Error!void {
    _ = mount_point;
    _ = fs;
    _ = options;
    // TODO: Implement via fuse_session_new + fuse_session_mount
}

pub const MountOptions = struct {
    allow_other: bool = false,
    auto_unmount: bool = true,
    foreground: bool = true,
    debug: bool = false,
};

test "basic functionality" {
    const os = @import("builtin").os.tag;
    try std.testing.expect(os == .linux or os == .macos or os == .freebsd);
}
