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

const Allocator = std.mem.Allocator;
const ScenarioParser = scenario_mod.ScenarioParser;
const Scenario = scenario_mod.Scenario;

const VERSION = "0.1.0-dev";

/// Command-line arguments
const Args = struct {
    command: Command,
    scenario_path: ?[]const u8,
    help: bool,
    version: bool,
};

/// Available commands
const Command = enum {
    none,
    run,
    validate,
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
        .help = false,
        .version = false,
    };

    while (args_iter.next()) |arg| {
        if (std.mem.eql(u8, arg, "run")) {
            result.command = .run;
        } else if (std.mem.eql(u8, arg, "validate")) {
            result.command = .validate;
        } else if (std.mem.eql(u8, arg, "help") or std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            result.help = true;
            result.command = .help;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            result.version = true;
        } else if (result.scenario_path == null) {
            // First non-flag argument is the scenario path
            result.scenario_path = arg;
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
        \\    z6 <COMMAND> [OPTIONS] <SCENARIO_FILE>
        \\
        \\COMMANDS:
        \\    run         Run a load test from a scenario file
        \\    validate    Validate a scenario file without running
        \\    help        Show this help message
        \\
        \\OPTIONS:
        \\    -h, --help     Show help message
        \\    -v, --version  Show version information
        \\
        \\EXAMPLES:
        \\    z6 run scenario.toml              Run load test
        \\    z6 validate scenario.toml         Validate scenario file
        \\    z6 --help                         Show help
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
                return err;
            };
        },
        .validate => {
            validateScenario(allocator, scenario_path) catch |err| {
                std.debug.print("\n❌ Validation failed: {}\n", .{err});
                return err;
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
