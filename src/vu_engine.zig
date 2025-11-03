//! VU Execution Engine
//!
//! Coordinates Virtual User execution for load testing.
//! Integrates Scenario, Scheduler, and Protocol Handlers.
//!
//! Tiger Style:
//! - All loops bounded
//! - Minimum 2 assertions per function
//! - Explicit error handling
//!
//! Note: Full integration with Scenario Parser (TASK-300) pending.
//! This is a foundational MVP for VU lifecycle management.

const std = @import("std");
const vu_mod = @import("vu.zig");

const Allocator = std.mem.Allocator;
const VU = vu_mod.VU;
const VUState = vu_mod.VUState;

/// Maximum VUs per engine
pub const MAX_VUS: usize = 10_000;

/// VU Engine errors
pub const EngineError = error{
    TooManyVUs,
    NoVUsAvailable,
    InvalidConfiguration,
};

/// VU Execution Engine Configuration
pub const EngineConfig = struct {
    max_vus: u32,
    duration_ticks: u64,
};

/// VU Execution Engine
pub const VUEngine = struct {
    allocator: Allocator,
    config: EngineConfig,
    vus: []VU,
    active_vu_count: usize,
    next_vu_id: u32,
    current_tick: u64,

    /// Initialize VU Engine with configuration
    pub fn init(allocator: Allocator, config: EngineConfig) !*VUEngine {
        // Preconditions
        std.debug.assert(config.max_vus > 0); // Must have VUs
        std.debug.assert(config.max_vus <= MAX_VUS); // Within limit

        if (config.max_vus > MAX_VUS) {
            return EngineError.TooManyVUs;
        }

        const engine = try allocator.create(VUEngine);
        errdefer allocator.destroy(engine);

        // Allocate VU array
        const vus = try allocator.alloc(VU, config.max_vus);
        errdefer allocator.free(vus);

        engine.* = VUEngine{
            .allocator = allocator,
            .config = config,
            .vus = vus,
            .active_vu_count = 0,
            .next_vu_id = 1,
            .current_tick = 0,
        };

        // Postconditions
        std.debug.assert(engine.config.max_vus == config.max_vus); // Config applied
        std.debug.assert(engine.active_vu_count == 0); // No VUs active yet

        return engine;
    }

    /// Free engine resources
    pub fn deinit(self: *VUEngine) void {
        self.allocator.free(self.vus);
        self.allocator.destroy(self);
    }

    /// Spawn a new VU
    pub fn spawnVU(self: *VUEngine) !u32 {
        // Preconditions
        std.debug.assert(self.active_vu_count < self.config.max_vus); // Have capacity
        std.debug.assert(self.next_vu_id > 0); // Valid ID counter

        if (self.active_vu_count >= self.config.max_vus) {
            return EngineError.TooManyVUs;
        }

        const vu_id = self.next_vu_id;
        self.next_vu_id += 1;

        // Initialize VU in array
        const vu_index = self.active_vu_count;
        self.vus[vu_index] = VU.init(vu_id, self.current_tick);
        self.active_vu_count += 1;

        // Postconditions
        std.debug.assert(self.active_vu_count > 0); // VU added
        std.debug.assert(self.vus[vu_index].id == vu_id); // ID set correctly

        return vu_id;
    }

    /// Advance engine by one tick
    pub fn tick(self: *VUEngine) !void {
        // Preconditions
        std.debug.assert(self.current_tick < std.math.maxInt(u64)); // No overflow
        std.debug.assert(self.active_vu_count <= self.max_vus); // Valid count

        self.current_tick += 1;

        // Process each active VU (bounded loop)
        var i: usize = 0;
        while (i < self.active_vu_count and i < MAX_VUS) : (i += 1) {
            try self.processVU(&self.vus[i]);
        }

        // Postconditions
        std.debug.assert(self.current_tick > 0); // Tick advanced
        std.debug.assert(i < MAX_VUS); // Loop bounded
    }

    /// Process a single VU
    fn processVU(self: *VUEngine, vu: *VU) !void {
        // Preconditions
        std.debug.assert(vu.id > 0); // Valid VU
        std.debug.assert(self.current_tick >= vu.spawn_tick); // Time coherent

        // Simple state machine (MVP)
        switch (vu.state) {
            .spawned => {
                // Transition spawned → ready
                vu.transitionTo(.ready, self.current_tick);
            },
            .ready => {
                // Ready to execute (would select and execute request here)
                // For MVP, just transition to complete
                vu.transitionTo(.complete, self.current_tick);
            },
            .executing, .waiting => {
                // Would handle request execution here
                vu.transitionTo(.complete, self.current_tick);
            },
            .complete => {
                // VU is done
            },
        }

        // Postcondition
        std.debug.assert(vu.last_transition_tick >= vu.spawn_tick); // Valid timeline
    }

    /// Get number of active VUs
    pub fn getActiveVUCount(self: *const VUEngine) usize {
        return self.active_vu_count;
    }

    /// Check if engine is complete (all VUs done)
    pub fn isComplete(self: *const VUEngine) bool {
        // Preconditions
        std.debug.assert(self.active_vu_count <= self.config.max_vus); // Valid

        var complete_count: usize = 0;
        var i: usize = 0;
        while (i < self.active_vu_count and i < MAX_VUS) : (i += 1) {
            if (self.vus[i].isComplete()) {
                complete_count += 1;
            }
        }

        const all_complete = complete_count == self.active_vu_count;

        // Postcondition
        std.debug.assert(complete_count <= self.active_vu_count); // Logical

        return all_complete;
    }
};
