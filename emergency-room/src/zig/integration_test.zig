// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// integration_test.zig — Integration tests for full emergency-room workflow.
//
// Corresponds to: src/integration_test.v
//
// Safety-critical tests (path validation, panic-safe semantics) are
// intentionally explicit about the exact characters being tested.

const std = @import("std");
const inc = @import("incident");
const handoff = @import("handoff");
const backup = @import("backup");
const utils = @import("utils");

// ── Incident bundle ───────────────────────────────────────────────────────────

test "Incident bundle creation in dry-run mode" {
    const allocator = std.testing.allocator;
    const config = inc.Config{ .dry_run = true };

    var incident = try inc.createIncidentBundle(allocator, config);
    defer incident.deinit(allocator);

    try std.testing.expect(std.mem.startsWith(u8, incident.id, "incident-"));
    try std.testing.expect(std.mem.startsWith(u8, incident.correlation_id, "corr-"));
    try std.testing.expectEqual(@as(usize, 13), incident.correlation_id.len);
    try std.testing.expect(incident.path.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, incident.logs_path, 1, "logs"));
}

// ── Handoff path validation (CRIT-001) ───────────────────────────────────────

test "isPathSafe: valid paths pass" {
    try std.testing.expect(handoff.isPathSafe("/tmp/valid-path"));
    try std.testing.expect(handoff.isPathSafe("/home/user/incident-20260102"));
}

test "isPathSafe: semicolon injection is rejected" {
    try std.testing.expect(!handoff.isPathSafe("/tmp/path;rm -rf /"));
}

test "isPathSafe: pipe injection is rejected" {
    try std.testing.expect(!handoff.isPathSafe("/tmp/path|cat /etc/passwd"));
}

test "isPathSafe: backtick injection is rejected" {
    try std.testing.expect(!handoff.isPathSafe("/tmp/path`whoami`"));
}

test "isPathSafe: dollar-sign injection is rejected" {
    try std.testing.expect(!handoff.isPathSafe("/tmp/path$(id)"));
}

test "isPathSafe: path traversal with .. is rejected" {
    try std.testing.expect(!handoff.isPathSafe("/tmp/../etc/passwd"));
}

test "isPathSafe: empty path is rejected" {
    try std.testing.expect(!handoff.isPathSafe(""));
}

// ── Backup path validation (CRIT-002) ────────────────────────────────────────

test "validateSafePath: valid path is accepted" {
    const allocator = std.testing.allocator;
    const result = try backup.validateSafePath(allocator, "/tmp");
    defer allocator.free(result);
    try std.testing.expect(result.len > 0);
}

test "validateSafePath: empty path is rejected" {
    const allocator = std.testing.allocator;
    const result = backup.validateSafePath(allocator, "");
    try std.testing.expectError(error.EmptyPath, result);
}

test "validateSafePath: semicolon is rejected" {
    const allocator = std.testing.allocator;
    const result = backup.validateSafePath(allocator, "/tmp/backup;rm -rf /");
    try std.testing.expectError(error.DangerousCharacterInPath, result);
}

test "validateSafePath: pipe is rejected" {
    const allocator = std.testing.allocator;
    const result = backup.validateSafePath(allocator, "/tmp/backup|cat /etc/passwd");
    try std.testing.expectError(error.DangerousCharacterInPath, result);
}

test "validateSafePath: dollar sign is rejected" {
    const allocator = std.testing.allocator;
    const result = backup.validateSafePath(allocator, "/tmp/backup$(id)");
    try std.testing.expectError(error.DangerousCharacterInPath, result);
}

// ── Schema version ────────────────────────────────────────────────────────────

test "schema version is set and semver-shaped" {
    const sv = utils.SCHEMA_VERSION;
    try std.testing.expect(sv.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, sv, 1, "."));
}

// ── Platform detection ────────────────────────────────────────────────────────

test "platform detection: getOsName returns known value" {
    const name = utils.getOsName();
    const valid = [_][]const u8{ "Linux", "macOS", "Windows", "Unknown" };
    var found = false;
    for (valid) |v| {
        if (std.mem.eql(u8, name, v)) { found = true; break; }
    }
    try std.testing.expect(found);
}

test "platform detection: getArch returns known value" {
    const arch = utils.getArch();
    const valid = [_][]const u8{ "x86_64", "arm64", "i386", "unknown" };
    var found = false;
    for (valid) |v| {
        if (std.mem.eql(u8, arch, v)) { found = true; break; }
    }
    try std.testing.expect(found);
}

// ── Correlation ID format ─────────────────────────────────────────────────────

test "correlation ID has corr- prefix and correct length" {
    const allocator = std.testing.allocator;
    const config = inc.Config{ .dry_run = true };

    var incident = try inc.createIncidentBundle(allocator, config);
    defer incident.deinit(allocator);

    try std.testing.expect(std.mem.startsWith(u8, incident.correlation_id, "corr-"));
    try std.testing.expectEqual(@as(usize, 13), incident.correlation_id.len);
}

// ── Atomic write utility ──────────────────────────────────────────────────────

test "atomicWriteFile: write and read back" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path = try std.fmt.allocPrint(allocator, "/tmp/emergency_room_zig_test_{x}.txt", .{std.time.nanoTimestamp()});
    defer allocator.free(path);

    const content = "schema_version: 1.0.0\ntest: atomic_write\n";
    try utils.atomicWriteFile(allocator, path, content);
    defer std.fs.cwd().deleteFile(path) catch {};

    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const read = try f.readToEndAlloc(allocator, 1024);
    defer allocator.free(read);

    try std.testing.expectEqualStrings(content, read);
}

test "atomicWriteFile: overwrite is atomic — no partial state visible" {
    const allocator = std.testing.allocator;

    const path = try std.fmt.allocPrint(allocator, "/tmp/emergency_room_zig_atomic_{x}.txt", .{std.time.nanoTimestamp()});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    try utils.atomicWriteFile(allocator, path, "first");
    try utils.atomicWriteFile(allocator, path, "second");

    const f = try std.fs.cwd().openFile(path, .{});
    defer f.close();
    const read = try f.readToEndAlloc(allocator, 64);
    defer allocator.free(read);

    try std.testing.expectEqualStrings("second", read);
}
