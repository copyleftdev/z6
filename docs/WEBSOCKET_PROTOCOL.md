# Z6 WebSocket Protocol

> "Future implementation. Real-time testing."

## Status

**⏳ Deferred to post-v1**

WebSocket support is planned but not implemented in version 1.0. This document defines requirements for when it is implemented.

## Why WebSocket?

WebSocket is critical for testing:
- Real-time applications
- Chat systems
- Live updates
- Gaming backends
- Streaming data

## Scope

### Supported (Planned)

- **Text frames** — UTF-8 messages
- **Binary frames** — Raw bytes
- **Ping/Pong** — Keep-alive mechanism
- **Fragmented messages** — Large payloads
- **Close handshake** — Graceful shutdown
- **TLS (wss://)** — Secure WebSocket

### Not Supported

- **Extensions** — No per-message compression (yet)
- **Subprotocols** — Use standard WebSocket only
- **Autobahn compliance** — Not a goal for v1

## Architecture

### Protocol Handler

```zig
const WebSocketHandler = struct {
    http: *HTTPHandler,  // For upgrade handshake
    connections: ConnectionPool(WebSocketConnection),
    
    pub fn init(allocator: Allocator, config: WebSocketConfig) !*WebSocketHandler {
        return WebSocketHandler{
            .http = try HTTPHandler.init(allocator, config.http),
            .connections = try ConnectionPool(WebSocketConnection).init(allocator, 1000),
        };
    }
    
    pub fn connect(self: *WebSocketHandler, url: []const u8) !ConnectionId {
        // HTTP upgrade handshake
        const upgrade_key = generate_websocket_key();
        
        const response = try self.http.send(.{
            .method = .GET,
            .path = url,
            .headers = &[_]Header{
                .{ .name = "Upgrade", .value = "websocket" },
                .{ .name = "Connection", .value = "Upgrade" },
                .{ .name = "Sec-WebSocket-Key", .value = upgrade_key },
                .{ .name = "Sec-WebSocket-Version", .value = "13" },
            },
        });
        
        if (response.status_code != 101) {
            return error.UpgradeFailed;
        }
        
        // Verify Sec-WebSocket-Accept
        const expected_accept = compute_websocket_accept(upgrade_key);
        const actual_accept = response.get_header("Sec-WebSocket-Accept");
        if (!std.mem.eql(u8, expected_accept, actual_accept)) {
            return error.InvalidAcceptKey;
        }
        
        // Connection established
        return self.connections.acquire(response.connection);
    }
    
    pub fn send_text(self: *WebSocketHandler, conn_id: ConnectionId, text: []const u8) !void {
        const frame = try encode_websocket_frame(.{
            .opcode = .text,
            .payload = text,
            .masked = true,  // Client must mask
        });
        
        try self.connections.get(conn_id).send(frame);
    }
    
    pub fn receive(self: *WebSocketHandler, conn_id: ConnectionId) !WebSocketMessage {
        const conn = self.connections.get(conn_id);
        const frame = try decode_websocket_frame(try conn.receive());
        
        return WebSocketMessage{
            .type = frame.opcode,
            .payload = frame.payload,
        };
    }
};
```

### Frame Structure

WebSocket frames:

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-------+-+-------------+-------------------------------+
|F|R|R|R| opcode|M| Payload len |    Extended payload length    |
|I|S|S|S|  (4)  |A|     (7)     |             (16/64)           |
|N|V|V|V|       |S|             |   (if payload len==126/127)   |
| |1|2|3|       |K|             |                               |
+-+-+-+-+-------+-+-------------+ - - - - - - - - - - - - - - - +
|     Extended payload length continued, if payload len == 127  |
+ - - - - - - - - - - - - - - - +-------------------------------+
|                               |Masking-key, if MASK set to 1  |
+-------------------------------+-------------------------------+
| Masking-key (continued)       |          Payload Data         |
+-------------------------------- - - - - - - - - - - - - - - - +
:                     Payload Data continued ...                :
+ - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - +
|                     Payload Data continued ...                |
+---------------------------------------------------------------+
```

### Opcodes

```zig
const WebSocketOpcode = enum(u4) {
    continuation = 0x0,
    text = 0x1,
    binary = 0x2,
    close = 0x8,
    ping = 0x9,
    pong = 0xA,
};
```

### Frame Encoding

```zig
fn encode_websocket_frame(frame: Frame) ![]u8 {
    var buf = ArrayList(u8).init(allocator);
    
    // Byte 0: FIN + opcode
    const byte0 = 0x80 | @intFromEnum(frame.opcode);  // FIN=1
    try buf.append(byte0);
    
    // Byte 1: MASK + length
    const masked: u8 = if (frame.masked) 0x80 else 0x00;
    
    if (frame.payload.len < 126) {
        try buf.append(masked | @intCast(frame.payload.len));
    } else if (frame.payload.len < 65536) {
        try buf.append(masked | 126);
        try buf.appendSlice(&std.mem.toBytes(@as(u16, @intCast(frame.payload.len))));
    } else {
        try buf.append(masked | 127);
        try buf.appendSlice(&std.mem.toBytes(@as(u64, frame.payload.len)));
    }
    
    // Masking key (if masked)
    if (frame.masked) {
        var mask: [4]u8 = undefined;
        std.crypto.random.bytes(&mask);
        try buf.appendSlice(&mask);
        
        // Mask payload
        for (frame.payload, 0..) |byte, i| {
            try buf.append(byte ^ mask[i % 4]);
        }
    } else {
        try buf.appendSlice(frame.payload);
    }
    
    return buf.toOwnedSlice();
}
```

### Frame Decoding

```zig
fn decode_websocket_frame(data: []const u8) !Frame {
    if (data.len < 2) return error.IncompleteFrame;
    
    const fin = (data[0] & 0x80) != 0;
    const opcode = @enumFromInt(WebSocketOpcode, data[0] & 0x0F);
    
    const masked = (data[1] & 0x80) != 0;
    var payload_len: u64 = data[1] & 0x7F;
    var pos: usize = 2;
    
    // Extended payload length
    if (payload_len == 126) {
        payload_len = std.mem.readIntBig(u16, data[pos..pos+2]);
        pos += 2;
    } else if (payload_len == 127) {
        payload_len = std.mem.readIntBig(u64, data[pos..pos+8]);
        pos += 8;
    }
    
    // Masking key
    var mask: [4]u8 = undefined;
    if (masked) {
        @memcpy(&mask, data[pos..pos+4]);
        pos += 4;
    }
    
    // Payload
    if (pos + payload_len > data.len) return error.IncompleteFrame;
    var payload = try allocator.alloc(u8, payload_len);
    
    if (masked) {
        for (0..payload_len) |i| {
            payload[i] = data[pos + i] ^ mask[i % 4];
        }
    } else {
        @memcpy(payload, data[pos..pos+payload_len]);
    }
    
    return Frame{
        .fin = fin,
        .opcode = opcode,
        .payload = payload,
    };
}
```

## Connection Upgrade

### Handshake

Client sends:

```
GET /chat HTTP/1.1
Host: server.example.com
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
```

Server responds:

```
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

### Key Generation

```zig
fn generate_websocket_key() ![24]u8 {
    var random_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    
    var encoded: [24]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&encoded, &random_bytes);
    
    return encoded;
}

fn compute_websocket_accept(key: []const u8) ![28]u8 {
    const magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(key);
    hasher.update(magic);
    var hash: [20]u8 = undefined;
    hasher.final(&hash);
    
    var encoded: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(&encoded, &hash);
    
    return encoded;
}
```

## Ping/Pong

### Keep-Alive

```zig
fn send_ping(handler: *WebSocketHandler, conn_id: ConnectionId) !void {
    const frame = try encode_websocket_frame(.{
        .opcode = .ping,
        .payload = "ping",
        .masked = true,
    });
    
    try handler.connections.get(conn_id).send(frame);
}

fn handle_pong(handler: *WebSocketHandler, frame: Frame) void {
    // Pong received, connection alive
    const conn = handler.find_connection_by_frame(frame);
    conn.last_pong_time = handler.scheduler.current_tick;
}
```

## Close Handshake

```zig
const CloseCode = enum(u16) {
    normal = 1000,
    going_away = 1001,
    protocol_error = 1002,
    unsupported_data = 1003,
    invalid_frame_payload = 1007,
    policy_violation = 1008,
    message_too_big = 1009,
    internal_error = 1011,
};

fn close_connection(
    handler: *WebSocketHandler,
    conn_id: ConnectionId,
    code: CloseCode,
    reason: []const u8,
) !void {
    var payload = ArrayList(u8).init(allocator);
    try payload.appendSlice(&std.mem.toBytes(@intFromEnum(code)));
    try payload.appendSlice(reason);
    
    const frame = try encode_websocket_frame(.{
        .opcode = .close,
        .payload = payload.items,
        .masked = true,
    });
    
    try handler.connections.get(conn_id).send(frame);
    
    // Wait for close frame from server
    const response = try handler.receive(conn_id);
    if (response.type != .close) {
        return error.ProtocolViolation;
    }
    
    // Close TCP connection
    try handler.connections.release(conn_id);
}
```

## Event Logging

WebSocket-specific events:

```zig
const WebSocketConnectedPayload = struct {
    conn_id: u64,
    url_hash: u64,
};

const WebSocketMessageSentPayload = struct {
    conn_id: u64,
    message_type: u8,  // text/binary
    size: u32,
};

const WebSocketMessageReceivedPayload = struct {
    conn_id: u64,
    message_type: u8,
    size: u32,
    latency_ns: u64,
};
```

## Scenario Definition

```toml
[target]
base_url = "wss://chat.example.com"

[[requests]]
name = "send_message"
method = "WEBSOCKET"
action = "send"
message_type = "text"
body = '''{"type":"message","content":"Hello"}'''

[[requests]]
name = "receive_message"
method = "WEBSOCKET"
action = "receive"
timeout_ms = 5000
```

## Limits

```zig
const WebSocketLimits = struct {
    max_frame_size: usize = 1_048_576,       // 1 MB
    max_message_size: usize = 10_485_760,    // 10 MB
    ping_interval_ms: u32 = 30_000,          // 30 seconds
    pong_timeout_ms: u32 = 10_000,           // 10 seconds
    max_connections: u32 = 10_000,
};
```

## Error Handling

```zig
const WebSocketError = error{
    UpgradeFailed,
    InvalidAcceptKey,
    IncompleteFrame,
    InvalidOpcode,
    ProtocolViolation,
    MessageTooLarge,
    PongTimeout,
};
```

## Testing Requirements

### Unit Tests

- Frame encoding/decoding
- Masking/unmasking
- Key generation
- Close handshake

### Integration Tests

- Connect and send/receive
- Ping/pong mechanism
- Graceful close
- Binary messages

### Fuzz Tests

- Frame parsing
- Invalid opcodes
- Malformed lengths
- Partial frames

## Performance Targets

| Metric | Target |
|--------|--------|
| Frame encode | <1μs |
| Frame decode | <2μs |
| Ping/pong latency | <10ms |
| Connection overhead | <1ms |

## Implementation Timeline

1. **Phase 1** — Basic text frames (v1.1)
2. **Phase 2** — Binary frames, ping/pong (v1.2)
3. **Phase 3** — Fragmentation, close handshake (v1.3)
4. **Phase 4** — Extensions (compression) (v2.0)

## Comparison

| Feature | K6 | Z6 (planned) |
|---------|-----|--------------|
| Text messages | ✅ | ✅ |
| Binary messages | ✅ | ✅ |
| Ping/Pong | ✅ | ✅ |
| Determinism | ❌ | ✅ |
| Event logging | ❌ | ✅ |

## Contributing

To implement WebSocket support:

1. Implement frame encoding/decoding
2. Add upgrade handshake
3. Write comprehensive tests
4. Update this document

---

## Summary

WebSocket support is planned for Z6 but deferred to post-v1. When implemented:

- Full WebSocket protocol support
- Deterministic replay
- Complete event logging
- Tiger Style correctness

---

**Version 1.0 — October 2025**
