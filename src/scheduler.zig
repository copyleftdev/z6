//! Scheduler - Deterministic Microkernel
//!
//! Coordinates all VU activity with perfect reproducibility.
//! Uses logical ticks (not wall-clock time) for determinism.
//!
//! Tiger Style:
//! - All operations are deterministic
//! - Minimum 2 assertions per function
//! - Bounded complexity

const std = @import("std");
const VU = @import("vu.zig").VU;
const VUState = @import("vu.zig").VUState;
const PRNG = @import("prng.zig").PRNG;
const EventLog = @import("event_log.zig").EventLog;
const Event = @import("event.zig").Event;
const EventType = @import("event.zig").EventType;

/// Tick is the fundamental unit of logical time
pub const Tick = u64;

/// Scheduler configuration
pub const SchedulerConfig = struct {
    /// Maximum number of VUs
    max_vus: u32 = 1000,

    /// PRNG seed (0 = use default seed)
    prng_seed: u64 = 0,

    /// Optional event log for recording execution
    event_log: ?*EventLog = null,
};

/// Scheduler - deterministic microkernel
pub const Scheduler = struct {
    allocator: std.mem.Allocator,

    /// Current logical time
    current_tick: Tick,

    /// Virtual users (sparse array, indexed by VU ID)
    vus: std.ArrayList(VU),

    /// Next VU ID to assign
    next_vu_id: u32,

    /// Maximum VUs allowed
    max_vus: u32,

    /// Deterministic PRNG
    prng: PRNG,

    /// Optional event log
    event_log: ?*EventLog,

    /// Initialize scheduler
    pub fn init(allocator: std.mem.Allocator, config: SchedulerConfig) !Scheduler {
        // Validate config first (before precondition asserts)
        if (config.max_vus > 100_000) {
            return error.ConfigInvalid;
        }

        // Preconditions (after validation)
        std.debug.assert(config.max_vus < 100_000); // Reasonable limit

        const seed = if (config.prng_seed == 0) 0x5A36_5343_4845_4420 else config.prng_seed; // Z6SCHED

        const scheduler = Scheduler{
            .allocator = allocator,
            .current_tick = 0,
            .vus = .{}, // Empty ArrayList
            .next_vu_id = 1, // VU IDs start at 1
            .max_vus = config.max_vus,
            .prng = PRNG.init(seed),
            .event_log = config.event_log,
        };

        // Postconditions
        std.debug.assert(scheduler.current_tick == 0); // Starts at tick 0
        std.debug.assert(scheduler.next_vu_id > 0); // Valid ID counter

        return scheduler;
    }

    /// Clean up scheduler resources
    pub fn deinit(self: *Scheduler) void {
        // Preconditions
        std.debug.assert(self.next_vu_id > 0); // Valid state

        self.vus.deinit(self.allocator);

        // Postcondition: resources freed
    }

    /// Advance logical tick
    pub fn advanceTick(self: *Scheduler) void {
        // Preconditions
        std.debug.assert(self.next_vu_id > 0); // Valid state
        const old_tick = self.current_tick;

        self.current_tick += 1;

        // Emit scheduler_tick event if logging
        if (self.event_log) |event_log| {
            const event = Event{
                .header = .{
                    .tick = self.current_tick,
                    .vu_id = 0, // System event
                    .event_type = .scheduler_tick,
                    ._padding = 0,
                    ._reserved = 0,
                },
                .payload = [_]u8{0} ** 240,
                .checksum = 0,
            };
            event_log.append(event) catch |err| {
                // Log error but don't fail - event logging is best-effort
                std.debug.print("Failed to log scheduler_tick: {}\n", .{err});
            };
        }

        // Postconditions
        std.debug.assert(self.current_tick == old_tick + 1); // Tick advanced
        std.debug.assert(self.current_tick > 0); // Monotonic
    }

    /// Spawn a new VU
    pub fn spawnVU(self: *Scheduler, spawn_tick: Tick) !u32 {
        // Preconditions
        std.debug.assert(self.next_vu_id > 0); // Valid state
        std.debug.assert(spawn_tick >= self.current_tick or spawn_tick == 0); // Future or current tick

        // Check capacity
        if (self.vus.items.len >= self.max_vus) {
            return error.TooManyVUs;
        }

        const vu_id = self.next_vu_id;
        self.next_vu_id += 1;

        const vu = VU.init(vu_id, spawn_tick);
        try self.vus.append(self.allocator, vu);

        // Emit vu_spawned event if logging
        if (self.event_log) |event_log| {
            const event = Event{
                .header = .{
                    .tick = self.current_tick,
                    .vu_id = vu_id,
                    .event_type = .vu_spawned,
                    ._padding = 0,
                    ._reserved = 0,
                },
                .payload = [_]u8{0} ** 240,
                .checksum = 0,
            };
            event_log.append(event) catch |err| {
                // Log error but don't fail - event logging is best-effort
                std.debug.print("Failed to log vu_spawned: {}\n", .{err});
            };
        }

        // Postconditions
        std.debug.assert(vu_id > 0); // Valid ID
        std.debug.assert(self.vus.items.len <= self.max_vus); // Within capacity

        return vu_id;
    }

    /// Get VU by ID (const)
    pub fn getVU(self: *const Scheduler, vu_id: u32) *const VU {
        // Preconditions
        std.debug.assert(vu_id > 0); // Valid ID
        std.debug.assert(vu_id < self.next_vu_id); // ID was assigned

        // Linear search (could optimize with hashmap later)
        for (self.vus.items) |*vu| {
            if (vu.id == vu_id) {
                // Postcondition: found VU
                std.debug.assert(vu.id == vu_id);
                return vu;
            }
        }

        unreachable; // VU ID must exist if it was assigned
    }

    /// Get mutable VU by ID
    pub fn getVUMut(self: *Scheduler, vu_id: u32) *VU {
        // Preconditions
        std.debug.assert(vu_id > 0); // Valid ID
        std.debug.assert(vu_id < self.next_vu_id); // ID was assigned

        // Linear search (could optimize with hashmap later)
        for (self.vus.items) |*vu| {
            if (vu.id == vu_id) {
                // Postcondition: found VU
                std.debug.assert(vu.id == vu_id);
                return vu;
            }
        }

        unreachable; // VU ID must exist if it was assigned
    }

    /// Count total VUs
    pub fn countVUs(self: *const Scheduler) usize {
        // Preconditions
        std.debug.assert(self.next_vu_id > 0); // Valid state

        const count = self.vus.items.len;

        // Postconditions
        std.debug.assert(count <= self.max_vus); // Within capacity

        return count;
    }

    /// Count active VUs (READY, EXECUTING, WAITING)
    pub fn countActiveVUs(self: *const Scheduler) usize {
        // Preconditions
        std.debug.assert(self.next_vu_id > 0); // Valid state

        var count: usize = 0;
        for (self.vus.items) |*vu| {
            if (vu.isActive()) {
                count += 1;
            }
        }

        // Postconditions
        std.debug.assert(count <= self.vus.items.len); // Can't exceed total

        return count;
    }

    /// Check if scheduler is complete (all VUs done or no VUs)
    pub fn isComplete(self: *const Scheduler) bool {
        // Preconditions
        std.debug.assert(self.next_vu_id > 0); // Valid state

        if (self.vus.items.len == 0) {
            return true; // No VUs = complete
        }

        // Check if all VUs are complete
        for (self.vus.items) |*vu| {
            if (!vu.isComplete()) {
                return false; // At least one VU not complete
            }
        }

        // Postcondition: all VUs are complete
        return true;
    }
};

// Compile-time tests
test "scheduler: comptime size check" {
    // Scheduler should be reasonably sized
    const scheduler_size = @sizeOf(Scheduler);
    try std.testing.expect(scheduler_size > 0);
}
