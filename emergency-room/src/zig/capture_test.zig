// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// capture_test.zig — Tests for safe diagnostic capture modules.
//
// Corresponds to: src/capture_test.v
//
// These tests must pass on the CI runner without network or root access.
// All assertions about PII redaction are safety-critical: they verify that
// the data-scrubbing invariants hold before any log file is written.

const std = @import("std");
const cap = @import("capture");

test "CaptureResult fields are accessible" {
    const result = cap.CaptureResult{
        .name = "test_capture",
        .success = true,
        .output = "test output",
        .error_msg = "",
        .duration_ms = 100,
    };
    try std.testing.expectEqualStrings("test_capture", result.name);
    try std.testing.expect(result.success);
    try std.testing.expectEqual(@as(i64, 100), result.duration_ms);
}

test "CaptureResult failure fields" {
    const result = cap.CaptureResult{
        .name = "failed_capture",
        .success = false,
        .output = "",
        .error_msg = "Command not found",
        .duration_ms = 50,
    };
    try std.testing.expect(!result.success);
    try std.testing.expectEqualStrings("Command not found", result.error_msg);
}

test "CaptureModule fields are accessible" {
    const cmds = [_][]const u8{ "uname -a", "cat /etc/os-release" };
    const mod = cap.CaptureModule{
        .name = "os_version",
        .display_name = "OS Version",
        .commands = &cmds,
    };
    try std.testing.expectEqualStrings("os_version", mod.name);
    try std.testing.expectEqualStrings("OS Version", mod.display_name);
    try std.testing.expectEqual(@as(usize, 2), mod.commands.len);
}

test "OS version commands are non-empty" {
    const cmds = cap.getOsVersionCommands();
    try std.testing.expect(cmds.len > 0);
}

test "Uptime commands are non-empty" {
    const cmds = cap.getUptimeCommands();
    try std.testing.expect(cmds.len > 0);
}

test "Disk commands are non-empty" {
    const cmds = cap.getDiskCommands();
    try std.testing.expect(cmds.len > 0);
}

test "Process commands are non-empty" {
    const cmds = cap.getProcessCommands();
    try std.testing.expect(cmds.len > 0);
}

// ── PII redaction — safety-critical assertions ────────────────────────────────

test "PII redaction: password=value is redacted" {
    const allocator = std.testing.allocator;
    const input = "password=s3cretValue123";
    const result = try cap.redactPii(allocator, input);
    defer allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "s3cretValue123"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "[REDACTED]"));
}

test "PII redaction: email is redacted" {
    const allocator = std.testing.allocator;
    const input = "Contact user@example.com for details";
    const result = try cap.redactPii(allocator, input);
    defer allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "user@example.com"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "[REDACTED-EMAIL]"));
}

test "PII redaction: SSN is redacted" {
    const allocator = std.testing.allocator;
    const input = "SSN: 123-45-6789";
    const result = try cap.redactPii(allocator, input);
    defer allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "123-45-6789"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "[REDACTED-SSN]"));
}

test "PII redaction: AWS key is redacted" {
    const allocator = std.testing.allocator;
    const input = "AWS key: AKIAIOSFODNN7EXAMPLE";
    const result = try cap.redactPii(allocator, input);
    defer allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "AKIAIOSFODNN7EXAMPLE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "[REDACTED]"));
}

test "PII redaction: GitHub token is redacted" {
    const allocator = std.testing.allocator;
    const input = "token=ghp_ABCDEFabcdef1234567890";
    const result = try cap.redactPii(allocator, input);
    defer allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "ghp_ABCDEFabcdef1234567890"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "[REDACTED]"));
}

test "PII redaction: clean input is unchanged" {
    const allocator = std.testing.allocator;
    const input = "Just a normal log line with no sensitive data";
    const result = try cap.redactPii(allocator, input);
    defer allocator.free(result);
    try std.testing.expectEqualStrings(input, result);
}

test "PII redaction: private key block marker is redacted" {
    const allocator = std.testing.allocator;
    const input = "-----BEGIN RSA PRIVATE KEY-----";
    const result = try cap.redactPii(allocator, input);
    defer allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "RSA PRIVATE KEY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result, 1, "[REDACTED"));
}

test "PII redaction: bearer token is redacted" {
    const allocator = std.testing.allocator;
    const input = "bearer=SuperSecretTokenValue";
    const result = try cap.redactPii(allocator, input);
    defer allocator.free(result);
    try std.testing.expect(!std.mem.containsAtLeast(u8, result, 1, "SuperSecretTokenValue"));
}
