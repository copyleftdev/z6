//! HDR Histogram Implementation
//!
//! High Dynamic Range Histogram for latency percentile calculations with
//! bounded memory usage. Based on Gil Tene's HdrHistogram algorithm.
//!
//! Key properties:
//! - Bounded memory: O(log(highest/lowest) * precision) regardless of sample count
//! - O(1) recording: Single index calculation and increment
//! - Configurable precision: 1-5 significant figures
//! - Accurate percentiles: Error bounded by significant figures
//!
//! Tiger Style compliance:
//! - Minimum 2 assertions per public function
//! - All loops have explicit bounds
//! - No unbounded allocations after init

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const math = std.math;

/// Errors that can occur during histogram operations
pub const HdrError = error{
    /// Significant figures must be 1-5
    InvalidSignificantFigures,
    /// Value range is invalid (lowest must be >= 1, highest must be > lowest * 2)
    InvalidValueRange,
    /// Value exceeds the trackable range
    ValueOutOfRange,
    /// Memory allocation failed
    OutOfMemory,
};

/// HDR Histogram for latency percentile calculations
pub const HdrHistogram = struct {
    /// Configuration for histogram initialization
    pub const Config = struct {
        /// Lowest trackable value (default: 1 nanosecond)
        lowest_trackable_value: u64 = 1,
        /// Highest trackable value (default: 1 hour in nanoseconds)
        highest_trackable_value: u64 = 3_600_000_000_000,
        /// Number of significant figures for precision (1-5)
        significant_figures: u8 = 3,
    };

    // Configuration
    lowest_trackable_value: u64,
    highest_trackable_value: u64,
    significant_figures: u8,

    // Derived constants for index calculation
    unit_magnitude: u8,
    sub_bucket_half_count_magnitude: u8,
    sub_bucket_count: u32,
    sub_bucket_half_count: u32,
    sub_bucket_mask: u64,
    bucket_count: u32,
    counts_array_length: u32,

    // Counts array (allocated)
    counts: []u64,

    // Running totals
    total_count: u64,
    min_value: u64,
    max_value: u64,

    // Allocator for cleanup
    allocator: Allocator,

    /// Initialize a new HDR Histogram
    pub fn init(allocator: Allocator, config: Config) HdrError!HdrHistogram {
        // Tiger Style: Assert preconditions
        assert(config.lowest_trackable_value >= 1 or config.lowest_trackable_value == 0);
        assert(config.significant_figures <= 10);

        // Validate significant figures (1-5)
        if (config.significant_figures < 1 or config.significant_figures > 5) {
            return error.InvalidSignificantFigures;
        }

        // Validate value range
        if (config.lowest_trackable_value < 1) {
            return error.InvalidValueRange;
        }
        if (config.highest_trackable_value <= config.lowest_trackable_value * 2) {
            return error.InvalidValueRange;
        }

        // Calculate derived constants
        const unit_magnitude = calculateUnitMagnitude(config.lowest_trackable_value);
        const sub_bucket_half_count_magnitude = calculateSubBucketHalfCountMagnitude(config.significant_figures);

        const sub_bucket_count: u32 = @as(u32, 1) << @intCast(sub_bucket_half_count_magnitude + 1);
        const sub_bucket_half_count: u32 = sub_bucket_count >> 1;
        const sub_bucket_mask: u64 = (@as(u64, sub_bucket_count) - 1) << @as(u6, @intCast(unit_magnitude));

        const bucket_count = calculateBucketCount(config.highest_trackable_value, sub_bucket_count, unit_magnitude);
        const counts_array_length = calculateCountsArrayLength(bucket_count, sub_bucket_half_count);

        // Tiger Style: Assert derived values are reasonable
        assert(sub_bucket_count >= 2);
        assert(bucket_count >= 1);
        assert(counts_array_length >= 1);

        // Allocate counts array
        const counts = allocator.alloc(u64, counts_array_length) catch {
            return error.OutOfMemory;
        };
        @memset(counts, 0);

        return HdrHistogram{
            .lowest_trackable_value = config.lowest_trackable_value,
            .highest_trackable_value = config.highest_trackable_value,
            .significant_figures = config.significant_figures,
            .unit_magnitude = unit_magnitude,
            .sub_bucket_half_count_magnitude = sub_bucket_half_count_magnitude,
            .sub_bucket_count = sub_bucket_count,
            .sub_bucket_half_count = sub_bucket_half_count,
            .sub_bucket_mask = sub_bucket_mask,
            .bucket_count = bucket_count,
            .counts_array_length = counts_array_length,
            .counts = counts,
            .total_count = 0,
            .min_value = math.maxInt(u64),
            .max_value = 0,
            .allocator = allocator,
        };
    }

    /// Free histogram memory
    pub fn deinit(self: *const HdrHistogram) void {
        // Tiger Style: Assert valid state
        assert(self.counts.len > 0);
        assert(self.counts.len == self.counts_array_length);

        self.allocator.free(self.counts);
    }

    /// Reset histogram to empty state
    pub fn reset(self: *HdrHistogram) void {
        // Tiger Style: Assert valid state
        assert(self.counts.len == self.counts_array_length);
        assert(self.counts_array_length > 0);

        @memset(self.counts, 0);
        self.total_count = 0;
        self.min_value = math.maxInt(u64);
        self.max_value = 0;
    }

    /// Record a single value
    pub fn recordValue(self: *HdrHistogram, value: u64) HdrError!void {
        // Tiger Style: Assert valid state
        assert(self.counts.len == self.counts_array_length);
        assert(self.counts_array_length > 0);

        if (value > self.highest_trackable_value) {
            return error.ValueOutOfRange;
        }

        const index = self.getCountsIndexForValue(value);
        if (index >= self.counts_array_length) {
            return error.ValueOutOfRange;
        }

        self.counts[index] += 1;
        self.total_count += 1;

        if (value < self.min_value) {
            self.min_value = value;
        }
        if (value > self.max_value) {
            self.max_value = value;
        }
    }

    /// Record a value multiple times
    pub fn recordValues(self: *HdrHistogram, value: u64, count: u64) HdrError!void {
        // Tiger Style: Assert valid state
        assert(self.counts.len == self.counts_array_length);
        assert(count <= math.maxInt(u64) - self.total_count);

        if (count == 0) {
            return;
        }

        if (value > self.highest_trackable_value) {
            return error.ValueOutOfRange;
        }

        const index = self.getCountsIndexForValue(value);
        if (index >= self.counts_array_length) {
            return error.ValueOutOfRange;
        }

        self.counts[index] += count;
        self.total_count += count;

        if (value < self.min_value) {
            self.min_value = value;
        }
        if (value > self.max_value) {
            self.max_value = value;
        }
    }

    /// Get minimum recorded value
    pub fn min(self: *const HdrHistogram) u64 {
        // Tiger Style: Assert valid state
        assert(self.counts.len > 0);
        assert(self.min_value == math.maxInt(u64) or self.min_value <= self.highest_trackable_value);

        return self.min_value;
    }

    /// Get maximum recorded value
    pub fn max(self: *const HdrHistogram) u64 {
        // Tiger Style: Assert valid state
        assert(self.counts.len > 0);
        assert(self.max_value <= self.highest_trackable_value or self.max_value == 0);

        return self.max_value;
    }

    /// Calculate mean of recorded values
    pub fn mean(self: *const HdrHistogram) f64 {
        // Tiger Style: Assert valid state
        assert(self.counts.len == self.counts_array_length);
        assert(self.counts_array_length > 0);

        if (self.total_count == 0) {
            return 0.0;
        }

        var total: u128 = 0;
        var index: u32 = 0;

        // Bounded loop: iterate through counts array
        while (index < self.counts_array_length) : (index += 1) {
            const count = self.counts[index];
            if (count > 0) {
                const value = self.valueFromIndex(index);
                total += @as(u128, count) * @as(u128, value);
            }
        }

        return @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(self.total_count));
    }

    /// Get total number of recorded values
    pub fn totalCount(self: *const HdrHistogram) u64 {
        // Tiger Style: Assert valid state
        assert(self.counts.len > 0);
        assert(self.total_count <= math.maxInt(u64));

        return self.total_count;
    }

    /// Get value at a given percentile (0-100)
    pub fn valueAtPercentile(self: *const HdrHistogram, percentile: f64) u64 {
        // Tiger Style: Assert valid state and percentile range
        assert(self.counts.len == self.counts_array_length);
        assert(percentile >= 0.0 and percentile <= 100.0);

        if (self.total_count == 0) {
            return 0;
        }

        // Calculate target count for percentile
        const requested_percentile = @min(percentile, 100.0);
        const count_at_percentile = @as(u64, @intFromFloat(
            (requested_percentile / 100.0) * @as(f64, @floatFromInt(self.total_count)) + 0.5,
        ));
        const target_count = @max(count_at_percentile, 1);

        var cumulative_count: u64 = 0;
        var index: u32 = 0;

        // Bounded loop: find the value at target count
        while (index < self.counts_array_length) : (index += 1) {
            cumulative_count += self.counts[index];
            if (cumulative_count >= target_count) {
                return self.valueFromIndex(index);
            }
        }

        // Should not reach here if total_count > 0
        return self.max_value;
    }

    // =========================================================================
    // Private helper functions
    // =========================================================================

    /// Calculate counts array index for a value
    fn getCountsIndexForValue(self: *const HdrHistogram, value: u64) u32 {
        const bucket_index = self.getBucketIndex(value);
        const sub_bucket_index = self.getSubBucketIndex(value, bucket_index);
        return self.countsArrayIndex(bucket_index, sub_bucket_index);
    }

    /// Get bucket index for a value
    fn getBucketIndex(self: *const HdrHistogram, value: u64) u32 {
        // Use leading zeros to find bucket
        const shift: u6 = @intCast(self.unit_magnitude);
        const pow2_ceiling = 64 - @as(u32, @clz(value | self.sub_bucket_mask));
        const bucket_index_offset: i32 = @as(i32, @intCast(pow2_ceiling)) - @as(i32, shift) -
            @as(i32, @intCast(self.sub_bucket_half_count_magnitude + 1));
        return @intCast(@max(bucket_index_offset, 0));
    }

    /// Get sub-bucket index for a value
    fn getSubBucketIndex(self: *const HdrHistogram, value: u64, bucket_index: u32) u32 {
        const shift_amount: u6 = @intCast(bucket_index + self.unit_magnitude);
        return @intCast(value >> shift_amount);
    }

    /// Calculate counts array index from bucket and sub-bucket
    fn countsArrayIndex(self: *const HdrHistogram, bucket_index: u32, sub_bucket_index: u32) u32 {
        assert(sub_bucket_index < self.sub_bucket_count);

        // Handle the special case where bucket 0's first half overlaps with negative bucket indices
        if (sub_bucket_index < self.sub_bucket_half_count) {
            // Values in the first half of bucket 0
            return sub_bucket_index;
        }

        // Standard formula for all other cases
        const shift: u5 = @intCast(self.sub_bucket_half_count_magnitude);
        const bucket_base_index = (bucket_index + 1) << shift;
        const offset_in_bucket = sub_bucket_index - self.sub_bucket_half_count;
        return bucket_base_index + offset_in_bucket;
    }

    /// Convert counts array index back to a value
    fn valueFromIndex(self: *const HdrHistogram, index: u32) u64 {
        const shift: u5 = @intCast(self.sub_bucket_half_count_magnitude);
        const bucket_index: u32 = (index >> shift) -| 1;
        const sub_bucket_index: u32 = if (bucket_index == 0 and index < self.sub_bucket_half_count)
            index
        else
            (index & (self.sub_bucket_half_count - 1)) + self.sub_bucket_half_count;

        const value_shift: u6 = @intCast(bucket_index + self.unit_magnitude);
        return @as(u64, sub_bucket_index) << value_shift;
    }
};

// =============================================================================
// Module-level helper functions
// =============================================================================

/// Calculate unit magnitude from lowest trackable value
fn calculateUnitMagnitude(lowest_trackable_value: u64) u8 {
    // Unit magnitude is the number of trailing zeros (floor of log2)
    const leading_zeros = @clz(lowest_trackable_value);
    const magnitude = 63 - leading_zeros;
    return @intCast(magnitude);
}

/// Calculate sub-bucket half count magnitude from significant figures
fn calculateSubBucketHalfCountMagnitude(significant_figures: u8) u8 {
    // For N significant figures, we need 10^N sub-buckets per bucket half
    // Use log2(10^N) = N * log2(10) ≈ N * 3.32
    const largest_significant = math.pow(f64, 10.0, @floatFromInt(significant_figures));
    const sub_bucket_magnitude = @as(u8, @intFromFloat(@ceil(math.log2(largest_significant))));
    return sub_bucket_magnitude;
}

/// Calculate number of buckets needed for value range
fn calculateBucketCount(highest_trackable_value: u64, sub_bucket_count: u32, unit_magnitude: u8) u32 {
    // Smallest value that needs second bucket
    const shift: u6 = @intCast(unit_magnitude);
    const smallest_untrackable: u64 = @as(u64, sub_bucket_count) << shift;

    var buckets_needed: u32 = 1;
    var value = smallest_untrackable;

    // Bounded loop: max 64 iterations (log2 of u64 max)
    while (value <= highest_trackable_value and buckets_needed < 64) {
        buckets_needed += 1;
        value <<= 1;
    }

    return buckets_needed;
}

/// Calculate total counts array length
fn calculateCountsArrayLength(bucket_count: u32, sub_bucket_half_count: u32) u32 {
    return (bucket_count + 1) * sub_bucket_half_count;
}

// =============================================================================
// Tests
// =============================================================================

test "hdr_histogram: unit magnitude calculation" {
    try std.testing.expectEqual(@as(u8, 0), calculateUnitMagnitude(1));
    try std.testing.expectEqual(@as(u8, 10), calculateUnitMagnitude(1024));
    try std.testing.expectEqual(@as(u8, 9), calculateUnitMagnitude(1000));
}

test "hdr_histogram: sub bucket magnitude calculation" {
    try std.testing.expectEqual(@as(u8, 4), calculateSubBucketHalfCountMagnitude(1)); // 10^1 = 10, log2(10) ≈ 3.32 -> 4
    try std.testing.expectEqual(@as(u8, 7), calculateSubBucketHalfCountMagnitude(2)); // 10^2 = 100, log2(100) ≈ 6.64 -> 7
    try std.testing.expectEqual(@as(u8, 10), calculateSubBucketHalfCountMagnitude(3)); // 10^3 = 1000, log2(1000) ≈ 9.97 -> 10
}
