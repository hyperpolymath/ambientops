// SPDX-License-Identifier: AGPL-3.0-or-later
//! Token bucket rate limiter for cloud API compliance

const std = @import("std");

/// Token bucket rate limiter
pub const RateLimiter = struct {
    tokens: f64,
    max_tokens: f64,
    refill_rate: f64,
    last_refill: i64,
    mutex: std.Thread.Mutex,

    pub const Config = struct {
        tps: u32 = 4,
        burst: u32 = 1,
    };

    pub fn init(config: Config) RateLimiter {
        return .{
            .tokens = @floatFromInt(config.burst),
            .max_tokens = @floatFromInt(config.burst),
            .refill_rate = @floatFromInt(config.tps),
            .last_refill = std.time.milliTimestamp(),
            .mutex = .{},
        };
    }

    pub fn acquire(self: *RateLimiter) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.refill();

        if (self.tokens < 1.0) {
            const wait_ns: u64 = @intFromFloat((1.0 - self.tokens) / self.refill_rate * 1e9);
            std.time.sleep(wait_ns);
            self.refill();
        }

        self.tokens -= 1.0;
    }

    fn refill(self: *RateLimiter) void {
        const now = std.time.milliTimestamp();
        const elapsed_ms = now - self.last_refill;
        const elapsed_s: f64 = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;

        self.tokens = @min(self.max_tokens, self.tokens + elapsed_s * self.refill_rate);
        self.last_refill = now;
    }
};
