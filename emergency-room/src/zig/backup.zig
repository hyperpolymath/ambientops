// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// backup.zig — Quick backup with path validation (CRIT-002).
//
// Corresponds to: src/backup.v

const std = @import("std");
const utils = @import("utils");
const incident = @import("incident");

// ── FFI: proven_path_has_traversal from libproven_ffi ──────────────────────────

/// C ABI result type for boolean operations (matches ProvenBoolResult in proven.h).
const ProvenBoolResult = extern struct {
    status: c_int,
    value:  bool,
};

const PROVEN_OK: c_int = 0;

/// Check if a byte slice contains a directory traversal sequence ("..").
/// Linked from verification-ecosystem/proven (libproven_ffi).
extern fn proven_path_has_traversal(ptr: [*]const u8, len: usize) ProvenBoolResult;

// ── Path validation (CRIT-002) ────────────────────────────────────────────────

const SHELL_DANGEROUS_CHARS: []const u8 = ";|&$`(){}[]<>\n\r*?~!#";

/// Validate a path is safe for shell interpolation.
/// Returns the normalized path on success, error otherwise.
///
/// Checks:
///   1. No empty paths
///   2. No shell metacharacters (injection prevention)
///   3. No directory traversal sequences ("..") via proven_path_has_traversal
pub fn validateSafePath(
    allocator: std.mem.Allocator,
    path: []const u8,
) ![]u8 {
    if (path.len == 0) return error.EmptyPath;

    // Gate 1: Shell character filtering.
    for (path) |c| {
        for (SHELL_DANGEROUS_CHARS) |bad| {
            if (c == bad) return error.DangerousCharacterInPath;
        }
    }

    // Gate 2: Proven-backed traversal detection.
    // proven_path_has_traversal is formally-verified; fail-closed on error.
    const result = proven_path_has_traversal(path.ptr, path.len);
    if (result.status != PROVEN_OK) {
        return error.PathTraversal;
    }
    if (result.value) {
        // result.value == true means traversal detected → deny.
        return error.PathTraversal;
    }

    // Normalize for the caller's convenience.
    var real_buf: [std.fs.max_path_bytes]u8 = undefined;
    const normalized = std.fs.realpath(path, &real_buf) catch {
        // If path doesn't exist yet, we've already validated no traversal
        // via proven_path_has_traversal above.
        return allocator.dupe(u8, path);
    };

    return allocator.dupe(u8, normalized);
}

// ── Backup plan ───────────────────────────────────────────────────────────────

pub const BackupItem = struct {
    path: []const u8,
    size: u64,
    is_dir: bool,
    will_backup: bool,
};

pub const BackupPlan = struct {
    source_dirs: []const []const u8,
    dest_path: []const u8,
    total_files: usize,
    total_size: u64,
    items: std.ArrayList(BackupItem),

    pub fn deinit(self: *BackupPlan, allocator: std.mem.Allocator) void {
        for (self.items.items) |item| allocator.free(item.path);
        self.items.deinit(allocator);
    }
};

fn scanDirectory(
    allocator: std.mem.Allocator,
    path: []const u8,
    plan: *BackupPlan,
    depth: usize,
) void {
    if (depth >= 10) return;

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (std.mem.eql(u8, entry.name, ".git")) continue;

        const full = std.fs.path.join(allocator, &.{ path, entry.name }) catch continue;

        if (entry.kind == .directory) {
            scanDirectory(allocator, full, plan, depth + 1);
            allocator.free(full);
        } else {
            const st = std.fs.cwd().statFile(full) catch {
                allocator.free(full);
                continue;
            };
            const size = st.size;
            plan.total_files += 1;
            plan.total_size += size;
            plan.items.append(allocator, BackupItem{
                .path = full,
                .size = size,
                .is_dir = false,
                .will_backup = true,
            }) catch {
                allocator.free(full);
            };
        }
    }
}

fn createBackupPlan(
    allocator: std.mem.Allocator,
    source_dirs: []const []const u8,
    dest: []const u8,
) BackupPlan {
    var plan = BackupPlan{
        .source_dirs = source_dirs,
        .dest_path = dest,
        .total_files = 0,
        .total_size = 0,
        .items = std.ArrayList(BackupItem){},
    };

    for (source_dirs) |dir| {
        if (std.fs.cwd().statFile(dir) catch null) |st| {
            if (st.kind != .directory) continue;
        } else continue;
        scanDirectory(allocator, dir, &plan, 0);
    }

    return plan;
}

fn formatSize(allocator: std.mem.Allocator, bytes: u64) ![]u8 {
    if (bytes >= 1_073_741_824)
        return std.fmt.allocPrint(allocator, "{d:.1}G", .{@as(f64, @floatFromInt(bytes)) / 1_073_741_824.0});
    if (bytes >= 1_048_576)
        return std.fmt.allocPrint(allocator, "{d:.1}M", .{@as(f64, @floatFromInt(bytes)) / 1_048_576.0});
    if (bytes >= 1024)
        return std.fmt.allocPrint(allocator, "{d:.1}K", .{@as(f64, @floatFromInt(bytes)) / 1024.0});
    return std.fmt.allocPrint(allocator, "{d}B", .{bytes});
}

pub fn runQuickBackup(
    allocator: std.mem.Allocator,
    inc: incident.Incident,
    config: incident.Config,
) void {
    runQuickBackupInner(allocator, inc, config) catch |e| {
        utils.eprint("\x1b[31m[ERROR]\x1b[0m Backup failed: {s}\n", .{@errorName(e)});
    };
}

fn runQuickBackupInner(
    allocator: std.mem.Allocator,
    inc: incident.Incident,
    config: incident.Config,
) !void {
    const dest = config.quick_backup_dest;

    // Check destination exists and is a directory.
    const dest_stat = std.fs.cwd().statFile(dest) catch {
        utils.eprint("\x1b[31m[ERROR]\x1b[0m Backup destination does not exist: {s}\n", .{dest});
        utils.eprint("\x1b[34m[INFO]\x1b[0m Please create the directory first or mount the drive.\n", .{});
        utils.logError(allocator, inc.logs_path, "backup", "Backup destination does not exist", &.{
            .{ .key = "destination", .value = dest },
        });
        return;
    };
    if (dest_stat.kind != .directory) {
        utils.eprint("\x1b[31m[ERROR]\x1b[0m Backup destination is not a directory: {s}\n", .{dest});
        utils.logError(allocator, inc.logs_path, "backup", "Backup destination is not a directory", &.{
            .{ .key = "destination", .value = dest },
        });
        return;
    }

    const home = std.posix.getenv("HOME") orelse "/tmp";
    const source_dirs = &[_][]const u8{
        try std.fs.path.join(allocator, &.{ home, "Documents" }),
        try std.fs.path.join(allocator, &.{ home, "Desktop" }),
        try std.fs.path.join(allocator, &.{ home, ".ssh" }),
        try std.fs.path.join(allocator, &.{ home, ".gnupg" }),
        try std.fs.path.join(allocator, &.{ home, ".config" }),
    };
    defer for (source_dirs) |d| allocator.free(d);

    utils.print("\n\x1b[34m━━━ Quick Backup Preview ━━━\x1b[0m\n\nSource directories:\n", .{});
    for (source_dirs) |dir| {
        if (std.fs.cwd().statFile(dir) catch null) |_| {
            utils.print("  \x1b[32m✓\x1b[0m {s}\n", .{dir});
        } else {
            utils.print("  \x1b[33m○\x1b[0m {s} (not found)\n", .{dir});
        }
    }

    var plan = createBackupPlan(allocator, source_dirs, dest);
    defer plan.deinit(allocator);

    const size_str = try formatSize(allocator, plan.total_size);
    defer allocator.free(size_str);

    utils.print("\nDestination: {s}\n\nSummary:\n  Files to backup: {d}\n  Estimated size:  {s}\n\n", .{
        dest, plan.total_files, size_str,
    });

    try logBackupPlan(allocator, inc, &plan, config);

    if (config.dry_run) {
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would perform backup of {d} files\n", .{plan.total_files});
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Backup log written to incident bundle\n", .{});
        return;
    }

    utils.print("\x1b[34m[INFO]\x1b[0m Starting backup...\n", .{});
    try performBackup(allocator, &plan, inc);
}

fn performBackup(
    allocator: std.mem.Allocator,
    plan: *BackupPlan,
    inc: incident.Incident,
) !void {
    const ts = try utils.rfc3339Now(allocator);
    defer allocator.free(ts);
    // Format as YYYYMMDD-HHmmss — reuse first 15 chars of RFC3339.
    const ts_compact = if (ts.len >= 19)
        try std.fmt.allocPrint(allocator, "{s}{s}{s}-{s}{s}{s}", .{
            ts[0..4], ts[5..7], ts[8..10],
            ts[11..13], ts[14..16], ts[17..19],
        })
    else
        try allocator.dupe(u8, "00000000-000000");
    defer allocator.free(ts_compact);

    // CRIT-002: validate destination.
    const safe_dest = validateSafePath(allocator, plan.dest_path) catch |e| {
        utils.eprint("\x1b[31m[ERROR]\x1b[0m Invalid backup destination path: {s}\n", .{@errorName(e)});
        utils.logError(allocator, inc.logs_path, "backup", "Invalid backup destination path", &.{
            .{ .key = "path", .value = plan.dest_path },
            .{ .key = "error", .value = @errorName(e) },
        });
        return;
    };
    defer allocator.free(safe_dest);

    const backup_dir = try std.fmt.allocPrint(allocator, "{s}/emergency-backup-{s}", .{
        safe_dest, ts_compact,
    });
    defer allocator.free(backup_dir);

    std.fs.cwd().makePath(backup_dir) catch |e| {
        utils.eprint("\x1b[31m[ERROR]\x1b[0m Failed to create backup directory: {s}\n", .{@errorName(e)});
        return;
    };

    var copied: usize = 0;
    var failed: usize = 0;

    for (plan.source_dirs) |dir| {
        if (std.fs.cwd().statFile(dir) catch null == null) continue;

        // CRIT-002: validate each source path.
        const safe_src = validateSafePath(allocator, dir) catch {
            utils.eprint("\x1b[33m[WARN]\x1b[0m Skipping unsafe path: {s}\n", .{dir});
            utils.logWarn(allocator, inc.logs_path, "backup", "Skipping unsafe source path");
            failed += 1;
            continue;
        };
        defer allocator.free(safe_src);

        const dir_name = std.fs.path.basename(safe_src);
        const dest_dir = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ backup_dir, dir_name });
        defer allocator.free(dest_dir);

        const safe_dest_dir = validateSafePath(allocator, dest_dir) catch {
            failed += 1;
            continue;
        };
        defer allocator.free(safe_dest_dir);

        const cp_cmd = try std.fmt.allocPrint(allocator, "cp -r \"{s}\" \"{s}\" 2>/dev/null", .{
            safe_src, safe_dest_dir,
        });
        defer allocator.free(cp_cmd);

        const r = utils.runShell(allocator, cp_cmd) catch {
            failed += 1;
            utils.print("  \x1b[31m✗\x1b[0m {s}\n", .{dir_name});
            continue;
        };
        defer allocator.free(r.stdout);
        defer allocator.free(r.stderr);

        if (r.exit_code == 0) {
            copied += 1;
            utils.print("  \x1b[32m✓\x1b[0m {s}\n", .{dir_name});
        } else {
            failed += 1;
            utils.print("  \x1b[31m✗\x1b[0m {s}\n", .{dir_name});
        }
    }

    utils.print("\n", .{});
    if (failed == 0) {
        utils.print("\x1b[32m[OK]\x1b[0m Backup complete: {s}\n", .{backup_dir});
    } else {
        utils.print("\x1b[33m[WARN]\x1b[0m Backup completed with {d} errors\n", .{failed});
    }

    try logBackupResult(allocator, inc, backup_dir, copied, failed);
}

fn logBackupPlan(
    allocator: std.mem.Allocator,
    inc: incident.Incident,
    plan: *const BackupPlan,
    config: incident.Config,
) !void {
    const log_path = try std.fs.path.join(allocator, &.{ inc.logs_path, "backup_plan.log" });
    defer allocator.free(log_path);

    const size_str = try formatSize(allocator, plan.total_size);
    defer allocator.free(size_str);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const w = buf.writer(allocator);
    try w.print("schema_version: {s}\n\nQuick Backup Plan\n=================\n\n", .{utils.SCHEMA_VERSION});
    try w.print("Destination: {s}\nTotal files: {d}\nTotal size:  {s}\n\nSource directories:\n", .{
        plan.dest_path, plan.total_files, size_str,
    });
    for (plan.source_dirs) |dir| {
        const exists = if (std.fs.cwd().statFile(dir) catch null != null) "exists" else "not found";
        try w.print("  - {s} ({s})\n", .{ dir, exists });
    }
    try w.print("\nDry run: {s}\n", .{if (config.dry_run) "true" else "false"});

    if (config.dry_run) {
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would write backup plan to logs\n", .{});
        return;
    }

    try utils.atomicWriteFile(allocator, log_path, buf.items);
}

fn logBackupResult(
    allocator: std.mem.Allocator,
    inc: incident.Incident,
    backup_dir: []const u8,
    copied: usize,
    failed: usize,
) !void {
    const log_path = try std.fs.path.join(allocator, &.{ inc.logs_path, "backup_result.log" });
    defer allocator.free(log_path);

    const content = try std.fmt.allocPrint(
        allocator,
        "schema_version: {s}\n\nBackup Result\n=============\n\nBackup directory: {s}\nDirectories copied: {d}\nDirectories failed: {d}\nStatus: {s}\n",
        .{
            utils.SCHEMA_VERSION,
            backup_dir,
            copied,
            failed,
            if (failed == 0) "SUCCESS" else "PARTIAL",
        },
    );
    defer allocator.free(content);

    try utils.atomicWriteFile(allocator, log_path, content);
}
