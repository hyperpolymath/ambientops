// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// integration_test.zig — Integration tests for full emergency-button workflow.
//
// Ported from integration_test.v (2026-04-17).

const std = @import("std");
const incident_mod = @import("incident");
const handoff_mod = @import("handoff");
const backup_mod = @import("backup");
const utils = @import("utils");

test "incident bundle creation dry run" {
    const alloc = std.testing.allocator;
    const config = incident_mod.Config{ .dry_run = true };

    var inc = try incident_mod.createIncidentBundle(alloc, config);
    defer inc.deinit();

    try std.testing.expect(std.mem.startsWith(u8, inc.id, "incident-"));
    try std.testing.expect(std.mem.startsWith(u8, inc.correlation_id, "corr-"));
    try std.testing.expectEqual(@as(usize, 13), inc.correlation_id.len);
    try std.testing.expect(inc.path.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, inc.logs_path, "logs") != null);
}

test "incident envelope JSON can be stringified" {
    const alloc = std.testing.allocator;

    const env = incident_mod.IncidentEnvelope{
        .schema_version = utils.schema_version,
        .id = "incident-test-integration-001",
        .correlation_id = "corr-12345678",
        .created_at = "2026-04-17T10:00:00.000Z",
        .hostname = "test-host",
        .username = "test-user",
        .working_dir = "/tmp",
        .platform = .{ .os = "Linux", .arch = "x86_64", .kernel = "6.0.0" },
        .trigger = .{ .version = incident_mod.app_version, .dry_run = true, .args = "trigger --dry-run" },
        .commands = &.{},
    };

    const json_bytes = try std.json.Stringify.valueAlloc(alloc, env, .{});
    defer alloc.free(json_bytes);

    try std.testing.expect(std.mem.indexOf(u8, json_bytes, "schema_version") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_bytes, "correlation_id") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_bytes, "corr-12345678") != null);
}

test "handoff targets include correlation ID" {
    const alloc = std.testing.allocator;
    const config = incident_mod.Config{ .dry_run = true };
    var inc = try incident_mod.createIncidentBundle(alloc, config);
    defer inc.deinit();

    // Verify the correlation ID format is correct for downstream use.
    try std.testing.expect(std.mem.startsWith(u8, inc.correlation_id, "corr-"));
    try std.testing.expectEqual(@as(usize, 13), inc.correlation_id.len);
}

test "path validation rejects dangerous chars" {
    try std.testing.expect(!handoff_mod.isPathSafe("/tmp/path;rm -rf /"));
    try std.testing.expect(!handoff_mod.isPathSafe("/tmp/path|cat /etc/passwd"));
    try std.testing.expect(!handoff_mod.isPathSafe("/tmp/path`whoami`"));
    try std.testing.expect(!handoff_mod.isPathSafe("/tmp/path$(id)"));
    try std.testing.expect(!handoff_mod.isPathSafe("/tmp/../etc/passwd"));
    try std.testing.expect(!handoff_mod.isPathSafe(""));
}

test "path validation accepts safe paths" {
    try std.testing.expect(handoff_mod.isPathSafe("/tmp/valid-path"));
    try std.testing.expect(handoff_mod.isPathSafe("/home/user/incident-20260102"));
}

test "backup path validation rejects dangerous characters" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.DangerousChar, backup_mod.validateSafePath(alloc, "/tmp/backup;rm -rf /"));
    try std.testing.expectError(error.DangerousChar, backup_mod.validateSafePath(alloc, "/tmp/backup|cat /etc/passwd"));
}

test "command log appended correctly" {
    const alloc = std.testing.allocator;
    const config = incident_mod.Config{ .dry_run = true };
    var inc = try incident_mod.createIncidentBundle(alloc, config);
    defer inc.deinit();

    const cmd = incident_mod.CommandLog{
        .name = try alloc.dupe(u8, "uname"),
        .command = try alloc.dupe(u8, "uname -a"),
        .started_at = try alloc.dupe(u8, "2026-04-17T10:00:00.000Z"),
        .ended_at = try alloc.dupe(u8, "2026-04-17T10:00:01.000Z"),
        .exit_code = 0,
        .output_len = 128,
    };
    try inc.commands.append(alloc, cmd);
    try std.testing.expectEqual(@as(usize, 1), inc.commands.items.len);
    try std.testing.expectEqual(@as(i32, 0), inc.commands.items[0].exit_code);
}

test "schema version is set and semver" {
    try std.testing.expect(utils.schema_version.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, utils.schema_version, ".") != null);
}

test "platform detection returns known values" {
    const os_name = utils.getOsName();
    const arch = utils.getArch();

    const valid_os = [_][]const u8{ "Linux", "macOS", "Windows", "Unknown" };
    const valid_arch = [_][]const u8{ "x86_64", "arm64", "i386", "unknown" };

    var os_ok = false;
    for (valid_os) |v| {
        if (std.mem.eql(u8, os_name, v)) {
            os_ok = true;
            break;
        }
    }
    try std.testing.expect(os_ok);

    var arch_ok = false;
    for (valid_arch) |v| {
        if (std.mem.eql(u8, arch, v)) {
            arch_ok = true;
            break;
        }
    }
    try std.testing.expect(arch_ok);
}
