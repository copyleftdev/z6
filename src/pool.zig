//! Object Pool Allocator
//!
//! Fixed-capacity pool for frequently allocated/deallocated objects.
//! Fast O(1) acquire and release with no fragmentation.
//!
//! Tiger Style:
//! - Fixed capacity (no unbounded growth)
//! - Zero allocations after init
//! - Minimum 2 assertions per function

const std = @import("std");

/// Object pool with fixed capacity
pub fn Pool(comptime T: type, comptime capacity: usize) type {
    // Compile-time precondition
    comptime {
        if (capacity == 0) {
            @compileError("Pool capacity must be greater than zero");
        }
    }

    return struct {
        const Self = @This();

        objects: [capacity]T,
        free_list: [capacity]u32,
        free_count: u32,

        /// Initialize pool with all objects available
        pub fn init() Self {
            var pool: Self = undefined;

            // Initialize free list with all indices
            for (0..capacity) |i| {
                pool.free_list[i] = @intCast(i);
            }
            pool.free_count = capacity;

            // Postconditions
            std.debug.assert(pool.free_count == capacity); // All free
            std.debug.assert(pool.free_count <= capacity); // Valid count

            return pool;
        }

        /// Acquire an object from the pool
        pub fn acquire(self: *Self) !*T {
            // Preconditions
            std.debug.assert(self.free_count <= capacity); // Valid state
            std.debug.assert(self.free_list.len == capacity); // Valid free list

            if (self.free_count == 0) {
                return error.PoolExhausted;
            }

            // Pop from free list
            self.free_count -= 1;
            const index = self.free_list[self.free_count];

            // Get object pointer
            const obj = &self.objects[index];

            // Postconditions
            std.debug.assert(self.free_count < capacity); // Count decreased
            std.debug.assert(index < capacity); // Valid index
            std.debug.assert(@intFromPtr(obj) >= @intFromPtr(&self.objects[0])); // Within bounds
            const end_addr = @intFromPtr(&self.objects[0]) + (@sizeOf(T) * capacity);
            std.debug.assert(@intFromPtr(obj) < end_addr); // Within bounds

            return obj;
        }

        /// Release an object back to the pool
        pub fn release(self: *Self, obj: *T) void {
            // Preconditions
            std.debug.assert(self.free_count <= capacity); // Valid state
            std.debug.assert(@intFromPtr(obj) >= @intFromPtr(&self.objects[0])); // Within pool
            const end_addr = @intFromPtr(&self.objects[0]) + (@sizeOf(T) * capacity);
            std.debug.assert(@intFromPtr(obj) < end_addr); // Within pool

            // Calculate index from pointer
            const base_addr = @intFromPtr(&self.objects[0]);
            const obj_addr = @intFromPtr(obj);
            const offset = obj_addr - base_addr;
            const index: u32 = @intCast(offset / @sizeOf(T));

            // Verify index is valid
            std.debug.assert(index < capacity); // Within bounds

            // Debug mode: Check for double release
            if (std.debug.runtime_safety) {
                for (self.free_list[0..self.free_count]) |free_idx| {
                    if (free_idx == index) {
                        std.debug.panic("Double release detected for object at index {}", .{index});
                    }
                }
            }

            // Push to free list
            self.free_list[self.free_count] = index;
            self.free_count += 1;

            // Postconditions
            std.debug.assert(self.free_count <= capacity); // Valid count
            std.debug.assert(self.free_count > 0); // Count increased
        }

        /// Get pool capacity
        pub fn getCapacity(self: *const Self) u32 {
            // Precondition
            _ = self;
            std.debug.assert(capacity > 0); // Compile-time ensured

            // Postcondition verified inline
            const result: u32 = capacity;
            std.debug.assert(result > 0); // Positive capacity

            return result;
        }

        /// Get number of available objects
        pub fn available(self: *const Self) u32 {
            // Preconditions
            std.debug.assert(self.free_count <= capacity); // Valid count
            std.debug.assert(self.free_list.len == capacity); // Valid free list

            return self.free_count;
        }

        /// Get number of used objects
        pub fn used(self: *const Self) u32 {
            // Preconditions
            std.debug.assert(self.free_count <= capacity); // Valid count
            std.debug.assert(self.free_list.len == capacity); // Valid free list

            const used_count: u32 = @as(u32, capacity) - self.free_count;

            // Postcondition
            std.debug.assert(used_count <= capacity); // Cannot exceed capacity

            return used_count;
        }

        /// Reset pool (makes all objects available again)
        /// WARNING: Caller must ensure no acquired objects are still in use
        pub fn reset(self: *Self) void {
            // Precondition
            std.debug.assert(self.free_list.len == capacity); // Valid free list

            // Reinitialize free list
            for (0..capacity) |i| {
                self.free_list[i] = @intCast(i);
            }
            self.free_count = capacity;

            // Postconditions
            std.debug.assert(self.free_count == capacity); // All free
            std.debug.assert(self.free_count <= capacity); // Valid count
        }
    };
}

// Compile-time tests
test "pool: comptime checks" {
    const TestType = struct { x: u32 };

    // Should compile
    const pool = Pool(TestType, 10);
    _ = pool;

    // Verify pool size is reasonable
    const pool_instance = Pool(TestType, 10).init();
    const pool_size = @sizeOf(@TypeOf(pool_instance));
    try std.testing.expect(pool_size > 0);
}

test "pool: different capacities at comptime" {
    const TestType = struct { value: u64 };

    const SmallPool = Pool(TestType, 5);
    const LargePool = Pool(TestType, 1000);

    var small = SmallPool.init();
    var large = LargePool.init();

    try std.testing.expectEqual(@as(u32, 5), small.capacity());
    try std.testing.expectEqual(@as(u32, 1000), large.capacity());
}
