//! HTTP/2 Frame Parser
//!
//! Implements HTTP/2 frame parsing per RFC 7540.
//!
//! Features:
//! - Frame header parsing (9 bytes)
//! - Core frame types: SETTINGS, DATA, PING
//! - Frame validation
//! - Bounds checking (max 16MB per frame)
//!
//! Tiger Style:
//! - All loops bounded
//! - Minimum 2 assertions per function
//! - Explicit error handling

const std = @import("std");

/// HTTP/2 frame types (RFC 7540 Section 6)
pub const FrameType = enum(u8) {
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

/// Frame parsing errors
pub const FrameError = error{
    FrameTooShort,
    FrameTooLarge,
    InvalidFrameType,
    InvalidStreamId,
    ProtocolError,
    FlowControlError,
};

/// Maximum frame payload size (16MB - 1)
pub const MAX_FRAME_SIZE: u24 = (1 << 24) - 1;

/// Default max frame size (16KB)
pub const DEFAULT_MAX_FRAME_SIZE: u24 = 1 << 14;

/// HTTP/2 connection preface
pub const CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

/// Frame header (9 bytes)
pub const FrameHeader = struct {
    length: u24, // Payload length
    frame_type: FrameType,
    flags: u8,
    stream_id: u31, // 31-bit stream identifier
};

/// Parsed frame
pub const Frame = struct {
    header: FrameHeader,
    payload: []const u8,
};

/// SETTINGS frame parameter
pub const SettingsParameter = struct {
    identifier: u16,
    value: u32,
};

/// SETTINGS identifiers (RFC 7540 Section 6.5.2)
pub const SettingsIdentifier = enum(u16) {
    SETTINGS_HEADER_TABLE_SIZE = 0x1,
    SETTINGS_ENABLE_PUSH = 0x2,
    SETTINGS_MAX_CONCURRENT_STREAMS = 0x3,
    SETTINGS_INITIAL_WINDOW_SIZE = 0x4,
    SETTINGS_MAX_FRAME_SIZE = 0x5,
    SETTINGS_MAX_HEADER_LIST_SIZE = 0x6,
};

/// Frame flags
pub const FrameFlags = struct {
    pub const END_STREAM: u8 = 0x1; // DATA, HEADERS
    pub const ACK: u8 = 0x1; // SETTINGS, PING
    pub const END_HEADERS: u8 = 0x4; // HEADERS, PUSH_PROMISE, CONTINUATION
    pub const PADDED: u8 = 0x8; // DATA, HEADERS, PUSH_PROMISE
    pub const PRIORITY: u8 = 0x20; // HEADERS
};

/// HTTP/2 Frame Parser
pub const HTTP2FrameParser = struct {
    allocator: std.mem.Allocator,
    max_frame_size: u24,

    /// Initialize parser
    pub fn init(allocator: std.mem.Allocator) HTTP2FrameParser {
        return HTTP2FrameParser{
            .allocator = allocator,
            .max_frame_size = DEFAULT_MAX_FRAME_SIZE,
        };
    }

    /// Parse frame header (9 bytes)
    pub fn parseHeader(self: *HTTP2FrameParser, data: []const u8) !FrameHeader {
        // Validate input length
        if (data.len < 9) {
            return FrameError.FrameTooShort;
        }

        // Preconditions (verified after input validation)
        std.debug.assert(self.max_frame_size <= MAX_FRAME_SIZE); // Valid limit

        // Parse length (24 bits, big-endian)
        const length: u24 = (@as(u24, data[0]) << 16) |
            (@as(u24, data[1]) << 8) |
            (@as(u24, data[2]));

        // Parse type (8 bits)
        const frame_type_int = data[3];
        const frame_type = std.meta.intToEnum(FrameType, frame_type_int) catch {
            return FrameError.InvalidFrameType;
        };

        // Parse flags (8 bits)
        const flags = data[4];

        // Parse stream ID (31 bits, big-endian, ignore R bit)
        const stream_id: u31 = @intCast(
            ((@as(u32, data[5] & 0x7F) << 24) |
                (@as(u32, data[6]) << 16) |
                (@as(u32, data[7]) << 8) |
                (@as(u32, data[8]))),
        );

        // Postconditions
        std.debug.assert(length <= MAX_FRAME_SIZE); // Within spec limit
        std.debug.assert(stream_id <= (1 << 31) - 1); // 31-bit value

        return FrameHeader{
            .length = length,
            .frame_type = frame_type,
            .flags = flags,
            .stream_id = stream_id,
        };
    }

    /// Parse complete frame
    pub fn parseFrame(self: *HTTP2FrameParser, data: []const u8) !Frame {
        // Precondition (self is valid)
        std.debug.assert(self.max_frame_size <= MAX_FRAME_SIZE); // Valid

        // parseHeader validates data.len >= 9 and returns error if too short
        const header = try self.parseHeader(data);

        // Check frame size
        if (header.length > self.max_frame_size) {
            return FrameError.FrameTooLarge;
        }

        // Check we have full frame
        if (data.len < 9 + header.length) {
            return FrameError.FrameTooShort;
        }

        const payload = data[9 .. 9 + header.length];

        // Postconditions
        std.debug.assert(payload.len == header.length); // Correct payload
        std.debug.assert(payload.len <= self.max_frame_size); // Within limit

        return Frame{
            .header = header,
            .payload = payload,
        };
    }

    /// Parse SETTINGS frame payload
    pub fn parseSettingsFrame(self: *HTTP2FrameParser, frame: Frame) ![]SettingsParameter {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .SETTINGS);

        // SETTINGS frames MUST be on stream 0 (RFC 7540 Section 6.5)
        if (frame.header.stream_id != 0) {
            return FrameError.ProtocolError;
        }

        // ACK flag means empty payload
        if (frame.header.flags & FrameFlags.ACK != 0) {
            if (frame.payload.len != 0) {
                return FrameError.ProtocolError;
            }
            return &[_]SettingsParameter{};
        }

        // Each parameter is 6 bytes
        if (frame.payload.len % 6 != 0) {
            return FrameError.ProtocolError;
        }

        const param_count = frame.payload.len / 6;
        const params = try self.allocator.alloc(SettingsParameter, param_count);

        var i: usize = 0;
        while (i < param_count and i < 100) : (i += 1) {
            const offset = i * 6;
            const identifier: u16 = (@as(u16, frame.payload[offset]) << 8) |
                (@as(u16, frame.payload[offset + 1]));
            const value: u32 = (@as(u32, frame.payload[offset + 2]) << 24) |
                (@as(u32, frame.payload[offset + 3]) << 16) |
                (@as(u32, frame.payload[offset + 4]) << 8) |
                (@as(u32, frame.payload[offset + 5]));

            params[i] = SettingsParameter{
                .identifier = identifier,
                .value = value,
            };
        }

        // Postconditions
        std.debug.assert(params.len == param_count); // Correct count
        std.debug.assert(i < 100); // Bounded loop

        return params;
    }

    /// Parse DATA frame
    pub fn parseDataFrame(self: *HTTP2FrameParser, frame: Frame) ![]const u8 {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .DATA);

        // DATA frames MUST be associated with a stream (RFC 7540 Section 6.1)
        if (frame.header.stream_id == 0) {
            return FrameError.ProtocolError;
        }

        var payload = frame.payload;

        // Handle padding if present
        if (frame.header.flags & FrameFlags.PADDED != 0) {
            if (payload.len < 1) {
                return FrameError.ProtocolError;
            }
            const pad_length = payload[0];
            if (payload.len < 1 + pad_length) {
                return FrameError.ProtocolError;
            }
            payload = payload[1 .. payload.len - pad_length];
        }

        // Postcondition: result is valid slice within original payload
        std.debug.assert(payload.len <= frame.payload.len);

        _ = self;
        return payload;
    }

    /// Parse PING frame
    pub fn parsePingFrame(self: *HTTP2FrameParser, frame: Frame) ![8]u8 {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .PING);

        // PING frames MUST be on stream 0 (RFC 7540 Section 6.7)
        if (frame.header.stream_id != 0) {
            return FrameError.ProtocolError;
        }

        // PING payload MUST be exactly 8 bytes
        if (frame.payload.len != 8) {
            return FrameError.ProtocolError;
        }

        var opaque_data: [8]u8 = undefined;
        @memcpy(&opaque_data, frame.payload[0..8]);

        // Postconditions
        std.debug.assert(opaque_data.len == 8); // Correct size
        std.debug.assert(frame.payload.len == 8); // Validated

        _ = self; // Not using self currently
        return opaque_data;
    }

    /// Validate connection preface
    pub fn validatePreface(data: []const u8) bool {
        // Compile-time assertion: spec constant is 24 bytes
        comptime std.debug.assert(CONNECTION_PREFACE.len == 24);

        if (data.len < CONNECTION_PREFACE.len) {
            return false;
        }

        return std.mem.eql(u8, data[0..CONNECTION_PREFACE.len], CONNECTION_PREFACE);
    }

    /// Parse PRIORITY frame (RFC 7540 Section 6.3)
    pub fn parsePriorityFrame(self: *HTTP2FrameParser, frame: Frame) !PriorityPayload {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .PRIORITY);

        // PRIORITY frames MUST be associated with a stream
        if (frame.header.stream_id == 0) {
            return FrameError.ProtocolError;
        }

        // PRIORITY payload MUST be exactly 5 bytes
        if (frame.payload.len != 5) {
            return FrameError.ProtocolError;
        }

        // Parse exclusive bit (1 bit) and stream dependency (31 bits)
        const exclusive = (frame.payload[0] & 0x80) != 0;
        const stream_dependency: u31 = @intCast(
            ((@as(u32, frame.payload[0] & 0x7F) << 24) |
                (@as(u32, frame.payload[1]) << 16) |
                (@as(u32, frame.payload[2]) << 8) |
                (@as(u32, frame.payload[3]))),
        );
        const weight = frame.payload[4];

        // Postconditions
        std.debug.assert(stream_dependency <= (1 << 31) - 1); // 31-bit value guaranteed by cast

        _ = self;
        return PriorityPayload{
            .exclusive = exclusive,
            .stream_dependency = stream_dependency,
            .weight = weight,
        };
    }

    /// Parse RST_STREAM frame (RFC 7540 Section 6.4)
    pub fn parseRstStreamFrame(self: *HTTP2FrameParser, frame: Frame) !u32 {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .RST_STREAM);

        // RST_STREAM frames MUST be associated with a stream
        if (frame.header.stream_id == 0) {
            return FrameError.ProtocolError;
        }

        // RST_STREAM payload MUST be exactly 4 bytes (error code)
        if (frame.payload.len != 4) {
            return FrameError.ProtocolError;
        }

        // Parse error code (32 bits, big-endian)
        const error_code: u32 = (@as(u32, frame.payload[0]) << 24) |
            (@as(u32, frame.payload[1]) << 16) |
            (@as(u32, frame.payload[2]) << 8) |
            (@as(u32, frame.payload[3]));

        _ = self;
        return error_code;
    }

    /// Parse GOAWAY frame (RFC 7540 Section 6.8)
    pub fn parseGoawayFrame(self: *HTTP2FrameParser, frame: Frame) !GoawayPayload {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .GOAWAY);

        // GOAWAY frames MUST be on stream 0
        if (frame.header.stream_id != 0) {
            return FrameError.ProtocolError;
        }

        // GOAWAY payload MUST be at least 8 bytes
        if (frame.payload.len < 8) {
            return FrameError.ProtocolError;
        }

        // Parse last stream ID (31 bits, R bit ignored)
        const last_stream_id: u31 = @intCast(
            ((@as(u32, frame.payload[0] & 0x7F) << 24) |
                (@as(u32, frame.payload[1]) << 16) |
                (@as(u32, frame.payload[2]) << 8) |
                (@as(u32, frame.payload[3]))),
        );

        // Parse error code (32 bits)
        const error_code: u32 = (@as(u32, frame.payload[4]) << 24) |
            (@as(u32, frame.payload[5]) << 16) |
            (@as(u32, frame.payload[6]) << 8) |
            (@as(u32, frame.payload[7]));

        // Debug data is optional
        const debug_data = if (frame.payload.len > 8) frame.payload[8..] else &[_]u8{};

        // Postcondition: result slices are within bounds
        std.debug.assert(debug_data.len <= frame.payload.len);

        _ = self;
        return GoawayPayload{
            .last_stream_id = last_stream_id,
            .error_code = error_code,
            .debug_data = debug_data,
        };
    }

    /// Parse WINDOW_UPDATE frame (RFC 7540 Section 6.9)
    pub fn parseWindowUpdateFrame(self: *HTTP2FrameParser, frame: Frame) !u31 {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .WINDOW_UPDATE);

        // WINDOW_UPDATE payload MUST be exactly 4 bytes
        if (frame.payload.len != 4) {
            return FrameError.ProtocolError;
        }

        // Parse window size increment (31 bits, R bit ignored)
        const window_size_increment: u31 = @intCast(
            ((@as(u32, frame.payload[0] & 0x7F) << 24) |
                (@as(u32, frame.payload[1]) << 16) |
                (@as(u32, frame.payload[2]) << 8) |
                (@as(u32, frame.payload[3]))),
        );

        // Window size increment of 0 is a flow control error (RFC 7540 Section 6.9)
        if (window_size_increment == 0) {
            return FrameError.FlowControlError;
        }

        _ = self;
        return window_size_increment;
    }

    /// Parse HEADERS frame (RFC 7540 Section 6.2)
    /// Note: Returns raw header block fragment. HPACK decoding required separately.
    pub fn parseHeadersFrame(self: *HTTP2FrameParser, frame: Frame) !HeadersPayload {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .HEADERS);

        // HEADERS frames MUST be associated with a stream
        if (frame.header.stream_id == 0) {
            return FrameError.ProtocolError;
        }

        var payload = frame.payload;
        var pad_length: u8 = 0;
        var priority: ?PriorityPayload = null;

        // Handle PADDED flag
        if (frame.header.flags & FrameFlags.PADDED != 0) {
            if (payload.len < 1) {
                return FrameError.ProtocolError;
            }
            pad_length = payload[0];
            payload = payload[1..];
        }

        // Handle PRIORITY flag
        if (frame.header.flags & FrameFlags.PRIORITY != 0) {
            if (payload.len < 5) {
                return FrameError.ProtocolError;
            }
            const exclusive = (payload[0] & 0x80) != 0;
            const stream_dependency: u31 = @intCast(
                ((@as(u32, payload[0] & 0x7F) << 24) |
                    (@as(u32, payload[1]) << 16) |
                    (@as(u32, payload[2]) << 8) |
                    (@as(u32, payload[3]))),
            );
            const weight = payload[4];
            priority = PriorityPayload{
                .exclusive = exclusive,
                .stream_dependency = stream_dependency,
                .weight = weight,
            };
            payload = payload[5..];
        }

        // Remove padding from end
        if (pad_length > 0) {
            if (payload.len < pad_length) {
                return FrameError.ProtocolError;
            }
            payload = payload[0 .. payload.len - pad_length];
        }

        // Postcondition: result slice is within bounds
        std.debug.assert(payload.len <= frame.payload.len);

        _ = self;
        return HeadersPayload{
            .priority = priority,
            .header_block_fragment = payload,
            .end_stream = (frame.header.flags & FrameFlags.END_STREAM) != 0,
            .end_headers = (frame.header.flags & FrameFlags.END_HEADERS) != 0,
        };
    }

    /// Parse CONTINUATION frame (RFC 7540 Section 6.10)
    pub fn parseContinuationFrame(self: *HTTP2FrameParser, frame: Frame) !ContinuationPayload {
        // Precondition: caller must pass correct frame type
        std.debug.assert(frame.header.frame_type == .CONTINUATION);

        // CONTINUATION frames MUST be associated with a stream
        if (frame.header.stream_id == 0) {
            return FrameError.ProtocolError;
        }

        _ = self;
        return ContinuationPayload{
            .header_block_fragment = frame.payload,
            .end_headers = (frame.header.flags & FrameFlags.END_HEADERS) != 0,
        };
    }

    /// Free settings parameters
    pub fn freeSettings(self: *HTTP2FrameParser, params: []SettingsParameter) void {
        self.allocator.free(params);
    }
};

/// PRIORITY frame payload
pub const PriorityPayload = struct {
    exclusive: bool,
    stream_dependency: u31,
    weight: u8,
};

/// GOAWAY frame payload
pub const GoawayPayload = struct {
    last_stream_id: u31,
    error_code: u32,
    debug_data: []const u8,
};

/// HEADERS frame payload
pub const HeadersPayload = struct {
    priority: ?PriorityPayload,
    header_block_fragment: []const u8, // Requires HPACK decoding
    end_stream: bool,
    end_headers: bool,
};

/// CONTINUATION frame payload
pub const ContinuationPayload = struct {
    header_block_fragment: []const u8, // Requires HPACK decoding
    end_headers: bool,
};

/// HTTP/2 error codes (RFC 7540 Section 7)
pub const ErrorCode = enum(u32) {
    NO_ERROR = 0x0,
    PROTOCOL_ERROR = 0x1,
    INTERNAL_ERROR = 0x2,
    FLOW_CONTROL_ERROR = 0x3,
    SETTINGS_TIMEOUT = 0x4,
    STREAM_CLOSED = 0x5,
    FRAME_SIZE_ERROR = 0x6,
    REFUSED_STREAM = 0x7,
    CANCEL = 0x8,
    COMPRESSION_ERROR = 0x9,
    CONNECT_ERROR = 0xa,
    ENHANCE_YOUR_CALM = 0xb,
    INADEQUATE_SECURITY = 0xc,
    HTTP_1_1_REQUIRED = 0xd,
};

// ============================================================================
// Frame Serialization Functions
// ============================================================================

/// Serialize frame header (9 bytes) into buffer
/// Returns the 9-byte header
pub fn serializeFrameHeader(header: FrameHeader) [9]u8 {
    // Preconditions
    std.debug.assert(header.length <= MAX_FRAME_SIZE); // Valid length
    std.debug.assert(header.stream_id <= (1 << 31) - 1); // 31-bit stream ID

    var buffer: [9]u8 = undefined;

    // Length (24 bits, big-endian)
    buffer[0] = @intCast((header.length >> 16) & 0xFF);
    buffer[1] = @intCast((header.length >> 8) & 0xFF);
    buffer[2] = @intCast(header.length & 0xFF);

    // Type (8 bits)
    buffer[3] = @intFromEnum(header.frame_type);

    // Flags (8 bits)
    buffer[4] = header.flags;

    // Stream ID (31 bits, big-endian, R bit = 0)
    buffer[5] = @intCast((header.stream_id >> 24) & 0x7F);
    buffer[6] = @intCast((header.stream_id >> 16) & 0xFF);
    buffer[7] = @intCast((header.stream_id >> 8) & 0xFF);
    buffer[8] = @intCast(header.stream_id & 0xFF);

    // Postconditions
    std.debug.assert(buffer[5] & 0x80 == 0); // R bit is 0

    return buffer;
}

/// Serialize a single SETTINGS parameter (6 bytes)
fn serializeSettingsParameter(identifier: u16, value: u32, buffer: []u8) void {
    // Preconditions
    std.debug.assert(buffer.len >= 6);

    // Identifier (16 bits, big-endian)
    buffer[0] = @intCast((identifier >> 8) & 0xFF);
    buffer[1] = @intCast(identifier & 0xFF);

    // Value (32 bits, big-endian)
    buffer[2] = @intCast((value >> 24) & 0xFF);
    buffer[3] = @intCast((value >> 16) & 0xFF);
    buffer[4] = @intCast((value >> 8) & 0xFF);
    buffer[5] = @intCast(value & 0xFF);
}

/// HTTP/2 Settings for serialization
pub const Settings = struct {
    header_table_size: u32 = 4096,
    enable_push: bool = false,
    max_concurrent_streams: u32 = 100,
    initial_window_size: u32 = 65535,
    max_frame_size: u32 = 16384,
    max_header_list_size: u32 = 8192,
};

/// Serialize SETTINGS frame
/// Returns total bytes written (9 header + 36 payload for 6 settings)
pub fn serializeSettingsFrame(settings: Settings, buffer: []u8) usize {
    // Preconditions
    std.debug.assert(buffer.len >= 9 + 36); // Header + 6 settings * 6 bytes
    std.debug.assert(settings.max_frame_size >= 16384); // RFC minimum

    var pos: usize = 9; // Start after header

    // SETTINGS_HEADER_TABLE_SIZE (0x1)
    serializeSettingsParameter(0x1, settings.header_table_size, buffer[pos..]);
    pos += 6;

    // SETTINGS_ENABLE_PUSH (0x2)
    serializeSettingsParameter(0x2, if (settings.enable_push) 1 else 0, buffer[pos..]);
    pos += 6;

    // SETTINGS_MAX_CONCURRENT_STREAMS (0x3)
    serializeSettingsParameter(0x3, settings.max_concurrent_streams, buffer[pos..]);
    pos += 6;

    // SETTINGS_INITIAL_WINDOW_SIZE (0x4)
    serializeSettingsParameter(0x4, settings.initial_window_size, buffer[pos..]);
    pos += 6;

    // SETTINGS_MAX_FRAME_SIZE (0x5)
    serializeSettingsParameter(0x5, settings.max_frame_size, buffer[pos..]);
    pos += 6;

    // SETTINGS_MAX_HEADER_LIST_SIZE (0x6)
    serializeSettingsParameter(0x6, settings.max_header_list_size, buffer[pos..]);
    pos += 6;

    const payload_len: u24 = 36;

    // Write frame header
    const header = serializeFrameHeader(.{
        .length = payload_len,
        .frame_type = .SETTINGS,
        .flags = 0,
        .stream_id = 0,
    });
    @memcpy(buffer[0..9], &header);

    // Postconditions
    std.debug.assert(pos == 9 + 36);

    return pos;
}

/// Serialize SETTINGS ACK frame (empty payload)
pub fn serializeSettingsAck(buffer: []u8) usize {
    // Preconditions
    std.debug.assert(buffer.len >= 9);

    const header = serializeFrameHeader(.{
        .length = 0,
        .frame_type = .SETTINGS,
        .flags = FrameFlags.ACK,
        .stream_id = 0,
    });
    @memcpy(buffer[0..9], &header);

    // Postconditions
    std.debug.assert(buffer[4] == FrameFlags.ACK);

    return 9;
}

/// Serialize DATA frame
/// Returns total bytes written (9 header + payload)
pub fn serializeDataFrame(
    stream_id: u31,
    data: []const u8,
    end_stream: bool,
    buffer: []u8,
) usize {
    // Preconditions
    std.debug.assert(stream_id > 0); // DATA must be on a stream
    std.debug.assert(data.len <= DEFAULT_MAX_FRAME_SIZE); // Within frame size
    std.debug.assert(buffer.len >= 9 + data.len);

    var flags: u8 = 0;
    if (end_stream) {
        flags |= FrameFlags.END_STREAM;
    }

    const header = serializeFrameHeader(.{
        .length = @intCast(data.len),
        .frame_type = .DATA,
        .flags = flags,
        .stream_id = stream_id,
    });
    @memcpy(buffer[0..9], &header);
    @memcpy(buffer[9..][0..data.len], data);

    // Postconditions
    std.debug.assert(buffer[5] & 0x80 == 0); // R bit is 0

    return 9 + data.len;
}

/// Serialize HEADERS frame (without HPACK - caller provides encoded header block)
/// Returns total bytes written
pub fn serializeHeadersFrame(
    stream_id: u31,
    header_block: []const u8,
    end_stream: bool,
    end_headers: bool,
    buffer: []u8,
) usize {
    // Preconditions
    std.debug.assert(stream_id > 0); // HEADERS must be on a stream
    std.debug.assert(stream_id % 2 == 1); // Client streams are odd
    std.debug.assert(header_block.len <= DEFAULT_MAX_FRAME_SIZE);
    std.debug.assert(buffer.len >= 9 + header_block.len);

    var flags: u8 = 0;
    if (end_stream) {
        flags |= FrameFlags.END_STREAM;
    }
    if (end_headers) {
        flags |= FrameFlags.END_HEADERS;
    }

    const header = serializeFrameHeader(.{
        .length = @intCast(header_block.len),
        .frame_type = .HEADERS,
        .flags = flags,
        .stream_id = stream_id,
    });
    @memcpy(buffer[0..9], &header);
    @memcpy(buffer[9..][0..header_block.len], header_block);

    // Postconditions
    std.debug.assert(buffer[5] & 0x80 == 0); // R bit is 0

    return 9 + header_block.len;
}

/// Serialize PING frame (8-byte opaque data)
pub fn serializePingFrame(opaque_data: [8]u8, ack: bool, buffer: []u8) usize {
    // Preconditions
    std.debug.assert(buffer.len >= 17); // 9 header + 8 payload

    var flags: u8 = 0;
    if (ack) {
        flags |= FrameFlags.ACK;
    }

    const header = serializeFrameHeader(.{
        .length = 8,
        .frame_type = .PING,
        .flags = flags,
        .stream_id = 0, // PING must be on stream 0
    });
    @memcpy(buffer[0..9], &header);
    @memcpy(buffer[9..17], &opaque_data);

    // Postconditions
    std.debug.assert(buffer[5] == 0); // Stream ID high byte is 0

    return 17;
}

/// Serialize WINDOW_UPDATE frame
pub fn serializeWindowUpdateFrame(stream_id: u31, increment: u31, buffer: []u8) usize {
    // Preconditions
    std.debug.assert(increment > 0); // Must be positive
    std.debug.assert(buffer.len >= 13); // 9 header + 4 payload

    const header = serializeFrameHeader(.{
        .length = 4,
        .frame_type = .WINDOW_UPDATE,
        .flags = 0,
        .stream_id = stream_id,
    });
    @memcpy(buffer[0..9], &header);

    // Window size increment (31 bits, R bit = 0)
    buffer[9] = @intCast((increment >> 24) & 0x7F);
    buffer[10] = @intCast((increment >> 16) & 0xFF);
    buffer[11] = @intCast((increment >> 8) & 0xFF);
    buffer[12] = @intCast(increment & 0xFF);

    // Postconditions
    std.debug.assert(buffer[9] & 0x80 == 0); // R bit is 0

    return 13;
}

/// Serialize GOAWAY frame
pub fn serializeGoawayFrame(
    last_stream_id: u31,
    error_code: ErrorCode,
    debug_data: []const u8,
    buffer: []u8,
) usize {
    // Preconditions
    std.debug.assert(buffer.len >= 9 + 8 + debug_data.len);
    std.debug.assert(debug_data.len <= DEFAULT_MAX_FRAME_SIZE - 8);

    const payload_len: u24 = @intCast(8 + debug_data.len);

    const header = serializeFrameHeader(.{
        .length = payload_len,
        .frame_type = .GOAWAY,
        .flags = 0,
        .stream_id = 0, // GOAWAY must be on stream 0
    });
    @memcpy(buffer[0..9], &header);

    // Last stream ID (31 bits, R bit = 0)
    buffer[9] = @intCast((last_stream_id >> 24) & 0x7F);
    buffer[10] = @intCast((last_stream_id >> 16) & 0xFF);
    buffer[11] = @intCast((last_stream_id >> 8) & 0xFF);
    buffer[12] = @intCast(last_stream_id & 0xFF);

    // Error code (32 bits)
    const err_val = @intFromEnum(error_code);
    buffer[13] = @intCast((err_val >> 24) & 0xFF);
    buffer[14] = @intCast((err_val >> 16) & 0xFF);
    buffer[15] = @intCast((err_val >> 8) & 0xFF);
    buffer[16] = @intCast(err_val & 0xFF);

    // Debug data (optional)
    if (debug_data.len > 0) {
        @memcpy(buffer[17..][0..debug_data.len], debug_data);
    }

    // Postconditions
    std.debug.assert(buffer[9] & 0x80 == 0); // R bit is 0

    return 9 + 8 + debug_data.len;
}

/// Serialize RST_STREAM frame
pub fn serializeRstStreamFrame(stream_id: u31, error_code: ErrorCode, buffer: []u8) usize {
    // Preconditions
    std.debug.assert(stream_id > 0); // RST_STREAM must be on a stream
    std.debug.assert(buffer.len >= 13); // 9 header + 4 payload

    const header = serializeFrameHeader(.{
        .length = 4,
        .frame_type = .RST_STREAM,
        .flags = 0,
        .stream_id = stream_id,
    });
    @memcpy(buffer[0..9], &header);

    // Error code (32 bits)
    const err_val = @intFromEnum(error_code);
    buffer[9] = @intCast((err_val >> 24) & 0xFF);
    buffer[10] = @intCast((err_val >> 16) & 0xFF);
    buffer[11] = @intCast((err_val >> 8) & 0xFF);
    buffer[12] = @intCast(err_val & 0xFF);

    // Postconditions
    std.debug.assert(buffer[5] & 0x80 == 0); // R bit is 0

    return 13;
}
