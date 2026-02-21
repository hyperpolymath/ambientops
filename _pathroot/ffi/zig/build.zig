// build.zig
// Build system for pathroot ABI Zig FFI
// SPDX-License-Identifier: PMPL-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build shared library for Ada FFI
    const lib = b.addSharedLibrary(.{
        .name = "pathroot_abi",
        .root_source_file = b.path("src/symlink.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Install to lib/ directory
    b.installArtifact(lib);

    // Unit tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/symlink.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // Default build step
    const build_step = b.step("build", "Build the FFI library");
    build_step.dependOn(&lib.step);
}
