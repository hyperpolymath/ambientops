// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// capture_test.zig — Tests for safe diagnostic capture modules.
//
// Ported from capture_test.v (2026-04-17).

const std = @import("std");
const capture = @import("capture");

test "CaptureResult success" {
    const r = capture.CaptureResult{
        .name = "test_capture",
        .success = true,
        .output = "test output",
        .error_msg = "",
        .duration_ms = 100,
    };
    try std.testing.expect(r.success);
    try std.testing.expectEqualStrings("test output", r.output);
    try std.testing.expectEqual(@as(i64, 100), r.duration_ms);
}

test "CaptureResult failure" {
    const r = capture.CaptureResult{
        .name = "failed_capture",
        .success = false,
        .output = "",
        .error_msg = "Command not found",
        .duration_ms = 50,
    };
    try std.testing.expect(!r.success);
    try std.testing.expectEqualStrings("Command not found", r.error_msg);
}

test "CaptureModule creation" {
    const cmds = [_][]const u8{ "uname -a", "cat /etc/os-release" };
    const mod = capture.CaptureModule{
        .name = "os_version",
        .display_name = "OS Version",
        .commands = &cmds,
    };
    try std.testing.expectEqualStrings("os_version", mod.name);
    try std.testing.expectEqualStrings("OS Version", mod.display_name);
    try std.testing.expectEqual(@as(usize, 2), mod.commands.len);
}

test "redactPii leaves clean content unchanged" {
    const alloc = std.testing.allocator;
    const input = "normal log line with no sensitive data";
    const out = try capture.redactPii(alloc, input);
    defer alloc.free(out);
    try std.testing.expectEqualStrings(input, out);
}

test "redactPii removes token with secret key" {
    const alloc = std.testing.allocator;
    const out = try capture.redactPii(alloc, "token=abc123xyz");
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "abc123xyz") == null);
}

test "redactPii redacts GitHub token prefix" {
    const alloc = std.testing.allocator;
    const out = try capture.redactPii(alloc, "auth ghp_secretvalue");
    defer alloc.free(out);
    try std.testing.expect(std.mem.indexOf(u8, out, "ghp_secretvalue") == null);
}
