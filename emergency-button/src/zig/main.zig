// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// main.zig — Emergency Button CLI entry-point.
//
// Ported from main.v (2026-04-17).
//
// Emergency system recovery launcher.
// Offline-first, non-destructive, idempotent.
//
// USAGE
//   emergency-button trigger [OPTIONS]
//   emergency-button help
//   emergency-button version
//
// Options (for trigger):
//   -b, --quick-backup <path>   Run quick backup to destination (opt-in)
//   -n, --dry-run               Preview actions without executing
//   -V, --verbose               Verbose output

const std = @import("std");
const incident_mod = @import("incident");
const capture = @import("capture");
const handoff = @import("handoff");
const backup = @import("backup");

// Terminal colours.
const c_reset = "\x1b[0m";
const c_bold = "\x1b[1m";
const c_red = "\x1b[31m";
const c_green = "\x1b[32m";
const c_yellow = "\x1b[33m";
const c_blue = "\x1b[34m";
const c_cyan = "\x1b[36m";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip executable name.
    _ = args.next();

    const subcommand = args.next() orelse {
        showHelp();
        return;
    };

    if (std.mem.eql(u8, subcommand, "trigger")) {
        try runTrigger(allocator, &args);
    } else if (std.mem.eql(u8, subcommand, "help") or
        std.mem.eql(u8, subcommand, "--help") or
        std.mem.eql(u8, subcommand, "-h"))
    {
        showHelp();
    } else if (std.mem.eql(u8, subcommand, "version") or
        std.mem.eql(u8, subcommand, "--version") or
        std.mem.eql(u8, subcommand, "-v"))
    {
        std.debug.print("{s} {s}\n", .{ incident_mod.app_name, incident_mod.app_version });
    } else {
        std.debug.print(
            "{s}[ERROR]{s} Unknown command: {s}\n",
            .{ c_red, c_reset, subcommand },
        );
        std.debug.print(
            "Use \"{s} help\" for usage information.\n",
            .{incident_mod.app_name},
        );
        std.process.exit(1);
    }
}

// =============================================================================
// Subcommands
// =============================================================================

fn runTrigger(
    allocator: std.mem.Allocator,
    args: *std.process.ArgIterator,
) !void {
    var quick_backup_dest: []const u8 = "";
    var dry_run = false;
    var verbose = false;

    // Simple flag parser — same semantics as the V original.
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--quick-backup") or std.mem.eql(u8, arg, "-b")) {
            quick_backup_dest = args.next() orelse {
                std.debug.print(
                    "{s}[ERROR]{s} --quick-backup requires a path argument\n",
                    .{ c_red, c_reset },
                );
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "-n")) {
            dry_run = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-V")) {
            verbose = true;
        } else {
            std.debug.print(
                "{s}[ERROR]{s} Unknown option: {s}\n",
                .{ c_red, c_reset, arg },
            );
            std.process.exit(1);
        }
    }

    const config = incident_mod.Config{
        .quick_backup_dest = quick_backup_dest,
        .dry_run = dry_run,
        .verbose = verbose,
    };

    // Banner.
    std.debug.print("\n", .{});
    std.debug.print("{s}╔══════════════════════════════════════════╗{s}\n", .{ c_blue, c_reset });
    std.debug.print("{s}║{s}       {s}EMERGENCY BUTTON{s}                   {s}║{s}\n", .{ c_blue, c_reset, c_bold, c_reset, c_blue, c_reset });
    std.debug.print("{s}║{s}       Safe • Offline • Idempotent        {s}║{s}\n", .{ c_blue, c_reset, c_blue, c_reset });
    std.debug.print("{s}╚══════════════════════════════════════════╝{s}\n", .{ c_blue, c_reset });
    std.debug.print("\n", .{});

    if (config.dry_run) {
        std.debug.print("{s}[DRY-RUN]{s} Preview mode - no changes will be made\n\n", .{ c_yellow, c_reset });
    }

    // Create incident bundle.
    var incident = incident_mod.createIncidentBundle(allocator, config) catch |err| {
        std.debug.print(
            "{s}[ERROR]{s} Failed to create incident bundle: {}\n",
            .{ c_red, c_reset, err },
        );
        std.process.exit(1);
    };
    defer incident.deinit();

    std.debug.print("{s}[OK]{s} Created incident bundle: {s}\n", .{ c_green, c_reset, incident.path });
    std.debug.print("{s}[INFO]{s} Correlation ID: {s}\n\n", .{ c_blue, c_reset, incident.correlation_id });

    // Capture diagnostics.
    std.debug.print("{s}[INFO]{s} Capturing safe diagnostics...\n", .{ c_blue, c_reset });
    capture.captureDiagnostics(allocator, &incident, config);

    // Write receipt.
    incident_mod.writeReceipt(&incident, config) catch |err| {
        std.debug.print("{s}[WARN]{s} Could not write receipt: {}\n", .{ c_yellow, c_reset, err });
    };

    // Optional quick backup.
    if (config.quick_backup_dest.len > 0) {
        std.debug.print("\n", .{});
        std.debug.print(
            "{s}[INFO]{s} Quick backup requested to: {s}\n",
            .{ c_blue, c_reset, config.quick_backup_dest },
        );
        backup.runQuickBackup(allocator, &incident, config);
    }

    // Handoff.
    std.debug.print("\n", .{});
    handoff.handoff(allocator, &incident, config);

    // Done banner.
    std.debug.print("\n", .{});
    std.debug.print("{s}════════════════════════════════════════════{s}\n", .{ c_green, c_reset });
    std.debug.print("{s}[DONE]{s} Incident bundle ready: {s}\n", .{ c_green, c_reset, incident.path });
    std.debug.print("{s}════════════════════════════════════════════{s}\n", .{ c_green, c_reset });
}

fn showHelp() void {
    std.debug.print(
        \\{s}emergency-button{s} - Emergency system recovery launcher
        \\
        \\{s}USAGE:{s}
        \\    emergency-button trigger [OPTIONS]
        \\
        \\{s}COMMANDS:{s}
        \\    trigger     Create incident bundle and capture diagnostics
        \\    help        Show this help message
        \\    version     Show version information
        \\
        \\{s}OPTIONS (for trigger):{s}
        \\    -b, --quick-backup <path>   Run quick backup to destination (opt-in)
        \\    -n, --dry-run               Preview actions without executing
        \\    -V, --verbose               Verbose output
        \\
        \\{s}EXAMPLES:{s}
        \\    emergency-button trigger
        \\    emergency-button trigger --dry-run
        \\    emergency-button trigger --quick-backup /mnt/backup
        \\
        \\{s}SAFETY:{s}
        \\    - Default action is non-destructive and offline-first
        \\    - No silent downloads, no auto-fixes
        \\    - Idempotent: pressing twice is safe
        \\    - Everything logged to incident bundle
        \\
    ,
        .{
            c_bold, c_reset,
            c_bold, c_reset,
            c_bold, c_reset,
            c_bold, c_reset,
            c_bold, c_reset,
            c_bold, c_reset,
        },
    );
}
