// SPDX-License-Identifier: AGPL-3.0-or-later
//! Zig FFI bindings for systemd (sd-bus, sd-journal)
//!
//! Provides direct D-Bus communication with systemd and journal access,
//! replacing subprocess calls to systemctl/journalctl.
//!
//! C-free: Uses extern "C" declarations linking to Rust shim.
//! No @cImport, no C headers at build time.

const std = @import("std");

// =============================================================================
// Systemd extern declarations (C ABI via Rust shim)
// =============================================================================

// Opaque types
const sd_bus = opaque {};
const sd_bus_message = opaque {};
const sd_journal = opaque {};

// sd-bus error struct (simplified)
const sd_bus_error = extern struct {
    name: ?[*:0]const u8,
    message: ?[*:0]const u8,
    need_free: c_int,
};

// Constants
const SD_BUS_ERROR_NULL: sd_bus_error = .{ .name = null, .message = null, .need_free = 0 };
const SD_JOURNAL_LOCAL_ONLY: c_int = 1;

// Rust shim functions (from libsystemd_shim.so)
extern "C" fn systemd_shim_bus_open_system(bus: *?*sd_bus) c_int;
extern "C" fn systemd_shim_bus_unref(bus: *sd_bus) ?*sd_bus;
extern "C" fn systemd_shim_bus_get_property_string(
    bus: *sd_bus,
    destination: [*:0]const u8,
    path: [*:0]const u8,
    interface: [*:0]const u8,
    member: [*:0]const u8,
    err: *sd_bus_error,
    out_value: *?[*:0]u8,
) c_int;
extern "C" fn systemd_shim_bus_error_free(err: *sd_bus_error) void;
extern "C" fn systemd_shim_free_string(s: [*:0]u8) void;

extern "C" fn systemd_shim_journal_open(journal: *?*sd_journal, flags: c_int) c_int;
extern "C" fn systemd_shim_journal_close(journal: *sd_journal) void;
extern "C" fn systemd_shim_journal_add_match(
    journal: *sd_journal,
    data: [*]const u8,
    len: usize,
) c_int;
extern "C" fn systemd_shim_journal_seek_tail(journal: *sd_journal) c_int;
extern "C" fn systemd_shim_journal_previous(journal: *sd_journal) c_int;
extern "C" fn systemd_shim_journal_next(journal: *sd_journal) c_int;
extern "C" fn systemd_shim_journal_get_data(
    journal: *sd_journal,
    field: [*:0]const u8,
    data: *?[*]const u8,
    len: *usize,
) c_int;

// =============================================================================
// Zig API
// =============================================================================

pub const Error = error{
    BusConnectionFailed,
    MessageFailed,
    CallFailed,
    JournalOpenFailed,
    JournalSeekFailed,
    AllocationFailed,
};

/// Unit active state
pub const ActiveState = enum {
    active,
    reloading,
    inactive,
    failed,
    activating,
    deactivating,
    maintenance,
    unknown,

    pub fn fromString(s: []const u8) ActiveState {
        if (std.mem.eql(u8, s, "active")) return .active;
        if (std.mem.eql(u8, s, "reloading")) return .reloading;
        if (std.mem.eql(u8, s, "inactive")) return .inactive;
        if (std.mem.eql(u8, s, "failed")) return .failed;
        if (std.mem.eql(u8, s, "activating")) return .activating;
        if (std.mem.eql(u8, s, "deactivating")) return .deactivating;
        if (std.mem.eql(u8, s, "maintenance")) return .maintenance;
        return .unknown;
    }
};

/// Unit status information
pub const UnitStatus = struct {
    name: []const u8,
    description: []const u8,
    load_state: []const u8,
    active_state: ActiveState,
    sub_state: []const u8,

    pub fn isRunning(self: UnitStatus) bool {
        return self.active_state == .active;
    }
};

/// D-Bus connection handle
pub const Bus = struct {
    bus: *sd_bus,

    pub fn connectSystem() Error!Bus {
        var bus: ?*sd_bus = null;
        if (systemd_shim_bus_open_system(&bus) < 0) {
            return Error.BusConnectionFailed;
        }
        return Bus{ .bus = bus.? };
    }

    pub fn close(self: *Bus) void {
        _ = systemd_shim_bus_unref(self.bus);
    }

    /// Get unit active state
    pub fn getUnitActiveState(self: *Bus, allocator: std.mem.Allocator, unit_name: []const u8) Error!ActiveState {
        const unit_z = allocator.dupeZ(u8, unit_name) catch return Error.AllocationFailed;
        defer allocator.free(unit_z);

        var err: sd_bus_error = SD_BUS_ERROR_NULL;
        defer systemd_shim_bus_error_free(&err);

        // Build object path: /org/freedesktop/systemd1/unit/...
        var path_buf: [512]u8 = undefined;
        const escaped = escapeUnitName(unit_name);
        const path = std.fmt.bufPrint(&path_buf, "/org/freedesktop/systemd1/unit/{s}", .{escaped}) catch return Error.AllocationFailed;
        const path_z = allocator.dupeZ(u8, path) catch return Error.AllocationFailed;
        defer allocator.free(path_z);

        var state_ptr: ?[*:0]u8 = null;
        if (systemd_shim_bus_get_property_string(
            self.bus,
            "org.freedesktop.systemd1",
            path_z.ptr,
            "org.freedesktop.systemd1.Unit",
            "ActiveState",
            &err,
            &state_ptr,
        ) < 0) {
            return Error.CallFailed;
        }

        if (state_ptr) |s| {
            defer systemd_shim_free_string(s);
            return ActiveState.fromString(std.mem.span(s));
        }

        return Error.CallFailed;
    }

    /// Check if unit is active
    pub fn isUnitActive(self: *Bus, allocator: std.mem.Allocator, unit_name: []const u8) Error!bool {
        const state = try self.getUnitActiveState(allocator, unit_name);
        return state == .active;
    }
};

/// Journal reader handle
pub const Journal = struct {
    journal: *sd_journal,

    pub fn open() Error!Journal {
        var j: ?*sd_journal = null;
        if (systemd_shim_journal_open(&j, SD_JOURNAL_LOCAL_ONLY) < 0) {
            return Error.JournalOpenFailed;
        }
        return Journal{ .journal = j.? };
    }

    pub fn close(self: *Journal) void {
        systemd_shim_journal_close(self.journal);
    }

    /// Add a match filter
    pub fn addMatch(self: *Journal, allocator: std.mem.Allocator, match: []const u8) Error!void {
        _ = allocator;
        _ = systemd_shim_journal_add_match(self.journal, match.ptr, match.len);
    }

    /// Seek to end of journal
    pub fn seekTail(self: *Journal) Error!void {
        if (systemd_shim_journal_seek_tail(self.journal) < 0) {
            return Error.JournalSeekFailed;
        }
    }

    /// Move to previous entry
    pub fn previous(self: *Journal) bool {
        return systemd_shim_journal_previous(self.journal) > 0;
    }

    /// Move to next entry
    pub fn next(self: *Journal) bool {
        return systemd_shim_journal_next(self.journal) > 0;
    }

    /// Get message from current entry
    pub fn getMessage(self: *Journal) ?[]const u8 {
        var data: ?[*]const u8 = null;
        var len: usize = 0;
        if (systemd_shim_journal_get_data(self.journal, "MESSAGE", &data, &len) < 0) {
            return null;
        }
        // Skip "MESSAGE=" prefix (8 bytes)
        if (data) |d| {
            if (len > 8) {
                return d[8..len];
            }
        }
        return null;
    }
};

/// Escape unit name for D-Bus object path
fn escapeUnitName(name: []const u8) []const u8 {
    // TODO: Proper escaping (replace - with _2d, etc.)
    // For now, just return as-is for simple names
    return name;
}

// =============================================================================
// C FFI exports
// =============================================================================

var global_allocator: std.mem.Allocator = std.heap.c_allocator;

export fn systemd_bus_connect() ?*Bus {
    const bus = Bus.connectSystem() catch return null;
    const ptr = global_allocator.create(Bus) catch return null;
    ptr.* = bus;
    return ptr;
}

export fn systemd_bus_close(bus: *Bus) void {
    bus.close();
    global_allocator.destroy(bus);
}

export fn systemd_is_unit_active(bus: *Bus, unit_name: [*:0]const u8) bool {
    return bus.isUnitActive(global_allocator, std.mem.span(unit_name)) catch false;
}

export fn systemd_journal_open() ?*Journal {
    const journal = Journal.open() catch return null;
    const ptr = global_allocator.create(Journal) catch return null;
    ptr.* = journal;
    return ptr;
}

export fn systemd_journal_close(journal: *Journal) void {
    journal.close();
    global_allocator.destroy(journal);
}

export fn systemd_journal_add_match(journal: *Journal, match: [*:0]const u8) void {
    journal.addMatch(global_allocator, std.mem.span(match)) catch {};
}

export fn systemd_journal_next(journal: *Journal) bool {
    return journal.next();
}

export fn systemd_journal_get_message(journal: *Journal) ?[*:0]const u8 {
    const msg = journal.getMessage() orelse return null;
    // Note: This returns a pointer to internal buffer, valid until next() is called
    return @ptrCast(msg.ptr);
}

// =============================================================================
// Tests
// =============================================================================

test "ActiveState.fromString" {
    try std.testing.expect(ActiveState.fromString("active") == .active);
    try std.testing.expect(ActiveState.fromString("failed") == .failed);
    try std.testing.expect(ActiveState.fromString("unknown_state") == .unknown);
}
