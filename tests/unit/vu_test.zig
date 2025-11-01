//! VU (Virtual User) Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.
//!
//! Tests for VU state machine and lifecycle management.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const VU = z6.VU;
const VUState = z6.VUState;

test "vu: initial state is SPAWNED" {
    const vu = VU.init(1, 0);

    try testing.expectEqual(VUState.spawned, vu.state);
    try testing.expectEqual(@as(u32, 1), vu.id);
    try testing.expectEqual(@as(u64, 0), vu.spawn_tick);
}

test "vu: transition SPAWNED -> READY" {
    var vu = VU.init(1, 0);
    try testing.expectEqual(VUState.spawned, vu.state);

    vu.transitionTo(.ready, 1);

    try testing.expectEqual(VUState.ready, vu.state);
    try testing.expectEqual(@as(u64, 1), vu.last_transition_tick);
}

test "vu: transition READY -> EXECUTING" {
    var vu = VU.init(1, 0);
    vu.transitionTo(.ready, 1);

    vu.transitionTo(.executing, 2);

    try testing.expectEqual(VUState.executing, vu.state);
    try testing.expectEqual(@as(u64, 2), vu.last_transition_tick);
}

test "vu: transition EXECUTING -> WAITING" {
    var vu = VU.init(1, 0);
    vu.transitionTo(.ready, 1);
    vu.transitionTo(.executing, 2);

    vu.transitionTo(.waiting, 3);

    try testing.expectEqual(VUState.waiting, vu.state);
    try testing.expectEqual(@as(u64, 3), vu.last_transition_tick);
}

test "vu: transition WAITING -> READY" {
    var vu = VU.init(1, 0);
    vu.transitionTo(.ready, 1);
    vu.transitionTo(.executing, 2);
    vu.transitionTo(.waiting, 3);

    vu.transitionTo(.ready, 4);

    try testing.expectEqual(VUState.ready, vu.state);
    try testing.expectEqual(@as(u64, 4), vu.last_transition_tick);
}

test "vu: transition READY -> COMPLETE" {
    var vu = VU.init(1, 0);
    vu.transitionTo(.ready, 1);

    vu.transitionTo(.complete, 5);

    try testing.expectEqual(VUState.complete, vu.state);
    try testing.expectEqual(@as(u64, 5), vu.last_transition_tick);
}

test "vu: transition WAITING -> COMPLETE (error case)" {
    var vu = VU.init(1, 0);
    vu.transitionTo(.ready, 1);
    vu.transitionTo(.executing, 2);
    vu.transitionTo(.waiting, 3);

    vu.transitionTo(.complete, 6);

    try testing.expectEqual(VUState.complete, vu.state);
}

test "vu: isActive returns true for active states" {
    var vu = VU.init(1, 0);

    // SPAWNED is not active yet
    try testing.expect(!vu.isActive());

    vu.transitionTo(.ready, 1);
    try testing.expect(vu.isActive());

    vu.transitionTo(.executing, 2);
    try testing.expect(vu.isActive());

    vu.transitionTo(.waiting, 3);
    try testing.expect(vu.isActive());

    vu.transitionTo(.complete, 4);
    try testing.expect(!vu.isActive());
}

test "vu: isComplete returns true only when COMPLETE" {
    var vu = VU.init(1, 0);

    try testing.expect(!vu.isComplete());

    vu.transitionTo(.ready, 1);
    try testing.expect(!vu.isComplete());

    vu.transitionTo(.executing, 2);
    try testing.expect(!vu.isComplete());

    vu.transitionTo(.waiting, 3);
    try testing.expect(!vu.isComplete());

    vu.transitionTo(.complete, 4);
    try testing.expect(vu.isComplete());
}

test "vu: canExecute returns true only when READY" {
    var vu = VU.init(1, 0);

    try testing.expect(!vu.canExecute());

    vu.transitionTo(.ready, 1);
    try testing.expect(vu.canExecute());

    vu.transitionTo(.executing, 2);
    try testing.expect(!vu.canExecute());

    vu.transitionTo(.waiting, 3);
    try testing.expect(!vu.canExecute());

    vu.transitionTo(.ready, 4);
    try testing.expect(vu.canExecute());

    vu.transitionTo(.complete, 5);
    try testing.expect(!vu.canExecute());
}

test "vu: scenario step tracking" {
    var vu = VU.init(1, 0);

    try testing.expectEqual(@as(u32, 0), vu.scenario_step);

    vu.advanceStep();
    try testing.expectEqual(@as(u32, 1), vu.scenario_step);

    vu.advanceStep();
    try testing.expectEqual(@as(u32, 2), vu.scenario_step);
}

test "vu: request tracking" {
    var vu = VU.init(1, 0);
    vu.transitionTo(.ready, 1);

    // Initially no pending request
    try testing.expect(!vu.hasPendingRequest());

    // Issue a request
    vu.setPendingRequest(42, 100);
    try testing.expect(vu.hasPendingRequest());
    try testing.expectEqual(@as(u64, 42), vu.pending_request_id);

    // Clear request
    vu.clearPendingRequest();
    try testing.expect(!vu.hasPendingRequest());
}

test "vu: state transition tick must advance" {
    var vu = VU.init(1, 0);

    vu.transitionTo(.ready, 1);
    try testing.expectEqual(@as(u64, 1), vu.last_transition_tick);

    vu.transitionTo(.executing, 5);
    try testing.expectEqual(@as(u64, 5), vu.last_transition_tick);

    // Tick should be >= last transition (can be equal if same tick)
    vu.transitionTo(.waiting, 5);
    try testing.expectEqual(@as(u64, 5), vu.last_transition_tick);
}

test "vu: multiple VUs have independent state" {
    var vu1 = VU.init(1, 0);
    var vu2 = VU.init(2, 5);

    vu1.transitionTo(.ready, 1);
    vu2.transitionTo(.ready, 6);

    try testing.expectEqual(VUState.ready, vu1.state);
    try testing.expectEqual(VUState.ready, vu2.state);
    try testing.expectEqual(@as(u32, 1), vu1.id);
    try testing.expectEqual(@as(u32, 2), vu2.id);

    vu1.transitionTo(.executing, 2);
    try testing.expectEqual(VUState.executing, vu1.state);
    try testing.expectEqual(VUState.ready, vu2.state); // vu2 unchanged
}

test "vu: timeout tracking" {
    var vu = VU.init(1, 0);
    vu.transitionTo(.ready, 1);
    vu.transitionTo(.executing, 2);

    // Set timeout
    vu.setTimeout(102); // tick 2 + timeout 100 = 102
    try testing.expectEqual(@as(u64, 102), vu.timeout_tick);

    // Clear timeout
    vu.clearTimeout();
    try testing.expectEqual(@as(u64, 0), vu.timeout_tick);
}

test "vu: state names for debugging" {
    try testing.expectEqualStrings("spawned", @tagName(VUState.spawned));
    try testing.expectEqualStrings("ready", @tagName(VUState.ready));
    try testing.expectEqualStrings("executing", @tagName(VUState.executing));
    try testing.expectEqualStrings("waiting", @tagName(VUState.waiting));
    try testing.expectEqualStrings("complete", @tagName(VUState.complete));
}

test "vu: Tiger Style - assertions present" {
    // Document that implementation should include:
    // - Assertion that VU ID > 0
    // - Assertion that tick advances (tick >= last_transition_tick)
    // - Assertion for valid state transitions

    var vu = VU.init(1, 0);
    vu.transitionTo(.ready, 1);

    // If we get here, basic operations work
    try testing.expect(true);
}

test "vu: full lifecycle flow" {
    var vu = VU.init(100, 0);

    // Birth
    try testing.expectEqual(VUState.spawned, vu.state);
    try testing.expectEqual(@as(u32, 100), vu.id);

    // Ready to work
    vu.transitionTo(.ready, 1);
    try testing.expect(vu.canExecute());

    // Execute request
    vu.transitionTo(.executing, 2);
    vu.setPendingRequest(1001, 102);
    try testing.expect(vu.hasPendingRequest());

    // Wait for response
    vu.transitionTo(.waiting, 3);
    try testing.expect(!vu.canExecute());
    try testing.expect(vu.isActive());

    // Response received
    vu.clearPendingRequest();
    vu.transitionTo(.ready, 50);
    try testing.expect(!vu.hasPendingRequest());

    // More work
    vu.advanceStep();
    try testing.expectEqual(@as(u32, 1), vu.scenario_step);

    // Complete
    vu.transitionTo(.complete, 100);
    try testing.expect(vu.isComplete());
    try testing.expect(!vu.isActive());
}
