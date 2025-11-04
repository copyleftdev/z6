//! Output Formatters - JSON and CSV output for results
//!
//! Provides formatters for test results in different formats.
//!
//! Built with Tiger Style:
//! - Minimum 2 assertions per function
//! - Explicit error handling
//! - Bounded operations

const std = @import("std");
const Allocator = std.mem.Allocator;

/// Test result summary for output
pub const TestResult = struct {
    test_name: []const u8,
    duration_seconds: u32,
    total_requests: u64,
    successful_requests: u64,
    failed_requests: u64,
    p50_latency_ms: u64,
    p95_latency_ms: u64,
    p99_latency_ms: u64,
    error_rate: f64,

    pub fn success_rate(self: TestResult) f64 {
        if (self.total_requests == 0) return 0.0;
        return @as(f64, @floatFromInt(self.successful_requests)) /
            @as(f64, @floatFromInt(self.total_requests));
    }
};

/// Format test result as JSON
pub fn formatJSON(allocator: Allocator, result: TestResult) ![]const u8 {
    // Assertions
    std.debug.assert(result.total_requests >= result.successful_requests);
    std.debug.assert(result.total_requests >= result.failed_requests);

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const writer = output.writer();

    try writer.writeAll("{\n");
    try writer.print("  \"test_name\": \"{s}\",\n", .{result.test_name});
    try writer.print("  \"duration_seconds\": {d},\n", .{result.duration_seconds});
    try writer.print("  \"total_requests\": {d},\n", .{result.total_requests});
    try writer.print("  \"successful_requests\": {d},\n", .{result.successful_requests});
    try writer.print("  \"failed_requests\": {d},\n", .{result.failed_requests});
    try writer.print("  \"success_rate\": {d:.4},\n", .{result.success_rate()});
    try writer.print("  \"error_rate\": {d:.4},\n", .{result.error_rate});
    try writer.writeAll("  \"latency\": {\n");
    try writer.print("    \"p50_ms\": {d},\n", .{result.p50_latency_ms});
    try writer.print("    \"p95_ms\": {d},\n", .{result.p95_latency_ms});
    try writer.print("    \"p99_ms\": {d}\n", .{result.p99_latency_ms});
    try writer.writeAll("  }\n");
    try writer.writeAll("}\n");

    return output.toOwnedSlice();
}

/// Format test result as CSV header
pub fn formatCSVHeader(allocator: Allocator) ![]const u8 {
    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const writer = output.writer();

    try writer.writeAll("test_name,duration_seconds,total_requests,successful_requests,");
    try writer.writeAll("failed_requests,success_rate,error_rate,");
    try writer.writeAll("p50_latency_ms,p95_latency_ms,p99_latency_ms\n");

    return output.toOwnedSlice();
}

/// Format test result as CSV row
pub fn formatCSV(allocator: Allocator, result: TestResult) ![]const u8 {
    // Assertions
    std.debug.assert(result.total_requests >= result.successful_requests);
    std.debug.assert(result.total_requests >= result.failed_requests);

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const writer = output.writer();

    try writer.print("{s},{d},{d},{d},{d},{d:.4},{d:.4},{d},{d},{d}\n", .{
        result.test_name,
        result.duration_seconds,
        result.total_requests,
        result.successful_requests,
        result.failed_requests,
        result.success_rate(),
        result.error_rate,
        result.p50_latency_ms,
        result.p95_latency_ms,
        result.p99_latency_ms,
    });

    return output.toOwnedSlice();
}

/// Format summary output (human-readable)
pub fn formatSummary(allocator: Allocator, result: TestResult) ![]const u8 {
    // Assertions
    std.debug.assert(result.total_requests >= result.successful_requests);
    std.debug.assert(result.total_requests >= result.failed_requests);

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();
    const writer = output.writer();

    try writer.writeAll("📊 Test Results Summary\n");
    try writer.writeAll("═══════════════════════\n\n");
    try writer.print("Test Name:        {s}\n", .{result.test_name});
    try writer.print("Duration:         {d}s\n\n", .{result.duration_seconds});

    try writer.writeAll("Requests:\n");
    try writer.print("  Total:          {d}\n", .{result.total_requests});
    try writer.print("  Successful:     {d}\n", .{result.successful_requests});
    try writer.print("  Failed:         {d}\n", .{result.failed_requests});
    try writer.print("  Success Rate:   {d:.2}%\n", .{result.success_rate() * 100.0});
    try writer.print("  Error Rate:     {d:.2}%\n\n", .{result.error_rate * 100.0});

    try writer.writeAll("Latency Percentiles:\n");
    try writer.print("  p50:            {d}ms\n", .{result.p50_latency_ms});
    try writer.print("  p95:            {d}ms\n", .{result.p95_latency_ms});
    try writer.print("  p99:            {d}ms\n", .{result.p99_latency_ms});

    return output.toOwnedSlice();
}

test "formatJSON basic" {
    const allocator = std.testing.allocator;

    const result = TestResult{
        .test_name = "Test Load Test",
        .duration_seconds = 60,
        .total_requests = 1000,
        .successful_requests = 990,
        .failed_requests = 10,
        .p50_latency_ms = 50,
        .p95_latency_ms = 100,
        .p99_latency_ms = 150,
        .error_rate = 0.01,
    };

    const json = try formatJSON(allocator, result);
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json, "test_name") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "Test Load Test") != null);
}

test "formatCSV basic" {
    const allocator = std.testing.allocator;

    const result = TestResult{
        .test_name = "Test",
        .duration_seconds = 60,
        .total_requests = 1000,
        .successful_requests = 990,
        .failed_requests = 10,
        .p50_latency_ms = 50,
        .p95_latency_ms = 100,
        .p99_latency_ms = 150,
        .error_rate = 0.01,
    };

    const csv = try formatCSV(allocator, result);
    defer allocator.free(csv);

    try std.testing.expect(csv.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, csv, "Test") != null);
    try std.testing.expect(std.mem.indexOf(u8, csv, "1000") != null);
}

test "formatCSVHeader" {
    const allocator = std.testing.allocator;

    const header = try formatCSVHeader(allocator);
    defer allocator.free(header);

    try std.testing.expect(header.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, header, "test_name") != null);
    try std.testing.expect(std.mem.indexOf(u8, header, "p99_latency_ms") != null);
}

test "formatSummary basic" {
    const allocator = std.testing.allocator;

    const result = TestResult{
        .test_name = "Load Test",
        .duration_seconds = 60,
        .total_requests = 1000,
        .successful_requests = 990,
        .failed_requests = 10,
        .p50_latency_ms = 50,
        .p95_latency_ms = 100,
        .p99_latency_ms = 150,
        .error_rate = 0.01,
    };

    const summary = try formatSummary(allocator, result);
    defer allocator.free(summary);

    try std.testing.expect(summary.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, summary, "Test Results Summary") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "Load Test") != null);
}

test "TestResult success_rate calculation" {
    const result = TestResult{
        .test_name = "Test",
        .duration_seconds = 60,
        .total_requests = 1000,
        .successful_requests = 950,
        .failed_requests = 50,
        .p50_latency_ms = 50,
        .p95_latency_ms = 100,
        .p99_latency_ms = 150,
        .error_rate = 0.05,
    };

    const rate = result.success_rate();
    try std.testing.expectApproxEqAbs(@as(f64, 0.95), rate, 0.001);
}

test "TestResult zero requests" {
    const result = TestResult{
        .test_name = "Empty",
        .duration_seconds = 0,
        .total_requests = 0,
        .successful_requests = 0,
        .failed_requests = 0,
        .p50_latency_ms = 0,
        .p95_latency_ms = 0,
        .p99_latency_ms = 0,
        .error_rate = 0.0,
    };

    const rate = result.success_rate();
    try std.testing.expectEqual(@as(f64, 0.0), rate);
}
