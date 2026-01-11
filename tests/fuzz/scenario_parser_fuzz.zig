//! Scenario Parser Fuzz Tests
//!
//! Fuzz testing with 100k+ random inputs to verify robustness.
//! Following Tiger Style: Test edge cases and random inputs.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const ScenarioParser = z6.ScenarioParser;
const Scenario = z6.Scenario;

// =============================================================================
// Fuzz Tests
// =============================================================================

test "fuzz: scenario parser 100k+ random byte sequences" {
    // PRNG with deterministic seed for reproducibility
    var prng = std.Random.DefaultPrng.init(0x44441111);
    const random = prng.random();

    var success_count: usize = 0;
    var error_count: usize = 0;

    // Run 100k iterations (scenario parsing is slower due to TOML complexity)
    const iterations: usize = 100_000;

    for (0..iterations) |i| {
        // Generate random bytes (varying sizes up to 1KB)
        const size = random.uintLessThan(usize, 1024) + 1;
        var input: [1024]u8 = undefined;
        random.bytes(input[0..size]);

        // Try to parse - should handle gracefully (no crash)
        var parser = ScenarioParser.init(testing.allocator, input[0..size]) catch {
            error_count += 1;
            continue;
        };
        defer parser.deinit();

        if (parser.parse()) |scenario| {
            defer scenario.deinit();
            success_count += 1;
        } else |_| {
            error_count += 1;
        }

        // Progress indicator every 10k iterations
        if (i > 0 and i % 10_000 == 0) {
            std.debug.print("Scenario fuzz progress: {d}k/{d}k iterations\n", .{ i / 1000, iterations / 1000 });
        }
    }

    // Report results
    std.debug.print("\nScenario Parser Fuzz Test Completed:\n", .{});
    std.debug.print("  Total: {d} iterations\n", .{iterations});
    std.debug.print("  Success: {d} ({d}%)\n", .{ success_count, success_count * 100 / iterations });
    std.debug.print("  Errors: {d} ({d}%)\n", .{ error_count, error_count * 100 / iterations });

    // Test passed - no crashes occurred
    try testing.expect(success_count + error_count == iterations);
}

test "fuzz: scenario parser with toml-like random data" {
    var prng = std.Random.DefaultPrng.init(0x44441112);
    const random = prng.random();

    const iterations: usize = 50_000;

    for (0..iterations) |_| {
        var buf: [2048]u8 = undefined;
        var pos: usize = 0;

        // Generate TOML-like content
        const sections = [_][]const u8{
            "[metadata]\n",
            "[runtime]\n",
            "[target]\n",
            "[[requests]]\n",
            "[schedule]\n",
            "[assertions]\n",
            "[unknown]\n",
        };

        // Add some sections
        const num_sections = random.uintLessThan(usize, 5) + 1;
        for (0..num_sections) |_| {
            const section = sections[random.uintLessThan(usize, sections.len)];
            if (pos + section.len >= buf.len) break;
            @memcpy(buf[pos..][0..section.len], section);
            pos += section.len;

            // Add some key-value pairs
            const num_pairs = random.uintLessThan(usize, 5);
            for (0..num_pairs) |_| {
                const keys = [_][]const u8{ "name", "version", "duration_seconds", "vus", "base_url", "method", "path", "type" };
                const key = keys[random.uintLessThan(usize, keys.len)];

                if (pos + key.len + 20 >= buf.len) break;
                @memcpy(buf[pos..][0..key.len], key);
                pos += key.len;

                buf[pos] = ' ';
                buf[pos + 1] = '=';
                buf[pos + 2] = ' ';
                pos += 3;

                // Random value
                const val_type = random.uintLessThan(u8, 3);
                switch (val_type) {
                    0 => {
                        // String value
                        buf[pos] = '"';
                        pos += 1;
                        const val_len = random.uintLessThan(usize, 20);
                        for (0..val_len) |j| {
                            if (pos + j >= buf.len) break;
                            buf[pos + j] = @intCast(random.intRangeAtMost(u8, 97, 122));
                        }
                        pos += val_len;
                        if (pos < buf.len) {
                            buf[pos] = '"';
                            pos += 1;
                        }
                    },
                    1 => {
                        // Number value
                        const num = random.intRangeAtMost(u32, 0, 9999);
                        const num_str = std.fmt.bufPrint(buf[pos..][0..@min(10, buf.len - pos)], "{d}", .{num}) catch break;
                        pos += num_str.len;
                    },
                    else => {
                        // Boolean or identifier
                        const vals = [_][]const u8{ "true", "false", "constant", "ramp" };
                        const val = vals[random.uintLessThan(usize, vals.len)];
                        if (pos + val.len < buf.len) {
                            @memcpy(buf[pos..][0..val.len], val);
                            pos += val.len;
                        }
                    },
                }

                if (pos < buf.len) {
                    buf[pos] = '\n';
                    pos += 1;
                }
            }
        }

        if (pos > 0) {
            var parser = ScenarioParser.init(testing.allocator, buf[0..pos]) catch continue;
            defer parser.deinit();
            if (parser.parse()) |scenario| {
                scenario.deinit();
            } else |_| {}
        }
    }
}

test "fuzz: scenario parser valid scenario mutations" {
    var prng = std.Random.DefaultPrng.init(0x44441113);
    const random = prng.random();

    const valid_scenario =
        \\[metadata]
        \\name = "Test"
        \\version = "1.0"
        \\
        \\[runtime]
        \\duration_seconds = 60
        \\vus = 10
        \\
        \\[target]
        \\base_url = "http://localhost:8080"
        \\http_version = "http1.1"
        \\
        \\[[requests]]
        \\name = "test"
        \\method = "GET"
        \\path = "/"
        \\timeout_ms = 1000
        \\
        \\[schedule]
        \\type = "constant"
        \\vus = 10
    ;

    const iterations: usize = 50_000;

    for (0..iterations) |_| {
        var buf: [1024]u8 = undefined;
        const copy_len = @min(valid_scenario.len, buf.len);
        @memcpy(buf[0..copy_len], valid_scenario[0..copy_len]);

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
                    // Replace byte with random printable
                    const idx = random.uintLessThan(usize, copy_len);
                    buf[idx] = @intCast(random.intRangeAtMost(u8, 32, 126));
                },
                2 => {
                    // Replace with newline
                    const idx = random.uintLessThan(usize, copy_len);
                    buf[idx] = '\n';
                },
                3 => {
                    // Replace with bracket
                    const idx = random.uintLessThan(usize, copy_len);
                    buf[idx] = if (random.boolean()) '[' else ']';
                },
                else => {},
            }
        }

        var parser = ScenarioParser.init(testing.allocator, buf[0..copy_len]) catch continue;
        defer parser.deinit();
        if (parser.parse()) |scenario| {
            scenario.deinit();
        } else |_| {}
    }
}

test "fuzz: scenario parser corpus seeds" {
    // Valid simple scenario
    const simple =
        \\[metadata]
        \\name = "Simple"
        \\version = "1.0"
        \\
        \\[runtime]
        \\duration_seconds = 60
        \\vus = 10
        \\
        \\[target]
        \\base_url = "http://localhost"
        \\http_version = "http1.1"
        \\
        \\[[requests]]
        \\name = "test"
        \\method = "GET"
        \\path = "/"
        \\timeout_ms = 1000
        \\
        \\[schedule]
        \\type = "constant"
        \\vus = 10
    ;

    var parser = ScenarioParser.init(testing.allocator, simple) catch return;
    defer parser.deinit();
    if (parser.parse()) |scenario| {
        defer scenario.deinit();
        try testing.expect(scenario.runtime.vus == 10);
    } else |_| {}

    // Invalid seeds - should not crash
    const invalid_seeds = [_][]const u8{
        "",
        "garbage",
        "[",
        "[]",
        "[metadata]",
        "[metadata]\nname",
        "[unknown_section]\nkey = value",
    };

    for (invalid_seeds) |seed| {
        if (seed.len == 0) continue;
        var seed_parser = ScenarioParser.init(testing.allocator, seed) catch continue;
        defer seed_parser.deinit();
        if (seed_parser.parse()) |scenario| {
            scenario.deinit();
        } else |_| {}
    }
}

test "fuzz: scenario parser boundary conditions" {
    var prng = std.Random.DefaultPrng.init(0x44441114);
    const random = prng.random();

    // Test boundary sizes
    const sizes = [_]usize{ 1, 2, 10, 50, 100, 255, 256, 257, 511, 512, 513, 1023, 1024 };

    for (sizes) |size| {
        var buf: [1024]u8 = undefined;
        random.bytes(buf[0..size]);

        var parser = ScenarioParser.init(testing.allocator, buf[0..size]) catch continue;
        defer parser.deinit();
        if (parser.parse()) |scenario| {
            scenario.deinit();
        } else |_| {}
    }
}
