//! Metrics Reducer Tests
//!
//! Test-Driven Development: These tests verify metrics computation.
//! Following Tiger Style: Test before implement.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const MetricsReducer = z6.MetricsReducer;
const Metrics = z6.Metrics;
const Event = z6.Event;
const EventType = z6.EventType;
const RequestPayload = z6.RequestPayload;
const ResponsePayload = z6.ResponsePayload;
const ConnectionPayload = z6.ConnectionPayload;

// =============================================================================
// Test Helpers
// =============================================================================

fn createEvent(event_type: EventType, tick: u64, vu_id: u32) Event {
    var event: Event = undefined;
    @memset(&event.payload, 0);
    event.header = .{
        .tick = tick,
        .vu_id = vu_id,
        .event_type = event_type,
        ._padding = 0,
        ._reserved = 0,
    };
    event.checksum = 0;
    return event;
}

fn createRequestEvent(tick: u64, vu_id: u32, method: []const u8) Event {
    var event = createEvent(.request_issued, tick, vu_id);
    const payload = @as(*RequestPayload, @ptrCast(@alignCast(&event.payload)));
    payload.request_id = tick;
    @memset(&payload.method, 0);
    @memcpy(payload.method[0..method.len], method);
    return event;
}

fn createResponseEvent(tick: u64, vu_id: u32, status_code: u16, latency_ns: u64) Event {
    var event = createEvent(.response_received, tick, vu_id);
    const payload = @as(*ResponsePayload, @ptrCast(@alignCast(&event.payload)));
    payload.request_id = tick;
    payload.status_code = status_code;
    payload.latency_ns = latency_ns;
    return event;
}

fn createConnectionEvent(tick: u64, vu_id: u32, conn_time_ns: u64) Event {
    var event = createEvent(.conn_established, tick, vu_id);
    const payload = @as(*ConnectionPayload, @ptrCast(@alignCast(&event.payload)));
    payload.conn_id = tick;
    payload.conn_time_ns = conn_time_ns;
    return event;
}

// =============================================================================
// Init/Deinit Tests
// =============================================================================

test "metrics: reducer init and deinit" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // Should start with zero counts
    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 0), metrics.requests.total);
    try testing.expectEqual(@as(u64, 0), metrics.latency.sample_count);
    try testing.expectEqual(@as(u64, 0), metrics.connections.total_connections);
    try testing.expectEqual(@as(u64, 0), metrics.errors.total_errors);
}

test "metrics: reducer reset" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // Process some events
    var req_event = createRequestEvent(100, 1, "GET");
    try reducer.processEvent(&req_event);

    var resp_event = createResponseEvent(200, 1, 200, 1_000_000);
    try reducer.processEvent(&resp_event);

    try testing.expectEqual(@as(u64, 1), reducer.request_count);

    // Reset
    reducer.reset();
    try testing.expectEqual(@as(u64, 0), reducer.request_count);
    try testing.expectEqual(@as(u64, 0), reducer.response_count);
}

// =============================================================================
// Request Count Tests
// =============================================================================

test "metrics: empty event list" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 0), metrics.requests.total);
    try testing.expectEqual(@as(f64, 0.0), metrics.requests.success_rate);
}

test "metrics: single request" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    var event = createRequestEvent(100, 1, "GET");
    try reducer.processEvent(&event);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 1), metrics.requests.total);
    try testing.expectEqual(@as(u64, 1), metrics.requests.by_method[0]); // GET
}

test "metrics: multiple requests with different methods" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    var get_event = createRequestEvent(100, 1, "GET");
    try reducer.processEvent(&get_event);

    var post_event = createRequestEvent(200, 1, "POST");
    try reducer.processEvent(&post_event);

    var put_event = createRequestEvent(300, 1, "PUT");
    try reducer.processEvent(&put_event);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 3), metrics.requests.total);
    try testing.expectEqual(@as(u64, 1), metrics.requests.by_method[0]); // GET
    try testing.expectEqual(@as(u64, 1), metrics.requests.by_method[1]); // POST
    try testing.expectEqual(@as(u64, 1), metrics.requests.by_method[2]); // PUT
}

test "metrics: request method breakdown" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // 5 GET, 3 POST, 2 DELETE
    var i: u64 = 0;
    while (i < 5) : (i += 1) {
        var event = createRequestEvent(i * 10, 1, "GET");
        try reducer.processEvent(&event);
    }
    while (i < 8) : (i += 1) {
        var event = createRequestEvent(i * 10, 1, "POST");
        try reducer.processEvent(&event);
    }
    while (i < 10) : (i += 1) {
        var event = createRequestEvent(i * 10, 1, "DELETE");
        try reducer.processEvent(&event);
    }

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 10), metrics.requests.total);
    try testing.expectEqual(@as(u64, 5), metrics.requests.by_method[0]); // GET
    try testing.expectEqual(@as(u64, 3), metrics.requests.by_method[1]); // POST
    try testing.expectEqual(@as(u64, 2), metrics.requests.by_method[3]); // DELETE
}

// =============================================================================
// Latency Tests
// =============================================================================

test "metrics: single response latency" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    var event = createResponseEvent(100, 1, 200, 5_000_000); // 5ms
    try reducer.processEvent(&event);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 1), metrics.latency.sample_count);
    // Min and max should be close to recorded value (within HDR precision)
    try testing.expect(metrics.latency.min_ns <= 5_000_000);
    try testing.expect(metrics.latency.max_ns >= 5_000_000);
}

test "metrics: multiple response latencies" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // Record latencies: 1ms, 2ms, 3ms, 4ms, 5ms
    var i: u64 = 1;
    while (i <= 5) : (i += 1) {
        var event = createResponseEvent(i * 100, 1, 200, i * 1_000_000);
        try reducer.processEvent(&event);
    }

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 5), metrics.latency.sample_count);
    try testing.expect(metrics.latency.min_ns <= 1_000_000);
    try testing.expect(metrics.latency.max_ns >= 5_000_000);
    // Mean should be around 3ms
    try testing.expect(metrics.latency.mean_ns >= 2_500_000);
    try testing.expect(metrics.latency.mean_ns <= 3_500_000);
}

test "metrics: percentile calculations" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // Record 100 latencies: 1ms, 2ms, ..., 100ms
    var i: u64 = 1;
    while (i <= 100) : (i += 1) {
        var event = createResponseEvent(i * 100, 1, 200, i * 1_000_000);
        try reducer.processEvent(&event);
    }

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 100), metrics.latency.sample_count);

    // p50 should be around 50ms
    try testing.expect(metrics.latency.p50_ns >= 49_000_000);
    try testing.expect(metrics.latency.p50_ns <= 51_000_000);

    // p99 should be around 99ms
    try testing.expect(metrics.latency.p99_ns >= 98_000_000);
    try testing.expect(metrics.latency.p99_ns <= 100_000_000);
}

// =============================================================================
// Success/Failure Tests
// =============================================================================

test "metrics: all successful responses" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    var i: u64 = 0;
    while (i < 10) : (i += 1) {
        var event = createResponseEvent(i * 100, 1, 200, 1_000_000);
        try reducer.processEvent(&event);
    }

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 10), metrics.requests.success);
    try testing.expectEqual(@as(u64, 0), metrics.requests.failed);
    try testing.expectEqual(@as(f64, 1.0), metrics.requests.success_rate);
}

test "metrics: mixed success and failure responses" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // 8 success (200), 2 failures (500)
    var i: u64 = 0;
    while (i < 8) : (i += 1) {
        var event = createResponseEvent(i * 100, 1, 200, 1_000_000);
        try reducer.processEvent(&event);
    }
    while (i < 10) : (i += 1) {
        var event = createResponseEvent(i * 100, 1, 500, 1_000_000);
        try reducer.processEvent(&event);
    }

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 8), metrics.requests.success);
    try testing.expectEqual(@as(u64, 2), metrics.requests.failed);
    try testing.expectEqual(@as(f64, 0.8), metrics.requests.success_rate);
}

test "metrics: status class breakdown" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // Various status codes
    var e1 = createResponseEvent(100, 1, 200, 1_000_000); // 2xx
    var e2 = createResponseEvent(200, 1, 201, 1_000_000); // 2xx
    var e3 = createResponseEvent(300, 1, 301, 1_000_000); // 3xx
    var e4 = createResponseEvent(400, 1, 404, 1_000_000); // 4xx
    var e5 = createResponseEvent(500, 1, 500, 1_000_000); // 5xx

    try reducer.processEvent(&e1);
    try reducer.processEvent(&e2);
    try reducer.processEvent(&e3);
    try reducer.processEvent(&e4);
    try reducer.processEvent(&e5);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 2), metrics.requests.by_status_class[1]); // 2xx
    try testing.expectEqual(@as(u64, 1), metrics.requests.by_status_class[2]); // 3xx
    try testing.expectEqual(@as(u64, 1), metrics.requests.by_status_class[3]); // 4xx
    try testing.expectEqual(@as(u64, 1), metrics.requests.by_status_class[4]); // 5xx
}

// =============================================================================
// Connection Tests
// =============================================================================

test "metrics: connection count" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    var i: u64 = 0;
    while (i < 5) : (i += 1) {
        var event = createConnectionEvent(i * 100, 1, 10_000_000); // 10ms each
        try reducer.processEvent(&event);
    }

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 5), metrics.connections.total_connections);
    try testing.expectEqual(@as(u64, 50_000_000), metrics.connections.total_connection_time_ns);
    try testing.expectEqual(@as(u64, 10_000_000), metrics.connections.avg_connection_time_ns);
}

test "metrics: connection errors" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    var conn_event = createConnectionEvent(100, 1, 10_000_000);
    try reducer.processEvent(&conn_event);

    var err_event = createEvent(.conn_error, 200, 1);
    try reducer.processEvent(&err_event);

    var err_event2 = createEvent(.conn_error, 300, 1);
    try reducer.processEvent(&err_event2);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 1), metrics.connections.total_connections);
    try testing.expectEqual(@as(u64, 2), metrics.connections.connection_errors);
}

// =============================================================================
// Error Tests
// =============================================================================

test "metrics: no errors" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    var event = createResponseEvent(100, 1, 200, 1_000_000);
    try reducer.processEvent(&event);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 0), metrics.errors.total_errors);
    try testing.expectEqual(@as(f64, 0.0), metrics.errors.error_rate);
}

test "metrics: error type breakdown" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // One request to establish baseline
    var req = createRequestEvent(50, 1, "GET");
    try reducer.processEvent(&req);

    // Various error types
    var dns_err = createEvent(.error_dns, 100, 1);
    var tcp_err = createEvent(.error_tcp, 200, 1);
    var tls_err = createEvent(.error_tls, 300, 1);
    var http_err = createEvent(.error_http, 400, 1);
    var timeout_err = createEvent(.error_timeout, 500, 1);

    try reducer.processEvent(&dns_err);
    try reducer.processEvent(&tcp_err);
    try reducer.processEvent(&tls_err);
    try reducer.processEvent(&http_err);
    try reducer.processEvent(&timeout_err);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 5), metrics.errors.total_errors);
    try testing.expectEqual(@as(u64, 1), metrics.errors.dns_errors);
    try testing.expectEqual(@as(u64, 1), metrics.errors.tcp_errors);
    try testing.expectEqual(@as(u64, 1), metrics.errors.tls_errors);
    try testing.expectEqual(@as(u64, 1), metrics.errors.http_errors);
    try testing.expectEqual(@as(u64, 1), metrics.errors.timeout_errors);
}

test "metrics: error rate calculation" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // 10 requests, 2 errors
    var i: u64 = 0;
    while (i < 10) : (i += 1) {
        var event = createRequestEvent(i * 100, 1, "GET");
        try reducer.processEvent(&event);
    }

    var err1 = createEvent(.error_timeout, 1000, 1);
    var err2 = createEvent(.error_tcp, 1100, 1);
    try reducer.processEvent(&err1);
    try reducer.processEvent(&err2);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 2), metrics.errors.total_errors);
    try testing.expectEqual(@as(f64, 0.2), metrics.errors.error_rate);
}

// =============================================================================
// Throughput Tests
// =============================================================================

test "metrics: throughput calculation" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // 10 responses over 100 ticks (tick 0 to tick 100)
    var i: u64 = 0;
    while (i < 10) : (i += 1) {
        var event = createResponseEvent(i * 10, 1, 200, 1_000_000);
        try reducer.processEvent(&event);
    }

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 10), metrics.throughput.response_count);
    try testing.expectEqual(@as(u64, 90), metrics.throughput.total_duration_ticks); // 90 - 0 = 90
    // 10 responses / 90 ticks ≈ 0.111
    try testing.expect(metrics.throughput.requests_per_tick > 0.1);
    try testing.expect(metrics.throughput.requests_per_tick < 0.12);
}

test "metrics: zero duration throughput" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // All events at same tick
    var i: u64 = 0;
    while (i < 5) : (i += 1) {
        var event = createResponseEvent(100, @intCast(i), 200, 1_000_000);
        try reducer.processEvent(&event);
    }

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 5), metrics.throughput.response_count);
    try testing.expectEqual(@as(u64, 0), metrics.throughput.total_duration_ticks);
    try testing.expectEqual(@as(f64, 0.0), metrics.throughput.requests_per_tick);
}

// =============================================================================
// Time Range Tests
// =============================================================================

test "metrics: time range tracking" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    var e1 = createRequestEvent(500, 1, "GET");
    var e2 = createRequestEvent(100, 1, "GET");
    var e3 = createRequestEvent(900, 1, "GET");
    var e4 = createRequestEvent(300, 1, "GET");

    try reducer.processEvent(&e1);
    try reducer.processEvent(&e2);
    try reducer.processEvent(&e3);
    try reducer.processEvent(&e4);

    const metrics = reducer.compute();
    try testing.expectEqual(@as(u64, 100), metrics.start_tick);
    try testing.expectEqual(@as(u64, 900), metrics.end_tick);
}

// =============================================================================
// Reduce Function Tests
// =============================================================================

test "metrics: reduce convenience function" {
    var events: [5]Event = undefined;
    events[0] = createRequestEvent(100, 1, "GET");
    events[1] = createResponseEvent(200, 1, 200, 5_000_000);
    events[2] = createRequestEvent(300, 1, "POST");
    events[3] = createResponseEvent(400, 1, 201, 10_000_000);
    events[4] = createConnectionEvent(50, 1, 1_000_000);

    const metrics = try z6.reduce(testing.allocator, &events);

    try testing.expectEqual(@as(u64, 2), metrics.requests.total);
    try testing.expectEqual(@as(u64, 2), metrics.latency.sample_count);
    try testing.expectEqual(@as(u64, 1), metrics.connections.total_connections);
}

// =============================================================================
// Tiger Style Tests
// =============================================================================

test "metrics: Tiger Style - assertions verified" {
    var reducer = try MetricsReducer.init(testing.allocator);
    defer reducer.deinit();

    // Process various events
    var req = createRequestEvent(100, 1, "GET");
    var resp = createResponseEvent(200, 1, 200, 1_000_000);
    var conn = createConnectionEvent(50, 1, 500_000);

    try reducer.processEvent(&req);
    try reducer.processEvent(&resp);
    try reducer.processEvent(&conn);

    const metrics = reducer.compute();

    // Verify all metrics are populated
    try testing.expect(metrics.requests.total > 0);
    try testing.expect(metrics.latency.sample_count > 0);
    try testing.expect(metrics.connections.total_connections > 0);
}
