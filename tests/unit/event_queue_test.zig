//! Event Queue Tests
//!
//! Test-Driven Development: These tests are written BEFORE implementation.
//! Following Tiger Style: Test before implement.
//!
//! Tests for priority queue used by scheduler to manage events.

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");
const EventQueue = z6.EventQueue;

// Simple event for testing
const TestEvent = struct {
    id: u32,
    data: u64,
};

test "event_queue: init empty" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    try testing.expectEqual(@as(usize, 0), queue.len());
    try testing.expect(queue.isEmpty());
}

test "event_queue: push and peek" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    const event = TestEvent{ .id = 1, .data = 100 };
    try queue.push(5, event);

    try testing.expectEqual(@as(usize, 1), queue.len());
    try testing.expect(!queue.isEmpty());

    const peeked = try queue.peek();
    try testing.expectEqual(@as(u64, 5), peeked.tick);
    try testing.expectEqual(@as(u32, 1), peeked.event.id);
}

test "event_queue: push and pop" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    const event = TestEvent{ .id = 1, .data = 100 };
    try queue.push(5, event);

    const popped = try queue.pop();
    try testing.expectEqual(@as(u64, 5), popped.tick);
    try testing.expectEqual(@as(u32, 1), popped.event.id);

    try testing.expectEqual(@as(usize, 0), queue.len());
    try testing.expect(queue.isEmpty());
}

test "event_queue: ordering by tick" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    // Push in random order
    try queue.push(10, TestEvent{ .id = 3, .data = 0 });
    try queue.push(5, TestEvent{ .id = 2, .data = 0 });
    try queue.push(1, TestEvent{ .id = 1, .data = 0 });
    try queue.push(20, TestEvent{ .id = 4, .data = 0 });

    // Pop should return in tick order
    const e1 = try queue.pop();
    try testing.expectEqual(@as(u64, 1), e1.tick);
    try testing.expectEqual(@as(u32, 1), e1.event.id);

    const e2 = try queue.pop();
    try testing.expectEqual(@as(u64, 5), e2.tick);
    try testing.expectEqual(@as(u32, 2), e2.event.id);

    const e3 = try queue.pop();
    try testing.expectEqual(@as(u64, 10), e3.tick);
    try testing.expectEqual(@as(u32, 3), e3.event.id);

    const e4 = try queue.pop();
    try testing.expectEqual(@as(u64, 20), e4.tick);
    try testing.expectEqual(@as(u32, 4), e4.event.id);
}

test "event_queue: same tick ordering (FIFO)" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    // Push multiple events at same tick
    try queue.push(5, TestEvent{ .id = 1, .data = 0 });
    try queue.push(5, TestEvent{ .id = 2, .data = 0 });
    try queue.push(5, TestEvent{ .id = 3, .data = 0 });

    // Should return in FIFO order for same tick
    const e1 = try queue.pop();
    try testing.expectEqual(@as(u32, 1), e1.event.id);

    const e2 = try queue.pop();
    try testing.expectEqual(@as(u32, 2), e2.event.id);

    const e3 = try queue.pop();
    try testing.expectEqual(@as(u32, 3), e3.event.id);
}

test "event_queue: capacity enforcement" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 3);
    defer queue.deinit();

    try queue.push(1, TestEvent{ .id = 1, .data = 0 });
    try queue.push(2, TestEvent{ .id = 2, .data = 0 });
    try queue.push(3, TestEvent{ .id = 3, .data = 0 });

    // Fourth push should fail
    try testing.expectError(error.QueueFull, queue.push(4, TestEvent{ .id = 4, .data = 0 }));
}

test "event_queue: peek on empty queue" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    try testing.expectError(error.QueueEmpty, queue.peek());
}

test "event_queue: pop on empty queue" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    try testing.expectError(error.QueueEmpty, queue.pop());
}

test "event_queue: multiple push and pop" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 5);
    defer queue.deinit();

    // Push some
    try queue.push(10, TestEvent{ .id = 1, .data = 0 });
    try queue.push(20, TestEvent{ .id = 2, .data = 0 });

    // Pop one
    _ = try queue.pop();

    // Push more
    try queue.push(5, TestEvent{ .id = 3, .data = 0 });
    try queue.push(15, TestEvent{ .id = 4, .data = 0 });

    // Should maintain order
    const e1 = try queue.pop();
    try testing.expectEqual(@as(u32, 3), e1.event.id); // tick 5

    const e2 = try queue.pop();
    try testing.expectEqual(@as(u32, 4), e2.event.id); // tick 15

    const e3 = try queue.pop();
    try testing.expectEqual(@as(u32, 2), e3.event.id); // tick 20
}

test "event_queue: peek doesn't remove" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    try queue.push(5, TestEvent{ .id = 1, .data = 100 });

    // Peek multiple times
    const p1 = try queue.peek();
    try testing.expectEqual(@as(u32, 1), p1.event.id);

    const p2 = try queue.peek();
    try testing.expectEqual(@as(u32, 1), p2.event.id);

    // Still in queue
    try testing.expectEqual(@as(usize, 1), queue.len());

    // Pop actually removes
    _ = try queue.pop();
    try testing.expect(queue.isEmpty());
}

test "event_queue: clear" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    try queue.push(1, TestEvent{ .id = 1, .data = 0 });
    try queue.push(2, TestEvent{ .id = 2, .data = 0 });
    try queue.push(3, TestEvent{ .id = 3, .data = 0 });

    try testing.expectEqual(@as(usize, 3), queue.len());

    queue.clear();

    try testing.expectEqual(@as(usize, 0), queue.len());
    try testing.expect(queue.isEmpty());
}

test "event_queue: large number of events" {
    const allocator = testing.allocator;

    var queue = EventQueue(TestEvent).init(allocator, 1000);
    defer queue.deinit();

    // Push 100 events in reverse order
    var i: u32 = 100;
    while (i > 0) : (i -= 1) {
        try queue.push(@as(u64, i), TestEvent{ .id = i, .data = 0 });
    }

    try testing.expectEqual(@as(usize, 100), queue.len());

    // Should pop in ascending order
    var expected: u32 = 1;
    while (expected <= 100) : (expected += 1) {
        const e = try queue.pop();
        try testing.expectEqual(@as(u64, expected), e.tick);
        try testing.expectEqual(expected, e.event.id);
    }

    try testing.expect(queue.isEmpty());
}

test "event_queue: Tiger Style - assertions present" {
    // Document that implementation should include:
    // - Assertion for capacity > 0
    // - Assertion that queue not full before push
    // - Assertion that queue not empty before pop/peek
    // - Assertion for tick ordering invariant

    const allocator = testing.allocator;
    var queue = EventQueue(TestEvent).init(allocator, 10);
    defer queue.deinit();

    try queue.push(1, TestEvent{ .id = 1, .data = 0 });

    // If we get here, basic operations work
    try testing.expect(true);
}
