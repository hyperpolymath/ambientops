// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// handoff.zig — Handoff logic to specialized tools (psa, ambientops).
//
// Path validation prevents command injection (CRIT-001).
//
// Corresponds to: src/handoff.v

const std = @import("std");
const utils = @import("utils");
const incident = @import("incident");

// ── Path safety validation (CRIT-001) ────────────────────────────────────────

/// Returns true iff `path` contains only the characters that are safe to
/// interpolate directly into a shell argument (alphanumeric, -, _, ., /).
/// Also rejects empty paths and paths containing "..".
pub fn isPathSafe(path: []const u8) bool {
    if (path.len == 0) return false;
    if (std.mem.indexOf(u8, path, "..") != null) return false;

    for (path) |c| {
        const safe = std.ascii.isAlphanumeric(c) or
            c == '-' or c == '_' or c == '.' or c == '/';
        if (!safe) return false;
    }
    return true;
}

// ── Handoff ───────────────────────────────────────────────────────────────────

const HandoffTarget = struct {
    name: []const u8,
    command: []const u8,
    args: []const []const u8,
    description: []const u8,
};

/// Attempt to hand off the incident to the first available specialized tool.
pub fn handoff(
    allocator: std.mem.Allocator,
    inc: incident.Incident,
    config: incident.Config,
) void {
    handoffInner(allocator, inc, config) catch |e| {
        utils.eprint("\x1b[33m[WARN]\x1b[0m Handoff error: {s}\n", .{@errorName(e)});
    };
}

fn handoffInner(
    allocator: std.mem.Allocator,
    inc: incident.Incident,
    config: incident.Config,
) !void {
    // CRIT-001: validate incident path before shell interpolation.
    if (!isPathSafe(inc.path)) {
        utils.eprint(
            "\x1b[31m[ERROR]\x1b[0m Invalid incident path detected (possible injection attempt)\n",
            .{},
        );
        utils.eprint(
            "\x1b[33m[INFO]\x1b[0m Path must contain only alphanumeric, dash, underscore, dot, slash\n",
            .{},
        );
        utils.logError(allocator, inc.logs_path, "handoff", "Invalid incident path detected", &.{
            .{ .key = "path", .value = inc.path },
        });
        return;
    }

    // Build candidate targets (order = preference).
    const targets = [_]HandoffTarget{
        .{
            .name = "ambientops-clinician",
            .command = "ambientops-clinician",
            .args = &.{ "crisis", "--incident", inc.path, "--correlation-id", inc.correlation_id },
            .description = "AmbientOps Clinician crisis mode",
        },
        .{
            .name = "psa",
            .command = "psa",
            .args = &.{ "crisis", "--incident", inc.path, "--correlation-id", inc.correlation_id },
            .description = "Personal Sysadmin crisis mode (legacy)",
        },
        .{
            .name = "ambientops",
            .command = "ambientops",
            .args = &.{ "scan", "--incident", inc.path, "--correlation-id", inc.correlation_id },
            .description = "Advanced diagnostics (non-mutating)",
        },
    };

    const found: ?HandoffTarget = blk: {
        for (targets) |t| {
            if (toolExists(allocator, t.command)) {
                break :blk t;
            }
        }
        break :blk null;
    };

    if (found) |target| {
        utils.print("\x1b[34m[HANDOFF]\x1b[0m Found {s}: {s}\n\n", .{
            target.name, target.description,
        });

        // Build full command string for display.
        var cmd_buf = std.ArrayList(u8){};
        defer cmd_buf.deinit(allocator);
        try cmd_buf.appendSlice(allocator, target.command);
        for (target.args) |arg| {
            try cmd_buf.append(allocator, ' ');
            try cmd_buf.appendSlice(allocator, arg);
        }

        if (config.dry_run) {
            utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would execute: {s}\n", .{cmd_buf.items});
            return;
        }

        utils.print("\x1b[34m[INFO]\x1b[0m Launching: {s}\n\n", .{cmd_buf.items});
        try logHandoff(allocator, inc, target, config);
        spawnTool(allocator, target);
    } else {
        utils.print("\x1b[33m[INFO]\x1b[0m No specialized tools found (psa, ambientops)\n", .{});
        utils.print("\x1b[34m[INFO]\x1b[0m Incident bundle is ready for manual review\n\n", .{});
        utils.print("\x1b[36mSuggested next steps:\x1b[0m\n", .{});
        utils.print("  1. Review logs in: {s}\n", .{inc.logs_path});
        utils.print("  2. Install psa or ambientops for enhanced diagnostics\n", .{});
        utils.print("  3. Share the incident bundle for analysis\n", .{});
    }
}

fn toolExists(allocator: std.mem.Allocator, name: []const u8) bool {
    const cmd = if (@import("builtin").target.os.tag == .windows)
        std.fmt.allocPrint(allocator, "where {s} 2>nul", .{name}) catch return false
    else
        std.fmt.allocPrint(allocator, "command -v {s} 2>/dev/null", .{name}) catch return false;
    defer allocator.free(cmd);

    const r = utils.runShell(allocator, cmd) catch return false;
    defer allocator.free(r.stdout);
    defer allocator.free(r.stderr);
    return r.exit_code == 0;
}

fn spawnTool(allocator: std.mem.Allocator, target: HandoffTarget) void {
    var argv = std.ArrayList([]const u8){};
    defer argv.deinit(allocator);

    argv.append(allocator, target.command) catch return;
    for (target.args) |a| argv.append(allocator, a) catch return;

    const result = utils.runCommand(allocator, argv.items) catch return;
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.exit_code != 0) {
        utils.eprint("\x1b[33m[WARN]\x1b[0m {s} exited with code {d}\n", .{
            target.name, result.exit_code,
        });
    }
}

fn logHandoff(
    allocator: std.mem.Allocator,
    inc: incident.Incident,
    target: HandoffTarget,
    config: incident.Config,
) !void {
    if (config.dry_run) return;

    const log_path = try std.fs.path.join(allocator, &.{ inc.logs_path, "handoff.log" });
    defer allocator.free(log_path);

    var args_buf = std.ArrayList(u8){};
    defer args_buf.deinit(allocator);
    for (target.args, 0..) |a, i| {
        if (i > 0) try args_buf.append(allocator, ' ');
        try args_buf.appendSlice(allocator, a);
    }

    const content = try std.fmt.allocPrint(
        allocator,
        "schema_version: {s}\n\nHandoff to: {s}\nCommand: {s} {s}\nDescription: {s}\n",
        .{
            utils.SCHEMA_VERSION,
            target.name,
            target.command,
            args_buf.items,
            target.description,
        },
    );
    defer allocator.free(content);

    try utils.atomicWriteFile(allocator, log_path, content);
}
