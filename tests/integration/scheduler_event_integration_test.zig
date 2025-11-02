//! Scheduler-Event Integration Test
//!
//! Verifies that scheduler properly emits events to EventLog
//! for deterministic recording of execution.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const Scheduler = z6.Scheduler;
const EventLog = z6.EventLog;
const Event = z6.Event;
const EventType = z6.EventType;

test "scheduler: emits vu_spawned event" {
    const allocator = testing.allocator;

    // Create event log
    var event_log = try EventLog.init(allocator, 100);
    defer event_log.deinit();

    // Create scheduler with event log
    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 42,
        .event_log = &event_log,
    });
    defer scheduler.deinit();

    // Spawn VU at tick 5
    scheduler.current_tick = 5;
    const vu_id = try scheduler.spawnVU(5);

    // Verify event was logged
    try testing.expectEqual(@as(usize, 1), event_log.count());

    const event = event_log.get(0);
    try testing.expectEqual(@as(u64, 5), event.header.tick);
    try testing.expectEqual(vu_id, event.header.vu_id);
    try testing.expectEqual(EventType.vu_spawned, event.header.event_type);
}

test "scheduler: emits scheduler_tick event" {
    const allocator = testing.allocator;

    var event_log = try EventLog.init(allocator, 100);
    defer event_log.deinit();

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 123,
        .event_log = &event_log,
    });
    defer scheduler.deinit();

    // Advance tick
    scheduler.advanceTick();

    // Should have one scheduler_tick event
    try testing.expectEqual(@as(usize, 1), event_log.count());

    const event = event_log.get(0);
    try testing.expectEqual(@as(u64, 1), event.header.tick);
    try testing.expectEqual(@as(u32, 0), event.header.vu_id); // System event
    try testing.expectEqual(EventType.scheduler_tick, event.header.event_type);
}

test "scheduler: multiple VU spawns emit multiple events" {
    const allocator = testing.allocator;

    var event_log = try EventLog.init(allocator, 100);
    defer event_log.deinit();

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 999,
        .event_log = &event_log,
    });
    defer scheduler.deinit();

    // Spawn 3 VUs
    _ = try scheduler.spawnVU(0);
    _ = try scheduler.spawnVU(1);
    _ = try scheduler.spawnVU(2);

    // Should have 3 vu_spawned events
    try testing.expectEqual(@as(usize, 3), event_log.count());

    for (0..3) |i| {
        const event = event_log.get(i);
        try testing.expectEqual(EventType.vu_spawned, event.header.event_type);
    }
}

test "scheduler: tick events accumulate" {
    const allocator = testing.allocator;

    var event_log = try EventLog.init(allocator, 100);
    defer event_log.deinit();

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 777,
        .event_log = &event_log,
    });
    defer scheduler.deinit();

    // Advance 5 ticks
    for (0..5) |_| {
        scheduler.advanceTick();
    }

    // Should have 5 scheduler_tick events
    try testing.expectEqual(@as(usize, 5), event_log.count());

    for (0..5) |i| {
        const event = event_log.get(i);
        const expected_tick: u64 = @intCast(i + 1);
        try testing.expectEqual(expected_tick, event.header.tick);
        try testing.expectEqual(EventType.scheduler_tick, event.header.event_type);
    }
}

test "scheduler: works without event log (optional)" {
    const allocator = testing.allocator;

    // Create scheduler WITHOUT event log
    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 42,
        .event_log = null, // No event log
    });
    defer scheduler.deinit();

    // Should still work normally
    const vu_id = try scheduler.spawnVU(0);
    try testing.expect(vu_id > 0);

    scheduler.advanceTick();
    try testing.expectEqual(@as(u64, 1), scheduler.current_tick);

    // No events logged (no event log provided)
    // This verifies scheduler can work standalone
}

test "scheduler: complex scenario logs all events" {
    const allocator = testing.allocator;

    var event_log = try EventLog.init(allocator, 100);
    defer event_log.deinit();

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 12345,
        .event_log = &event_log,
    });
    defer scheduler.deinit();

    // Complex scenario:
    // Spawn 2 VUs
    _ = try scheduler.spawnVU(0);
    _ = try scheduler.spawnVU(0);

    // Advance tick
    scheduler.advanceTick();

    // Spawn 1 more VU
    _ = try scheduler.spawnVU(1);

    // Advance tick
    scheduler.advanceTick();

    // Expected events:
    // 1. vu_spawned (tick 0)
    // 2. vu_spawned (tick 0)
    // 3. scheduler_tick (tick 1)
    // 4. vu_spawned (tick 1)
    // 5. scheduler_tick (tick 2)

    try testing.expectEqual(@as(usize, 5), event_log.count());

    // Verify event sequence
    const event0 = event_log.get(0);
    try testing.expectEqual(EventType.vu_spawned, event0.header.event_type);
    try testing.expectEqual(@as(u64, 0), event0.header.tick);

    const event1 = event_log.get(1);
    try testing.expectEqual(EventType.vu_spawned, event1.header.event_type);
    try testing.expectEqual(@as(u64, 0), event1.header.tick);

    const event2 = event_log.get(2);
    try testing.expectEqual(EventType.scheduler_tick, event2.header.event_type);
    try testing.expectEqual(@as(u64, 1), event2.header.tick);

    const event3 = event_log.get(3);
    try testing.expectEqual(EventType.vu_spawned, event3.header.event_type);
    try testing.expectEqual(@as(u64, 1), event3.header.tick);

    const event4 = event_log.get(4);
    try testing.expectEqual(EventType.scheduler_tick, event4.header.event_type);
    try testing.expectEqual(@as(u64, 2), event4.header.tick);
}

test "scheduler: event log is deterministic with same seed" {
    const allocator = testing.allocator;

    // Run 1
    var event_log1 = try EventLog.init(allocator, 100);
    defer event_log1.deinit();

    var scheduler1 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 54321,
        .event_log = &event_log1,
    });
    defer scheduler1.deinit();

    _ = try scheduler1.spawnVU(0);
    scheduler1.advanceTick();
    _ = try scheduler1.spawnVU(1);

    // Run 2 with same seed
    var event_log2 = try EventLog.init(allocator, 100);
    defer event_log2.deinit();

    var scheduler2 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 54321,
        .event_log = &event_log2,
    });
    defer scheduler2.deinit();

    _ = try scheduler2.spawnVU(0);
    scheduler2.advanceTick();
    _ = try scheduler2.spawnVU(1);

    // Event logs should be identical
    try testing.expectEqual(event_log1.count(), event_log2.count());

    for (0..event_log1.count()) |i| {
        const e1 = event_log1.get(i);
        const e2 = event_log2.get(i);
        try testing.expectEqual(e1.header.tick, e2.header.tick);
        try testing.expectEqual(e1.header.vu_id, e2.header.vu_id);
        try testing.expectEqual(e1.header.event_type, e2.header.event_type);
    }
}
