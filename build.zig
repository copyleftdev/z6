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

    // Create z6 module for tests
    const z6_module = b.createModule(.{
        .root_source_file = b.path("src/z6.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Arena allocator tests
    const arena_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/arena_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    arena_tests.root_module.addImport("z6", z6_module);
    const run_arena_tests = b.addRunArtifact(arena_tests);
    test_step.dependOn(&run_arena_tests.step);

    // Pool allocator tests
    const pool_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/pool_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pool_tests.root_module.addImport("z6", z6_module);
    const run_pool_tests = b.addRunArtifact(pool_tests);
    test_step.dependOn(&run_pool_tests.step);

    // Memory budget tests
    const memory_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/memory_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    memory_tests.root_module.addImport("z6", z6_module);
    const run_memory_tests = b.addRunArtifact(memory_tests);
    test_step.dependOn(&run_memory_tests.step);

    // PRNG tests
    const prng_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/prng_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    prng_tests.root_module.addImport("z6", z6_module);
    const run_prng_tests = b.addRunArtifact(prng_tests);
    test_step.dependOn(&run_prng_tests.step);

    // VU tests
    const vu_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/vu_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    vu_tests.root_module.addImport("z6", z6_module);
    const run_vu_tests = b.addRunArtifact(vu_tests);
    test_step.dependOn(&run_vu_tests.step);

    // Scheduler tests
    const scheduler_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/scheduler_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    scheduler_tests.root_module.addImport("z6", z6_module);
    const run_scheduler_tests = b.addRunArtifact(scheduler_tests);
    test_step.dependOn(&run_scheduler_tests.step);

    // Event queue tests
    const event_queue_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/event_queue_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    event_queue_tests.root_module.addImport("z6", z6_module);
    const run_event_queue_tests = b.addRunArtifact(event_queue_tests);
    test_step.dependOn(&run_event_queue_tests.step);

    // Event model tests
    const event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/event_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    event_tests.root_module.addImport("z6", z6_module);
    const run_event_tests = b.addRunArtifact(event_tests);
    test_step.dependOn(&run_event_tests.step);

    // Event log tests
    const event_log_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/event_log_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    event_log_tests.root_module.addImport("z6", z6_module);
    const run_event_log_tests = b.addRunArtifact(event_log_tests);
    test_step.dependOn(&run_event_log_tests.step);

    // Fuzz tests
    const fuzz_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/fuzz/event_serialization_fuzz.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    fuzz_tests.root_module.addImport("z6", z6_module);
    const run_fuzz_tests = b.addRunArtifact(fuzz_tests);
    test_step.dependOn(&run_fuzz_tests.step);

    // Protocol tests
    const protocol_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/protocol_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    protocol_tests.root_module.addImport("z6", z6_module);
    const run_protocol_tests = b.addRunArtifact(protocol_tests);
    test_step.dependOn(&run_protocol_tests.step);

    // HTTP/1.1 Parser tests
    const http1_parser_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/http1_parser_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    http1_parser_tests.root_module.addImport("z6", z6_module);
    const run_http1_parser_tests = b.addRunArtifact(http1_parser_tests);
    test_step.dependOn(&run_http1_parser_tests.step);

    // HTTP/1.1 Handler tests
    const http1_handler_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/http1_handler_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    http1_handler_tests.root_module.addImport("z6", z6_module);
    const run_http1_handler_tests = b.addRunArtifact(http1_handler_tests);
    test_step.dependOn(&run_http1_handler_tests.step);

    // Scenario Parser tests
    const scenario_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/scenario_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    scenario_tests.root_module.addImport("z6", z6_module);
    const run_scenario_tests = b.addRunArtifact(scenario_tests);
    test_step.dependOn(&run_scenario_tests.step);

    // HTTP/2 Frame Parser tests
    const http2_frame_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/http2_frame_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    http2_frame_tests.root_module.addImport("z6", z6_module);
    const run_http2_frame_tests = b.addRunArtifact(http2_frame_tests);
    test_step.dependOn(&run_http2_frame_tests.step);

    // VU Engine tests
    const vu_engine_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/vu_engine_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    vu_engine_tests.root_module.addImport("z6", z6_module);
    const run_vu_engine_tests = b.addRunArtifact(vu_engine_tests);
    test_step.dependOn(&run_vu_engine_tests.step);

    // HTTP/2 HPACK tests
    const http2_hpack_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/http2_hpack_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    http2_hpack_tests.root_module.addImport("z6", z6_module);
    const run_http2_hpack_tests = b.addRunArtifact(http2_hpack_tests);
    test_step.dependOn(&run_http2_hpack_tests.step);

    // HTTP/2 Handler tests
    const http2_handler_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/http2_handler_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    http2_handler_tests.root_module.addImport("z6", z6_module);
    const run_http2_handler_tests = b.addRunArtifact(http2_handler_tests);
    test_step.dependOn(&run_http2_handler_tests.step);

    // HDR Histogram tests
    const hdr_histogram_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/hdr_histogram_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hdr_histogram_tests.root_module.addImport("z6", z6_module);
    const run_hdr_histogram_tests = b.addRunArtifact(hdr_histogram_tests);
    test_step.dependOn(&run_hdr_histogram_tests.step);

    // Metrics Reducer tests
    const metrics_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/metrics_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    metrics_tests.root_module.addImport("z6", z6_module);
    const run_metrics_tests = b.addRunArtifact(metrics_tests);
    test_step.dependOn(&run_metrics_tests.step);

    // Integration tests
    const integration_test_step = b.step("test-integration", "Run integration tests");

    // HTTP/1.1 Handler integration tests
    const http1_handler_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/http1_handler_integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    http1_handler_integration_tests.root_module.addImport("z6", z6_module);
    const run_http1_handler_integration_tests = b.addRunArtifact(http1_handler_integration_tests);
    integration_test_step.dependOn(&run_http1_handler_integration_tests.step);
    test_step.dependOn(&run_http1_handler_integration_tests.step);

    // Determinism integration test
    const determinism_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/determinism_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    determinism_tests.root_module.addImport("z6", z6_module);
    const run_determinism_tests = b.addRunArtifact(determinism_tests);
    integration_test_step.dependOn(&run_determinism_tests.step);
    test_step.dependOn(&run_determinism_tests.step); // Also run with unit tests

    // Scheduler-Event integration test
    const scheduler_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/scheduler_event_integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    scheduler_event_tests.root_module.addImport("z6", z6_module);
    const run_scheduler_event_tests = b.addRunArtifact(scheduler_event_tests);
    integration_test_step.dependOn(&run_scheduler_event_tests.step);
    test_step.dependOn(&run_scheduler_event_tests.step); // Also run with unit tests

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

    // Real scenario integration example
    const real_scenario_test = b.addExecutable(.{
        .name = "real_scenario_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/real_scenario_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    real_scenario_test.root_module.addImport("z6", z6_module);
    b.installArtifact(real_scenario_test);

    const run_real_scenario_test = b.addRunArtifact(real_scenario_test);
    const real_scenario_step = b.step("run-real-scenario", "Run real scenario file integration (Level 5)");
    real_scenario_step.dependOn(&run_real_scenario_test.step);

    // HTTP integration test (real network requests)
    const http_integration_test = b.addExecutable(.{
        .name = "http_integration_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/http_integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    http_integration_test.root_module.addImport("z6", z6_module);
    b.installArtifact(http_integration_test);

    const run_http_integration_test = b.addRunArtifact(http_integration_test);
    const http_integration_step = b.step("run-http-test", "Run real HTTP integration test (Level 6)");
    http_integration_step.dependOn(&run_http_integration_test.step);

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

    // Fuzz targets (TASK-500)
    const fuzz_step = b.step("fuzz-targets", "Build and run all fuzz targets");

    // HTTP/1.1 Parser fuzz tests
    const http1_fuzz = b.addTest(.{
        .name = "http1_parser_fuzz",
        .root_source_file = b.path("tests/fuzz/http1_parser_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    http1_fuzz.root_module.addImport("z6", z6_module);
    const run_http1_fuzz = b.addRunArtifact(http1_fuzz);
    fuzz_step.dependOn(&run_http1_fuzz.step);

    // HTTP/2 Frame Parser fuzz tests
    const http2_fuzz = b.addTest(.{
        .name = "http2_frame_fuzz",
        .root_source_file = b.path("tests/fuzz/http2_frame_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    http2_fuzz.root_module.addImport("z6", z6_module);
    const run_http2_fuzz = b.addRunArtifact(http2_fuzz);
    fuzz_step.dependOn(&run_http2_fuzz.step);

    // HPACK Decoder fuzz tests
    const hpack_fuzz = b.addTest(.{
        .name = "hpack_decoder_fuzz",
        .root_source_file = b.path("tests/fuzz/hpack_decoder_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    hpack_fuzz.root_module.addImport("z6", z6_module);
    const run_hpack_fuzz = b.addRunArtifact(hpack_fuzz);
    fuzz_step.dependOn(&run_hpack_fuzz.step);

    // Scenario Parser fuzz tests
    const scenario_fuzz = b.addTest(.{
        .name = "scenario_parser_fuzz",
        .root_source_file = b.path("tests/fuzz/scenario_parser_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    scenario_fuzz.root_module.addImport("z6", z6_module);
    const run_scenario_fuzz = b.addRunArtifact(scenario_fuzz);
    fuzz_step.dependOn(&run_scenario_fuzz.step);

    // Event Serialization fuzz tests (existing)
    const event_fuzz = b.addTest(.{
        .name = "event_serialization_fuzz",
        .root_source_file = b.path("tests/fuzz/event_serialization_fuzz.zig"),
        .target = target,
        .optimize = optimize,
    });
    event_fuzz.root_module.addImport("z6", z6_module);
    const run_event_fuzz = b.addRunArtifact(event_fuzz);
    fuzz_step.dependOn(&run_event_fuzz.step);

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
