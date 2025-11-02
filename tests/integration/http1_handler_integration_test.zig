//! HTTP/1.1 Handler Integration Test
//!
//! Tests the HTTP/1.1 handler with a simple echo server.
//! Note: This is a basic integration test. Full TLS testing requires BoringSSL.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const HTTP1Handler = z6.HTTP1Handler;
const ProtocolConfig = z6.ProtocolConfig;
const HTTPConfig = z6.HTTPConfig;
const Target = z6.Target;
const Request = z6.Request;
const Method = z6.Method;
const Header = z6.Header;
const CompletionQueue = z6.CompletionQueue;

test "http1_handler_integration: basic request/response flow" {
    // Note: This test is currently limited because we need a real HTTP server.
    // In production, we would:
    // 1. Spin up a mock HTTP server on localhost
    // 2. Make actual HTTP requests
    // 3. Verify responses
    //
    // For now, we verify the handler can be initialized and basic operations work.

    const allocator = testing.allocator;

    const config = ProtocolConfig{
        .http = HTTPConfig{
            .version = .http1_1,
            .max_connections = 10,
            .connection_timeout_ms = 5000,
            .request_timeout_ms = 30000,
            .max_redirects = 0,
            .enable_compression = false,
        },
    };

    const handler = try HTTP1Handler.init(allocator, config);
    defer handler.deinit();

    // Verify handler state
    try testing.expect(handler.connection_count == 0);
    try testing.expect(handler.next_conn_id == 1);
    try testing.expect(handler.next_request_id == 1);

    // Note: Actual connect/send/poll tests require a running HTTP server
    // These would be added in a full integration test suite with a test server
}

test "http1_handler_integration: connection pool management" {
    const allocator = testing.allocator;

    const config = ProtocolConfig{
        .http = HTTPConfig{
            .version = .http1_1,
            .max_connections = 5,
            .connection_timeout_ms = 5000,
            .request_timeout_ms = 30000,
            .max_redirects = 0,
            .enable_compression = false,
        },
    };

    const handler = try HTTP1Handler.init(allocator, config);
    defer handler.deinit();

    // Verify configuration applied
    try testing.expectEqual(@as(u32, 5), handler.config.max_connections);
    try testing.expectEqual(@as(u32, 5000), handler.config.connection_timeout_ms);
    try testing.expectEqual(@as(u32, 30000), handler.config.request_timeout_ms);
}

test "http1_handler_integration: event log integration" {
    const allocator = testing.allocator;

    const config = ProtocolConfig{
        .http = HTTPConfig{
            .version = .http1_1,
            .max_connections = 10,
            .connection_timeout_ms = 5000,
            .request_timeout_ms = 30000,
            .max_redirects = 0,
            .enable_compression = false,
        },
    };

    const handler = try HTTP1Handler.init(allocator, config);
    defer handler.deinit();

    // Create event log
    var event_log = try z6.EventLog.init(allocator, 1000);
    defer event_log.deinit();

    // Attach event log
    handler.setEventLog(&event_log);

    try testing.expect(handler.event_log != null);

    // Note: Actual event emission testing requires making requests
    // which requires a running HTTP server
}

test "http1_handler_integration: request serialization variants" {
    const allocator = testing.allocator;

    const config = ProtocolConfig{
        .http = HTTPConfig{
            .version = .http1_1,
            .max_connections = 10,
            .connection_timeout_ms = 5000,
            .request_timeout_ms = 30000,
            .max_redirects = 0,
            .enable_compression = false,
        },
    };

    const handler = try HTTP1Handler.init(allocator, config);
    defer handler.deinit();

    var buffer: [8192]u8 = undefined;

    // Test GET request (no body)
    {
        const headers = try allocator.alloc(Header, 0);
        defer allocator.free(headers);

        const request = Request{
            .id = 1,
            .method = .GET,
            .path = "/test",
            .headers = headers,
            .body = null, // No body for GET
            .timeout_ns = 30_000_000_000,
        };

        const serialized = try handler.serializeRequest(request, &buffer);
        try testing.expect(std.mem.indexOf(u8, serialized, "GET /test HTTP/1.1") != null);
        try testing.expect(std.mem.indexOf(u8, serialized, "Host: localhost") != null);
        try testing.expect(std.mem.indexOf(u8, serialized, "Content-Length") == null); // No body
    }

    // Test POST request with body
    {
        const headers = try allocator.alloc(Header, 1);
        defer allocator.free(headers);
        headers[0] = .{ .name = "Content-Type", .value = "text/plain" };

        const request = Request{
            .id = 2,
            .method = .POST,
            .path = "/data",
            .headers = headers,
            .body = "test data",
            .timeout_ns = 30_000_000_000,
        };

        const serialized = try handler.serializeRequest(request, &buffer);
        try testing.expect(std.mem.indexOf(u8, serialized, "POST /data HTTP/1.1") != null);
        try testing.expect(std.mem.indexOf(u8, serialized, "Content-Type: text/plain") != null);
        try testing.expect(std.mem.indexOf(u8, serialized, "Content-Length: 9") != null);
        try testing.expect(std.mem.indexOf(u8, serialized, "test data") != null);
    }
}

// TODO: Add full integration tests with mock HTTP server
// - Test actual TCP connection
// - Test request/response roundtrip
// - Test keep-alive connection reuse
// - Test timeout handling
// - Test connection pool exhaustion
// - Test event emission
// - Test error handling (connection refused, timeout, parse error)
