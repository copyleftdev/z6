# Z6 Metrics

> "All metrics are derived from events. No estimation, only exact computation."

## Philosophy

Z6 computes metrics **post-run** from the immutable event log. This ensures:

1. **Reproducibility** — Same events → same metrics, always
2. **Accuracy** — No sampling, no approximation
3. **Flexibility** — Compute different metrics without re-running tests
4. **Auditability** — Trace every metric to source events

## Core Metrics

### Request Count

Total requests issued:

```
total_requests = COUNT(event_type == request_issued)
```

### Success Rate

Percentage of successful responses:

```
successes = COUNT(event_type == response_received AND status_code < 400)
failures = COUNT(event_type IN (response_error, request_timeout))
success_rate = successes / (successes + failures)
```

### Latency Distribution

Time from request issuance to response completion:

```zig
const LatencyMetrics = struct {
    min: u64,
    max: u64,
    mean: f64,
    p50: u64,
    p90: u64,
    p95: u64,
    p99: u64,
    p999: u64,
};
```

Computed using **HDR Histogram** for accuracy.

### Throughput

Requests per second (RPS):

```
rps = total_requests / duration_seconds
```

### Error Rate

Percentage of failed requests:

```
error_rate = failures / total_requests
```

### Connection Metrics

```zig
const ConnectionMetrics = struct {
    total_connections: u32,
    connection_errors: u32,
    avg_connection_time_ns: u64,
    connections_reused: u32,
};
```

## HDR Histogram

Z6 uses **HdrHistogram** for latency tracking:

### Why HDR Histogram?

- **Accurate percentiles** — No binning errors
- **Bounded memory** — Fixed size regardless of sample count
- **Fast queries** — O(1) percentile computation

### Configuration

```zig
const HDRConfig = struct {
    lowest_trackable_value: u64 = 1,           // 1 nanosecond
    highest_trackable_value: u64 = 3600_000_000_000, // 1 hour
    significant_figures: u8 = 3,               // 0.1% precision
};
```

### Usage

```zig
fn compute_latency_metrics(events: []const Event) !LatencyMetrics {
    var histogram = try HdrHistogram.init(HDRConfig{});
    defer histogram.deinit();
    
    // Record all latencies
    for (events) |event| {
        if (event.event_type == .response_received) {
            const payload = event.payload.cast(ResponseReceivedPayload);
            try histogram.record_value(payload.latency_ns);
        }
    }
    
    // Compute percentiles
    return LatencyMetrics{
        .min = histogram.min(),
        .max = histogram.max(),
        .mean = histogram.mean(),
        .p50 = histogram.value_at_percentile(50.0),
        .p90 = histogram.value_at_percentile(90.0),
        .p95 = histogram.value_at_percentile(95.0),
        .p99 = histogram.value_at_percentile(99.0),
        .p999 = histogram.value_at_percentile(99.9),
    };
}
```

## Metrics Reducer

The metrics reducer processes events post-run:

```zig
const MetricsReducer = struct {
    allocator: Allocator,
    event_log: *EventLog,
    
    fn compute(reducer: *MetricsReducer) !Metrics {
        const events = try reducer.event_log.read_all();
        
        return Metrics{
            .requests = try compute_request_metrics(events),
            .latency = try compute_latency_metrics(events),
            .throughput = try compute_throughput_metrics(events),
            .connections = try compute_connection_metrics(events),
            .errors = try compute_error_metrics(events),
        };
    }
};
```

### Request Metrics

```zig
fn compute_request_metrics(events: []const Event) !RequestMetrics {
    var total: u64 = 0;
    var by_method = std.StringHashMap(u64).init(allocator);
    var by_status = std.AutoHashMap(u16, u64).init(allocator);
    
    for (events) |event| {
        switch (event.event_type) {
            .request_issued => {
                total += 1;
                const payload = event.payload.cast(RequestIssuedPayload);
                const count = by_method.get(payload.method) orelse 0;
                try by_method.put(payload.method, count + 1);
            },
            .response_received => {
                const payload = event.payload.cast(ResponseReceivedPayload);
                const count = by_status.get(payload.status_code) orelse 0;
                try by_status.put(payload.status_code, count + 1);
            },
            else => {},
        }
    }
    
    return RequestMetrics{
        .total = total,
        .by_method = by_method,
        .by_status = by_status,
    };
}
```

### Throughput Over Time

```zig
fn compute_throughput_over_time(events: []const Event, interval_ticks: u64) ![]ThroughputSample {
    var samples = ArrayList(ThroughputSample).init(allocator);
    
    var current_tick: u64 = 0;
    var count: u32 = 0;
    
    for (events) |event| {
        if (event.event_type != .response_received) continue;
        
        // New interval?
        if (event.header.tick >= current_tick + interval_ticks) {
            try samples.append(.{
                .tick = current_tick,
                .rps = @as(f64, @floatFromInt(count)) / tick_to_seconds(interval_ticks),
            });
            
            current_tick += interval_ticks;
            count = 0;
        }
        
        count += 1;
    }
    
    return samples.toOwnedSlice();
}
```

## Error Metrics

```zig
const ErrorMetrics = struct {
    total_errors: u64,
    by_type: HashMap(ErrorType, u64),
    error_rate: f64,
};

fn compute_error_metrics(events: []const Event) !ErrorMetrics {
    var total: u64 = 0;
    var by_type = std.AutoHashMap(ErrorType, u64).init(allocator);
    
    for (events) |event| {
        const is_error = switch (event.event_type) {
            .error_dns,
            .error_tcp,
            .error_tls,
            .error_http,
            .error_timeout,
            .error_protocol_violation,
            => true,
            else => false,
        };
        
        if (is_error) {
            total += 1;
            const count = by_type.get(event.event_type) orelse 0;
            try by_type.put(event.event_type, count + 1);
        }
    }
    
    const total_requests = count_requests(events);
    const error_rate = @as(f64, @floatFromInt(total)) / @as(f64, @floatFromInt(total_requests));
    
    return ErrorMetrics{
        .total_errors = total,
        .by_type = by_type,
        .error_rate = error_rate,
    };
}
```

## Custom Metrics

Users can define custom metrics via event filtering:

```zig
const CustomMetric = struct {
    name: []const u8,
    filter: *const fn(Event) bool,
    aggregation: AggregationType,
};

const AggregationType = enum {
    count,
    sum,
    avg,
    min,
    max,
    percentile,
};
```

Example: Count 5xx errors

```zig
const metric = CustomMetric{
    .name = "5xx_errors",
    .filter = &struct {
        fn f(event: Event) bool {
            if (event.event_type != .response_received) return false;
            const payload = event.payload.cast(ResponseReceivedPayload);
            return payload.status_code >= 500;
        }
    }.f,
    .aggregation = .count,
};
```

## Assertions

Assertions are **post-run checks**:

```zig
const Assertion = struct {
    name: []const u8,
    check: *const fn(Metrics) bool,
    expected: []const u8,
};
```

Example assertions:

```zig
const assertions = &[_]Assertion{
    .{
        .name = "p99 latency under 100ms",
        .check = &struct {
            fn f(m: Metrics) bool {
                return m.latency.p99 < 100_000_000; // 100ms in ns
            }
        }.f,
        .expected = "p99 < 100ms",
    },
    .{
        .name = "error rate under 1%",
        .check = &struct {
            fn f(m: Metrics) bool {
                return m.errors.error_rate < 0.01;
            }
        }.f,
        .expected = "error_rate < 1%",
    },
    .{
        .name = "success rate above 99%",
        .check = &struct {
            fn f(m: Metrics) bool {
                return m.requests.success_rate > 0.99;
            }
        }.f,
        .expected = "success_rate > 99%",
    },
};
```

Assertion failures are logged as events.

## Output Formats

### Human-Readable Summary

```
Z6 Load Test Results
====================

Duration: 60.0s
Virtual Users: 100

Requests
--------
Total: 120,000
Success: 119,500 (99.6%)
Failed: 500 (0.4%)

Latency (ms)
------------
Min: 5.2
Max: 523.1
Mean: 42.3
p50: 38.5
p90: 67.2
p95: 89.4
p99: 142.7
p999: 318.2

Throughput
----------
RPS: 2,000
Peak RPS: 2,341
Min RPS: 1,689

Errors
------
Timeouts: 300 (60%)
Connection Errors: 150 (30%)
HTTP 5xx: 50 (10%)

Assertions
----------
✓ p99 latency under 100ms: PASS (p99=89.4ms)
✗ error rate under 1%: FAIL (error_rate=0.4%)
✓ success rate above 99%: PASS (success_rate=99.6%)
```

### JSON Output

```json
{
  "duration_seconds": 60.0,
  "vus": 100,
  "requests": {
    "total": 120000,
    "success": 119500,
    "failed": 500,
    "success_rate": 0.996
  },
  "latency": {
    "min_ns": 5200000,
    "max_ns": 523100000,
    "mean_ns": 42300000,
    "p50_ns": 38500000,
    "p90_ns": 67200000,
    "p95_ns": 89400000,
    "p99_ns": 142700000,
    "p999_ns": 318200000
  },
  "throughput": {
    "rps": 2000,
    "peak_rps": 2341,
    "min_rps": 1689
  },
  "errors": {
    "total": 500,
    "by_type": {
      "timeout": 300,
      "connection_error": 150,
      "http_5xx": 50
    },
    "error_rate": 0.004
  },
  "assertions": [
    {
      "name": "p99 latency under 100ms",
      "passed": true,
      "actual": "89.4ms"
    },
    {
      "name": "error rate under 1%",
      "passed": false,
      "actual": "0.4%"
    }
  ]
}
```

### CSV Output

For time-series analysis:

```csv
tick,rps,latency_p50,latency_p99,errors
0,1850,35.2,98.3,2
1000,2100,38.1,105.7,3
2000,2050,37.9,102.4,1
3000,1980,36.5,99.8,4
...
```

## Metrics Storage

Metrics are computed once and stored:

```
test_results/
├── run_2025-10-31_12-00-00/
│   ├── events.log          # Raw event log
│   ├── metrics.json        # Computed metrics
│   ├── summary.txt         # Human-readable summary
│   └── timeseries.csv      # Time-series data
```

## Comparison Tool

Compare two runs:

```bash
z6 diff run1/ run2/
```

Output:

```
Comparing run1 vs run2:

Requests: 120,000 → 125,000 (+4.2%)
Success Rate: 99.6% → 99.8% (+0.2pp)

Latency (ms):
  p50: 38.5 → 35.2 (-8.6%)
  p99: 142.7 → 128.3 (-10.1%)

Throughput:
  RPS: 2,000 → 2,083 (+4.2%)

Errors: 500 → 250 (-50.0%)
```

## Performance

Metrics computation is fast:

| Events | Metrics Compute Time |
|--------|---------------------|
| 10K | <10ms |
| 100K | <50ms |
| 1M | <300ms |
| 10M | <3s |

Single pass over events, O(N) complexity.

## Precision Guarantees

- **Latency:** Nanosecond precision (hardware dependent)
- **Percentiles:** 0.1% relative error (HDR Histogram)
- **Counts:** Exact (no sampling)
- **Rates:** Floating-point precision

---

## Summary

Z6's metrics are:

- **Exact** — No sampling, no approximation
- **Reproducible** — Same events → same metrics
- **Flexible** — Compute different views without re-running
- **Auditable** — Trace to source events

---

**Version 1.0 — October 2025**
