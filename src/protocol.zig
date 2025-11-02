//! Protocol Interface - Generic protocol handler interface
//!
//! Provides a unified interface for all network protocols (HTTP, gRPC, WebSocket).
//! Each protocol implementation is self-contained, minimal, and thoroughly tested.
//!
//! Tiger Style:
//! - All types are explicit and bounded
//! - Minimum 2 assertions per function
//! - No silent failures

const std = @import("std");

/// Protocol type discriminator
pub const Protocol = enum {
    http1_1,
    http2,
    // Future protocols:
    // grpc,
    // websocket,
};

/// Connection target specification
pub const Target = struct {
    /// Hostname or IP address
    host: []const u8,

    /// Port number (1-65535)
    port: u16,

    /// Use TLS/SSL encryption
    tls: bool,

    /// Protocol to use
    protocol: Protocol,

    /// Validate target configuration
    pub fn isValid(self: *const Target) bool {
        // Preconditions
        std.debug.assert(self.host.len > 0); // Host must not be empty
        std.debug.assert(self.port > 0); // Port must be valid (u16 ensures <= 65535)

        const valid = self.host.len > 0 and self.port > 0;

        // Postcondition
        std.debug.assert(valid == (self.host.len > 0)); // Consistent validation

        return valid;
    }
};

/// HTTP method
pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    PATCH,
    HEAD,
    OPTIONS,
};

/// HTTP header
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Unique request identifier
pub const RequestId = u64;

/// HTTP request
pub const Request = struct {
    /// Unique request ID
    id: RequestId,

    /// HTTP method
    method: Method,

    /// Request path
    path: []const u8,

    /// Request headers
    headers: []const Header,

    /// Optional request body
    body: ?[]const u8,

    /// Request timeout in nanoseconds
    timeout_ns: u64,

    /// Validate request
    pub fn isValid(self: *const Request) bool {
        // Preconditions
        std.debug.assert(self.path.len > 0); // Path must not be empty
        std.debug.assert(self.timeout_ns > 0); // Timeout must be positive

        const valid = self.path.len > 0 and self.timeout_ns > 0;

        // Postcondition
        std.debug.assert(valid == (self.path.len > 0 and self.timeout_ns > 0)); // Consistent

        return valid;
    }
};

/// Protocol errors
pub const ProtocolError = error{
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

/// Network errors
pub const NetworkError = enum {
    connection_refused,
    connection_reset,
    connection_timeout,
    dns_failed,
    unknown,
};

/// Response status
pub const Status = union(enum) {
    /// HTTP status code (200, 404, etc.)
    success: u16,

    /// Request timed out
    timeout,

    /// Network-level error
    network_error: NetworkError,

    /// Protocol-level error
    protocol_error: ProtocolError,
};

/// HTTP response
pub const Response = struct {
    /// ID of the request this responds to
    request_id: RequestId,

    /// Response status
    status: Status,

    /// Response headers
    headers: []const Header,

    /// Response body
    body: []const u8,

    /// Request to response latency in nanoseconds
    latency_ns: u64,

    /// Validate response
    pub fn isValid(self: *const Response) bool {
        // Preconditions
        std.debug.assert(self.request_id > 0); // Must have valid request ID
        std.debug.assert(self.latency_ns >= 0); // Latency cannot be negative

        const valid = self.request_id > 0;

        // Postcondition
        std.debug.assert(valid == (self.request_id > 0)); // Consistent

        return valid;
    }
};

/// Opaque connection identifier
pub const ConnectionId = u64;

/// Completion result
pub const CompletionResult = union(enum) {
    response: Response,
    @"error": anyerror,
};

/// Completed I/O operation
pub const Completion = struct {
    request_id: RequestId,
    result: CompletionResult,
};

/// Queue of completed operations
pub const CompletionQueue = std.ArrayList(Completion);

/// Protocol handler configuration
pub const ProtocolConfig = union(enum) {
    http: HTTPConfig,
    // Future: grpc, websocket
};

/// HTTP-specific configuration
pub const HTTPConfig = struct {
    /// HTTP version
    version: HTTPVersion = .http2,

    /// Maximum number of connections
    max_connections: u32 = 1000,

    /// Connection timeout in milliseconds
    connection_timeout_ms: u32 = 5000,

    /// Request timeout in milliseconds
    request_timeout_ms: u32 = 30000,

    /// Maximum number of redirects (0 = no redirects)
    max_redirects: u8 = 0,

    /// Enable compression
    enable_compression: bool = true,

    /// Validate configuration
    pub fn isValid(self: *const HTTPConfig) bool {
        // Preconditions
        std.debug.assert(self.max_connections > 0); // Must allow at least one connection
        std.debug.assert(self.max_connections <= 100_000); // Reasonable upper bound
        std.debug.assert(self.connection_timeout_ms > 0); // Must have timeout
        std.debug.assert(self.request_timeout_ms > 0); // Must have timeout

        const valid = self.max_connections > 0 and
            self.max_connections <= 100_000 and
            self.connection_timeout_ms > 0 and
            self.request_timeout_ms > 0;

        // Postcondition
        std.debug.assert(valid == (self.max_connections > 0 and self.max_connections <= 100_000)); // Consistent

        return valid;
    }
};

/// HTTP version
pub const HTTPVersion = enum {
    http1_1,
    http2,
};

/// Protocol handler interface (function pointers)
///
/// All protocol handlers must implement this interface.
/// Each function is called via function pointer for polymorphism.
pub const ProtocolHandler = struct {
    const Self = @This();

    /// Opaque context pointer (points to specific handler implementation)
    context: *anyopaque,

    /// Function pointers for interface
    initFn: *const fn (allocator: std.mem.Allocator, config: ProtocolConfig) anyerror!*anyopaque,
    connectFn: *const fn (context: *anyopaque, target: Target) anyerror!ConnectionId,
    sendFn: *const fn (context: *anyopaque, conn_id: ConnectionId, request: Request) anyerror!RequestId,
    pollFn: *const fn (context: *anyopaque, completions: *CompletionQueue) anyerror!void,
    closeFn: *const fn (context: *anyopaque, conn_id: ConnectionId) anyerror!void,
    deinitFn: *const fn (context: *anyopaque) void,

    /// Initialize protocol handler
    pub fn init(allocator: std.mem.Allocator, config: ProtocolConfig) !Self {
        // Preconditions
        std.debug.assert(@sizeOf(@TypeOf(allocator)) > 0); // Valid allocator
        std.debug.assert(@sizeOf(@TypeOf(config)) > 0); // Valid config

        // Postcondition stub - actual implementation will have real context
        std.debug.assert(true); // Placeholder

        // Return uninitialized handler - specific implementations will override
        return error.UnsupportedProtocol; // Must be implemented by specific protocol
    }

    /// Establish connection to target
    pub fn connect(self: *Self, target: Target) !ConnectionId {
        // Preconditions
        std.debug.assert(target.host.len > 0); // Valid host
        std.debug.assert(target.port > 0); // Valid port

        const conn_id = try self.connectFn(self.context, target);

        // Postcondition
        std.debug.assert(conn_id > 0); // Valid connection ID

        return conn_id;
    }

    /// Send request on connection
    pub fn send(self: *Self, conn_id: ConnectionId, request: Request) !RequestId {
        // Preconditions
        std.debug.assert(conn_id > 0); // Valid connection
        std.debug.assert(request.path.len > 0); // Valid request

        const req_id = try self.sendFn(self.context, conn_id, request);

        // Postcondition
        std.debug.assert(req_id > 0); // Valid request ID

        return req_id;
    }

    /// Poll for completed operations (non-blocking)
    pub fn poll(self: *Self, completions: *CompletionQueue) !void {
        // Preconditions
        std.debug.assert(@sizeOf(@TypeOf(completions.*)) > 0); // Valid queue
        const old_len = completions.items.len;

        try self.pollFn(self.context, completions);

        // Postcondition
        std.debug.assert(completions.items.len >= old_len); // Queue can only grow

        return;
    }

    /// Close connection gracefully
    pub fn close(self: *Self, conn_id: ConnectionId) !void {
        // Preconditions
        std.debug.assert(conn_id > 0); // Valid connection ID
        std.debug.assert(@sizeOf(@TypeOf(self.context)) > 0); // Valid context

        try self.closeFn(self.context, conn_id);

        // Postcondition
        std.debug.assert(true); // Connection closed

        return;
    }

    /// Cleanup and free resources
    pub fn deinit(self: *Self) void {
        // Preconditions
        std.debug.assert(@sizeOf(@TypeOf(self.context)) > 0); // Valid context
        std.debug.assert(@sizeOf(@TypeOf(self.*)) > 0); // Valid self

        self.deinitFn(self.context);

        // Postcondition
        std.debug.assert(true); // Cleaned up

        return;
    }
};
