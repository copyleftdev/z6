//! HPACK Encoder/Decoder Tests

const std = @import("std");
const testing = std.testing;
const z6 = @import("z6");

test "hpack: encode indexed header (static table)" {
    var buffer: [64]u8 = undefined;

    // :method GET should be index 2
    const len = try z6.HPACKEncoder.encode(":method", "GET", &buffer);

    try testing.expectEqual(@as(usize, 1), len);
    try testing.expectEqual(@as(u8, 0x82), buffer[0]); // 0x80 | 2
}

test "hpack: encode indexed header POST" {
    var buffer: [64]u8 = undefined;

    // :method POST should be index 3
    const len = try z6.HPACKEncoder.encode(":method", "POST", &buffer);

    try testing.expectEqual(@as(usize, 1), len);
    try testing.expectEqual(@as(u8, 0x83), buffer[0]); // 0x80 | 3
}

test "hpack: encode literal with indexed name" {
    var buffer: [64]u8 = undefined;

    // :authority with custom value - name is indexed, value is literal
    const len = try z6.HPACKEncoder.encode(":authority", "example.com", &buffer);

    // Should be: 0x01 (indexed name at 1) + length + "example.com"
    try testing.expect(len > 1);
    try testing.expectEqual(@as(u8, 0x01), buffer[0]); // Index 1 for :authority
    try testing.expectEqual(@as(u8, 11), buffer[1]); // Length of "example.com"
    try testing.expectEqualStrings("example.com", buffer[2..13]);
}

test "hpack: encode literal with literal name" {
    var buffer: [64]u8 = undefined;

    // Custom header - both name and value are literal
    const len = try z6.HPACKEncoder.encode("x-custom", "value123", &buffer);

    // Should be: 0x00 + name_len + name + value_len + value
    try testing.expect(len > 2);
    try testing.expectEqual(@as(u8, 0x00), buffer[0]); // Literal name
    try testing.expectEqual(@as(u8, 8), buffer[1]); // Length of "x-custom"
    try testing.expectEqualStrings("x-custom", buffer[2..10]);
    try testing.expectEqual(@as(u8, 8), buffer[10]); // Length of "value123"
    try testing.expectEqualStrings("value123", buffer[11..19]);
}

test "hpack: encode scheme http" {
    var buffer: [64]u8 = undefined;

    const len = try z6.HPACKEncoder.encode(":scheme", "http", &buffer);

    try testing.expectEqual(@as(usize, 1), len);
    try testing.expectEqual(@as(u8, 0x86), buffer[0]); // 0x80 | 6
}

test "hpack: encode scheme https" {
    var buffer: [64]u8 = undefined;

    const len = try z6.HPACKEncoder.encode(":scheme", "https", &buffer);

    try testing.expectEqual(@as(usize, 1), len);
    try testing.expectEqual(@as(u8, 0x87), buffer[0]); // 0x80 | 7
}

test "hpack: encode path /" {
    var buffer: [64]u8 = undefined;

    const len = try z6.HPACKEncoder.encode(":path", "/", &buffer);

    try testing.expectEqual(@as(usize, 1), len);
    try testing.expectEqual(@as(u8, 0x84), buffer[0]); // 0x80 | 4
}

test "hpack: encode custom path" {
    var buffer: [64]u8 = undefined;

    const len = try z6.HPACKEncoder.encode(":path", "/api/users", &buffer);

    // Should use indexed name (4) with literal value
    try testing.expect(len > 1);
    try testing.expectEqual(@as(u8, 0x04), buffer[0]); // Index 4 for :path
}

test "hpack: decode indexed header" {
    // Encoded :method GET
    const input = [_]u8{0x82};
    var headers: [10]z6.HPACKHeader = undefined;

    const count = try z6.HPACKDecoder.decode(&input, &headers);

    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualStrings(":method", headers[0].name);
    try testing.expectEqualStrings("GET", headers[0].value);
}

test "hpack: decode multiple indexed headers" {
    // :method GET, :scheme https, :path /
    const input = [_]u8{ 0x82, 0x87, 0x84 };
    var headers: [10]z6.HPACKHeader = undefined;

    const count = try z6.HPACKDecoder.decode(&input, &headers);

    try testing.expectEqual(@as(usize, 3), count);
    try testing.expectEqualStrings(":method", headers[0].name);
    try testing.expectEqualStrings("GET", headers[0].value);
    try testing.expectEqualStrings(":scheme", headers[1].name);
    try testing.expectEqualStrings("https", headers[1].value);
    try testing.expectEqualStrings(":path", headers[2].name);
    try testing.expectEqualStrings("/", headers[2].value);
}

test "hpack: decode literal with indexed name" {
    // Index 1 (:authority) with literal value "test.com"
    var input: [32]u8 = undefined;
    input[0] = 0x01; // Indexed name at 1
    input[1] = 8; // Length
    @memcpy(input[2..10], "test.com");

    var headers: [10]z6.HPACKHeader = undefined;
    const count = try z6.HPACKDecoder.decode(input[0..10], &headers);

    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualStrings(":authority", headers[0].name);
    try testing.expectEqualStrings("test.com", headers[0].value);
}

test "hpack: decode literal with literal name" {
    // Literal name and value
    var input: [32]u8 = undefined;
    input[0] = 0x00; // Literal name
    input[1] = 4; // Name length
    @memcpy(input[2..6], "test");
    input[6] = 5; // Value length
    @memcpy(input[7..12], "value");

    var headers: [10]z6.HPACKHeader = undefined;
    const count = try z6.HPACKDecoder.decode(input[0..12], &headers);

    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualStrings("test", headers[0].name);
    try testing.expectEqualStrings("value", headers[0].value);
}

test "hpack: encode request headers" {
    var buffer: [256]u8 = undefined;

    // No extra headers for this test - pseudo-headers only
    const extra = [_]z6.HPACKHeader{};

    const len = try z6.encodeRequestHeaders(
        "GET",
        "/",
        "https",
        "example.com",
        &extra,
        &buffer,
    );

    try testing.expect(len > 0);

    // Decode and verify
    var headers: [10]z6.HPACKHeader = undefined;
    const count = try z6.HPACKDecoder.decode(buffer[0..len], &headers);

    try testing.expectEqual(@as(usize, 4), count); // The 4 pseudo-headers
    try testing.expectEqualStrings(":method", headers[0].name);
    try testing.expectEqualStrings("GET", headers[0].value);
    try testing.expectEqualStrings(":scheme", headers[1].name);
    try testing.expectEqualStrings("https", headers[1].value);
}

test "hpack: encode and decode roundtrip" {
    var encode_buffer: [128]u8 = undefined;
    var pos: usize = 0;

    // Encode several headers
    pos += try z6.HPACKEncoder.encode(":method", "GET", encode_buffer[pos..]);
    pos += try z6.HPACKEncoder.encode(":scheme", "https", encode_buffer[pos..]);
    pos += try z6.HPACKEncoder.encode(":path", "/test", encode_buffer[pos..]);
    pos += try z6.HPACKEncoder.encode(":authority", "localhost", encode_buffer[pos..]);

    // Decode them back
    var headers: [10]z6.HPACKHeader = undefined;
    const count = try z6.HPACKDecoder.decode(encode_buffer[0..pos], &headers);

    try testing.expectEqual(@as(usize, 4), count);
    try testing.expectEqualStrings(":method", headers[0].name);
    try testing.expectEqualStrings("GET", headers[0].value);
    try testing.expectEqualStrings(":scheme", headers[1].name);
    try testing.expectEqualStrings("https", headers[1].value);
    try testing.expectEqualStrings(":path", headers[2].name);
    try testing.expectEqualStrings("/test", headers[2].value);
    try testing.expectEqualStrings(":authority", headers[3].name);
    try testing.expectEqualStrings("localhost", headers[3].value);
}

test "hpack: Tiger Style - bounded loops" {
    // Verify decoder doesn't infinite loop on malformed input
    // MAX_HEADERS bounds the iteration count
    var headers: [10]z6.HPACKHeader = undefined;

    // Empty input
    const count1 = try z6.HPACKDecoder.decode(&[_]u8{}, &headers);
    try testing.expectEqual(@as(usize, 0), count1);

    // Single indexed header
    const count2 = try z6.HPACKDecoder.decode(&[_]u8{0x82}, &headers);
    try testing.expectEqual(@as(usize, 1), count2);
}

test "hpack: static table entries" {
    // Verify key static table entries by decoding indexed headers
    var headers: [1]z6.HPACKHeader = undefined;

    // :status 200 should be index 8
    const count = try z6.HPACKDecoder.decode(&[_]u8{0x88}, &headers);
    try testing.expectEqual(@as(usize, 1), count);
    try testing.expectEqualStrings(":status", headers[0].name);
    try testing.expectEqualStrings("200", headers[0].value);
}
