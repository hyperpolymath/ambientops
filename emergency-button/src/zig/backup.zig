// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// backup.zig — Quick-backup functionality with preview/dry-run mode.
//
// Ported from backup.v (2026-04-17).
//
// CRIT-002: Path validation prevents shell injection during backup operations.
// HIGH-006: Log writes go through atomicWriteFile.
//
// The backup is deliberately opt-in (only runs when --quick-backup is passed).
// Default is non-destructive and offline-first.

const std = @import("std");
const utils = @import("utils");
const incident_mod = @import("incident");

// =============================================================================
// Path safety
// =============================================================================

/// Shell metacharacters that would enable injection attacks.
const shell_dangerous_chars = [_]u8{
    ';', '|', '&', '$', '`', '(', ')', '{', '}',
    '[', ']', '<', '>', '\n', '\r', '*', '?', '~',
    '!', '#',
};

/// CRIT-002: Validate that a path is safe for interpolation into shell commands.
/// Returns the normalised path on success.
pub fn validateSafePath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]const u8 {
    if (path.len == 0) return error.EmptyPath;

    for (shell_dangerous_chars) |bad| {
        if (std.mem.indexOfScalar(u8, path, bad) != null) {
            return error.DangerousChar;
        }
    }

    // Resolve to absolute, normalised path.
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalised = std.fs.realpath(path, &buf) catch {
        // If the path doesn't exist yet (e.g. backup dest), just return as-is
        // after basic normalisation.  We still refuse ".." traversal.
        if (std.mem.indexOf(u8, path, "..") != null) return error.TraversalDetected;
        return allocator.dupe(u8, path);
    };

    if (std.mem.indexOf(u8, normalised, "..") != null) return error.TraversalDetected;
    return allocator.dupe(u8, normalised);
}

// =============================================================================
// Types
// =============================================================================

pub const BackupItem = struct {
    path: []const u8,
    size: u64,
    is_dir: bool,
    will_backup: bool,
};

pub const BackupPlan = struct {
    allocator: std.mem.Allocator,
    source_dirs: []const []const u8,
    dest_path: []const u8,
    total_files: usize,
    total_size: u64,
    items: std.ArrayList(BackupItem),

    pub fn deinit(self: *BackupPlan) void {
        for (self.items.items) |item| {
            self.allocator.free(item.path);
        }
        self.items.deinit(self.allocator);
    }
};

// =============================================================================
// Public API
// =============================================================================

/// Entry point: validate destination, build plan, optionally execute.
pub fn runQuickBackup(
    allocator: std.mem.Allocator,
    incident: *const incident_mod.Incident,
    config: incident_mod.Config,
) void {
    const dest = config.quick_backup_dest;
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const blue = "\x1b[34m";
    const cyan = "\x1b[36m";
    const reset = "\x1b[0m";

    // Validate destination exists and is a directory.
    std.fs.accessAbsolute(dest, .{}) catch {
        std.debug.print(
            "{s}[ERROR]{s} Backup destination does not exist: {s}\n",
            .{ red, reset, dest },
        );
        std.debug.print(
            "{s}[INFO]{s} Please create the directory first or mount the drive.\n",
            .{ blue, reset },
        );
        utils.logError(allocator, incident.logs_path, "backup", "Destination does not exist", &.{
            .{ .key = "destination", .value = dest },
        });
        return;
    };

    {
        var d = std.fs.openDirAbsolute(dest, .{}) catch {
            std.debug.print(
                "{s}[ERROR]{s} Backup destination is not a directory: {s}\n",
                .{ red, reset, dest },
            );
            return;
        };
        d.close();
    }

    // Determine home dir and default source directories.
    const home = std.posix.getenv("HOME") orelse "/root";

    const source_dirs = [_][]const u8{
        std.fs.path.join(allocator, &.{ home, "Documents" }) catch return,
        std.fs.path.join(allocator, &.{ home, "Desktop" }) catch return,
        std.fs.path.join(allocator, &.{ home, ".ssh" }) catch return,
        std.fs.path.join(allocator, &.{ home, ".gnupg" }) catch return,
        std.fs.path.join(allocator, &.{ home, ".config" }) catch return,
    };
    defer for (source_dirs) |d| allocator.free(d);

    std.debug.print("\n{s}━━━ Quick Backup Preview ━━━{s}\n\n", .{ blue, reset });

    var plan = createBackupPlan(allocator, &source_dirs, dest);
    defer plan.deinit();

    std.debug.print("Source directories:\n", .{});
    for (source_dirs) |dir| {
        if (std.fs.accessAbsolute(dir, .{})) |_| {
            std.debug.print("  {s}✓{s} {s}\n", .{ green, reset, dir });
        } else |_| {
            std.debug.print("  {s}○{s} {s} (not found)\n", .{ yellow, reset, dir });
        }
    }
    std.debug.print("\nDestination: {s}\n", .{dest});
    std.debug.print("\nSummary:\n", .{});
    std.debug.print("  Files to backup: {d}\n", .{plan.total_files});

    var size_buf: [32]u8 = undefined;
    const size_str = formatSize(&size_buf, plan.total_size);
    std.debug.print("  Estimated size:  {s}\n\n", .{size_str});

    logBackupPlan(allocator, incident, &plan, config);

    if (config.dry_run) {
        std.debug.print(
            "{s}[DRY-RUN]{s} Would perform backup of {d} files\n",
            .{ cyan, reset, plan.total_files },
        );
        std.debug.print(
            "{s}[DRY-RUN]{s} Backup log written to incident bundle\n",
            .{ cyan, reset },
        );
        return;
    }

    std.debug.print("{s}[INFO]{s} Starting backup...\n", .{ blue, reset });
    performBackup(allocator, &plan, incident, config);
}

// =============================================================================
// Plan creation
// =============================================================================

fn createBackupPlan(
    allocator: std.mem.Allocator,
    source_dirs: []const []const u8,
    dest: []const u8,
) BackupPlan {
    var plan = BackupPlan{
        .allocator = allocator,
        .source_dirs = source_dirs,
        .dest_path = dest,
        .total_files = 0,
        .total_size = 0,
        .items = std.ArrayList(BackupItem).empty,
    };

    for (source_dirs) |dir| {
        if (std.fs.accessAbsolute(dir, .{})) |_| {
            scanDirectory(allocator, dir, &plan, 0);
        } else |_| {}
    }

    return plan;
}

fn scanDirectory(
    allocator: std.mem.Allocator,
    path: []const u8,
    plan: *BackupPlan,
    depth: usize,
) void {
    if (depth >= 10) return;

    var dir = std.fs.openDirAbsolute(path, .{ .iterate = true }) catch return;
    defer dir.close();

    var it = dir.iterate();
    while (it.next() catch null) |entry| {
        if (std.mem.eql(u8, entry.name, ".git")) continue;

        const child_path = std.fs.path.join(allocator, &.{ path, entry.name }) catch continue;

        if (entry.kind == .directory) {
            scanDirectory(allocator, child_path, plan, depth + 1);
            allocator.free(child_path);
        } else {
            const f = std.fs.openFileAbsolute(child_path, .{}) catch {
                allocator.free(child_path);
                continue;
            };
            const stat = f.stat() catch {
                f.close();
                allocator.free(child_path);
                continue;
            };
            f.close();

            plan.total_files += 1;
            plan.total_size += stat.size;
            plan.items.append(allocator, .{
                .path = child_path,
                .size = stat.size,
                .is_dir = false,
                .will_backup = true,
            }) catch {
                allocator.free(child_path);
            };
        }
    }
}

// =============================================================================
// Execution
// =============================================================================

fn performBackup(
    allocator: std.mem.Allocator,
    plan: *const BackupPlan,
    incident: *const incident_mod.Incident,
    config: incident_mod.Config,
) void {
    _ = config;
    const red = "\x1b[31m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const reset = "\x1b[0m";

    // CRIT-002: Validate destination.
    const safe_dest = validateSafePath(allocator, plan.dest_path) catch |err| {
        std.debug.print(
            "{s}[ERROR]{s} Invalid backup destination path: {}\n",
            .{ red, reset, err },
        );
        utils.logError(allocator, incident.logs_path, "backup", "Invalid destination path", &.{
            .{ .key = "path", .value = plan.dest_path },
            .{ .key = "error", .value = @errorName(err) },
        });
        return;
    };
    defer allocator.free(safe_dest);

    // Build timestamped backup dir name.
    var ts_buf: [16]u8 = undefined;
    const ms = std.time.milliTimestamp();
    const secs: u64 = @intCast(@divTrunc(ms, 1000));
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    const ts = std.fmt.bufPrint(&ts_buf, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}", .{
        yd.year,
        md.month.numeric(),
        md.day_index + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    }) catch &ts_buf;

    const dir_name = std.fmt.allocPrint(allocator, "emergency-backup-{s}", .{ts}) catch return;
    defer allocator.free(dir_name);
    const backup_dir = std.fs.path.join(allocator, &.{ safe_dest, dir_name }) catch return;
    defer allocator.free(backup_dir);

    std.fs.makeDirAbsolute(backup_dir) catch |err| {
        std.debug.print(
            "{s}[ERROR]{s} Failed to create backup directory: {}\n",
            .{ red, reset, err },
        );
        utils.logError(allocator, incident.logs_path, "backup", "Failed to create backup dir", &.{
            .{ .key = "directory", .value = backup_dir },
            .{ .key = "error", .value = @errorName(err) },
        });
        return;
    };

    var copied: usize = 0;
    var failed: usize = 0;

    for (plan.source_dirs) |dir| {
        if (std.fs.accessAbsolute(dir, .{})) |_| {} else |_| continue;

        // CRIT-002: Validate source path.
        const safe_source = validateSafePath(allocator, dir) catch |err| {
            std.debug.print(
                "{s}[WARN]{s} Skipping unsafe path: {s} ({})\n",
                .{ yellow, reset, dir, err },
            );
            utils.logWarn(allocator, incident.logs_path, "backup", "Skipping unsafe source path");
            failed += 1;
            continue;
        };
        defer allocator.free(safe_source);

        const src_dir_name = std.fs.path.basename(safe_source);
        const dest_dir = std.fs.path.join(allocator, &.{ backup_dir, src_dir_name }) catch {
            failed += 1;
            continue;
        };
        defer allocator.free(dest_dir);

        const safe_dest_dir = validateSafePath(allocator, dest_dir) catch |err| {
            std.debug.print(
                "{s}[WARN]{s} Skipping invalid destination: {} \n",
                .{ yellow, reset, err },
            );
            failed += 1;
            continue;
        };
        defer allocator.free(safe_dest_dir);

        // Use system copy: paths are validated.
        const copy_argv: []const []const u8 = switch (@import("builtin").os.tag) {
            .windows => &.{ "xcopy", "/E", "/I", "/H", "/Y", safe_source, safe_dest_dir },
            else => &.{ "cp", "-r", safe_source, safe_dest_dir },
        };

        const result = std.process.Child.run(.{
            .allocator = allocator,
            .argv = copy_argv,
        }) catch {
            failed += 1;
            std.debug.print("  {s}✗{s} {s}\n", .{ red, reset, dir_name });
            continue;
        };
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term == .Exited and result.term.Exited == 0) {
            copied += 1;
            std.debug.print("  {s}✓{s} {s}\n", .{ green, reset, src_dir_name });
        } else {
            failed += 1;
            std.debug.print("  {s}✗{s} {s}\n", .{ red, reset, src_dir_name });
        }
    }

    std.debug.print("\n", .{});
    if (failed == 0) {
        std.debug.print("{s}[OK]{s} Backup complete: {s}\n", .{ green, reset, backup_dir });
    } else {
        std.debug.print(
            "{s}[WARN]{s} Backup completed with {d} errors\n",
            .{ yellow, reset, failed },
        );
    }

    logBackupResult(allocator, incident, backup_dir, copied, failed);
}

// =============================================================================
// Logging helpers
// =============================================================================

fn logBackupPlan(
    allocator: std.mem.Allocator,
    incident: *const incident_mod.Incident,
    plan: *const BackupPlan,
    config: incident_mod.Config,
) void {
    if (config.dry_run) {
        std.debug.print("\x1b[36m[DRY-RUN]\x1b[0m Would write backup plan to logs\n", .{});
        return;
    }

    const log_path = std.fs.path.join(
        allocator,
        &.{ incident.logs_path, "backup_plan.log" },
    ) catch return;
    defer allocator.free(log_path);

    var size_buf: [32]u8 = undefined;
    const size_str = formatSize(&size_buf, plan.total_size);

    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(allocator);
    const w = buf.writer(allocator);

    w.print("schema_version: {s}\n\nQuick Backup Plan\n=================\n\n", .{utils.schema_version}) catch return;
    w.print("Destination: {s}\n", .{plan.dest_path}) catch return;
    w.print("Total files: {d}\n", .{plan.total_files}) catch return;
    w.print("Total size:  {s}\n\nSource directories:\n", .{size_str}) catch return;
    for (plan.source_dirs) |dir| {
        const exists = if (std.fs.accessAbsolute(dir, .{})) |_| "exists" else |_| "not found";
        w.print("  - {s} ({s})\n", .{ dir, exists }) catch {};
    }
    w.print("\nDry run: {}\n", .{config.dry_run}) catch return;

    utils.atomicWriteFile(allocator, log_path, buf.items) catch |err| {
        std.debug.print("\x1b[33m[WARN]\x1b[0m Could not write backup plan: {}\n", .{err});
    };
}

fn logBackupResult(
    allocator: std.mem.Allocator,
    incident: *const incident_mod.Incident,
    backup_dir: []const u8,
    copied: usize,
    failed: usize,
) void {
    const log_path = std.fs.path.join(
        allocator,
        &.{ incident.logs_path, "backup_result.log" },
    ) catch return;
    defer allocator.free(log_path);

    const status = if (failed == 0) "SUCCESS" else "PARTIAL";
    const content = std.fmt.allocPrint(
        allocator,
        "schema_version: {s}\n\nBackup Result\n=============\n\nBackup directory: {s}\nDirectories copied: {d}\nDirectories failed: {d}\nStatus: {s}\n",
        .{ utils.schema_version, backup_dir, copied, failed, status },
    ) catch return;
    defer allocator.free(content);

    utils.atomicWriteFile(allocator, log_path, content) catch |err| {
        std.debug.print("\x1b[33m[WARN]\x1b[0m Could not write backup result: {}\n", .{err});
    };
}

// =============================================================================
// Size formatting
// =============================================================================

/// Format a byte count into a human-readable string.  Writes into `buf`
/// and returns a slice of it; buf must be at least 16 bytes.
pub fn formatSize(buf: []u8, bytes: u64) []const u8 {
    if (bytes >= 1_073_741_824) {
        return std.fmt.bufPrint(buf, "{d:.1}G", .{@as(f64, @floatFromInt(bytes)) / 1_073_741_824.0}) catch "?";
    } else if (bytes >= 1_048_576) {
        return std.fmt.bufPrint(buf, "{d:.1}M", .{@as(f64, @floatFromInt(bytes)) / 1_048_576.0}) catch "?";
    } else if (bytes >= 1024) {
        return std.fmt.bufPrint(buf, "{d:.1}K", .{@as(f64, @floatFromInt(bytes)) / 1024.0}) catch "?";
    }
    return std.fmt.bufPrint(buf, "{d}B", .{bytes}) catch "?";
}

// =============================================================================
// Tests
// =============================================================================

test "validateSafePath rejects dangerous characters" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.DangerousChar, validateSafePath(alloc, "/tmp/backup;rm -rf /"));
    try std.testing.expectError(error.DangerousChar, validateSafePath(alloc, "/tmp/backup|cat"));
}

test "validateSafePath rejects empty path" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.EmptyPath, validateSafePath(alloc, ""));
}

test "formatSize bytes" {
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("512B", formatSize(&buf, 512));
}

test "formatSize kilobytes" {
    var buf: [32]u8 = undefined;
    const s = formatSize(&buf, 2048);
    try std.testing.expect(std.mem.endsWith(u8, s, "K"));
}

test "formatSize gigabytes" {
    var buf: [32]u8 = undefined;
    const s = formatSize(&buf, 2_000_000_000);
    try std.testing.expect(std.mem.endsWith(u8, s, "G"));
}
