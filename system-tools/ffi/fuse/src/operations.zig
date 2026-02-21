// SPDX-License-Identifier: AGPL-3.0-or-later
//! FUSE operations implementation

const std = @import("std");
const c = @import("c.zig");
const FileSystem = @import("filesystem.zig").FileSystem;

/// Convert FileSystem to fuse_operations
pub const Operations = struct {
    fs: FileSystem,

    pub fn toFuseOps(self: *Operations) c.fuse_operations {
        _ = self;
        // TODO: Fill in C callbacks that delegate to Zig FileSystem
        return std.mem.zeroes(c.fuse_operations);
    }
};
