# Z6 Fuzz Targets

> "Fuzzing finds bugs humans miss. Fuzz everything that parses external input."

## Fuzzing Strategy

Z6 fuzzes all components that process untrusted input:

1. **Protocol parsers** — HTTP, gRPC, WebSocket
2. **Serialization** — Event log, metrics
3. **Configuration** — Scenario files
4. **Network data** — Raw bytes from sockets

## Fuzz Target Template

```zig
const std = @import("std");
const z6 = @import("z6");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    
    if (args.len < 2) {
        std.debug.print("Usage: {} <input_file>\n", .{args[0]});
        return error.MissingArgument;
    }
    
    const input = try std.fs.cwd().readFileAlloc(allocator, args[1], 10 * 1024 * 1024);
    defer allocator.free(input);
    
    fuzz(input);
}

pub fn fuzz(data: []const u8) void {
    // Fuzz logic here
    _ = parse_something(data) catch return;
}
```

## Target 1: HTTP/1.1 Response Parser

Parse arbitrary HTTP/1.1 responses.

```zig
// fuzz/http1_response.zig

pub fn fuzz(data: []const u8) void {
    if (data.len < 16) return; // Minimum valid response
    if (data.len > 1024 * 1024) return; // 1MB max
    
    var parser = HTTPParser.init(std.testing.allocator);
    defer parser.deinit();
    
    _ = parser.parse_http1_response(data) catch return;
}
```

### Corpus Seeds

```
corpus/http1_response/valid/
├── 200_ok.bin
├── 404_not_found.bin
├── 500_error.bin
├── chunked_encoding.bin
├── large_headers.bin
└── keep_alive.bin

corpus/http1_response/invalid/
├── missing_status_line.bin
├── malformed_headers.bin
├── incomplete_body.bin
└── random_bytes.bin
```

### Expected Invariants

- No crashes
- No memory leaks
- No hangs (timeout: 1s per input)
- All errors are explicitly handled

## Target 2: HTTP/2 Frame Parser

Parse HTTP/2 frames.

```zig
// fuzz/http2_frame.zig

pub fn fuzz(data: []const u8) void {
    if (data.len < 9) return; // Frame header is 9 bytes
    
    var parser = HTTP2FrameParser.init();
    _ = parser.parse_frame(data) catch return;
}
```

### Test Cases

- Valid DATA, HEADERS, SETTINGS frames
- Frames with invalid lengths
- Frames with unknown types
- Malformed HPACK headers
- Flow control violations

## Target 3: Event Serialization

Test event serialization/deserialization.

```zig
// fuzz/event_serialization.zig

pub fn fuzz(data: []const u8) void {
    if (data.len != @sizeOf(Event)) return;
    
    // Interpret bytes as an event
    const event_ptr = @as(*const Event, @ptrCast(@alignCast(data.ptr)));
    const event = event_ptr.*;
    
    // Serialize
    var buf: [@sizeOf(Event)]u8 = undefined;
    serialize_event(event, &buf) catch return;
    
    // Deserialize
    const deserialized = deserialize_event(&buf) catch return;
    
    // Must match (except checksum which is recomputed)
    std.debug.assert(deserialized.tick == event.tick);
    std.debug.assert(deserialized.vu_id == event.vu_id);
    std.debug.assert(deserialized.event_type == event.event_type);
}
```

## Target 4: TOML Scenario Parser

Parse scenario files.

```zig
// fuzz/scenario_parser.zig

pub fn fuzz(data: []const u8) void {
    if (data.len > 1024 * 1024) return; // 1MB max scenario
    
    _ = Scenario.parse(data) catch return;
}
```

### Corpus

```toml
# Valid scenarios
corpus/scenario/valid/simple.toml
corpus/scenario/valid/complex.toml

# Invalid scenarios
corpus/scenario/invalid/missing_fields.toml
corpus/scenario/invalid/invalid_types.toml
corpus/scenario/invalid/malformed_toml.toml
```

## Target 5: URL Parser

Parse and validate URLs.

```zig
// fuzz/url_parser.zig

pub fn fuzz(data: []const u8) void {
    if (data.len > 2048) return; // Reasonable URL length
    
    _ = URL.parse(data) catch return;
}
```

### Test Cases

- Valid URLs (http, https)
- URLs with unusual characters
- Extremely long URLs
- URLs with special encoding
- Malformed URLs

## Target 6: Header Parser

Parse HTTP headers.

```zig
// fuzz/header_parser.zig

pub fn fuzz(data: []const u8) void {
    _ = parse_headers(data) catch return;
}
```

### Edge Cases

- Headers with no colon
- Headers with multiple colons
- Headers with whitespace variations
- Very long header values
- Binary data in headers

## Target 7: Chunked Encoding Parser

Parse chunked transfer encoding.

```zig
// fuzz/chunked_encoding.zig

pub fn fuzz(data: []const u8) void {
    var output: [10 * 1024]u8 = undefined;
    _ = parse_chunked_body(data, &output) catch return;
}
```

### Test Cases

- Valid chunked bodies
- Chunk sizes as hex
- Final chunk (size 0)
- Malformed chunk sizes
- Missing CRLF

## Target 8: HPACK Decoder

Decode HPACK-compressed headers.

```zig
// fuzz/hpack_decoder.zig

pub fn fuzz(data: []const u8) void {
    var decoder = HPACKDecoder.init(std.testing.allocator);
    defer decoder.deinit();
    
    var headers = std.ArrayList(Header).init(std.testing.allocator);
    defer headers.deinit();
    
    _ = decoder.decode(data, &headers) catch return;
}
```

### Invariants

- Dynamic table never exceeds max size
- No integer overflow in Huffman decoding
- All decoded headers are valid UTF-8

## Running Fuzzing

### Local Development

```bash
# Build all fuzz targets
zig build fuzz-targets

# Run single target for 1 minute
./zig-out/bin/fuzz_http1_response -max_total_time=60 corpus/http1_response/
```

### CI Pipeline

```bash
# Run each target for 10 minutes
for target in fuzz_*; do
    timeout 600 ./$target -max_total_time=600 corpus/$(basename $target)/
done
```

### Pre-Release

```bash
# 24-hour fuzz run
for target in fuzz_*; do
    timeout 86400 ./$target corpus/$(basename $target)/ &
done
wait
```

## Fuzzing Tools

### AFL++

```bash
# Instrument for AFL
export AFL_USE_ASAN=1
afl-clang-fast -o fuzz_target fuzz_target.c

# Run fuzzer
afl-fuzz -i corpus/ -o findings/ ./fuzz_target
```

### libFuzzer

```bash
# Build with libFuzzer
zig build-exe fuzz_target.zig -fsanitize=fuzzer,address

# Run
./fuzz_target corpus/

# Minimize corpus
./fuzz_target -merge=1 corpus_minimal/ corpus/
```

### Honggfuzz

```bash
# Build
honggfuzz -f corpus/ -- ./fuzz_target ___FILE___
```

## Sanitizers

Run fuzzing with sanitizers enabled:

### AddressSanitizer

Detects:
- Use-after-free
- Heap buffer overflow
- Stack buffer overflow
- Memory leaks

```bash
zig build fuzz -Dsanitize=address
```

### UndefinedBehaviorSanitizer

Detects:
- Integer overflow
- Null pointer dereference
- Division by zero
- Unaligned access

```bash
zig build fuzz -Dsanitize=undefined
```

### MemorySanitizer

Detects uninitialized memory reads:

```bash
zig build fuzz -Dsanitize=memory
```

## Crash Triage

When fuzzing finds a crash:

### 1. Reproduce

```bash
./fuzz_target crash-file
```

### 2. Minimize

```bash
# AFL
afl-tmin -i crash-file -o minimized-crash -- ./fuzz_target @@

# libFuzzer
./fuzz_target -minimize_crash=1 -exact_artifact_path=minimized crash-file
```

### 3. Debug

```bash
gdb --args ./fuzz_target minimized-crash
```

### 4. Write Regression Test

```zig
test "Regression: fuzz crash #123" {
    const input = @embedFile("crashes/crash-123.bin");
    
    // This should not crash
    _ = parse_http_response(input) catch |err| {
        // Expected error is OK
        try std.testing.expect(err == error.InvalidResponse);
        return;
    };
}
```

## Corpus Management

### Corpus Organization

```
corpus/
├── http1_response/
│   ├── valid/
│   │   ├── 200_ok.bin
│   │   └── ...
│   └── invalid/
│       ├── malformed.bin
│       └── ...
├── http2_frame/
│   ├── data_frame.bin
│   └── ...
└── scenario/
    ├── simple.toml
    └── ...
```

### Corpus Minimization

Reduce corpus size while maintaining coverage:

```bash
# libFuzzer
./fuzz_target -merge=1 corpus_min/ corpus/

# AFL
afl-cmin -i corpus/ -o corpus_min/ -- ./fuzz_target @@
```

### Corpus Synchronization

Share corpus across fuzz instances:

```bash
# Sync from other fuzzers
rsync -av fuzzer1:corpus/ corpus/
rsync -av fuzzer2:corpus/ corpus/

# Minimize merged corpus
./fuzz_target -merge=1 corpus_final/ corpus/
```

## Coverage Tracking

Measure fuzzing effectiveness:

```bash
# Build with coverage
zig build fuzz -Dcoverage

# Run fuzzer
./fuzz_target corpus/

# Generate coverage report
llvm-cov show ./fuzz_target -instr-profile=default.profdata

# Coverage should increase over time
# Target: >95% line coverage of parser code
```

## Performance Targets

| Metric | Target |
|--------|--------|
| Executions/second | >10,000 |
| Corpus size | <10,000 files |
| Max input size | 1 MB |
| Timeout per input | 1 second |
| Coverage | >95% of parser code |

## Continuous Fuzzing

Run fuzzing infrastructure 24/7:

### OSS-Fuzz Integration

```yaml
# .clusterfuzzlite/project.yaml
language: c
sanitizers:
  - address
  - undefined
  - memory
```

### Self-Hosted

```bash
# Start long-running fuzz jobs
for target in fuzz_*; do
    screen -dmS $target bash -c "
        while true; do
            ./$target corpus/$(basename $target)/
            sleep 60
        done
    "
done
```

## Fuzzing Checklist

Before release:

- [ ] All fuzz targets run for 24+ hours
- [ ] No crashes found
- [ ] >95% coverage on parsers
- [ ] Corpus minimized
- [ ] All crashes triaged
- [ ] Regression tests added

---

## Summary

Z6's fuzzing is:

- **Comprehensive** — All parsers covered
- **Continuous** — Always running
- **Systematic** — Corpus managed, crashes triaged
- **Effective** — High coverage, real bugs found

Fuzzing is how we prove robustness.

---

**Version 1.0 — October 2025**
