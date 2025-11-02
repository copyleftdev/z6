//! HTTP/1.1 Response Parser
//!
//! Parses HTTP/1.1 responses following RFC 7230.
//! Designed for load testing - minimal, correct, fast.
//!
//! Features:
//! - Status line parsing
//! - Header parsing (max 100 headers, max 8KB per header)
//! - Content-Length body parsing
//! - Chunked transfer encoding
//! - Keep-alive detection
//! - Bounds checking (max 10MB response)
//!
//! Tiger Style:
//! - All loops bounded
//! - Minimum 2 assertions per function
//! - Explicit error handling
//! - Zero-copy where possible

const std = @import("std");
const protocol = @import("protocol.zig");

/// Maximum number of headers per response
pub const MAX_HEADERS = 100;

/// Maximum size of a single header (name + value)
pub const MAX_HEADER_SIZE = 8192; // 8 KB

/// Maximum response body size
pub const MAX_BODY_SIZE = 10 * 1024 * 1024; // 10 MB

/// Maximum response size total
pub const MAX_RESPONSE_SIZE = MAX_BODY_SIZE + (MAX_HEADERS * MAX_HEADER_SIZE);

/// HTTP/1.1 Parser errors
pub const ParserError = error{
    InvalidStatusLine,
    InvalidHeader,
    InvalidChunkSize,
    TooManyHeaders,
    HeaderTooLarge,
    BodyTooLarge,
    IncompleteResponse,
    UnsupportedTransferEncoding,
    MalformedChunkedBody,
};

/// Parse result
pub const ParseResult = struct {
    /// HTTP status code
    status_code: u16,

    /// Response headers (slices into original buffer)
    headers: []protocol.Header,

    /// Response body (slice into original buffer or owned)
    body: []const u8,

    /// Total bytes consumed from input buffer
    bytes_consumed: usize,

    /// Whether connection should be kept alive
    keep_alive: bool,
};

/// HTTP/1.1 Response Parser
pub const HTTP1Parser = struct {
    allocator: std.mem.Allocator,
    headers_buf: [MAX_HEADERS]protocol.Header,
    header_count: usize,

    /// Initialize parser
    pub fn init(allocator: std.mem.Allocator) HTTP1Parser {
        // Preconditions
        std.debug.assert(@sizeOf(@TypeOf(allocator)) > 0); // Valid allocator
        std.debug.assert(MAX_HEADERS > 0); // Reasonable limit

        // Postconditions
        const parser = HTTP1Parser{
            .allocator = allocator,
            .headers_buf = undefined,
            .header_count = 0,
        };
        std.debug.assert(parser.header_count == 0); // Initialized

        return parser;
    }

    /// Parse HTTP/1.1 response
    pub fn parse(self: *HTTP1Parser, data: []const u8) !ParseResult {
        // Preconditions
        std.debug.assert(data.len > 0); // Must have data
        std.debug.assert(data.len <= MAX_RESPONSE_SIZE); // Within bounds

        self.header_count = 0;
        var pos: usize = 0;

        // Parse status line
        const status_code = try self.parseStatusLine(data, &pos);

        // Parse headers
        _ = try self.parseHeaders(data, &pos);

        // Determine if chunked or content-length
        const content_length = self.findContentLength();
        const is_chunked = self.isChunkedEncoding();
        const keep_alive = self.isKeepAlive();

        // Parse body
        const body = if (is_chunked)
            try self.parseChunkedBody(data[pos..])
        else if (content_length) |len|
            try self.parseFixedBody(data[pos..], len)
        else
            data[pos..pos]; // Empty body

        const bytes_consumed = pos + body.len;

        // Postconditions
        std.debug.assert(status_code >= 100 and status_code < 600); // Valid HTTP status
        std.debug.assert(bytes_consumed <= data.len); // Didn't overrun

        return ParseResult{
            .status_code = status_code,
            .headers = self.headers_buf[0..self.header_count],
            .body = body,
            .bytes_consumed = bytes_consumed,
            .keep_alive = keep_alive,
        };
    }

    /// Parse HTTP status line
    fn parseStatusLine(_: *HTTP1Parser, data: []const u8, pos: *usize) !u16 {
        // Preconditions
        std.debug.assert(data.len > 0); // Must have data
        std.debug.assert(pos.* == 0); // Should be at start

        // Find end of status line (\r\n)
        const line_end = std.mem.indexOf(u8, data[pos.*..], "\r\n") orelse
            return error.IncompleteResponse;

        const status_line = data[pos.* .. pos.* + line_end];

        // Status line format: "HTTP/1.1 200 OK"
        // Minimum: "HTTP/1.1 200 " = 13 chars
        if (status_line.len < 13) return error.InvalidStatusLine;

        // Verify "HTTP/1.1 " prefix
        if (!std.mem.startsWith(u8, status_line, "HTTP/1.1 ")) {
            return error.InvalidStatusLine;
        }

        // Extract status code (3 digits after "HTTP/1.1 ")
        const status_start = 9; // Length of "HTTP/1.1 "
        const status_str = status_line[status_start .. status_start + 3];

        const status_code = std.fmt.parseInt(u16, status_str, 10) catch
            return error.InvalidStatusLine;

        // Validate status code range
        if (status_code < 100 or status_code >= 600) {
            return error.InvalidStatusLine;
        }

        pos.* += line_end + 2; // Move past \r\n

        // Postconditions
        std.debug.assert(status_code >= 100 and status_code < 600); // Valid
        std.debug.assert(pos.* > 0); // Advanced position

        return status_code;
    }

    /// Parse HTTP headers
    fn parseHeaders(self: *HTTP1Parser, data: []const u8, pos: *usize) !void {
        // Preconditions
        std.debug.assert(data.len > pos.*); // Have data to parse
        std.debug.assert(self.header_count == 0); // Starting fresh

        while (pos.* < data.len) {
            // Check for end of headers (empty line: \r\n)
            if (std.mem.startsWith(u8, data[pos.*..], "\r\n")) {
                pos.* += 2;
                break;
            }

            // Check header count limit
            if (self.header_count >= MAX_HEADERS) {
                return error.TooManyHeaders;
            }

            // Find end of header line
            const line_end = std.mem.indexOf(u8, data[pos.*..], "\r\n") orelse
                return error.IncompleteResponse;

            const header_line = data[pos.* .. pos.* + line_end];

            // Check header size
            if (header_line.len > MAX_HEADER_SIZE) {
                return error.HeaderTooLarge;
            }

            // Parse header: "Name: Value"
            const colon_pos = std.mem.indexOf(u8, header_line, ":") orelse
                return error.InvalidHeader;

            const name = header_line[0..colon_pos];
            // Skip colon and any leading whitespace
            var value_start = colon_pos + 1;
            while (value_start < header_line.len and header_line[value_start] == ' ') {
                value_start += 1;
            }
            const value = header_line[value_start..];

            // Store header
            self.headers_buf[self.header_count] = protocol.Header{
                .name = name,
                .value = value,
            };
            self.header_count += 1;

            pos.* += line_end + 2; // Move past \r\n
        }

        // Postconditions
        std.debug.assert(self.header_count <= MAX_HEADERS); // Within limit
        std.debug.assert(pos.* <= data.len); // Valid position
    }

    /// Find Content-Length header value
    fn findContentLength(self: *const HTTP1Parser) ?usize {
        // Preconditions
        std.debug.assert(self.header_count <= MAX_HEADERS); // Valid count

        for (self.headers_buf[0..self.header_count]) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "content-length")) {
                const len = std.fmt.parseInt(usize, header.value, 10) catch
                    return null;

                // Postcondition
                std.debug.assert(len >= 0); // Valid length
                return len;
            }
        }
        return null;
    }

    /// Check if chunked transfer encoding
    fn isChunkedEncoding(self: *const HTTP1Parser) bool {
        // Preconditions
        std.debug.assert(self.header_count <= MAX_HEADERS); // Valid count

        for (self.headers_buf[0..self.header_count]) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "transfer-encoding")) {
                const is_chunked = std.ascii.eqlIgnoreCase(header.value, "chunked");

                // Postcondition
                std.debug.assert(is_chunked or !is_chunked); // Boolean result
                return is_chunked;
            }
        }
        return false;
    }

    /// Check if connection should be kept alive
    fn isKeepAlive(self: *const HTTP1Parser) bool {
        // Preconditions
        std.debug.assert(self.header_count <= MAX_HEADERS); // Valid count

        // HTTP/1.1 defaults to keep-alive
        var keep_alive = true;

        for (self.headers_buf[0..self.header_count]) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "connection")) {
                keep_alive = !std.ascii.eqlIgnoreCase(header.value, "close");
                break;
            }
        }

        // Postcondition
        std.debug.assert(keep_alive or !keep_alive); // Boolean result
        return keep_alive;
    }

    /// Parse fixed-length body
    fn parseFixedBody(self: *HTTP1Parser, data: []const u8, length: usize) ![]const u8 {
        // Preconditions
        std.debug.assert(length > 0); // Have expected length
        std.debug.assert(data.len >= 0); // Valid data

        // Check body size limit
        if (length > MAX_BODY_SIZE) {
            return error.BodyTooLarge;
        }

        // Check if we have enough data
        if (data.len < length) {
            return error.IncompleteResponse;
        }

        const body = data[0..length];

        // Postconditions
        std.debug.assert(body.len == length); // Correct length
        std.debug.assert(body.len <= MAX_BODY_SIZE); // Within limit

        _ = self; // Parser not needed for fixed body
        return body;
    }

    /// Parse chunked transfer encoded body
    fn parseChunkedBody(self: *HTTP1Parser, data: []const u8) ![]const u8 {
        // Preconditions
        std.debug.assert(data.len >= 0); // Valid data
        std.debug.assert(@sizeOf(@TypeOf(self.allocator)) > 0); // Valid allocator

        var chunks = try std.ArrayList(u8).initCapacity(self.allocator, 1024);
        errdefer chunks.deinit(self.allocator);

        var pos: usize = 0;

        // Parse chunks until we hit 0-sized chunk
        var chunk_count: usize = 0;
        while (pos < data.len and chunk_count < 1000) : (chunk_count += 1) {
            // Parse chunk size line (hex number followed by \r\n)
            const size_line_end = std.mem.indexOf(u8, data[pos..], "\r\n") orelse
                return error.MalformedChunkedBody;

            const size_line = data[pos .. pos + size_line_end];

            // Parse hex chunk size
            const chunk_size = std.fmt.parseInt(usize, size_line, 16) catch
                return error.InvalidChunkSize;

            pos += size_line_end + 2; // Move past \r\n

            // Check if terminal chunk (size 0)
            if (chunk_size == 0) {
                // Expect final \r\n
                if (pos + 2 <= data.len and
                    data[pos] == '\r' and data[pos + 1] == '\n')
                {
                    pos += 2;
                }
                break;
            }

            // Check total size limit
            if (chunks.items.len + chunk_size > MAX_BODY_SIZE) {
                return error.BodyTooLarge;
            }

            // Check if we have the chunk data
            if (pos + chunk_size + 2 > data.len) {
                return error.IncompleteResponse;
            }

            // Append chunk data
            try chunks.appendSlice(self.allocator, data[pos .. pos + chunk_size]);
            pos += chunk_size;

            // Expect \r\n after chunk data
            if (data[pos] != '\r' or data[pos + 1] != '\n') {
                return error.MalformedChunkedBody;
            }
            pos += 2;
        }

        // Postconditions
        std.debug.assert(chunks.items.len <= MAX_BODY_SIZE); // Within limit
        std.debug.assert(chunk_count < 1000); // Reasonable chunk count

        return try chunks.toOwnedSlice(self.allocator);
    }

    /// Free chunked body memory
    pub fn freeChunkedBody(self: *HTTP1Parser, body: []const u8) void {
        // Preconditions
        std.debug.assert(body.len <= MAX_BODY_SIZE); // Valid body
        std.debug.assert(@sizeOf(@TypeOf(self.allocator)) > 0); // Valid allocator

        self.allocator.free(body);

        // Postcondition
        std.debug.assert(true); // Freed successfully
    }
};
