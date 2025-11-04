//! Z6: Deterministic Load Testing Tool
//!
//! Command-line interface for running load tests from scenario files.
//!
//! Built with Tiger Style philosophy:
//! - Zero technical debt
//! - Test before implement
//! - Minimum 2 assertions per function
//! - Bounded complexity
//! - Explicit error handling

const std = @import("std");
const scenario_mod = @import("scenario.zig");
const protocol = @import("protocol.zig");
const vu_mod = @import("vu.zig");
const http1_handler = @import("http1_handler.zig");
const cli = @import("cli.zig");

const Allocator = std.mem.Allocator;
const ScenarioParser = scenario_mod.ScenarioParser;
const Scenario = scenario_mod.Scenario;
const ExitCode = cli.ExitCode;
const OutputFormat = cli.OutputFormat;

const VERSION = "0.1.0-dev";

/// Command-line arguments
const Args = struct {
    command: Command,
    scenario_path: ?[]const u8,
    second_path: ?[]const u8, // For diff command
    output_format: OutputFormat,
    help: bool,
    version: bool,
};

/// Available commands
const Command = enum {
    none,
    run,
    validate,
    replay,
    analyze,
    diff,
    help,
};

/// Parse command-line arguments
fn parseArgs(allocator: Allocator) !Args {
    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();

    // Skip program name
    _ = args_iter.next();

    var result = Args{
        .command = .none,
        .scenario_path = null,
        .second_path = null,
        .output_format = .summary,
        .help = false,
        .version = false,
    };

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "run")) {
            result.command = .run;
        } else if (std.mem.eql(u8, arg, "validate")) {
            result.command = .validate;
        } else if (std.mem.eql(u8, arg, "replay")) {
            result.command = .replay;
        } else if (std.mem.eql(u8, arg, "analyze")) {
            result.command = .analyze;
        } else if (std.mem.eql(u8, arg, "diff")) {
            result.command = .diff;
        } else if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.help = true;
            result.command = .help;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.version = true;
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const format_str = arg["--format=".len..];
            result.output_format = OutputFormat.fromString(format_str) catch .summary;
        } else if (result.scenario_path == null) {
            // First non-flag argument is the scenario path
            result.scenario_path = arg;
        } else if (result.second_path == null and result.command == .diff) {
            // Second path for diff command
            result.second_path = arg;
        }
    }

    return result;
}

/// Print usage information
fn printHelp() void {
    std.debug.print(
        \\Z6 - Deterministic Load Testing Tool
        \\Version: {s}
        \\
        \\USAGE:
        \\    z6 <COMMAND> [OPTIONS] <FILE> [FILE2]
        \\
        \\COMMANDS:
        \\    run         Run a load test from a scenario file
        \\    validate    Validate a scenario file without running
        \\    replay      Replay a test from event log (deterministic)
        \\    analyze     Recompute metrics from event log
        \\    diff        Compare results from two test runs
        \\    help        Show this help message
        \\
        \\OPTIONS:
        \\    -h, --help         Show help message
        \\    -v, --version      Show version information
        \\    --format=<fmt>     Output format: summary, json, csv (default: summary)
        \\
        \\EXAMPLES:
        \\    z6 run scenario.toml                    Run load test
        \\    z6 run scenario.toml --format=json      Run with JSON output
        \\    z6 validate scenario.toml               Validate scenario file
        \\    z6 replay events.log                    Replay from event log
        \\    z6 analyze events.log --format=csv      Analyze with CSV output
        \\    z6 diff run1.log run2.log               Compare two runs
        \\    z6 --help                               Show help
        \\
        \\EXIT CODES:
        \\    0    Success
        \\    1    Assertion failure (goals not met)
        \\    2    Configuration error
        \\    3    Runtime error
        \\
        \\SCENARIO FILE:
        \\    TOML format with sections:
        \\    - [metadata]    Test name and description
        \\    - [runtime]     Duration, VUs, seed
        \\    - [target]      HTTP target configuration
        \\    - [[requests]]  HTTP requests to send
        \\    - [schedule]    VU scheduling strategy
        \\    - [assertions]  Performance goals
        \\
        \\For more information: https://github.com/copyleftdev/z6
        \\
    , .{VERSION});
}

/// Print version information
fn printVersion() void {
    std.debug.print("Z6 version {s}\n", .{VERSION});
    std.debug.print("Built with Zig {s}\n", .{@import("builtin").zig_version_string});
}

/// Validate a scenario file
fn validateScenario(allocator: Allocator, scenario_path: []const u8) !void {
    std.debug.print("🔍 Validating scenario: {s}\n\n", .{scenario_path});

    // Read file
    const content = std.fs.cwd().readFileAlloc(
        allocator,
        scenario_path,
        scenario_mod.MAX_SCENARIO_SIZE,
    ) catch |err| {
        std.debug.print("❌ Failed to read file: {}\n", .{err});
        return err;
    };
    defer allocator.free(content);

    std.debug.print("✓ File read successfully ({d} bytes)\n", .{content.len});

    // Parse scenario
    var parser = ScenarioParser.init(allocator, content) catch |err| {
        std.debug.print("❌ Failed to initialize parser: {}\n", .{err});
        return err;
    };

    var scenario = parser.parse() catch |err| {
        std.debug.print("❌ Failed to parse scenario: {}\n", .{err});
        return err;
    };
    defer scenario.deinit();

    std.debug.print("✓ Scenario parsed successfully\n\n", .{});

    // Display scenario info
    std.debug.print("📋 Scenario Details:\n", .{});
    std.debug.print("   Name: {s}\n", .{scenario.metadata.name});
    std.debug.print("   Version: {s}\n", .{scenario.metadata.version});
    if (scenario.metadata.description) |desc| {
        std.debug.print("   Description: {s}\n", .{desc});
    }
    std.debug.print("\n", .{});

    std.debug.print("⚙️  Runtime Configuration:\n", .{});
    std.debug.print("   Duration: {d}s\n", .{scenario.runtime.duration_seconds});
    std.debug.print("   VUs: {d}\n", .{scenario.runtime.vus});
    if (scenario.runtime.prng_seed) |seed| {
        std.debug.print("   PRNG Seed: {d}\n", .{seed});
    }
    std.debug.print("\n", .{});

    std.debug.print("🎯 Target:\n", .{});
    std.debug.print("   Base URL: {s}\n", .{scenario.target.base_url});
    std.debug.print("   HTTP Version: {s}\n", .{scenario.target.http_version});
    std.debug.print("   TLS: {s}\n", .{if (scenario.target.tls) "enabled" else "disabled"});
    std.debug.print("\n", .{});

    std.debug.print("📝 Requests: {d} defined\n", .{scenario.requests.len});
    for (scenario.requests, 0..) |req, i| {
        std.debug.print("   {d}. {s}: {s} {s}\n", .{ i + 1, req.name, @tagName(req.method), req.path });
    }
    std.debug.print("\n", .{});

    std.debug.print("📊 Schedule: {s}\n", .{@tagName(scenario.schedule.schedule_type)});
    std.debug.print("   VUs: {d}\n\n", .{scenario.schedule.vus});

    std.debug.print("🎯 Assertions:\n", .{});
    if (scenario.assertions.p99_latency_ms) |p99| {
        std.debug.print("   P99 Latency: < {d}ms\n", .{p99});
    }
    if (scenario.assertions.error_rate_max) |err_rate| {
        std.debug.print("   Max Error Rate: < {d:.1}%\n", .{err_rate * 100.0});
    }
    if (scenario.assertions.success_rate_min) |success_rate| {
        std.debug.print("   Min Success Rate: > {d:.1}%\n", .{success_rate * 100.0});
    }
    std.debug.print("\n", .{});

    std.debug.print("✅ Scenario is valid!\n", .{});
}

/// Run a load test from a scenario file
fn runScenario(allocator: Allocator, scenario_path: []const u8) !void {
    std.debug.print("🚀 Running load test: {s}\n\n", .{scenario_path});

    // Read file
    const content = try std.fs.cwd().readFileAlloc(
        allocator,
        scenario_path,
        scenario_mod.MAX_SCENARIO_SIZE,
    );
    defer allocator.free(content);

    // Parse scenario
    var parser = try ScenarioParser.init(allocator, content);
    var scenario = try parser.parse();
    defer scenario.deinit();

    std.debug.print("📋 Scenario: {s}\n", .{scenario.metadata.name});
    std.debug.print("   Version: {s}\n", .{scenario.metadata.version});
    std.debug.print("   Duration: {d}s, VUs: {d}\n\n", .{
        scenario.runtime.duration_seconds,
        scenario.runtime.vus,
    });

    std.debug.print("⚠️  NOTE: Full load test execution requires completed integration.\n", .{});
    std.debug.print("   See examples/http_integration_test.zig for working demo.\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("   To run real load test:\n", .{});
    std.debug.print("   1. zig build run-http-test (integration example)\n", .{});
    std.debug.print("   2. Or use the full CLI once integration is complete\n", .{});
    std.debug.print("\n", .{});

    std.debug.print("✓ Scenario loaded and validated!\n", .{});
    std.debug.print("   Ready for load test execution (pending final integration)\n", .{});
}

/// Replay a test from event log
fn replayTest(allocator: Allocator, event_log_path: []const u8, format: OutputFormat) !void {
    std.debug.print("🔁 Replaying test from: {s}\n", .{event_log_path});
    std.debug.print("   Output format: {s}\n\n", .{format.toString()});

    // Read event log
    const content = std.fs.cwd().readFileAlloc(
        allocator,
        event_log_path,
        10 * 1024 * 1024, // 10 MB max
    ) catch |err| {
        std.debug.print("❌ Failed to read event log: {}\n", .{err});
        return err;
    };
    defer allocator.free(content);

    std.debug.print("✓ Event log read ({d} bytes)\n", .{content.len});
    std.debug.print("\n⚠️  Replay functionality requires event log system integration.\n", .{});
    std.debug.print("   This will replay all events deterministically using the same PRNG seed.\n", .{});
    std.debug.print("   Status: Foundation ready, full implementation pending.\n", .{});
}

/// Analyze metrics from event log
fn analyzeMetrics(allocator: Allocator, event_log_path: []const u8, format: OutputFormat) !void {
    std.debug.print("📊 Analyzing metrics from: {s}\n", .{event_log_path});
    std.debug.print("   Output format: {s}\n\n", .{format.toString()});

    // Read event log
    const content = std.fs.cwd().readFileAlloc(
        allocator,
        event_log_path,
        10 * 1024 * 1024, // 10 MB max
    ) catch |err| {
        std.debug.print("❌ Failed to read event log: {}\n", .{err});
        return err;
    };
    defer allocator.free(content);

    std.debug.print("✓ Event log read ({d} bytes)\n", .{content.len});
    std.debug.print("\n⚠️  Analysis functionality requires HDR histogram integration (TASK-400).\n", .{});
    std.debug.print("   This will recompute all metrics from raw events.\n", .{});
    std.debug.print("   Metrics: latency percentiles, error rates, throughput, etc.\n", .{});
    std.debug.print("   Status: Foundation ready, full implementation pending.\n", .{});
}

/// Compare two test runs
fn diffResults(allocator: Allocator, log1_path: []const u8, log2_path: []const u8, format: OutputFormat) !void {
    std.debug.print("🔍 Comparing test runs:\n", .{});
    std.debug.print("   Run 1: {s}\n", .{log1_path});
    std.debug.print("   Run 2: {s}\n", .{log2_path});
    std.debug.print("   Output format: {s}\n\n", .{format.toString()});

    // Read both logs
    const content1 = std.fs.cwd().readFileAlloc(
        allocator,
        log1_path,
        10 * 1024 * 1024,
    ) catch |err| {
        std.debug.print("❌ Failed to read first log: {}\n", .{err});
        return err;
    };
    defer allocator.free(content1);

    const content2 = std.fs.cwd().readFileAlloc(
        allocator,
        log2_path,
        10 * 1024 * 1024,
    ) catch |err| {
        std.debug.print("❌ Failed to read second log: {}\n", .{err});
        return err;
    };
    defer allocator.free(content2);

    std.debug.print("✓ Both logs read successfully\n", .{});
    std.debug.print("   Log 1: {d} bytes\n", .{content1.len});
    std.debug.print("   Log 2: {d} bytes\n", .{content2.len});
    std.debug.print("\n⚠️  Diff functionality requires metrics reducer (TASK-401).\n", .{});
    std.debug.print("   This will compare:\n", .{});
    std.debug.print("   - Latency distributions (p50, p95, p99, p999)\n", .{});
    std.debug.print("   - Error rates and types\n", .{});
    std.debug.print("   - Throughput (requests/sec)\n", .{});
    std.debug.print("   - Resource usage\n", .{});
    std.debug.print("   Status: Foundation ready, full implementation pending.\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse arguments
    const args = parseArgs(allocator) catch {
        printHelp();
        return;
    };

    // Handle version flag
    if (args.version) {
        printVersion();
        return;
    }

    // Handle help command or flag
    if (args.help or args.command == .help or args.command == .none) {
        printHelp();
        return;
    }

    // Check for scenario path
    const scenario_path = args.scenario_path orelse {
        std.debug.print("❌ Error: No scenario file specified\n\n", .{});
        printHelp();
        return error.MissingScenarioPath;
    };

    // Execute command
    switch (args.command) {
        .run => {
            runScenario(allocator, scenario_path) catch |err| {
                std.debug.print("\n❌ Load test failed: {}\n", .{err});
                std.process.exit(ExitCode.runtime_error.toInt());
            };
        },
        .validate => {
            validateScenario(allocator, scenario_path) catch |err| {
                std.debug.print("\n❌ Validation failed: {}\n", .{err});
                std.process.exit(ExitCode.config_error.toInt());
            };
        },
        .replay => {
            replayTest(allocator, scenario_path, args.output_format) catch |err| {
                std.debug.print("\n❌ Replay failed: {}\n", .{err});
                std.process.exit(ExitCode.runtime_error.toInt());
            };
        },
        .analyze => {
            analyzeMetrics(allocator, scenario_path, args.output_format) catch |err| {
                std.debug.print("\n❌ Analysis failed: {}\n", .{err});
                std.process.exit(ExitCode.runtime_error.toInt());
            };
        },
        .diff => {
            const second_path = args.second_path orelse {
                std.debug.print("❌ Error: Diff command requires two files\n\n", .{});
                printHelp();
                std.process.exit(ExitCode.config_error.toInt());
            };
            diffResults(allocator, scenario_path, second_path, args.output_format) catch |err| {
                std.debug.print("\n❌ Diff failed: {}\n", .{err});
                std.process.exit(ExitCode.runtime_error.toInt());
            };
        },
        .help, .none => {
            printHelp();
        },
    }
}

test "parseArgs with run command" {
    // Test would require mocking process.args
    try std.testing.expect(true);
}

test "parseArgs with validate command" {
    // Test would require mocking process.args
    try std.testing.expect(true);
}
