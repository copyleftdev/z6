//! Output Formatters - JSON and CSV output for results
//!
//! Provides formatters for test results in different formats:
//! - Summary text (human-readable)
//! - JSON (machine-readable)
//! - CSV (time-series data)
//! - Diff (compare two runs)
//!
//! Built with Tiger Style:
//! - Minimum 2 assertions per function
//! - Explicit error handling
//! - Bounded operations

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

// Import Metrics types
const metrics = @import("metrics.zig");
const Metrics = metrics.Metrics;
const RequestMetrics = metrics.RequestMetrics;
const LatencyMetrics = metrics.LatencyMetrics;
const ThroughputMetrics = metrics.ThroughputMetrics;
const ConnectionMetrics = metrics.ConnectionMetrics;
const ErrorMetrics = metrics.ErrorMetrics;

// =============================================================================
// Constants
// =============================================================================

/// Method names for by_method breakdown
pub const METHOD_NAMES = [_][]const u8{
    "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "OTHER",
};

/// Status class names
pub const STATUS_NAMES = [_][]const u8{
    "1xx", "2xx", "3xx", "4xx", "5xx", "other",
};

/// Output configuration
pub const OutputConfig = struct {
    include_metadata: bool = true,
    pretty_print: bool = true,
    tick_interval: u64 = 1000, // For time-series
};

/// Interval metrics for time-series output
pub const IntervalMetrics = struct {
    rps: u64,
    latency_p50_ns: u64,
    latency_p99_ns: u64,
    errors: u64,
    active_vus: u64,
};

// =============================================================================
// Helper Functions
// =============================================================================

/// Convert nanoseconds to milliseconds
pub fn nsToMs(ns: u64) f64 {
    return @as(f64, @floatFromInt(ns)) / 1_000_000.0;
}

/// Format number with thousands separators
pub fn formatWithCommas(writer: anytype, value: u64) !void {
    if (value < 1000) {
        try writer.print("{d}", .{value});
        return;
    }

    var digits: [20]u8 = undefined;
    var len: usize = 0;
    var n = value;

    // Extract digits in reverse order
    while (n > 0) : (len += 1) {
        digits[len] = @intCast(n % 10);
        n /= 10;
    }

    // Write with commas - insert comma every 3 digits from right
    var i: usize = len;
    while (i > 0) {
        i -= 1;
        try writer.writeByte('0' + digits[i]);
        // Add comma if not at start and position from right is multiple of 3
        if (i > 0 and i % 3 == 0) {
            try writer.writeByte(',');
        }
    }
}

/// Format percentage with 1 decimal place
pub fn formatPercent(writer: anytype, rate: f64) !void {
    try writer.print("{d:.1}%", .{rate * 100.0});
}

/// Format delta with direction indicator
pub fn formatDelta(writer: anytype, old_val: f64, new_val: f64) !void {
    if (old_val == 0.0) {
        if (new_val == 0.0) {
            try writer.writeAll("(no change)");
        } else {
            try writer.writeAll("(new)");
        }
        return;
    }

    const delta = ((new_val - old_val) / old_val) * 100.0;
    if (delta > 0) {
        try writer.print("(+{d:.1}%)", .{delta});
    } else if (delta < 0) {
        try writer.print("({d:.1}%)", .{delta});
    } else {
        try writer.writeAll("(no change)");
    }
}

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

// =============================================================================
// Metrics Formatters (Full Metrics Structure)
// =============================================================================

/// Format full Metrics as human-readable summary text
pub fn formatSummaryText(writer: anytype, m: *const Metrics, config: OutputConfig) !void {
    // Tiger Style: Assert preconditions
    assert(m.requests.total >= m.requests.success);
    assert(m.latency.sample_count <= m.requests.total);

    _ = config; // Reserved for future options

    // Header
    try writer.writeAll("Z6 Load Test Results\n");
    try writer.writeAll("====================\n\n");

    // Duration
    const duration_ticks = if (m.end_tick > m.start_tick) m.end_tick - m.start_tick else 0;
    const duration_secs = @as(f64, @floatFromInt(duration_ticks)) / 1000.0;
    try writer.print("Duration: {d:.1}s\n\n", .{duration_secs});

    // Requests section
    try writer.writeAll("Requests\n");
    try writer.writeAll("--------\n");
    try writer.writeAll("Total: ");
    try formatWithCommas(writer, m.requests.total);
    try writer.writeAll("\n");

    try writer.writeAll("Success: ");
    try formatWithCommas(writer, m.requests.success);
    try writer.print(" ({d:.1}%)\n", .{m.requests.success_rate * 100.0});

    try writer.writeAll("Failed: ");
    try formatWithCommas(writer, m.requests.failed);
    if (m.requests.total > 0) {
        const fail_rate = @as(f64, @floatFromInt(m.requests.failed)) / @as(f64, @floatFromInt(m.requests.total));
        try writer.print(" ({d:.1}%)\n", .{fail_rate * 100.0});
    } else {
        try writer.writeAll(" (0.0%)\n");
    }
    try writer.writeAll("\n");

    // Latency section
    try writer.writeAll("Latency (ms)\n");
    try writer.writeAll("------------\n");
    try writer.print("Min: {d:.1}\n", .{nsToMs(m.latency.min_ns)});
    try writer.print("Max: {d:.1}\n", .{nsToMs(m.latency.max_ns)});
    try writer.print("Mean: {d:.1}\n", .{nsToMs(@intFromFloat(m.latency.mean_ns))});
    try writer.print("p50: {d:.1}\n", .{nsToMs(m.latency.p50_ns)});
    try writer.print("p90: {d:.1}\n", .{nsToMs(m.latency.p90_ns)});
    try writer.print("p95: {d:.1}\n", .{nsToMs(m.latency.p95_ns)});
    try writer.print("p99: {d:.1}\n", .{nsToMs(m.latency.p99_ns)});
    try writer.print("p999: {d:.1}\n\n", .{nsToMs(m.latency.p999_ns)});

    // Throughput section
    try writer.writeAll("Throughput\n");
    try writer.writeAll("----------\n");
    // Convert requests_per_tick to requests_per_second (assuming 1 tick = 1ms)
    const rps = m.throughput.requests_per_tick * 1000.0;
    try writer.print("RPS: {d:.0}\n\n", .{rps});

    // Errors section
    try writer.writeAll("Errors\n");
    try writer.writeAll("------\n");
    try writer.writeAll("Total: ");
    try formatWithCommas(writer, m.errors.total_errors);
    try writer.print(" ({d:.1}%)\n", .{m.errors.error_rate * 100.0});
    try writer.print("  DNS: {d}\n", .{m.errors.dns_errors});
    try writer.print("  TCP: {d}\n", .{m.errors.tcp_errors});
    try writer.print("  TLS: {d}\n", .{m.errors.tls_errors});
    try writer.print("  HTTP: {d}\n", .{m.errors.http_errors});
    try writer.print("  Timeout: {d}\n", .{m.errors.timeout_errors});
    try writer.print("  Protocol: {d}\n", .{m.errors.protocol_errors});
    try writer.print("  Resource: {d}\n\n", .{m.errors.resource_errors});

    // Connections section
    try writer.writeAll("Connections\n");
    try writer.writeAll("-----------\n");
    try writer.print("Total: {d}\n", .{m.connections.total_connections});
    try writer.print("Errors: {d}\n", .{m.connections.connection_errors});
    try writer.print("Avg Connect: {d:.1}ms\n", .{nsToMs(m.connections.avg_connection_time_ns)});
}

/// Format full Metrics as JSON
pub fn formatMetricsJSON(writer: anytype, m: *const Metrics, config: OutputConfig) !void {
    // Tiger Style: Assert preconditions
    assert(m.requests.total >= m.requests.success);
    assert(m.latency.sample_count <= m.requests.total);

    const indent = if (config.pretty_print) "  " else "";
    const newline = if (config.pretty_print) "\n" else "";

    try writer.writeAll("{");
    try writer.writeAll(newline);

    // Version
    if (config.include_metadata) {
        try writer.print("{s}\"version\": \"1.0\",{s}", .{ indent, newline });
    }

    // Requests object
    try writer.print("{s}\"requests\": {{{s}", .{ indent, newline });
    try writer.print("{s}{s}\"total\": {d},{s}", .{ indent, indent, m.requests.total, newline });
    try writer.print("{s}{s}\"success\": {d},{s}", .{ indent, indent, m.requests.success, newline });
    try writer.print("{s}{s}\"failed\": {d},{s}", .{ indent, indent, m.requests.failed, newline });
    try writer.print("{s}{s}\"success_rate\": {d:.6},{s}", .{ indent, indent, m.requests.success_rate, newline });

    // by_method object
    try writer.print("{s}{s}\"by_method\": {{{s}", .{ indent, indent, newline });
    var first_method = true;
    for (m.requests.by_method, 0..) |count, i| {
        if (count > 0) {
            if (!first_method) {
                try writer.print(",{s}", .{newline});
            }
            try writer.print("{s}{s}{s}\"{s}\": {d}", .{ indent, indent, indent, METHOD_NAMES[i], count });
            first_method = false;
        }
    }
    try writer.print("{s}{s}{s}}},{s}", .{ newline, indent, indent, newline });

    // by_status object
    try writer.print("{s}{s}\"by_status\": {{{s}", .{ indent, indent, newline });
    var first_status = true;
    for (m.requests.by_status_class, 0..) |count, i| {
        if (count > 0) {
            if (!first_status) {
                try writer.print(",{s}", .{newline});
            }
            try writer.print("{s}{s}{s}\"{s}\": {d}", .{ indent, indent, indent, STATUS_NAMES[i], count });
            first_status = false;
        }
    }
    try writer.print("{s}{s}{s}}}{s}", .{ newline, indent, indent, newline });
    try writer.print("{s}}},{s}", .{ indent, newline });

    // Latency object
    try writer.print("{s}\"latency\": {{{s}", .{ indent, newline });
    try writer.print("{s}{s}\"min_ns\": {d},{s}", .{ indent, indent, m.latency.min_ns, newline });
    try writer.print("{s}{s}\"max_ns\": {d},{s}", .{ indent, indent, m.latency.max_ns, newline });
    try writer.print("{s}{s}\"mean_ns\": {d:.2},{s}", .{ indent, indent, m.latency.mean_ns, newline });
    try writer.print("{s}{s}\"p50_ns\": {d},{s}", .{ indent, indent, m.latency.p50_ns, newline });
    try writer.print("{s}{s}\"p90_ns\": {d},{s}", .{ indent, indent, m.latency.p90_ns, newline });
    try writer.print("{s}{s}\"p95_ns\": {d},{s}", .{ indent, indent, m.latency.p95_ns, newline });
    try writer.print("{s}{s}\"p99_ns\": {d},{s}", .{ indent, indent, m.latency.p99_ns, newline });
    try writer.print("{s}{s}\"p999_ns\": {d},{s}", .{ indent, indent, m.latency.p999_ns, newline });
    try writer.print("{s}{s}\"sample_count\": {d}{s}", .{ indent, indent, m.latency.sample_count, newline });
    try writer.print("{s}}},{s}", .{ indent, newline });

    // Throughput object
    try writer.print("{s}\"throughput\": {{{s}", .{ indent, newline });
    try writer.print("{s}{s}\"duration_ticks\": {d},{s}", .{ indent, indent, m.throughput.total_duration_ticks, newline });
    try writer.print("{s}{s}\"requests_per_tick\": {d:.6},{s}", .{ indent, indent, m.throughput.requests_per_tick, newline });
    try writer.print("{s}{s}\"response_count\": {d}{s}", .{ indent, indent, m.throughput.response_count, newline });
    try writer.print("{s}}},{s}", .{ indent, newline });

    // Connections object
    try writer.print("{s}\"connections\": {{{s}", .{ indent, newline });
    try writer.print("{s}{s}\"total\": {d},{s}", .{ indent, indent, m.connections.total_connections, newline });
    try writer.print("{s}{s}\"errors\": {d},{s}", .{ indent, indent, m.connections.connection_errors, newline });
    try writer.print("{s}{s}\"avg_time_ns\": {d}{s}", .{ indent, indent, m.connections.avg_connection_time_ns, newline });
    try writer.print("{s}}},{s}", .{ indent, newline });

    // Errors object
    try writer.print("{s}\"errors\": {{{s}", .{ indent, newline });
    try writer.print("{s}{s}\"total\": {d},{s}", .{ indent, indent, m.errors.total_errors, newline });
    try writer.print("{s}{s}\"rate\": {d:.6},{s}", .{ indent, indent, m.errors.error_rate, newline });
    try writer.print("{s}{s}\"dns\": {d},{s}", .{ indent, indent, m.errors.dns_errors, newline });
    try writer.print("{s}{s}\"tcp\": {d},{s}", .{ indent, indent, m.errors.tcp_errors, newline });
    try writer.print("{s}{s}\"tls\": {d},{s}", .{ indent, indent, m.errors.tls_errors, newline });
    try writer.print("{s}{s}\"http\": {d},{s}", .{ indent, indent, m.errors.http_errors, newline });
    try writer.print("{s}{s}\"timeout\": {d},{s}", .{ indent, indent, m.errors.timeout_errors, newline });
    try writer.print("{s}{s}\"protocol\": {d},{s}", .{ indent, indent, m.errors.protocol_errors, newline });
    try writer.print("{s}{s}\"resource\": {d}{s}", .{ indent, indent, m.errors.resource_errors, newline });
    try writer.print("{s}}}{s}", .{ indent, newline });

    try writer.writeAll("}");
    try writer.writeAll(newline);
}

/// Format CSV time-series header
pub fn formatTimeSeriesHeader(writer: anytype) !void {
    try writer.writeAll("tick,rps,latency_p50_ns,latency_p99_ns,errors,active_vus\n");
}

/// Format CSV time-series row
pub fn formatTimeSeriesRow(writer: anytype, tick: u64, interval: IntervalMetrics) !void {
    // Tiger Style: Assert valid interval data
    assert(interval.active_vus <= 10000); // Reasonable upper bound
    assert(interval.rps <= 1_000_000); // Max 1M RPS per interval

    try writer.print("{d},{d},{d},{d},{d},{d}\n", .{
        tick,
        interval.rps,
        interval.latency_p50_ns,
        interval.latency_p99_ns,
        interval.errors,
        interval.active_vus,
    });
}

/// Format diff between two metrics runs
pub fn formatDiff(writer: anytype, baseline: *const Metrics, current: *const Metrics) !void {
    // Tiger Style: Assert preconditions
    assert(baseline.requests.total >= baseline.requests.success);
    assert(current.requests.total >= current.requests.success);

    try writer.writeAll("Comparing baseline vs current:\n\n");

    // Requests comparison
    try writer.writeAll("Requests: ");
    try formatWithCommas(writer, baseline.requests.total);
    try writer.writeAll(" -> ");
    try formatWithCommas(writer, current.requests.total);
    try writer.writeAll(" ");
    try formatDelta(writer, @floatFromInt(baseline.requests.total), @floatFromInt(current.requests.total));
    try writer.writeAll("\n");

    // Success rate comparison
    try writer.print("Success Rate: {d:.1}% -> {d:.1}% ", .{
        baseline.requests.success_rate * 100.0,
        current.requests.success_rate * 100.0,
    });
    const sr_delta = (current.requests.success_rate - baseline.requests.success_rate) * 100.0;
    if (sr_delta > 0) {
        try writer.print("(+{d:.1}pp)\n", .{sr_delta});
    } else if (sr_delta < 0) {
        try writer.print("({d:.1}pp)\n", .{sr_delta});
    } else {
        try writer.writeAll("(no change)\n");
    }

    try writer.writeAll("\nLatency (ms):\n");

    // p50 comparison
    const p50_baseline = nsToMs(baseline.latency.p50_ns);
    const p50_current = nsToMs(current.latency.p50_ns);
    try writer.print("  p50: {d:.1} -> {d:.1} ", .{ p50_baseline, p50_current });
    try formatDelta(writer, p50_baseline, p50_current);
    if (p50_current < p50_baseline) {
        try writer.writeAll(" [improved]");
    } else if (p50_current > p50_baseline) {
        try writer.writeAll(" [regressed]");
    }
    try writer.writeAll("\n");

    // p99 comparison
    const p99_baseline = nsToMs(baseline.latency.p99_ns);
    const p99_current = nsToMs(current.latency.p99_ns);
    try writer.print("  p99: {d:.1} -> {d:.1} ", .{ p99_baseline, p99_current });
    try formatDelta(writer, p99_baseline, p99_current);
    if (p99_current < p99_baseline) {
        try writer.writeAll(" [improved]");
    } else if (p99_current > p99_baseline) {
        try writer.writeAll(" [regressed]");
    }
    try writer.writeAll("\n");

    // Errors comparison
    try writer.writeAll("\nErrors: ");
    try formatWithCommas(writer, baseline.errors.total_errors);
    try writer.writeAll(" -> ");
    try formatWithCommas(writer, current.errors.total_errors);
    try writer.writeAll(" ");
    try formatDelta(writer, @floatFromInt(baseline.errors.total_errors), @floatFromInt(current.errors.total_errors));
    if (current.errors.total_errors < baseline.errors.total_errors) {
        try writer.writeAll(" [improved]");
    } else if (current.errors.total_errors > baseline.errors.total_errors) {
        try writer.writeAll(" [regressed]");
    }
    try writer.writeAll("\n");
}

// =============================================================================
// Convenience Functions
// =============================================================================

/// Format Metrics to allocated JSON string
pub fn metricsToJSON(allocator: Allocator, m: *const Metrics) ![]u8 {
    // Tiger Style: Assert preconditions
    assert(m.requests.total >= m.requests.success);
    assert(m.latency.sample_count <= m.requests.total);

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    try formatMetricsJSON(output.writer(), m, .{});

    return output.toOwnedSlice();
}

/// Format Metrics to allocated summary string
pub fn metricsToSummary(allocator: Allocator, m: *const Metrics) ![]u8 {
    // Tiger Style: Assert preconditions
    assert(m.requests.total >= m.requests.success);
    assert(m.latency.sample_count <= m.requests.total);

    var output = std.ArrayList(u8).init(allocator);
    errdefer output.deinit();

    try formatSummaryText(output.writer(), m, .{});

    return output.toOwnedSlice();
}

// =============================================================================
// Legacy TestResult Formatters (Backward Compatibility)
// =============================================================================

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

// =============================================================================
// Metrics Formatter Tests
// =============================================================================

fn createTestMetrics() Metrics {
    return Metrics{
        .requests = RequestMetrics{
            .total = 10000,
            .success = 9800,
            .failed = 200,
            .success_rate = 0.98,
            .by_method = [_]u64{ 8000, 2000, 0, 0, 0, 0, 0, 0 },
            .by_status_class = [_]u64{ 0, 9500, 100, 200, 200, 0 },
        },
        .latency = LatencyMetrics{
            .min_ns = 1_000_000, // 1ms
            .max_ns = 500_000_000, // 500ms
            .mean_ns = 45_000_000.0, // 45ms
            .p50_ns = 35_000_000, // 35ms
            .p90_ns = 80_000_000, // 80ms
            .p95_ns = 120_000_000, // 120ms
            .p99_ns = 200_000_000, // 200ms
            .p999_ns = 450_000_000, // 450ms
            .sample_count = 9800,
        },
        .throughput = ThroughputMetrics{
            .total_duration_ticks = 60000, // 60 seconds
            .requests_per_tick = 166.67, // ~166k RPS
            .response_count = 10000,
        },
        .connections = ConnectionMetrics{
            .total_connections = 100,
            .connection_errors = 5,
            .avg_connection_time_ns = 15_000_000, // 15ms
            .total_connection_time_ns = 1_500_000_000,
        },
        .errors = ErrorMetrics{
            .total_errors = 200,
            .dns_errors = 10,
            .tcp_errors = 50,
            .tls_errors = 20,
            .http_errors = 30,
            .timeout_errors = 80,
            .protocol_errors = 5,
            .resource_errors = 5,
            .error_rate = 0.02,
        },
        .start_tick = 0,
        .end_tick = 60000,
    };
}

test "nsToMs conversion" {
    try std.testing.expectEqual(@as(f64, 1.0), nsToMs(1_000_000));
    try std.testing.expectEqual(@as(f64, 0.001), nsToMs(1000));
    try std.testing.expectEqual(@as(f64, 1000.0), nsToMs(1_000_000_000));
}

test "formatWithCommas small numbers" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatWithCommas(stream.writer(), 123);
    try std.testing.expectEqualStrings("123", stream.getWritten());
}

test "formatWithCommas thousands" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatWithCommas(stream.writer(), 1234567);
    try std.testing.expectEqualStrings("1,234,567", stream.getWritten());
}

test "formatPercent" {
    var buf: [64]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatPercent(stream.writer(), 0.985);
    try std.testing.expectEqualStrings("98.5%", stream.getWritten());
}

test "formatSummaryText basic" {
    const m = createTestMetrics();

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatSummaryText(stream.writer(), &m, .{});
    const output = stream.getWritten();

    // Check sections are present
    try std.testing.expect(std.mem.indexOf(u8, output, "Z6 Load Test Results") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Requests") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Latency (ms)") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Throughput") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Errors") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "Connections") != null);
}

test "formatSummaryText empty metrics" {
    const m = Metrics{
        .requests = RequestMetrics{
            .total = 0,
            .success = 0,
            .failed = 0,
            .success_rate = 0.0,
            .by_method = [_]u64{0} ** 8,
            .by_status_class = [_]u64{0} ** 6,
        },
        .latency = LatencyMetrics{
            .min_ns = 0,
            .max_ns = 0,
            .mean_ns = 0.0,
            .p50_ns = 0,
            .p90_ns = 0,
            .p95_ns = 0,
            .p99_ns = 0,
            .p999_ns = 0,
            .sample_count = 0,
        },
        .throughput = ThroughputMetrics{
            .total_duration_ticks = 0,
            .requests_per_tick = 0.0,
            .response_count = 0,
        },
        .connections = ConnectionMetrics{
            .total_connections = 0,
            .connection_errors = 0,
            .avg_connection_time_ns = 0,
            .total_connection_time_ns = 0,
        },
        .errors = ErrorMetrics{
            .total_errors = 0,
            .dns_errors = 0,
            .tcp_errors = 0,
            .tls_errors = 0,
            .http_errors = 0,
            .timeout_errors = 0,
            .protocol_errors = 0,
            .resource_errors = 0,
            .error_rate = 0.0,
        },
        .start_tick = 0,
        .end_tick = 0,
    };

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatSummaryText(stream.writer(), &m, .{});
    const output = stream.getWritten();

    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "Z6 Load Test Results") != null);
}

test "formatMetricsJSON structure" {
    const m = createTestMetrics();

    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatMetricsJSON(stream.writer(), &m, .{});
    const output = stream.getWritten();

    // Check JSON structure
    try std.testing.expect(std.mem.indexOf(u8, output, "\"version\": \"1.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"requests\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"latency\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"throughput\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"connections\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"errors\":") != null);
}

test "formatMetricsJSON by_method" {
    const m = createTestMetrics();

    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatMetricsJSON(stream.writer(), &m, .{});
    const output = stream.getWritten();

    // Check method breakdown
    try std.testing.expect(std.mem.indexOf(u8, output, "\"GET\": 8000") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"POST\": 2000") != null);
}

test "formatMetricsJSON compact" {
    const m = createTestMetrics();

    var buf: [8192]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatMetricsJSON(stream.writer(), &m, .{ .pretty_print = false });
    const output = stream.getWritten();

    // Compact JSON should not have newlines (except at very end possibly)
    var newline_count: usize = 0;
    for (output) |c| {
        if (c == '\n') newline_count += 1;
    }
    try std.testing.expect(newline_count <= 1);
}

test "formatTimeSeriesHeader" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatTimeSeriesHeader(stream.writer());
    const output = stream.getWritten();

    try std.testing.expectEqualStrings("tick,rps,latency_p50_ns,latency_p99_ns,errors,active_vus\n", output);
}

test "formatTimeSeriesRow" {
    var buf: [256]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    const interval = IntervalMetrics{
        .rps = 1500,
        .latency_p50_ns = 35_000_000,
        .latency_p99_ns = 150_000_000,
        .errors = 5,
        .active_vus = 100,
    };

    try formatTimeSeriesRow(stream.writer(), 1000, interval);
    const output = stream.getWritten();

    try std.testing.expectEqualStrings("1000,1500,35000000,150000000,5,100\n", output);
}

test "formatDiff improvement" {
    const baseline = createTestMetrics();
    var current = createTestMetrics();
    // Current has better latency
    current.latency.p50_ns = 30_000_000; // 30ms vs 35ms
    current.latency.p99_ns = 180_000_000; // 180ms vs 200ms
    current.errors.total_errors = 100; // 100 vs 200

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatDiff(stream.writer(), &baseline, &current);
    const output = stream.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "Comparing baseline vs current") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "[improved]") != null);
}

test "formatDiff regression" {
    const baseline = createTestMetrics();
    var current = createTestMetrics();
    // Current has worse latency
    current.latency.p50_ns = 50_000_000; // 50ms vs 35ms
    current.latency.p99_ns = 300_000_000; // 300ms vs 200ms

    var buf: [4096]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);

    try formatDiff(stream.writer(), &baseline, &current);
    const output = stream.getWritten();

    try std.testing.expect(std.mem.indexOf(u8, output, "[regressed]") != null);
}

test "metricsToJSON convenience" {
    const allocator = std.testing.allocator;
    const m = createTestMetrics();

    const json = try metricsToJSON(allocator, &m);
    defer allocator.free(json);

    try std.testing.expect(json.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"requests\":") != null);
}

test "metricsToSummary convenience" {
    const allocator = std.testing.allocator;
    const m = createTestMetrics();

    const summary = try metricsToSummary(allocator, &m);
    defer allocator.free(summary);

    try std.testing.expect(summary.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, summary, "Z6 Load Test Results") != null);
}
