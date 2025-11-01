//! Event Serialization Fuzz Tests
//!
//! Fuzz testing with 1M+ random inputs to verify robustness.
//! Following Tiger Style: Test edge cases and random inputs.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const Event = z6.Event;
const EventType = z6.EventType;

test "fuzz: deserialize 1M+ random byte sequences" {
    // PRNG with deterministic seed for reproducibility
    var prng = std.Random.DefaultPrng.init(0xDEADBEEF);
    const random = prng.random();

    var success_count: usize = 0;
    var error_count: usize = 0;

    // Run 1 million+ iterations as required by acceptance criteria
    // Note: Can be increased for more thorough testing
    const iterations: usize = 1_000_000;

    for (0..iterations) |i| {
        // Generate random bytes for event
        var bytes: [272]u8 = undefined;
        random.bytes(&bytes);

        // Try to deserialize - should handle gracefully
        if (Event.deserialize(&bytes)) |event| {
            // Deserialization succeeded
            success_count += 1;

            // Verify basic invariants
            try testing.expect(event.payload.len == 240);
            try testing.expect(@sizeOf(@TypeOf(event.checksum)) == 8);
        } else |err| {
            // Error is expected for random data
            error_count += 1;
            try testing.expect(err == error.InsufficientData);
        }

        // Progress indicator every 100k iterations
        if (i > 0 and i % 100_000 == 0) {
            std.debug.print("Fuzz progress: {}/{}k iterations\n", .{ i / 1000, iterations / 1000 });
        }
    }

    // Report results
    std.debug.print("\nFuzz test completed:\n", .{});
    std.debug.print("  Total: {} iterations\n", .{iterations});
    std.debug.print("  Success: {} ({}%)\n", .{ success_count, success_count * 100 / iterations });
    std.debug.print("  Errors: {} ({}%)\n", .{ error_count, error_count * 100 / iterations });

    // Test passes - no crashes occurred
    try testing.expect(success_count + error_count == iterations);
}

test "fuzz: serialize-deserialize round-trip with random events" {
    var prng = std.Random.DefaultPrng.init(0xCAFEBABE);
    const random = prng.random();

    const iterations: usize = 100_000;

    for (0..iterations) |_| {
        // Create random but valid event
        var payload: [240]u8 = undefined;
        random.bytes(&payload);

        // Pick a random valid event type
        const event_types = [_]EventType{
            .vu_spawned,
            .vu_ready,
            .vu_complete,
            .request_issued,
            .request_timeout,
            .request_cancelled,
            .response_received,
            .response_error,
            .conn_established,
            .conn_closed,
            .conn_error,
            .scheduler_tick,
            .assertion_passed,
            .assertion_failed,
            .error_dns,
            .error_tcp,
            .error_tls,
            .error_http,
            .error_timeout,
            .error_protocol_violation,
            .error_resource_exhausted,
        };

        const event = Event{
            .header = .{
                .tick = random.int(u64),
                .vu_id = random.int(u32),
                .event_type = event_types[random.uintLessThan(usize, event_types.len)],
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = payload,
            .checksum = 0,
        };

        // Serialize
        var buffer: [272]u8 = undefined;
        const serialized = Event.serialize(&event, &buffer);

        // Deserialize
        const deserialized = try Event.deserialize(serialized);

        // Verify round-trip
        try testing.expectEqual(event.header.tick, deserialized.header.tick);
        try testing.expectEqual(event.header.vu_id, deserialized.header.vu_id);
        try testing.expectEqual(event.header.event_type, deserialized.header.event_type);

        // Verify payload
        for (event.payload, 0..) |byte, i| {
            try testing.expectEqual(byte, deserialized.payload[i]);
        }
    }
}

test "fuzz: checksum with random data patterns" {
    var prng = std.Random.DefaultPrng.init(0xFEEDFACE);
    const random = prng.random();

    const iterations: usize = 50_000;

    for (0..iterations) |_| {
        // Create event with random data
        var payload: [240]u8 = undefined;
        random.bytes(&payload);

        var event = Event{
            .header = .{
                .tick = random.int(u64),
                .vu_id = random.int(u32),
                .event_type = .request_issued,
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = payload,
            .checksum = 0,
        };

        // Calculate checksum
        const checksum = Event.calculateChecksum(&event);
        event.checksum = checksum;

        // Should validate
        try testing.expect(Event.validateChecksum(&event));

        // Corrupt one random byte in payload
        const corrupt_idx = random.uintLessThan(usize, 240);
        event.payload[corrupt_idx] ^= 0xFF;

        // Should detect corruption
        try testing.expect(!Event.validateChecksum(&event));
    }
}

test "fuzz: event log with random operations" {
    const allocator = testing.allocator;
    var log = try z6.EventLog.init(allocator, 1000);
    defer log.deinit();

    var prng = std.Random.DefaultPrng.init(0xBAADF00D);
    const random = prng.random();

    const iterations: usize = 10_000;

    for (0..iterations) |i| {
        // Random operation
        const op = random.uintLessThan(u8, 3);

        switch (op) {
            0 => {
                // Append random event
                if (!log.isFull()) {
                    var payload: [240]u8 = undefined;
                    random.bytes(&payload);

                    const event = Event{
                        .header = .{
                            .tick = @intCast(i),
                            .vu_id = random.int(u32),
                            .event_type = .request_issued,
                            ._padding = 0,
                            ._reserved = 0,
                        },
                        .payload = payload,
                        .checksum = 0,
                    };

                    try log.append(event);
                }
            },
            1 => {
                // Get random event if log not empty
                if (log.count() > 0) {
                    const idx = random.uintLessThan(usize, log.count());
                    const event = log.get(idx);
                    try testing.expect(event.payload.len == 240);
                }
            },
            2 => {
                // Clear occasionally
                if (random.boolean()) {
                    log.clear();
                }
            },
            else => unreachable,
        }
    }

    // Verify final state is valid
    try testing.expect(log.count() <= log.capacity());
}

test "fuzz: stress test event log capacity" {
    const allocator = testing.allocator;

    // Test with smaller capacity for speed
    const capacity = 5000;
    var log = try z6.EventLog.init(allocator, capacity);
    defer log.deinit();

    var prng = std.Random.DefaultPrng.init(0x12345678);
    const random = prng.random();

    // Fill to capacity
    for (0..capacity) |i| {
        var payload: [240]u8 = undefined;
        random.bytes(&payload);

        const event = Event{
            .header = .{
                .tick = @intCast(i),
                .vu_id = 0,
                .event_type = .request_issued,
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = payload,
            .checksum = 0,
        };

        try log.append(event);
    }

    try testing.expect(log.isFull());
    try testing.expectEqual(capacity, log.count());

    // Verify all events retrievable
    for (0..capacity) |i| {
        const event = log.get(i);
        try testing.expectEqual(@as(u64, @intCast(i)), event.header.tick);
    }
}
