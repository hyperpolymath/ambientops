// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// build.zig — Zig build script for emergency-button (Zig 0.15.2).
//
// Replaces the V build system (v.mod, v run) following the V-lang ban
// (2026-04-10).  The Idris2 ABI definitions in src/abi/ and the legacy FFI
// library in ffi/zig/ are separate build targets and are not rebuilt here.
//
// TARGETS
//   zig build                → emergency-button executable
//   zig build run            → build + run (passes remaining args)
//   zig build test           → unit + integration tests
//   zig build test-unit      → module-embedded tests only
//   zig build test-integ     → integration_test.zig only

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // -------------------------------------------------------------------------
    // Modules: one per source file, with explicit import wiring.
    // -------------------------------------------------------------------------
    const utils_mod = b.addModule("utils", .{
        .root_source_file = b.path("src/zig/utils.zig"),
        .target = target,
        .optimize = optimize,
    });

    const incident_mod = b.addModule("incident", .{
        .root_source_file = b.path("src/zig/incident.zig"),
        .imports = &.{.{ .name = "utils", .module = utils_mod }},
        .target = target,
        .optimize = optimize,
    });

    const capture_mod = b.addModule("capture", .{
        .root_source_file = b.path("src/zig/capture.zig"),
        .imports = &.{
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "incident", .module = incident_mod },
        },
        .target = target,
        .optimize = optimize,
    });

    const handoff_mod = b.addModule("handoff", .{
        .root_source_file = b.path("src/zig/handoff.zig"),
        .imports = &.{
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "incident", .module = incident_mod },
        },
        .target = target,
        .optimize = optimize,
    });

    const backup_mod = b.addModule("backup", .{
        .root_source_file = b.path("src/zig/backup.zig"),
        .imports = &.{
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "incident", .module = incident_mod },
        },
        .target = target,
        .optimize = optimize,
    });

    // Main module — wires in all imports for main.zig.
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/zig/main.zig"),
        .imports = &.{
            .{ .name = "utils", .module = utils_mod },
            .{ .name = "incident", .module = incident_mod },
            .{ .name = "capture", .module = capture_mod },
            .{ .name = "handoff", .module = handoff_mod },
            .{ .name = "backup", .module = backup_mod },
        },
        .target = target,
        .optimize = optimize,
    });

    // -------------------------------------------------------------------------
    // Executable.
    // -------------------------------------------------------------------------
    const exe = b.addExecutable(.{
        .name = "emergency-button",
        .root_module = main_mod,
    });
    b.installArtifact(exe);

    // `zig build run -- [args]`
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |user_args| run_cmd.addArgs(user_args);
    const run_step = b.step("run", "Run emergency-button");
    run_step.dependOn(&run_cmd.step);

    // -------------------------------------------------------------------------
    // Tests.
    // -------------------------------------------------------------------------

    // Helper to make test modules (same import tree as the source module).
    const run_test_step = b.step("test", "Run all tests (unit + integration)");
    const unit_step = b.step("test-unit", "Run module unit tests only");
    const integ_step = b.step("test-integ", "Run integration tests only");

    // utils
    {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zig/utils.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        unit_step.dependOn(&r.step);
    }
    // incident (module-embedded tests)
    {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zig/incident.zig"),
                .imports = &.{.{ .name = "utils", .module = utils_mod }},
                .target = target,
                .optimize = optimize,
            }),
        });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        unit_step.dependOn(&r.step);
    }
    // capture (module-embedded tests)
    {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zig/capture.zig"),
                .imports = &.{
                    .{ .name = "utils", .module = utils_mod },
                    .{ .name = "incident", .module = incident_mod },
                },
                .target = target,
                .optimize = optimize,
            }),
        });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        unit_step.dependOn(&r.step);
    }
    // handoff (module-embedded tests)
    {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zig/handoff.zig"),
                .imports = &.{
                    .{ .name = "utils", .module = utils_mod },
                    .{ .name = "incident", .module = incident_mod },
                },
                .target = target,
                .optimize = optimize,
            }),
        });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        unit_step.dependOn(&r.step);
    }
    // backup (module-embedded tests)
    {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zig/backup.zig"),
                .imports = &.{
                    .{ .name = "utils", .module = utils_mod },
                    .{ .name = "incident", .module = incident_mod },
                },
                .target = target,
                .optimize = optimize,
            }),
        });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        unit_step.dependOn(&r.step);
    }
    // incident_test.zig (ported V test file)
    {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zig/incident_test.zig"),
                .imports = &.{
                    .{ .name = "utils", .module = utils_mod },
                    .{ .name = "incident", .module = incident_mod },
                },
                .target = target,
                .optimize = optimize,
            }),
        });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        unit_step.dependOn(&r.step);
    }
    // capture_test.zig (ported V test file)
    {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zig/capture_test.zig"),
                .imports = &.{
                    .{ .name = "utils", .module = utils_mod },
                    .{ .name = "capture", .module = capture_mod },
                },
                .target = target,
                .optimize = optimize,
            }),
        });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        unit_step.dependOn(&r.step);
    }
    // integration_test.zig (ported V integration test file)
    {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/zig/integration_test.zig"),
                .imports = &.{
                    .{ .name = "utils", .module = utils_mod },
                    .{ .name = "incident", .module = incident_mod },
                    .{ .name = "handoff", .module = handoff_mod },
                    .{ .name = "backup", .module = backup_mod },
                },
                .target = target,
                .optimize = optimize,
            }),
        });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        integ_step.dependOn(&r.step);
    }
}
