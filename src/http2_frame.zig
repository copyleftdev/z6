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
        // Preconditions
        std.debug.assert(data.len >= 9); // Must have at least header
        std.debug.assert(self.max_frame_size <= MAX_FRAME_SIZE); // Valid limit

        if (data.len < 9) {
            return FrameError.FrameTooShort;
        }

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
        // Preconditions
        std.debug.assert(data.len >= 9); // Must have header
        std.debug.assert(self.max_frame_size <= MAX_FRAME_SIZE); // Valid

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
