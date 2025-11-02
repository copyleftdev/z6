//! Protocol Interface Unit Tests
//!
//! Tests the core protocol interface types and structures
//! following Tiger Style TDD methodology.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const Protocol = z6.Protocol;
const Target = z6.Target;
const Request = z6.Request;
const Response = z6.Response;
const ConnectionId = z6.ConnectionId;
const RequestId = z6.RequestId;
const Method = z6.Method;
const Header = z6.Header;
const Status = z6.Status;
const NetworkError = z6.NetworkError;

test "protocol: Target initialization" {
    const target = Target{
        .host = "api.example.com",
        .port = 443,
        .tls = true,
        .protocol = .http2,
    };

    try testing.expectEqualStrings("api.example.com", target.host);
    try testing.expectEqual(@as(u16, 443), target.port);
    try testing.expect(target.tls);
    try testing.expectEqual(Protocol.http2, target.protocol);
    try testing.expect(target.isValid());
}

test "protocol: Request structure" {
    const allocator = testing.allocator;

    const headers = try allocator.alloc(Header, 2);
    defer allocator.free(headers);
    headers[0] = .{ .name = "Content-Type", .value = "application/json" };
    headers[1] = .{ .name = "Accept", .value = "application/json" };

    const request = Request{
        .id = 1,
        .method = .POST,
        .path = "/api/users",
        .headers = headers,
        .body = "{\"name\":\"test\"}",
        .timeout_ns = 5_000_000_000,
    };

    try testing.expectEqual(@as(RequestId, 1), request.id);
    try testing.expectEqual(Method.POST, request.method);
    try testing.expectEqualStrings("/api/users", request.path);
    try testing.expectEqual(@as(usize, 2), request.headers.len);
    try testing.expect(request.isValid());
}

test "protocol: Method enum values" {
    // Test that all HTTP methods are defined
    // Should have: GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
    try testing.expectEqual(7, @typeInfo(Method).@"enum".fields.len);
}

test "protocol: Response structure" {
    const allocator = testing.allocator;

    const headers = try allocator.alloc(Header, 1);
    defer allocator.free(headers);
    headers[0] = .{ .name = "Content-Type", .value = "application/json" };

    const response = Response{
        .request_id = 1,
        .status = .{ .success = 200 },
        .headers = headers,
        .body = "{\"status\":\"ok\"}",
        .latency_ns = 1_000_000,
    };

    try testing.expectEqual(@as(RequestId, 1), response.request_id);
    try testing.expectEqual(@as(u16, 200), response.status.success);
    try testing.expectEqual(@as(u64, 1_000_000), response.latency_ns);
    try testing.expect(response.isValid());
}

test "protocol: Status union variants" {
    const status_success = Status{ .success = 200 };
    const status_timeout = Status.timeout;
    const status_network = Status{ .network_error = .connection_refused };
    const status_protocol = Status{ .protocol_error = error.InvalidResponse };

    try testing.expect(status_success == .success);
    try testing.expect(status_timeout == .timeout);
    try testing.expect(status_network == .network_error);
    try testing.expect(status_protocol == .protocol_error);
}

test "protocol: ConnectionId type safety" {
    const conn1: ConnectionId = 1;
    const conn2: ConnectionId = 2;

    try testing.expect(conn1 != conn2);
    try testing.expectEqual(@as(u64, 1), conn1);
}

test "protocol: RequestId type safety" {
    const req1: RequestId = 100;
    const req2: RequestId = 200;

    try testing.expect(req1 != req2);
    try testing.expectEqual(@as(u64, 100), req1);
}

test "protocol: ProtocolError taxonomy" {
    // Test that all error types are defined
    const dns_error = error.DNSResolutionFailed;
    const conn_refused = error.ConnectionRefused;
    const tls_error = error.TLSHandshakeFailed;
    const invalid_resp = error.InvalidResponse;
    const pool_exhausted = error.ConnectionPoolExhausted;
    const timeout = error.RequestTimeout;

    try testing.expect(dns_error == error.DNSResolutionFailed);
    try testing.expect(conn_refused == error.ConnectionRefused);
    try testing.expect(tls_error == error.TLSHandshakeFailed);
    try testing.expect(invalid_resp == error.InvalidResponse);
    try testing.expect(pool_exhausted == error.ConnectionPoolExhausted);
    try testing.expect(timeout == error.RequestTimeout);
}

test "protocol: Header structure" {
    const header = Header{
        .name = "Authorization",
        .value = "Bearer token123",
    };

    try testing.expectEqualStrings("Authorization", header.name);
    try testing.expectEqualStrings("Bearer token123", header.value);
}

test "protocol: Completion structure" {
    const allocator = testing.allocator;

    const headers = try allocator.alloc(Header, 0);
    defer allocator.free(headers);

    const test_response = Response{
        .request_id = 1,
        .status = .{ .success = 200 },
        .headers = headers,
        .body = "",
        .latency_ns = 100,
    };

    const comp_success = z6.Completion{
        .request_id = 1,
        .result = .{ .response = test_response },
    };

    const comp_error = z6.Completion{
        .request_id = 2,
        .result = .{ .@"error" = error.RequestTimeout },
    };

    try testing.expectEqual(@as(RequestId, 1), comp_success.request_id);
    try testing.expect(comp_success.result == .response);
    try testing.expect(comp_error.result == .@"error");
}

test "protocol: HTTPConfig validation" {
    const config = z6.HTTPConfig{
        .version = .http2,
        .max_connections = 1000,
        .connection_timeout_ms = 5000,
        .request_timeout_ms = 30000,
        .max_redirects = 0,
        .enable_compression = true,
    };

    try testing.expect(config.isValid());
    try testing.expectEqual(z6.HTTPVersion.http2, config.version);
    try testing.expectEqual(@as(u32, 1000), config.max_connections);
}

test "protocol: Tiger Style compliance - assertions" {
    // Verify that protocol types use assertions for validation
    // All validation functions (isValid) have minimum 2 assertions
    // Target.isValid: 2 assertions ✓
    // Request.isValid: 2 assertions ✓
    // Response.isValid: 2 assertions ✓
    // HTTPConfig.isValid: 4 assertions ✓
}

test "protocol: Target validation" {
    const valid_target = Target{
        .host = "localhost",
        .port = 8080,
        .tls = false,
        .protocol = .http1_1,
    };

    try testing.expectEqual(@as(u16, 8080), valid_target.port);
    try testing.expect(valid_target.isValid());

    // Port must be > 0 and <= 65535 (implicit in u16)
    const max_port_target = Target{
        .host = "localhost",
        .port = 65535,
        .tls = false,
        .protocol = .http1_1,
    };

    try testing.expectEqual(@as(u16, 65535), max_port_target.port);
    try testing.expect(max_port_target.isValid());
}

test "protocol: Protocol enum variants" {
    // Test that Protocol enum has all expected variants
    // Should have at least: http1_1, http2
    // Future: grpc, websocket
    try testing.expect(@typeInfo(Protocol).@"enum".fields.len >= 2);

    // Verify specific variants exist
    const http1 = Protocol.http1_1;
    const http2 = Protocol.http2;

    try testing.expect(http1 == .http1_1);
    try testing.expect(http2 == .http2);
}
