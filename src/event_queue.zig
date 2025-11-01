//! Event Queue - Priority Queue for Scheduler
//!
//! Min-heap priority queue ordered by tick (earliest first).
//! For events at same tick, maintains FIFO order.
//!
//! Tiger Style:
//! - Bounded capacity
//! - All operations have assertions
//! - Deterministic ordering

const std = @import("std");

/// Entry in the event queue
pub fn Entry(comptime T: type) type {
    return struct {
        tick: u64,
        event: T,
        sequence: u64, // For FIFO ordering within same tick
    };
}

/// Priority queue for scheduled events
pub fn EventQueue(comptime T: type) type {
    return struct {
        const Self = @This();
        const EntryType = Entry(T);

        allocator: std.mem.Allocator,
        items: []EntryType,
        capacity: usize,
        count: usize,
        next_sequence: u64, // Monotonic sequence for FIFO

        /// Initialize event queue with maximum capacity
        pub fn init(allocator: std.mem.Allocator, capacity: usize) Self {
            // Preconditions
            std.debug.assert(capacity > 0); // Must have capacity
            std.debug.assert(capacity <= 1_000_000); // Reasonable limit

            return Self{
                .allocator = allocator,
                .items = &.{}, // Start empty, allocate on first push
                .capacity = capacity,
                .count = 0,
                .next_sequence = 0,
            };
        }

        /// Clean up queue resources
        pub fn deinit(self: *Self) void {
            // Preconditions
            std.debug.assert(self.capacity > 0); // Valid state

            if (self.items.len > 0) {
                self.allocator.free(self.items);
            }

            // Postcondition: resources freed
        }

        /// Get number of items in queue
        pub fn len(self: *const Self) usize {
            // Preconditions
            std.debug.assert(self.count <= self.capacity); // Within bounds

            const length = self.count;

            // Postconditions
            std.debug.assert(length <= self.capacity); // Valid length

            return length;
        }

        /// Check if queue is empty
        pub fn isEmpty(self: *const Self) bool {
            // Preconditions
            std.debug.assert(self.count <= self.capacity); // Valid state

            return self.count == 0;
        }

        /// Push event scheduled for given tick
        pub fn push(self: *Self, tick: u64, event: T) !void {
            // Preconditions
            std.debug.assert(self.count <= self.capacity); // Valid state

            // Check capacity
            if (self.count >= self.capacity) {
                return error.QueueFull;
            }

            // Allocate storage if needed
            if (self.items.len == 0) {
                self.items = try self.allocator.alloc(EntryType, self.capacity);
            }

            // Create entry with sequence number for FIFO ordering
            const entry = EntryType{
                .tick = tick,
                .event = event,
                .sequence = self.next_sequence,
            };
            self.next_sequence += 1;

            // Add to end and bubble up
            self.items[self.count] = entry;
            self.count += 1;
            self.siftUp(self.count - 1);

            // Postconditions
            std.debug.assert(self.count > 0); // Item added
            std.debug.assert(self.count <= self.capacity); // Within bounds
            std.debug.assert(self.isHeapOrdered()); // Heap property maintained
        }

        /// Peek at next event without removing
        pub fn peek(self: *const Self) !EntryType {
            // Preconditions
            std.debug.assert(self.count <= self.capacity); // Valid state

            if (self.count == 0) {
                return error.QueueEmpty;
            }

            const entry = self.items[0];

            // Postcondition: returned earliest event
            return entry;
        }

        /// Remove and return next event
        pub fn pop(self: *Self) !EntryType {
            // Preconditions
            std.debug.assert(self.count <= self.capacity); // Valid state

            if (self.count == 0) {
                return error.QueueEmpty;
            }

            const result = self.items[0];

            // Move last element to root and sift down
            self.count -= 1;
            if (self.count > 0) {
                self.items[0] = self.items[self.count];
                self.siftDown(0);
            }

            // Postconditions
            std.debug.assert(self.count < self.capacity); // Count reduced
            std.debug.assert(self.isHeapOrdered()); // Heap property maintained

            return result;
        }

        /// Clear all events
        pub fn clear(self: *Self) void {
            // Preconditions
            std.debug.assert(self.count <= self.capacity); // Valid state

            self.count = 0;
            self.next_sequence = 0;

            // Postconditions
            std.debug.assert(self.count == 0); // Queue cleared
        }

        /// Sift element up to maintain heap property
        fn siftUp(self: *Self, start_index: usize) void {
            var index = start_index;

            while (index > 0) {
                const parent_index = (index - 1) / 2;

                if (self.lessThan(self.items[index], self.items[parent_index])) {
                    // Swap with parent
                    const temp = self.items[index];
                    self.items[index] = self.items[parent_index];
                    self.items[parent_index] = temp;
                    index = parent_index;
                } else {
                    break;
                }
            }
        }

        /// Sift element down to maintain heap property
        fn siftDown(self: *Self, start_index: usize) void {
            var index = start_index;

            while (true) {
                const left_child = 2 * index + 1;
                const right_child = 2 * index + 2;

                if (left_child >= self.count) {
                    break; // No children
                }

                // Find smallest child
                var smallest = index;

                if (self.lessThan(self.items[left_child], self.items[smallest])) {
                    smallest = left_child;
                }

                if (right_child < self.count and
                    self.lessThan(self.items[right_child], self.items[smallest]))
                {
                    smallest = right_child;
                }

                if (smallest != index) {
                    // Swap with smallest child
                    const temp = self.items[index];
                    self.items[index] = self.items[smallest];
                    self.items[smallest] = temp;
                    index = smallest;
                } else {
                    break;
                }
            }
        }

        /// Compare entries: first by tick, then by sequence (FIFO)
        fn lessThan(self: *const Self, a: EntryType, b: EntryType) bool {
            _ = self;
            if (a.tick != b.tick) {
                return a.tick < b.tick;
            }
            // Same tick: use sequence for FIFO ordering
            return a.sequence < b.sequence;
        }

        /// Verify heap property (for assertions)
        fn isHeapOrdered(self: *const Self) bool {
            if (self.count <= 1) return true;

            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                const left_child = 2 * i + 1;
                const right_child = 2 * i + 2;

                if (left_child < self.count) {
                    if (self.lessThan(self.items[left_child], self.items[i])) {
                        return false; // Heap property violated
                    }
                }

                if (right_child < self.count) {
                    if (self.lessThan(self.items[right_child], self.items[i])) {
                        return false; // Heap property violated
                    }
                }
            }

            return true;
        }
    };
}

// Compile-time tests
test "event_queue: comptime size check" {
    const TestEvent = struct { id: u32 };
    const Queue = EventQueue(TestEvent);

    // Queue should be reasonably sized
    const queue_size = @sizeOf(Queue);
    try std.testing.expect(queue_size > 0);
}
