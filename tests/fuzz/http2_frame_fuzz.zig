//! HTTP/2 Frame Parser Fuzz Tests
//!
//! Fuzz testing with 1M+ random inputs to verify robustness.
//! Following Tiger Style: Test edge cases and random inputs.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const HTTP2FrameParser = z6.HTTP2FrameParser;
const FrameType = z6.HTTP2FrameType;

// =============================================================================
// Fuzz Tests
// =============================================================================

test "fuzz: http2 frame parser 1M+ random byte sequences" {
    // PRNG with deterministic seed for reproducibility
    var prng = std.Random.DefaultPrng.init(0x22222222);
    const random = prng.random();

    var success_count: usize = 0;
    var error_count: usize = 0;

    // Run 1 million iterations
    const iterations: usize = 1_000_000;

    for (0..iterations) |i| {
        // Generate random bytes (varying sizes - frames need at least 9 bytes for header)
        const size = random.uintLessThan(usize, 256) + 1;
        var input: [256]u8 = undefined;
        random.bytes(input[0..size]);

        // Create parser
        var parser = HTTP2FrameParser.init(testing.allocator);

        // Try to parse header first (needs 9 bytes minimum)
        if (size >= 9) {
            if (parser.parseHeader(input[0..size])) |header| {
                success_count += 1;
                // Verify basic invariants
                try testing.expect(header.length <= z6.HTTP2_MAX_FRAME_SIZE);
            } else |_| {
                error_count += 1;
            }
        } else {
            // Too short for header
            _ = parser.parseHeader(input[0..size]) catch {
                error_count += 1;
            };
        }

        // Progress indicator every 100k iterations
        if (i > 0 and i % 100_000 == 0) {
            std.debug.print("HTTP/2 frame fuzz progress: {d}k/{d}k iterations\n", .{ i / 1000, iterations / 1000 });
        }
    }

    // Report results
    std.debug.print("\nHTTP/2 Frame Parser Fuzz Test Completed:\n", .{});
    std.debug.print("  Total: {d} iterations\n", .{iterations});
    std.debug.print("  Success: {d} ({d}%)\n", .{ success_count, success_count * 100 / iterations });
    std.debug.print("  Errors: {d} ({d}%)\n", .{ error_count, error_count * 100 / iterations });

    // Test passed - no crashes occurred
    try testing.expect(success_count + error_count == iterations);
}

test "fuzz: http2 frame with valid structure random payload" {
    var prng = std.Random.DefaultPrng.init(0x22222223);
    const random = prng.random();

    const iterations: usize = 100_000;

    for (0..iterations) |_| {
        var buf: [512]u8 = undefined;

        // Create valid frame header structure
        const payload_len = random.uintLessThan(u24, 256);

        // Length (3 bytes, big-endian)
        buf[0] = @intCast((payload_len >> 16) & 0xFF);
        buf[1] = @intCast((payload_len >> 8) & 0xFF);
        buf[2] = @intCast(payload_len & 0xFF);

        // Type (1 byte) - pick from valid frame types
        const frame_types = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
        buf[3] = frame_types[random.uintLessThan(usize, frame_types.len)];

        // Flags (1 byte)
        buf[4] = random.int(u8);

        // Stream ID (4 bytes, clear reserved bit)
        const stream_id = random.int(u32) & 0x7FFFFFFF;
        buf[5] = @intCast((stream_id >> 24) & 0xFF);
        buf[6] = @intCast((stream_id >> 16) & 0xFF);
        buf[7] = @intCast((stream_id >> 8) & 0xFF);
        buf[8] = @intCast(stream_id & 0xFF);

        // Random payload
        const actual_payload_len = @min(payload_len, buf.len - 9);
        random.bytes(buf[9..][0..actual_payload_len]);

        var parser = HTTP2FrameParser.init(testing.allocator);

        // Parse header
        if (parser.parseHeader(buf[0..9])) |header| {
            // If payload fits, try to parse full frame
            if (actual_payload_len >= header.length) {
                _ = parser.parseFrame(buf[0 .. 9 + header.length]) catch continue;
            }
        } else |_| {
            continue;
        }
    }
}

test "fuzz: http2 frame type specific parsing" {
    var prng = std.Random.DefaultPrng.init(0x22222224);
    const random = prng.random();

    const iterations: usize = 50_000;

    for (0..iterations) |_| {
        var parser = HTTP2FrameParser.init(testing.allocator);

        // Test SETTINGS frames (type=4, payload must be multiple of 6)
        {
            var buf: [64]u8 = undefined;
            const num_settings = random.uintLessThan(usize, 5);
            const payload_len: u24 = @intCast(num_settings * 6);

            // Header
            buf[0] = 0;
            buf[1] = 0;
            buf[2] = @intCast(payload_len);
            buf[3] = 4; // SETTINGS
            buf[4] = random.int(u8) & 0x01; // Only ACK flag is valid
            buf[5] = 0;
            buf[6] = 0;
            buf[7] = 0;
            buf[8] = 0; // Stream 0 for SETTINGS

            // Settings payload
            random.bytes(buf[9..][0..payload_len]);

            if (parser.parseFrame(buf[0 .. 9 + payload_len])) |frame| {
                if (parser.parseSettingsFrame(frame)) |params| {
                    testing.allocator.free(params);
                } else |_| {}
            } else |_| {
                continue;
            }
        }

        // Test PING frames (type=6, payload must be exactly 8 bytes)
        {
            var buf: [17]u8 = undefined;

            // Header for PING
            buf[0] = 0;
            buf[1] = 0;
            buf[2] = 8; // PING payload is always 8 bytes
            buf[3] = 6; // PING type
            buf[4] = random.int(u8) & 0x01; // Only ACK flag
            buf[5] = 0;
            buf[6] = 0;
            buf[7] = 0;
            buf[8] = 0; // Stream 0

            // Random 8-byte opaque data
            random.bytes(buf[9..17]);

            if (parser.parseFrame(&buf)) |frame| {
                _ = parser.parsePingFrame(frame) catch continue;
            } else |_| {
                continue;
            }
        }

        // Test WINDOW_UPDATE frames (type=8, payload is 4 bytes)
        {
            var buf: [13]u8 = undefined;

            buf[0] = 0;
            buf[1] = 0;
            buf[2] = 4;
            buf[3] = 8; // WINDOW_UPDATE
            buf[4] = 0;
            const stream_id = random.int(u32) & 0x7FFFFFFF;
            buf[5] = @intCast((stream_id >> 24) & 0xFF);
            buf[6] = @intCast((stream_id >> 16) & 0xFF);
            buf[7] = @intCast((stream_id >> 8) & 0xFF);
            buf[8] = @intCast(stream_id & 0xFF);

            // Window increment (4 bytes)
            random.bytes(buf[9..13]);

            if (parser.parseFrame(&buf)) |frame| {
                _ = parser.parseWindowUpdateFrame(frame) catch continue;
            } else |_| {
                continue;
            }
        }
    }
}

test "fuzz: http2 frame corpus seeds" {
    var parser = HTTP2FrameParser.init(testing.allocator);

    // Valid SETTINGS empty
    const settings_empty = [_]u8{ 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00 };
    if (parser.parseHeader(&settings_empty)) |header| {
        try testing.expectEqual(FrameType.SETTINGS, header.frame_type);
        try testing.expectEqual(@as(u24, 0), header.length);
    } else |_| {}

    // SETTINGS ACK
    const settings_ack = [_]u8{ 0x00, 0x00, 0x00, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00 };
    if (parser.parseHeader(&settings_ack)) |header| {
        try testing.expectEqual(FrameType.SETTINGS, header.frame_type);
        try testing.expectEqual(@as(u8, 0x01), header.flags);
    } else |_| {}

    // DATA frame
    const data_frame = [_]u8{ 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 'h', 'e', 'l', 'l', 'o' };
    if (parser.parseHeader(&data_frame)) |header| {
        try testing.expectEqual(FrameType.DATA, header.frame_type);
        try testing.expectEqual(@as(u24, 5), header.length);
    } else |_| {}

    // Invalid seeds - should not crash
    const invalid_seeds = [_][]const u8{
        &[_]u8{}, // Empty
        &[_]u8{0x00}, // Too short
        &[_]u8{ 0x00, 0x00 }, // Still too short
        &[_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF }, // Max values
    };

    for (invalid_seeds) |seed| {
        _ = parser.parseHeader(seed) catch continue;
    }
}

test "fuzz: http2 frame boundary conditions" {
    var prng = std.Random.DefaultPrng.init(0x22222225);
    const random = prng.random();

    var parser = HTTP2FrameParser.init(testing.allocator);

    // Test boundary sizes around frame header (9 bytes)
    const sizes = [_]usize{ 0, 1, 7, 8, 9, 10, 15, 16, 17 };

    for (sizes) |size| {
        if (size == 0) continue;
        var buf: [32]u8 = undefined;
        random.bytes(buf[0..size]);
        _ = parser.parseHeader(buf[0..size]) catch continue;
    }
}
