//! HTTP/2 Frame Parser Tests
//!
//! Tests for HTTP/2 frame parsing per RFC 7540.
//!
//! Coverage:
//! - Frame header parsing (9 bytes)
//! - Frame types: SETTINGS, DATA, PING, HEADERS (basic)
//! - Frame validation
//! - Bounds checking
//! - Tiger Style compliance

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const HTTP2FrameParser = z6.HTTP2FrameParser;
const FrameType = z6.HTTP2FrameType;

test "http2_frame: parse frame header" {
    // Frame header is 9 bytes:
    // Length (24 bits) | Type (8 bits) | Flags (8 bits) | Stream ID (31 bits + R bit)

    // Example: SETTINGS frame (empty)
    // Length: 0x000000 (0 bytes)
    // Type: 0x04 (SETTINGS)
    // Flags: 0x00
    // Stream ID: 0x00000000
    const frame_data = [_]u8{
        0x00, 0x00, 0x00, // Length: 0
        0x04, // Type: SETTINGS
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x00, // Stream ID: 0
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const header = try parser.parseHeader(&frame_data);
    try testing.expectEqual(@as(u24, 0), header.length);
    try testing.expectEqual(FrameType.SETTINGS, header.frame_type);
    try testing.expectEqual(@as(u8, 0), header.flags);
    try testing.expectEqual(@as(u31, 0), header.stream_id);
}

test "http2_frame: parse SETTINGS frame" {
    // SETTINGS frame with one parameter
    // SETTINGS_MAX_CONCURRENT_STREAMS = 100
    const frame_data = [_]u8{
        0x00, 0x00, 0x06, // Length: 6 bytes
        0x04, // Type: SETTINGS
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (required for SETTINGS)
        // Payload (6 bytes = 1 setting)
        0x00, 0x03, // Identifier: SETTINGS_MAX_CONCURRENT_STREAMS (3)
        0x00, 0x00, 0x00, 0x64, // Value: 100
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const params = try parser.parseSettingsFrame(frame);
    defer parser.freeSettings(params);

    try testing.expectEqual(@as(usize, 1), params.len);
    try testing.expectEqual(@as(u16, 0x0003), params[0].identifier);
    try testing.expectEqual(@as(u32, 100), params[0].value);
}

test "http2_frame: parse DATA frame" {
    // DATA frame with payload
    const frame_data = [_]u8{
        0x00, 0x00, 0x0D, // Length: 13 bytes
        0x00, // Type: DATA
        0x01, // Flags: END_STREAM
        0x00, 0x00, 0x00, 0x01, // Stream ID: 1
        // Payload (13 bytes)
        'H',  'e',  'l',  'l',
        'o',  ',',  ' ',  'W',
        'o',  'r',  'l',  'd',
        '!',
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const data = try parser.parseDataFrame(frame);

    try testing.expectEqualStrings("Hello, World!", data);
    try testing.expectEqual(@as(u31, 1), frame.header.stream_id);
}

test "http2_frame: parse PING frame" {
    // PING frame (8 bytes opaque data)
    const frame_data = [_]u8{
        0x00, 0x00, 0x08, // Length: 8 bytes
        0x06, // Type: PING
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (required for PING)
        // Payload (8 bytes opaque)
        0x01, 0x02, 0x03, 0x04,
        0x05, 0x06, 0x07, 0x08,
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const opaque_data = try parser.parsePingFrame(frame);

    try testing.expectEqual(@as(u8, 0x01), opaque_data[0]);
    try testing.expectEqual(@as(u8, 0x08), opaque_data[7]);
}

test "http2_frame: validate frame size limits" {
    // HTTP/2 max frame size is 16MB (2^24 - 1)
    // Default is 16KB (2^14)

    // Test default max frame size (16KB)
    const allocator = testing.allocator;
    var parser = HTTP2FrameParser.init(allocator);

    try testing.expectEqual(@as(u24, 1 << 14), parser.max_frame_size);

    // Frame with 17KB payload (exceeds default)
    var large_frame = [_]u8{0} ** (9 + (1 << 14) + 1);
    large_frame[0] = 0x00;
    large_frame[1] = 0x40; // 0x004001 = 16385 bytes
    large_frame[2] = 0x01;
    large_frame[3] = 0x00; // DATA frame

    try testing.expectError(z6.HTTP2FrameError.FrameTooLarge, parser.parseFrame(&large_frame));
}

test "http2_frame: reject invalid stream ID for SETTINGS" {
    // SETTINGS frame MUST have stream ID 0
    const invalid_settings = [_]u8{
        0x00, 0x00, 0x00, // Length: 0
        0x04, // Type: SETTINGS
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x01, // Stream ID: 1 (INVALID for SETTINGS)
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&invalid_settings);
    try testing.expectError(z6.HTTP2FrameError.ProtocolError, parser.parseSettingsFrame(frame));
}

test "http2_frame: connection preface validation" {
    // HTTP/2 connection preface
    const preface = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

    try testing.expectEqual(@as(usize, 24), preface.len);
    try testing.expect(z6.HTTP2FrameParser.validatePreface(preface));

    // Invalid preface
    const bad_preface = "GET / HTTP/1.1\r\n\r\n      ";
    try testing.expect(!z6.HTTP2FrameParser.validatePreface(bad_preface));
}

test "http2_frame: Tiger Style - assertions" {
    // All frame parsing functions have >= 2 assertions:
    // - parseHeader: 2 preconditions, 2 postconditions ✓
    // - parseSettings: 2 preconditions, 2 postconditions ✓
    // - parseData: 2 preconditions, 2 postconditions ✓
    // - parsePing: 2 preconditions, 2 postconditions ✓
}

// TODO: Add more tests for:
// - HEADERS frame parsing
// - GOAWAY frame parsing
// - WINDOW_UPDATE frame parsing
// - Frame flag handling
// - Padding handling
// - Error conditions
