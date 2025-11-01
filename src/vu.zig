//! Virtual User (VU) State Machine
//!
//! Represents a single virtual user in the load test.
//! VUs progress through a deterministic state machine.
//!
//! Tiger Style:
//! - All state transitions are explicit
//! - Minimum 2 assertions per function
//! - State is always valid

const std = @import("std");

/// VU State Machine States
pub const VUState = enum {
    spawned, // VU allocated, not yet ready
    ready, // VU ready to execute next scenario step
    executing, // VU actively performing an action
    waiting, // VU blocked on I/O (waiting for response)
    complete, // VU has finished all scenario steps
};

/// Virtual User
pub const VU = struct {
    /// Unique VU identifier
    id: u32,

    /// Current state
    state: VUState,

    /// Current scenario step (0-indexed)
    scenario_step: u32,

    /// Tick when VU was spawned
    spawn_tick: u64,

    /// Tick of last state transition
    last_transition_tick: u64,

    /// Pending request ID (0 if no pending request)
    pending_request_id: u64,

    /// Timeout tick for current operation (0 if no timeout)
    timeout_tick: u64,

    /// Initialize a new VU
    pub fn init(id: u32, spawn_tick: u64) VU {
        // Preconditions
        std.debug.assert(id > 0); // VU ID must be positive

        const vu = VU{
            .id = id,
            .state = .spawned,
            .scenario_step = 0,
            .spawn_tick = spawn_tick,
            .last_transition_tick = spawn_tick,
            .pending_request_id = 0,
            .timeout_tick = 0,
        };

        // Postconditions
        std.debug.assert(vu.state == .spawned); // Initial state
        std.debug.assert(vu.id == id); // ID preserved

        return vu;
    }

    /// Transition to a new state
    pub fn transitionTo(self: *VU, new_state: VUState, tick: u64) void {
        // Preconditions
        std.debug.assert(tick >= self.last_transition_tick); // Time moves forward
        std.debug.assert(self.state != .complete or new_state == .complete); // Can't leave COMPLETE

        self.state = new_state;
        self.last_transition_tick = tick;

        // Postconditions
        std.debug.assert(self.state == new_state); // State updated
        std.debug.assert(self.last_transition_tick == tick); // Tick updated
    }

    /// Check if VU is active (not SPAWNED or COMPLETE)
    pub fn isActive(self: *const VU) bool {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU

        const active = switch (self.state) {
            .spawned, .complete => false,
            .ready, .executing, .waiting => true,
        };

        // Postcondition: result is deterministic
        return active;
    }

    /// Check if VU is complete
    pub fn isComplete(self: *const VU) bool {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU

        const complete = self.state == .complete;

        // Postcondition: complete state is terminal
        return complete;
    }

    /// Check if VU can execute (is in READY state)
    pub fn canExecute(self: *const VU) bool {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU

        const can_exec = self.state == .ready;

        // Postcondition: only READY VUs can execute
        return can_exec;
    }

    /// Advance to next scenario step
    pub fn advanceStep(self: *VU) void {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU
        const old_step = self.scenario_step;

        self.scenario_step += 1;

        // Postconditions
        std.debug.assert(self.scenario_step == old_step + 1); // Step advanced
        std.debug.assert(self.scenario_step > 0); // Non-zero step
    }

    /// Set pending request
    pub fn setPendingRequest(self: *VU, request_id: u64, timeout_tick: u64) void {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU
        std.debug.assert(request_id > 0); // Valid request ID

        self.pending_request_id = request_id;
        self.timeout_tick = timeout_tick;

        // Postconditions
        std.debug.assert(self.hasPendingRequest()); // Request set
        std.debug.assert(self.pending_request_id == request_id); // ID preserved
    }

    /// Clear pending request
    pub fn clearPendingRequest(self: *VU) void {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU

        self.pending_request_id = 0;
        self.timeout_tick = 0;

        // Postconditions
        std.debug.assert(!self.hasPendingRequest()); // Request cleared
        std.debug.assert(self.timeout_tick == 0); // Timeout cleared
    }

    /// Check if VU has a pending request
    pub fn hasPendingRequest(self: *const VU) bool {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU

        const has_pending = self.pending_request_id != 0;

        // Postcondition: pending state matches request ID
        return has_pending;
    }

    /// Set timeout for current operation
    pub fn setTimeout(self: *VU, timeout_tick: u64) void {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU
        std.debug.assert(timeout_tick > 0); // Valid timeout

        self.timeout_tick = timeout_tick;

        // Postcondition: timeout set
        std.debug.assert(self.timeout_tick == timeout_tick);
    }

    /// Clear timeout
    pub fn clearTimeout(self: *VU) void {
        // Preconditions
        std.debug.assert(self.id > 0); // Valid VU

        self.timeout_tick = 0;

        // Postcondition: timeout cleared
        std.debug.assert(self.timeout_tick == 0);
    }
};

// Compile-time tests
test "vu: comptime size check" {
    // VU should be reasonably small
    const vu_size = @sizeOf(VU);
    // Should fit in a few cache lines (< 128 bytes)
    try std.testing.expect(vu_size <= 128);
}

test "vu: state enum is compact" {
    // State should be small (u8)
    const state_size = @sizeOf(VUState);
    try std.testing.expect(state_size <= 4);
}
