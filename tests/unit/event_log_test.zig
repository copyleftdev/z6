//! Event Log Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const EventLog = z6.EventLog;
const Event = z6.Event;
const EventType = z6.EventType;

// Import constants from z6 module
const Header = z6.EventLogHeader;
const Footer = z6.EventLogFooter;
const MAGIC_NUMBER = z6.EVENT_LOG_MAGIC_NUMBER;
const MAX_EVENTS = z6.EVENT_LOG_MAX_EVENTS;

test "event_log: header size is 64 bytes" {
    try testing.expectEqual(@as(usize, 64), @sizeOf(Header));
}

test "event_log: footer size is 64 bytes" {
    try testing.expectEqual(@as(usize, 64), @sizeOf(Footer));
}

test "event_log: header has magic number" {
    const header = Header{
        .magic = MAGIC_NUMBER,
        .version = 1,
        ._padding1 = [_]u8{0} ** 6,
        .prng_seed = 0,
        .scenario_hash = [_]u8{0} ** 32,
        ._padding2 = [_]u8{0} ** 8,
    };

    try testing.expectEqual(MAGIC_NUMBER, header.magic);
}

test "event_log: initialize empty log" {
    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 1000);
    defer log.deinit();

    try testing.expectEqual(@as(usize, 0), log.count());
    try testing.expectEqual(@as(usize, 1000), log.capacity());
}

test "event_log: append single event" {
    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 100);
    defer log.deinit();

    const event = Event{
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

    try log.append(event);
    try testing.expectEqual(@as(usize, 1), log.count());
}

test "event_log: append multiple events" {
    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 100);
    defer log.deinit();

    for (0..10) |i| {
        const event = Event{
            .header = .{
                .tick = @intCast(i * 100),
                .vu_id = @intCast(i),
                .event_type = .request_issued,
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = [_]u8{0} ** 240,
            .checksum = 0,
        };
        try log.append(event);
    }

    try testing.expectEqual(@as(usize, 10), log.count());
}

test "event_log: append until full" {
    const allocator = testing.allocator;
    const capacity = 50;
    var log = try EventLog.init(allocator, capacity);
    defer log.deinit();

    // Fill the log
    for (0..capacity) |i| {
        const event = Event{
            .header = .{
                .tick = @intCast(i),
                .vu_id = 0,
                .event_type = .request_issued,
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = [_]u8{0} ** 240,
            .checksum = 0,
        };
        try log.append(event);
    }

    try testing.expectEqual(capacity, log.count());
    try testing.expect(log.isFull());
}

test "event_log: append to full log fails" {
    const allocator = testing.allocator;
    const capacity = 10;
    var log = try EventLog.init(allocator, capacity);
    defer log.deinit();

    // Fill the log
    for (0..capacity) |i| {
        const event = Event{
            .header = .{
                .tick = @intCast(i),
                .vu_id = 0,
                .event_type = .request_issued,
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = [_]u8{0} ** 240,
            .checksum = 0,
        };
        try log.append(event);
    }

    // Try to append one more - should fail
    const overflow_event = Event{
        .header = .{
            .tick = 9999,
            .vu_id = 0,
            .event_type = .request_issued,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0} ** 240,
        .checksum = 0,
    };

    try testing.expectError(error.LogFull, log.append(overflow_event));
}

test "event_log: retrieve event by index" {
    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 100);
    defer log.deinit();

    const event = Event{
        .header = .{
            .tick = 1234,
            .vu_id = 42,
            .event_type = .response_received,
            ._padding = 0,
            ._reserved = 0,
        },
        .payload = [_]u8{0xAA} ** 240,
        .checksum = 0x123456789ABCDEF0,
    };

    try log.append(event);

    const retrieved = log.get(0);
    try testing.expectEqual(event.header.tick, retrieved.header.tick);
    try testing.expectEqual(event.header.vu_id, retrieved.header.vu_id);
    try testing.expectEqual(event.checksum, retrieved.checksum);
}

test "event_log: get out of bounds returns error" {
    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 100);
    defer log.deinit();

    // Log is empty, index 0 should fail
    try testing.expectError(error.IndexOutOfBounds, log.getChecked(0));

    // Add one event
    const event = Event{
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
    try log.append(event);

    // Index 1 should fail (only index 0 valid)
    try testing.expectError(error.IndexOutOfBounds, log.getChecked(1));
}

test "event_log: iterate over events" {
    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 100);
    defer log.deinit();

    // Add 5 events
    for (0..5) |i| {
        const event = Event{
            .header = .{
                .tick = @intCast(i * 100),
                .vu_id = @intCast(i),
                .event_type = .request_issued,
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = [_]u8{0} ** 240,
            .checksum = 0,
        };
        try log.append(event);
    }

    // Iterate and verify
    var count: usize = 0;
    var iter = log.iterator();
    while (iter.next()) |event| {
        try testing.expectEqual(@as(u64, count * 100), event.header.tick);
        try testing.expectEqual(@as(u32, @intCast(count)), event.header.vu_id);
        count += 1;
    }

    try testing.expectEqual(@as(usize, 5), count);
}

test "event_log: events are ordered by tick" {
    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 100);
    defer log.deinit();

    // Add events in order
    const ticks = [_]u64{ 100, 200, 300, 400, 500 };
    for (ticks) |tick| {
        const event = Event{
            .header = .{
                .tick = tick,
                .vu_id = 0,
                .event_type = .request_issued,
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = [_]u8{0} ** 240,
            .checksum = 0,
        };
        try log.append(event);
    }

    // Verify ordering
    for (0..log.count()) |i| {
        const event = log.get(i);
        try testing.expectEqual(ticks[i], event.header.tick);
    }
}

test "event_log: capacity cannot exceed max" {
    const allocator = testing.allocator;

    // Try to create log with capacity > MAX_EVENTS
    try testing.expectError(error.CapacityTooLarge, EventLog.init(allocator, MAX_EVENTS + 1));
}

test "event_log: default max events is 10 million" {
    try testing.expectEqual(@as(usize, 10_000_000), MAX_EVENTS);
}

test "event_log: clear empties the log" {
    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 100);
    defer log.deinit();

    // Add events
    for (0..5) |i| {
        const event = Event{
            .header = .{
                .tick = @intCast(i),
                .vu_id = 0,
                .event_type = .request_issued,
                ._padding = 0,
                ._reserved = 0,
            },
            .payload = [_]u8{0} ** 240,
            .checksum = 0,
        };
        try log.append(event);
    }

    try testing.expectEqual(@as(usize, 5), log.count());

    // Clear
    log.clear();
    try testing.expectEqual(@as(usize, 0), log.count());
    try testing.expect(!log.isFull());
}

test "event_log: Tiger Style - preconditions verified" {
    // Document that implementation should include assertions:
    // - Capacity > 0 on init
    // - Capacity <= MAX_EVENTS on init
    // - Index < count on get
    // - Log not full on append

    const allocator = testing.allocator;
    var log = try EventLog.init(allocator, 100);
    defer log.deinit();

    try testing.expect(log.capacity() > 0);
    try testing.expect(log.capacity() <= MAX_EVENTS);
    try testing.expect(log.count() <= log.capacity());
}
