//! Metrics Reducer
//!
//! Post-run metrics computation from event log.
//! Single-pass O(N) algorithm for computing request counts, latency distribution,
//! throughput, connection metrics, and error rates.
//!
//! Tiger Style:
//! - Minimum 2 assertions per function
//! - All loops bounded by event count
//! - No unbounded allocations after init

const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const math = std.math;

const Event = @import("event.zig").Event;
const EventType = @import("event.zig").EventType;
const HdrHistogram = @import("hdr_histogram.zig").HdrHistogram;

// =============================================================================
// Payload Structures (for casting from Event.payload)
// =============================================================================

/// Request issued payload structure
pub const RequestPayload = extern struct {
    request_id: u64,
    method: [8]u8,
    url_hash: u64,
    header_count: u16,
    _pad1: u16,
    body_size: u32,
    _reserved: [208]u8,

    comptime {
        assert(@sizeOf(RequestPayload) == 240);
    }
};

/// Response received payload structure
/// Layout: request_id(8) + status_code(2) + _pad1(2) + header_size(4) + body_size(4) + _pad2(4) + latency_ns(8) + _reserved(208) = 240
pub const ResponsePayload = extern struct {
    request_id: u64,
    status_code: u16,
    _pad1: u16,
    header_size: u32,
    body_size: u32,
    _pad2: u32,
    latency_ns: u64,
    _reserved: [208]u8,

    comptime {
        assert(@sizeOf(ResponsePayload) == 240);
    }
};

/// Connection established payload structure
/// Layout: conn_id(8) + remote_addr_hash(8) + protocol(1) + tls(1) + _pad(6) + conn_time_ns(8) + _reserved(208) = 240
pub const ConnectionPayload = extern struct {
    conn_id: u64,
    remote_addr_hash: u64,
    protocol: u8,
    tls: u8,
    _pad: [6]u8,
    conn_time_ns: u64,
    _reserved: [208]u8,

    comptime {
        assert(@sizeOf(ConnectionPayload) == 240);
    }
};

// =============================================================================
// Metrics Output Structures
// =============================================================================

/// HTTP method enumeration for breakdown
pub const HttpMethod = enum(u8) {
    GET = 0,
    POST = 1,
    PUT = 2,
    DELETE = 3,
    PATCH = 4,
    HEAD = 5,
    OPTIONS = 6,
    OTHER = 7,
};

/// Request metrics
pub const RequestMetrics = struct {
    total: u64,
    success: u64,
    failed: u64,
    success_rate: f64,
    by_method: [8]u64,
    by_status_class: [6]u64, // 1xx, 2xx, 3xx, 4xx, 5xx, other
};

/// Latency metrics (nanoseconds)
pub const LatencyMetrics = struct {
    min_ns: u64,
    max_ns: u64,
    mean_ns: f64,
    p50_ns: u64,
    p90_ns: u64,
    p95_ns: u64,
    p99_ns: u64,
    p999_ns: u64,
    sample_count: u64,
};

/// Throughput metrics
pub const ThroughputMetrics = struct {
    total_duration_ticks: u64,
    requests_per_tick: f64,
    response_count: u64,
};

/// Connection metrics
pub const ConnectionMetrics = struct {
    total_connections: u64,
    connection_errors: u64,
    avg_connection_time_ns: u64,
    total_connection_time_ns: u64,
};

/// Error metrics
pub const ErrorMetrics = struct {
    total_errors: u64,
    dns_errors: u64,
    tcp_errors: u64,
    tls_errors: u64,
    http_errors: u64,
    timeout_errors: u64,
    protocol_errors: u64,
    resource_errors: u64,
    error_rate: f64,
};

/// Complete metrics result
pub const Metrics = struct {
    requests: RequestMetrics,
    latency: LatencyMetrics,
    throughput: ThroughputMetrics,
    connections: ConnectionMetrics,
    errors: ErrorMetrics,
    start_tick: u64,
    end_tick: u64,
};

// =============================================================================
// MetricsReducer
// =============================================================================

pub const MetricsReducer = struct {
    allocator: Allocator,
    histogram: HdrHistogram,

    // Request counters
    request_count: u64,
    success_count: u64,
    response_count: u64,
    by_method: [8]u64,
    by_status_class: [6]u64,

    // Connection counters
    connection_count: u64,
    connection_errors: u64,
    total_conn_time: u64,

    // Error counters (7 types)
    error_counts: [7]u64,

    // Time range
    start_tick: u64,
    end_tick: u64,

    /// Initialize a new MetricsReducer
    pub fn init(allocator: Allocator) !MetricsReducer {
        // Tiger Style: Assert preconditions
        assert(@sizeOf(Event) == 272);
        assert(@sizeOf(RequestPayload) == 240);

        const histogram = try HdrHistogram.init(allocator, .{
            .lowest_trackable_value = 1,
            .highest_trackable_value = 3_600_000_000_000, // 1 hour in ns
            .significant_figures = 3,
        });

        return MetricsReducer{
            .allocator = allocator,
            .histogram = histogram,
            .request_count = 0,
            .success_count = 0,
            .response_count = 0,
            .by_method = [_]u64{0} ** 8,
            .by_status_class = [_]u64{0} ** 6,
            .connection_count = 0,
            .connection_errors = 0,
            .total_conn_time = 0,
            .error_counts = [_]u64{0} ** 7,
            .start_tick = math.maxInt(u64),
            .end_tick = 0,
        };
    }

    /// Free resources
    pub fn deinit(self: *MetricsReducer) void {
        // Tiger Style: Assert valid state
        assert(self.histogram.counts.len > 0);
        assert(self.response_count >= self.success_count);

        self.histogram.deinit();
    }

    /// Reset reducer to initial state
    pub fn reset(self: *MetricsReducer) void {
        // Tiger Style: Assert valid state
        assert(self.histogram.counts.len > 0);
        assert(@sizeOf(Event) == 272);

        self.histogram.reset();
        self.request_count = 0;
        self.success_count = 0;
        self.response_count = 0;
        self.by_method = [_]u64{0} ** 8;
        self.by_status_class = [_]u64{0} ** 6;
        self.connection_count = 0;
        self.connection_errors = 0;
        self.total_conn_time = 0;
        self.error_counts = [_]u64{0} ** 7;
        self.start_tick = math.maxInt(u64);
        self.end_tick = 0;
    }

    /// Process a single event
    pub fn processEvent(self: *MetricsReducer, event: *const Event) !void {
        // Tiger Style: Assert valid state
        assert(self.histogram.counts.len > 0);
        assert(event.payload.len == 240);

        // Track time range
        if (event.header.tick < self.start_tick) {
            self.start_tick = event.header.tick;
        }
        if (event.header.tick > self.end_tick) {
            self.end_tick = event.header.tick;
        }

        switch (event.header.event_type) {
            .request_issued => {
                self.request_count += 1;
                const payload = castPayload(RequestPayload, &event.payload);
                const method_idx = methodToIndex(&payload.method);
                self.by_method[method_idx] += 1;
            },
            .response_received => {
                self.response_count += 1;
                const payload = castPayload(ResponsePayload, &event.payload);

                // Record latency
                if (payload.latency_ns > 0) {
                    self.histogram.recordValue(payload.latency_ns) catch {
                        // Value out of range, skip
                    };
                }

                // Track status class
                const status_class = payload.status_code / 100;
                if (status_class >= 1 and status_class <= 5) {
                    self.by_status_class[status_class - 1] += 1;
                } else {
                    self.by_status_class[5] += 1; // other
                }

                // Track success
                if (payload.status_code < 400) {
                    self.success_count += 1;
                }
            },
            .conn_established => {
                self.connection_count += 1;
                const payload = castPayload(ConnectionPayload, &event.payload);
                self.total_conn_time += payload.conn_time_ns;
            },
            .conn_error => {
                self.connection_errors += 1;
            },
            .error_dns => self.error_counts[0] += 1,
            .error_tcp => self.error_counts[1] += 1,
            .error_tls => self.error_counts[2] += 1,
            .error_http => self.error_counts[3] += 1,
            .error_timeout => self.error_counts[4] += 1,
            .error_protocol_violation => self.error_counts[5] += 1,
            .error_resource_exhausted => self.error_counts[6] += 1,
            else => {}, // Ignore other event types
        }
    }

    /// Compute final metrics from accumulated data
    pub fn compute(self: *const MetricsReducer) Metrics {
        // Tiger Style: Assert valid state
        assert(self.histogram.counts.len > 0);
        assert(self.response_count >= self.success_count);

        // Calculate total errors
        var total_errors: u64 = 0;
        for (self.error_counts) |count| {
            total_errors += count;
        }

        // Calculate failed requests (responses with status >= 400 or errors)
        const failed = if (self.response_count > self.success_count)
            self.response_count - self.success_count
        else
            0;

        // Calculate rates
        const success_rate = if (self.response_count > 0)
            @as(f64, @floatFromInt(self.success_count)) / @as(f64, @floatFromInt(self.response_count))
        else
            0.0;

        const error_rate = if (self.request_count > 0)
            @as(f64, @floatFromInt(total_errors)) / @as(f64, @floatFromInt(self.request_count))
        else
            0.0;

        // Calculate throughput
        const duration = if (self.end_tick > self.start_tick)
            self.end_tick - self.start_tick
        else
            0;

        const requests_per_tick = if (duration > 0)
            @as(f64, @floatFromInt(self.response_count)) / @as(f64, @floatFromInt(duration))
        else
            0.0;

        // Calculate average connection time
        const avg_conn_time = if (self.connection_count > 0)
            self.total_conn_time / self.connection_count
        else
            0;

        return Metrics{
            .requests = RequestMetrics{
                .total = self.request_count,
                .success = self.success_count,
                .failed = failed,
                .success_rate = success_rate,
                .by_method = self.by_method,
                .by_status_class = self.by_status_class,
            },
            .latency = LatencyMetrics{
                .min_ns = self.histogram.min(),
                .max_ns = self.histogram.max(),
                .mean_ns = self.histogram.mean(),
                .p50_ns = self.histogram.valueAtPercentile(50.0),
                .p90_ns = self.histogram.valueAtPercentile(90.0),
                .p95_ns = self.histogram.valueAtPercentile(95.0),
                .p99_ns = self.histogram.valueAtPercentile(99.0),
                .p999_ns = self.histogram.valueAtPercentile(99.9),
                .sample_count = self.histogram.totalCount(),
            },
            .throughput = ThroughputMetrics{
                .total_duration_ticks = duration,
                .requests_per_tick = requests_per_tick,
                .response_count = self.response_count,
            },
            .connections = ConnectionMetrics{
                .total_connections = self.connection_count,
                .connection_errors = self.connection_errors,
                .avg_connection_time_ns = avg_conn_time,
                .total_connection_time_ns = self.total_conn_time,
            },
            .errors = ErrorMetrics{
                .total_errors = total_errors,
                .dns_errors = self.error_counts[0],
                .tcp_errors = self.error_counts[1],
                .tls_errors = self.error_counts[2],
                .http_errors = self.error_counts[3],
                .timeout_errors = self.error_counts[4],
                .protocol_errors = self.error_counts[5],
                .resource_errors = self.error_counts[6],
                .error_rate = error_rate,
            },
            .start_tick = self.start_tick,
            .end_tick = self.end_tick,
        };
    }
};

// =============================================================================
// Convenience Functions
// =============================================================================

/// Reduce a slice of events to metrics in a single pass
pub fn reduce(allocator: Allocator, events: []const Event) !Metrics {
    // Tiger Style: Assert preconditions
    assert(@sizeOf(Event) == 272);
    assert(events.len <= 10_000_000); // Max 10M events per METRICS.md

    var reducer = try MetricsReducer.init(allocator);
    defer reducer.deinit();

    // Single pass over all events (bounded by events.len)
    for (events) |*event| {
        try reducer.processEvent(event);
    }

    return reducer.compute();
}

// =============================================================================
// Helper Functions
// =============================================================================

/// Cast payload bytes to typed structure
fn castPayload(comptime T: type, payload: *const [240]u8) *const T {
    assert(@sizeOf(T) == 240);
    return @ptrCast(@alignCast(payload));
}

/// Map HTTP method string to index
fn methodToIndex(method: *const [8]u8) u8 {
    // Check common methods first for performance
    if (method[0] == 'G' and method[1] == 'E' and method[2] == 'T') {
        return @intFromEnum(HttpMethod.GET);
    }
    if (method[0] == 'P' and method[1] == 'O' and method[2] == 'S' and method[3] == 'T') {
        return @intFromEnum(HttpMethod.POST);
    }
    if (method[0] == 'P' and method[1] == 'U' and method[2] == 'T') {
        return @intFromEnum(HttpMethod.PUT);
    }
    if (method[0] == 'D' and method[1] == 'E' and method[2] == 'L') {
        return @intFromEnum(HttpMethod.DELETE);
    }
    if (method[0] == 'P' and method[1] == 'A' and method[2] == 'T') {
        return @intFromEnum(HttpMethod.PATCH);
    }
    if (method[0] == 'H' and method[1] == 'E' and method[2] == 'A') {
        return @intFromEnum(HttpMethod.HEAD);
    }
    if (method[0] == 'O' and method[1] == 'P' and method[2] == 'T') {
        return @intFromEnum(HttpMethod.OPTIONS);
    }
    return @intFromEnum(HttpMethod.OTHER);
}

// =============================================================================
// Tests
// =============================================================================

test "metrics: method index mapping" {
    var method: [8]u8 = undefined;

    @memcpy(method[0..3], "GET");
    try std.testing.expectEqual(@as(u8, 0), methodToIndex(&method));

    @memcpy(method[0..4], "POST");
    try std.testing.expectEqual(@as(u8, 1), methodToIndex(&method));

    @memcpy(method[0..3], "PUT");
    try std.testing.expectEqual(@as(u8, 2), methodToIndex(&method));

    @memcpy(method[0..6], "DELETE");
    try std.testing.expectEqual(@as(u8, 3), methodToIndex(&method));

    @memcpy(method[0..5], "PATCH");
    try std.testing.expectEqual(@as(u8, 4), methodToIndex(&method));

    @memcpy(method[0..4], "HEAD");
    try std.testing.expectEqual(@as(u8, 5), methodToIndex(&method));

    @memcpy(method[0..7], "OPTIONS");
    try std.testing.expectEqual(@as(u8, 6), methodToIndex(&method));

    @memcpy(method[0..5], "XYZAB");
    try std.testing.expectEqual(@as(u8, 7), methodToIndex(&method));
}

test "metrics: payload size checks" {
    try std.testing.expectEqual(@as(usize, 240), @sizeOf(RequestPayload));
    try std.testing.expectEqual(@as(usize, 240), @sizeOf(ResponsePayload));
    try std.testing.expectEqual(@as(usize, 240), @sizeOf(ConnectionPayload));
}
