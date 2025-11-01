//! Determinism Integration Test
//!
//! Verifies that scheduler produces identical results with same seed.
//! This is the core guarantee of Z6's deterministic execution.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const Scheduler = z6.Scheduler;
const VUState = z6.VUState;

test "determinism: same seed produces identical VU spawns" {
    const allocator = testing.allocator;

    // Run 1
    var scheduler1 = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 42,
    });
    defer scheduler1.deinit();

    const vu_id1_a = try scheduler1.spawnVU(0);
    const vu_id1_b = try scheduler1.spawnVU(1);
    const vu_id1_c = try scheduler1.spawnVU(2);

    // Run 2 with same seed
    var scheduler2 = try Scheduler.init(allocator, .{
        .max_vus = 10,
        .prng_seed = 42,
    });
    defer scheduler2.deinit();

    const vu_id2_a = try scheduler2.spawnVU(0);
    const vu_id2_b = try scheduler2.spawnVU(1);
    const vu_id2_c = try scheduler2.spawnVU(2);

    // VU IDs should be identical
    try testing.expectEqual(vu_id1_a, vu_id2_a);
    try testing.expectEqual(vu_id1_b, vu_id2_b);
    try testing.expectEqual(vu_id1_c, vu_id2_c);
}

test "determinism: same seed produces identical PRNG sequence" {
    const allocator = testing.allocator;

    // Run 1
    var scheduler1 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 12345,
    });
    defer scheduler1.deinit();

    var values1: [100]u64 = undefined;
    for (&values1) |*val| {
        val.* = scheduler1.prng.next();
    }

    // Run 2 with same seed
    var scheduler2 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 12345,
    });
    defer scheduler2.deinit();

    var values2: [100]u64 = undefined;
    for (&values2) |*val| {
        val.* = scheduler2.prng.next();
    }

    // All values should match exactly
    try testing.expectEqualSlices(u64, &values1, &values2);
}

test "determinism: tick advancement is reproducible" {
    const allocator = testing.allocator;

    // Run 1
    var scheduler1 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 999,
    });
    defer scheduler1.deinit();

    for (0..100) |_| {
        scheduler1.advanceTick();
    }
    const final_tick1 = scheduler1.current_tick;

    // Run 2
    var scheduler2 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 999,
    });
    defer scheduler2.deinit();

    for (0..100) |_| {
        scheduler2.advanceTick();
    }
    const final_tick2 = scheduler2.current_tick;

    // Final ticks should match
    try testing.expectEqual(final_tick1, final_tick2);
    try testing.expectEqual(@as(u64, 100), final_tick1);
}

test "determinism: VU state transitions are reproducible" {
    const allocator = testing.allocator;

    // Run 1
    var scheduler1 = try Scheduler.init(allocator, .{
        .max_vus = 3,
        .prng_seed = 777,
    });
    defer scheduler1.deinit();

    const vu_id1 = try scheduler1.spawnVU(0);
    scheduler1.advanceTick();
    var vu1 = scheduler1.getVUMut(vu_id1);
    vu1.transitionTo(.ready, 1);
    vu1.transitionTo(.executing, 2);
    scheduler1.advanceTick();
    scheduler1.advanceTick();

    // Run 2 with same seed and operations
    var scheduler2 = try Scheduler.init(allocator, .{
        .max_vus = 3,
        .prng_seed = 777,
    });
    defer scheduler2.deinit();

    const vu_id2 = try scheduler2.spawnVU(0);
    scheduler2.advanceTick();
    var vu2 = scheduler2.getVUMut(vu_id2);
    vu2.transitionTo(.ready, 1);
    vu2.transitionTo(.executing, 2);
    scheduler2.advanceTick();
    scheduler2.advanceTick();

    // States and ticks should match
    try testing.expectEqual(vu1.state, vu2.state);
    try testing.expectEqual(scheduler1.current_tick, scheduler2.current_tick);
    try testing.expectEqual(@as(u64, 3), scheduler1.current_tick);
}

test "determinism: different seeds produce different results" {
    const allocator = testing.allocator;

    // Run 1
    var scheduler1 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 111,
    });
    defer scheduler1.deinit();

    const val1 = scheduler1.prng.next();

    // Run 2 with different seed
    var scheduler2 = try Scheduler.init(allocator, .{
        .max_vus = 5,
        .prng_seed = 222,
    });
    defer scheduler2.deinit();

    const val2 = scheduler2.prng.next();

    // Values should be different
    try testing.expect(val1 != val2);
}

test "determinism: complex scenario is reproducible" {
    const allocator = testing.allocator;

    // Helper to run a complex scenario
    const runScenario = struct {
        fn run(allocator_param: std.mem.Allocator, seed: u64) !struct { tick: u64, vu_count: usize, active_count: usize } {
            var scheduler = try Scheduler.init(allocator_param, .{
                .max_vus = 10,
                .prng_seed = seed,
            });
            defer scheduler.deinit();

            // Spawn VUs
            _ = try scheduler.spawnVU(0);
            _ = try scheduler.spawnVU(0);
            const vu_id3 = try scheduler.spawnVU(1);

            // Advance time
            scheduler.advanceTick();
            scheduler.advanceTick();

            // Transition some VUs
            var vu3 = scheduler.getVUMut(vu_id3);
            vu3.transitionTo(.ready, 2);

            // Spawn more
            _ = try scheduler.spawnVU(2);
            _ = try scheduler.spawnVU(3);

            scheduler.advanceTick();

            return .{
                .tick = scheduler.current_tick,
                .vu_count = scheduler.countVUs(),
                .active_count = scheduler.countActiveVUs(),
            };
        }
    }.run;

    // Run scenario twice with same seed
    const result1 = try runScenario(allocator, 54321);
    const result2 = try runScenario(allocator, 54321);

    // Results should be identical
    try testing.expectEqual(result1.tick, result2.tick);
    try testing.expectEqual(result1.vu_count, result2.vu_count);
    try testing.expectEqual(result1.active_count, result2.active_count);
}
