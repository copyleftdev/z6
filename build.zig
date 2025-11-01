const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main executable
    const exe = b.addExecutable(.{
        .name = "z6",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
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
}
