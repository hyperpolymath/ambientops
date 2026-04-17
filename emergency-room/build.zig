// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// build.zig — Zig build script for emergency-room.
//
// Produces the `emergency-button` binary (matching the artifact name in main.v
// and the Rust build in emergency-room/rust/).
//
// Requires Zig 0.15.2+.
//
// Usage:
//   zig build                          Compile the binary
//   zig build run -- --help            Compile and run with --help
//   zig build test                     Run all unit and integration tests
//   zig build -Doptimize=ReleaseSafe   Release build with safety checks

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target   = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ── Modules ────────────────────────────────────────────────────────────────
    // Each source file is its own module so test executables can import them
    // individually without dragging in main.zig.

    const utils_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/utils.zig"),
        .target           = target,
        .optimize         = optimize,
    });

    const capture_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/capture.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    capture_mod.addImport("utils", utils_mod);

    const incident_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/incident.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    incident_mod.addImport("utils", utils_mod);

    const handoff_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/handoff.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    handoff_mod.addImport("utils",    utils_mod);
    handoff_mod.addImport("incident", incident_mod);

    const backup_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/backup.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    backup_mod.addImport("utils",    utils_mod);
    backup_mod.addImport("incident", incident_mod);

    const boot_guardian_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/boot_guardian.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    boot_guardian_mod.addImport("utils",    utils_mod);
    boot_guardian_mod.addImport("incident", incident_mod);
    boot_guardian_mod.addImport("capture",  capture_mod);

    const shutdown_marshal_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/shutdown_marshal.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    shutdown_marshal_mod.addImport("utils",    utils_mod);
    shutdown_marshal_mod.addImport("incident", incident_mod);

    // ── Main executable module ────────────────────────────────────────────────

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .target           = target,
        .optimize         = optimize,
    });
    main_mod.addImport("utils",           utils_mod);
    main_mod.addImport("capture",         capture_mod);
    main_mod.addImport("incident",        incident_mod);
    main_mod.addImport("handoff",         handoff_mod);
    main_mod.addImport("backup",          backup_mod);
    main_mod.addImport("boot_guardian",   boot_guardian_mod);
    main_mod.addImport("shutdown_marshal", shutdown_marshal_mod);

    // ── Executable ─────────────────────────────────────────────────────────────

    const exe = b.addExecutable(.{
        .name        = "emergency-button",
        .root_module = main_mod,
    });
    b.installArtifact(exe);

    // ── Run step ───────────────────────────────────────────────────────────────

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run emergency-button");
    run_step.dependOn(&run_cmd.step);

    // ── Test step ──────────────────────────────────────────────────────────────

    const test_step = b.step("test", "Run all tests");

    // Each test file gets its own module so it can import the production modules.
    const test_srcs = [_]struct { src: []const u8 }{
        .{ .src = "src/zig/capture_test.zig" },
        .{ .src = "src/zig/incident_test.zig" },
        .{ .src = "src/zig/integration_test.zig" },
    };

    for (test_srcs) |ts| {
        const t_mod = b.createModule(.{
            .root_source_file = b.path(ts.src),
            .target           = target,
            .optimize         = optimize,
        });
        t_mod.addImport("utils",    utils_mod);
        t_mod.addImport("capture",  capture_mod);
        t_mod.addImport("incident", incident_mod);
        t_mod.addImport("handoff",  handoff_mod);
        t_mod.addImport("backup",   backup_mod);

        const t = b.addTest(.{ .root_module = t_mod });
        const run_t = b.addRunArtifact(t);
        test_step.dependOn(&run_t.step);
    }
}
