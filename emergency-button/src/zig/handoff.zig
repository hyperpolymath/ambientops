// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// handoff.zig — Handoff to specialized tools (psa, big-up).
//
// Ported from handoff.v (2026-04-17).
//
// CRIT-001: Path validation prevents shell-injection via incident.path.
// COULD-001: Correlation ID forwarded to downstream tools.
// HIGH-006: Log writes go through atomicWriteFile.

const std = @import("std");
const utils = @import("utils");
const incident_mod = @import("incident");

pub const HandoffTarget = struct {
    name: []const u8,
    command: []const u8,
    /// Arguments passed to the tool, in order.
    args: []const []const u8,
    description: []const u8,
};

// =============================================================================
// Path safety
// =============================================================================

/// CRIT-001: Returns true only when every character is alphanumeric, dash,
/// underscore, dot, or forward-slash, and the path contains no `..` traversal.
pub fn isPathSafe(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;
    for (path) |c| {
        const ok = std.ascii.isAlphanumeric(c) or
            c == '-' or c == '_' or c == '.' or c == '/';
        if (!ok) return false;
    }
    return true;
}

// =============================================================================
// Tool discovery
// =============================================================================

/// Check whether `name` resolves in PATH (platform-aware).
fn toolExists(allocator: std.mem.Allocator, name: []const u8) bool {
    const argv: []const []const u8 = switch (@import("builtin").os.tag) {
        .windows => &.{ "where", name },
        else => &.{ "command", "-v", name },
    };

    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    }) catch return false;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    return result.term == .Exited and result.term.Exited == 0;
}

// =============================================================================
// Public API
// =============================================================================

/// Attempt to hand off to a specialized tool (psa, then big-up).
/// Logs the attempt to `logs/handoff.log` and spawns the tool synchronously.
pub fn handoff(
    allocator: std.mem.Allocator,
    incident: *const incident_mod.Incident,
    config: incident_mod.Config,
) void {
    // CRIT-001: Validate incident path.
    if (!isPathSafe(incident.path)) {
        const red = "\x1b[31m";
        const yellow = "\x1b[33m";
        const reset = "\x1b[0m";
        std.debug.print(
            "{s}[ERROR]{s} Invalid incident path detected (possible injection attempt)\n",
            .{ red, reset },
        );
        std.debug.print(
            "{s}[INFO]{s} Path must contain only alphanumeric, dash, underscore, dot, slash\n",
            .{ yellow, reset },
        );
        utils.logError(allocator, incident.logs_path, "handoff", "Invalid incident path", &.{
            .{ .key = "path", .value = incident.path },
        });
        return;
    }

    // Build target list; args slices are stack-allocated here.
    const psa_args = [_][]const u8{
        "crisis",
        "--incident",
        incident.path,
        "--correlation-id",
        incident.correlation_id,
    };
    const bigup_args = [_][]const u8{
        "scan",
        "--incident",
        incident.path,
        "--correlation-id",
        incident.correlation_id,
    };

    const targets = [_]HandoffTarget{
        .{
            .name = "psa",
            .command = "psa",
            .args = &psa_args,
            .description = "Personal Sysadmin crisis mode",
        },
        .{
            .name = "big-up",
            .command = "big-up",
            .args = &bigup_args,
            .description = "Advanced diagnostics (non-mutating)",
        },
    };

    var found: ?HandoffTarget = null;
    for (targets) |target| {
        if (toolExists(allocator, target.command)) {
            found = target;
            break;
        }
    }

    if (found) |target| {
        const blue = "\x1b[34m";
        const reset = "\x1b[0m";
        const cyan = "\x1b[36m";
        const yellow = "\x1b[33m";

        std.debug.print(
            "{s}[HANDOFF]{s} Found {s}: {s}\n",
            .{ blue, reset, target.name, target.description },
        );
        std.debug.print("\n", .{});

        if (config.dry_run) {
            var argv_str = std.ArrayList(u8).empty;
            defer argv_str.deinit(allocator);
            argv_str.appendSlice(allocator, target.command) catch {};
            for (target.args) |arg| {
                argv_str.append(allocator, ' ') catch {};
                argv_str.appendSlice(allocator, arg) catch {};
            }
            std.debug.print(
                "{s}[DRY-RUN]{s} Would execute: {s}\n",
                .{ cyan, reset, argv_str.items },
            );
            return;
        }

        logHandoff(allocator, incident, target, config);
        spawnTool(allocator, target, yellow, reset);
    } else {
        const yellow = "\x1b[33m";
        const blue = "\x1b[34m";
        const cyan = "\x1b[36m";
        const reset = "\x1b[0m";
        std.debug.print(
            "{s}[INFO]{s} No specialized tools found (psa, big-up)\n",
            .{ yellow, reset },
        );
        std.debug.print(
            "{s}[INFO]{s} Incident bundle is ready for manual review\n",
            .{ blue, reset },
        );
        std.debug.print("\n", .{});
        std.debug.print("{s}Suggested next steps:{s}\n", .{ cyan, reset });
        std.debug.print("  1. Review logs in: {s}\n", .{incident.logs_path});
        std.debug.print("  2. Install psa or big-up for enhanced diagnostics\n", .{});
        std.debug.print("  3. Share the incident bundle for analysis\n", .{});
    }
}

fn spawnTool(
    allocator: std.mem.Allocator,
    target: HandoffTarget,
    yellow: []const u8,
    reset: []const u8,
) void {
    // Build argv: [command, ...args].
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    argv.append(allocator, target.command) catch return;
    for (target.args) |arg| argv.append(allocator, arg) catch return;

    // Run synchronously.
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv.items,
    }) catch return;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term == .Exited and result.term.Exited != 0) {
        std.debug.print(
            "{s}[WARN]{s} {s} exited with code {d}\n",
            .{ yellow, reset, target.name, result.term.Exited },
        );
    }
}

fn logHandoff(
    allocator: std.mem.Allocator,
    incident: *const incident_mod.Incident,
    target: HandoffTarget,
    config: incident_mod.Config,
) void {
    if (config.dry_run) return;

    const log_path = std.fs.path.join(
        allocator,
        &.{ incident.logs_path, "handoff.log" },
    ) catch return;
    defer allocator.free(log_path);

    var args_str = std.ArrayList(u8).empty;
    defer args_str.deinit(allocator);
    for (target.args, 0..) |arg, i| {
        if (i != 0) args_str.append(allocator, ' ') catch {};
        args_str.appendSlice(allocator, arg) catch {};
    }

    const content = std.fmt.allocPrint(
        allocator,
        "schema_version: {s}\n\nHandoff to: {s}\nCommand: {s} {s}\nDescription: {s}\n",
        .{
            utils.schema_version,
            target.name,
            target.command,
            args_str.items,
            target.description,
        },
    ) catch return;
    defer allocator.free(content);

    utils.atomicWriteFile(allocator, log_path, content) catch |err| {
        std.debug.print("\x1b[33m[WARN]\x1b[0m Could not write handoff log: {}\n", .{err});
    };
}

// =============================================================================
// Tests
// =============================================================================

test "isPathSafe accepts safe paths" {
    try std.testing.expect(isPathSafe("/tmp/valid-path"));
    try std.testing.expect(isPathSafe("/home/user/incident-20260102"));
}

test "isPathSafe rejects dangerous paths" {
    try std.testing.expect(!isPathSafe("/tmp/path;rm -rf /"));
    try std.testing.expect(!isPathSafe("/tmp/path|cat /etc/passwd"));
    try std.testing.expect(!isPathSafe("/tmp/path`whoami`"));
    try std.testing.expect(!isPathSafe("/tmp/path$(id)"));
}

test "isPathSafe rejects path traversal and empty" {
    try std.testing.expect(!isPathSafe("/tmp/../etc/passwd"));
    try std.testing.expect(!isPathSafe(""));
}
