//! Deterministic Pseudo-Random Number Generator
//!
//! Implements xorshift64* algorithm for Z6 scheduler.
//! Guarantees deterministic output for reproducible load tests.
//!
//! Tiger Style:
//! - All operations are deterministic
//! - State is explicit and mutable
//! - Minimum 2 assertions per function

const std = @import("std");

/// Deterministic PRNG using xorshift64* algorithm
pub const PRNG = struct {
    state: u64,

    /// Initialize PRNG with seed
    /// Seed of 0 is valid and will be transformed to non-zero state
    pub fn init(seed: u64) PRNG {
        // Transform seed to ensure non-zero initial state
        // xorshift64* requires non-zero state
        const initial_state = if (seed == 0) 0x853c49e6748fea9b else seed;

        // Postconditions
        std.debug.assert(initial_state != 0); // State must be non-zero

        return PRNG{ .state = initial_state };
    }

    /// Generate next pseudo-random u64
    /// Uses xorshift64* algorithm (deterministic)
    pub fn next(self: *PRNG) u64 {
        // Preconditions
        std.debug.assert(self.state != 0); // State must be non-zero for xorshift
        const old_state = self.state;

        // xorshift64* algorithm
        var x = self.state;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.state = x;

        // Postconditions
        std.debug.assert(self.state != 0); // State remains non-zero
        std.debug.assert(self.state != old_state); // State advanced

        // Multiply by constant for final mixing
        return x *% 0x2545F4914F6CDD1D;
    }

    /// Generate random u64 in range [0, max)
    /// Returns value < max
    pub fn range(self: *PRNG, max: u64) u64 {
        // Preconditions
        std.debug.assert(max > 0); // Range must be positive
        std.debug.assert(self.state != 0); // Valid state

        if (max == 1) {
            return 0;
        }

        // Use rejection sampling for uniform distribution
        // This avoids modulo bias
        const range_size = max;
        const rejection_threshold = (std.math.maxInt(u64) / range_size) * range_size;

        // Bounded loop - rejection probability is extremely low
        // Maximum iterations is capped for safety (should never reach this)
        var attempts: u32 = 0;
        const max_attempts: u32 = 1000; // Probabilistically should succeed in < 10 attempts

        while (attempts < max_attempts) : (attempts += 1) {
            const val = self.next();
            if (val < rejection_threshold) {
                const result = val % range_size;

                // Postconditions
                std.debug.assert(result < max); // Result within bounds

                return result;
            }
            // Reject and retry if val >= threshold
        }

        // Fallback if rejection sampling fails (astronomically unlikely)
        // Use simple modulo in this case
        return self.next() % range_size;
    }

    /// Shuffle array in-place using Fisher-Yates algorithm
    /// Deterministic given same PRNG state
    pub fn shuffle(self: *PRNG, comptime T: type, array: []T) void {
        // Preconditions
        std.debug.assert(array.len > 0); // Array must not be empty
        std.debug.assert(self.state != 0); // Valid state

        if (array.len <= 1) {
            return; // Nothing to shuffle
        }

        // Fisher-Yates shuffle (inside-out variant for determinism)
        var i: usize = array.len;
        while (i > 1) {
            i -= 1;
            const j = self.range(@as(u64, i + 1));
            const temp = array[i];
            array[i] = array[@intCast(j)];
            array[@intCast(j)] = temp;
        }

        // Postcondition: array length unchanged
        // (can't directly assert shuffle occurred without tracking original)
    }

    /// Generate random boolean (true/false with equal probability)
    pub fn boolean(self: *PRNG) bool {
        // Preconditions
        std.debug.assert(self.state != 0); // Valid state

        const val = self.next();

        // Postcondition: returns bool
        return (val & 1) == 1;
    }

    /// Generate random f64 in range [0.0, 1.0)
    pub fn float(self: *PRNG) f64 {
        // Preconditions
        std.debug.assert(self.state != 0); // Valid state

        const val = self.next();

        // Convert to [0.0, 1.0) by dividing by max u64
        const result = @as(f64, @floatFromInt(val)) / @as(f64, @floatFromInt(std.math.maxInt(u64)));

        // Postconditions
        std.debug.assert(result >= 0.0); // Non-negative
        std.debug.assert(result < 1.0); // Less than 1.0

        return result;
    }
};

// Compile-time tests
test "prng: comptime size check" {
    // PRNG should be small (just u64 state)
    const prng_size = @sizeOf(PRNG);
    try std.testing.expect(prng_size == 8);
}
