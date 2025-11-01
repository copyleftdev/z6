//! Memory Budget Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const Memory = z6.Memory;

test "memory: default budget initialization" {
    var mem = Memory.init();
    defer mem.deinit();

    // Default budget should be 16 GB (MEMORY_MODEL.md)
    const expected_budget: usize = 16 * 1024 * 1024 * 1024; // 16 GB
    try testing.expectEqual(expected_budget, mem.totalBudget());
    try testing.expectEqual(@as(usize, 0), mem.used());
    try testing.expectEqual(expected_budget, mem.remaining());
}

test "memory: custom budget initialization" {
    const custom_budget: usize = 1024 * 1024 * 1024; // 1 GB
    var mem = Memory.initWithBudget(custom_budget);
    defer mem.deinit();

    try testing.expectEqual(custom_budget, mem.totalBudget());
    try testing.expectEqual(@as(usize, 0), mem.used());
    try testing.expectEqual(custom_budget, mem.remaining());
}

test "memory: allocate within budget" {
    var mem = Memory.initWithBudget(1024 * 1024); // 1 MB budget
    defer mem.deinit();

    // Allocate 512 KB - should succeed
    const size: usize = 512 * 1024;
    const allocation = try mem.allocate(size);
    defer mem.free(allocation);

    try testing.expectEqual(size, mem.used());
    try testing.expectEqual(1024 * 1024 - size, mem.remaining());
}

test "memory: allocate exceeds budget" {
    var mem = Memory.initWithBudget(1024 * 1024); // 1 MB budget
    defer mem.deinit();

    // Try to allocate 2 MB - should fail
    const size: usize = 2 * 1024 * 1024;
    try testing.expectError(error.OutOfMemory, mem.allocate(size));

    // Memory usage should be unchanged
    try testing.expectEqual(@as(usize, 0), mem.used());
}

test "memory: multiple allocations track correctly" {
    var mem = Memory.initWithBudget(10 * 1024 * 1024); // 10 MB
    defer mem.deinit();

    const alloc1 = try mem.allocate(1024 * 1024); // 1 MB
    defer mem.free(alloc1);
    try testing.expectEqual(@as(usize, 1024 * 1024), mem.used());

    const alloc2 = try mem.allocate(2 * 1024 * 1024); // 2 MB
    defer mem.free(alloc2);
    try testing.expectEqual(@as(usize, 3 * 1024 * 1024), mem.used());

    const alloc3 = try mem.allocate(512 * 1024); // 512 KB
    defer mem.free(alloc3);
    try testing.expectEqual(@as(usize, 3 * 1024 * 1024 + 512 * 1024), mem.used());
}

test "memory: free reduces usage" {
    var mem = Memory.initWithBudget(10 * 1024 * 1024); // 10 MB
    defer mem.deinit();

    const alloc1 = try mem.allocate(2 * 1024 * 1024);
    const alloc2 = try mem.allocate(3 * 1024 * 1024);

    try testing.expectEqual(@as(usize, 5 * 1024 * 1024), mem.used());

    mem.free(alloc1);
    try testing.expectEqual(@as(usize, 3 * 1024 * 1024), mem.used());

    mem.free(alloc2);
    try testing.expectEqual(@as(usize, 0), mem.used());
}

test "memory: allocate after free reuses budget" {
    var mem = Memory.initWithBudget(1024 * 1024); // 1 MB
    defer mem.deinit();

    // Allocate all budget
    const alloc1 = try mem.allocate(1024 * 1024);
    try testing.expectEqual(@as(usize, 0), mem.remaining());

    // Free it
    mem.free(alloc1);
    try testing.expectEqual(@as(usize, 1024 * 1024), mem.remaining());

    // Can allocate again
    const alloc2 = try mem.allocate(1024 * 1024);
    defer mem.free(alloc2);
    try testing.expectEqual(@as(usize, 0), mem.remaining());
}

test "memory: peak usage tracking" {
    var mem = Memory.initWithBudget(10 * 1024 * 1024); // 10 MB
    defer mem.deinit();

    const alloc1 = try mem.allocate(5 * 1024 * 1024);
    try testing.expectEqual(@as(usize, 5 * 1024 * 1024), mem.peakUsage());

    const alloc2 = try mem.allocate(3 * 1024 * 1024);
    try testing.expectEqual(@as(usize, 8 * 1024 * 1024), mem.peakUsage());

    mem.free(alloc1);
    // Peak should remain at 8 MB even after free
    try testing.expectEqual(@as(usize, 8 * 1024 * 1024), mem.peakUsage());

    mem.free(alloc2);
    try testing.expectEqual(@as(usize, 8 * 1024 * 1024), mem.peakUsage());
}

test "memory: allocation count tracking" {
    var mem = Memory.initWithBudget(10 * 1024 * 1024);
    defer mem.deinit();

    try testing.expectEqual(@as(usize, 0), mem.allocationCount());

    const alloc1 = try mem.allocate(1024);
    try testing.expectEqual(@as(usize, 1), mem.allocationCount());

    const alloc2 = try mem.allocate(2048);
    try testing.expectEqual(@as(usize, 2), mem.allocationCount());

    mem.free(alloc1);
    try testing.expectEqual(@as(usize, 1), mem.allocationCount());

    mem.free(alloc2);
    try testing.expectEqual(@as(usize, 0), mem.allocationCount());
}

test "memory: zero-size allocation fails" {
    var mem = Memory.initWithBudget(1024 * 1024);
    defer mem.deinit();

    try testing.expectError(error.InvalidSize, mem.allocate(0));
}

test "memory: alignment guarantees" {
    var mem = Memory.initWithBudget(10 * 1024 * 1024);
    defer mem.deinit();

    const alloc = try mem.allocate(100);
    defer mem.free(alloc);

    // Should be at least 8-byte aligned (MEMORY_MODEL.md requirement)
    const addr = @intFromPtr(alloc.ptr);
    try testing.expectEqual(@as(usize, 0), addr % 8);
}

test "memory: VU memory budget" {
    // Per-VU memory: 64 KB (MEMORY_MODEL.md)
    const vu_memory_size: usize = 64 * 1024;

    var mem = Memory.initWithBudget(100 * vu_memory_size); // 100 VUs
    defer mem.deinit();

    // Allocate memory for 10 VUs
    var vu_allocations: [10][]u8 = undefined;
    for (&vu_allocations) |*alloc| {
        alloc.* = try mem.allocate(vu_memory_size);
    }

    try testing.expectEqual(10 * vu_memory_size, mem.used());

    // Free all
    for (vu_allocations) |alloc| {
        mem.free(alloc);
    }
}

test "memory: event log memory budget" {
    // Event log memory: 2.7 GB for 10M events (MEMORY_MODEL.md)
    const event_size: usize = 272; // bytes per event
    const max_events: usize = 10_000_000;
    const event_log_size: usize = event_size * max_events;

    var mem = Memory.initWithBudget(3 * 1024 * 1024 * 1024); // 3 GB budget
    defer mem.deinit();

    const event_log = try mem.allocate(event_log_size);
    defer mem.free(event_log);

    // Should fit within budget
    try testing.expect(mem.used() <= mem.totalBudget());
}

test "memory: budget enforcement prevents overflow" {
    var mem = Memory.initWithBudget(1000);
    defer mem.deinit();

    const alloc1 = try mem.allocate(400);
    const alloc2 = try mem.allocate(400);

    // Should have 200 bytes remaining
    try testing.expectEqual(@as(usize, 200), mem.remaining());

    // Try to allocate 300 - should fail
    try testing.expectError(error.OutOfMemory, mem.allocate(300));

    // But 200 should succeed
    const alloc3 = try mem.allocate(200);

    mem.free(alloc1);
    mem.free(alloc2);
    mem.free(alloc3);
}

test "memory: statistics reporting" {
    var mem = Memory.initWithBudget(10 * 1024 * 1024);
    defer mem.deinit();

    const alloc1 = try mem.allocate(3 * 1024 * 1024);
    const alloc2 = try mem.allocate(2 * 1024 * 1024);

    const stats = mem.getStats();

    try testing.expectEqual(@as(usize, 10 * 1024 * 1024), stats.total_budget);
    try testing.expectEqual(@as(usize, 5 * 1024 * 1024), stats.used);
    try testing.expectEqual(@as(usize, 5 * 1024 * 1024), stats.remaining);
    try testing.expectEqual(@as(usize, 5 * 1024 * 1024), stats.peak_usage);
    try testing.expectEqual(@as(usize, 2), stats.allocation_count);

    mem.free(alloc1);
    mem.free(alloc2);
}

test "memory: Tiger Style - preconditions verified" {
    // This test documents that implementation should include assertions:
    // - budget > 0 on init
    // - size > 0 on allocate
    // - pointer is valid on free
    // - used <= total_budget (invariant)

    var mem = Memory.initWithBudget(1024 * 1024);
    defer mem.deinit();

    try testing.expect(mem.totalBudget() > 0);
    try testing.expect(mem.used() <= mem.totalBudget());
    try testing.expect(mem.remaining() <= mem.totalBudget());
}

test "memory: no allocations after deinit" {
    // Document that using Memory after deinit is undefined behavior
    // In debug mode, should panic
    // This is a documentation test - actual test would cause panic
}
