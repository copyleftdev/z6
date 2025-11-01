# Z6 Error Taxonomy

> "Failure is a first-class result. Every error has a deterministic cause."

## Error Philosophy

In Z6, errors are:

1. **Expected** — Operating errors are part of normal execution
2. **Semantic** — Error types have specific meanings
3. **Actionable** — Each error suggests a root cause
4. **Deterministic** — Same conditions → same error

Assertions (programmer errors) are **not** in this taxonomy. They crash immediately.

## Error Categories

```zig
const Error = union(enum) {
    network: NetworkError,
    protocol: ProtocolError,
    timeout: TimeoutError,
    resource: ResourceError,
    configuration: ConfigurationError,
};
```

## Network Errors

Errors at the network layer:

```zig
const NetworkError = error{
    /// DNS resolution failed (invalid hostname, DNS server down)
    DNSResolutionFailed,
    
    /// TCP connection refused (no service on port)
    ConnectionRefused,
    
    /// TCP connection reset by peer
    ConnectionReset,
    
    /// Connection closed unexpectedly
    ConnectionClosed,
    
    /// Network unreachable (routing issue)
    NetworkUnreachable,
    
    /// Host unreachable (firewall, down)
    HostUnreachable,
    
    /// Socket creation failed
    SocketError,
};
```

### Root Causes & Actions

| Error | Likely Cause | Action |
|-------|--------------|--------|
| DNSResolutionFailed | Invalid hostname, DNS server down | Check hostname, DNS config |
| ConnectionRefused | Service not running | Verify service is up |
| ConnectionReset | Backend crashed, load balancer issue | Check backend logs |
| NetworkUnreachable | Routing problem | Check network config |

## Protocol Errors

Errors in protocol implementation:

```zig
const ProtocolError = error{
    /// Invalid HTTP response (malformed)
    InvalidHTTPResponse,
    
    /// HTTP/2 protocol violation
    HTTP2ProtocolViolation,
    
    /// Unsupported HTTP version
    UnsupportedHTTPVersion,
    
    /// Invalid header format
    InvalidHeader,
    
    /// Chunked encoding error
    InvalidChunkedEncoding,
    
    /// Content-Length mismatch
    ContentLengthMismatch,
    
    /// TLS handshake failed
    TLSHandshakeFailed,
    
    /// Certificate validation failed
    CertificateInvalid,
    
    /// ALPN negotiation failed
    ALPNNegotiationFailed,
};
```

### Root Causes & Actions

| Error | Likely Cause | Action |
|-------|--------------|--------|
| InvalidHTTPResponse | Backend bug, proxy issue | Check backend implementation |
| TLSHandshakeFailed | Certificate expired, version mismatch | Check TLS config |
| CertificateInvalid | Self-signed, expired, wrong host | Update certificates |

## Timeout Errors

Timing-related failures:

```zig
const TimeoutError = error{
    /// DNS resolution timeout
    DNSTimeout,
    
    /// TCP connection timeout
    ConnectionTimeout,
    
    /// TLS handshake timeout
    TLSTimeout,
    
    /// Request timeout (no response)
    RequestTimeout,
    
    /// Read timeout (partial response)
    ReadTimeout,
    
    /// Write timeout (send blocked)
    WriteTimeout,
};
```

### Timeout Configuration

Each timeout is configurable:

```zig
const TimeoutConfig = struct {
    dns_timeout_ms: u32 = 5000,
    connection_timeout_ms: u32 = 10000,
    tls_timeout_ms: u32 = 10000,
    request_timeout_ms: u32 = 30000,
    read_timeout_ms: u32 = 30000,
    write_timeout_ms: u32 = 30000,
};
```

### Root Causes & Actions

| Error | Likely Cause | Action |
|-------|--------------|--------|
| RequestTimeout | Slow backend, network latency | Increase timeout, investigate backend |
| ConnectionTimeout | Firewall, overloaded backend | Check network path, backend capacity |
| ReadTimeout | Slow response generation | Investigate backend performance |

## Resource Errors

Resource exhaustion:

```zig
const ResourceError = error{
    /// Connection pool exhausted
    ConnectionPoolExhausted,
    
    /// Event log full
    EventLogFull,
    
    /// Memory budget exceeded
    MemoryBudgetExceeded,
    
    /// Too many VUs
    TooManyVUs,
    
    /// Request queue full
    RequestQueueFull,
    
    /// File descriptor limit reached
    FileDescriptorLimitReached,
};
```

### Root Causes & Actions

| Error | Likely Cause | Action |
|-------|--------------|--------|
| ConnectionPoolExhausted | Too many concurrent requests | Increase pool size or reduce VUs |
| EventLogFull | Disk write too slow | Use faster disk or reduce event rate |
| MemoryBudgetExceeded | Too many VUs | Reduce VU count |

## Configuration Errors

Invalid configuration (detected at startup):

```zig
const ConfigurationError = error{
    /// Invalid scenario file
    InvalidScenario,
    
    /// Invalid URL format
    InvalidURL,
    
    /// Invalid timeout value
    InvalidTimeout,
    
    /// Conflicting options
    ConflictingOptions,
    
    /// Missing required field
    MissingRequiredField,
    
    /// Value out of range
    ValueOutOfRange,
};
```

These errors **prevent test execution**. No events are logged.

## HTTP Status Codes

HTTP responses are **not errors** from Z6's perspective. A 404 or 500 is a successful HTTP transaction.

Status codes are recorded as events:

```zig
const HTTPStatusCategory = enum {
    informational,  // 1xx
    success,        // 2xx
    redirection,    // 3xx
    client_error,   // 4xx
    server_error,   // 5xx
};
```

Users can define assertions on status codes:

```zig
// Fail if >1% of requests return 5xx
const assertion = Assertion{
    .name = "low 5xx rate",
    .check = fn(m: Metrics) bool {
        const count_5xx = count_status_range(m, 500, 599);
        return count_5xx / m.total_requests < 0.01;
    },
};
```

## Error Context

Every error event includes context:

```zig
const ErrorPayload = struct {
    request_id: u64,
    error_code: u32,
    error_message: [200]u8,  // Human-readable
    context: ErrorContext,
};

const ErrorContext = union(enum) {
    network: NetworkContext,
    protocol: ProtocolContext,
    timeout: TimeoutContext,
    resource: ResourceContext,
};

const NetworkContext = struct {
    host: [256]u8,
    port: u16,
    ip_address: [46]u8,  // IPv6 max length
    syscall_errno: i32,
};
```

Example error event:

```
Error Event:
  Type: ConnectionRefused
  Request ID: 12345
  Host: api.example.com:443
  IP: 93.184.216.34
  Errno: ECONNREFUSED (111)
  Message: "Connection refused when connecting to 93.184.216.34:443"
```

## Error Recovery

### Retryable Errors

Some errors are retryable:

```zig
fn is_retryable(err: Error) bool {
    return switch (err) {
        .network => |ne| switch (ne) {
            error.ConnectionReset,
            error.NetworkUnreachable,
            => true,
            else => false,
        },
        .timeout => true,  // All timeouts retryable
        .resource => |re| switch (re) {
            error.ConnectionPoolExhausted,
            error.RequestQueueFull,
            => true,
            else => false,
        },
        else => false,
    };
}
```

### Non-Retryable Errors

These indicate fundamental problems:

- `DNSResolutionFailed` — Hostname is wrong
- `CertificateInvalid` — TLS config issue
- `InvalidHTTPResponse` — Backend bug
- `MemoryBudgetExceeded` — Configuration issue

## Error Handling in Code

All operations return `Result(T, Error)`:

```zig
fn send_request(handler: *HTTPHandler, request: Request) !Response {
    const conn = handler.pool.acquire(request.target) catch |err| {
        return switch (err) {
            error.ConnectionPoolExhausted => error.ResourceError,
            error.DNSResolutionFailed => error.NetworkError,
            else => err,
        };
    };
    
    handler.protocol.send(conn, request) catch |err| {
        try handler.logger.log_error(request.id, err);
        return err;
    };
    
    // Success path...
}
```

## Error Metrics

Post-run error analysis:

```zig
const ErrorMetrics = struct {
    total_errors: u64,
    by_category: HashMap(ErrorCategory, u64),
    by_specific_error: HashMap(Error, u64),
    error_rate: f64,
    most_common_error: Error,
};
```

Example output:

```
Errors: 1,250 (1.04%)
  Network Errors: 800 (64%)
    - ConnectionReset: 500
    - ConnectionTimeout: 300
  Timeout Errors: 400 (32%)
    - RequestTimeout: 400
  Protocol Errors: 50 (4%)
    - InvalidHTTPResponse: 50
```

## Debugging Guide

### ConnectionRefused

**Symptoms:** Immediate failure, no latency

**Check:**

1. Is the service running?
2. Is the port correct?
3. Is there a firewall blocking?

### ConnectionTimeout

**Symptoms:** Fails after connection timeout duration

**Check:**

1. Network path (traceroute, ping)
2. Firewall rules
3. Backend load (may be refusing connections)

### RequestTimeout

**Symptoms:** Connection succeeds, but no response

**Check:**

1. Backend processing time
2. Network latency
3. Is timeout too aggressive?

### InvalidHTTPResponse

**Symptoms:** Random, intermittent

**Check:**

1. Backend logs for crashes
2. Proxy/load balancer issues
3. HTTP/2 support on backend

### TLSHandshakeFailed

**Symptoms:** After TCP connection, before request

**Check:**

1. Certificate validity
2. TLS version compatibility
3. Cipher suite mismatch

## Comparison to K6

| K6 Error | Z6 Error | Difference |
|----------|----------|------------|
| `connection_refused` | `ConnectionRefused` | Same |
| `timeout` | Specific timeout types | More granular |
| `http_error` | Protocol-specific | Better classification |
| `unknown` | None | Z6 has no unknown errors |

## Future Error Types

Planned for future protocols:

- `GRPCError` — gRPC-specific errors
- `WebSocketError` — WebSocket-specific errors
- `QuicError` — QUIC/HTTP3 errors

---

## Summary

Z6's error taxonomy is:

- **Complete** — Every error has a type
- **Semantic** — Error names describe root cause
- **Actionable** — Each error suggests debugging steps
- **Deterministic** — No "unknown" or "unexpected" errors

---

**Version 1.0 — October 2025**
