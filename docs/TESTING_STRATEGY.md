# Z6 Testing Strategy

> "Can't prove correctness without rigorous testing."

## Testing Philosophy

Z6 follows TigerBeetle's testing discipline:

1. **Test before implement** — Write tests first
2. **Fuzz everything** — Protocol parsers, event handling, edge cases
3. **Property-based testing** — Prove invariants hold
4. **Determinism verification** — Replay must work
5. **No untested code** — Coverage is mandatory, not optional

## Testing Pyramid

```
         /\
        /  \  Fuzz Tests (1M+ inputs)
       /────\
      / Inte \
     / gration\ Integration Tests (scenarios)
    /──────────\
   /   Unit     \
  /    Tests     \ Unit Tests (functions, modules)
 /________________\
```

## Unit Tests

Test individual functions and modules in isolation.

### Requirements

- Every public function has a test
- Every error path has a test
- Edge cases are explicit

ly tested
- Minimum 90% code coverage

### Example

```zig
test "HTTPParser: parse status line" {
    const parser = HTTPParser.init();
    
    const input = "HTTP/1.1 200 OK\r\n";
    const result = try parser.parse_status_line(input);
    
    try std.testing.expectEqual(200, result.status_code);
    try std.testing.expectEqualStrings("OK", result.reason);
}

test "HTTPParser: invalid status line" {
    const parser = HTTPParser.init();
    
    const input = "NOT HTTP\r\n";
    const result = parser.parse_status_line(input);
    
    try std.testing.expectError(error.InvalidStatusLine, result);
}
```

### Assertion Density

Minimum 2 assertions per function:

```zig
fn send_request(handler: *HTTPHandler, req: Request) !Response {
    assert(handler != null);
    assert(req.path.len > 0);
    assert(req.timeout_ns > 0);
    
    const conn = try handler.pool.acquire(req.target);
    assert(conn.state == .CONNECTED);
    
    try handler.protocol.send(conn, req);
    
    const response = try handler.wait_for_response(req.id);
    assert(response.request_id == req.id);
    
    return response;
}
```

## Integration Tests

Test complete workflows end-to-end.

### Test Scenarios

```zig
test "E2E: simple GET request" {
    const scenario = try Scenario.init(.{
        .duration_seconds = 5,
        .vus = 10,
        .requests = &[_]Request{
            .{ .method = .GET, .path = "/api/test" },
        },
    });
    
    const result = try z6.run(scenario);
    
    try std.testing.expect(result.requests.total > 0);
    try std.testing.expect(result.errors.total == 0);
}
```

### Mock Backend

For integration tests, use a controlled mock server:

```zig
const MockServer = struct {
    port: u16,
    
    fn init() !MockServer {
        const server = try std.net.StreamServer.init(.{});
        try server.listen(std.net.Address.initIp4(.{0,0,0,0}, 0));
        
        return MockServer{ .port = server.listen_address.getPort() };
    }
    
    fn respond_with(self: *MockServer, status: u16, body: []const u8) !void {
        const conn = try self.server.accept();
        defer conn.stream.close();
        
        try conn.stream.writer().print(
            "HTTP/1.1 {} OK\r\n" ++
            "Content-Length: {}\r\n\r\n" ++
            "{}",
            .{status, body.len, body}
        );
    }
};
```

### Determinism Tests

Verify replay works:

```zig
test "Replay: deterministic execution" {
    const seed: u64 = 42;
    
    // Run 1
    const result1 = try z6.run_with_seed(scenario, seed);
    const events1 = try result1.event_log.read_all();
    
    // Run 2 (same seed)
    const result2 = try z6.run_with_seed(scenario, seed);
    const events2 = try result2.event_log.read_all();
    
    // Events must match exactly
    try std.testing.expectEqual(events1.len, events2.len);
    for (events1, events2) |e1, e2| {
        try std.testing.expectEqual(e1.tick, e2.tick);
        try std.testing.expectEqual(e1.event_type, e2.event_type);
        try std.testing.expectEqualSlices(u8, &e1.payload, &e2.payload);
    }
}
```

## Fuzz Testing

Discover bugs through randomized input.

### Fuzz Targets

#### 1. HTTP Response Parser

```zig
pub fn fuzz_http_response_parser(data: []const u8) void {
    const parser = HTTPParser.init();
    _ = parser.parse_response(data) catch return;
}
```

#### 2. Event Serialization

```zig
pub fn fuzz_event_serialization(data: []const u8) void {
    if (data.len < @sizeOf(Event)) return;
    
    const event = std.mem.bytesAsValue(Event, data[0..@sizeOf(Event)]);
    
    var buf: [1024]u8 = undefined;
    _ = serialize_event(event.*, &buf) catch return;
}
```

#### 3. Scenario Parser

```zig
pub fn fuzz_scenario_parser(data: []const u8) void {
    _ = Scenario.parse(data) catch return;
}
```

### Fuzzing Infrastructure

```zig
// Build fuzz target
const fuzz_exe = b.addExecutable(.{
    .name = "fuzz_http_parser",
    .root_source_file = .{ .path = "fuzz/http_parser.zig" },
});

// Run with AFL++
// afl-fuzz -i corpus/ -o findings/ ./zig-out/bin/fuzz_http_parser

// Or libFuzzer
// zig build fuzz_http_parser && ./zig-out/bin/fuzz_http_parser corpus/
```

### Fuzzing Budget

Each fuzz target runs for:

- **Local development:** 1 minute
- **CI:** 10 minutes
- **Pre-release:** 24 hours

Target: 1 million inputs minimum per target.

## Property-Based Testing

Verify invariants hold for all inputs.

### Example Properties

```zig
test "Property: request count equals responses + errors" {
    var prng = std.rand.DefaultPrng.init(42);
    const random = prng.random();
    
    for (0..100) |_| {
        const vus = random.intRangeAtMost(u16, 1, 1000);
        const duration = random.intRangeAtMost(u16, 1, 60);
        
        const scenario = try generate_random_scenario(vus, duration, random);
        const result = try z6.run(scenario);
        
        // Invariant: requests = responses + errors
        const total = result.requests.success + result.errors.total;
        try std.testing.expectEqual(result.requests.total, total);
    }
}
```

### Invariants to Test

1. **Request/Response pairing** — Every request produces exactly one result
2. **Event ordering** — Events respect happens-before
3. **Metric consistency** — Derived metrics match event counts
4. **Memory bounds** — No allocation exceeds budget
5. **Determinism** — Same seed → same output

## Performance Testing

Verify performance characteristics.

### Benchmarks

```zig
test "Benchmark: event log append" {
    var log = try EventLog.init(10_000_000);
    defer log.deinit();
    
    const event = Event{
        .tick = 1000,
        .vu_id = 42,
        .event_type = .request_issued,
        .payload = undefined,
    };
    
    const start = std.time.nanoTimestamp();
    
    for (0..1_000_000) |_| {
        try log.append(event);
    }
    
    const end = std.time.nanoTimestamp();
    const elapsed_ns = @as(u64, @intCast(end - start));
    const ns_per_append = elapsed_ns / 1_000_000;
    
    std.debug.print("Event append: {}ns\n", .{ns_per_append});
    
    // Assert performance requirement
    try std.testing.expect(ns_per_append < 1000);  // <1μs
}
```

### Performance Targets

| Operation | Target | Test |
|-----------|--------|------|
| Event append | <1μs | Benchmark |
| Event serialize | <500ns | Benchmark |
| Parser (HTTP) | <10μs | Benchmark |
| Scheduler tick | <100ns | Benchmark |

## Regression Testing

Prevent bugs from reappearing.

### Regression Suite

When a bug is found:

1. Write a failing test that reproduces it
2. Fix the bug
3. Verify test now passes
4. Add test to regression suite

```zig
// Regression test for issue #42: ConnectionReset not logged
test "Regression: #42 log ConnectionReset error" {
    const mock = try MockServer.init();
    defer mock.deinit();
    
    // Mock server closes connection immediately
    mock.close_after_accept = true;
    
    const scenario = try Scenario.init(.{
        .target = try std.fmt.allocPrint(allocator, "http://localhost:{}", .{mock.port}),
        .requests = &[_]Request{.{ .method = .GET, .path = "/" }},
    });
    
    const result = try z6.run(scenario);
    const events = try result.event_log.read_all();
    
    // Must have error event
    var found_error = false;
    for (events) |event| {
        if (event.event_type == .error_tcp) {
            found_error = true;
            break;
        }
    }
    
    try std.testing.expect(found_error);
}
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Test

on: [push, pull_request]

jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2
        with:
          version: 0.11.0
      - run: zig build test
      
  integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2
      - run: zig build test-integration
      
  fuzz:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: goto-bus-stop/setup-zig@v2
      - run: zig build fuzz --timeout 600  # 10 minutes
```

### Pre-commit Hooks

```bash
#!/bin/bash
# .git/hooks/pre-commit

zig fmt --check src/
zig build test
zig build test-integration

if [ $? -ne 0 ]; then
    echo "Tests failed. Commit aborted."
    exit 1
fi
```

## Test Coverage

### Measurement

```bash
zig build test -Dtest-coverage
kcov --exclude-pattern=/usr coverage/ ./zig-out/bin/test
```

### Requirements

- **Overall:** >90% line coverage
- **Core modules:** >95% line coverage
- **Protocol handlers:** >98% line coverage

### Coverage Report

```
File                          Lines    Exec    Cover
----------------------------------------------------
src/scheduler.zig             1,234    1,180   95.6%
src/event_log.zig             856      842     98.4%
src/http/parser.zig           2,134    2,098   98.3%
src/metrics.zig               567      542     95.6%
----------------------------------------------------
Total                         12,456   11,892  95.5%
```

## Mutation Testing

Verify tests catch bugs:

```bash
# mutagen: https://github.com/alexliesenfeld/mutagen
zig build test --mutate
```

Mutation testing changes code and verifies tests fail. If tests still pass after mutation, tests are insufficient.

## Test Organization

```
tests/
├── unit/
│   ├── scheduler_test.zig
│   ├── event_log_test.zig
│   └── http_parser_test.zig
├── integration/
│   ├── simple_get_test.zig
│   ├── concurrent_requests_test.zig
│   └── determinism_test.zig
├── fuzz/
│   ├── http_parser_fuzz.zig
│   ├── event_serialization_fuzz.zig
│   └── corpus/
│       ├── valid_responses/
│       └── invalid_inputs/
├── regression/
│   ├── issue_42_test.zig
│   └── issue_58_test.zig
└── benchmarks/
    ├── event_log_bench.zig
    └── http_parser_bench.zig
```

---

## Summary

Z6's testing is:

- **Comprehensive** — Unit, integration, fuzz, property
- **Automated** — CI/CD, pre-commit hooks
- **Measurable** — Coverage, benchmarks
- **Deterministic** — Replay verification

Testing is not optional. It's how we prove correctness.

---

**Version 1.0 — October 2025**
