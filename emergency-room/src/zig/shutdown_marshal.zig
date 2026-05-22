// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// shutdown_marshal.zig — Graceful shutdown orchestration.
//
// Addresses CC-002 (unsafe shutdowns).
//
// The Shutdown Marshal coordinates system shutdown to ensure:
//  1. All AmbientOps components are notified and can flush state.
//  2. Evidence envelopes are finalised before power loss.
//  3. Shutdown reason is recorded for post-mortem analysis.
//  4. Ungraceful shutdowns are detected on the next boot.
//
// State is persisted atomically to disk (HIGH-006) so the next boot can
// detect an incomplete shutdown.
//
// Corresponds to: src/shutdown_marshal.v

const std = @import("std");
const utils = @import("utils");
const incident = @import("incident");

// ── Configuration ─────────────────────────────────────────────────────────────

pub const DEFAULT_SHUTDOWN_STATE_PATH: []const u8 =
    "/var/lib/ambientops/shutdown-marshal/state.json";
pub const DEFAULT_GRACE_PERIOD_SECS: u32 = 30;
pub const DEFAULT_NOTIFY_COMPONENTS = [_][]const u8{
    "observatory",
    "clinician",
    "session-sentinel",
};

// ── Types ─────────────────────────────────────────────────────────────────────

pub const ShutdownReason = enum {
    user_initiated,
    scheduled,
    emergency,
    kernel_panic,
    power_loss,
    unknown,

    pub fn toString(self: ShutdownReason) []const u8 {
        return switch (self) {
            .user_initiated => "user_initiated",
            .scheduled => "scheduled",
            .emergency => "emergency",
            .kernel_panic => "kernel_panic",
            .power_loss => "power_loss",
            .unknown => "unknown",
        };
    }

    pub fn fromString(s: []const u8) ShutdownReason {
        if (std.mem.eql(u8, s, "user") or std.mem.eql(u8, s, "user_initiated")) return .user_initiated;
        if (std.mem.eql(u8, s, "scheduled")) return .scheduled;
        if (std.mem.eql(u8, s, "emergency")) return .emergency;
        if (std.mem.eql(u8, s, "panic") or std.mem.eql(u8, s, "kernel_panic")) return .kernel_panic;
        if (std.mem.eql(u8, s, "power") or std.mem.eql(u8, s, "power_loss")) return .power_loss;
        return .unknown;
    }
};

pub const ShutdownState = struct {
    schema_version: []const u8,
    last_clean_shutdown: []const u8,
    shutdown_in_progress: bool,
    shutdown_reason: []const u8,
    notified_components: std.ArrayList([]const u8),
    pending_flushes: std.ArrayList([]const u8),
    ungraceful_count: i32,

    pub fn deinit(self: *ShutdownState, allocator: std.mem.Allocator) void {
        allocator.free(self.last_clean_shutdown);
        allocator.free(self.shutdown_reason);
        for (self.notified_components.items) |c| allocator.free(c);
        self.notified_components.deinit(allocator);
        for (self.pending_flushes.items) |f| allocator.free(f);
        self.pending_flushes.deinit(allocator);
    }
};

pub const ShutdownAction = struct {
    name: []const u8,
    description: []const u8,
    command: []const u8,
    timeout_ms: u32,
    critical: bool,
};

pub const ShutdownPlan = struct {
    reason: ShutdownReason,
    grace_period_secs: u32,
    components: []const []const u8,
    actions: []const ShutdownAction,
};

pub const ShutdownActionResult = struct {
    name: []const u8,
    success: bool,
    duration_ms: i64,
    error_msg: []const u8,
};

pub const ShutdownReport = struct {
    schema_version: []const u8,
    initiated_at: []const u8,
    completed_at: []const u8,
    reason: []const u8,
    success: bool,
    actions_taken: std.ArrayList(ShutdownActionResult),
    components_notified: std.ArrayList([]const u8),

    pub fn deinit(self: *ShutdownReport, allocator: std.mem.Allocator) void {
        allocator.free(self.initiated_at);
        allocator.free(self.completed_at);
        for (self.actions_taken.items) |r| {
            allocator.free(r.name);
            allocator.free(r.error_msg);
        }
        self.actions_taken.deinit(allocator);
        for (self.components_notified.items) |c| allocator.free(c);
        self.components_notified.deinit(allocator);
    }
};

// ── Core functions ────────────────────────────────────────────────────────────

/// Check persisted state and detect ungraceful previous shutdown.
pub fn checkLastShutdown(
    allocator: std.mem.Allocator,
    state_path: []const u8,
) !ShutdownState {
    var state = try loadShutdownState(allocator, state_path);
    if (state.shutdown_in_progress) {
        // The flag was never cleared — ungraceful shutdown detected.
        state.ungraceful_count += 1;
        state.shutdown_in_progress = false;
    }
    return state;
}

/// Build a shutdown plan for the given reason.
pub fn prepareShutdown(
    allocator: std.mem.Allocator,
    reason: ShutdownReason,
    grace_period: u32,
) !ShutdownPlan {
    var actions = std.ArrayList(ShutdownAction){};

    try actions.append(allocator, ShutdownAction{
        .name = "flush-state",
        .description = "Flush .machine_readable state files",
        .command = "sync",
        .timeout_ms = 5000,
        .critical = false,
    });

    try actions.append(allocator, ShutdownAction{
        .name = "stop-sentinel",
        .description = "Stop session-sentinel gracefully",
        .command = "systemctl --user stop session-sentinel.service 2>/dev/null || true",
        .timeout_ms = 10000,
        .critical = false,
    });

    try actions.append(allocator, ShutdownAction{
        .name = "filesystem-sync",
        .description = "Force filesystem sync",
        .command = "sync",
        .timeout_ms = 15000,
        .critical = true,
    });

    if (reason == .emergency or reason == .kernel_panic) {
        try actions.append(allocator, ShutdownAction{
            .name = "emergency-snapshot",
            .description = "Capture minimal emergency snapshot",
            .command = "journalctl -b --no-pager -n 100 > /tmp/ambientops-emergency-snapshot.log 2>/dev/null || true",
            .timeout_ms = 5000,
            .critical = false,
        });
    }

    return ShutdownPlan{
        .reason = reason,
        .grace_period_secs = grace_period,
        .components = &DEFAULT_NOTIFY_COMPONENTS,
        .actions = try actions.toOwnedSlice(allocator),
    };
}

/// Execute the shutdown plan and return a report.
pub fn executeShutdown(
    allocator: std.mem.Allocator,
    plan: ShutdownPlan,
    state_path: []const u8,
    dry_run: bool,
) !ShutdownReport {
    const initiated_at = try utils.rfc3339Now(allocator);
    errdefer allocator.free(initiated_at);

    // Mark shutdown in progress.
    if (!dry_run) {
        var state = try loadShutdownState(allocator, state_path);
        defer state.deinit(allocator);
        state.shutdown_in_progress = true;
        allocator.free(state.shutdown_reason);
        state.shutdown_reason = try allocator.dupe(u8, plan.reason.toString());
        saveShutdownState(allocator, state_path, state) catch |e| {
            utils.eprint("\x1b[33m[WARN]\x1b[0m Could not persist shutdown state: {s}\n", .{@errorName(e)});
        };
    }

    var results = std.ArrayList(ShutdownActionResult){};
    errdefer {
        for (results.items) |r| {
            allocator.free(r.name);
            allocator.free(r.error_msg);
        }
        results.deinit(allocator);
    }

    var all_success = true;

    // Notify components.
    var notified = std.ArrayList([]const u8){};
    errdefer {
        for (notified.items) |c| allocator.free(c);
        notified.deinit(allocator);
    }

    for (plan.components) |component| {
        if (dry_run) {
            utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would notify: {s}\n", .{component});
            try notified.append(allocator, try allocator.dupe(u8, component));
            continue;
        }
        const cmd = try std.fmt.allocPrint(
            allocator,
            "systemctl --user kill -s SIGTERM {s}.service 2>/dev/null",
            .{component},
        );
        defer allocator.free(cmd);

        const r = utils.runShell(allocator, cmd) catch continue;
        defer allocator.free(r.stdout);
        defer allocator.free(r.stderr);

        if (r.exit_code == 0) {
            try notified.append(allocator, try allocator.dupe(u8, component));
            utils.print("\x1b[32m[OK]\x1b[0m Notified: {s}\n", .{component});
        } else {
            utils.print("\x1b[33m[SKIP]\x1b[0m Component not running: {s}\n", .{component});
        }
    }

    // Execute shutdown actions.
    for (plan.actions) |action| {
        const start_ns = std.time.nanoTimestamp();

        if (dry_run) {
            utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would execute: {s} — {s}\n", .{
                action.name, action.description,
            });
            try results.append(allocator, ShutdownActionResult{
                .name = try allocator.dupe(u8, action.name),
                .success = true,
                .duration_ms = 0,
                .error_msg = try allocator.dupe(u8, ""),
            });
            continue;
        }

        utils.print("\x1b[34m[EXEC]\x1b[0m {s}: {s}\n", .{ action.name, action.description });

        const r = utils.runShell(allocator, action.command) catch |e| {
            const duration_ms = @divTrunc(std.time.nanoTimestamp() - start_ns, std.time.ns_per_ms);
            if (action.critical) all_success = false;
            try results.append(allocator, ShutdownActionResult{
                .name = try allocator.dupe(u8, action.name),
                .success = false,
                .duration_ms = @intCast(duration_ms),
                .error_msg = try std.fmt.allocPrint(allocator, "{s}", .{@errorName(e)}),
            });
            continue;
        };
        defer allocator.free(r.stdout);
        defer allocator.free(r.stderr);

        const duration_ms = @divTrunc(std.time.nanoTimestamp() - start_ns, std.time.ns_per_ms);
        const ok = r.exit_code == 0;
        if (!ok and action.critical) {
            all_success = false;
            utils.eprint("\x1b[31m[FAIL]\x1b[0m Critical action failed: {s}\n", .{action.name});
        }
        try results.append(allocator, ShutdownActionResult{
            .name = try allocator.dupe(u8, action.name),
            .success = ok,
            .duration_ms = @intCast(duration_ms),
            .error_msg = if (ok)
                try allocator.dupe(u8, "")
            else
                try std.fmt.allocPrint(allocator, "exit code {d}", .{r.exit_code}),
        });
    }

    const completed_at = try utils.rfc3339Now(allocator);
    errdefer allocator.free(completed_at);

    // Mark shutdown complete (clean).
    if (!dry_run) {
        var state = try loadShutdownState(allocator, state_path);
        defer state.deinit(allocator);
        state.shutdown_in_progress = false;
        allocator.free(state.last_clean_shutdown);
        state.last_clean_shutdown = try allocator.dupe(u8, completed_at);
        allocator.free(state.shutdown_reason);
        state.shutdown_reason = try allocator.dupe(u8, plan.reason.toString());
        for (state.notified_components.items) |c| allocator.free(c);
        state.notified_components.clearRetainingCapacity();
        for (notified.items) |c| try state.notified_components.append(allocator, try allocator.dupe(u8, c));
        state.ungraceful_count = 0;
        saveShutdownState(allocator, state_path, state) catch {};
    }

    return ShutdownReport{
        .schema_version = utils.SCHEMA_VERSION,
        .initiated_at = initiated_at,
        .completed_at = completed_at,
        .reason = plan.reason.toString(),
        .success = all_success,
        .actions_taken = results,
        .components_notified = notified,
    };
}

// ── Persistence ───────────────────────────────────────────────────────────────

fn loadShutdownState(
    allocator: std.mem.Allocator,
    path: []const u8,
) !ShutdownState {
    const empty = ShutdownState{
        .schema_version = utils.SCHEMA_VERSION,
        .last_clean_shutdown = try allocator.dupe(u8, ""),
        .shutdown_in_progress = false,
        .shutdown_reason = try allocator.dupe(u8, "unknown"),
        .notified_components = std.ArrayList([]const u8){},
        .pending_flushes = std.ArrayList([]const u8){},
        .ungraceful_count = 0,
    };

    const content = blk: {
        const f = std.fs.cwd().openFile(path, .{}) catch return empty;
        defer f.close();
        break :blk f.readToEndAlloc(allocator, 512 * 1024) catch return empty;
    };
    defer allocator.free(content);

    return parseStateFile(allocator, content) catch empty;
}

fn parseStateFile(allocator: std.mem.Allocator, content: []const u8) !ShutdownState {
    // Narrow parser for our own output format.
    var state = ShutdownState{
        .schema_version = utils.SCHEMA_VERSION,
        .last_clean_shutdown = try allocator.dupe(u8, ""),
        .shutdown_in_progress = false,
        .shutdown_reason = try allocator.dupe(u8, "unknown"),
        .notified_components = std.ArrayList([]const u8){},
        .pending_flushes = std.ArrayList([]const u8){},
        .ungraceful_count = 0,
    };
    errdefer state.deinit(allocator);

    // Extract "shutdown_in_progress": true/false.
    if (std.mem.indexOf(u8, content, "\"shutdown_in_progress\":true") != null or
        std.mem.indexOf(u8, content, "\"shutdown_in_progress\": true") != null)
    {
        state.shutdown_in_progress = true;
    }

    // Extract "ungraceful_count": n.
    if (std.mem.indexOf(u8, content, "\"ungraceful_count\"") != null) {
        const pos = std.mem.indexOf(u8, content, "\"ungraceful_count\"").?;
        const after = content[pos + 18 ..];
        const colon = std.mem.indexOfScalar(u8, after, ':') orelse 0;
        const digits_start = blk: {
            var i = colon + 1;
            while (i < after.len and !std.ascii.isDigit(after[i])) i += 1;
            break :blk i;
        };
        var digits_end = digits_start;
        while (digits_end < after.len and std.ascii.isDigit(after[digits_end])) digits_end += 1;
        if (digits_end > digits_start) {
            state.ungraceful_count = std.fmt.parseInt(i32, after[digits_start..digits_end], 10) catch 0;
        }
    }

    return state;
}

fn saveShutdownState(
    allocator: std.mem.Allocator,
    path: []const u8,
    state: ShutdownState,
) !void {
    const dir = std.fs.path.dirname(path) orelse ".";
    std.fs.cwd().makePath(dir) catch {};

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const w = buf.writer(allocator);
    try w.writeAll("{\n");
    try w.print("  \"schema_version\": \"{s}\",\n", .{utils.SCHEMA_VERSION});
    try w.print("  \"last_clean_shutdown\": \"{s}\",\n", .{state.last_clean_shutdown});
    try w.print("  \"shutdown_in_progress\": {s},\n", .{
        if (state.shutdown_in_progress) "true" else "false",
    });
    try w.print("  \"shutdown_reason\": \"{s}\",\n", .{state.shutdown_reason});
    try w.print("  \"ungraceful_count\": {d},\n", .{state.ungraceful_count});
    try w.writeAll("  \"notified_components\": [");
    for (state.notified_components.items, 0..) |c, i| {
        if (i > 0) try w.writeByte(',');
        try w.print("\"{s}\"", .{c});
    }
    try w.writeAll("],\n  \"pending_flushes\": []\n}\n");

    try utils.atomicWriteFile(allocator, path, buf.items);
}

// ── CLI integration ───────────────────────────────────────────────────────────

pub const ShutdownMarshalArgs = struct {
    state_path: []const u8 = DEFAULT_SHUTDOWN_STATE_PATH,
    dry_run: bool = false,
    reason_str: []const u8 = "user",
    grace: u32 = DEFAULT_GRACE_PERIOD_SECS,
    check: bool = false,
    json_output: bool = false,
};

pub fn runShutdownMarshal(
    allocator: std.mem.Allocator,
    args: ShutdownMarshalArgs,
) !void {
    if (args.check) {
        var state = try checkLastShutdown(allocator, args.state_path);
        defer state.deinit(allocator);

        if (args.json_output) {
            utils.print(
                "{{\"schema_version\":\"{s}\",\"last_clean_shutdown\":\"{s}\",\"shutdown_in_progress\":{s},\"ungraceful_count\":{d}}}\n",
                .{
                    state.schema_version,
                    state.last_clean_shutdown,
                    if (state.shutdown_in_progress) "true" else "false",
                    state.ungraceful_count,
                },
            );
            return;
        }

        utils.print("\n\x1b[34m╔══════════════════════════════════════════╗\x1b[0m\n", .{});
        utils.print("\x1b[34m║\x1b[0m       \x1b[1mSHUTDOWN MARSHAL\x1b[0m                   \x1b[34m║\x1b[0m\n", .{});
        utils.print("\x1b[34m╚══════════════════════════════════════════╝\x1b[0m\n\n", .{});

        if (state.last_clean_shutdown.len > 0) {
            utils.print("\x1b[32m[OK]\x1b[0m Last clean shutdown: {s}\n", .{state.last_clean_shutdown});
        } else {
            utils.print("\x1b[33m[WARN]\x1b[0m No clean shutdown on record\n", .{});
        }

        if (state.ungraceful_count > 0) {
            utils.print(
                "\x1b[31m[ALERT]\x1b[0m {d} consecutive ungraceful shutdown(s) detected\n  This may indicate power loss, kernel panic, or forced reboot\n",
                .{state.ungraceful_count},
            );
        } else {
            utils.print("\x1b[32m[OK]\x1b[0m No ungraceful shutdowns detected\n", .{});
        }
        return;
    }

    const reason = ShutdownReason.fromString(args.reason_str);
    const plan = try prepareShutdown(allocator, reason, args.grace);

    utils.print("\n\x1b[34m╔══════════════════════════════════════════╗\x1b[0m\n", .{});
    utils.print("\x1b[34m║\x1b[0m       \x1b[1mSHUTDOWN MARSHAL\x1b[0m                   \x1b[34m║\x1b[0m\n", .{});
    utils.print("\x1b[34m║\x1b[0m       Graceful Shutdown Orchestrator      \x1b[34m║\x1b[0m\n", .{});
    utils.print("\x1b[34m╚══════════════════════════════════════════╝\x1b[0m\n\n", .{});
    utils.print("\x1b[34m[INFO]\x1b[0m Reason: {s}\n", .{reason.toString()});
    utils.print("\x1b[34m[INFO]\x1b[0m Grace period: {d}s\n", .{args.grace});
    utils.print("\x1b[34m[INFO]\x1b[0m Actions: {d}\n\n", .{plan.actions.len});

    var report = try executeShutdown(allocator, plan, args.state_path, args.dry_run);
    defer report.deinit(allocator);

    if (args.json_output) {
        utils.print(
            "{{\"schema_version\":\"{s}\",\"initiated_at\":\"{s}\",\"completed_at\":\"{s}\",\"reason\":\"{s}\",\"success\":{s}}}\n",
            .{
                report.schema_version,
                report.initiated_at,
                report.completed_at,
                report.reason,
                if (report.success) "true" else "false",
            },
        );
        return;
    }

    if (report.success) {
        utils.print("\n\x1b[32m════════════════════════════════════════════\x1b[0m\n", .{});
        utils.print("\x1b[32m[DONE]\x1b[0m Shutdown orchestration complete\n", .{});
        utils.print("\x1b[32m════════════════════════════════════════════\x1b[0m\n", .{});
    } else {
        utils.print("\n\x1b[33m════════════════════════════════════════════\x1b[0m\n", .{});
        utils.print("\x1b[33m[WARN]\x1b[0m Shutdown orchestration completed with errors\n", .{});
        utils.print("\x1b[33m════════════════════════════════════════════\x1b[0m\n", .{});
    }
}
