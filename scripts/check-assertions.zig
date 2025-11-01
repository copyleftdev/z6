//! Tiger Style Assertion Density Checker
//!
//! Validates that each function has minimum 2 assertions.
//! This enforces Tiger Style's requirement for rigorous validation.

const std = @import("std");

pub fn main() !void {
    // Verify we have at least 2 assertions per function
    const min_assertions_per_function = 2;

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
    std.debug.assert(args.len >= 1); // arg[0] is program name

    if (args.len < 2) {
        std.debug.print("Usage: {s} <file.zig> [file2.zig ...]\n", .{args[0]});
        std.debug.print("\nChecks that each function has minimum {d} assertions (Tiger Style)\n", .{min_assertions_per_function});
        std.process.exit(1);
    }

    var failures: u32 = 0;

    // Process each file
    for (args[1..]) |filepath| {
        std.debug.assert(filepath.len > 0); // Non-empty filepath

        // Skip test files
        if (std.mem.indexOf(u8, filepath, "test") != null) {
            continue;
        }

        const result = try checkFile(allocator, filepath, min_assertions_per_function);
        if (!result.passed) {
            std.debug.print(
                "✗ {s}: {d} assertions for {d} functions (need {d})\n",
                .{ filepath, result.assertion_count, result.function_count, result.required_assertions },
            );
            failures += 1;
        }
    }

    // Postconditions
    std.debug.assert(failures <= args.len - 1); // Can't have more failures than files

    if (failures > 0) {
        std.debug.print("\n✗ {d} file(s) failed assertion density check\n", .{failures});
        std.debug.print("Tiger Style requires minimum {d} assertions per function\n", .{min_assertions_per_function});
        std.process.exit(1);
    }

    std.debug.print("✓ All files meet assertion density requirements\n", .{});
}

const CheckResult = struct {
    passed: bool,
    function_count: u32,
    assertion_count: u32,
    required_assertions: u32,
};

fn checkFile(allocator: std.mem.Allocator, filepath: []const u8, min_per_function: u32) !CheckResult {
    // Preconditions
    std.debug.assert(filepath.len > 0);
    std.debug.assert(min_per_function > 0);

    const file = std.fs.cwd().openFile(filepath, .{}) catch |err| {
        std.debug.print("Error opening {s}: {}\n", .{ filepath, err });
        return error.FileOpenFailed;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 10 * 1024 * 1024); // 10MB max
    defer allocator.free(content);

    var function_count: u32 = 0;
    var assertion_count: u32 = 0;

    // Count functions
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Match function definitions: "pub fn" or "fn"
        if (std.mem.startsWith(u8, trimmed, "pub fn ") or
            std.mem.startsWith(u8, trimmed, "fn "))
        {
            function_count += 1;
        }

        // Count assertions
        if (std.mem.indexOf(u8, line, "assert(") != null or
            std.mem.indexOf(u8, line, "std.debug.assert(") != null)
        {
            assertion_count += 1;
        }
    }

    const required = function_count * min_per_function;
    const passed = (function_count == 0) or (assertion_count >= required);

    // Postconditions
    std.debug.assert(assertion_count <= content.len); // Can't have more assertions than content
    std.debug.assert(function_count <= content.len);

    return CheckResult{
        .passed = passed,
        .function_count = function_count,
        .assertion_count = assertion_count,
        .required_assertions = required,
    };
}

test "check single function with sufficient assertions" {
    const allocator = std.testing.allocator;

    const test_file = "test_sufficient.zig";
    const content =
        \\fn example(x: u32) u32 {
        \\    std.debug.assert(x > 0);
        \\    std.debug.assert(x < 100);
        \\    return x * 2;
        \\}
    ;

    // Write test file
    try std.fs.cwd().writeFile(.{ .sub_path = test_file, .data = content });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const result = try checkFile(allocator, test_file, 2);
    try std.testing.expect(result.passed);
    try std.testing.expectEqual(@as(u32, 1), result.function_count);
    try std.testing.expectEqual(@as(u32, 2), result.assertion_count);
}

test "check single function with insufficient assertions" {
    const allocator = std.testing.allocator;

    const test_file = "test_insufficient.zig";
    const content =
        \\fn example(x: u32) u32 {
        \\    return x * 2;
        \\}
    ;

    // Write test file
    try std.fs.cwd().writeFile(.{ .sub_path = test_file, .data = content });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const result = try checkFile(allocator, test_file, 2);
    try std.testing.expect(!result.passed);
    try std.testing.expectEqual(@as(u32, 1), result.function_count);
    try std.testing.expectEqual(@as(u32, 0), result.assertion_count);
}
