// SPDX-License-Identifier: AGPL-3.0-or-later
//! Linux-specific FUSE implementation

const std = @import("std");
const c = @import("../c.zig");

pub fn mount(source: []const u8, target: []const u8, options: []const u8) !void {
    _ = source;
    _ = target;
    _ = options;
    // Use libfuse3 mount API
}

pub fn unmount(target: []const u8) !void {
    _ = target;
    // Use fusermount3 -u
}
