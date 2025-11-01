//! Event Model Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const Event = z6.Event;
const EventHeader = z6.EventHeader;
const EventType = z6.EventType;

test "event: header size is 24 bytes" {
    try testing.expectEqual(@as(usize, 24), @sizeOf(EventHeader));
}

test "event: total event size is 272 bytes" {
    try testing.expectEqual(@as(usize, 272), @sizeOf(Event));
}

test "event: header fields are correct sizes" {
    const header = EventHeader{
        .tick = 0,
        .vu_id = 0,
        .event_type = .vu_spawned,
        ._padding = 0,
        ._reserved = 0,
    };

    try testing.expectEqual(@as(usize, 8), @sizeOf(@TypeOf(header.tick)));
    try testing.expectEqual(@as(usize, 4), @sizeOf(@TypeOf(header.vu_id)));
    try testing.expectEqual(@as(usize, 2), @sizeOf(EventType));
    try testing.expectEqual(@as(usize, 2), @sizeOf(@TypeOf(header._padding)));
    try testing.expectEqual(@as(usize, 8), @sizeOf(@TypeOf(header._reserved)));
}

test "event: event type enum values" {
    // Verify all required event types exist
    const lifecycle_events = [_]EventType{
        .vu_spawned,
        .vu_ready,
        .vu_complete,
    };
    try testing.expect(lifecycle_events.len == 3);

    const request_events = [_]EventType{
        .request_issued,
        .request_timeout,
        .request_cancelled,
    };
    try testing.expect(request_events.len == 3);

    const response_events = [_]EventType{
        .response_received,
        .response_error,
    };
    try testing.expect(response_events.len == 2);
}

test "event: create event with header" {
    const event = Event{
        .header = .{
            .tick = 1000,
            .vu_id = 42,
            .event_type = .request_issued,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    try testing.expectEqual(@as(u64, 1000), event.header.tick);
    try testing.expectEqual(@as(u32, 42), event.header.vu_id);
    try testing.expectEqual(EventType.request_issued, event.header.event_type);
}

test "event: payload is 240 bytes" {
    const event = Event{
        .header = .{
            .tick = 0,
            .vu_id = 0,
            .event_type = .vu_spawned,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    try testing.expectEqual(@as(usize, 240), event.payload.len);
}

test "event: checksum is u64" {
    const event = Event{
        .header = .{
            .tick = 0,
            .vu_id = 0,
            .event_type = .vu_spawned,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0x1234567890ABCDEF,
    };

    try testing.expectEqual(@as(u64, 0x1234567890ABCDEF), event.checksum);
    try testing.expectEqual(@as(usize, 8), @sizeOf(@TypeOf(event.checksum)));
}

test "event: serialization round-trip" {
    const original = Event{
        .header = .{
            .tick = 1234567890,
            .vu_id = 999,
            .event_type = .response_received,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0xAA} ** 240,
        .checksum = 0xDEADBEEFCAFEBABE,
    };

    // Serialize
    var buffer: [272]u8 = undefined;
    const serialized = Event.serialize(&original, &buffer);
    try testing.expectEqual(@as(usize, 272), serialized.len);

    // Deserialize
    const deserialized = try Event.deserialize(serialized);

    // Verify round-trip
    try testing.expectEqual(original.header.tick, deserialized.header.tick);
    try testing.expectEqual(original.header.vu_id, deserialized.header.vu_id);
    try testing.expectEqual(original.header.event_type, deserialized.header.event_type);
    try testing.expectEqual(original.checksum, deserialized.checksum);

    // Verify payload
    for (original.payload, 0..) |byte, i| {
        try testing.expectEqual(byte, deserialized.payload[i]);
    }
}

test "event: serialize to bytes" {
    const event = Event{
        .header = .{
            .tick = 100,
            .vu_id = 1,
            .event_type = .request_issued,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    var buffer: [272]u8 = undefined;
    const bytes = Event.serialize(&event, &buffer);

    // Should be 272 bytes
    try testing.expectEqual(@as(usize, 272), bytes.len);

    // Should be deterministic
    var buffer2: [272]u8 = undefined;
    const bytes2 = Event.serialize(&event, &buffer2);
    try testing.expect(std.mem.eql(u8, bytes, bytes2));
}

test "event: deserialize from bytes" {
    var buffer: [272]u8 = undefined;

    // Manually construct valid event bytes
    const event = Event{
        .header = .{
            .tick = 500,
            .vu_id = 10,
            .event_type = .conn_established,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0x42} ** 240,
        .checksum = 0x123456789ABCDEF0,
    };

    const bytes = Event.serialize(&event, &buffer);
    const deserialized = try Event.deserialize(bytes);

    try testing.expectEqual(event.header.tick, deserialized.header.tick);
    try testing.expectEqual(event.header.vu_id, deserialized.header.vu_id);
}

test "event: checksum calculation" {
    var event = Event{
        .header = .{
            .tick = 1000,
            .vu_id = 42,
            .event_type = .request_issued,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0xFF} ** 240,
        .checksum = 0,
    };

    // Calculate checksum
    const checksum = Event.calculateChecksum(&event);
    event.checksum = checksum;

    // Verify checksum is non-zero for non-zero data
    try testing.expect(checksum != 0);

    // Verify checksum is deterministic
    const checksum2 = Event.calculateChecksum(&event);
    try testing.expectEqual(checksum, checksum2);
}

test "event: checksum validation" {
    var event = Event{
        .header = .{
            .tick = 2000,
            .vu_id = 5,
            .event_type = .response_received,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0xAA} ** 240,
        .checksum = 0,
    };

    // Calculate and set correct checksum
    event.checksum = Event.calculateChecksum(&event);

    // Should validate correctly
    try testing.expect(Event.validateChecksum(&event));

    // Corrupt the checksum
    event.checksum ^= 1;

    // Should fail validation
    try testing.expect(!Event.validateChecksum(&event));
}

test "event: checksum detects payload corruption" {
    var event = Event{
        .header = .{
            .tick = 3000,
            .vu_id = 7,
            .event_type = .error_timeout,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    // Calculate checksum
    event.checksum = Event.calculateChecksum(&event);
    try testing.expect(Event.validateChecksum(&event));

    // Corrupt payload
    event.payload[100] ^= 1;

    // Should detect corruption
    try testing.expect(!Event.validateChecksum(&event));
}

test "event: checksum detects header corruption" {
    var event = Event{
        .header = .{
            .tick = 4000,
            .vu_id = 9,
            .event_type = .scheduler_tick,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0x55} ** 240,
        .checksum = 0,
    };

    event.checksum = Event.calculateChecksum(&event);
    try testing.expect(Event.validateChecksum(&event));

    // Corrupt header
    event.header.tick += 1;

    // Should detect corruption
    try testing.expect(!Event.validateChecksum(&event));
}

test "event: different events have different checksums" {
    const event1 = Event{
        .header = .{
            .tick = 1000,
            .vu_id = 1,
            .event_type = .request_issued,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    const event2 = Event{
        .header = .{
            .tick = 2000,
            .vu_id = 2,
            .event_type = .response_received,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    const checksum1 = Event.calculateChecksum(&event1);
    const checksum2 = Event.calculateChecksum(&event2);

    try testing.expect(checksum1 != checksum2);
}

test "event: ordering by tick" {
    const event1 = Event{
        .header = .{
            .tick = 1000,
            .vu_id = 1,
            .event_type = .request_issued,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    const event2 = Event{
        .header = .{
            .tick = 2000,
            .vu_id = 1,
            .event_type = .response_received,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    try testing.expect(Event.isBefore(&event1, &event2));
    try testing.expect(!Event.isBefore(&event2, &event1));
}

test "event: ordering by vu_id when ticks equal" {
    const event1 = Event{
        .header = .{
            .tick = 1000,
            .vu_id = 1,
            .event_type = .request_issued,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    const event2 = Event{
        .header = .{
            .tick = 1000,
            .vu_id = 2,
            .event_type = .request_issued,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    try testing.expect(Event.isBefore(&event1, &event2));
    try testing.expect(!Event.isBefore(&event2, &event1));
}

test "event: Tiger Style - preconditions verified" {
    // Document that implementation should include assertions:
    // - Event size is 272 bytes
    // - Header size is 24 bytes
    // - Payload size is 240 bytes
    // - Checksum covers header + payload

    try testing.expectEqual(@as(usize, 272), @sizeOf(Event));
    try testing.expectEqual(@as(usize, 24), @sizeOf(EventHeader));
}
