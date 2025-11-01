# Z6 gRPC Protocol

> "Future implementation. Specification first."

## Status

**⏳ Deferred to post-v1**

gRPC support is planned but not implemented in version 1.0. This document defines requirements for when it is implemented.

## Why gRPC?

gRPC is increasingly common for:
- Microservice communication
- High-performance APIs
- Streaming workloads

Z6 should support gRPC load testing.

## Scope

### Supported (Planned)

- **Unary RPC** — Single request, single response
- **Client Streaming** — Multiple requests, single response
- **Server Streaming** — Single request, multiple responses
- **Bidirectional Streaming** — Multiple requests, multiple responses
- **HTTP/2 Transport** — Required by gRPC
- **Protobuf Serialization** — Binary payload format
- **Metadata** — gRPC headers
- **Deadlines** — Request timeouts
- **Status Codes** — gRPC error codes

### Not Supported

- **gRPC-Web** — Browser variant
- **Reflection API** — Service discovery (use static .proto files)
- **Custom Load Balancing** — Use external load balancer
- **Interceptors** — No middleware support
- **Dynamic message creation** — Pre-compiled .proto required

## Architecture

### Protocol Handler

```zig
const GRPCHandler = struct {
    http2: *HTTP2Handler,  // Reuse HTTP/2 transport
    proto_registry: ProtoRegistry,
    
    pub fn init(allocator: Allocator, config: GRPCConfig) !*GRPCHandler {
        // Initialize HTTP/2 with ALPN for "h2"
        const http2 = try HTTP2Handler.init(allocator, .{
            .alpn = &[_][]const u8{"h2"},
        });
        
        const registry = try ProtoRegistry.load(config.proto_files);
        
        return GRPCHandler{
            .http2 = http2,
            .proto_registry = registry,
        };
    }
    
    pub fn call_unary(
        self: *GRPCHandler,
        service: []const u8,
        method: []const u8,
        request: []const u8,
    ) ![]const u8 {
        // :method = POST
        // :scheme = https
        // :path = /service/method
        // :authority = target
        // content-type = application/grpc+proto
        // grpc-timeout = 10S
        
        const path = try std.fmt.allocPrint(
            self.allocator,
            "/{s}/{s}",
            .{service, method}
        );
        
        const response = try self.http2.send(.{
            .method = .POST,
            .path = path,
            .headers = &[_]Header{
                .{ .name = "content-type", .value = "application/grpc+proto" },
                .{ .name = "te", .value = "trailers" },
            },
            .body = try encode_grpc_message(request),
        });
        
        return try decode_grpc_message(response.body);
    }
};
```

### Message Framing

gRPC uses length-prefixed framing:

```
[Compressed-Flag: 1 byte]
[Message-Length: 4 bytes, big-endian]
[Message: N bytes]
```

```zig
fn encode_grpc_message(data: []const u8) ![]u8 {
    var buf = try allocator.alloc(u8, 5 + data.len);
    
    buf[0] = 0;  // Not compressed
    std.mem.writeIntBig(u32, buf[1..5], @intCast(data.len));
    @memcpy(buf[5..], data);
    
    return buf;
}

fn decode_grpc_message(data: []const u8) ![]const u8 {
    if (data.len < 5) return error.InvalidGRPCMessage;
    
    const compressed = data[0];
    if (compressed != 0) return error.CompressionNotSupported;
    
    const length = std.mem.readIntBig(u32, data[1..5]);
    if (length != data.len - 5) return error.LengthMismatch;
    
    return data[5..];
}
```

### Status Codes

```zig
const GRPCStatus = enum(u8) {
    OK = 0,
    CANCELLED = 1,
    UNKNOWN = 2,
    INVALID_ARGUMENT = 3,
    DEADLINE_EXCEEDED = 4,
    NOT_FOUND = 5,
    ALREADY_EXISTS = 6,
    PERMISSION_DENIED = 7,
    RESOURCE_EXHAUSTED = 8,
    FAILED_PRECONDITION = 9,
    ABORTED = 10,
    OUT_OF_RANGE = 11,
    UNIMPLEMENTED = 12,
    INTERNAL = 13,
    UNAVAILABLE = 14,
    DATA_LOSS = 15,
    UNAUTHENTICATED = 16,
};
```

## Protobuf Integration

### Compilation

```bash
# Compile .proto to Zig
protoc --zig_out=src/proto/ api.proto
```

### Usage in Scenario

```toml
[target]
base_url = "grpc://api.example.com:443"
proto_files = ["protos/user_service.proto"]

[[requests]]
name = "create_user"
service = "UserService"
method = "CreateUser"
body_proto = '''
{
  "name": "Alice",
  "email": "alice@example.com"
}
'''
```

## Streaming Support

### Client Streaming

```zig
fn call_client_streaming(
    self: *GRPCHandler,
    service: []const u8,
    method: []const u8,
    requests: [][]const u8,
) ![]const u8 {
    const stream = try self.http2.create_stream();
    
    for (requests) |req| {
        try stream.send_data(try encode_grpc_message(req));
    }
    
    try stream.end_stream();
    
    const response = try stream.receive();
    return try decode_grpc_message(response);
}
```

### Server Streaming

```zig
fn call_server_streaming(
    self: *GRPCHandler,
    service: []const u8,
    method: []const u8,
    request: []const u8,
) ![][]const u8 {
    const stream = try self.http2.create_stream();
    
    try stream.send_data(try encode_grpc_message(request));
    try stream.end_stream();
    
    var responses = ArrayList([]const u8).init(self.allocator);
    
    while (try stream.receive_data()) |data| {
        const msg = try decode_grpc_message(data);
        try responses.append(msg);
    }
    
    return responses.toOwnedSlice();
}
```

## Error Handling

```zig
const GRPCError = error{
    InvalidMessage,
    CompressionNotSupported,
    LengthMismatch,
    DeadlineExceeded,
    Unavailable,
    InvalidProto,
};
```

## Event Logging

gRPC events extend the base event model:

```zig
const GRPCRequestIssuedPayload = struct {
    request_id: u64,
    service: [64]u8,       // Service name
    method: [64]u8,        // Method name
    message_size: u32,
    is_streaming: bool,
};

const GRPCResponseReceivedPayload = struct {
    request_id: u64,
    status_code: GRPCStatus,
    message_size: u32,
    latency_ns: u64,
};
```

## Metrics

Additional gRPC-specific metrics:

- Requests by service/method
- Status code distribution
- Streaming message count
- Protobuf serialization overhead

## Testing Requirements

Before gRPC is production-ready:

### Unit Tests

- Message framing
- Status code handling
- Metadata parsing

### Integration Tests

- Unary RPC end-to-end
- Client streaming
- Server streaming
- Bidirectional streaming

### Fuzz Tests

- Protobuf parsing
- gRPC message framing
- Invalid status codes

## Dependencies

- **protobuf-zig** — Protobuf compiler for Zig
- **HTTP/2 handler** — Already implemented

## Performance Targets

| Metric | Target |
|--------|--------|
| Unary RPC latency overhead | <100μs |
| Protobuf encode/decode | <10μs per message |
| Stream creation | <1ms |

## Comparison to Other Tools

| Feature | K6 | Ghz | Z6 (planned) |
|---------|-----|-----|--------------|
| Unary RPC | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ |
| Determinism | ❌ | ❌ | ✅ |
| Event logging | ❌ | ❌ | ✅ |

## Implementation Timeline

1. **Phase 1** — Unary RPC (v1.1)
2. **Phase 2** — Client/Server streaming (v1.2)
3. **Phase 3** — Bidirectional streaming (v1.3)
4. **Phase 4** — Full feature parity (v2.0)

## Contributing

To implement gRPC support:

1. Open RFC issue with detailed design
2. Implement HTTP/2 extensions first
3. Add protobuf parsing
4. Write comprehensive tests
5. Update this document with actual implementation

---

## Summary

gRPC support is planned for Z6 but deferred to post-v1. When implemented, it will provide:

- Full gRPC feature support
- Deterministic replay
- Complete event logging
- Tiger Style correctness

---

**Version 1.0 — October 2025**
