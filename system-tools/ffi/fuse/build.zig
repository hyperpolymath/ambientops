// SPDX-License-Identifier: AGPL-3.0-or-later
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library
    const lib = b.addStaticLibrary(.{
        .name = "zig-fuse-ext",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link libfuse3
    lib.linkSystemLibrary("fuse3");
    lib.linkLibC();

    b.installArtifact(lib);

    // Tests
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    // Example: hello filesystem
    const hello_example = b.addExecutable(.{
        .name = "hello-fs",
        .root_source_file = b.path("examples/hello.zig"),
        .target = target,
        .optimize = optimize,
    });
    hello_example.root_module.addImport("fuse", &lib.root_module);
    hello_example.linkSystemLibrary("fuse3");
    hello_example.linkLibC();

    const run_hello = b.addRunArtifact(hello_example);
    const hello_step = b.step("example-hello", "Run hello filesystem example");
    hello_step.dependOn(&run_hello.step);
}
