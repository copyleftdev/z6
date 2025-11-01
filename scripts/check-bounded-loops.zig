//! Tiger Style Bounded Loop Checker
//!
//! Validates that all loops are bounded or explicitly marked as intentional infinite loops.
//! Infinite loops must be followed by `unreachable` or `assert` to document intent.

const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected!\n", .{});
        }
    }

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Preconditions
    std.debug.assert(args.len >= 1);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file.zig> [file2.zig ...]\n", .{args[0]});
        std.debug.print("\nChecks that all while(true) loops are followed by unreachable/assert (Tiger Style)\n", .{});
        std.process.exit(1);
    }

    var failures: u32 = 0;

    for (args[1..]) |filepath| {
        std.debug.assert(filepath.len > 0);

        const unbounded = try checkFile(allocator, filepath);
        if (unbounded > 0) {
            failures += 1;
        }
    }

    // Postcondition
    std.debug.assert(failures <= args.len - 1);

    if (failures > 0) {
        std.debug.print("\n✗ {d} file(s) contain unbounded loops\n", .{failures});
        std.debug.print("All loops must be bounded or followed by unreachable/assert\n", .{});
        std.process.exit(1);
    }

    std.debug.print("✓ All loops are properly bounded or marked\n", .{});
}

fn checkFile(allocator: std.mem.Allocator, filepath: []const u8) !u32 {
    // Preconditions
    std.debug.assert(filepath.len > 0);

    const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
        std.debug.print("Error opening {s}: {}\n", .{ filepath, err });
        return error.FileOpenFailed;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    var unbounded_count: u32 = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');
    var lines_buffer = std.ArrayList([]const u8){};
    try lines_buffer.ensureTotalCapacity(allocator, 100);
    defer lines_buffer.deinit(allocator);

    // Store all lines for context checking
    while (lines.next()) |line| {
        try lines_buffer.append(allocator, line);
    }

    // Check each line
    for (lines_buffer.items, 0..) |line, idx| {
        if (std.mem.indexOf(u8, line, "while (true)") != null or
            std.mem.indexOf(u8, line, "while(true)") != null)
        {
            // Check next 5 lines for unreachable/assert/@panic
            var found_marker = false;
            const check_range = @min(5, lines_buffer.items.len - idx - 1);

            for (0..check_range) |offset| {
                const next_line = lines_buffer.items[idx + offset + 1];
                if (std.mem.indexOf(u8, next_line, "unreachable") != null or
                    std.mem.indexOf(u8, next_line, "assert(") != null or
                    std.mem.indexOf(u8, next_line, "std.debug.assert(") != null or
                    std.mem.indexOf(u8, next_line, "@panic(") != null)
                {
                    found_marker = true;
                    break;
                }
            }

            if (!found_marker) {
                const line_num = @as(u32, @intCast(idx + 1)); // 1-indexed line number
                std.debug.print(
                    "✗ {s}:{d}: unbounded while(true) without unreachable/assert\n",
                    .{ filepath, line_num },
                );
                unbounded_count += 1;
            }
        }
    }

    // Postcondition
    std.debug.assert(unbounded_count <= lines_buffer.items.len);

    return unbounded_count;
}

test "detect unbounded while true loop" {
    const allocator = std.testing.allocator;

    const test_file = "test_unbounded.zig";
    const content =
        \\fn bad_loop() void {
        \\    while (true) {
        \\        do_something();
        \\    }
        \\}
    ;

    try std.fs.cwd().writeFile(.{ .sub_path = test_file, .data = content });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const unbounded = try checkFile(allocator, test_file);
    try std.testing.expectEqual(@as(u32, 1), unbounded);
}

test "accept bounded loop with unreachable" {
    const allocator = std.testing.allocator;

    const test_file = "test_bounded.zig";
    const content =
        \\fn event_loop() void {
        \\    while (true) {
        \\        process_events();
        \\    }
        \\    unreachable;
        \\}
    ;

    try std.fs.cwd().writeFile(.{ .sub_path = test_file, .data = content });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const unbounded = try checkFile(allocator, test_file);
    try std.testing.expectEqual(@as(u32, 0), unbounded);
}

test "accept bounded loop with assert" {
    const allocator = std.testing.allocator;

    const test_file = "test_bounded_assert.zig";
    const content =
        \\fn event_loop() void {
        \\    while (true) {
        \\        process_events();
        \\    }
        \\    std.debug.assert(false); // Should never reach here
        \\}
    ;

    try std.fs.cwd().writeFile(.{ .sub_path = test_file, .data = content });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const unbounded = try checkFile(allocator, test_file);
    try std.testing.expectEqual(@as(u32, 0), unbounded);
}
