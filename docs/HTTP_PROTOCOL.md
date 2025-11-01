# Z6 HTTP Protocol Implementation

> "Minimal, correct, fast — in that order."

## Overview

Z6's HTTP implementation supports the **essential subset** needed for load testing. It is not a general-purpose HTTP client.

## Supported Features

### HTTP/1.1 ✅

- **Methods:** GET, POST, PUT, DELETE, PATCH, HEAD, OPTIONS
- **Headers:** Custom headers, standard headers
- **Body:** Fixed-size bodies (no streaming uploads)
- **Keep-Alive:** Connection reuse
- **Chunked Transfer:** Response parsing only
- **TLS:** Via BoringSSL

### HTTP/2 ✅

- **Multiplexing:** Multiple concurrent streams per connection
- **Header Compression:** HPACK
- **Flow Control:** Stream and connection level
- **Stream Prioritization:** Basic support
- **Server Push:** Receive and ignore

## Explicitly NOT Supported

Following Tiger Style, we declare what we **won't** do:

- ❌ **Redirects** — Handled by scenario, not protocol
- ❌ **Cookies** — Not a browser
- ❌ **Caching** — Defeats load testing purpose
- ❌ **Form encoding** — Specify body manually
- ❌ **Multipart uploads** — Use raw body
- ❌ **Content negotiation** — Set headers explicitly
- ❌ **HTTP/0.9, HTTP/1.0** — Ancient, not relevant
- ❌ **HTTP/3 (QUIC)** — Too complex for v1

## Request Structure

```zig
const HTTPRequest = struct {
    id: u64,
    method: Method,
    path: []const u8,
    headers: []Header,
    body: ?[]const u8,
    timeout_ns: u64,
    
    // HTTP version preference
    version: HTTPVersion,
};

const HTTPVersion = enum {
    http1_1,
    http2,
};

const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
};
```

### Example Request

```zig
const req = HTTPRequest{
    .id = 1,
    .method = .POST,
    .path = "/api/v1/users",
    .headers = &[_]Header{
        .{ .name = "Content-Type", .value = "application/json" },
        .{ .name = "Accept", .value = "application/json" },
    },
    .body = "{\"name\":\"Alice\",\"email\":\"alice@example.com\"}",
    .timeout_ns = 5_000_000_000, // 5s
    .version = .http2,
};
```

## Response Structure

```zig
const HTTPResponse = struct {
    request_id: u64,
    status_code: u16,
    headers: []Header,
    body: []const u8,
    version: HTTPVersion,
    latency_ns: u64,
};
```

## Connection Management

### Connection Pool

```zig
const HTTPConnectionPool = struct {
    connections: [MAX_CONNECTIONS]HTTPConnection,
    by_target: HashMap(Target, []ConnectionId),
    
    fn acquire(pool: *Self, target: Target, version: HTTPVersion) !ConnectionId {
        // Try to reuse existing connection
        if (pool.by_target.get(target)) |conn_ids| {
            for (conn_ids) |id| {
                const conn = &pool.connections[id];
                if (conn.is_idle() and conn.version == version) {
                    return id;
                }
            }
        }
        
        // Create new connection
        return try pool.create_connection(target, version);
    }
};
```

### Connection States

```
CONNECTING → CONNECTED → IDLE ↔ ACTIVE → CLOSING → CLOSED
```

### Keep-Alive

HTTP/1.1 connections use keep-alive by default:

```
Connection: keep-alive
Keep-Alive: timeout=30, max=100
```

Connections are reused until:
- Server closes connection
- Max requests reached (100)
- Idle timeout (30s)
- Protocol error

## HTTP/1.1 Implementation

### Request Serialization

```zig
fn serialize_http1_request(req: HTTPRequest, buf: []u8) !usize {
    var pos: usize = 0;
    
    // Request line: METHOD PATH HTTP/1.1\r\n
    pos += try std.fmt.bufPrint(buf[pos..], "{s} {s} HTTP/1.1\r\n", .{
        @tagName(req.method),
        req.path,
    }).len;
    
    // Headers
    for (req.headers) |header| {
        pos += try std.fmt.bufPrint(buf[pos..], "{s}: {s}\r\n", .{
            header.name,
            header.value,
        }).len;
    }
    
    // Body length header
    if (req.body) |body| {
        pos += try std.fmt.bufPrint(buf[pos..], "Content-Length: {d}\r\n", .{
            body.len,
        }).len;
    }
    
    // End of headers
    pos += try std.fmt.bufPrint(buf[pos..], "\r\n", .{}).len;
    
    // Body
    if (req.body) |body| {
        @memcpy(buf[pos..][0..body.len], body);
        pos += body.len;
    }
    
    return pos;
}
```

### Response Parsing

```zig
const HTTPParser = struct {
    state: ParserState,
    
    fn parse_response(parser: *Self, data: []const u8) !HTTPResponse {
        // Parse status line
        const status_line_end = std.mem.indexOf(u8, data, "\r\n") orelse 
            return error.InvalidResponse;
        
        const status_line = data[0..status_line_end];
        const status_code = try parse_status_code(status_line);
        
        // Parse headers
        var pos = status_line_end + 2;
        var headers = ArrayList(Header).init(parser.allocator);
        
        while (true) {
            const line_end = std.mem.indexOf(u8, data[pos..], "\r\n") orelse
                return error.InvalidResponse;
            
            if (line_end == 0) {
                // Empty line = end of headers
                pos += 2;
                break;
            }
            
            const header_line = data[pos..pos + line_end];
            const header = try parse_header(header_line);
            try headers.append(header);
            
            pos += line_end + 2;
        }
        
        // Parse body (remaining data)
        const body = data[pos..];
        
        return HTTPResponse{
            .status_code = status_code,
            .headers = try headers.toOwnedSlice(),
            .body = body,
            .version = .http1_1,
        };
    }
};
```

### Chunked Transfer Encoding

```zig
fn parse_chunked_body(data: []const u8, output: []u8) !usize {
    var pos: usize = 0;
    var out_pos: usize = 0;
    
    while (true) {
        // Read chunk size (hex)
        const size_line_end = std.mem.indexOf(u8, data[pos..], "\r\n") orelse
            return error.InvalidChunkedEncoding;
        
        const size_hex = data[pos..pos + size_line_end];
        const chunk_size = try std.fmt.parseInt(usize, size_hex, 16);
        
        if (chunk_size == 0) break; // Last chunk
        
        pos += size_line_end + 2;
        
        // Read chunk data
        if (pos + chunk_size > data.len) return error.InvalidChunkedEncoding;
        @memcpy(output[out_pos..][0..chunk_size], data[pos..pos + chunk_size]);
        
        pos += chunk_size + 2; // Skip \r\n after chunk
        out_pos += chunk_size;
    }
    
    return out_pos;
}
```

## HTTP/2 Implementation

### Frame Structure

```zig
const HTTP2Frame = struct {
    length: u24,        // Frame payload length
    type: FrameType,    // Frame type
    flags: u8,          // Frame flags
    stream_id: u31,     // Stream identifier
    payload: []u8,      // Frame payload
};

const FrameType = enum(u8) {
    DATA = 0x0,
    HEADERS = 0x1,
    PRIORITY = 0x2,
    RST_STREAM = 0x3,
    SETTINGS = 0x4,
    PUSH_PROMISE = 0x5,
    PING = 0x6,
    GOAWAY = 0x7,
    WINDOW_UPDATE = 0x8,
    CONTINUATION = 0x9,
};
```

### Connection Preface

HTTP/2 connections start with:

```
PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n
```

Followed by SETTINGS frame.

### Stream Management

```zig
const HTTP2Stream = struct {
    id: u31,
    state: StreamState,
    window_size: i32,
    headers: ArrayList(Header),
    body: ArrayList(u8),
};

const StreamState = enum {
    idle,
    open,
    half_closed_local,
    half_closed_remote,
    closed,
};
```

### HPACK Header Compression

```zig
const HPACKEncoder = struct {
    dynamic_table: DynamicTable,
    
    fn encode_header(encoder: *Self, header: Header, output: []u8) !usize {
        // Try to find in static table
        if (STATIC_TABLE.get(header)) |index| {
            return encode_indexed(index, output);
        }
        
        // Try to find in dynamic table
        if (encoder.dynamic_table.get(header)) |index| {
            return encode_indexed(index + 61, output);
        }
        
        // Encode literal with indexing
        return encode_literal_with_indexing(header, output);
    }
};
```

### Flow Control

```zig
fn send_data_frame(conn: *HTTP2Connection, stream_id: u31, data: []const u8) !void {
    const stream = &conn.streams[stream_id];
    
    // Check stream window
    if (stream.window_size < data.len) {
        return error.FlowControlError;
    }
    
    // Check connection window
    if (conn.window_size < data.len) {
        return error.FlowControlError;
    }
    
    // Send frame
    try conn.send_frame(.{
        .type = .DATA,
        .stream_id = stream_id,
        .payload = data,
    });
    
    // Update windows
    stream.window_size -= @intCast(data.len);
    conn.window_size -= @intCast(data.len);
}
```

## TLS Integration

### Configuration

```zig
const TLSConfig = struct {
    verify_peer: bool = true,
    ca_bundle: ?[]const u8 = null,
    alpn_protocols: []const []const u8 = &[_][]const u8{ "h2", "http/1.1" },
    min_version: TLSVersion = .tls1_2,
};
```

### Handshake

```zig
fn tls_handshake(conn: *HTTPConnection, config: TLSConfig) !void {
    const ssl = try SSL.init(config);
    defer ssl.deinit();
    
    // Set ALPN for HTTP/2 negotiation
    try ssl.set_alpn_protos(config.alpn_protocols);
    
    // Perform handshake
    try ssl.connect(conn.socket);
    
    // Check negotiated protocol
    const protocol = try ssl.get_alpn_selected();
    conn.version = if (std.mem.eql(u8, protocol, "h2"))
        .http2
    else
        .http1_1;
}
```

## Error Handling

### HTTP/1.1 Errors

```zig
const HTTP1Error = error{
    InvalidStatusLine,
    InvalidHeader,
    InvalidChunkedEncoding,
    ContentLengthMismatch,
    ConnectionClosed,
    ParseError,
};
```

### HTTP/2 Errors

```zig
const HTTP2Error = error{
    ProtocolError,
    InternalError,
    FlowControlError,
    SettingsTimeout,
    StreamClosed,
    FrameSizeError,
    RefusedStream,
    CompressionError,
};
```

### Error Event Emission

```zig
fn handle_error(handler: *HTTPHandler, err: anyerror, request_id: u64) !void {
    try handler.logger.log_event(.{
        .event_type = .error_http,
        .payload = .{
            .request_id = request_id,
            .error_code = @intFromError(err),
            .error_context = @errorName(err),
        },
    });
}
```

## Timeout Implementation

Timeouts are tracked per request:

```zig
const PendingRequest = struct {
    id: u64,
    issued_tick: u64,
    timeout_ticks: u64,
};

fn check_timeouts(handler: *HTTPHandler) !void {
    const now = handler.scheduler.current_tick;
    
    for (handler.pending_requests.items) |req| {
        if (now - req.issued_tick > req.timeout_ticks) {
            try handler.complete_with_timeout(req.id);
        }
    }
}
```

## Performance Optimizations

### Zero-Copy Parsing

```zig
// BAD: Copy headers
var headers = ArrayList(Header).init(allocator);
for (parsed_headers) |h| {
    try headers.append(.{
        .name = try allocator.dupe(u8, h.name),
        .value = try allocator.dupe(u8, h.value),
    });
}

// GOOD: Reference original buffer
const HeaderView = struct {
    name: []const u8,   // Points into recv buffer
    value: []const u8,  // Points into recv buffer
};
```

### Connection Warmup

Pre-establish connections before test starts:

```zig
fn warmup(handler: *HTTPHandler, targets: []Target) !void {
    for (targets) |target| {
        _ = try handler.pool.acquire(target, .http2);
    }
}
```

### Pipelining (Future)

HTTP/1.1 pipelining **not supported** in v1:
- Too risky (many servers don't support it)
- HTTP/2 multiplexing is better

## Limits

All operations are bounded:

```zig
const HTTPLimits = struct {
    max_request_size: usize = 1024 * 1024,      // 1 MB
    max_response_size: usize = 10 * 1024 * 1024, // 10 MB
    max_header_count: usize = 100,
    max_header_size: usize = 8192,
    max_redirects: u8 = 0,                       // No redirects
    max_streams_per_connection: u16 = 100,       // HTTP/2
};
```

## Testing

### Unit Tests

```zig
test "HTTP/1.1 request serialization" {
    const req = HTTPRequest{
        .id = 1,
        .method = .GET,
        .path = "/test",
        .headers = &[_]Header{},
        .body = null,
        .timeout_ns = 1000,
        .version = .http1_1,
    };
    
    var buf: [1024]u8 = undefined;
    const len = try serialize_http1_request(req, &buf);
    
    const expected = "GET /test HTTP/1.1\r\n\r\n";
    try std.testing.expectEqualStrings(expected, buf[0..len]);
}
```

### Fuzz Tests

```zig
test "Fuzz HTTP/1.1 response parser" {
    const parser = HTTPParser.init(std.testing.allocator);
    defer parser.deinit();
    
    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();
    
    for (0..1_000_000) |_| {
        var data: [8192]u8 = undefined;
        random.bytes(&data);
        
        _ = parser.parse_response(&data) catch {};
    }
}
```

## Comparison

| Feature | K6 | Z6 |
|---------|----|----|
| HTTP/1.1 | ✅ | ✅ |
| HTTP/2 | ✅ | ✅ |
| HTTP/3 | ❌ | ❌ |
| Redirects | ✅ | ❌ |
| Cookies | ✅ | ❌ |
| WebSockets | ✅ | ⏳ |
| gRPC | ✅ | ⏳ |

---

## Summary

Z6's HTTP implementation is **minimal, correct, and fast**:

- Supports essential load testing features
- No bloat from browser features
- Deterministic behavior
- Fuzzed for correctness

---

**Version 1.0 — October 2025**
