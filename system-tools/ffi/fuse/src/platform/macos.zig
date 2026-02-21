// SPDX-License-Identifier: AGPL-3.0-or-later
//! macOS-specific FUSE implementation (macFUSE)

const std = @import("std");

pub fn mount(source: []const u8, target: []const u8, options: []const u8) !void {
    _ = source;
    _ = target;
    _ = options;
    // Use macFUSE mount API
}

pub fn unmount(target: []const u8) !void {
    _ = target;
    // Use umount
}
