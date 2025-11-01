//! Scheduler Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.
//!
//! Tests for deterministic scheduler core.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const Scheduler = z6.Scheduler;
const VU = z6.VU;
const VUState = z6.VUState;
const PRNG = z6.PRNG;

test "scheduler: init with zero VUs" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 0,
        .prng_seed = 42,
    });
    defer scheduler.deinit();

    try testing.expectEqual(@as(u64, 0), scheduler.current_tick);
    try testing.expectEqual(@as(usize, 0), scheduler.vus.items.len);
}

test "scheduler: init with VUs" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 42,
    });
    defer scheduler.deinit();

    try testing.expectEqual(@as(u64, 0), scheduler.current_tick);
    try testing.expect(scheduler.vus.items.len <= 10);
}

test "scheduler: tick advances" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 123,
    });
    defer scheduler.deinit();

    try testing.expectEqual(@as(u64, 0), scheduler.current_tick);

    scheduler.advanceTick();
    try testing.expectEqual(@as(u64, 1), scheduler.current_tick);

    scheduler.advanceTick();
    try testing.expectEqual(@as(u64, 2), scheduler.current_tick);
}

test "scheduler: spawn VU" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 456,
    });
    defer scheduler.deinit();

    const vu_id = try scheduler.spawnVU(0);
    try testing.expect(vu_id > 0);

    const vu = scheduler.getVU(vu_id);
    try testing.expectEqual(VUState.spawned, vu.state);
    try testing.expectEqual(@as(u64, 0), vu.spawn_tick);
}

test "scheduler: cannot exceed max VUs" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 2,
        .prng_seed = 789,
    });
    defer scheduler.deinit();

    _ = try scheduler.spawnVU(0);
    _ = try scheduler.spawnVU(0);

    // Third spawn should fail
    try testing.expectError(error.TooManyVUs, scheduler.spawnVU(0));
}

test "scheduler: get VU by ID" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 111,
    });
    defer scheduler.deinit();

    const vu_id = try scheduler.spawnVU(0);
    const vu = scheduler.getVU(vu_id);

    try testing.expectEqual(vu_id, vu.id);
}

test "scheduler: count VUs" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 222,
    });
    defer scheduler.deinit();

    try testing.expectEqual(@as(usize, 0), scheduler.countVUs());

    _ = try scheduler.spawnVU(0);
    try testing.expectEqual(@as(usize, 1), scheduler.countVUs());

    _ = try scheduler.spawnVU(0);
    _ = try scheduler.spawnVU(0);
    try testing.expectEqual(@as(usize, 3), scheduler.countVUs());
}

test "scheduler: count active VUs" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 333,
    });
    defer scheduler.deinit();

    const vu_id1 = try scheduler.spawnVU(0);
    const vu_id2 = try scheduler.spawnVU(0);

    // Both spawned (not active yet)
    try testing.expectEqual(@as(usize, 0), scheduler.countActiveVUs());

    // Activate first VU
    var vu1 = scheduler.getVUMut(vu_id1);
    vu1.transitionTo(.ready, 1);
    try testing.expectEqual(@as(usize, 1), scheduler.countActiveVUs());

    // Activate second VU
    var vu2 = scheduler.getVUMut(vu_id2);
    vu2.transitionTo(.ready, 1);
    try testing.expectEqual(@as(usize, 2), scheduler.countActiveVUs());

    // Complete first VU
    vu1.transitionTo(.complete, 2);
    try testing.expectEqual(@as(usize, 1), scheduler.countActiveVUs());
}

test "scheduler: deterministic PRNG" {
    const allocator = testing.allocator;

    var scheduler1 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 12345,
    });
    defer scheduler1.deinit();

    var scheduler2 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 12345,
    });
    defer scheduler2.deinit();

    // Same seed should produce same random values
    const val1 = scheduler1.prng.next();
    const val2 = scheduler2.prng.next();
    try testing.expectEqual(val1, val2);
}

test "scheduler: config validation" {
    const allocator = testing.allocator;

    // Max VUs too large
    try testing.expectError(error.ConfigInvalid, Scheduler.init(allocator, .{
        .max_vus = 1_000_000, // Way too many
        .prng_seed = 42,
    }));
}

test "scheduler: is complete when all VUs done" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 2,
        .prng_seed = 444,
    });
    defer scheduler.deinit();

    // No VUs spawned - scheduler is complete
    try testing.expect(scheduler.isComplete());

    // Spawn VUs
    const vu_id1 = try scheduler.spawnVU(0);
    const vu_id2 = try scheduler.spawnVU(0);

    // VUs exist but not complete
    try testing.expect(!scheduler.isComplete());

    // Complete VUs
    var vu1 = scheduler.getVUMut(vu_id1);
    vu1.transitionTo(.complete, 1);
    try testing.expect(!scheduler.isComplete()); // Still one active

    var vu2 = scheduler.getVUMut(vu_id2);
    vu2.transitionTo(.complete, 1);
    try testing.expect(scheduler.isComplete()); // All complete
}

test "scheduler: Tiger Style - assertions present" {
    // Document that implementation should include:
    // - Assertion that max_vus is reasonable (< 100K)
    // - Assertion that current_tick only advances
    // - Assertion for valid VU IDs
    // - Assertion for valid state transitions

    const allocator = testing.allocator;
    var scheduler = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 42,
    });
    defer scheduler.deinit();

    // If we get here, basic operations work
    try testing.expect(true);
}

test "scheduler: configuration defaults" {
    const allocator = testing.allocator;

    var scheduler = try Scheduler.init(allocator, .{});
    defer scheduler.deinit();

    // Should use default values
    try testing.expectEqual(@as(u64, 0), scheduler.current_tick);
}
