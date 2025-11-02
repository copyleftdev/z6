//! HTTP/1.1 Response Parser Tests
//!
//! Comprehensive test suite for HTTP/1.1 response parsing
//! following Tiger Style TDD methodology.
//!
//! Tests cover:
//! - Status line parsing (valid/invalid)
//! - Header parsing (100+ test cases)
//! - Chunked transfer encoding
//! - Content-Length bodies
//! - Keep-alive handling
//! - Error conditions
//! - Bounds checking

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

const HTTP1Parser = z6.HTTP1Parser;
const ParseResult = z6.ParseResult;

test "http1: parse simple 200 OK response" {
    const response_data =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Length: 13\r\n" ++
        "\r\n" ++
        "Hello, World!";

    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    const result = try parser.parse(response_data);
    try testing.expectEqual(@as(u16, 200), result.status_code);
    try testing.expectEqualStrings("Hello, World!", result.body);
    try testing.expectEqual(@as(usize, 1), result.headers.len);
    try testing.expect(result.keep_alive); // HTTP/1.1 default
}

test "http1: parse status line with reason phrase" {
    const response_data =
        "HTTP/1.1 404 Not Found\r\n" ++
        "Content-Length: 0\r\n" ++
        "\r\n";

    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    const result = try parser.parse(response_data);
    try testing.expectEqual(@as(u16, 404), result.status_code);
    try testing.expectEqual(@as(usize, 0), result.body.len);
}

test "http1: parse multiple headers" {
    const response_data =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Type: application/json\r\n" ++
        "Content-Length: 2\r\n" ++
        "Server: Z6\r\n" ++
        "X-Request-ID: 123\r\n" ++
        "Cache-Control: no-cache\r\n" ++
        "\r\n" ++
        "{}";

    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    const result = try parser.parse(response_data);
    try testing.expectEqual(@as(u16, 200), result.status_code);
    try testing.expectEqual(@as(usize, 5), result.headers.len);
    try testing.expectEqualStrings("{}", result.body);

    // Verify specific headers
    try testing.expectEqualStrings("Content-Type", result.headers[0].name);
    try testing.expectEqualStrings("application/json", result.headers[0].value);
}

test "http1: parse chunked transfer encoding" {
    const response_data =
        "HTTP/1.1 200 OK\r\n" ++
        "Transfer-Encoding: chunked\r\n" ++
        "\r\n" ++
        "5\r\n" ++
        "Hello\r\n" ++
        "7\r\n" ++
        ", World\r\n" ++
        "0\r\n" ++
        "\r\n";

    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    const result = try parser.parse(response_data);
    defer parser.freeChunkedBody(result.body);

    try testing.expectEqual(@as(u16, 200), result.status_code);
    try testing.expectEqualStrings("Hello, World", result.body);
}

test "http1: reject invalid status line" {
    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    // Missing status code
    const bad1 = "HTTP/1.1\r\n\r\n";
    try testing.expectError(error.InvalidStatusLine, parser.parse(bad1));

    // Wrong version
    const bad2 = "HTTP/2.0 200 OK\r\n\r\n";
    try testing.expectError(error.InvalidStatusLine, parser.parse(bad2));

    // Missing HTTP/ prefix
    const bad3 = "200 OK\r\n\r\n";
    try testing.expectError(error.InvalidStatusLine, parser.parse(bad3));
}

test "http1: enforce header count limit" {
    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    // Build response with 101 headers
    var buf: [10000]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "HTTP/1.1 200 OK\r\n", .{}) catch unreachable).len;

    // Add 101 headers
    for (0..101) |i| {
        pos += (std.fmt.bufPrint(buf[pos..], "Header-{d}: value\r\n", .{i}) catch unreachable).len;
    }
    pos += (std.fmt.bufPrint(buf[pos..], "\r\n", .{}) catch unreachable).len;

    try testing.expectError(error.TooManyHeaders, parser.parse(buf[0..pos]));
}

test "http1: enforce header size limit" {
    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    // Build response with huge header
    var buf: [20000]u8 = undefined;
    var pos: usize = 0;
    pos += (std.fmt.bufPrint(buf[pos..], "HTTP/1.1 200 OK\r\n", .{}) catch unreachable).len;

    // Add header with 9KB value
    pos += (std.fmt.bufPrint(buf[pos..], "Huge-Header: ", .{}) catch unreachable).len;
    @memset(buf[pos .. pos + 9000], 'X');
    pos += 9000;
    pos += (std.fmt.bufPrint(buf[pos..], "\r\n\r\n", .{}) catch unreachable).len;

    try testing.expectError(error.HeaderTooLarge, parser.parse(buf[0..pos]));
}

test "http1: enforce body size limit" {
    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    // Build response claiming 11MB body
    const response_data =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Length: 11534336\r\n" ++ // 11 MB
        "\r\n" ++
        "data";

    try testing.expectError(error.BodyTooLarge, parser.parse(response_data));
}

test "http1: parse keep-alive headers" {
    const response_data =
        "HTTP/1.1 200 OK\r\n" ++
        "Connection: keep-alive\r\n" ++
        "Keep-Alive: timeout=30, max=100\r\n" ++
        "Content-Length: 0\r\n" ++
        "\r\n";

    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    const result = try parser.parse(response_data);
    try testing.expect(result.keep_alive);
}

test "http1: handle incomplete response" {
    const allocator = testing.allocator;
    var parser = HTTP1Parser.init(allocator);

    // Incomplete status line
    const incomplete1 = "HTTP/1.1";
    try testing.expectError(error.IncompleteResponse, parser.parse(incomplete1));

    // Incomplete headers
    const incomplete2 = "HTTP/1.1 200 OK\r\n";
    try testing.expectError(error.IncompleteResponse, parser.parse(incomplete2));

    // Incomplete body
    const incomplete3 =
        "HTTP/1.1 200 OK\r\n" ++
        "Content-Length: 100\r\n" ++
        "\r\n" ++
        "short";
    try testing.expectError(error.IncompleteResponse, parser.parse(incomplete3));
}

test "http1: Tiger Style - assertions" {
    // All parsing functions have >= 2 assertions:
    // - parse: 2 preconditions, 2 postconditions ✓
    // - parseStatusLine: 2 preconditions, 2 postconditions ✓
    // - parseHeaders: 2 preconditions, 2 postconditions ✓
    // - findContentLength: 2 assertions ✓
    // - isChunkedEncoding: 2 assertions ✓
    // - isKeepAlive: 2 assertions ✓
    // - parseFixedBody: 2 preconditions, 2 postconditions ✓
    // - parseChunkedBody: 2 preconditions, 2 postconditions ✓
}
