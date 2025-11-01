const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const static = b.option(bool, "static", "Build fully static binary") orelse false;
    const strip = b.option(bool, "strip", "Strip debug symbols") orelse false;
    const lto = b.option(bool, "lto", "Enable link-time optimization") orelse false;
    const coverage = b.option(bool, "coverage", "Generate coverage report") orelse false;

    // Main executable
    const exe = b.addExecutable(.{
        .name = "z6",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Apply build options
    if (static) {
        exe.linkage = .static;
    }
    if (strip) {
        exe.root_module.strip = true;
    }
    if (lto) {
        exe.want_lto = true;
    }

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Unit tests
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Integration tests (placeholder for TASK-100+)
    const integration_test_step = b.step("test-integration", "Run integration tests");
    // TODO: Add integration tests when implemented

    // All tests
    const test_all_step = b.step("test-all", "Run all tests");
    test_all_step.dependOn(test_step);
    test_all_step.dependOn(integration_test_step);

    // Check-assertions tool
    const check_assertions = b.addExecutable(.{
        .name = "check-assertions",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check-assertions.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    b.installArtifact(check_assertions);

    // Check-bounded-loops tool
    const check_bounded_loops = b.addExecutable(.{
        .name = "check-bounded-loops",
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check-bounded-loops.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });
    b.installArtifact(check_bounded_loops);

    // Build all tools
    const tools_step = b.step("tools", "Build all Tiger Style validation tools");
    tools_step.dependOn(&b.addInstallArtifact(check_assertions, .{}).step);
    tools_step.dependOn(&b.addInstallArtifact(check_bounded_loops, .{}).step);

    // Test checker tools
    const check_assertions_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check-assertions.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const check_bounded_loops_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("scripts/check-bounded-loops.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_checker_tests = b.addRunArtifact(check_assertions_tests);
    const run_loop_tests = b.addRunArtifact(check_bounded_loops_tests);
    test_step.dependOn(&run_checker_tests.step);
    test_step.dependOn(&run_loop_tests.step);

    // Fuzz targets (placeholder for TASK-300+)
    _ = b.step("fuzz-targets", "Build all fuzz targets");
    // TODO: Add fuzz targets when parsers are implemented:
    // - fuzz_http1_response
    // - fuzz_http2_frame
    // - fuzz_event_serialization

    // Documentation generation (placeholder for TASK-400+)
    _ = b.step("docs", "Generate documentation");
    // TODO: Implement documentation generation when API is stable

    // Build information
    if (b.verbose) {
        std.debug.print("\n🐅 Z6 Build Configuration\n", .{});
        std.debug.print("========================\n", .{});
        std.debug.print("Target: {s}\n", .{@tagName(target.result.os.tag)});
        std.debug.print("Optimize: {s}\n", .{@tagName(optimize)});
        std.debug.print("Static: {any}\n", .{static});
        std.debug.print("Strip: {any}\n", .{strip});
        std.debug.print("LTO: {any}\n", .{lto});
        std.debug.print("Coverage: {any}\n\n", .{coverage});
    }
}
