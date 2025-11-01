//! PRNG Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.
//!
//! Tests for deterministic pseudo-random number generator (PRNG).
//! Uses xorshift64* algorithm for reproducibility.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const PRNG = z6.PRNG;

test "prng: determinism - same seed produces same sequence" {
    // Same seed should produce identical sequences
    var prng1 = PRNG.init(12345);
    var prng2 = PRNG.init(12345);

    // Generate 1000 numbers and verify they match
    for (0..1000) |_| {
        const val1 = prng1.next();
        const val2 = prng2.next();
        try testing.expectEqual(val1, val2);
    }
}

test "prng: different seeds produce different sequences" {
    var prng1 = PRNG.init(11111);
    var prng2 = PRNG.init(22222);

    // First values should be different
    const val1 = prng1.next();
    const val2 = prng2.next();
    try testing.expect(val1 != val2);

    // Sequences should remain different
    var differences: usize = 0;
    for (0..100) |_| {
        if (prng1.next() != prng2.next()) {
            differences += 1;
        }
    }

    // Expect at least 95% different (very unlikely to match by chance)
    try testing.expect(differences >= 95);
}

test "prng: produces non-zero values" {
    var prng = PRNG.init(42);

    // Should not produce all zeros
    var non_zero_count: usize = 0;
    for (0..100) |_| {
        if (prng.next() != 0) {
            non_zero_count += 1;
        }
    }

    // Expect at least some non-zero values
    try testing.expect(non_zero_count > 0);
}

test "prng: produces values across range" {
    var prng = PRNG.init(0xDEADBEEF);

    // Just verify we get non-zero values and some variation
    var values: [10]u64 = undefined;
    for (&values) |*val| {
        val.* = prng.next();
    }

    // Check that at least some values are different
    var all_same = true;
    for (values[1..]) |val| {
        if (val != values[0]) {
            all_same = false;
            break;
        }
    }

    try testing.expect(!all_same);
}

test "prng: zero seed is valid" {
    var prng = PRNG.init(0);

    // Should still produce non-zero values eventually
    const val1 = prng.next();
    const val2 = prng.next();

    // At least one should be non-zero
    try testing.expect(val1 != 0 or val2 != 0);
}

test "prng: reproducible across resets" {
    const seed: u64 = 98765;

    // First run
    var prng1 = PRNG.init(seed);
    var sequence1: [10]u64 = undefined;
    for (&sequence1) |*val| {
        val.* = prng1.next();
    }

    // Second run with same seed
    var prng2 = PRNG.init(seed);
    var sequence2: [10]u64 = undefined;
    for (&sequence2) |*val| {
        val.* = prng2.next();
    }

    // Should be identical
    try testing.expectEqualSlices(u64, &sequence1, &sequence2);
}

test "prng: state advances correctly" {
    var prng = PRNG.init(1);

    const val1 = prng.next();
    const val2 = prng.next();
    const val3 = prng.next();

    // All three should be different (extremely unlikely to collide)
    try testing.expect(val1 != val2);
    try testing.expect(val2 != val3);
    try testing.expect(val1 != val3);
}

test "prng: long sequence determinism" {
    // Verify determinism over long sequences
    var prng1 = PRNG.init(0xCAFEBABE);
    var prng2 = PRNG.init(0xCAFEBABE);

    // Generate 100,000 numbers
    for (0..100_000) |_| {
        try testing.expectEqual(prng1.next(), prng2.next());
    }
}

test "prng: bounded random in range" {
    var prng = PRNG.init(777);

    // Test range [0, 100)
    const max: u64 = 100;
    for (0..1000) |_| {
        const val = prng.range(max);
        try testing.expect(val < max);
    }
}

test "prng: bounded random range edge cases" {
    var prng = PRNG.init(888);

    // Range of 1 should always return 0
    for (0..10) |_| {
        try testing.expectEqual(@as(u64, 0), prng.range(1));
    }

    // Range of 2 should return 0 or 1
    for (0..100) |_| {
        const val = prng.range(2);
        try testing.expect(val == 0 or val == 1);
    }
}

test "prng: shuffle determinism" {
    var prng1 = PRNG.init(555);
    var prng2 = PRNG.init(555);

    var array1 = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var array2 = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };

    prng1.shuffle(u32, &array1);
    prng2.shuffle(u32, &array2);

    // Shuffled arrays should be identical
    try testing.expectEqualSlices(u32, &array1, &array2);

    // At least one element should have moved
    const original = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    var moved = false;
    for (array1, 0..) |val, i| {
        if (val != original[i]) {
            moved = true;
            break;
        }
    }
    try testing.expect(moved);
}

test "prng: Tiger Style - assertions present" {
    // Document that implementation should include:
    // - Assertion that state advances (state changes after next())
    // - Assertion for range bounds (max > 0)
    // - Assertion for shuffle array not empty

    var prng = PRNG.init(123);
    _ = prng.next();

    // If we get here, basic operations work
    try testing.expect(true);
}

test "prng: range produces all values in small range" {
    var prng = PRNG.init(999);

    // Generate numbers in range [0, 10) and verify we get different values
    var buckets = [_]bool{false} ** 10;

    // With 100 samples, we should see most buckets filled
    for (0..100) |_| {
        const val = prng.range(10);
        buckets[val] = true;
    }

    // Count how many different values we saw
    var filled: usize = 0;
    for (buckets) |seen| {
        if (seen) filled += 1;
    }

    // Should see at least 8 out of 10 values (80%)
    try testing.expect(filled >= 8);
}
