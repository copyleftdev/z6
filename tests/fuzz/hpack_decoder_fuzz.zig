//! HPACK Decoder Fuzz Tests
//!
//! Fuzz testing with 1M+ random inputs to verify robustness.
//! Following Tiger Style: Test edge cases and random inputs.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const HPACKDecoder = z6.HPACKDecoder;
const HPACKHeader = z6.HPACKHeader;

// =============================================================================
// Fuzz Tests
// =============================================================================

test "fuzz: hpack decoder 1M+ random byte sequences" {
    // PRNG with deterministic seed for reproducibility
    var prng = std.Random.DefaultPrng.init(0x33333111);
    const random = prng.random();

    var success_count: usize = 0;
    var error_count: usize = 0;

    // Run 1 million iterations
    const iterations: usize = 1_000_000;

    for (0..iterations) |i| {
        // Generate random bytes (varying sizes up to 256 bytes)
        const size = random.uintLessThan(usize, 256) + 1;
        var input: [256]u8 = undefined;
        random.bytes(input[0..size]);

        // Headers buffer
        var headers: [100]HPACKHeader = undefined;

        // Try to decode - should handle gracefully (no crash)
        if (HPACKDecoder.decode(input[0..size], &headers)) |count| {
            success_count += 1;
            // Verify basic invariants
            try testing.expect(count <= 100);
        } else |_| {
            error_count += 1;
        }

        // Progress indicator every 100k iterations
        if (i > 0 and i % 100_000 == 0) {
            std.debug.print("HPACK fuzz progress: {d}k/{d}k iterations\n", .{ i / 1000, iterations / 1000 });
        }
    }

    // Report results
    std.debug.print("\nHPACK Decoder Fuzz Test Completed:\n", .{});
    std.debug.print("  Total: {d} iterations\n", .{iterations});
    std.debug.print("  Success: {d} ({d}%)\n", .{ success_count, success_count * 100 / iterations });
    std.debug.print("  Errors: {d} ({d}%)\n", .{ error_count, error_count * 100 / iterations });

    // Test passed - no crashes occurred
    try testing.expect(success_count + error_count == iterations);
}

test "fuzz: hpack decoder with indexed headers" {
    var prng = std.Random.DefaultPrng.init(0x33333112);
    const random = prng.random();

    const iterations: usize = 100_000;

    for (0..iterations) |_| {
        var buf: [64]u8 = undefined;
        var pos: usize = 0;

        // Generate sequence of indexed headers (0x80 | index)
        const num_headers = random.uintLessThan(usize, 10) + 1;
        for (0..num_headers) |_| {
            if (pos >= buf.len) break;
            // Indexed header: 1xxxxxxx
            // Valid indices are 1-61 (static table)
            const index = random.uintLessThan(u8, 62);
            buf[pos] = 0x80 | index;
            pos += 1;
        }

        var headers: [100]HPACKHeader = undefined;
        _ = HPACKDecoder.decode(buf[0..pos], &headers) catch continue;
    }
}

test "fuzz: hpack decoder with literal headers" {
    var prng = std.Random.DefaultPrng.init(0x33333113);
    const random = prng.random();

    const iterations: usize = 100_000;

    for (0..iterations) |_| {
        var buf: [256]u8 = undefined;
        var pos: usize = 0;

        // Generate literal header without indexing (0000xxxx)
        // Format: 0x00 | name_index, then value length + value
        // Or: 0x00, name_length + name, value_length + value

        // Random literal type
        const literal_type = random.uintLessThan(u8, 3);

        switch (literal_type) {
            0 => {
                // Literal with indexed name
                const name_idx = random.uintLessThan(u8, 16);
                buf[pos] = name_idx; // 0000xxxx
                pos += 1;

                // Value length and value
                const val_len = random.uintLessThan(u8, 20);
                buf[pos] = val_len;
                pos += 1;
                for (0..val_len) |j| {
                    if (pos + j >= buf.len) break;
                    buf[pos + j] = @intCast(random.intRangeAtMost(u8, 32, 126));
                }
                pos += val_len;
            },
            1 => {
                // Literal with literal name
                buf[pos] = 0x00;
                pos += 1;

                // Name length and name
                const name_len = random.uintLessThan(u8, 15) + 1;
                buf[pos] = name_len;
                pos += 1;
                for (0..name_len) |j| {
                    if (pos + j >= buf.len) break;
                    buf[pos + j] = @intCast(random.intRangeAtMost(u8, 97, 122)); // lowercase letters
                }
                pos += name_len;

                // Value length and value
                const val_len = random.uintLessThan(u8, 20);
                if (pos < buf.len) {
                    buf[pos] = val_len;
                    pos += 1;
                }
                for (0..val_len) |j| {
                    if (pos + j >= buf.len) break;
                    buf[pos + j] = @intCast(random.intRangeAtMost(u8, 32, 126));
                }
                pos += @min(val_len, buf.len - pos);
            },
            else => {
                // Random bytes
                const len = random.uintLessThan(usize, 30);
                random.bytes(buf[0..len]);
                pos = len;
            },
        }

        if (pos > 0) {
            var headers: [100]HPACKHeader = undefined;
            _ = HPACKDecoder.decode(buf[0..pos], &headers) catch continue;
        }
    }
}

test "fuzz: hpack decoder corpus seeds" {
    var headers: [100]HPACKHeader = undefined;

    // Indexed header - :method GET (index 2)
    const indexed_get = [_]u8{0x82};
    if (HPACKDecoder.decode(&indexed_get, &headers)) |count| {
        try testing.expectEqual(@as(usize, 1), count);
    } else |_| {}

    // Multiple indexed headers
    const indexed_multi = [_]u8{ 0x82, 0x84, 0x86 }; // GET, /, http
    if (HPACKDecoder.decode(&indexed_multi, &headers)) |count| {
        try testing.expect(count > 0);
    } else |_| {}

    // Invalid seeds - should not crash
    const invalid_seeds = [_][]const u8{
        &[_]u8{0xFF}, // Invalid index
        &[_]u8{ 0x00, 0xFF }, // String too long
        &[_]u8{0x00}, // Truncated literal
        &[_]u8{ 0x00, 0x05, 'a', 'b' }, // Truncated name
    };

    for (invalid_seeds) |seed| {
        _ = HPACKDecoder.decode(seed, &headers) catch continue;
    }
}

test "fuzz: hpack decoder boundary conditions" {
    var prng = std.Random.DefaultPrng.init(0x33333114);
    const random = prng.random();

    var headers: [100]HPACKHeader = undefined;

    // Test boundary sizes
    const sizes = [_]usize{ 1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129 };

    for (sizes) |size| {
        var buf: [256]u8 = undefined;
        random.bytes(buf[0..size]);
        _ = HPACKDecoder.decode(buf[0..size], &headers) catch continue;
    }
}

test "fuzz: hpack decoder string length variations" {
    var prng = std.Random.DefaultPrng.init(0x33333115);
    const random = prng.random();

    const iterations: usize = 50_000;

    for (0..iterations) |_| {
        var buf: [512]u8 = undefined;

        // Create literal header with varying string lengths
        buf[0] = 0x00; // Literal without indexing

        // Name with various length encodings
        const name_len = random.uintLessThan(u8, 200);
        if (name_len < 127) {
            buf[1] = name_len;
            // Fill name
            for (0..@min(name_len, 128)) |j| {
                buf[2 + j] = 'x';
            }
        } else {
            // Multi-byte length (not fully implemented in decoder)
            buf[1] = 0x7F;
            buf[2] = name_len - 127;
        }

        var headers: [100]HPACKHeader = undefined;
        _ = HPACKDecoder.decode(buf[0..@min(buf.len, name_len + 10)], &headers) catch continue;
    }
}
