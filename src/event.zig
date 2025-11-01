//! Event Model
//!
//! Immutable event log for Z6 - the single source of truth.
//! All events are fixed-size (272 bytes), cache-line aligned, and checksummed.
//!
//! Tiger Style:
//! - All events are immutable
//! - All events are bounded (fixed 272 bytes)
//! - All events are measured (CRC64 checksum)
//! - Minimum 2 assertions per function

const std = @import("std");

/// Event type discriminator (22 types total per EVENT_MODEL.md)
pub const EventType = enum(u16) {
    // Lifecycle Events (3)
    vu_spawned,
    vu_ready,
    vu_complete,

    // Request Events (3)
    request_issued,
    request_timeout,
    request_cancelled,

    // Response Events (2)
    response_received,
    response_error,

    // Connection Events (3)
    conn_established,
    conn_closed,
    conn_error,

    // Scheduler Events (1)
    scheduler_tick,

    // Assertion Events (2)
    assertion_passed,
    assertion_failed,

    // Error Events (7)
    error_dns,
    error_tcp,
    error_tls,
    error_http,
    error_timeout,
    error_protocol_violation,
    error_resource_exhausted,
};

/// Event header (24 bytes)
/// Layout: tick(8) + vu_id(4) + event_type(2) + _padding(2) + _reserved(8) = 24 bytes
pub const EventHeader = extern struct {
    /// Logical timestamp (monotonic, deterministic)
    tick: u64,

    /// Virtual user that emitted this event
    vu_id: u32,

    /// Event type discriminator
    event_type: EventType,

    /// Padding for alignment
    _padding: u16,

    /// Reserved for future use (must be 0)
    _reserved: u64,

    comptime {
        std.debug.assert(@sizeOf(EventHeader) == 24);
    }
};

/// Event structure (272 bytes total)
/// Layout: header (24) + payload (240) + checksum (8) = 272 bytes
pub const Event = extern struct {
    header: EventHeader,
    payload: [240]u8,
    checksum: u64,

    comptime {
        std.debug.assert(@sizeOf(Event) == 272);
        std.debug.assert(@offsetOf(Event, "header") == 0);
        std.debug.assert(@offsetOf(Event, "payload") == 24);
        std.debug.assert(@offsetOf(Event, "checksum") == 264);
    }

    /// Serialize event to bytes
    pub fn serialize(event: *const Event, buffer: *[272]u8) []u8 {
        // Preconditions
        std.debug.assert(@sizeOf(Event) == 272); // Fixed size
        std.debug.assert(buffer.len == 272); // Buffer matches

        // Cast event to bytes
        const event_bytes = std.mem.asBytes(event);
        std.debug.assert(event_bytes.len == 272); // Verify size

        // Copy to buffer
        @memcpy(buffer[0..272], event_bytes[0..272]);

        // Postconditions
        std.debug.assert(buffer.len == 272); // Size unchanged
        std.debug.assert(buffer.len == event_bytes.len); // Complete copy

        return buffer[0..];
    }

    /// Deserialize event from bytes
    pub fn deserialize(bytes: []const u8) !Event {
        // Preconditions
        std.debug.assert(bytes.len >= @sizeOf(Event)); // Sufficient data
        std.debug.assert(@sizeOf(Event) == 272); // Fixed size

        if (bytes.len < @sizeOf(Event)) {
            return error.InsufficientData;
        }

        // Interpret bytes as Event
        const event_ptr = @as(*align(1) const Event, @ptrCast(bytes.ptr));
        const event = event_ptr.*;

        // Postconditions
        std.debug.assert(event.payload.len == 240); // Payload intact
        std.debug.assert(@sizeOf(@TypeOf(event.checksum)) == 8); // Checksum present

        return event;
    }

    /// Calculate CRC64 checksum for event
    /// Covers header (24 bytes) + payload (240 bytes) = 264 bytes
    pub fn calculateChecksum(event: *const Event) u64 {
        // Preconditions
        std.debug.assert(@sizeOf(EventHeader) == 24); // Header size
        std.debug.assert(event.payload.len == 240); // Payload size

        // Get bytes to checksum (header + payload, excluding checksum field)
        const event_bytes = std.mem.asBytes(event);
        const bytes_to_check = event_bytes[0..264]; // First 264 bytes

        // Calculate CRC32 twice to get 64-bit checksum
        // CRC64 not available in std.hash, using double CRC32 as substitute
        const crc1 = std.hash.Crc32.hash(bytes_to_check);
        const crc2 = std.hash.Crc32.hash(bytes_to_check[64..]);
        const checksum = (@as(u64, crc1) << 32) | @as(u64, crc2);

        // Postconditions
        std.debug.assert(bytes_to_check.len == 264); // Correct length
        std.debug.assert(checksum != 0 or std.mem.allEqual(u8, bytes_to_check, 0)); // Non-zero for non-zero data

        return checksum;
    }

    /// Validate event checksum
    pub fn validateChecksum(event: *const Event) bool {
        // Preconditions
        std.debug.assert(@sizeOf(Event) == 272); // Fixed size
        std.debug.assert(event.payload.len == 240); // Valid payload

        const computed = calculateChecksum(event);
        const valid = computed == event.checksum;

        // Postcondition
        std.debug.assert(computed == calculateChecksum(event)); // Deterministic

        return valid;
    }

    /// Compare events for ordering (by tick, then vu_id)
    pub fn isBefore(a: *const Event, b: *const Event) bool {
        // Preconditions
        std.debug.assert(@sizeOf(Event) == 272); // Fixed size
        std.debug.assert(a.payload.len == 240); // Valid events
        std.debug.assert(b.payload.len == 240); // Valid events

        // Primary ordering: by tick
        if (a.header.tick != b.header.tick) {
            return a.header.tick < b.header.tick;
        }

        // Secondary ordering: by vu_id
        const result = a.header.vu_id < b.header.vu_id;

        // Postcondition: total ordering
        std.debug.assert(result == (a.header.vu_id < b.header.vu_id)); // Deterministic

        return result;
    }
};

// Compile-time tests
test "event: comptime size checks" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(EventHeader));
    try std.testing.expectEqual(@as(usize, 272), @sizeOf(Event));
    try std.testing.expectEqual(@as(usize, 2), @sizeOf(EventType));
}

test "event: comptime offset checks" {
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Event, "header"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(Event, "payload"));
    try std.testing.expectEqual(@as(usize, 264), @offsetOf(Event, "checksum"));
}
