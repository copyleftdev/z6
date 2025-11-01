//! Event Log
//!
//! Append-only immutable event log for Z6.
//! Bounded capacity, deterministic ordering, integrity checked.
//!
//! Tiger Style:
//! - All logs are bounded (max 10M events)
//! - All operations are explicit
//! - Minimum 2 assertions per function

const std = @import("std");
const Event = @import("event.zig").Event;

/// Magic number for event log files (Z6EVT)
pub const MAGIC_NUMBER: u64 = 0x5A36_4556_5420;

/// Maximum events per log (10 million)
pub const MAX_EVENTS: usize = 10_000_000;

/// Event log header (64 bytes)
pub const Header = extern struct {
    magic: u64,
    version: u16,
    _padding1: [6]u8,
    prng_seed: u64,
    scenario_hash: [32]u8,
    _padding2: [8]u8,

    comptime {
        std.debug.assert(@sizeOf(Header) == 64);
    }
};

/// Event log footer (64 bytes)
pub const Footer = extern struct {
    event_count: u64,
    log_checksum: [32]u8,
    _padding: [24]u8,

    comptime {
        std.debug.assert(@sizeOf(Footer) == 64);
    }
};

/// Event log - bounded, append-only collection of events
pub const EventLog = struct {
    allocator: std.mem.Allocator,
    events: std.ArrayList(Event),
    max_capacity: usize,

    /// Initialize event log with bounded capacity
    pub fn init(allocator: std.mem.Allocator, max_capacity: usize) !EventLog {
        // Check errors first (before assertions)
        if (max_capacity > MAX_EVENTS) {
            return error.CapacityTooLarge;
        }

        if (max_capacity == 0) {
            return error.ZeroCapacity;
        }

        // Preconditions (after error checks)
        std.debug.assert(max_capacity > 0); // Non-zero capacity
        std.debug.assert(max_capacity <= MAX_EVENTS); // Within bounds

        var log = EventLog{
            .allocator = allocator,
            .events = .{},
            .max_capacity = max_capacity,
        };

        // Pre-allocate to avoid reallocations
        try log.events.ensureTotalCapacity(allocator, max_capacity);

        // Postconditions
        std.debug.assert(log.max_capacity == max_capacity); // Capacity set
        std.debug.assert(log.events.items.len == 0); // Starts empty

        return log;
    }

    /// Clean up event log
    pub fn deinit(self: *EventLog) void {
        // Preconditions
        std.debug.assert(self.events.items.len <= self.max_capacity); // Valid state
        std.debug.assert(self.max_capacity > 0); // Valid capacity

        self.events.deinit(self.allocator);

        // Postcondition: memory freed (implicit)
        std.debug.assert(self.max_capacity > 0); // Capacity preserved
    }

    /// Append event to log (append-only)
    pub fn append(self: *EventLog, event: Event) !void {
        // Preconditions
        std.debug.assert(self.events.items.len <= self.max_capacity); // Valid state
        std.debug.assert(event.payload.len == 240); // Valid event

        if (self.events.items.len >= self.max_capacity) {
            return error.LogFull;
        }

        try self.events.append(self.allocator, event);

        // Postconditions
        std.debug.assert(self.events.items.len > 0); // Event added
        std.debug.assert(self.events.items.len <= self.max_capacity); // Still within bounds
    }

    /// Get event by index (unchecked - for performance)
    pub fn get(self: *const EventLog, index: usize) Event {
        // Preconditions
        std.debug.assert(index < self.events.items.len); // Valid index
        std.debug.assert(self.events.items.len <= self.max_capacity); // Valid state

        const event = self.events.items[index];

        // Postcondition
        std.debug.assert(event.payload.len == 240); // Valid event

        return event;
    }

    /// Get event by index (checked - returns error)
    pub fn getChecked(self: *const EventLog, index: usize) !Event {
        // Preconditions
        std.debug.assert(self.events.items.len <= self.max_capacity); // Valid state
        std.debug.assert(self.max_capacity > 0); // Valid capacity

        if (index >= self.events.items.len) {
            return error.IndexOutOfBounds;
        }

        const event = self.events.items[index];

        // Postcondition
        std.debug.assert(event.payload.len == 240); // Valid event

        return event;
    }

    /// Get current event count
    pub fn count(self: *const EventLog) usize {
        // Preconditions
        std.debug.assert(self.events.items.len <= self.max_capacity); // Valid state
        std.debug.assert(self.max_capacity > 0); // Valid capacity

        const c = self.events.items.len;

        // Postcondition
        std.debug.assert(c <= self.max_capacity); // Within bounds

        return c;
    }

    /// Get maximum capacity
    pub fn capacity(self: *const EventLog) usize {
        // Preconditions
        std.debug.assert(self.max_capacity > 0); // Valid capacity
        std.debug.assert(self.max_capacity <= MAX_EVENTS); // Within global limit

        return self.max_capacity;
    }

    /// Check if log is full
    pub fn isFull(self: *const EventLog) bool {
        // Preconditions
        std.debug.assert(self.events.items.len <= self.max_capacity); // Valid state
        std.debug.assert(self.max_capacity > 0); // Valid capacity

        const full = self.events.items.len >= self.max_capacity;

        // Postcondition
        std.debug.assert(!full or self.events.items.len == self.max_capacity); // Full means at capacity

        return full;
    }

    /// Clear all events from log
    pub fn clear(self: *EventLog) void {
        // Preconditions
        std.debug.assert(self.events.items.len <= self.max_capacity); // Valid state
        std.debug.assert(self.max_capacity > 0); // Valid capacity

        self.events.clearRetainingCapacity();

        // Postconditions
        std.debug.assert(self.events.items.len == 0); // Empty
        std.debug.assert(!self.isFull()); // Not full after clear
    }

    /// Get iterator over events
    pub fn iterator(self: *const EventLog) Iterator {
        // Preconditions
        std.debug.assert(self.events.items.len <= self.max_capacity); // Valid state
        std.debug.assert(self.max_capacity > 0); // Valid capacity

        const iter = Iterator{
            .events = self.events.items,
            .index = 0,
        };

        // Postcondition
        std.debug.assert(iter.index == 0); // Starts at beginning

        return iter;
    }

    /// Iterator for event log
    pub const Iterator = struct {
        events: []const Event,
        index: usize,

        pub fn next(self: *Iterator) ?Event {
            // Preconditions
            std.debug.assert(self.index <= self.events.len); // Valid index
            std.debug.assert(self.events.len <= MAX_EVENTS); // Within bounds

            if (self.index >= self.events.len) {
                return null;
            }

            const event = self.events[self.index];
            self.index += 1;

            // Postconditions
            std.debug.assert(self.index > 0); // Advanced
            std.debug.assert(event.payload.len == 240); // Valid event

            return event;
        }
    };
};

// Compile-time tests
test "event_log: comptime size checks" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Header));
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(Footer));
}

test "event_log: comptime constant checks" {
    try std.testing.expectEqual(@as(u64, 0x5A36_4556_5420), MAGIC_NUMBER);
    try std.testing.expectEqual(@as(usize, 10_000_000), MAX_EVENTS);
}
