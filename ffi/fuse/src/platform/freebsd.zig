// SPDX-License-Identifier: MPL-2.0
//! FreeBSD-specific FUSE implementation (fusefs)

const std = @import("std");

pub fn mount(source: []const u8, target: []const u8, options: []const u8) !void {
    _ = source;
    _ = target;
    _ = options;
    // Use fusefs mount API
}

pub fn unmount(target: []const u8) !void {
    _ = target;
    // Use umount
}
