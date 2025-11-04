//! Z6 Scenario Parser
//!
//! Parses TOML scenario files for load testing.
//! Focused implementation for Z6 scenario format only.
//!
//! Tiger Style:
//! - All loops bounded
//! - Minimum 2 assertions per function
//! - Explicit error handling

const std = @import("std");
const protocol = @import("protocol.zig");

const Allocator = std.mem.Allocator;
const Method = protocol.Method;

/// Maximum scenario file size (10 MB)
pub const MAX_SCENARIO_SIZE: usize = 10 * 1024 * 1024;

/// Maximum number of requests in a scenario
pub const MAX_REQUESTS: usize = 1000;

/// Scenario parsing errors
pub const ScenarioError = error{
    FileTooLarge,
    InvalidFormat,
    MissingRequiredField,
    InvalidValue,
    TooManyRequests,
};

/// Scenario metadata
pub const Metadata = struct {
    name: []const u8,
    version: []const u8,
    description: ?[]const u8,
};

/// Runtime configuration
pub const Runtime = struct {
    duration_seconds: u32,
    vus: u32,
    prng_seed: ?u64,
};

/// Scenario target configuration
pub const ScenarioTarget = struct {
    base_url: []const u8,
    http_version: []const u8, // "http1.1" or "http2"
    tls: bool,
};

/// Request definition
pub const RequestDef = struct {
    name: []const u8,
    method: Method,
    path: []const u8,
    timeout_ms: u32,
    headers: []const protocol.Header,
    body: ?[]const u8,
    weight: f32,
};

/// Schedule type
pub const ScheduleType = enum {
    constant,
    ramp,
    spike,
    steps,
};

/// Schedule configuration
pub const Schedule = struct {
    schedule_type: ScheduleType,
    vus: u32,
};

/// Assertions
pub const Assertions = struct {
    p99_latency_ms: ?u32,
    error_rate_max: ?f32,
    success_rate_min: ?f32,
};

/// Complete scenario
pub const Scenario = struct {
    allocator: Allocator,
    metadata: Metadata,
    runtime: Runtime,
    target: ScenarioTarget,
    requests: []RequestDef,
    schedule: Schedule,
    assertions: Assertions,

    /// Free scenario resources
    pub fn deinit(self: *Scenario) void {
        self.allocator.free(self.requests);
    }
};

/// Simple key-value parser for TOML subset
pub const ScenarioParser = struct {
    allocator: Allocator,
    content: []const u8,
    pos: usize,

    /// Initialize parser
    pub fn init(allocator: Allocator, content: []const u8) !ScenarioParser {
        // Preconditions
        std.debug.assert(content.len > 0); // Must have content
        std.debug.assert(content.len <= MAX_SCENARIO_SIZE); // Within limit

        if (content.len > MAX_SCENARIO_SIZE) {
            return ScenarioError.FileTooLarge;
        }

        // Postconditions
        const parser = ScenarioParser{
            .allocator = allocator,
            .content = content,
            .pos = 0,
        };
        std.debug.assert(parser.pos == 0); // Started at beginning
        std.debug.assert(parser.content.len <= MAX_SCENARIO_SIZE); // Valid

        return parser;
    }

    /// Parse complete scenario
    pub fn parse(self: *ScenarioParser) !Scenario {
        // Preconditions
        std.debug.assert(self.content.len > 0); // Must have content
        std.debug.assert(self.pos < self.content.len or self.pos == 0); // Valid position

        // Parse sections (simplified)
        const metadata = try self.parseMetadata();
        const runtime = try self.parseRuntime();
        const target = try self.parseTarget();
        const requests = try self.parseRequests();
        const schedule = try self.parseSchedule();
        const assertions = try self.parseAssertions();

        const scenario = Scenario{
            .allocator = self.allocator,
            .metadata = metadata,
            .runtime = runtime,
            .target = target,
            .requests = requests,
            .schedule = schedule,
            .assertions = assertions,
        };

        // Postconditions
        std.debug.assert(scenario.requests.len > 0); // At least one request
        std.debug.assert(scenario.requests.len <= MAX_REQUESTS); // Within limit

        return scenario;
    }

    /// Parse [metadata] section
    fn parseMetadata(self: *ScenarioParser) !Metadata {
        // Simplified: look for name and version
        const name = try self.findValue("[metadata]", "name");
        const version = try self.findValue("[metadata]", "version");

        return Metadata{
            .name = name,
            .version = version,
            .description = null,
        };
    }

    /// Parse [runtime] section
    fn parseRuntime(self: *ScenarioParser) !Runtime {
        const duration = try self.findIntValue("[runtime]", "duration_seconds");
        const vus = try self.findIntValue("[runtime]", "vus");

        return Runtime{
            .duration_seconds = @intCast(duration),
            .vus = @intCast(vus),
            .prng_seed = null, // Optional
        };
    }

    /// Parse [target] section
    fn parseTarget(self: *ScenarioParser) !ScenarioTarget {
        const base_url = try self.findValue("[target]", "base_url");
        const http_version = try self.findValue("[target]", "http_version");

        return ScenarioTarget{
            .base_url = base_url,
            .http_version = http_version,
            .tls = false, // Simplified
        };
    }

    /// Parse [[requests]] sections
    fn parseRequests(self: *ScenarioParser) ![]RequestDef {
        var requests = try std.ArrayList(RequestDef).initCapacity(self.allocator, 10);
        errdefer requests.deinit(self.allocator);

        // Simplified: parse first request only for MVP
        const name = try self.findValue("[[requests]]", "name");
        const method_str = try self.findValue("[[requests]]", "method");
        const path = try self.findValue("[[requests]]", "path");
        const timeout = try self.findIntValue("[[requests]]", "timeout_ms");

        const method = std.meta.stringToEnum(Method, method_str) orelse
            return ScenarioError.InvalidValue;

        const request = RequestDef{
            .name = name,
            .method = method,
            .path = path,
            .timeout_ms = @intCast(timeout),
            .headers = &[_]protocol.Header{},
            .body = null,
            .weight = 1.0,
        };

        try requests.append(self.allocator, request);

        return try requests.toOwnedSlice(self.allocator);
    }

    /// Parse [schedule] section
    fn parseSchedule(self: *ScenarioParser) !Schedule {
        const schedule_type_str = try self.findValue("[schedule]", "type");
        const vus = try self.findIntValue("[schedule]", "vus");

        const schedule_type = std.meta.stringToEnum(ScheduleType, schedule_type_str) orelse
            return ScenarioError.InvalidValue;

        return Schedule{
            .schedule_type = schedule_type,
            .vus = @intCast(vus),
        };
    }

    /// Parse [assertions] section
    fn parseAssertions(self: *ScenarioParser) !Assertions {
        // Optional fields - simplified for MVP
        _ = self; // Will be used when parsing assertions
        return Assertions{
            .p99_latency_ms = null,
            .error_rate_max = null,
            .success_rate_min = null,
        };
    }

    /// Find string value in section
    fn findValue(self: *ScenarioParser, section: []const u8, key: []const u8) ![]const u8 {
        // Preconditions
        std.debug.assert(section.len > 0); // Valid section
        std.debug.assert(key.len > 0); // Valid key

        // Find section
        const section_start = std.mem.indexOf(u8, self.content, section) orelse
            return ScenarioError.MissingRequiredField;

        // Find key after section
        const search_from = self.content[section_start..];
        const key_with_equals = try std.fmt.allocPrint(self.allocator, "{s} =", .{key});
        defer self.allocator.free(key_with_equals);

        const key_pos = std.mem.indexOf(u8, search_from, key_with_equals) orelse
            return ScenarioError.MissingRequiredField;

        // Find value (between quotes)
        const after_key = search_from[key_pos + key_with_equals.len ..];
        const quote1 = std.mem.indexOf(u8, after_key, "\"") orelse
            return ScenarioError.InvalidFormat;
        const quote2 = std.mem.indexOfPos(u8, after_key, quote1 + 1, "\"") orelse
            return ScenarioError.InvalidFormat;

        const value = after_key[quote1 + 1 .. quote2];

        // Postcondition
        std.debug.assert(value.len > 0); // Found something

        return value;
    }

    /// Find integer value in section
    fn findIntValue(self: *ScenarioParser, section: []const u8, key: []const u8) !u64 {
        // Preconditions
        std.debug.assert(section.len > 0); // Valid section
        std.debug.assert(key.len > 0); // Valid key

        // Find section
        const section_start = std.mem.indexOf(u8, self.content, section) orelse
            return ScenarioError.MissingRequiredField;

        // Find key after section
        const search_from = self.content[section_start..];
        const key_with_equals = try std.fmt.allocPrint(self.allocator, "{s} =", .{key});
        defer self.allocator.free(key_with_equals);

        const key_pos = std.mem.indexOf(u8, search_from, key_with_equals) orelse
            return ScenarioError.MissingRequiredField;

        // Find value (number)
        const after_key = search_from[key_pos + key_with_equals.len ..];
        const line_end = std.mem.indexOf(u8, after_key, "\n") orelse after_key.len;
        const value_str = std.mem.trim(u8, after_key[0..line_end], " \r\n\t");

        const value = std.fmt.parseInt(u64, value_str, 10) catch
            return ScenarioError.InvalidValue;

        // Postcondition
        std.debug.assert(value < 1_000_000_000); // Reasonable limit

        return value;
    }
};
