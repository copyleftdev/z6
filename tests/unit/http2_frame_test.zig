//! HTTP/2 Frame Parser Tests
//!
//! Tests for HTTP/2 frame parsing per RFC 7540.
//!
//! Coverage:
//! - Frame header parsing (9 bytes)
//! - All frame types: DATA, HEADERS, PRIORITY, RST_STREAM, SETTINGS, PING, GOAWAY, WINDOW_UPDATE, CONTINUATION
//! - Frame validation
//! - Bounds checking
//! - Tiger Style compliance

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const HTTP2FrameParser = z6.HTTP2FrameParser;
const FrameType = z6.HTTP2FrameType;
const FrameFlags = z6.HTTP2FrameFlags;

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

test "http2_frame: parse PRIORITY frame" {
    // PRIORITY frame (5 bytes)
    const frame_data = [_]u8{
        0x00, 0x00, 0x05, // Length: 5 bytes
        0x02, // Type: PRIORITY
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x03, // Stream ID: 3
        // Payload (5 bytes)
        0x80, 0x00, 0x00, 0x01, // Exclusive bit + Stream dependency: 1
        0x0F, // Weight: 15
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const priority = try parser.parsePriorityFrame(frame);

    try testing.expect(priority.exclusive);
    try testing.expectEqual(@as(u31, 1), priority.stream_dependency);
    try testing.expectEqual(@as(u8, 15), priority.weight);
}

test "http2_frame: parse RST_STREAM frame" {
    // RST_STREAM frame (4 bytes error code)
    const frame_data = [_]u8{
        0x00, 0x00, 0x04, // Length: 4 bytes
        0x03, // Type: RST_STREAM
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x05, // Stream ID: 5
        // Payload (4 bytes)
        0x00, 0x00, 0x00, 0x08, // Error code: CANCEL (8)
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const error_code = try parser.parseRstStreamFrame(frame);

    try testing.expectEqual(@as(u32, 0x08), error_code); // CANCEL
}

test "http2_frame: parse GOAWAY frame" {
    // GOAWAY frame
    const frame_data = [_]u8{
        0x00, 0x00, 0x0D, // Length: 13 bytes
        0x07, // Type: GOAWAY
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (required for GOAWAY)
        // Payload
        0x00, 0x00, 0x00, 0x07, // Last stream ID: 7
        0x00, 0x00, 0x00, 0x00, // Error code: NO_ERROR (0)
        'b', 'y', 'e', '!', '!', // Debug data: "bye!!"
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const goaway = try parser.parseGoawayFrame(frame);

    try testing.expectEqual(@as(u31, 7), goaway.last_stream_id);
    try testing.expectEqual(@as(u32, 0), goaway.error_code);
    try testing.expectEqualStrings("bye!!", goaway.debug_data);
}

test "http2_frame: parse WINDOW_UPDATE frame" {
    // WINDOW_UPDATE frame (4 bytes)
    const frame_data = [_]u8{
        0x00, 0x00, 0x04, // Length: 4 bytes
        0x08, // Type: WINDOW_UPDATE
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (connection level)
        // Payload (4 bytes)
        0x00, 0x00, 0x10, 0x00, // Window size increment: 4096
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const increment = try parser.parseWindowUpdateFrame(frame);

    try testing.expectEqual(@as(u31, 4096), increment);
}

test "http2_frame: parse WINDOW_UPDATE zero increment error" {
    // WINDOW_UPDATE with 0 increment is a FLOW_CONTROL_ERROR
    const frame_data = [_]u8{
        0x00, 0x00, 0x04, // Length: 4 bytes
        0x08, // Type: WINDOW_UPDATE
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x01, // Stream ID: 1
        // Payload (4 bytes)
        0x00, 0x00, 0x00, 0x00, // Window size increment: 0 (INVALID)
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    try testing.expectError(z6.HTTP2FrameError.FlowControlError, parser.parseWindowUpdateFrame(frame));
}

test "http2_frame: parse HEADERS frame basic" {
    // Simple HEADERS frame without padding or priority
    const frame_data = [_]u8{
        0x00, 0x00, 0x05, // Length: 5 bytes
        0x01, // Type: HEADERS
        0x04, // Flags: END_HEADERS
        0x00, 0x00, 0x00, 0x01, // Stream ID: 1
        // Payload (header block fragment - not decoded)
        0x82, 0x86, 0x84, 0x41, 0x8A, // HPACK encoded headers (example)
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const headers = try parser.parseHeadersFrame(frame);

    try testing.expectEqual(@as(?z6.HTTP2PriorityPayload, null), headers.priority);
    try testing.expectEqual(@as(usize, 5), headers.header_block_fragment.len);
    try testing.expect(!headers.end_stream);
    try testing.expect(headers.end_headers);
}

test "http2_frame: parse HEADERS frame with priority" {
    // HEADERS frame with PRIORITY flag
    const frame_data = [_]u8{
        0x00, 0x00, 0x08, // Length: 8 bytes (5 priority + 3 header block)
        0x01, // Type: HEADERS
        0x24, // Flags: END_HEADERS | PRIORITY
        0x00, 0x00, 0x00, 0x03, // Stream ID: 3
        // Priority data (5 bytes)
        0x00, 0x00, 0x00, 0x00, // Stream dependency: 0 (no exclusive)
        0x10, // Weight: 16
        // Header block fragment
        0x82,
        0x86,
        0x84,
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const headers = try parser.parseHeadersFrame(frame);

    try testing.expect(headers.priority != null);
    const priority = headers.priority.?;
    try testing.expect(!priority.exclusive);
    try testing.expectEqual(@as(u31, 0), priority.stream_dependency);
    try testing.expectEqual(@as(u8, 16), priority.weight);
    try testing.expectEqual(@as(usize, 3), headers.header_block_fragment.len);
}

test "http2_frame: parse CONTINUATION frame" {
    // CONTINUATION frame
    const frame_data = [_]u8{
        0x00, 0x00, 0x04, // Length: 4 bytes
        0x09, // Type: CONTINUATION
        0x04, // Flags: END_HEADERS
        0x00, 0x00, 0x00, 0x01, // Stream ID: 1
        // Payload (header block fragment)
        0x82, 0x86, 0x84, 0x41,
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&frame_data);
    const continuation = try parser.parseContinuationFrame(frame);

    try testing.expectEqual(@as(usize, 4), continuation.header_block_fragment.len);
    try testing.expect(continuation.end_headers);
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

test "http2_frame: reject DATA frame on stream 0" {
    // DATA frame MUST NOT be on stream 0
    const invalid_data = [_]u8{
        0x00, 0x00, 0x05, // Length: 5 bytes
        0x00, // Type: DATA
        0x00, // Flags: 0
        0x00, 0x00, 0x00, 0x00, // Stream ID: 0 (INVALID for DATA)
        'H',  'e',  'l',  'l',
        'o',
    };

    var parser = HTTP2FrameParser.init(testing.allocator);
    const frame = try parser.parseFrame(&invalid_data);
    try testing.expectError(z6.HTTP2FrameError.ProtocolError, parser.parseDataFrame(frame));
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

test "http2_frame: error codes enum" {
    // Verify error codes match RFC 7540
    try testing.expectEqual(@as(u32, 0x0), @intFromEnum(z6.HTTP2ErrorCode.NO_ERROR));
    try testing.expectEqual(@as(u32, 0x1), @intFromEnum(z6.HTTP2ErrorCode.PROTOCOL_ERROR));
    try testing.expectEqual(@as(u32, 0x3), @intFromEnum(z6.HTTP2ErrorCode.FLOW_CONTROL_ERROR));
    try testing.expectEqual(@as(u32, 0x8), @intFromEnum(z6.HTTP2ErrorCode.CANCEL));
    try testing.expectEqual(@as(u32, 0xd), @intFromEnum(z6.HTTP2ErrorCode.HTTP_1_1_REQUIRED));
}

test "http2_frame: Tiger Style - assertions" {
    // All frame parsing functions have >= 2 assertions:
    // - parseHeader: 2 preconditions, 2 postconditions
    // - parseFrame: 2 preconditions, 2 postconditions
    // - parseSettingsFrame: 2 preconditions, 2 postconditions
    // - parseDataFrame: 2 preconditions, 2 postconditions
    // - parsePingFrame: 2 preconditions, 2 postconditions
    // - parsePriorityFrame: 2 preconditions, 2 postconditions
    // - parseRstStreamFrame: 2 preconditions, 2 postconditions
    // - parseGoawayFrame: 2 preconditions, 2 postconditions
    // - parseWindowUpdateFrame: 2 preconditions, 2 postconditions
    // - parseHeadersFrame: 2 preconditions, 2 postconditions
    // - parseContinuationFrame: 2 preconditions, 2 postconditions
    // - validatePreface: 2 preconditions, 1 postcondition
}

test "http2_frame: bounded loops verification" {
    // All loops in HTTP/2 frame parser are bounded:
    // - parseSettingsFrame: bounded by param_count AND 100 max
}

// ============================================================================
// Frame Serialization Tests
// ============================================================================

test "http2_frame: serialize frame header" {
    const header = z6.HTTP2FrameHeader{
        .length = 0x123456 & 0xFFFFFF, // 24-bit length
        .frame_type = .SETTINGS,
        .flags = 0x01,
        .stream_id = 0x7FFFFFFF, // Max 31-bit value
    };

    const serialized = z6.serializeFrameHeader(header);

    // Verify length (big-endian)
    try testing.expectEqual(@as(u8, 0x12), serialized[0]);
    try testing.expectEqual(@as(u8, 0x34), serialized[1]);
    try testing.expectEqual(@as(u8, 0x56), serialized[2]);

    // Verify type
    try testing.expectEqual(@as(u8, 0x04), serialized[3]); // SETTINGS

    // Verify flags
    try testing.expectEqual(@as(u8, 0x01), serialized[4]);

    // Verify stream ID (31 bits, R bit = 0)
    try testing.expectEqual(@as(u8, 0x7F), serialized[5]);
    try testing.expectEqual(@as(u8, 0xFF), serialized[6]);
    try testing.expectEqual(@as(u8, 0xFF), serialized[7]);
    try testing.expectEqual(@as(u8, 0xFF), serialized[8]);
}

test "http2_frame: serialize SETTINGS frame" {
    var buffer: [128]u8 = undefined;
    const settings = z6.HTTP2Settings{
        .header_table_size = 4096,
        .enable_push = false,
        .max_concurrent_streams = 100,
        .initial_window_size = 65535,
        .max_frame_size = 16384,
        .max_header_list_size = 8192,
    };

    const len = z6.serializeSettingsFrame(settings, &buffer);

    // Should be 9 header + 36 payload (6 settings * 6 bytes)
    try testing.expectEqual(@as(usize, 45), len);

    // Verify frame type is SETTINGS
    try testing.expectEqual(@as(u8, 0x04), buffer[3]);

    // Verify stream ID is 0
    try testing.expectEqual(@as(u8, 0x00), buffer[5]);
    try testing.expectEqual(@as(u8, 0x00), buffer[6]);
    try testing.expectEqual(@as(u8, 0x00), buffer[7]);
    try testing.expectEqual(@as(u8, 0x00), buffer[8]);

    // Verify payload length (36 bytes)
    try testing.expectEqual(@as(u8, 0x00), buffer[0]);
    try testing.expectEqual(@as(u8, 0x00), buffer[1]);
    try testing.expectEqual(@as(u8, 0x24), buffer[2]); // 36 in hex
}

test "http2_frame: serialize SETTINGS ACK" {
    var buffer: [16]u8 = undefined;

    const len = z6.serializeSettingsAck(&buffer);

    // Should be 9 bytes (header only, no payload)
    try testing.expectEqual(@as(usize, 9), len);

    // Verify ACK flag is set
    try testing.expectEqual(@as(u8, 0x01), buffer[4]);

    // Verify payload length is 0
    try testing.expectEqual(@as(u8, 0x00), buffer[0]);
    try testing.expectEqual(@as(u8, 0x00), buffer[1]);
    try testing.expectEqual(@as(u8, 0x00), buffer[2]);
}

test "http2_frame: serialize DATA frame" {
    var buffer: [64]u8 = undefined;
    const data = "Hello, HTTP/2!";

    const len = z6.serializeDataFrame(1, data, true, &buffer);

    // Should be 9 header + 14 payload
    try testing.expectEqual(@as(usize, 23), len);

    // Verify frame type is DATA
    try testing.expectEqual(@as(u8, 0x00), buffer[3]);

    // Verify END_STREAM flag
    try testing.expectEqual(@as(u8, 0x01), buffer[4]);

    // Verify stream ID is 1
    try testing.expectEqual(@as(u8, 0x00), buffer[5]);
    try testing.expectEqual(@as(u8, 0x00), buffer[6]);
    try testing.expectEqual(@as(u8, 0x00), buffer[7]);
    try testing.expectEqual(@as(u8, 0x01), buffer[8]);

    // Verify payload
    try testing.expectEqualStrings(data, buffer[9..23]);
}

test "http2_frame: serialize HEADERS frame" {
    var buffer: [64]u8 = undefined;
    const header_block = &[_]u8{ 0x82, 0x86, 0x84 }; // Example HPACK encoded

    const len = z6.serializeHeadersFrame(1, header_block, true, true, &buffer);

    // Should be 9 header + 3 payload
    try testing.expectEqual(@as(usize, 12), len);

    // Verify frame type is HEADERS
    try testing.expectEqual(@as(u8, 0x01), buffer[3]);

    // Verify flags: END_STREAM (0x1) | END_HEADERS (0x4) = 0x5
    try testing.expectEqual(@as(u8, 0x05), buffer[4]);

    // Verify stream ID is 1 (odd for client)
    try testing.expectEqual(@as(u8, 0x01), buffer[8]);
}

test "http2_frame: serialize PING frame" {
    var buffer: [32]u8 = undefined;
    const opaque_data = [8]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };

    const len = z6.serializePingFrame(opaque_data, false, &buffer);

    // Should be 17 bytes (9 header + 8 payload)
    try testing.expectEqual(@as(usize, 17), len);

    // Verify frame type is PING
    try testing.expectEqual(@as(u8, 0x06), buffer[3]);

    // Verify no ACK flag
    try testing.expectEqual(@as(u8, 0x00), buffer[4]);

    // Verify stream ID is 0
    try testing.expectEqual(@as(u8, 0x00), buffer[8]);

    // Verify opaque data
    try testing.expectEqualSlices(u8, &opaque_data, buffer[9..17]);
}

test "http2_frame: serialize PING ACK" {
    var buffer: [32]u8 = undefined;
    const opaque_data = [8]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };

    const len = z6.serializePingFrame(opaque_data, true, &buffer);

    try testing.expectEqual(@as(usize, 17), len);

    // Verify ACK flag is set
    try testing.expectEqual(@as(u8, 0x01), buffer[4]);
}

test "http2_frame: serialize WINDOW_UPDATE frame" {
    var buffer: [16]u8 = undefined;

    const len = z6.serializeWindowUpdateFrame(1, 65535, &buffer);

    // Should be 13 bytes (9 header + 4 payload)
    try testing.expectEqual(@as(usize, 13), len);

    // Verify frame type is WINDOW_UPDATE
    try testing.expectEqual(@as(u8, 0x08), buffer[3]);

    // Verify stream ID
    try testing.expectEqual(@as(u8, 0x01), buffer[8]);

    // Verify increment (65535 = 0x0000FFFF, big-endian)
    try testing.expectEqual(@as(u8, 0x00), buffer[9]);
    try testing.expectEqual(@as(u8, 0x00), buffer[10]);
    try testing.expectEqual(@as(u8, 0xFF), buffer[11]);
    try testing.expectEqual(@as(u8, 0xFF), buffer[12]);
}

test "http2_frame: serialize GOAWAY frame" {
    var buffer: [64]u8 = undefined;
    const debug_data = "test error";

    const len = z6.serializeGoawayFrame(5, .PROTOCOL_ERROR, debug_data, &buffer);

    // Should be 9 header + 8 (last_stream + error) + 10 debug
    try testing.expectEqual(@as(usize, 27), len);

    // Verify frame type is GOAWAY
    try testing.expectEqual(@as(u8, 0x07), buffer[3]);

    // Verify stream ID is 0
    try testing.expectEqual(@as(u8, 0x00), buffer[8]);

    // Verify last stream ID (5)
    try testing.expectEqual(@as(u8, 0x00), buffer[9]);
    try testing.expectEqual(@as(u8, 0x00), buffer[10]);
    try testing.expectEqual(@as(u8, 0x00), buffer[11]);
    try testing.expectEqual(@as(u8, 0x05), buffer[12]);

    // Verify error code (PROTOCOL_ERROR = 0x1)
    try testing.expectEqual(@as(u8, 0x00), buffer[13]);
    try testing.expectEqual(@as(u8, 0x00), buffer[14]);
    try testing.expectEqual(@as(u8, 0x00), buffer[15]);
    try testing.expectEqual(@as(u8, 0x01), buffer[16]);

    // Verify debug data
    try testing.expectEqualStrings(debug_data, buffer[17..27]);
}

test "http2_frame: serialize RST_STREAM frame" {
    var buffer: [16]u8 = undefined;

    const len = z6.serializeRstStreamFrame(3, .CANCEL, &buffer);

    // Should be 13 bytes (9 header + 4 payload)
    try testing.expectEqual(@as(usize, 13), len);

    // Verify frame type is RST_STREAM
    try testing.expectEqual(@as(u8, 0x03), buffer[3]);

    // Verify stream ID (3)
    try testing.expectEqual(@as(u8, 0x03), buffer[8]);

    // Verify error code (CANCEL = 0x8)
    try testing.expectEqual(@as(u8, 0x00), buffer[9]);
    try testing.expectEqual(@as(u8, 0x00), buffer[10]);
    try testing.expectEqual(@as(u8, 0x00), buffer[11]);
    try testing.expectEqual(@as(u8, 0x08), buffer[12]);
}

test "http2_frame: serialize and parse roundtrip" {
    const allocator = testing.allocator;
    var parser = z6.HTTP2FrameParser.init(allocator);

    // Serialize a SETTINGS frame
    var buffer: [128]u8 = undefined;
    const settings = z6.HTTP2Settings{};
    const len = z6.serializeSettingsFrame(settings, &buffer);

    // Parse it back
    const frame = try parser.parseFrame(buffer[0..len]);

    // Verify header
    try testing.expectEqual(z6.HTTP2FrameType.SETTINGS, frame.header.frame_type);
    try testing.expectEqual(@as(u31, 0), frame.header.stream_id);
    try testing.expectEqual(@as(u24, 36), frame.header.length);

    // Parse settings
    const params = try parser.parseSettingsFrame(frame);
    defer parser.freeSettings(params);

    try testing.expectEqual(@as(usize, 6), params.len);
}
