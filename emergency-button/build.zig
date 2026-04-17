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

/// Path to the directory containing libzig_api.a (from developer-ecosystem/zig-api).
const DEFAULT_ZIG_API_LIB_PATH =
    "/var/mnt/eclipse/repos/developer-ecosystem/zig-api/ffi/zig/zig-out/lib";

/// Path to the directory containing zig_api.h.
const DEFAULT_ZIG_API_INCLUDE_PATH =
    "/var/mnt/eclipse/repos/developer-ecosystem/zig-api/generated/abi";

/// Path to the directory containing libproven_ffi.a (transitive dep of libzig_api).
/// Points to proven's standard zig-out/lib output (zig-out-standalone symlink removed 2026-04-17).
const DEFAULT_PROVEN_LIB_PATH =
    "/var/mnt/eclipse/repos/verification-ecosystem/proven/ffi/zig/zig-out/lib";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Allow callers to override library paths (for CI).
    const zig_api_lib_path = b.option(
        []const u8,
        "zig-api-lib-path",
        "Directory containing libzig_api.a (default: " ++ DEFAULT_ZIG_API_LIB_PATH ++ ")",
    ) orelse DEFAULT_ZIG_API_LIB_PATH;

    const zig_api_include_path = b.option(
        []const u8,
        "zig-api-include-path",
        "Directory containing zig_api.h (default: " ++ DEFAULT_ZIG_API_INCLUDE_PATH ++ ")",
    ) orelse DEFAULT_ZIG_API_INCLUDE_PATH;

    const proven_lib_path = b.option(
        []const u8,
        "proven-lib-path",
        "Directory containing libproven_ffi.a (transitive; default: " ++ DEFAULT_PROVEN_LIB_PATH ++ ")",
    ) orelse DEFAULT_PROVEN_LIB_PATH;

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
        .link_libc = true,
    });
    backup_mod.addLibraryPath(.{ .cwd_relative = zig_api_lib_path });
    backup_mod.addIncludePath(.{ .cwd_relative = zig_api_include_path });
    backup_mod.linkSystemLibrary("zig_api", .{});
    // libzig_api.a references proven_path_has_traversal from libproven_ffi.
    backup_mod.addLibraryPath(.{ .cwd_relative = proven_lib_path });
    backup_mod.linkSystemLibrary("proven_ffi", .{});

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
        .link_libc = true,
    });
    main_mod.addLibraryPath(.{ .cwd_relative = zig_api_lib_path });
    main_mod.addIncludePath(.{ .cwd_relative = zig_api_include_path });
    main_mod.linkSystemLibrary("zig_api", .{});
    // libzig_api.a references proven_path_has_traversal from libproven_ffi.
    main_mod.addLibraryPath(.{ .cwd_relative = proven_lib_path });
    main_mod.linkSystemLibrary("proven_ffi", .{});

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
        const backup_test_mod = b.createModule(.{
            .root_source_file = b.path("src/zig/backup.zig"),
            .imports = &.{
                .{ .name = "utils", .module = utils_mod },
                .{ .name = "incident", .module = incident_mod },
            },
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        backup_test_mod.addLibraryPath(.{ .cwd_relative = zig_api_lib_path });
        backup_test_mod.addIncludePath(.{ .cwd_relative = zig_api_include_path });
        backup_test_mod.linkSystemLibrary("zig_api", .{});
        backup_test_mod.addLibraryPath(.{ .cwd_relative = proven_lib_path });
        backup_test_mod.linkSystemLibrary("proven_ffi", .{});
        const t = b.addTest(.{ .root_module = backup_test_mod });
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
        const integ_test_mod = b.createModule(.{
            .root_source_file = b.path("src/zig/integration_test.zig"),
            .imports = &.{
                .{ .name = "utils", .module = utils_mod },
                .{ .name = "incident", .module = incident_mod },
                .{ .name = "handoff", .module = handoff_mod },
                .{ .name = "backup", .module = backup_mod },
            },
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        integ_test_mod.addLibraryPath(.{ .cwd_relative = zig_api_lib_path });
        integ_test_mod.addIncludePath(.{ .cwd_relative = zig_api_include_path });
        integ_test_mod.linkSystemLibrary("zig_api", .{});
        integ_test_mod.addLibraryPath(.{ .cwd_relative = proven_lib_path });
        integ_test_mod.linkSystemLibrary("proven_ffi", .{});
        const t = b.addTest(.{ .root_module = integ_test_mod });
        const r = b.addRunArtifact(t);
        run_test_step.dependOn(&r.step);
        integ_step.dependOn(&r.step);
    }
}
