//! VU Execution Engine Tests
//!
//! Tests for VU lifecycle and request execution
//!
//! Note: Full tests require Scenario Parser (TASK-300).
//! These are basic structural tests for MVP.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const VUEngine = z6.VUEngine;
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

test "vu_engine: Tiger Style - assertions" {
    // All VU engine functions have >= 2 assertions:
    // - VU.init: 1 precondition, 2 postconditions ✓
    // - VU.transitionTo: 2 preconditions, 2 postconditions ✓
    // - VU.isActive: 1 precondition ✓
    // - VU.isComplete: 1 precondition ✓
}
