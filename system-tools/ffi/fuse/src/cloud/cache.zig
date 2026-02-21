// SPDX-License-Identifier: AGPL-3.0-or-later
//! Write-back cache for cloud filesystems

const std = @import("std");

/// Write-back cache for reducing cloud API calls
pub const WriteBackCache = struct {
    allocator: std.mem.Allocator,
    entries: std.StringHashMap(CacheEntry),
    max_age_ns: u64,
    mode: CacheMode,
    mutex: std.Thread.Mutex,

    pub const CacheMode = enum {
        off,
        minimal,
        writes,
        full,
    };

    pub const Config = struct {
        mode: CacheMode = .writes,
        max_age: u64 = 72 * std.time.ns_per_hour,
        max_size: usize = 256 * 1024 * 1024, // 256MB
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) !WriteBackCache {
        return .{
            .allocator = allocator,
            .entries = std.StringHashMap(CacheEntry).init(allocator),
            .max_age_ns = config.max_age,
            .mode = config.mode,
            .mutex = .{},
        };
    }

    pub fn deinit(self: *WriteBackCache) void {
        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
            self.allocator.free(entry.key_ptr.*);
        }
        self.entries.deinit();
    }

    /// Get cached data for a file region
    pub fn get(self: *WriteBackCache, path: []const u8, offset: u64, buf: []u8) ?usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const entry = self.entries.get(path) orelse return null;

        // Check if expired
        const now = std.time.nanoTimestamp();
        if (now - entry.timestamp > @as(i128, self.max_age_ns)) {
            return null;
        }

        // Check if requested region is in cache
        if (offset >= entry.data.len) return null;

        const available = entry.data.len - offset;
        const to_copy = @min(buf.len, available);
        @memcpy(buf[0..to_copy], entry.data[offset..][0..to_copy]);

        return to_copy;
    }

    /// Write data to cache (async flush to backend)
    pub fn write(self: *WriteBackCache, path: []const u8, data: []const u8, offset: u64) !usize {
        self.mutex.lock();
        defer self.mutex.unlock();

        const path_copy = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_copy);

        // Simple implementation: cache whole file
        const data_copy = try self.allocator.dupe(u8, data);
        errdefer self.allocator.free(data_copy);

        try self.entries.put(path_copy, .{
            .data = data_copy,
            .offset = offset,
            .timestamp = std.time.nanoTimestamp(),
            .dirty = true,
        });

        return data.len;
    }

    /// Flush dirty entries to backend
    pub fn flush(self: *WriteBackCache, backend: anytype) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var iter = self.entries.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.dirty) {
                try backend.write(entry.key_ptr.*, entry.value_ptr.data, entry.value_ptr.offset);
                entry.value_ptr.dirty = false;
            }
        }
    }
};

const CacheEntry = struct {
    data: []u8,
    offset: u64,
    timestamp: i128,
    dirty: bool,
};
