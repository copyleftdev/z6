//! HDR Histogram Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.
//!
//! HDR Histogram provides high dynamic range histograms with bounded memory
//! and configurable precision for latency percentile calculations.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const HdrHistogram = z6.HdrHistogram;

// =============================================================================
// Phase 1: Init/Deinit Tests
// =============================================================================

test "hdr_histogram: init with default config" {
    const histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Default config: 1ns to 1 hour, 3 significant figures
    try testing.expectEqual(@as(u64, 1), histogram.lowest_trackable_value);
    try testing.expectEqual(@as(u64, 3_600_000_000_000), histogram.highest_trackable_value);
    try testing.expectEqual(@as(u8, 3), histogram.significant_figures);

    // Should start empty
    try testing.expectEqual(@as(u64, 0), histogram.totalCount());
}

test "hdr_histogram: init with custom config" {
    const histogram = try HdrHistogram.init(testing.allocator, .{
        .lowest_trackable_value = 1000, // 1 microsecond in ns
        .highest_trackable_value = 60_000_000_000, // 1 minute in ns
        .significant_figures = 2,
    });
    defer histogram.deinit();

    try testing.expectEqual(@as(u64, 1000), histogram.lowest_trackable_value);
    try testing.expectEqual(@as(u64, 60_000_000_000), histogram.highest_trackable_value);
    try testing.expectEqual(@as(u8, 2), histogram.significant_figures);
}

test "hdr_histogram: init validates significant figures" {
    // Significant figures must be 1-5
    try testing.expectError(error.InvalidSignificantFigures, HdrHistogram.init(testing.allocator, .{
        .significant_figures = 0,
    }));
    try testing.expectError(error.InvalidSignificantFigures, HdrHistogram.init(testing.allocator, .{
        .significant_figures = 6,
    }));

    // Valid range
    const h1 = try HdrHistogram.init(testing.allocator, .{ .significant_figures = 1 });
    defer h1.deinit();
    const h5 = try HdrHistogram.init(testing.allocator, .{ .significant_figures = 5 });
    defer h5.deinit();
}

test "hdr_histogram: init validates value range" {
    // Lowest must be >= 1
    try testing.expectError(error.InvalidValueRange, HdrHistogram.init(testing.allocator, .{
        .lowest_trackable_value = 0,
    }));

    // Highest must be > lowest * 2
    try testing.expectError(error.InvalidValueRange, HdrHistogram.init(testing.allocator, .{
        .lowest_trackable_value = 100,
        .highest_trackable_value = 100,
    }));
}

test "hdr_histogram: reset clears all data" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Record some values
    try histogram.recordValue(1000);
    try histogram.recordValue(2000);
    try histogram.recordValue(3000);
    try testing.expectEqual(@as(u64, 3), histogram.totalCount());

    // Reset
    histogram.reset();
    try testing.expectEqual(@as(u64, 0), histogram.totalCount());
    try testing.expectEqual(@as(u64, 0), histogram.max());
    try testing.expectEqual(@as(u64, std.math.maxInt(u64)), histogram.min());
}

// =============================================================================
// Phase 2: Value Recording Tests
// =============================================================================

test "hdr_histogram: record single value" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValue(1000);
    try testing.expectEqual(@as(u64, 1), histogram.totalCount());
    try testing.expectEqual(@as(u64, 1000), histogram.min());
    try testing.expectEqual(@as(u64, 1000), histogram.max());
}

test "hdr_histogram: record multiple values" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValue(100);
    try histogram.recordValue(200);
    try histogram.recordValue(300);

    try testing.expectEqual(@as(u64, 3), histogram.totalCount());
    try testing.expectEqual(@as(u64, 100), histogram.min());
    try testing.expectEqual(@as(u64, 300), histogram.max());
}

test "hdr_histogram: record values with count" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValues(1000, 5);
    try testing.expectEqual(@as(u64, 5), histogram.totalCount());
    try testing.expectEqual(@as(u64, 1000), histogram.min());
    try testing.expectEqual(@as(u64, 1000), histogram.max());
}

test "hdr_histogram: record value at lowest trackable" {
    var histogram = try HdrHistogram.init(testing.allocator, .{
        .lowest_trackable_value = 1,
    });
    defer histogram.deinit();

    try histogram.recordValue(1);
    try testing.expectEqual(@as(u64, 1), histogram.totalCount());
    try testing.expectEqual(@as(u64, 1), histogram.min());
}

test "hdr_histogram: record value at highest trackable" {
    var histogram = try HdrHistogram.init(testing.allocator, .{
        .highest_trackable_value = 1_000_000,
    });
    defer histogram.deinit();

    try histogram.recordValue(1_000_000);
    try testing.expectEqual(@as(u64, 1), histogram.totalCount());
    try testing.expectEqual(@as(u64, 1_000_000), histogram.max());
}

test "hdr_histogram: record value exceeding range returns error" {
    var histogram = try HdrHistogram.init(testing.allocator, .{
        .highest_trackable_value = 1_000_000,
    });
    defer histogram.deinit();

    // Value exceeds highest trackable
    try testing.expectError(error.ValueOutOfRange, histogram.recordValue(2_000_000));

    // Original state should be unchanged
    try testing.expectEqual(@as(u64, 0), histogram.totalCount());
}

// =============================================================================
// Phase 3: Query Tests
// =============================================================================

test "hdr_histogram: min returns minimum recorded value" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValue(500);
    try histogram.recordValue(100);
    try histogram.recordValue(300);

    try testing.expectEqual(@as(u64, 100), histogram.min());
}

test "hdr_histogram: max returns maximum recorded value" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValue(100);
    try histogram.recordValue(500);
    try histogram.recordValue(300);

    try testing.expectEqual(@as(u64, 500), histogram.max());
}

test "hdr_histogram: mean calculation" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Record values: 100, 200, 300, 400, 500
    // Mean = (100+200+300+400+500) / 5 = 300
    try histogram.recordValue(100);
    try histogram.recordValue(200);
    try histogram.recordValue(300);
    try histogram.recordValue(400);
    try histogram.recordValue(500);

    // Mean should be approximately 300 (within histogram resolution)
    const mean = histogram.mean();
    try testing.expect(mean >= 290.0 and mean <= 310.0);
}

test "hdr_histogram: mean on empty histogram" {
    const histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Empty histogram should return 0 mean
    try testing.expectEqual(@as(f64, 0.0), histogram.mean());
}

test "hdr_histogram: totalCount accumulates correctly" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValue(100);
    try testing.expectEqual(@as(u64, 1), histogram.totalCount());

    try histogram.recordValues(200, 10);
    try testing.expectEqual(@as(u64, 11), histogram.totalCount());

    try histogram.recordValue(300);
    try testing.expectEqual(@as(u64, 12), histogram.totalCount());
}

// =============================================================================
// Phase 4: Percentile Tests
// =============================================================================

test "hdr_histogram: p0 returns minimum" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValue(100);
    try histogram.recordValue(200);
    try histogram.recordValue(300);

    const p0 = histogram.valueAtPercentile(0.0);
    try testing.expectEqual(@as(u64, 100), p0);
}

test "hdr_histogram: p100 returns maximum" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValue(100);
    try histogram.recordValue(200);
    try histogram.recordValue(300);

    const p100 = histogram.valueAtPercentile(100.0);
    try testing.expectEqual(@as(u64, 300), p100);
}

test "hdr_histogram: p50 on uniform distribution" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Record values 1-100
    var i: u64 = 1;
    while (i <= 100) : (i += 1) {
        try histogram.recordValue(i);
    }

    // p50 should be around 50
    const p50 = histogram.valueAtPercentile(50.0);
    try testing.expect(p50 >= 49 and p50 <= 51);
}

test "hdr_histogram: p99 on uniform distribution" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Record values 1-100
    var i: u64 = 1;
    while (i <= 100) : (i += 1) {
        try histogram.recordValue(i);
    }

    // p99 should be around 99
    const p99 = histogram.valueAtPercentile(99.0);
    try testing.expect(p99 >= 98 and p99 <= 100);
}

test "hdr_histogram: p999 on large distribution" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Record values 1-10000
    var i: u64 = 1;
    while (i <= 10000) : (i += 1) {
        try histogram.recordValue(i);
    }

    // p99.9 should be around 9990
    const p999 = histogram.valueAtPercentile(99.9);
    try testing.expect(p999 >= 9980 and p999 <= 10000);
}

test "hdr_histogram: percentile on single value" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    try histogram.recordValue(12345);

    // All percentiles should return the same value (within quantization precision)
    const p0 = histogram.valueAtPercentile(0.0);
    const p50 = histogram.valueAtPercentile(50.0);
    const p100 = histogram.valueAtPercentile(100.0);

    // All percentiles should be equal (single value)
    try testing.expectEqual(p0, p50);
    try testing.expectEqual(p50, p100);

    // Value should be within 0.1% of original (3 significant figures)
    const expected: u64 = 12345;
    const error_ratio = @as(f64, @floatFromInt(if (p0 > expected) p0 - expected else expected - p0)) / @as(f64, @floatFromInt(expected));
    try testing.expect(error_ratio < 0.001);
}

test "hdr_histogram: percentile on empty histogram" {
    const histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Empty histogram should return 0
    try testing.expectEqual(@as(u64, 0), histogram.valueAtPercentile(50.0));
}

// =============================================================================
// Memory Bounds Tests
// =============================================================================

test "hdr_histogram: bounded memory for default config" {
    const histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Default config (1ns to 1hr, 3 sig figs) should use bounded memory
    // counts_array_length should be calculable and bounded
    try testing.expect(histogram.counts_array_length > 0);
    try testing.expect(histogram.counts_array_length <= 100_000); // Reasonable upper bound
}

test "hdr_histogram: memory does not grow with record count" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    const initial_length = histogram.counts_array_length;

    // Record many values
    var i: u64 = 0;
    while (i < 100_000) : (i += 1) {
        try histogram.recordValue((i % 1_000_000) + 1);
    }

    // Array length should not change
    try testing.expectEqual(initial_length, histogram.counts_array_length);
}

// =============================================================================
// Accuracy Tests
// =============================================================================

test "hdr_histogram: accuracy within significant figures" {
    var histogram = try HdrHistogram.init(testing.allocator, .{
        .significant_figures = 3,
    });
    defer histogram.deinit();

    // Record a specific value
    const test_value: u64 = 123_456_789;
    try histogram.recordValue(test_value);

    // The recorded value should be within 0.1% (3 sig figs) of original
    const recorded_max = histogram.max();
    const error_ratio = @as(f64, @floatFromInt(if (recorded_max > test_value) recorded_max - test_value else test_value - recorded_max)) / @as(f64, @floatFromInt(test_value));
    try testing.expect(error_ratio < 0.001); // 0.1% error
}

test "hdr_histogram: percentile accuracy on bimodal distribution" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // 90% fast responses (1ms), 10% slow responses (100ms)
    const fast_count: u64 = 9000;
    const slow_count: u64 = 1000;

    try histogram.recordValues(1_000_000, fast_count); // 1ms in ns
    try histogram.recordValues(100_000_000, slow_count); // 100ms in ns

    // p50 should be fast (around 1ms)
    const p50 = histogram.valueAtPercentile(50.0);
    try testing.expect(p50 <= 2_000_000); // Should be close to 1ms

    // p95 should still be fast
    const p95 = histogram.valueAtPercentile(95.0);
    try testing.expect(p95 <= 100_000_000); // Should be at or below 100ms

    // p99 should be slow (around 100ms)
    const p99 = histogram.valueAtPercentile(99.0);
    try testing.expect(p99 >= 50_000_000); // Should be close to 100ms
}

// =============================================================================
// Edge Cases
// =============================================================================

test "hdr_histogram: handles zero count for recordValues" {
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // Recording zero count should be a no-op
    try histogram.recordValues(1000, 0);
    try testing.expectEqual(@as(u64, 0), histogram.totalCount());
}

test "hdr_histogram: handles value exactly at unit magnitude boundary" {
    var histogram = try HdrHistogram.init(testing.allocator, .{
        .lowest_trackable_value = 1,
        .highest_trackable_value = 1_000_000_000,
        .significant_figures = 3,
    });
    defer histogram.deinit();

    // Record values at power of 2 boundaries
    try histogram.recordValue(1);
    try histogram.recordValue(2);
    try histogram.recordValue(4);
    try histogram.recordValue(1024);
    try histogram.recordValue(65536);

    try testing.expectEqual(@as(u64, 5), histogram.totalCount());
}

// =============================================================================
// Tiger Style Tests
// =============================================================================

test "hdr_histogram: Tiger Style - all public functions have assertions" {
    // This test documents that the implementation should include
    // at least 2 assertions per public function as per Tiger Style
    var histogram = try HdrHistogram.init(testing.allocator, .{});
    defer histogram.deinit();

    // The implementation should assert:
    // - init: significant_figures in range, value range valid
    // - recordValue: value in range
    // - valueAtPercentile: percentile 0-100

    // These operations should work
    try histogram.recordValue(100);
    _ = histogram.valueAtPercentile(50.0);
    _ = histogram.min();
    _ = histogram.max();
    _ = histogram.mean();
    _ = histogram.totalCount();

    try testing.expect(histogram.totalCount() > 0);
}
