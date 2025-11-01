# Z6 Protocol Interface

> "Each protocol is a small, verified, modular engine."

## Overview

Z6 supports multiple protocols (HTTP, gRPC, WebSocket) through a **unified interface**. Each protocol implementation is:

- **Self-contained** — No shared mutable state
- **Minimal** — Only load testing features
- **Fuzzed** — Exhaustively tested for correctness
- **Composable** — Can be combined in scenarios

## Protocol Handler Interface

All protocol handlers implement this interface:

```zig
const ProtocolHandler = struct {
    const Self = @This();
    
    /// Initialize protocol handler
    initFn: *const fn(allocator: Allocator, config: ProtocolConfig) anyerror!*Self,
    
    /// Establish connection
    connectFn: *const fn(self: *Self, target: Target) anyerror!ConnectionId,
    
    /// Send request
    sendFn: *const fn(self: *Self, conn_id: ConnectionId, request: Request) anyerror!RequestId,
    
    /// Poll for completions (non-blocking)
    pollFn: *const fn(self: *Self, completions: *CompletionQueue) anyerror!void,
    
    /// Close connection
    closeFn: *const fn(self: *Self, conn_id: ConnectionId) anyerror!void,
    
    /// Cleanup
    deinitFn: *const fn(self: *Self) void,
};
```

## Core Types

### Target

Represents a connection target:

```zig
const Target = struct {
    host: []const u8,        // Hostname or IP
    port: u16,               // Port number
    tls: bool,               // Use TLS?
    protocol: Protocol,      // HTTP/1.1, HTTP/2, gRPC, etc.
};
```

### Request

Generic request structure:

```zig
const Request = struct {
    id: RequestId,
    method: Method,          // GET, POST, etc.
    path: []const u8,
    headers: []Header,
    body: ?[]const u8,
    timeout_ns: u64,         // Nanosecond timeout
};

const RequestId = u64;

const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
};

const Header = struct {
    name: []const u8,
    value: []const u8,
};
```

### Response

Generic response structure:

```zig
const Response = struct {
    request_id: RequestId,
    status: Status,
    headers: []Header,
    body: []const u8,
    latency_ns: u64,         // Request to full response
};

const Status = union(enum) {
    success: u16,            // HTTP status code (200, 404, etc.)
    timeout,
    network_error: NetworkError,
    protocol_error: ProtocolError,
};
```

### Completion

Represents a completed I/O operation:

```zig
const Completion = struct {
    request_id: RequestId,
    result: CompletionResult,
};

const CompletionResult = union(enum) {
    response: Response,
    error: Error,
};
```

### Connection

Opaque connection identifier:

```zig
const ConnectionId = u64;
```

## Protocol Lifecycle

### 1. Initialization

```zig
const handler = try HTTPHandler.init(allocator, config);
defer handler.deinit();
```

Handler allocates:

- Connection pool
- I/O buffers
- Internal state

### 2. Connection Establishment

```zig
const target = Target{
    .host = "api.example.com",
    .port = 443,
    .tls = true,
    .protocol = .http2,
};

const conn_id = try handler.connect(target);
```

Steps:

1. DNS resolution (cached)
2. TCP connection
3. TLS handshake (if enabled)
4. Protocol negotiation (ALPN for HTTP/2)

All steps emit events to the event log.

### 3. Request Sending

```zig
const request = Request{
    .id = generate_request_id(),
    .method = .GET,
    .path = "/api/users",
    .headers = &[_]Header{
        .{ .name = "Accept", .value = "application/json" },
    },
    .body = null,
    .timeout_ns = 5_000_000_000, // 5 seconds
};

const request_id = try handler.send(conn_id, request);
```

Returns immediately. Request is in-flight.

### 4. Polling for Completions

```zig
var completions: CompletionQueue = undefined;

try handler.poll(&completions);

for (completions.items) |completion| {
    switch (completion.result) {
        .response => |resp| {
            // Handle success
            process_response(resp);
        },
        .error => |err| {
            // Handle error
            process_error(err);
        },
    }
}
```

Poll is **non-blocking**. Returns immediately with available completions.

### 5. Connection Closing

```zig
try handler.close(conn_id);
```

Graceful shutdown. Outstanding requests are cancelled.

### 6. Cleanup

```zig
handler.deinit();
```

Frees all resources.

## Error Taxonomy

Protocol handlers return semantic errors:

```zig
const ProtocolError = error{
    // Connection errors
    DNSResolutionFailed,
    ConnectionRefused,
    ConnectionReset,
    ConnectionTimeout,
    
    // TLS errors
    TLSHandshakeFailed,
    CertificateInvalid,
    
    // Protocol errors
    InvalidResponse,
    ProtocolViolation,
    UnsupportedProtocol,
    
    // Resource errors
    ConnectionPoolExhausted,
    BufferPoolExhausted,
    RequestQueueFull,
    
    // Timeout errors
    RequestTimeout,
    ReadTimeout,
    WriteTimeout,
};
```

Every error is **deterministic** — same network conditions → same errors.

## Connection Pooling

Protocol handlers manage connection pools internally:

```zig
const ConnectionPool = struct {
    connections: [MAX_CONNECTIONS]Connection,
    free_list: [MAX_CONNECTIONS]ConnectionId,
    free_count: u32,
    
    fn acquire(pool: *ConnectionPool, target: Target) !ConnectionId {
        // Try to find existing connection
        for (pool.connections) |conn| {
            if (conn.target.equals(target) and conn.is_idle()) {
                return conn.id;
            }
        }
        
        // Acquire new connection
        if (pool.free_count == 0) return error.ConnectionPoolExhausted;
        
        pool.free_count -= 1;
        const id = pool.free_list[pool.free_count];
        
        return id;
    }
    
    fn release(pool: *ConnectionPool, id: ConnectionId) void {
        pool.free_list[pool.free_count] = id;
        pool.free_count += 1;
    }
};
```

Pool size is **fixed**. Exhaustion triggers backpressure.

## Event Emission

Protocol handlers emit events to the logger:

```zig
fn send(self: *HTTPHandler, conn_id: ConnectionId, request: Request) !RequestId {
    // Log request issued
    try self.logger.log_event(.{
        .tick = self.scheduler.current_tick,
        .vu_id = request.vu_id,
        .event_type = .request_issued,
        .payload = .{
            .request_id = request.id,
            .method = @tagName(request.method),
            .url_hash = hash(request.path),
        },
    });
    
    // Actually send request
    try self.io.send(conn_id, request);
    
    return request.id;
}
```

All operations are logged for replay.

## Timeout Handling

Timeouts are enforced by the protocol handler:

```zig
fn poll(self: *HTTPHandler, completions: *CompletionQueue) !void {
    const now = self.scheduler.current_tick;
    
    // Check for timeouts
    for (self.pending_requests) |req| {
        if (now - req.issued_tick > req.timeout_ticks) {
            try completions.append(.{
                .request_id = req.id,
                .result = .{ .error = error.RequestTimeout },
            });
            
            // Log timeout event
            try self.logger.log_timeout(req);
        }
    }
    
    // Check for I/O completions
    const io_completions = try self.io.poll();
    for (io_completions) |io_comp| {
        try completions.append(io_comp);
    }
}
```

Timeouts are **deterministic** — based on logical ticks, not wall time.

## Protocol-Specific Configuration

Each protocol has its own configuration:

```zig
const ProtocolConfig = union(enum) {
    http: HTTPConfig,
    grpc: GRPCConfig,
    websocket: WebSocketConfig,
};

const HTTPConfig = struct {
    version: HTTPVersion = .http2,
    max_connections: u32 = 1000,
    connection_timeout_ms: u32 = 5000,
    request_timeout_ms: u32 = 30000,
    max_redirects: u8 = 0,        // No redirects by default
    enable_compression: bool = true,
};
```

## Invariants

Protocol handlers must maintain these invariants:

### 1. Request-Response Pairing

Every `send()` produces exactly one completion (response or error).

```zig
// Assertion
assert(sent_requests == completed_requests + in_flight_requests);
```

### 2. Connection Lifecycle

Connections progress: `CONNECTING → CONNECTED → IDLE ↔ ACTIVE → CLOSING → CLOSED`

No invalid transitions.

### 3. Resource Bounds

```zig
assert(active_connections <= MAX_CONNECTIONS);
assert(pending_requests <= MAX_PENDING_REQUESTS);
assert(buffer_usage <= MAX_BUFFER_MEMORY);
```

### 4. Event Ordering

```zig
// request_issued must precede response_received
assert(request_issued_tick < response_received_tick);
```

## Fuzzing Interface

Protocol handlers expose a fuzzing interface:

```zig
fn fuzz_response_parser(data: []const u8) !void {
    const parser = ResponseParser.init();
    _ = parser.parse(data) catch |err| {
        // Expected errors are OK
        if (err == error.InvalidResponse) return;
        return err;
    };
}
```

Fuzz targets:

- Request serialization
- Response parsing
- Header parsing
- Chunked encoding
- TLS handshake

## Testing Requirements

Before a protocol handler is production-ready:

### Unit Tests

- Connection pooling logic
- Request/response serialization
- Error handling
- Timeout enforcement

### Integration Tests

- Full request/response cycle
- Connection reuse
- Error recovery
- Timeout behavior

### Fuzz Tests

- 1 million inputs per fuzz target
- No crashes, no hangs, no memory leaks
- Deterministic behavior

### Correctness Tests

- RFC compliance (HTTP/1.1, HTTP/2, etc.)
- Edge cases (empty responses, large headers, etc.)
- Error cases (malformed data, connection drops, etc.)

## Supported Protocols (v1)

### HTTP/1.1 ✅

Supported:

- GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
- Request/response headers
- Chunked transfer encoding
- Keep-alive connections
- TLS (via OpenSSL/BoringSSL)

Not supported:

- Pipelining (too risky)
- Trailers
- 100-continue
- Redirects (handled externally)
- Cookies (handled externally)

### HTTP/2 ✅

Supported:

- Multiplexing
- Stream prioritization (basic)
- Flow control
- Header compression (HPACK)
- Server push (receive only)

Not supported:

- Push promises (ignore)
- Server push (send)

### gRPC ⏳ (Future)

Planned:

- Unary RPCs
- Client streaming
- Server streaming
- Bidirectional streaming

### WebSocket ⏳ (Future)

Planned:

- Text frames
- Binary frames
- Ping/pong
- Graceful close

## Comparison to Other Implementations

| System | Protocol Support | Z6 Difference |
|--------|------------------|---------------|
| K6 | HTTP/1.1, HTTP/2, WebSocket, gRPC | No scripting, minimal subset |
| Locust | HTTP/1.1 | HTTP/2, gRPC planned |
| Gatling | HTTP/1.1, HTTP/2, WebSocket | Zig, not JVM |
| curl | Everything | Load testing subset only |

## Extension Guide

To add a new protocol:

### 1. Define Handler

```zig
const MyProtocolHandler = struct {
    allocator: Allocator,
    logger: *EventLogger,
    // ... state ...
    
    pub fn init(allocator: Allocator, config: MyProtocolConfig) !*MyProtocolHandler {
        // Allocate and initialize
    }
    
    pub fn connect(self: *MyProtocolHandler, target: Target) !ConnectionId {
        // Establish connection
    }
    
    // ... implement interface ...
};
```

### 2. Write Tests

```zig
test "MyProtocol: basic request/response" {
    const handler = try MyProtocolHandler.init(allocator, .{});
    defer handler.deinit();
    
    const conn_id = try handler.connect(.{ .host = "localhost", .port = 8080 });
    const req_id = try handler.send(conn_id, test_request);
    
    var completions: CompletionQueue = undefined;
    try handler.poll(&completions);
    
    try std.testing.expectEqual(1, completions.items.len);
}
```

### 3. Fuzz

```zig
test "MyProtocol: fuzz response parser" {
    const fuzzer = try Fuzzer.init(allocator);
    defer fuzzer.deinit();
    
    for (0..1_000_000) |_| {
        const data = try fuzzer.generate_random_data(1024);
        _ = MyProtocolHandler.parse_response(data) catch {};
    }
}
```

### 4. Document

Add `MY_PROTOCOL.md` documenting:

- Supported features
- Unsupported features
- Configuration options
- Error conditions

### 5. Integrate

Register handler in protocol engine:

```zig
const protocol_engine = ProtocolEngine{
    .http = try HTTPHandler.init(allocator, config.http),
    .grpc = try GRPCHandler.init(allocator, config.grpc),
    .my_protocol = try MyProtocolHandler.init(allocator, config.my_protocol),
};
```

---

## Summary

The protocol interface provides:

- **Consistency** — All protocols behave the same
- **Testability** — Easy to unit test and fuzz
- **Extensibility** — New protocols follow template
- **Correctness** — Enforced invariants

---

**Version 1.0 — October 2025**
