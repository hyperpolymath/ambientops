// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// incident.zig — Incident bundle creation and management.
//
// Corresponds to: src/incident.v
//
// Safety contracts:
//   - atomicWriteFile used for every JSON/AsciiDoc output (HIGH-006).
//   - All error paths propagate via error unions; no @panic.
//   - All allocated strings are documented at call site.

const std = @import("std");
const utils = @import("utils");

pub const SCHEMA_VERSION = utils.SCHEMA_VERSION;

// ── Types ─────────────────────────────────────────────────────────────────────

pub const CommandLog = struct {
    name: []const u8,
    command: []const u8,
    started_at: []const u8,
    ended_at: []const u8,
    exit_code: i32,
    output_len: usize,
};

pub const Incident = struct {
    id: []const u8,
    correlation_id: []const u8,
    path: []const u8,
    logs_path: []const u8,
    created_at_epoch: i64,
    /// Mutable command log; owned by the Incident.
    commands: std.ArrayList(CommandLog),

    pub fn deinit(self: *Incident, allocator: std.mem.Allocator) void {
        for (self.commands.items) |cmd| {
            allocator.free(cmd.name);
            allocator.free(cmd.command);
            allocator.free(cmd.started_at);
            allocator.free(cmd.ended_at);
        }
        self.commands.deinit(allocator);
        allocator.free(self.id);
        allocator.free(self.correlation_id);
        allocator.free(self.path);
        allocator.free(self.logs_path);
    }
};

pub const Config = struct {
    quick_backup_dest: []const u8 = "",
    dry_run: bool = false,
    verbose: bool = false,
    envelope: bool = false,
};

// ── Bundle creation ───────────────────────────────────────────────────────────

/// Create and return an Incident.  On dry_run the directory is NOT created.
/// Caller must call incident.deinit(allocator) when done.
pub fn createIncidentBundle(
    allocator: std.mem.Allocator,
    config: Config,
) !Incident {
    const now_secs = std.time.timestamp();

    // Timestamp component: YYYYMMDD-HHmmss
    const ts = try formatTimestamp(allocator, now_secs);
    defer allocator.free(ts);

    // Nanoseconds for collision avoidance (HIGH-005 equivalent).
    const nanos = std.time.nanoTimestamp();
    const rand_suffix = try utils.randomHex(allocator, 2); // 4 hex chars
    defer allocator.free(rand_suffix);

    const incident_id = try std.fmt.allocPrint(allocator, "incident-{s}-{d:0>9}-{s}", .{
        ts, @as(u64, @intCast(@mod(nanos, 1_000_000_000))), rand_suffix,
    });
    errdefer allocator.free(incident_id);

    // Correlation ID for cross-tool tracing.
    const corr_hex = try utils.randomHex(allocator, 4); // 8 hex chars
    defer allocator.free(corr_hex);
    const correlation_id = try std.fmt.allocPrint(allocator, "corr-{s}", .{corr_hex});
    errdefer allocator.free(correlation_id);

    // Build paths.
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buf);

    const incident_path = try std.fs.path.join(allocator, &.{ cwd, incident_id });
    errdefer allocator.free(incident_path);

    const logs_path = try std.fs.path.join(allocator, &.{ incident_path, "logs" });
    errdefer allocator.free(logs_path);

    if (config.dry_run) {
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would create: {s}\n", .{incident_path});
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would create: {s}\n", .{logs_path});
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Correlation ID: {s}\n", .{correlation_id});

        return Incident{
            .id = incident_id,
            .correlation_id = correlation_id,
            .path = incident_path,
            .logs_path = logs_path,
            .created_at_epoch = now_secs,
            .commands = std.ArrayList(CommandLog){},
        };
    }

    // Idempotency: reject if already exists.
    if (std.fs.cwd().openDir(incident_path, .{}) catch null != null) {
        return error.IncidentDirectoryAlreadyExists;
    }

    // Create directory tree.
    std.fs.cwd().makePath(logs_path) catch |e| return e;

    var incident = Incident{
        .id = incident_id,
        .correlation_id = correlation_id,
        .path = incident_path,
        .logs_path = logs_path,
        .created_at_epoch = now_secs,
        .commands = std.ArrayList(CommandLog){},
    };

    // Write initial incident.json.
    writeIncidentJson(allocator, incident, config) catch |e| {
        incident.deinit(allocator);
        return e;
    };

    return incident;
}

// ── JSON writers ──────────────────────────────────────────────────────────────

/// Write incident.json (atomic).  Corresponds to write_incident_json in V.
pub fn writeIncidentJson(
    allocator: std.mem.Allocator,
    incident: Incident,
    config: Config,
) !void {
    if (config.dry_run) {
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would write incident.json\n", .{});
        return;
    }

    const hostname = try getHostname(allocator);
    defer allocator.free(hostname);

    const username = try getUsername(allocator);
    defer allocator.free(username);

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buf);

    const kernel = try utils.getKernelVersion(allocator);
    defer allocator.free(kernel);

    const created_at = try utils.rfc3339FromEpoch(allocator, incident.created_at_epoch);
    defer allocator.free(created_at);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const w = buf.writer(allocator);
    try w.writeAll("{\n");
    try w.print("  \"schema_version\": \"{s}\",\n", .{SCHEMA_VERSION});
    try w.print("  \"id\": \"{s}\",\n", .{incident.id});
    try w.print("  \"correlation_id\": \"{s}\",\n", .{incident.correlation_id});
    try w.print("  \"created_at\": \"{s}\",\n", .{created_at});
    try w.print("  \"hostname\": \"{s}\",\n", .{hostname});
    try w.print("  \"username\": \"{s}\",\n", .{username});
    try w.print("  \"working_dir\": \"{s}\",\n", .{cwd});
    try w.writeAll("  \"platform\": {\n");
    try w.print("    \"os\": \"{s}\",\n", .{utils.getOsName()});
    try w.print("    \"arch\": \"{s}\",\n", .{utils.getArch()});
    try w.print("    \"kernel\": \"{s}\"\n", .{kernel});
    try w.writeAll("  },\n");
    try w.writeAll("  \"trigger\": {\n");
    try w.print("    \"version\": \"0.1.0\",\n", .{});
    try w.print("    \"dry_run\": {s},\n", .{if (config.dry_run) "true" else "false"});
    try w.writeAll("    \"args\": \"\"\n");
    try w.writeAll("  },\n");
    try w.writeAll("  \"commands\": [");

    for (incident.commands.items, 0..) |cmd, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("\n    {");
        try w.print("\"name\":\"{s}\",", .{cmd.name});
        try w.print("\"command\":\"{s}\",", .{cmd.command});
        try w.print("\"started_at\":\"{s}\",", .{cmd.started_at});
        try w.print("\"ended_at\":\"{s}\",", .{cmd.ended_at});
        try w.print("\"exit_code\":{d},", .{cmd.exit_code});
        try w.print("\"output_len\":{d}", .{cmd.output_len});
        try w.writeByte('}');
    }

    if (incident.commands.items.len > 0) try w.writeByte('\n') else try w.writeByte(' ');
    try w.writeAll("]\n}\n");

    const json_path = try std.fs.path.join(allocator, &.{ incident.path, "incident.json" });
    defer allocator.free(json_path);

    try utils.atomicWriteFile(allocator, json_path, buf.items);
}

/// Update incident.json (best-effort; errors are printed but not propagated).
pub fn updateIncidentJson(
    allocator: std.mem.Allocator,
    incident: Incident,
    config: Config,
) void {
    if (config.dry_run) return;
    writeIncidentJson(allocator, incident, config) catch |e| {
        utils.eprint("\x1b[33m[WARN]\x1b[0m Could not update incident.json: {s}\n", .{@errorName(e)});
    };
}

/// Write receipt.adoc (atomic).
pub fn writeReceipt(
    allocator: std.mem.Allocator,
    incident: Incident,
    config: Config,
) !void {
    const receipt_path = try std.fs.path.join(allocator, &.{ incident.path, "receipt.adoc" });
    defer allocator.free(receipt_path);

    const hostname = try getHostname(allocator);
    defer allocator.free(hostname);

    const created_at = try utils.rfc3339FromEpoch(allocator, incident.created_at_epoch);
    defer allocator.free(created_at);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const w = buf.writer(allocator);
    try w.writeAll("= Incident Receipt\n:icons: font\n:toc:\n\n== Summary\n\n|===\n|Field |Value\n\n");
    try w.print("|Incident ID\n|`{s}`\n\n", .{incident.id});
    try w.print("|Created\n|{s}\n\n", .{created_at});
    try w.print("|Hostname\n|{s}\n\n", .{hostname});
    try w.print("|Platform\n|{s} ({s})\n\n", .{ utils.getOsName(), utils.getArch() });
    try w.print("|Dry Run\n|{s}\n", .{if (config.dry_run) "true" else "false"});
    try w.writeAll("|===\n\n== Commands Executed\n\n");

    if (incident.commands.items.len == 0) {
        try w.writeAll("_No commands logged._\n");
    } else {
        try w.writeAll("|===\n|Command |Exit Code |Output Size\n\n");
        for (incident.commands.items) |cmd| {
            try w.print("|{s}\n|{d}\n|{d} bytes\n\n", .{ cmd.name, cmd.exit_code, cmd.output_len });
        }
        try w.writeAll("|===\n");
    }

    try w.writeAll("\n== Log Files\n\n");

    if (config.dry_run) {
        try w.writeAll("_Dry run - no log files created._\n");
    } else {
        var log_dir = std.fs.cwd().openDir(incident.logs_path, .{ .iterate = true }) catch null;
        if (log_dir) |*d| {
            defer d.close();
            var iter = d.iterate();
            var any = false;
            while (iter.next() catch null) |entry| {
                try w.print("* `logs/{s}`\n", .{entry.name});
                any = true;
            }
            if (!any) try w.writeAll("_No log files._\n");
        } else {
            try w.writeAll("_No log files._\n");
        }
    }

    try w.writeAll("\n== Next Steps\n\n");
    try w.writeAll("1. Review the captured diagnostics in the `logs/` directory\n");
    try w.writeAll("2. If issues persist, run specialized tools:\n");
    try w.print("   - `psa crisis --incident {s}`\n", .{incident.path});
    try w.print("   - `ambientops scan --incident {s}`\n", .{incident.path});
    try w.writeAll("3. Report findings via feedback-o-tron\n\n== License\n\nPMPL-1.0-or-later\n");

    if (config.dry_run) {
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would write receipt.adoc\n", .{});
        return;
    }

    try utils.atomicWriteFile(allocator, receipt_path, buf.items);
    utils.print("\x1b[32m[OK]\x1b[0m Written receipt.adoc\n", .{});
}

/// Write evidence envelope (AmbientOps contract).
pub fn writeEvidenceEnvelope(
    allocator: std.mem.Allocator,
    incident: Incident,
    config: Config,
) !void {
    if (config.dry_run) {
        utils.print("\x1b[36m[DRY-RUN]\x1b[0m Would write evidence envelope: envelope.json\n", .{});
        return;
    }

    // Build envelope_id.
    const eid_parts = [_][]const u8{
        try utils.randomHex(allocator, 2),
        try utils.randomHex(allocator, 1),
        try utils.randomHex(allocator, 1),
        try utils.randomHex(allocator, 1),
        try utils.randomHex(allocator, 3),
    };
    defer for (eid_parts) |p| allocator.free(p);
    const eid = try std.fmt.allocPrint(allocator, "{s}-{s}-{s}-{s}-{s}", .{
        eid_parts[0], eid_parts[1], eid_parts[2], eid_parts[3], eid_parts[4],
    });
    defer allocator.free(eid);

    const hostname = try getHostname(allocator);
    defer allocator.free(hostname);

    var buf = std.ArrayList(u8){};
    defer buf.deinit(allocator);

    const w = buf.writer(allocator);
    try w.writeAll("{\n");
    try w.print("  \"version\": \"{s}\",\n", .{SCHEMA_VERSION});
    try w.print("  \"envelope_id\": \"{s}\",\n", .{eid});
    try w.writeAll("  \"source\": {\n");
    try w.writeAll("    \"tool\": \"emergency-button\",\n");
    try w.print("    \"host\": \"{s}\",\n", .{hostname});
    try w.writeAll("    \"profile\": \"default\"\n");
    try w.writeAll("  },\n");
    try w.writeAll("  \"artifacts\": [");

    var any = false;

    // Collect incident.json.
    const inc_json = try std.fs.path.join(allocator, &.{ incident.path, "incident.json" });
    defer allocator.free(inc_json);
    if (std.fs.cwd().statFile(inc_json) catch null) |st| {
        if (any) try w.writeByte(',');
        try w.print(
            "\n    {{\"type\":\"report\",\"path\":\"incident.json\",\"description\":\"Incident manifest\",\"size_bytes\":{d}}}",
            .{st.size},
        );
        any = true;
    }

    // Collect log files.
    var log_dir = std.fs.cwd().openDir(incident.logs_path, .{ .iterate = true }) catch null;
    if (log_dir) |*d| {
        defer d.close();
        var iter = d.iterate();
        while (iter.next() catch null) |entry| {
            const fp = try std.fs.path.join(allocator, &.{ incident.logs_path, entry.name });
            defer allocator.free(fp);
            if (std.fs.cwd().statFile(fp) catch null) |st| {
                if (any) try w.writeByte(',');
                try w.print(
                    "\n    {{\"type\":\"log\",\"path\":\"logs/{s}\",\"description\":\"Captured diagnostic log\",\"size_bytes\":{d}}}",
                    .{ entry.name, st.size },
                );
                any = true;
            }
        }
    }

    if (any) try w.writeByte('\n') else try w.writeByte(' ');
    try w.writeAll("],\n");
    try w.writeAll("  \"findings\": [],\n");
    try w.writeAll("  \"redaction_profile\": \"standard\"\n}\n");

    const ev_path = try std.fs.path.join(allocator, &.{ incident.path, "envelope.json" });
    defer allocator.free(ev_path);

    try utils.atomicWriteFile(allocator, ev_path, buf.items);
    utils.print("\x1b[32m[OK]\x1b[0m Written evidence envelope: envelope.json\n", .{});
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn getHostname(allocator: std.mem.Allocator) ![]u8 {
    var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const name = std.posix.gethostname(&buf) catch return allocator.dupe(u8, "unknown");
    return allocator.dupe(u8, name);
}

fn getUsername(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("USER")) |u| return allocator.dupe(u8, u);
    if (std.posix.getenv("LOGNAME")) |u| return allocator.dupe(u8, u);
    return allocator.dupe(u8, "unknown");
}

fn formatTimestamp(allocator: std.mem.Allocator, epoch_secs: i64) ![]u8 {
    const es = std.time.epoch.EpochSeconds{
        .secs = @as(u64, @intCast(if (epoch_secs < 0) 0 else epoch_secs)),
    };
    const day = es.getEpochDay();
    const ymd = day.calculateYearDay();
    const ym = ymd.calculateMonthDay();
    const ds = es.getDaySeconds();

    return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}", .{
        ymd.year,
        @intFromEnum(ym.month),
        ym.day_index + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    });
}
