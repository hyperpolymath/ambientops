// SPDX-License-Identifier: AGPL-3.0-or-later
//! Read-ahead prefetcher for cloud filesystems

const std = @import("std");

/// Read-ahead prefetcher
pub const Prefetcher = struct {
    allocator: std.mem.Allocator,
    chunk_size: usize,
    lookahead: usize,
    cache: std.StringHashMap(PrefetchEntry),
    mutex: std.Thread.Mutex,

    pub const Config = struct {
        chunk_size: usize = 32 * 1024 * 1024, // 32MB
        lookahead: usize = 2, // Prefetch 2 chunks ahead
    };

    pub fn init(allocator: std.mem.Allocator, config: Config) Prefetcher {
        return .{
            .allocator = allocator,
            .chunk_size = config.chunk_size,
            .lookahead = config.lookahead,
            .cache = std.StringHashMap(PrefetchEntry).init(allocator),
            .mutex = .{},
        };
    }

    pub fn deinit(self: *Prefetcher) void {
        var iter = self.cache.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.value_ptr.data);
            self.allocator.free(entry.key_ptr.*);
        }
        self.cache.deinit();
    }

    /// Notify prefetcher of a read operation (triggers prefetch)
    pub fn onRead(self: *Prefetcher, path: []const u8, offset: u64, backend: anytype) void {
        _ = self;
        _ = path;
        _ = offset;
        _ = backend;
        // TODO: Spawn async prefetch of next chunks
    }

    /// Get prefetched data if available
    pub fn get(self: *Prefetcher, path: []const u8, offset: u64) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const key = makeCacheKey(self.allocator, path, offset) catch return null;
        defer self.allocator.free(key);

        const entry = self.cache.get(key) orelse return null;
        return entry.data;
    }

    fn makeCacheKey(allocator: std.mem.Allocator, path: []const u8, offset: u64) ![]u8 {
        return std.fmt.allocPrint(allocator, "{s}:{d}", .{ path, offset });
    }
};

const PrefetchEntry = struct {
    data: []u8,
    offset: u64,
    timestamp: i128,
};
