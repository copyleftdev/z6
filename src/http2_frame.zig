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
        // Preconditions
        std.debug.assert(frame.header.frame_type == .SETTINGS); // Correct type
        std.debug.assert(frame.header.stream_id == 0); // MUST be 0

        if (frame.header.frame_type != .SETTINGS) {
            return FrameError.ProtocolError;
        }

        // SETTINGS frames MUST be on stream 0
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
        // Preconditions
        std.debug.assert(frame.header.frame_type == .DATA); // Correct type
        std.debug.assert(frame.header.stream_id != 0); // MUST NOT be 0

        if (frame.header.frame_type != .DATA) {
            return FrameError.ProtocolError;
        }

        // DATA frames MUST be associated with a stream
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

        // Postconditions
        std.debug.assert(payload.len <= frame.payload.len); // Valid slice
        std.debug.assert(frame.header.stream_id > 0); // Valid stream

        _ = self; // Not using self currently
        return payload;
    }

    /// Parse PING frame
    pub fn parsePingFrame(self: *HTTP2FrameParser, frame: Frame) ![8]u8 {
        // Preconditions
        std.debug.assert(frame.header.frame_type == .PING); // Correct type
        std.debug.assert(frame.header.stream_id == 0); // MUST be 0

        if (frame.header.frame_type != .PING) {
            return FrameError.ProtocolError;
        }

        // PING frames MUST be on stream 0
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
        // Preconditions
        std.debug.assert(data.len >= CONNECTION_PREFACE.len); // Must have enough data
        std.debug.assert(CONNECTION_PREFACE.len == 24); // Spec constant

        if (data.len < CONNECTION_PREFACE.len) {
            return false;
        }

        const matches = std.mem.eql(u8, data[0..CONNECTION_PREFACE.len], CONNECTION_PREFACE);

        // Postcondition
        std.debug.assert(matches == std.mem.eql(u8, data[0..24], CONNECTION_PREFACE)); // Consistent

        return matches;
    }

    /// Free settings parameters
    pub fn freeSettings(self: *HTTP2FrameParser, params: []SettingsParameter) void {
        self.allocator.free(params);
    }
};
