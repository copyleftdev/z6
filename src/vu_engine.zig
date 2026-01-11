//! VU Execution Engine
//!
//! Coordinates Virtual User execution for load testing.
//! Integrates Scenario, Scheduler, and Protocol Handlers.
//!
//! Tiger Style:
//! - All loops bounded
//! - Minimum 2 assertions per function
//! - Explicit error handling

const std = @import("std");
const vu_mod = @import("vu.zig");
const scenario_mod = @import("scenario.zig");
const prng_mod = @import("prng.zig");
const event_mod = @import("event.zig");

const Allocator = std.mem.Allocator;
const VU = vu_mod.VU;
const VUState = vu_mod.VUState;
const Scenario = scenario_mod.Scenario;
const RequestDef = scenario_mod.RequestDef;
const PRNG = prng_mod.PRNG;
const Event = event_mod.Event;
const EventType = event_mod.EventType;

/// Maximum VUs per engine
pub const MAX_VUS: usize = 10_000;

/// Default think time in ticks (between requests)
pub const DEFAULT_THINK_TIME_TICKS: u64 = 10;

/// Maximum requests per VU
pub const MAX_REQUESTS_PER_VU: usize = 10_000;

/// VU Engine errors
pub const EngineError = error{
    TooManyVUs,
    NoVUsAvailable,
    InvalidConfiguration,
    NoRequestsDefined,
};

/// VU Execution Engine Configuration
pub const EngineConfig = struct {
    max_vus: u32,
    duration_ticks: u64,
    think_time_ticks: u64 = DEFAULT_THINK_TIME_TICKS,
    prng_seed: u64 = 42,
};

/// VU execution context (tracks per-VU state)
pub const VUContext = struct {
    request_count: u32,
    last_request_tick: u64,
    current_request_index: ?usize,
};

/// VU Execution Engine
pub const VUEngine = struct {
    allocator: Allocator,
    config: EngineConfig,
    vus: []VU,
    vu_contexts: []VUContext,
    active_vu_count: usize,
    next_vu_id: u32,
    current_tick: u64,
    prng: PRNG,
    requests: []const RequestDef,
    total_weight: f32,
    events_emitted: u64,

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

        // Allocate VU context array
        const vu_contexts = try allocator.alloc(VUContext, config.max_vus);
        errdefer allocator.free(vu_contexts);

        // Initialize contexts
        var i: usize = 0;
        while (i < config.max_vus) : (i += 1) {
            vu_contexts[i] = VUContext{
                .request_count = 0,
                .last_request_tick = 0,
                .current_request_index = null,
            };
        }

        engine.* = VUEngine{
            .allocator = allocator,
            .config = config,
            .vus = vus,
            .vu_contexts = vu_contexts,
            .active_vu_count = 0,
            .next_vu_id = 1,
            .current_tick = 0,
            .prng = PRNG.init(config.prng_seed),
            .requests = &[_]RequestDef{},
            .total_weight = 0.0,
            .events_emitted = 0,
        };

        // Postconditions
        std.debug.assert(engine.config.max_vus == config.max_vus); // Config applied
        std.debug.assert(engine.active_vu_count == 0); // No VUs active yet

        return engine;
    }

    /// Initialize VU Engine from a parsed Scenario
    pub fn initFromScenario(allocator: Allocator, scenario: *const Scenario) !*VUEngine {
        // Preconditions
        std.debug.assert(scenario.requests.len > 0); // Must have requests
        std.debug.assert(scenario.runtime.vus > 0); // Must have VUs

        if (scenario.requests.len == 0) {
            return EngineError.NoRequestsDefined;
        }

        // Convert duration from seconds to ticks (assume 100 ticks/second)
        const ticks_per_second: u64 = 100;
        const duration_ticks = @as(u64, scenario.runtime.duration_seconds) * ticks_per_second;

        const config = EngineConfig{
            .max_vus = scenario.runtime.vus,
            .duration_ticks = duration_ticks,
            .think_time_ticks = DEFAULT_THINK_TIME_TICKS,
            .prng_seed = scenario.runtime.prng_seed orelse 42,
        };

        const engine = try init(allocator, config);
        errdefer engine.deinit();

        // Set requests and calculate total weight
        engine.requests = scenario.requests;
        engine.total_weight = 0.0;
        var i: usize = 0;
        while (i < scenario.requests.len and i < scenario_mod.MAX_REQUESTS) : (i += 1) {
            engine.total_weight += scenario.requests[i].weight;
        }

        // Postconditions
        std.debug.assert(engine.requests.len > 0); // Requests set
        std.debug.assert(engine.total_weight > 0.0); // Valid weights

        return engine;
    }

    /// Free engine resources
    pub fn deinit(self: *VUEngine) void {
        self.allocator.free(self.vu_contexts);
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
        std.debug.assert(self.active_vu_count <= self.config.max_vus); // Valid count

        self.current_tick += 1;

        // Process each active VU (bounded loop)
        var i: usize = 0;
        while (i < self.active_vu_count and i < MAX_VUS) : (i += 1) {
            try self.processVU(i);
        }

        // Postconditions
        std.debug.assert(self.current_tick > 0); // Tick advanced
        std.debug.assert(i <= MAX_VUS); // Loop bounded
    }

    /// Process a single VU by index
    fn processVU(self: *VUEngine, vu_index: usize) !void {
        // Preconditions
        std.debug.assert(vu_index < self.active_vu_count); // Valid index
        std.debug.assert(vu_index < MAX_VUS); // Within bounds

        const vu = &self.vus[vu_index];
        const ctx = &self.vu_contexts[vu_index];

        std.debug.assert(vu.id > 0); // Valid VU
        std.debug.assert(self.current_tick >= vu.spawn_tick); // Time coherent

        // State machine with request selection and think time
        switch (vu.state) {
            .spawned => {
                // Transition spawned → ready
                vu.transitionTo(.ready, self.current_tick);
                self.emitVUEvent(vu.id, .vu_ready);
            },
            .ready => {
                // Check think time before starting new request
                const elapsed = self.current_tick - ctx.last_request_tick;
                if (ctx.request_count == 0 or elapsed >= self.config.think_time_ticks) {
                    // Select and start a request
                    if (self.requests.len > 0) {
                        const request_index = self.selectRequest();
                        ctx.current_request_index = request_index;
                        ctx.request_count += 1;
                        ctx.last_request_tick = self.current_tick;
                        vu.transitionTo(.executing, self.current_tick);
                        self.emitVUEvent(vu.id, .request_issued);
                    } else {
                        // No requests defined, complete immediately
                        vu.transitionTo(.complete, self.current_tick);
                        self.emitVUEvent(vu.id, .vu_complete);
                    }
                }
            },
            .executing => {
                // Simulate request execution (1 tick for now)
                // In real implementation, would wait for protocol handler response
                vu.transitionTo(.waiting, self.current_tick);
            },
            .waiting => {
                // Simulate response received
                // In real implementation, would check CompletionQueue
                ctx.current_request_index = null;
                self.emitVUEvent(vu.id, .response_received);

                // Check if we should continue or complete
                if (self.current_tick >= self.config.duration_ticks) {
                    vu.transitionTo(.complete, self.current_tick);
                    self.emitVUEvent(vu.id, .vu_complete);
                } else {
                    vu.transitionTo(.ready, self.current_tick);
                }
            },
            .complete => {
                // VU is done, no action needed
            },
        }

        // Postcondition
        std.debug.assert(vu.last_transition_tick >= vu.spawn_tick); // Valid timeline
    }

    /// Select a request by weight (weighted random selection)
    fn selectRequest(self: *VUEngine) usize {
        // Preconditions
        std.debug.assert(self.requests.len > 0); // Have requests
        std.debug.assert(self.total_weight > 0.0); // Valid weights

        // Generate random value in [0, total_weight)
        const rand_val: f32 = @floatCast(self.prng.float() * @as(f64, self.total_weight));

        // Find request by accumulated weight
        var accumulated: f32 = 0.0;
        var i: usize = 0;
        while (i < self.requests.len and i < scenario_mod.MAX_REQUESTS) : (i += 1) {
            accumulated += self.requests[i].weight;
            if (rand_val < accumulated) {
                return i;
            }
        }

        // Fallback to last request (shouldn't happen with valid weights)
        std.debug.assert(self.requests.len > 0); // Postcondition

        return self.requests.len - 1;
    }

    /// Emit a VU event (for event log integration)
    fn emitVUEvent(self: *VUEngine, vu_id: u32, event_type: EventType) void {
        // Preconditions
        std.debug.assert(vu_id > 0); // Valid VU ID
        std.debug.assert(self.events_emitted < std.math.maxInt(u64)); // No overflow

        // Track event (actual EventLog integration will be added)
        self.events_emitted += 1;

        // Postcondition
        std.debug.assert(self.events_emitted > 0); // Event counted

        // Note: In full implementation, would append to EventLog
        _ = event_type;
    }

    /// Get number of active VUs
    pub fn getActiveVUCount(self: *const VUEngine) usize {
        // Precondition
        std.debug.assert(self.active_vu_count <= self.config.max_vus);
        // Postcondition - return is bounded
        return self.active_vu_count;
    }

    /// Get current tick
    pub fn getCurrentTick(self: *const VUEngine) u64 {
        return self.current_tick;
    }

    /// Get total events emitted
    pub fn getEventsEmitted(self: *const VUEngine) u64 {
        return self.events_emitted;
    }

    /// Get total requests made across all VUs
    pub fn getTotalRequests(self: *const VUEngine) u64 {
        // Precondition
        std.debug.assert(self.active_vu_count <= self.config.max_vus);

        var total: u64 = 0;
        var i: usize = 0;
        while (i < self.active_vu_count and i < MAX_VUS) : (i += 1) {
            total += self.vu_contexts[i].request_count;
        }

        // Postcondition
        std.debug.assert(i <= MAX_VUS);

        return total;
    }

    /// Run engine until all VUs complete or duration expires
    pub fn run(self: *VUEngine) !void {
        // Preconditions
        std.debug.assert(self.active_vu_count > 0); // Must have VUs
        std.debug.assert(self.config.duration_ticks > 0); // Must have duration

        // Run until complete or max ticks (bounded)
        var tick_count: u64 = 0;
        const max_ticks = self.config.duration_ticks + 1000; // Buffer for completion

        while (!self.isComplete() and tick_count < max_ticks) : (tick_count += 1) {
            try self.tick();
        }

        // Postconditions
        std.debug.assert(tick_count <= max_ticks); // Loop bounded
        std.debug.assert(self.current_tick > 0); // Made progress
    }

    /// Spawn all configured VUs
    pub fn spawnAllVUs(self: *VUEngine) !void {
        // Preconditions
        std.debug.assert(self.active_vu_count == 0); // No VUs yet
        std.debug.assert(self.config.max_vus > 0); // Have VUs to spawn

        var i: u32 = 0;
        while (i < self.config.max_vus and i < MAX_VUS) : (i += 1) {
            _ = try self.spawnVU();
        }

        // Postconditions
        std.debug.assert(self.active_vu_count == self.config.max_vus); // All spawned
        std.debug.assert(i <= MAX_VUS); // Loop bounded
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
