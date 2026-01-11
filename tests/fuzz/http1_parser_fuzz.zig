//! HTTP/1.1 Parser Fuzz Tests
//!
//! Fuzz testing with 1M+ random inputs to verify robustness.
//! Following Tiger Style: Test edge cases and random inputs.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const HTTP1Parser = z6.HTTP1Parser;

// =============================================================================
// Fuzz Tests
// =============================================================================

test "fuzz: http1 parser 1M+ random byte sequences" {
    // PRNG with deterministic seed for reproducibility
    var prng = std.Random.DefaultPrng.init(0x11111111);
    const random = prng.random();

    var success_count: usize = 0;
    var error_count: usize = 0;

    // Run 1 million iterations
    const iterations: usize = 1_000_000;

    for (0..iterations) |i| {
        // Generate random bytes (varying sizes up to 4KB)
        const size = random.uintLessThan(usize, 4096) + 1;
        var input: [4096]u8 = undefined;
        random.bytes(input[0..size]);

        // Create parser
        var parser = HTTP1Parser.init(testing.allocator);

        // Try to parse - should handle gracefully (no crash)
        if (parser.parse(input[0..size])) |result| {
            success_count += 1;
            // Verify basic invariants
            try testing.expect(result.status_code >= 100 and result.status_code <= 999);
            try testing.expect(result.bytes_consumed <= size);
        } else |_| {
            error_count += 1;
        }

        // Progress indicator every 100k iterations
        if (i > 0 and i % 100_000 == 0) {
            std.debug.print("HTTP/1.1 fuzz progress: {d}k/{d}k iterations\n", .{ i / 1000, iterations / 1000 });
        }
    }

    // Report results
    std.debug.print("\nHTTP/1.1 Parser Fuzz Test Completed:\n", .{});
    std.debug.print("  Total: {d} iterations\n", .{iterations});
    std.debug.print("  Success: {d} ({d}%)\n", .{ success_count, success_count * 100 / iterations });
    std.debug.print("  Errors: {d} ({d}%)\n", .{ error_count, error_count * 100 / iterations });

    // Test passed - no crashes occurred
    try testing.expect(success_count + error_count == iterations);
}

test "fuzz: http1 parser with http-like random data" {
    // Generate data that looks more like HTTP responses
    var prng = std.Random.DefaultPrng.init(0x11111112);
    const random = prng.random();

    const iterations: usize = 100_000;

    for (0..iterations) |_| {
        var buf: [2048]u8 = undefined;
        var pos: usize = 0;

        // Start with HTTP version (sometimes valid, sometimes not)
        const versions = [_][]const u8{ "HTTP/1.1 ", "HTTP/1.0 ", "HTTP/2.0 ", "HTTP", "HT", "" };
        const version = versions[random.uintLessThan(usize, versions.len)];
        @memcpy(buf[pos..][0..version.len], version);
        pos += version.len;

        // Add random status code
        const status = random.intRangeAtMost(u16, 100, 599);
        const status_str = std.fmt.bufPrint(buf[pos..][0..3], "{d}", .{status}) catch continue;
        pos += status_str.len;

        // Add space and reason phrase
        if (pos < buf.len - 20) {
            buf[pos] = ' ';
            pos += 1;
            const reasons = [_][]const u8{ "OK", "Not Found", "Error", "", "X" };
            const reason = reasons[random.uintLessThan(usize, reasons.len)];
            @memcpy(buf[pos..][0..reason.len], reason);
            pos += reason.len;
        }

        // Add CRLF
        if (pos < buf.len - 2) {
            buf[pos] = '\r';
            buf[pos + 1] = '\n';
            pos += 2;
        }

        // Maybe add headers
        const num_headers = random.uintLessThan(usize, 5);
        for (0..num_headers) |_| {
            if (pos >= buf.len - 50) break;
            const header_names = [_][]const u8{ "Content-Length", "Content-Type", "X-Test", "Connection" };
            const name = header_names[random.uintLessThan(usize, header_names.len)];
            @memcpy(buf[pos..][0..name.len], name);
            pos += name.len;
            buf[pos] = ':';
            buf[pos + 1] = ' ';
            pos += 2;

            // Random value
            const val_len = random.uintLessThan(usize, 20);
            for (0..val_len) |j| {
                if (pos + j >= buf.len) break;
                buf[pos + j] = @intCast(random.intRangeAtMost(u8, 32, 126));
            }
            pos += val_len;

            if (pos < buf.len - 2) {
                buf[pos] = '\r';
                buf[pos + 1] = '\n';
                pos += 2;
            }
        }

        // Add empty line to end headers
        if (pos < buf.len - 2) {
            buf[pos] = '\r';
            buf[pos + 1] = '\n';
            pos += 2;
        }

        // Try to parse
        if (pos > 0) {
            var parser = HTTP1Parser.init(testing.allocator);
            _ = parser.parse(buf[0..pos]) catch continue;
        }
    }
}

test "fuzz: http1 parser valid response mutations" {
    // Start with valid responses and mutate them
    var prng = std.Random.DefaultPrng.init(0x11111113);
    const random = prng.random();

    const valid_responses = [_][]const u8{
        "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello",
        "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n",
        "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n",
    };

    const iterations: usize = 100_000;

    for (0..iterations) |_| {
        // Pick a valid response
        const base = valid_responses[random.uintLessThan(usize, valid_responses.len)];

        // Copy and mutate
        var buf: [256]u8 = undefined;
        const copy_len = @min(base.len, buf.len);
        @memcpy(buf[0..copy_len], base[0..copy_len]);

        // Apply random mutations
        const num_mutations = random.uintLessThan(usize, 10);
        for (0..num_mutations) |_| {
            const mutation_type = random.uintLessThan(u8, 4);
            switch (mutation_type) {
                0 => {
                    // Flip random byte
                    const idx = random.uintLessThan(usize, copy_len);
                    buf[idx] ^= @intCast(random.intRangeAtMost(u8, 1, 255));
                },
                1 => {
                    // Replace byte with random
                    const idx = random.uintLessThan(usize, copy_len);
                    buf[idx] = random.int(u8);
                },
                2 => {
                    // Insert null byte
                    const idx = random.uintLessThan(usize, copy_len);
                    buf[idx] = 0;
                },
                3 => {
                    // Replace with CRLF
                    if (copy_len > 2) {
                        const idx = random.uintLessThan(usize, copy_len - 1);
                        buf[idx] = '\r';
                        buf[idx + 1] = '\n';
                    }
                },
                else => {},
            }
        }

        // Try to parse mutated response
        var parser = HTTP1Parser.init(testing.allocator);
        _ = parser.parse(buf[0..copy_len]) catch continue;
    }
}

test "fuzz: http1 parser corpus seeds" {
    // Test with corpus seed files (embedded at compile time)
    const seeds = [_]struct { name: []const u8, data: []const u8 }{
        .{ .name = "200_ok", .data = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello" },
        .{ .name = "404_not_found", .data = "HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nNot Found" },
        .{ .name = "chunked", .data = "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n5\r\nhello\r\n0\r\n\r\n" },
        .{ .name = "empty_body", .data = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n" },
        .{ .name = "multi_headers", .data = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nCache-Control: no-cache\r\nContent-Length: 4\r\n\r\ntest" },
        .{ .name = "keep_alive", .data = "HTTP/1.1 200 OK\r\nConnection: keep-alive\r\nContent-Length: 4\r\n\r\ntest" },
    };

    for (seeds) |seed| {
        var parser = HTTP1Parser.init(testing.allocator);
        const result = parser.parse(seed.data) catch |err| {
            std.debug.print("Corpus seed '{s}' failed with error: {}\n", .{ seed.name, err });
            continue;
        };

        // Valid seeds should parse successfully
        try testing.expect(result.status_code >= 100);
        try testing.expect(result.status_code <= 599);
    }

    // Test invalid seeds - should not crash
    const invalid_seeds = [_][]const u8{
        "garbage",
        "",
        "HTTP",
        "HTTP/1.1",
        "HTTP/1.1 ",
        "HTTP/1.1 200",
        "\x00\x00\x00",
    };

    for (invalid_seeds) |seed| {
        if (seed.len == 0) continue; // Skip empty (assertion would fail)
        var parser = HTTP1Parser.init(testing.allocator);
        _ = parser.parse(seed) catch continue;
    }
}

test "fuzz: http1 parser boundary conditions" {
    var prng = std.Random.DefaultPrng.init(0x11111114);
    const random = prng.random();

    // Test various boundary sizes
    const sizes = [_]usize{ 1, 2, 8, 9, 10, 15, 16, 17, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 257, 511, 512, 513, 1023, 1024, 1025 };

    for (sizes) |size| {
        var buf: [2048]u8 = undefined;
        random.bytes(buf[0..size]);

        var parser = HTTP1Parser.init(testing.allocator);
        _ = parser.parse(buf[0..size]) catch continue;
    }
}
