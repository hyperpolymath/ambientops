// SPDX-License-Identifier: AGPL-3.0-or-later
//! Build configuration for zig-systemd-ffi
//!
//! Requires systemd development libraries:
//! - Fedora: sudo dnf install systemd-devel
//! - Ubuntu: sudo apt install libsystemd-dev
//! - Arch: sudo pacman -S systemd-libs

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "zig-systemd-ffi",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.linkSystemLibrary("systemd");
    lib.linkLibC();

    b.installArtifact(lib);

    // Shared library for FFI consumers
    const shared_lib = b.addSharedLibrary(.{
        .name = "systemd_ffi",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    shared_lib.linkSystemLibrary("systemd");
    shared_lib.linkLibC();

    b.installArtifact(shared_lib);

    // Tests
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    unit_tests.linkSystemLibrary("systemd");
    unit_tests.linkLibC();

    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
