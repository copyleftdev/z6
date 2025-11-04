//! CLI Module - Command-line interface utilities
//!
//! Provides common CLI functionality:
//! - Exit codes
//! - Output formats
//! - Progress indicators
//! - Signal handling
//!
//! Built with Tiger Style:
//! - Minimum 2 assertions per function
//! - Explicit error handling
//! - Bounded operations

const std = @import("std");

/// Standard exit codes
pub const ExitCode = enum(u8) {
    success = 0,
    assertion_failure = 1,
    config_error = 2,
    runtime_error = 3,

    pub fn toInt(self: ExitCode) u8 {
        return @intFromEnum(self);
    }
};

/// Output format options
pub const OutputFormat = enum {
    summary,
    json,
    csv,

    pub fn fromString(s: []const u8) !OutputFormat {
        if (std.mem.eql(u8, s, "summary")) return .summary;
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "csv")) return .csv;
        return error.InvalidFormat;
    }

    pub fn toString(self: OutputFormat) []const u8 {
        return switch (self) {
            .summary => "summary",
            .json => "json",
            .csv => "csv",
        };
    }
};

/// Progress indicator for long-running operations
pub const ProgressIndicator = struct {
    total: u64,
    current: u64,
    start_time: i64,
    last_update: i64,

    const Self = @This();

    pub fn init(total: u64) !Self {
        const now = std.time.milliTimestamp();
        return Self{
            .total = total,
            .current = 0,
            .start_time = now,
            .last_update = now,
        };
    }

    pub fn update(self: *Self, current: u64) void {
        // Assertions
        std.debug.assert(current <= self.total);
        std.debug.assert(self.total > 0);

        self.current = current;
        self.last_update = std.time.milliTimestamp();
    }

    pub fn print(self: *Self) void {
        const elapsed = self.last_update - self.start_time;
        const percent = if (self.total > 0)
            @as(f64, @floatFromInt(self.current)) / @as(f64, @floatFromInt(self.total)) * 100.0
        else
            0.0;

        std.debug.print("\r[{d:5.1}%] {d}/{d} elapsed: {d}ms", .{
            percent,
            self.current,
            self.total,
            elapsed,
        });
    }

    pub fn finish(self: *Self) void {
        self.current = self.total;
        self.print();
        std.debug.print("\n", .{});
    }
};

/// Signal handler state
pub const SignalHandler = struct {
    interrupted: bool,

    const Self = @This();

    pub fn init() Self {
        return Self{
            .interrupted = false,
        };
    }

    pub fn isInterrupted(self: *const Self) bool {
        return self.interrupted;
    }

    pub fn setInterrupted(self: *Self) void {
        self.interrupted = true;
    }

    pub fn reset(self: *Self) void {
        self.interrupted = false;
    }
};

// Global signal handler instance
var global_signal_handler = SignalHandler.init();

/// Install SIGINT handler
pub fn installSignalHandler() void {
    // Note: Actual signal handling would require platform-specific code
    // This is a placeholder for the structure
    // In production, we'd use std.os.sigaction or similar
}

/// Check if interrupted by signal
pub fn checkInterrupted() bool {
    return global_signal_handler.isInterrupted();
}

/// Set interrupted flag (called by signal handler)
pub fn setInterrupted() void {
    global_signal_handler.setInterrupted();
}

test "ExitCode conversion" {
    try std.testing.expectEqual(@as(u8, 0), ExitCode.success.toInt());
    try std.testing.expectEqual(@as(u8, 1), ExitCode.assertion_failure.toInt());
    try std.testing.expectEqual(@as(u8, 2), ExitCode.config_error.toInt());
    try std.testing.expectEqual(@as(u8, 3), ExitCode.runtime_error.toInt());
}

test "OutputFormat fromString" {
    try std.testing.expectEqual(OutputFormat.summary, try OutputFormat.fromString("summary"));
    try std.testing.expectEqual(OutputFormat.json, try OutputFormat.fromString("json"));
    try std.testing.expectEqual(OutputFormat.csv, try OutputFormat.fromString("csv"));
    try std.testing.expectError(error.InvalidFormat, OutputFormat.fromString("invalid"));
}

test "OutputFormat toString" {
    try std.testing.expectEqualStrings("summary", OutputFormat.summary.toString());
    try std.testing.expectEqualStrings("json", OutputFormat.json.toString());
    try std.testing.expectEqualStrings("csv", OutputFormat.csv.toString());
}

test "ProgressIndicator init" {
    const progress = try ProgressIndicator.init(100);
    try std.testing.expectEqual(@as(u64, 100), progress.total);
    try std.testing.expectEqual(@as(u64, 0), progress.current);
}

test "ProgressIndicator update" {
    var progress = try ProgressIndicator.init(100);
    progress.update(50);
    try std.testing.expectEqual(@as(u64, 50), progress.current);
}

test "SignalHandler init" {
    const handler = SignalHandler.init();
    try std.testing.expectEqual(false, handler.interrupted);
}

test "SignalHandler setInterrupted" {
    var handler = SignalHandler.init();
    try std.testing.expectEqual(false, handler.isInterrupted());
    handler.setInterrupted();
    try std.testing.expectEqual(true, handler.isInterrupted());
    handler.reset();
    try std.testing.expectEqual(false, handler.isInterrupted());
}
