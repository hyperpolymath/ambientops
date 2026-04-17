// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// incident_test.zig — Tests for incident bundle creation and management.
//
// Ported from incident_test.v (2026-04-17).

const std = @import("std");
const incident_mod = @import("incident");
const utils = @import("utils");

test "incident envelope has required fields" {
    const env = incident_mod.IncidentEnvelope{
        .schema_version = utils.schema_version,
        .id = "incident-test-123",
        .correlation_id = "corr-12345678",
        .created_at = "2026-04-17T10:00:00.000Z",
        .hostname = "test-host",
        .username = "test-user",
        .working_dir = "/tmp",
        .platform = .{ .os = "Linux", .arch = "x86_64", .kernel = "6.0.0" },
        .trigger = .{ .version = "0.1.0", .dry_run = false, .args = "trigger" },
        .commands = &.{},
    };

    try std.testing.expectEqualStrings(utils.schema_version, env.schema_version);
    try std.testing.expect(std.mem.startsWith(u8, env.id, "incident-"));
    try std.testing.expect(env.hostname.len > 0);
    try std.testing.expect(env.platform.os.len > 0);
}

test "platform info fields" {
    const info = incident_mod.PlatformInfo{
        .os = "Linux",
        .arch = "x86_64",
        .kernel = "6.0.0-test",
    };
    try std.testing.expectEqualStrings("Linux", info.os);
    try std.testing.expectEqualStrings("x86_64", info.arch);
    try std.testing.expectEqualStrings("6.0.0-test", info.kernel);
}

test "trigger info dry run flag" {
    const trigger = incident_mod.TriggerInfo{
        .version = "0.1.0",
        .dry_run = true,
        .args = "trigger --dry-run",
    };
    try std.testing.expect(trigger.dry_run);
    try std.testing.expect(std.mem.indexOf(u8, trigger.args, "--dry-run") != null);
}

test "command log creation" {
    const log = incident_mod.CommandLog{
        .name = "test_command",
        .command = "echo hello",
        .started_at = "2026-01-02T20:00:00.000Z",
        .ended_at = "2026-01-02T20:00:01.000Z",
        .exit_code = 0,
        .output_len = 6,
    };
    try std.testing.expectEqualStrings("test_command", log.name);
    try std.testing.expectEqual(@as(i32, 0), log.exit_code);
    try std.testing.expectEqual(@as(usize, 6), log.output_len);
}

test "incident id format starts with incident-" {
    const alloc = std.testing.allocator;
    const config = incident_mod.Config{ .dry_run = true };
    var inc = try incident_mod.createIncidentBundle(alloc, config);
    defer inc.deinit();
    try std.testing.expect(std.mem.startsWith(u8, inc.id, "incident-"));
    try std.testing.expect(inc.id.len > 9);
}

test "dry run config flags" {
    const config = incident_mod.Config{
        .quick_backup_dest = "",
        .dry_run = true,
        .verbose = false,
    };
    try std.testing.expect(config.dry_run);
    try std.testing.expect(!config.verbose);
    try std.testing.expectEqual(@as(usize, 0), config.quick_backup_dest.len);
}

test "correlation id format is 13 chars starting with corr-" {
    const alloc = std.testing.allocator;
    const config = incident_mod.Config{ .dry_run = true };
    var inc = try incident_mod.createIncidentBundle(alloc, config);
    defer inc.deinit();
    try std.testing.expect(std.mem.startsWith(u8, inc.correlation_id, "corr-"));
    try std.testing.expectEqual(@as(usize, 13), inc.correlation_id.len);
}

test "incident struct command list starts empty" {
    const alloc = std.testing.allocator;
    const config = incident_mod.Config{ .dry_run = true };
    var inc = try incident_mod.createIncidentBundle(alloc, config);
    defer inc.deinit();
    try std.testing.expectEqual(@as(usize, 0), inc.commands.items.len);
}
