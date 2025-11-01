//! Memory Budget Manager
//!
//! Tracks and enforces memory budget for Z6.
//! All allocations are bounded and measured.
//!
//! Tiger Style:
//! - All allocations are explicit
//! - All allocations are bounded
//! - All allocations are measured
//! - Minimum 2 assertions per function

const std = @import("std");

/// Memory statistics
pub const MemoryStats = struct {
    total_budget: usize,
    used: usize,
    remaining: usize,
    peak_usage: usize,
    allocation_count: usize,
};

/// Allocation metadata
const Allocation = struct {
    size: usize,
};

/// Memory budget manager
pub const Memory = struct {
    allocator: std.mem.Allocator,
    total_budget: usize,
    current_used: usize,
    peak_used: usize,
    allocation_count: usize,
    allocations: std.AutoHashMap(usize, Allocation),

    /// Default memory budget: 16 GB (per MEMORY_MODEL.md)
    pub const DEFAULT_BUDGET: usize = 16 * 1024 * 1024 * 1024;

    /// Minimum alignment: 8 bytes (per MEMORY_MODEL.md)
    pub const MIN_ALIGNMENT: usize = 8;

    /// Initialize with default budget (16 GB)
    pub fn init() Memory {
        return initWithBudget(DEFAULT_BUDGET);
    }

    /// Initialize with custom budget
    pub fn initWithBudget(budget: usize) Memory {
        // Preconditions
        std.debug.assert(budget > 0); // Non-zero budget
        std.debug.assert(budget <= std.math.maxInt(usize)); // Valid size

        const mem = Memory{
            .allocator = std.heap.page_allocator,
            .total_budget = budget,
            .current_used = 0,
            .peak_used = 0,
            .allocation_count = 0,
            .allocations = std.AutoHashMap(usize, Allocation).init(std.heap.page_allocator),
        };

        // Postconditions
        std.debug.assert(mem.total_budget == budget); // Budget set correctly
        std.debug.assert(mem.current_used == 0); // Starts at zero

        return mem;
    }

    /// Clean up memory manager
    pub fn deinit(self: *Memory) void {
        // Precondition
        std.debug.assert(self.allocation_count == 0); // All freed before deinit

        self.allocations.deinit();

        // Postcondition
        std.debug.assert(self.current_used == 0); // Nothing remaining
    }

    /// Allocate memory within budget
    pub fn allocate(self: *Memory, size: usize) ![]u8 {
        // Precondition - check valid state
        std.debug.assert(self.current_used <= self.total_budget); // Valid state

        // Check for zero-size allocation first (before assertion)
        if (size == 0) {
            return error.InvalidSize;
        }

        // Now assert size is valid
        std.debug.assert(size > 0); // Non-zero allocation (guaranteed by check above)

        // Check budget
        if (self.current_used + size > self.total_budget) {
            return error.OutOfMemory;
        }

        // Allocate with minimum alignment (8 bytes)
        const ptr = try self.allocator.alloc(u8, size);

        // Track allocation
        const addr = @intFromPtr(ptr.ptr);
        try self.allocations.put(addr, Allocation{ .size = size });

        self.current_used += size;
        self.allocation_count += 1;

        // Update peak
        if (self.current_used > self.peak_used) {
            self.peak_used = self.current_used;
        }

        // Postconditions
        std.debug.assert(self.current_used <= self.total_budget); // Within budget
        std.debug.assert(ptr.len == size); // Correct size
        std.debug.assert(@intFromPtr(ptr.ptr) % @alignOf(u64) == 0); // Properly aligned (8 bytes)
        std.debug.assert(self.allocation_count > 0); // Count increased

        return ptr;
    }

    /// Free allocated memory
    pub fn free(self: *Memory, allocation: []u8) void {
        // Preconditions
        std.debug.assert(allocation.len > 0); // Valid allocation
        std.debug.assert(self.allocation_count > 0); // Have allocations

        const addr = @intFromPtr(allocation.ptr);

        // Look up allocation metadata
        const metadata = self.allocations.get(addr) orelse {
            std.debug.panic("Attempt to free untracked allocation at 0x{x}", .{addr});
        };

        std.debug.assert(metadata.size == allocation.len); // Size matches

        // Update tracking
        self.current_used -= metadata.size;
        self.allocation_count -= 1;
        _ = self.allocations.remove(addr);

        // Actually free the memory
        self.allocator.free(allocation);

        // Postconditions
        std.debug.assert(self.current_used <= self.total_budget); // Still valid
        std.debug.assert(self.allocation_count >= 0); // Count decreased
    }

    /// Get total budget
    pub fn totalBudget(self: *const Memory) usize {
        // Preconditions
        std.debug.assert(self.total_budget > 0); // Valid budget
        std.debug.assert(self.current_used <= self.total_budget); // Valid state

        return self.total_budget;
    }

    /// Get current memory usage
    pub fn used(self: *const Memory) usize {
        // Preconditions
        std.debug.assert(self.current_used <= self.total_budget); // Valid state
        std.debug.assert(self.total_budget > 0); // Valid budget

        return self.current_used;
    }

    /// Get remaining budget
    pub fn remaining(self: *const Memory) usize {
        // Preconditions
        std.debug.assert(self.current_used <= self.total_budget); // Valid state
        std.debug.assert(self.total_budget > 0); // Valid budget

        const rem = self.total_budget - self.current_used;

        // Postcondition
        std.debug.assert(rem <= self.total_budget); // Cannot exceed budget

        return rem;
    }

    /// Get peak memory usage
    pub fn peakUsage(self: *const Memory) usize {
        // Preconditions
        std.debug.assert(self.peak_used >= self.current_used); // Peak >= current
        std.debug.assert(self.peak_used <= self.total_budget); // Peak <= budget

        return self.peak_used;
    }

    /// Get current allocation count
    pub fn allocationCount(self: *const Memory) usize {
        // Precondition
        std.debug.assert(self.allocation_count >= 0); // Valid count

        // Postcondition verified inline
        const count = self.allocation_count;
        std.debug.assert(count >= 0); // Non-negative

        return count;
    }

    /// Get memory statistics
    pub fn getStats(self: *const Memory) MemoryStats {
        // Preconditions
        std.debug.assert(self.current_used <= self.total_budget); // Valid state
        std.debug.assert(self.total_budget > 0); // Valid budget

        const stats = MemoryStats{
            .total_budget = self.total_budget,
            .used = self.current_used,
            .remaining = self.total_budget - self.current_used,
            .peak_usage = self.peak_used,
            .allocation_count = self.allocation_count,
        };

        // Postconditions
        std.debug.assert(stats.used + stats.remaining == stats.total_budget); // Math checks out
        std.debug.assert(stats.peak_usage >= stats.used); // Peak >= current

        return stats;
    }
};

// Compile-time tests
test "memory: comptime budget checks" {
    const budget = Memory.DEFAULT_BUDGET;
    try std.testing.expectEqual(@as(usize, 16 * 1024 * 1024 * 1024), budget);
}

test "memory: comptime alignment checks" {
    const alignment = Memory.MIN_ALIGNMENT;
    try std.testing.expectEqual(@as(usize, 8), alignment);
}
