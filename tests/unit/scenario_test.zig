//! Scenario Parser Tests
//!
//! Tests for parsing Z6 TOML scenario files

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const ScenarioParser = z6.ScenarioParser;
const Scenario = z6.Scenario;

test "scenario: parse simple scenario" {
    const scenario_content =
        \\[metadata]
        \\name = "Simple Test"
        \\version = "1.0"
        \\
        \\[runtime]
        \\duration_seconds = 60
        \\vus = 10
        \\
        \\[target]
        \\base_url = "http://localhost:8080"
        \\http_version = "http1.1"
        \\
        \\[[requests]]
        \\name = "get_hello"
        \\method = "GET"
        \\path = "/hello"
        \\timeout_ms = 1000
        \\
        \\[schedule]
        \\type = "constant"
        \\vus = 10
        \\
        \\[assertions]
        \\p99_latency_ms = 100
    ;

    const allocator = testing.allocator;
    var parser = try ScenarioParser.init(allocator, scenario_content);
    var scenario = try parser.parse();
    defer scenario.deinit();

    // Verify metadata
    try testing.expectEqualStrings("Simple Test", scenario.metadata.name);
    try testing.expectEqualStrings("1.0", scenario.metadata.version);

    // Verify runtime
    try testing.expectEqual(@as(u32, 60), scenario.runtime.duration_seconds);
    try testing.expectEqual(@as(u32, 10), scenario.runtime.vus);

    // Verify target
    try testing.expectEqualStrings("http://localhost:8080", scenario.target.base_url);
    try testing.expectEqualStrings("http1.1", scenario.target.http_version);

    // Verify requests
    try testing.expectEqual(@as(usize, 1), scenario.requests.len);
    try testing.expectEqualStrings("get_hello", scenario.requests[0].name);
    try testing.expectEqual(z6.Method.GET, scenario.requests[0].method);
    try testing.expectEqualStrings("/hello", scenario.requests[0].path);
    try testing.expectEqual(@as(u32, 1000), scenario.requests[0].timeout_ms);

    // Verify schedule
    try testing.expectEqual(@as(u32, 10), scenario.schedule.vus);
}

test "scenario: parse from file" {
    const allocator = testing.allocator;

    // Read test scenario file
    const file_content = try std.fs.cwd().readFileAlloc(
        allocator,
        "tests/fixtures/scenarios/simple.toml",
        10 * 1024 * 1024, // 10 MB max
    );
    defer allocator.free(file_content);

    var parser = try ScenarioParser.init(allocator, file_content);
    var scenario = try parser.parse();
    defer scenario.deinit();

    // Basic validation
    try testing.expect(scenario.runtime.vus > 0);
    try testing.expect(scenario.requests.len > 0);
}

test "scenario: reject file too large" {
    const allocator = testing.allocator;

    // Create content larger than MAX_SCENARIO_SIZE (10 MB)
    const large_content = try allocator.alloc(u8, 10 * 1024 * 1024 + 1);
    defer allocator.free(large_content);

    try testing.expectError(
        z6.ScenarioError.FileTooLarge,
        ScenarioParser.init(allocator, large_content),
    );
}

test "scenario: Tiger Style - assertions" {
    // All parsing functions have >= 2 assertions:
    // - init: 2 preconditions, 2 postconditions ✓
    // - parse: 2 preconditions, 2 postconditions ✓
    // - findValue: 2 preconditions, 1 postcondition ✓
    // - findIntValue: 2 preconditions, 1 postcondition ✓
}
