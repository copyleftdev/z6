//! HPACK Header Compression (RFC 7541)
//!
//! Minimal implementation for HTTP/2 handler:
//! - Static table only (no dynamic table)
//! - Literal encoding without Huffman
//! - Decodes indexed headers and literals
//!
//! Tiger Style:
//! - All loops bounded
//! - Minimum 2 assertions per function
//! - Explicit error handling

const std = @import("std");

/// HPACK errors
pub const HPACKError = error{
    BufferTooSmall,
    InvalidIndex,
    InvalidEncoding,
    StringTooLong,
    TooManyHeaders,
};

/// Maximum header name/value length
pub const MAX_STRING_LENGTH: usize = 8192;

/// Maximum headers per block
pub const MAX_HEADERS: usize = 100;

/// Header name-value pair
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Static table (RFC 7541 Appendix A)
/// Index 1-61 are predefined headers
const STATIC_TABLE = [_]Header{
    .{ .name = "", .value = "" }, // Index 0 is unused
    .{ .name = ":authority", .value = "" },
    .{ .name = ":method", .value = "GET" },
    .{ .name = ":method", .value = "POST" },
    .{ .name = ":path", .value = "/" },
    .{ .name = ":path", .value = "/index.html" },
    .{ .name = ":scheme", .value = "http" },
    .{ .name = ":scheme", .value = "https" },
    .{ .name = ":status", .value = "200" },
    .{ .name = ":status", .value = "204" },
    .{ .name = ":status", .value = "206" },
    .{ .name = ":status", .value = "304" },
    .{ .name = ":status", .value = "400" },
    .{ .name = ":status", .value = "404" },
    .{ .name = ":status", .value = "500" },
    .{ .name = "accept-charset", .value = "" },
    .{ .name = "accept-encoding", .value = "gzip, deflate" },
    .{ .name = "accept-language", .value = "" },
    .{ .name = "accept-ranges", .value = "" },
    .{ .name = "accept", .value = "" },
    .{ .name = "access-control-allow-origin", .value = "" },
    .{ .name = "age", .value = "" },
    .{ .name = "allow", .value = "" },
    .{ .name = "authorization", .value = "" },
    .{ .name = "cache-control", .value = "" },
    .{ .name = "content-disposition", .value = "" },
    .{ .name = "content-encoding", .value = "" },
    .{ .name = "content-language", .value = "" },
    .{ .name = "content-length", .value = "" },
    .{ .name = "content-location", .value = "" },
    .{ .name = "content-range", .value = "" },
    .{ .name = "content-type", .value = "" },
    .{ .name = "cookie", .value = "" },
    .{ .name = "date", .value = "" },
    .{ .name = "etag", .value = "" },
    .{ .name = "expect", .value = "" },
    .{ .name = "expires", .value = "" },
    .{ .name = "from", .value = "" },
    .{ .name = "host", .value = "" },
    .{ .name = "if-match", .value = "" },
    .{ .name = "if-modified-since", .value = "" },
    .{ .name = "if-none-match", .value = "" },
    .{ .name = "if-range", .value = "" },
    .{ .name = "if-unmodified-since", .value = "" },
    .{ .name = "last-modified", .value = "" },
    .{ .name = "link", .value = "" },
    .{ .name = "location", .value = "" },
    .{ .name = "max-forwards", .value = "" },
    .{ .name = "proxy-authenticate", .value = "" },
    .{ .name = "proxy-authorization", .value = "" },
    .{ .name = "range", .value = "" },
    .{ .name = "referer", .value = "" },
    .{ .name = "refresh", .value = "" },
    .{ .name = "retry-after", .value = "" },
    .{ .name = "server", .value = "" },
    .{ .name = "set-cookie", .value = "" },
    .{ .name = "strict-transport-security", .value = "" },
    .{ .name = "transfer-encoding", .value = "" },
    .{ .name = "user-agent", .value = "" },
    .{ .name = "vary", .value = "" },
    .{ .name = "via", .value = "" },
    .{ .name = "www-authenticate", .value = "" },
};

/// HPACK Encoder (minimal - static table + literals only)
pub const HPACKEncoder = struct {
    /// Encode a header into the output buffer
    /// Returns number of bytes written
    pub fn encode(name: []const u8, value: []const u8, output: []u8) !usize {
        // Preconditions
        std.debug.assert(name.len > 0); // Name required
        std.debug.assert(output.len >= 4); // Minimum space for encoding

        var pos: usize = 0;

        // Try to find in static table
        if (findStaticIndex(name, value)) |index| {
            // Indexed Header Field (RFC 7541 Section 6.1)
            // Format: 1xxxxxxx (7-bit index)
            if (output.len < 1) return HPACKError.BufferTooSmall;
            output[pos] = 0x80 | @as(u8, @intCast(index));
            pos += 1;
        } else if (findStaticNameIndex(name)) |name_index| {
            // Literal with Indexed Name (RFC 7541 Section 6.2.2)
            // Format: 0000xxxx (4-bit index, no indexing)
            if (output.len < 1) return HPACKError.BufferTooSmall;
            output[pos] = @as(u8, @intCast(name_index));
            pos += 1;

            // Encode value
            pos += try encodeString(value, output[pos..]);
        } else {
            // Literal with Literal Name (RFC 7541 Section 6.2.2)
            // Format: 00000000 (no indexing, literal name)
            if (output.len < 1) return HPACKError.BufferTooSmall;
            output[pos] = 0x00;
            pos += 1;

            // Encode name
            pos += try encodeString(name, output[pos..]);

            // Encode value
            pos += try encodeString(value, output[pos..]);
        }

        // Postconditions
        std.debug.assert(pos > 0); // Something was written
        std.debug.assert(pos <= output.len); // Didn't overflow

        return pos;
    }

    /// Encode a string without Huffman (H=0)
    fn encodeString(str: []const u8, output: []u8) !usize {
        // Preconditions
        std.debug.assert(str.len <= MAX_STRING_LENGTH);

        if (str.len > 127) {
            // Need multi-byte length encoding
            if (output.len < 2 + str.len) return HPACKError.BufferTooSmall;

            // Use 7-bit prefix with continuation
            output[0] = 0x7F; // H=0, length prefix = 127
            output[1] = @intCast(str.len - 127);
            @memcpy(output[2..][0..str.len], str);

            return 2 + str.len;
        } else {
            // Single byte length
            if (output.len < 1 + str.len) return HPACKError.BufferTooSmall;

            output[0] = @intCast(str.len); // H=0, length
            @memcpy(output[1..][0..str.len], str);

            return 1 + str.len;
        }
    }

    /// Find exact match in static table (name + value)
    fn findStaticIndex(name: []const u8, value: []const u8) ?u7 {
        // Common indexed headers for HTTP/2 requests
        if (std.mem.eql(u8, name, ":method")) {
            if (std.mem.eql(u8, value, "GET")) return 2;
            if (std.mem.eql(u8, value, "POST")) return 3;
        }
        if (std.mem.eql(u8, name, ":path")) {
            if (std.mem.eql(u8, value, "/")) return 4;
            if (std.mem.eql(u8, value, "/index.html")) return 5;
        }
        if (std.mem.eql(u8, name, ":scheme")) {
            if (std.mem.eql(u8, value, "http")) return 6;
            if (std.mem.eql(u8, value, "https")) return 7;
        }
        if (std.mem.eql(u8, name, ":status")) {
            if (std.mem.eql(u8, value, "200")) return 8;
            if (std.mem.eql(u8, value, "204")) return 9;
            if (std.mem.eql(u8, value, "206")) return 10;
            if (std.mem.eql(u8, value, "304")) return 11;
            if (std.mem.eql(u8, value, "400")) return 12;
            if (std.mem.eql(u8, value, "404")) return 13;
            if (std.mem.eql(u8, value, "500")) return 14;
        }
        if (std.mem.eql(u8, name, "accept-encoding") and std.mem.eql(u8, value, "gzip, deflate")) {
            return 16;
        }
        return null;
    }

    /// Find name-only match in static table
    fn findStaticNameIndex(name: []const u8) ?u6 {
        if (std.mem.eql(u8, name, ":authority")) return 1;
        if (std.mem.eql(u8, name, ":method")) return 2;
        if (std.mem.eql(u8, name, ":path")) return 4;
        if (std.mem.eql(u8, name, ":scheme")) return 6;
        if (std.mem.eql(u8, name, ":status")) return 8;
        if (std.mem.eql(u8, name, "accept")) return 19;
        if (std.mem.eql(u8, name, "accept-encoding")) return 16;
        if (std.mem.eql(u8, name, "accept-language")) return 17;
        if (std.mem.eql(u8, name, "authorization")) return 23;
        if (std.mem.eql(u8, name, "cache-control")) return 24;
        if (std.mem.eql(u8, name, "content-length")) return 28;
        if (std.mem.eql(u8, name, "content-type")) return 31;
        if (std.mem.eql(u8, name, "cookie")) return 32;
        if (std.mem.eql(u8, name, "host")) return 38;
        if (std.mem.eql(u8, name, "user-agent")) return 58;
        return null;
    }
};

/// HPACK Decoder (minimal - static table only, no Huffman decoding)
pub const HPACKDecoder = struct {
    /// Decode header block into headers array
    /// Returns number of headers decoded
    pub fn decode(
        input: []const u8,
        headers: []Header,
    ) !usize {
        // Preconditions
        std.debug.assert(headers.len > 0); // Space for headers
        std.debug.assert(headers.len <= MAX_HEADERS);

        var pos: usize = 0;
        var header_count: usize = 0;

        // Bounded loop
        var iterations: usize = 0;
        const max_iterations: usize = MAX_HEADERS;

        while (pos < input.len and header_count < headers.len and iterations < max_iterations) {
            iterations += 1;

            const first_byte = input[pos];

            if (first_byte & 0x80 != 0) {
                // Indexed Header Field (RFC 7541 Section 6.1)
                const index = first_byte & 0x7F;
                if (index == 0 or index >= STATIC_TABLE.len) {
                    return HPACKError.InvalidIndex;
                }
                headers[header_count] = STATIC_TABLE[index];
                pos += 1;
            } else if (first_byte & 0x40 != 0) {
                // Literal Header Field with Incremental Indexing (Section 6.2.1)
                // We don't update dynamic table, just parse
                const name_index = first_byte & 0x3F;
                pos += 1;

                var name: []const u8 = undefined;
                var value: []const u8 = undefined;

                if (name_index > 0) {
                    // Indexed name
                    if (name_index >= STATIC_TABLE.len) {
                        return HPACKError.InvalidIndex;
                    }
                    name = STATIC_TABLE[name_index].name;
                } else {
                    // Literal name
                    const name_result = try decodeString(input[pos..]);
                    name = name_result.str;
                    pos += name_result.bytes_consumed;
                }

                // Decode value
                const value_result = try decodeString(input[pos..]);
                value = value_result.str;
                pos += value_result.bytes_consumed;

                headers[header_count] = .{ .name = name, .value = value };
            } else if (first_byte & 0xF0 == 0) {
                // Literal Header Field without Indexing (Section 6.2.2)
                const name_index = first_byte & 0x0F;
                pos += 1;

                var name: []const u8 = undefined;
                var value: []const u8 = undefined;

                if (name_index > 0) {
                    if (name_index >= STATIC_TABLE.len) {
                        return HPACKError.InvalidIndex;
                    }
                    name = STATIC_TABLE[name_index].name;
                } else {
                    const name_result = try decodeString(input[pos..]);
                    name = name_result.str;
                    pos += name_result.bytes_consumed;
                }

                const value_result = try decodeString(input[pos..]);
                value = value_result.str;
                pos += value_result.bytes_consumed;

                headers[header_count] = .{ .name = name, .value = value };
            } else if (first_byte & 0xF0 == 0x10) {
                // Literal Header Field Never Indexed (Section 6.2.3)
                const name_index = first_byte & 0x0F;
                pos += 1;

                var name: []const u8 = undefined;
                var value: []const u8 = undefined;

                if (name_index > 0) {
                    if (name_index >= STATIC_TABLE.len) {
                        return HPACKError.InvalidIndex;
                    }
                    name = STATIC_TABLE[name_index].name;
                } else {
                    const name_result = try decodeString(input[pos..]);
                    name = name_result.str;
                    pos += name_result.bytes_consumed;
                }

                const value_result = try decodeString(input[pos..]);
                value = value_result.str;
                pos += value_result.bytes_consumed;

                headers[header_count] = .{ .name = name, .value = value };
            } else if (first_byte & 0xE0 == 0x20) {
                // Dynamic Table Size Update (Section 6.3)
                // We ignore these since we don't use dynamic table
                pos += 1;
                continue;
            } else {
                return HPACKError.InvalidEncoding;
            }

            header_count += 1;
        }

        // Postconditions
        std.debug.assert(header_count <= headers.len);
        std.debug.assert(iterations <= max_iterations);

        return header_count;
    }

    const DecodeStringResult = struct {
        str: []const u8,
        bytes_consumed: usize,
    };

    /// Decode a string (with or without Huffman)
    fn decodeString(input: []const u8) !DecodeStringResult {
        // Preconditions
        std.debug.assert(input.len > 0);

        if (input.len < 1) return HPACKError.InvalidEncoding;

        const first_byte = input[0];
        const huffman = (first_byte & 0x80) != 0;
        var length: usize = first_byte & 0x7F;
        var pos: usize = 1;

        // Handle multi-byte length
        if (length == 127) {
            if (input.len < 2) return HPACKError.InvalidEncoding;
            length = 127 + @as(usize, input[1]);
            pos = 2;
        }

        if (pos + length > input.len) {
            return HPACKError.InvalidEncoding;
        }

        if (huffman) {
            // For now, we don't decode Huffman - return raw bytes
            // A full implementation would decode here
            // This is a simplification for v1
            return DecodeStringResult{
                .str = input[pos..][0..length],
                .bytes_consumed = pos + length,
            };
        } else {
            return DecodeStringResult{
                .str = input[pos..][0..length],
                .bytes_consumed = pos + length,
            };
        }
    }
};

/// Encode pseudo-headers for HTTP/2 request
pub fn encodeRequestHeaders(
    method: []const u8,
    path: []const u8,
    scheme: []const u8,
    authority: []const u8,
    extra_headers: []const Header,
    output: []u8,
) !usize {
    // Preconditions
    std.debug.assert(method.len > 0);
    std.debug.assert(path.len > 0);
    std.debug.assert(output.len >= 64); // Minimum space

    var pos: usize = 0;

    // :method
    pos += try HPACKEncoder.encode(":method", method, output[pos..]);

    // :scheme
    pos += try HPACKEncoder.encode(":scheme", scheme, output[pos..]);

    // :authority
    pos += try HPACKEncoder.encode(":authority", authority, output[pos..]);

    // :path
    pos += try HPACKEncoder.encode(":path", path, output[pos..]);

    // Extra headers (bounded loop)
    var i: usize = 0;
    while (i < extra_headers.len and i < MAX_HEADERS) : (i += 1) {
        const h = extra_headers[i];
        pos += try HPACKEncoder.encode(h.name, h.value, output[pos..]);
    }

    // Postconditions
    std.debug.assert(pos > 0);
    std.debug.assert(i <= MAX_HEADERS);

    return pos;
}

// Compile-time tests
test "hpack: static table size" {
    // Static table should have 62 entries (index 0-61)
    try std.testing.expectEqual(@as(usize, 62), STATIC_TABLE.len);
}
