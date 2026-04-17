// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// main.zig — Emergency Room CLI entry point.
//
// Subcommands:
//   trigger          Create incident bundle and capture diagnostics.
//   boot-guardian    Boot health monitoring and loop detection (CC-002, CC-003).
//   shutdown-marshal Graceful shutdown orchestration (CC-002).
//   help             Show usage.
//   version          Show version.
//
// Corresponds to: src/main.v
//
// All allocation flows through a GeneralPurposeAllocator.  Every sub-path
// that owns allocations cleans up via defer / errdefer.  No @panic in
// reachable code — all errors propagate as error union values.

const std = @import("std");
const utils = @import("utils");
const inc_mod = @import("incident");
const cap_mod = @import("capture");
const handoff_mod = @import("handoff");
const backup_mod = @import("backup");
const boot_guardian = @import("boot_guardian");
const shutdown_marshal = @import("shutdown_marshal");

const APP_NAME = "emergency-button";
const VERSION = "0.1.0";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        showHelp();
        return;
    }

    const cmd = args[1];

    if (std.mem.eql(u8, cmd, "trigger")) {
        try runTrigger(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "boot-guardian")) {
        try runBootGuardianCmd(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "shutdown-marshal")) {
        try runShutdownMarshalCmd(allocator, args[2..]);
    } else if (std.mem.eql(u8, cmd, "help") or
        std.mem.eql(u8, cmd, "--help") or
        std.mem.eql(u8, cmd, "-h"))
    {
        showHelp();
    } else if (std.mem.eql(u8, cmd, "version") or
        std.mem.eql(u8, cmd, "--version") or
        std.mem.eql(u8, cmd, "-v"))
    {
        utils.print("{s} {s}\n", .{ APP_NAME, VERSION });
    } else {
        utils.eprint("Unknown command: {s}\n", .{cmd});
        utils.eprint("Use \"{s} help\" for usage information.\n", .{APP_NAME});
        std.process.exit(1);
    }
}

// ── trigger subcommand ────────────────────────────────────────────────────────

fn runTrigger(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var config = inc_mod.Config{};

    // Parse flags.
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            config.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-V")) {
            config.verbose = true;
        } else if (std.mem.eql(u8, arg, "--envelope") or std.mem.eql(u8, arg, "-e")) {
            config.envelope = true;
        } else if (std.mem.eql(u8, arg, "--quick-backup") or std.mem.eql(u8, arg, "-b")) {
            i += 1;
            if (i >= args.len) {
                utils.eprint("--quick-backup requires a path argument\n", .{});
                std.process.exit(1);
            }
            config.quick_backup_dest = args[i];
        }
    }

    utils.print("\n\x1b[34m╔══════════════════════════════════════════╗\x1b[0m\n", .{});
    utils.print("\x1b[34m║\x1b[0m       \x1b[1mEMERGENCY BUTTON\x1b[0m                   \x1b[34m║\x1b[0m\n", .{});
    utils.print("\x1b[34m║\x1b[0m       Safe • Offline • Idempotent        \x1b[34m║\x1b[0m\n", .{});
    utils.print("\x1b[34m╚══════════════════════════════════════════╝\x1b[0m\n\n", .{});

    if (config.dry_run) {
        utils.print("\x1b[33m[DRY-RUN]\x1b[0m Preview mode - no changes will be made\n\n", .{});
    }

    // Create incident bundle.
    var incident = inc_mod.createIncidentBundle(allocator, config) catch |e| {
        utils.eprint("\x1b[31m[ERROR]\x1b[0m Failed to create incident bundle: {s}\n", .{@errorName(e)});
        std.process.exit(1);
    };
    defer incident.deinit(allocator);

    utils.print("\x1b[32m[OK]\x1b[0m Created incident bundle: {s}\n", .{incident.path});
    utils.print("\x1b[34m[INFO]\x1b[0m Correlation ID: {s}\n\n", .{incident.correlation_id});

    // Capture diagnostics.
    utils.print("\x1b[34m[INFO]\x1b[0m Capturing safe diagnostics...\n", .{});

    const modules = [_]cap_mod.CaptureModule{
        .{ .name = "os_version",      .display_name = "OS Version",       .commands = cap_mod.getOsVersionCommands() },
        .{ .name = "uptime",          .display_name = "System Uptime",    .commands = cap_mod.getUptimeCommands() },
        .{ .name = "disk_free",       .display_name = "Disk Space",       .commands = cap_mod.getDiskCommands() },
        .{ .name = "memory",          .display_name = "Memory Status",    .commands = cap_mod.getMemoryCommands() },
        .{ .name = "network_summary", .display_name = "Network Summary",  .commands = cap_mod.getNetworkCommands() },
        .{ .name = "process_summary", .display_name = "Process Summary",  .commands = cap_mod.getProcessCommands() },
    };

    const now_ts = try utils.rfc3339Now(allocator);
    defer allocator.free(now_ts);

    for (modules) |mod| {
        const result = try cap_mod.runCaptureModule(allocator, mod, incident.logs_path, config.dry_run);
        defer allocator.free(result.output);
        defer allocator.free(result.error_msg);

        if (result.success) {
            utils.print("  \x1b[32m✓\x1b[0m {s}\n", .{mod.display_name});
        } else {
            utils.print("  \x1b[33m○\x1b[0m {s} (skipped)\n", .{mod.display_name});
        }

        const end_ts = try utils.rfc3339Now(allocator);
        defer allocator.free(end_ts);

        try incident.commands.append(allocator, inc_mod.CommandLog{
            .name       = try allocator.dupe(u8, mod.name),
            .command    = try allocator.dupe(u8, if (mod.commands.len > 0) mod.commands[0] else ""),
            .started_at = try allocator.dupe(u8, now_ts),
            .ended_at   = try allocator.dupe(u8, end_ts),
            .exit_code  = if (result.success) 0 else 1,
            .output_len = result.output.len,
        });
    }

    inc_mod.updateIncidentJson(allocator, incident, config);

    // Write receipt.
    inc_mod.writeReceipt(allocator, incident, config) catch |e| {
        utils.eprint("\x1b[33m[WARN]\x1b[0m Could not write receipt: {s}\n", .{@errorName(e)});
        utils.logWarn(allocator, incident.logs_path, "main", "Could not write receipt");
    };

    // Generate EvidenceEnvelope if requested.
    if (config.envelope) {
        inc_mod.writeEvidenceEnvelope(allocator, incident, config) catch |e| {
            utils.eprint("\x1b[33m[WARN]\x1b[0m Could not write envelope: {s}\n", .{@errorName(e)});
            utils.logWarn(allocator, incident.logs_path, "main", "Could not write envelope");
        };
    }

    // Quick backup if requested.
    if (config.quick_backup_dest.len > 0) {
        utils.print("\n\x1b[34m[INFO]\x1b[0m Quick backup requested to: {s}\n", .{config.quick_backup_dest});
        backup_mod.runQuickBackup(allocator, incident, config);
    }

    // Handoff to specialized tool.
    utils.print("\n", .{});
    handoff_mod.handoff(allocator, incident, config);

    utils.print("\n\x1b[32m════════════════════════════════════════════\x1b[0m\n", .{});
    utils.print("\x1b[32m[DONE]\x1b[0m Incident bundle ready: {s}\n", .{incident.path});
    utils.print("\x1b[32m════════════════════════════════════════════\x1b[0m\n", .{});
}

// ── boot-guardian subcommand ──────────────────────────────────────────────────

fn runBootGuardianCmd(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var bg_args = boot_guardian.BootGuardianArgs{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            bg_args.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--record") or std.mem.eql(u8, arg, "-r")) {
            bg_args.record = true;
        } else if (std.mem.eql(u8, arg, "--check") or std.mem.eql(u8, arg, "-c")) {
            bg_args.check_only = true;
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            bg_args.json_output = true;
        } else if (std.mem.eql(u8, arg, "--stamps") or std.mem.eql(u8, arg, "-s")) {
            i += 1;
            if (i < args.len) bg_args.stamp_path = args[i];
        }
    }

    try boot_guardian.runBootGuardian(allocator, bg_args);
}

// ── shutdown-marshal subcommand ───────────────────────────────────────────────

fn runShutdownMarshalCmd(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var sm_args = shutdown_marshal.ShutdownMarshalArgs{};

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            sm_args.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--check") or std.mem.eql(u8, arg, "-c")) {
            sm_args.check = true;
        } else if (std.mem.eql(u8, arg, "--json") or std.mem.eql(u8, arg, "-j")) {
            sm_args.json_output = true;
        } else if (std.mem.eql(u8, arg, "--reason") or std.mem.eql(u8, arg, "-r")) {
            i += 1;
            if (i < args.len) sm_args.reason_str = args[i];
        } else if (std.mem.eql(u8, arg, "--grace") or std.mem.eql(u8, arg, "-g")) {
            i += 1;
            if (i < args.len) {
                sm_args.grace = std.fmt.parseInt(u32, args[i], 10) catch sm_args.grace;
            }
        } else if (std.mem.eql(u8, arg, "--state") or std.mem.eql(u8, arg, "-s")) {
            i += 1;
            if (i < args.len) sm_args.state_path = args[i];
        }
    }

    try shutdown_marshal.runShutdownMarshal(allocator, sm_args);
}

// ── Help ──────────────────────────────────────────────────────────────────────

fn showHelp() void {
    utils.print(
        "\x1b[1m{s}\x1b[0m - Emergency system recovery launcher\n\n" ++
            "\x1b[1mUSAGE:\x1b[0m\n" ++
            "    {s} trigger [OPTIONS]\n\n" ++
            "\x1b[1mCOMMANDS:\x1b[0m\n" ++
            "    trigger          Create incident bundle and capture diagnostics\n" ++
            "    boot-guardian    Boot health monitoring and loop detection (CC-002, CC-003)\n" ++
            "    shutdown-marshal Graceful shutdown orchestration (CC-002)\n" ++
            "    help             Show this help message\n" ++
            "    version          Show version information\n\n" ++
            "\x1b[1mOPTIONS (for trigger):\x1b[0m\n" ++
            "    -b, --quick-backup <path>   Run quick backup to destination (opt-in)\n" ++
            "    -n, --dry-run               Preview actions without executing\n" ++
            "    -V, --verbose               Verbose output\n" ++
            "    -e, --envelope              Generate EvidenceEnvelope JSON\n\n" ++
            "\x1b[1mEXAMPLES:\x1b[0m\n" ++
            "    {s} trigger\n" ++
            "    {s} trigger --dry-run\n" ++
            "    {s} trigger --quick-backup /mnt/backup\n\n" ++
            "\x1b[1mSAFETY:\x1b[0m\n" ++
            "    - Default action is non-destructive and offline-first\n" ++
            "    - No silent downloads, no auto-fixes\n" ++
            "    - Idempotent: pressing twice is safe\n" ++
            "    - Everything logged to incident bundle\n",
        .{ APP_NAME, APP_NAME, APP_NAME, APP_NAME, APP_NAME },
    );
}
