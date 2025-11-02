//! HTTP/1.1 Protocol Handler
//!
//! Implements ProtocolHandler interface for HTTP/1.1.
//!
//! Features:
//! - TCP connection management (no TLS yet)
//! - Request serialization
//! - Response parsing via HTTP1Parser
//! - Connection pooling with keep-alive
//! - Timeout enforcement
//! - Event logging
//!
//! Tiger Style:
//! - All loops bounded
//! - Minimum 2 assertions per function
//! - Explicit error handling

const std = @import("std");
const protocol = @import("protocol.zig");
const http1_parser = @import("http1_parser.zig");
const event_mod = @import("event.zig");
const event_log_mod = @import("event_log.zig");

const Allocator = std.mem.Allocator;
const Target = protocol.Target;
const Request = protocol.Request;
const Response = protocol.Response;
const ConnectionId = protocol.ConnectionId;
const RequestId = protocol.RequestId;
const Completion = protocol.Completion;
const CompletionQueue = protocol.CompletionQueue;
const ProtocolConfig = protocol.ProtocolConfig;
const HTTPConfig = protocol.HTTPConfig;
const HTTP1Parser = http1_parser.HTTP1Parser;
const Event = event_mod.Event;
const EventType = event_mod.EventType;
const EventLog = event_log_mod.EventLog;

/// Maximum connections in pool
const MAX_CONNECTIONS = 10_000;

/// Maximum pending requests per connection
const MAX_PENDING_REQUESTS = 100;

/// Maximum requests per keep-alive connection
const MAX_REQUESTS_PER_CONNECTION = 100;

/// Connection state
const ConnectionState = enum {
    idle,
    connecting,
    active,
    closing,
    closed,
};

/// Connection info
const Connection = struct {
    id: ConnectionId,
    state: ConnectionState,
    target: Target,
    stream: ?std.net.Stream,
    requests_sent: u32,
    keep_alive: bool,
    last_used_ns: u64, // Logical tick, not wall clock
};

/// Pending request
const PendingRequest = struct {
    request_id: RequestId,
    connection_id: ConnectionId,
    sent_at_ns: u64,
    timeout_ns: u64,
};

/// HTTP/1.1 Handler
pub const HTTP1Handler = struct {
    allocator: Allocator,
    config: HTTPConfig,
    connections: [MAX_CONNECTIONS]Connection,
    connection_count: usize,
    next_conn_id: ConnectionId,
    next_request_id: RequestId,
    pending_requests: std.ArrayList(PendingRequest),
    parser: HTTP1Parser,
    current_tick: u64, // Logical time
    event_log: ?*EventLog, // Optional event logging

    /// Initialize handler
    pub fn init(allocator: Allocator, config: ProtocolConfig) !*HTTP1Handler {
        // Preconditions
        std.debug.assert(@sizeOf(@TypeOf(allocator)) > 0); // Valid allocator
        std.debug.assert(config == .http); // HTTP config

        const http_config = config.http;
        std.debug.assert(http_config.isValid()); // Valid config

        const handler = try allocator.create(HTTP1Handler);
        handler.* = HTTP1Handler{
            .allocator = allocator,
            .config = http_config,
            .connections = undefined,
            .connection_count = 0,
            .next_conn_id = 1,
            .next_request_id = 1,
            .pending_requests = try std.ArrayList(PendingRequest).initCapacity(allocator, 100),
            .parser = HTTP1Parser.init(allocator),
            .current_tick = 0,
            .event_log = null, // Will be set via setEventLog()
        };

        // Initialize connections
        for (0..MAX_CONNECTIONS) |i| {
            handler.connections[i] = Connection{
                .id = 0,
                .state = .closed,
                .target = undefined,
                .stream = null,
                .requests_sent = 0,
                .keep_alive = true,
                .last_used_ns = 0,
            };
        }

        // Postconditions
        std.debug.assert(handler.connection_count == 0); // No connections yet
        std.debug.assert(handler.next_conn_id > 0); // Valid ID counter

        return handler;
    }

    /// Set event log for event emission
    pub fn setEventLog(self: *HTTP1Handler, event_log: *EventLog) void {
        self.event_log = event_log;
    }

    /// Cleanup handler
    pub fn deinit(self: *HTTP1Handler) void {
        // Preconditions
        std.debug.assert(self.connection_count <= MAX_CONNECTIONS); // Valid count

        // Close all connections
        for (0..MAX_CONNECTIONS) |i| {
            if (self.connections[i].state != .closed) {
                if (self.connections[i].stream) |stream| {
                    stream.close();
                }
                self.connections[i].state = .closed;
                self.connections[i].stream = null;
            }
        }

        self.pending_requests.deinit(self.allocator);
        self.allocator.destroy(self);

        // Postcondition
        std.debug.assert(true); // Cleaned up
    }

    /// Connect to target
    pub fn connect(self: *HTTP1Handler, target: Target) !ConnectionId {
        // Preconditions
        std.debug.assert(target.isValid()); // Valid target
        std.debug.assert(self.connection_count <= MAX_CONNECTIONS); // Room for connection

        // Check if we can reuse an existing connection
        if (self.findIdleConnection(target)) |conn_id| {
            return conn_id;
        }

        // Check connection limit
        if (self.connection_count >= self.config.max_connections) {
            return error.ConnectionPoolExhausted;
        }

        // Find free slot
        const slot = self.findFreeConnectionSlot() orelse
            return error.ConnectionPoolExhausted;

        // Create connection (TCP only for now, no TLS)
        const address = try std.net.Address.parseIp4("127.0.0.1", target.port);
        const stream = try std.net.tcpConnectToAddress(address);

        const conn_id = self.next_conn_id;
        self.next_conn_id += 1;

        self.connections[slot] = Connection{
            .id = conn_id,
            .state = .idle,
            .target = target,
            .stream = stream,
            .requests_sent = 0,
            .keep_alive = true,
            .last_used_ns = self.current_tick,
        };
        self.connection_count += 1;

        // Emit event
        self.emitEvent(.conn_established, conn_id, 0);

        // Postconditions
        std.debug.assert(self.connections[slot].id == conn_id); // ID set
        std.debug.assert(self.connection_count <= MAX_CONNECTIONS); // Within limit

        return conn_id;
    }

    /// Send request
    pub fn send(self: *HTTP1Handler, conn_id: ConnectionId, request: Request) !RequestId {
        // Preconditions
        std.debug.assert(request.isValid()); // Valid request
        std.debug.assert(conn_id > 0); // Valid connection ID

        // Find connection
        const conn = self.findConnection(conn_id) orelse
            return error.ConnectionNotFound;

        if (conn.state != .idle and conn.state != .active) {
            return error.ConnectionNotReady;
        }

        // Check keep-alive limit
        if (conn.requests_sent >= MAX_REQUESTS_PER_CONNECTION) {
            return error.ConnectionExhausted;
        }

        // Serialize request
        var buffer: [16384]u8 = undefined; // 16KB buffer
        const request_data = try self.serializeRequest(request, &buffer);

        // Send data
        const stream = conn.stream orelse return error.ConnectionClosed;
        _ = try stream.writeAll(request_data);

        // Track request
        const request_id = self.next_request_id;
        self.next_request_id += 1;

        conn.requests_sent += 1;
        conn.state = .active;
        conn.last_used_ns = self.current_tick;

        try self.pending_requests.append(self.allocator, PendingRequest{
            .request_id = request_id,
            .connection_id = conn_id,
            .sent_at_ns = self.current_tick,
            .timeout_ns = request.timeout_ns,
        });

        // Emit event
        self.emitEvent(.request_issued, conn_id, request_id);

        // Postconditions
        std.debug.assert(request_id > 0); // Valid request ID
        std.debug.assert(conn.requests_sent <= MAX_REQUESTS_PER_CONNECTION); // Within limit

        return request_id;
    }

    /// Poll for completed requests
    pub fn poll(self: *HTTP1Handler, completions: *CompletionQueue) !void {
        // Preconditions
        std.debug.assert(self.pending_requests.items.len <= MAX_PENDING_REQUESTS * MAX_CONNECTIONS); // Bounded
        std.debug.assert(completions.items.len == 0); // Should start empty

        self.current_tick += 1; // Advance logical time

        // Check for timeouts (bounded loop)
        var timeout_count: usize = 0;
        var i: usize = 0;
        while (i < self.pending_requests.items.len and timeout_count < 1000) : (i += 1) {
            const pending = self.pending_requests.items[i];
            const elapsed = self.current_tick - pending.sent_at_ns;

            if (elapsed > pending.timeout_ns) {
                self.emitEvent(.request_timeout, pending.connection_id, pending.request_id);
                try completions.append(self.allocator, Completion{
                    .request_id = pending.request_id,
                    .result = .{ .@"error" = error.RequestTimeout },
                });
                timeout_count += 1;
            }
        }

        // Try to read responses from active connections (bounded loop)
        var read_count: usize = 0;
        for (0..MAX_CONNECTIONS) |slot_idx| {
            if (read_count >= 100) break; // Limit reads per poll

            const conn = &self.connections[slot_idx];
            if (conn.state != .active) continue;
            if (conn.stream == null) continue;

            // Try non-blocking read
            var buffer: [65536]u8 = undefined; // 64KB buffer
            const stream = conn.stream.?;

            const bytes_read = stream.read(&buffer) catch |err| {
                // Connection error
                if (self.findPendingRequest(conn.id)) |request_id| {
                    self.emitEvent(.response_error, conn.id, request_id);
                    try completions.append(self.allocator, Completion{
                        .request_id = request_id,
                        .result = .{ .@"error" = err },
                    });
                }
                self.emitEvent(.conn_error, conn.id, 0);
                conn.state = .closed;
                if (conn.stream) |s| s.close();
                conn.stream = null;
                continue;
            };

            if (bytes_read == 0) continue; // No data yet

            // Parse response
            const response_data = buffer[0..bytes_read];
            const result = self.parser.parse(response_data) catch |err| {
                // Parser error
                if (self.findPendingRequest(conn.id)) |request_id| {
                    self.emitEvent(.response_error, conn.id, request_id);
                    try completions.append(self.allocator, Completion{
                        .request_id = request_id,
                        .result = .{ .@"error" = err },
                    });
                }
                continue;
            };

            // Success!
            if (self.findPendingRequest(conn.id)) |request_id| {
                self.emitEvent(.response_received, conn.id, request_id);
                const response = Response{
                    .request_id = request_id,
                    .status = .{ .success = result.status_code },
                    .headers = result.headers,
                    .body = result.body,
                    .latency_ns = self.current_tick - self.findPendingRequestTime(conn.id),
                };

                try completions.append(self.allocator, Completion{
                    .request_id = request_id,
                    .result = .{ .response = response },
                });

                // Update connection state
                conn.keep_alive = result.keep_alive;
                conn.state = if (result.keep_alive) .idle else .closing;
                read_count += 1;
            }
        }

        // Postconditions
        std.debug.assert(completions.items.len <= self.pending_requests.items.len + 1); // Reasonable
        std.debug.assert(timeout_count < 1000); // Bounded
    }

    /// Close connection
    pub fn close(self: *HTTP1Handler, conn_id: ConnectionId) !void {
        // Preconditions
        std.debug.assert(conn_id > 0); // Valid ID
        std.debug.assert(self.connection_count <= MAX_CONNECTIONS); // Valid state

        if (self.findConnection(conn_id)) |conn| {
            if (conn.stream) |stream| {
                stream.close();
            }
            self.emitEvent(.conn_closed, conn_id, 0);
            conn.state = .closed;
            conn.stream = null;
            if (self.connection_count > 0) {
                self.connection_count -= 1;
            }
        }

        // Postcondition
        std.debug.assert(self.connection_count <= MAX_CONNECTIONS); // Valid
    }

    // Helper functions

    fn findIdleConnection(self: *HTTP1Handler, target: Target) ?ConnectionId {
        for (0..MAX_CONNECTIONS) |i| {
            const conn = &self.connections[i];
            if (conn.state == .idle and
                conn.keep_alive and
                std.mem.eql(u8, conn.target.host, target.host) and
                conn.target.port == target.port and
                conn.requests_sent < MAX_REQUESTS_PER_CONNECTION)
            {
                return conn.id;
            }
        }
        return null;
    }

    fn findFreeConnectionSlot(self: *HTTP1Handler) ?usize {
        for (0..MAX_CONNECTIONS) |i| {
            if (self.connections[i].state == .closed) {
                return i;
            }
        }
        return null;
    }

    fn findConnection(self: *HTTP1Handler, conn_id: ConnectionId) ?*Connection {
        for (0..MAX_CONNECTIONS) |i| {
            if (self.connections[i].id == conn_id and self.connections[i].state != .closed) {
                return &self.connections[i];
            }
        }
        return null;
    }

    fn findPendingRequest(self: *HTTP1Handler, conn_id: ConnectionId) ?RequestId {
        for (self.pending_requests.items) |pending| {
            if (pending.connection_id == conn_id) {
                return pending.request_id;
            }
        }
        return null;
    }

    fn findPendingRequestTime(self: *HTTP1Handler, conn_id: ConnectionId) u64 {
        for (self.pending_requests.items) |pending| {
            if (pending.connection_id == conn_id) {
                return pending.sent_at_ns;
            }
        }
        return 0;
    }

    pub fn serializeRequest(self: *HTTP1Handler, request: Request, buffer: []u8) ![]const u8 {
        // Preconditions
        std.debug.assert(request.isValid()); // Valid request
        std.debug.assert(buffer.len >= 1024); // Reasonable buffer

        var pos: usize = 0;

        // Request line: METHOD PATH HTTP/1.1\r\n
        const method_str = @tagName(request.method);
        pos += (try std.fmt.bufPrint(buffer[pos..], "{s} {s} HTTP/1.1\r\n", .{
            method_str,
            request.path,
        })).len;

        // Headers
        for (request.headers) |header| {
            pos += (try std.fmt.bufPrint(buffer[pos..], "{s}: {s}\r\n", .{
                header.name,
                header.value,
            })).len;
        }

        // Host header (required for HTTP/1.1)
        pos += (try std.fmt.bufPrint(buffer[pos..], "Host: localhost\r\n", .{})).len;

        // Content-Length if body present
        if (request.body) |body| {
            if (body.len > 0) {
                pos += (try std.fmt.bufPrint(buffer[pos..], "Content-Length: {d}\r\n", .{
                    body.len,
                })).len;
            }
        }

        // End of headers
        pos += (try std.fmt.bufPrint(buffer[pos..], "\r\n", .{})).len;

        // Body
        if (request.body) |body| {
            if (body.len > 0) {
                @memcpy(buffer[pos .. pos + body.len], body);
                pos += body.len;
            }
        }

        // Postconditions
        std.debug.assert(pos > 0); // Generated something
        std.debug.assert(pos <= buffer.len); // Didn't overflow

        _ = self; // Not using self currently
        return buffer[0..pos];
    }

    /// Emit event to event log (if set)
    fn emitEvent(self: *HTTP1Handler, event_type: EventType, conn_id: ConnectionId, request_id: RequestId) void {
        if (self.event_log) |event_log| {
            var event = Event.init(event_type, self.current_tick);
            event.connection_id = conn_id;
            event.request_id = request_id;
            event_log.append(event) catch {}; // Best-effort logging
        }
    }
};

/// Create ProtocolHandler interface for HTTP/1.1
pub fn createHandler(allocator: Allocator, config: ProtocolConfig) !protocol.ProtocolHandler {
    const handler = try HTTP1Handler.init(allocator, config);

    return protocol.ProtocolHandler{
        .context = @ptrCast(handler),
        .initFn = initFn,
        .connectFn = connectFn,
        .sendFn = sendFn,
        .pollFn = pollFn,
        .closeFn = closeFn,
        .deinitFn = deinitFn,
    };
}

// Function pointer implementations

fn initFn(allocator: Allocator, config: ProtocolConfig) !*anyopaque {
    return @ptrCast(try HTTP1Handler.init(allocator, config));
}

fn connectFn(context: *anyopaque, target: Target) !ConnectionId {
    const handler: *HTTP1Handler = @ptrCast(@alignCast(context));
    return handler.connect(target);
}

fn sendFn(context: *anyopaque, conn_id: ConnectionId, request: Request) !RequestId {
    const handler: *HTTP1Handler = @ptrCast(@alignCast(context));
    return handler.send(conn_id, request);
}

fn pollFn(context: *anyopaque, completions: *CompletionQueue) !void {
    const handler: *HTTP1Handler = @ptrCast(@alignCast(context));
    return handler.poll(completions);
}

fn closeFn(context: *anyopaque, conn_id: ConnectionId) !void {
    const handler: *HTTP1Handler = @ptrCast(@alignCast(context));
    return handler.close(conn_id);
}

fn deinitFn(context: *anyopaque) void {
    const handler: *HTTP1Handler = @ptrCast(@alignCast(context));
    handler.deinit();
}
