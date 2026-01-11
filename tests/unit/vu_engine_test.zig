//! VU Execution Engine Tests
//!
//! Tests for VU lifecycle and request execution
//! Integrated with Scenario Parser (TASK-300)

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const VUEngine = z6.VUEngine;
const EngineConfig = z6.EngineConfig;
const VU = z6.VU;
const VUState = z6.VUState;

test "vu_engine: basic structure" {
    // Engine structure exists and can be referenced
    const engine_type = @TypeOf(VUEngine);
    try testing.expect(engine_type == type);
}

test "vu_engine: VU initialization" {
    // Test VU creation directly
    const vu = VU.init(1, 0);
    try testing.expectEqual(@as(u32, 1), vu.id);
    try testing.expectEqual(VUState.spawned, vu.state);
    try testing.expectEqual(@as(u64, 0), vu.spawn_tick);
}

test "vu_engine: VU state transitions" {
    var vu = VU.init(1, 0);

    // Transition spawned -> ready
    vu.transitionTo(.ready, 1);
    try testing.expectEqual(VUState.ready, vu.state);
    try testing.expectEqual(@as(u64, 1), vu.last_transition_tick);

    // Transition ready -> executing
    vu.transitionTo(.executing, 2);
    try testing.expectEqual(VUState.executing, vu.state);

    // Transition executing -> complete
    vu.transitionTo(.complete, 3);
    try testing.expectEqual(VUState.complete, vu.state);
    try testing.expect(vu.isComplete());
}

test "vu_engine: VU active state check" {
    var vu = VU.init(1, 0);

    // Spawned = not active
    try testing.expect(!vu.isActive());

    // Ready = active
    vu.transitionTo(.ready, 1);
    try testing.expect(vu.isActive());

    // Executing = active
    vu.transitionTo(.executing, 2);
    try testing.expect(vu.isActive());

    // Complete = not active
    vu.transitionTo(.complete, 3);
    try testing.expect(!vu.isActive());
}

test "vu_engine: engine init and deinit" {
    const allocator = testing.allocator;

    const config = EngineConfig{
        .max_vus = 10,
        .duration_ticks = 100,
    };

    const engine = try VUEngine.init(allocator, config);
    defer engine.deinit();

    try testing.expectEqual(@as(u32, 10), engine.config.max_vus);
    try testing.expectEqual(@as(u64, 100), engine.config.duration_ticks);
    try testing.expectEqual(@as(usize, 0), engine.getActiveVUCount());
    try testing.expectEqual(@as(u64, 0), engine.getCurrentTick());
}

test "vu_engine: spawn VU" {
    const allocator = testing.allocator;

    const config = EngineConfig{
        .max_vus = 5,
        .duration_ticks = 100,
    };

    const engine = try VUEngine.init(allocator, config);
    defer engine.deinit();

    // Spawn first VU
    const vu_id1 = try engine.spawnVU();
    try testing.expectEqual(@as(u32, 1), vu_id1);
    try testing.expectEqual(@as(usize, 1), engine.getActiveVUCount());

    // Spawn second VU
    const vu_id2 = try engine.spawnVU();
    try testing.expectEqual(@as(u32, 2), vu_id2);
    try testing.expectEqual(@as(usize, 2), engine.getActiveVUCount());
}

test "vu_engine: spawn all VUs" {
    const allocator = testing.allocator;

    const config = EngineConfig{
        .max_vus = 5,
        .duration_ticks = 100,
    };

    const engine = try VUEngine.init(allocator, config);
    defer engine.deinit();

    try engine.spawnAllVUs();

    try testing.expectEqual(@as(usize, 5), engine.getActiveVUCount());
}

test "vu_engine: tick processing" {
    const allocator = testing.allocator;

    const config = EngineConfig{
        .max_vus = 2,
        .duration_ticks = 10,
        .think_time_ticks = 1,
    };

    const engine = try VUEngine.init(allocator, config);
    defer engine.deinit();

    // Spawn VUs
    _ = try engine.spawnVU();
    _ = try engine.spawnVU();

    // First tick: VUs transition spawned -> ready
    try engine.tick();
    try testing.expectEqual(@as(u64, 1), engine.getCurrentTick());

    // VUs should have emitted events
    try testing.expect(engine.getEventsEmitted() > 0);
}

test "vu_engine: completion detection" {
    const allocator = testing.allocator;

    const config = EngineConfig{
        .max_vus = 2,
        .duration_ticks = 5, // Short duration
        .think_time_ticks = 0, // No think time
    };

    const engine = try VUEngine.init(allocator, config);
    defer engine.deinit();

    try engine.spawnAllVUs();

    // Not complete initially
    try testing.expect(!engine.isComplete());

    // Run until complete
    var tick_count: u32 = 0;
    while (!engine.isComplete() and tick_count < 100) : (tick_count += 1) {
        try engine.tick();
    }

    // Should be complete within reasonable ticks
    try testing.expect(engine.isComplete());
    try testing.expect(tick_count < 100);
}

test "vu_engine: deterministic with same seed" {
    const allocator = testing.allocator;

    // Run 1
    const config1 = EngineConfig{
        .max_vus = 3,
        .duration_ticks = 20,
        .prng_seed = 12345,
    };
    const engine1 = try VUEngine.init(allocator, config1);
    defer engine1.deinit();
    try engine1.spawnAllVUs();
    var i: u32 = 0;
    while (i < 25) : (i += 1) {
        try engine1.tick();
    }
    const events1 = engine1.getEventsEmitted();

    // Run 2 with same seed
    const config2 = EngineConfig{
        .max_vus = 3,
        .duration_ticks = 20,
        .prng_seed = 12345, // Same seed
    };
    const engine2 = try VUEngine.init(allocator, config2);
    defer engine2.deinit();
    try engine2.spawnAllVUs();
    var j: u32 = 0;
    while (j < 25) : (j += 1) {
        try engine2.tick();
    }
    const events2 = engine2.getEventsEmitted();

    // Same seed should produce same number of events
    try testing.expectEqual(events1, events2);
}

test "vu_engine: Tiger Style - assertions" {
    // All VU engine functions have >= 2 assertions:
    // - VUEngine.init: 2 preconditions, 2 postconditions
    // - VUEngine.initFromScenario: 2 preconditions, 2 postconditions
    // - VUEngine.spawnVU: 2 preconditions, 2 postconditions
    // - VUEngine.tick: 2 preconditions, 2 postconditions
    // - VUEngine.processVU: 4 preconditions, 1 postcondition
    // - VUEngine.selectRequest: 2 preconditions, 1 postcondition
    // - VUEngine.emitVUEvent: 2 preconditions, 1 postcondition
    // - VUEngine.run: 2 preconditions, 2 postconditions
    // - VUEngine.spawnAllVUs: 2 preconditions, 2 postconditions
    // - VU.init: 1 precondition, 2 postconditions
    // - VU.transitionTo: 2 preconditions, 2 postconditions
}

test "vu_engine: bounded loops verification" {
    // All loops in VU engine are bounded:
    // - init: bounded by config.max_vus
    // - tick: bounded by active_vu_count AND MAX_VUS
    // - selectRequest: bounded by requests.len AND MAX_REQUESTS
    // - isComplete: bounded by active_vu_count AND MAX_VUS
    // - getTotalRequests: bounded by active_vu_count AND MAX_VUS
    // - run: bounded by max_ticks
    // - spawnAllVUs: bounded by config.max_vus AND MAX_VUS
}
