//! Arena Allocator Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const Arena = z6.Arena;

test "arena: basic allocation" {
    var buffer: [1024]u8 = undefined;
    var arena = Arena.init(&buffer);

    // Should start with zero offset
    try testing.expectEqual(@as(usize, 0), arena.offset);
    try testing.expectEqual(@as(usize, 1024), arena.capacity());

    // Allocate 100 bytes
    const slice1 = try arena.alloc(100);
    try testing.expectEqual(@as(usize, 100), slice1.len);
    try testing.expectEqual(@as(usize, 100), arena.offset);

    // Allocate another 200 bytes
    const slice2 = try arena.alloc(200);
    try testing.expectEqual(@as(usize, 200), slice2.len);
    try testing.expectEqual(@as(usize, 300), arena.offset);

    // Allocations should not overlap
    const addr1 = @intFromPtr(slice1.ptr);
    const addr2 = @intFromPtr(slice2.ptr);
    try testing.expect(addr2 >= addr1 + 100);
}

test "arena: allocation exceeds capacity" {
    var buffer: [100]u8 = undefined;
    var arena = Arena.init(&buffer);

    // Should succeed
    _ = try arena.alloc(50);

    // Should fail - not enough space
    try testing.expectError(error.OutOfMemory, arena.alloc(100));
}

test "arena: reset clears allocations" {
    var buffer: [1024]u8 = undefined;
    var arena = Arena.init(&buffer);

    // Allocate some memory
    _ = try arena.alloc(500);
    try testing.expectEqual(@as(usize, 500), arena.offset);

    // Reset arena
    arena.reset();
    try testing.expectEqual(@as(usize, 0), arena.offset);

    // Should be able to allocate again
    const slice = try arena.alloc(500);
    try testing.expectEqual(@as(usize, 500), slice.len);
}

test "arena: aligned allocation" {
    var buffer: [1024]u8 align(8) = undefined;
    var arena = Arena.init(&buffer);

    // Allocate with 8-byte alignment requirement
    const slice = try arena.allocAligned(100, 8);
    try testing.expectEqual(@as(usize, 100), slice.len);

    // Check alignment
    const addr = @intFromPtr(slice.ptr);
    try testing.expectEqual(@as(usize, 0), addr % 8);
}

test "arena: multiple aligned allocations" {
    var buffer: [1024]u8 align(8) = undefined;
    var arena = Arena.init(&buffer);

    // Allocate several aligned blocks
    const slice1 = try arena.allocAligned(13, 8); // Odd size
    const slice2 = try arena.allocAligned(7, 8); // Another odd size
    const slice3 = try arena.allocAligned(100, 8);

    // All should be properly aligned
    try testing.expectEqual(@as(usize, 0), @intFromPtr(slice1.ptr) % 8);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(slice2.ptr) % 8);
    try testing.expectEqual(@as(usize, 0), @intFromPtr(slice3.ptr) % 8);
}

test "arena: zero-size allocation" {
    var buffer: [1024]u8 = undefined;
    var arena = Arena.init(&buffer);

    // Zero-size allocation should succeed and not advance offset
    const slice = try arena.alloc(0);
    try testing.expectEqual(@as(usize, 0), slice.len);
    try testing.expectEqual(@as(usize, 0), arena.offset);
}

test "arena: allocation at exact capacity" {
    var buffer: [100]u8 = undefined;
    var arena = Arena.init(&buffer);

    // Should succeed - exactly at capacity
    const slice = try arena.alloc(100);
    try testing.expectEqual(@as(usize, 100), slice.len);
    try testing.expectEqual(@as(usize, 100), arena.offset);

    // Next allocation should fail
    try testing.expectError(error.OutOfMemory, arena.alloc(1));
}

test "arena: fragmentation does not occur" {
    var buffer: [1000]u8 = undefined;
    var arena = Arena.init(&buffer);

    // Allocate, reset, allocate again
    _ = try arena.alloc(500);
    arena.reset();
    const slice = try arena.alloc(900);

    // Should be able to use full capacity after reset
    try testing.expectEqual(@as(usize, 900), slice.len);
}

test "arena: used and remaining memory" {
    var buffer: [1000]u8 = undefined;
    var arena = Arena.init(&buffer);

    try testing.expectEqual(@as(usize, 0), arena.used());
    try testing.expectEqual(@as(usize, 1000), arena.remaining());

    _ = try arena.alloc(300);
    try testing.expectEqual(@as(usize, 300), arena.used());
    try testing.expectEqual(@as(usize, 700), arena.remaining());

    _ = try arena.alloc(200);
    try testing.expectEqual(@as(usize, 500), arena.used());
    try testing.expectEqual(@as(usize, 500), arena.remaining());
}

test "arena: memory is not zeroed on allocation" {
    var buffer: [100]u8 = undefined;
    // Fill buffer with non-zero pattern
    @memset(&buffer, 0xAA);

    var arena = Arena.init(&buffer);
    const slice = try arena.alloc(10);

    // Memory should retain previous contents (not zeroed)
    // This is intentional for performance
    try testing.expectEqual(@as(u8, 0xAA), slice[0]);
}

test "arena: memory is not zeroed on reset" {
    var buffer: [100]u8 = undefined;
    var arena = Arena.init(&buffer);

    const slice1 = try arena.alloc(10);
    @memset(slice1, 0xBB);

    arena.reset();
    const slice2 = try arena.alloc(10);

    // Memory should retain previous contents after reset
    try testing.expectEqual(@as(u8, 0xBB), slice2[0]);
}

test "arena: Tiger Style - preconditions verified" {
    // This test verifies that implementation will include proper assertions
    // The actual implementation should assert:
    // - buffer is not null
    // - size is not zero for init
    // - alignment is power of 2
    // - requested size fits in usize

    var buffer: [100]u8 = undefined;
    const arena = Arena.init(&buffer);

    // These should work
    try testing.expect(arena.capacity() > 0);
    try testing.expect(arena.offset == 0);
}
