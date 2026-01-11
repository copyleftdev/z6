//! HTTP/2 Handler Tests
//!
//! Unit tests for HTTP/2 protocol handler implementation.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

test "http2_handler: init and deinit" {
    const allocator = testing.allocator;

    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
            .max_connections = 100,
            .connection_timeout_ms = 5000,
            .request_timeout_ms = 30000,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    // Handler should be initialized with no connections
    try testing.expectEqual(@as(usize, 0), handler.connection_count);
    try testing.expectEqual(@as(u64, 1), handler.next_conn_id);
    try testing.expectEqual(@as(u64, 1), handler.next_request_id);
}

test "http2_handler: createHandler interface" {
    const allocator = testing.allocator;

    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
            .max_connections = 100,
        },
    };

    var handler = try z6.createHTTP2Handler(allocator, config);
    defer handler.deinit();

    // Should have valid function pointers
    try testing.expect(@intFromPtr(handler.context) != 0);
}

test "http2_handler: MAX_CONNECTIONS constant" {
    // Verify constants are reasonable
    try testing.expect(z6.HTTP2_MAX_CONNECTIONS > 0);
    try testing.expect(z6.HTTP2_MAX_CONNECTIONS <= 10000);
}

test "http2_handler: MAX_STREAMS constant" {
    try testing.expect(z6.HTTP2_MAX_STREAMS > 0);
    try testing.expect(z6.HTTP2_MAX_STREAMS <= 1000);
}

test "http2_handler: handler poll with no connections" {
    const allocator = testing.allocator;

    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    var completions = z6.CompletionQueue.init(allocator);
    defer completions.deinit();

    // Poll should succeed with no connections
    try handler.poll(&completions);
    try testing.expectEqual(@as(usize, 0), completions.items.len);
}

test "http2_handler: connection not found error" {
    const allocator = testing.allocator;

    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    // Try to send on non-existent connection
    const request = z6.Request{
        .id = 1,
        .method = .GET,
        .path = "/test",
        .headers = &[_]z6.Header{},
        .body = null,
        .timeout_ns = 1000000,
    };

    const result = handler.send(999, request);
    try testing.expectError(error.ConnectionNotFound, result);
}

test "http2_handler: close non-existent connection" {
    const allocator = testing.allocator;

    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    // Close non-existent connection should not error
    try handler.close(999);
}

test "http2_handler: Tiger Style - bounded constants" {
    // Verify all constants have reasonable bounds
    try testing.expect(z6.HTTP2_MAX_CONNECTIONS <= 10000);
    try testing.expect(z6.HTTP2_MAX_STREAMS <= 1000);

    // Default window size per RFC 7540 (65535)
    // Verified through handler behavior - no direct access to module constant
}

test "http2_handler: Tiger Style - assertions in init" {
    const allocator = testing.allocator;

    // Valid config should work
    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
            .max_connections = 100,
            .connection_timeout_ms = 5000,
            .request_timeout_ms = 30000,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    // Verify postconditions
    try testing.expectEqual(@as(usize, 0), handler.connection_count);
    try testing.expect(handler.next_conn_id > 0);
}

test "http2_handler: current tick advances on poll" {
    const allocator = testing.allocator;

    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    const initial_tick = handler.current_tick;

    var completions = z6.CompletionQueue.init(allocator);
    defer completions.deinit();

    try handler.poll(&completions);

    // Tick should have advanced
    try testing.expect(handler.current_tick > initial_tick);
}

test "http2_handler: multiple polls advance tick" {
    const allocator = testing.allocator;

    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    var completions = z6.CompletionQueue.init(allocator);
    defer completions.deinit();

    // Poll multiple times
    for (0..10) |_| {
        completions.clearRetainingCapacity();
        try handler.poll(&completions);
    }

    // Should have advanced by 10
    try testing.expectEqual(@as(u64, 10), handler.current_tick);
}

test "http2_handler: HTTP2Error error set" {
    // Verify error types exist and can be used
    // This tests that the error set is properly defined
    const allocator = testing.allocator;

    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    // Test that send returns ConnectionNotFound for invalid connection
    const request = z6.Request{
        .id = 1,
        .method = .GET,
        .path = "/test",
        .headers = &[_]z6.Header{},
        .body = null,
        .timeout_ns = 1000000,
    };

    const result = handler.send(999, request);
    try testing.expectError(error.ConnectionNotFound, result);
}

test "http2_handler: config validation" {
    const allocator = testing.allocator;

    // Test with different config values
    const config = z6.ProtocolConfig{
        .http = z6.HTTPConfig{
            .version = .http2,
            .max_connections = 500,
            .connection_timeout_ms = 10000,
            .request_timeout_ms = 60000,
            .max_redirects = 0,
            .enable_compression = false,
        },
    };

    const handler = try z6.HTTP2Handler.init(allocator, config);
    defer handler.deinit();

    try testing.expectEqual(@as(u32, 500), handler.config.max_connections);
    try testing.expectEqual(@as(u32, 10000), handler.config.connection_timeout_ms);
    try testing.expectEqual(@as(u32, 60000), handler.config.request_timeout_ms);
}
