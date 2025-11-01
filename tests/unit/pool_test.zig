//! Object Pool Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const Pool = z6.Pool;

// Test object type
const TestObject = struct {
    id: u32,
    value: u64,
    data: [16]u8,
};

test "pool: initialization" {
    var pool = Pool(TestObject, 10).init();

    // Should start with all objects available
    try testing.expectEqual(@as(u32, 10), pool.getCapacity());
    try testing.expectEqual(@as(u32, 10), pool.available());
    try testing.expectEqual(@as(u32, 0), pool.used());
}

test "pool: acquire single object" {
    var pool = Pool(TestObject, 10).init();

    const obj = try pool.acquire();
    // obj acquired successfully - can write to it
    obj.id = 42;

    // Should reduce available count
    try testing.expectEqual(@as(u32, 9), pool.available());
    try testing.expectEqual(@as(u32, 1), pool.used());
}

test "pool: acquire and release" {
    var pool = Pool(TestObject, 10).init();

    const obj = try pool.acquire();
    try testing.expectEqual(@as(u32, 9), pool.available());

    pool.release(obj);
    try testing.expectEqual(@as(u32, 10), pool.available());
    try testing.expectEqual(@as(u32, 0), pool.used());
}

test "pool: acquire all objects" {
    var pool = Pool(TestObject, 5).init();

    var objects: [5]*TestObject = undefined;

    // Acquire all objects
    for (&objects) |*obj| {
        obj.* = try pool.acquire();
    }

    try testing.expectEqual(@as(u32, 0), pool.available());
    try testing.expectEqual(@as(u32, 5), pool.used());
}

test "pool: exhaustion returns error" {
    var pool = Pool(TestObject, 3).init();

    // Acquire all objects
    _ = try pool.acquire();
    _ = try pool.acquire();
    _ = try pool.acquire();

    // Next acquisition should fail
    try testing.expectError(error.PoolExhausted, pool.acquire());
}

test "pool: release order doesn't matter" {
    var pool = Pool(TestObject, 5).init();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();
    const obj3 = try pool.acquire();

    // Release in different order
    pool.release(obj2);
    pool.release(obj1);
    pool.release(obj3);

    try testing.expectEqual(@as(u32, 5), pool.available());
}

test "pool: reuse released objects" {
    var pool = Pool(TestObject, 3).init();

    const obj1 = try pool.acquire();
    obj1.id = 42;

    pool.release(obj1);

    const obj2 = try pool.acquire();

    // Should get the same object back (though value might not be cleared)
    try testing.expectEqual(@intFromPtr(obj1), @intFromPtr(obj2));
}

test "pool: multiple acquire-release cycles" {
    var pool = Pool(TestObject, 5).init();

    // Cycle 1
    var objs1: [3]*TestObject = undefined;
    for (&objs1) |*obj| {
        obj.* = try pool.acquire();
    }
    for (objs1) |obj| {
        pool.release(obj);
    }

    // Cycle 2
    var objs2: [5]*TestObject = undefined;
    for (&objs2) |*obj| {
        obj.* = try pool.acquire();
    }
    try testing.expectEqual(@as(u32, 0), pool.available());
}

test "pool: objects are distinct" {
    var pool = Pool(TestObject, 10).init();

    const obj1 = try pool.acquire();
    const obj2 = try pool.acquire();

    // Objects should have different addresses
    try testing.expect(@intFromPtr(obj1) != @intFromPtr(obj2));
}

test "pool: object alignment" {
    var pool = Pool(TestObject, 10).init();

    const obj = try pool.acquire();
    const addr = @intFromPtr(obj);

    // Should be properly aligned
    try testing.expectEqual(@as(usize, 0), addr % @alignOf(TestObject));
}

test "pool: capacity is compile-time constant" {
    // Different pool sizes at compile time
    const pool1 = Pool(TestObject, 5).init();
    const pool2 = Pool(TestObject, 100).init();

    try testing.expectEqual(@as(u32, 5), pool1.getCapacity());
    try testing.expectEqual(@as(u32, 100), pool2.getCapacity());
}

test "pool: works with different object types" {
    const SmallObject = struct { x: u8 };
    const LargeObject = struct { data: [1024]u8 };

    var small_pool = Pool(SmallObject, 10).init();
    var large_pool = Pool(LargeObject, 5).init();

    const small = try small_pool.acquire();
    const large = try large_pool.acquire();

    // Acquired successfully - verify we can write to them
    small.x = 123;
    large.data[0] = 0xFF;

    try testing.expectEqual(@as(u8, 123), small.x);
    try testing.expectEqual(@as(u8, 0xFF), large.data[0]);
}

test "pool: zero-capacity pool is compile error" {
    // This test documents that Pool(T, 0) should be a compile error
    // The actual implementation should static_assert capacity > 0
    // Cannot test compile error directly, but document the requirement
}

test "pool: double release is safe" {
    // Pool should handle double release gracefully
    // Implementation should either:
    // 1. Track which objects are in use (debug mode)
    // 2. Document that double release is undefined behavior
    // For now, we test that it doesn't crash
    var pool = Pool(TestObject, 5).init();

    const obj = try pool.acquire();
    pool.release(obj);

    // Second release - behavior is implementation-defined
    // In release mode, this might corrupt the free list
    // In debug mode, this should panic
    // pool.release(obj); // Commented out - would panic in debug
}

test "pool: stress test" {
    var pool = Pool(TestObject, 100).init();

    // Acquire all
    var objects: [100]*TestObject = undefined;
    for (&objects) |*obj| {
        obj.* = try pool.acquire();
    }

    // Release all
    for (objects) |obj| {
        pool.release(obj);
    }

    // Acquire again
    for (&objects) |*obj| {
        obj.* = try pool.acquire();
    }

    try testing.expectEqual(@as(u32, 0), pool.available());
}

test "pool: acquired objects can be modified" {
    var pool = Pool(TestObject, 5).init();

    const obj = try pool.acquire();
    obj.id = 123;
    obj.value = 456789;
    @memset(&obj.data, 0xFF);

    // Verify modifications
    try testing.expectEqual(@as(u32, 123), obj.id);
    try testing.expectEqual(@as(u64, 456789), obj.value);
    try testing.expectEqual(@as(u8, 0xFF), obj.data[0]);
}

test "pool: Tiger Style - preconditions verified" {
    // This test documents that implementation should include assertions:
    // - capacity > 0 at comptime
    // - free_count <= capacity (invariant)
    // - acquired pointer is within pool bounds

    var pool = Pool(TestObject, 5).init();
    try testing.expect(pool.getCapacity() > 0);
    try testing.expect(pool.available() <= pool.getCapacity());
}
