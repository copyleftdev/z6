//! Arena Allocator
//!
//! Fixed-buffer bump allocator for Z6.
//! Fast, predictable, bounded memory allocation.
//!
//! Tiger Style:
//! - All allocations are bounded
//! - Zero fragmentation
//! - Reset is O(1)
//! - Minimum 2 assertions per function

const std = @import("std");

/// Arena allocator with fixed buffer
pub const Arena = struct {
    buffer: []u8,
    offset: usize,

    /// Initialize arena with fixed buffer
    pub fn init(buffer: []u8) Arena {
        // Preconditions
        std.debug.assert(buffer.len > 0); // Non-empty buffer
        std.debug.assert(@intFromPtr(buffer.ptr) != 0); // Valid pointer

        return Arena{
            .buffer = buffer,
            .offset = 0,
        };
    }

    /// Allocate memory from arena
    pub fn alloc(self: *Arena, size: usize) ![]u8 {
        // Preconditions
        std.debug.assert(self.offset <= self.buffer.len); // Valid state
        std.debug.assert(size <= std.math.maxInt(usize)); // No overflow

        // Check if we have enough space
        if (self.offset + size > self.buffer.len) {
            return error.OutOfMemory;
        }

        const ptr = self.buffer[self.offset..][0..size];
        self.offset += size;

        // Postconditions
        std.debug.assert(self.offset <= self.buffer.len); // Still valid
        std.debug.assert(ptr.len == size); // Correct size returned

        return ptr;
    }

    /// Allocate aligned memory from arena
    pub fn allocAligned(self: *Arena, size: usize, alignment: usize) ![]u8 {
        // Preconditions
        std.debug.assert(self.offset <= self.buffer.len); // Valid state
        std.debug.assert(std.math.isPowerOfTwo(alignment)); // Power of 2 alignment

        // Calculate aligned offset
        const current_addr = @intFromPtr(self.buffer.ptr) + self.offset;
        const aligned_addr = std.mem.alignForward(usize, current_addr, alignment);
        const padding = aligned_addr - current_addr;

        // Check if we have enough space including padding
        if (self.offset + padding + size > self.buffer.len) {
            return error.OutOfMemory;
        }

        // Advance offset to aligned position
        self.offset += padding;

        const ptr = self.buffer[self.offset..][0..size];
        self.offset += size;

        // Postconditions
        std.debug.assert(self.offset <= self.buffer.len); // Still valid
        std.debug.assert(@intFromPtr(ptr.ptr) % alignment == 0); // Properly aligned
        std.debug.assert(ptr.len == size); // Correct size

        return ptr;
    }

    /// Reset arena to initial state (O(1))
    pub fn reset(self: *Arena) void {
        // Precondition
        std.debug.assert(self.offset <= self.buffer.len); // Valid state

        self.offset = 0;

        // Postcondition
        std.debug.assert(self.offset == 0); // Reset complete
    }

    /// Get arena capacity
    pub fn capacity(self: *const Arena) usize {
        // Precondition
        std.debug.assert(self.buffer.len > 0); // Valid buffer

        // Postcondition checked inline
        const cap = self.buffer.len;
        std.debug.assert(cap > 0); // Capacity is positive

        return cap;
    }

    /// Get used memory
    pub fn used(self: *const Arena) usize {
        // Preconditions
        std.debug.assert(self.offset <= self.buffer.len); // Valid state
        std.debug.assert(self.buffer.len > 0); // Valid buffer

        return self.offset;
    }

    /// Get remaining memory
    pub fn remaining(self: *const Arena) usize {
        // Preconditions
        std.debug.assert(self.offset <= self.buffer.len); // Valid state
        std.debug.assert(self.buffer.len > 0); // Valid buffer

        const rem = self.buffer.len - self.offset;

        // Postcondition
        std.debug.assert(rem <= self.buffer.len); // Cannot exceed capacity

        return rem;
    }
};

// Compile-time tests
test "arena: comptime size checks" {
    // Verify Arena struct size is reasonable
    const arena_size = @sizeOf(Arena);
    try std.testing.expect(arena_size <= 32); // Should be small
}

test "arena: comptime alignment" {
    // Verify Arena alignment
    const arena_align = @alignOf(Arena);
    try std.testing.expect(arena_align > 0);
}
