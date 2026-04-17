// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// incident_test.zig — Tests for incident bundle types and creation.
//
// Corresponds to: src/incident_test.v

const std = @import("std");
const inc = @import("incident");
const utils = @import("utils");

test "Config struct has expected default values" {
    const config = inc.Config{};
    try std.testing.expect(config.dry_run == false);
    try std.testing.expect(config.verbose == false);
    try std.testing.expect(config.envelope == false);
    try std.testing.expectEqualStrings("", config.quick_backup_dest);
}

test "Config dry_run flag" {
    const config = inc.Config{ .dry_run = true };
    try std.testing.expect(config.dry_run == true);
    try std.testing.expect(config.verbose == false);
}

test "CommandLog fields are accessible" {
    const log = inc.CommandLog{
        .name = "test_command",
        .command = "echo hello",
        .started_at = "2026-01-02T20:00:00Z",
        .ended_at = "2026-01-02T20:00:01Z",
        .exit_code = 0,
        .output_len = 6,
    };
    try std.testing.expectEqualStrings("test_command", log.name);
    try std.testing.expectEqual(@as(i32, 0), log.exit_code);
    try std.testing.expectEqual(@as(usize, 6), log.output_len);
}

test "getOsName returns known value" {
    const name = utils.getOsName();
    const valid = [_][]const u8{ "Linux", "macOS", "Windows", "Unknown" };
    var found = false;
    for (valid) |v| {
        if (std.mem.eql(u8, name, v)) { found = true; break; }
    }
    try std.testing.expect(found);
}

test "getArch returns known value" {
    const arch = utils.getArch();
    const valid = [_][]const u8{ "x86_64", "arm64", "i386", "unknown" };
    var found = false;
    for (valid) |v| {
        if (std.mem.eql(u8, arch, v)) { found = true; break; }
    }
    try std.testing.expect(found);
}

test "rfc3339Now produces a plausible timestamp" {
    const allocator = std.testing.allocator;
    const ts = try utils.rfc3339Now(allocator);
    defer allocator.free(ts);
    // Must be at least "2026-…T…Z" (20 chars minimum).
    try std.testing.expect(ts.len >= 20);
    try std.testing.expect(ts[4] == '-');
    try std.testing.expect(ts[10] == 'T');
    try std.testing.expect(ts[ts.len - 1] == 'Z');
}

test "randomHex produces correct length" {
    const allocator = std.testing.allocator;
    const h4 = try utils.randomHex(allocator, 4); // 4 bytes = 8 hex chars
    defer allocator.free(h4);
    try std.testing.expectEqual(@as(usize, 8), h4.len);

    const h8 = try utils.randomHex(allocator, 4); // re-test
    defer allocator.free(h8);
    try std.testing.expectEqual(@as(usize, 8), h8.len);
}

test "SCHEMA_VERSION is set and semver-shaped" {
    const sv = utils.SCHEMA_VERSION;
    try std.testing.expect(sv.len > 0);
    try std.testing.expect(std.mem.containsAtLeast(u8, sv, 1, "."));
}

test "Incident createIncidentBundle dry_run does not create directories" {
    const allocator = std.testing.allocator;
    const config = inc.Config{ .dry_run = true };

    var incident = try inc.createIncidentBundle(allocator, config);
    defer incident.deinit(allocator);

    try std.testing.expect(std.mem.startsWith(u8, incident.id, "incident-"));
    try std.testing.expect(std.mem.startsWith(u8, incident.correlation_id, "corr-"));
    // Correlation ID must be "corr-" (5) + 8 hex chars = 13 chars.
    try std.testing.expectEqual(@as(usize, 13), incident.correlation_id.len);
    try std.testing.expect(incident.path.len > 0);
    try std.testing.expect(std.mem.endsWith(u8, incident.logs_path, "logs"));
    // Dry-run: directory must NOT have been created.
    try std.testing.expect(std.fs.cwd().statFile(incident.path) catch null == null);
}

test "Incident correlation_id format" {
    const allocator = std.testing.allocator;
    const config = inc.Config{ .dry_run = true };

    var incident = try inc.createIncidentBundle(allocator, config);
    defer incident.deinit(allocator);

    try std.testing.expect(std.mem.startsWith(u8, incident.correlation_id, "corr-"));
    try std.testing.expectEqual(@as(usize, 13), incident.correlation_id.len);
}
