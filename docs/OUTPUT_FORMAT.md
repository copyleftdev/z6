# Z6 Output Format

> "Clear, parseable, auditable."

## Output Directory Structure

After a test run:

```
results/run_2025-10-31_120000/
├── events.log          # Binary event log
├── metrics.json        # Computed metrics
├── summary.txt         # Human-readable summary
├── timeseries.csv      # Time-series data
├── config.toml         # Scenario used
└── metadata.json       # Run metadata
```

## Event Log Format

Binary format for maximum efficiency and determinism.

### File Header

```
Offset | Size | Field
-------|------|------
0      | 8    | Magic: 0x5A36_4556_5420 ("Z6EVT ")
8      | 2    | Version: 1
10     | 6    | Reserved
16     | 8    | PRNG seed
24     | 8    | Start timestamp (Unix ns)
32     | 32   | Scenario hash (SHA256)
64     | --   | Events begin
```

### Event Structure

Each event is 272 bytes:

```
Offset | Size | Field
-------|------|------
0      | 8    | Tick (u64)
8      | 4    | VU ID (u32)
12     | 2    | Event type (u16)
14     | 2    | Reserved
16     | 240  | Payload (event-specific)
256    | 8    | Checksum (CRC64)
```

### File Footer

```
Offset | Size | Field
-------|------|------
-64    | 8    | Total events (u64)
-56    | 32   | Log checksum (SHA256)
-24    | 8    | End timestamp (Unix ns)
-16    | 16   | Reserved
```

## Metrics JSON

Complete metrics in JSON format:

```json
{
  "version": "1.0",
  "run_id": "run_2025-10-31_120000",
  "scenario": {
    "name": "API Load Test",
    "version": "1.0"
  },
  "runtime": {
    "start_time": "2025-10-31T12:00:00Z",
    "end_time": "2025-10-31T12:01:00Z",
    "duration_seconds": 60.0,
    "vus": 100,
    "seed": 42
  },
  "requests": {
    "total": 120000,
    "success": 119500,
    "failed": 500,
    "success_rate": 0.996,
    "by_method": {
      "GET": 90000,
      "POST": 30000
    },
    "by_status": {
      "200": 115000,
      "201": 4500,
      "404": 100,
      "500": 400
    }
  },
  "latency": {
    "min_ns": 5200000,
    "max_ns": 523100000,
    "mean_ns": 42300000,
    "stddev_ns": 15200000,
    "p50_ns": 38500000,
    "p90_ns": 67200000,
    "p95_ns": 89400000,
    "p99_ns": 142700000,
    "p999_ns": 318200000
  },
  "throughput": {
    "rps": 2000.0,
    "peak_rps": 2341.0,
    "min_rps": 1689.0
  },
  "connections": {
    "total": 150,
    "reused": 149850,
    "errors": 50,
    "avg_connection_time_ns": 12500000
  },
  "errors": {
    "total": 500,
    "rate": 0.004,
    "by_type": {
      "timeout": 300,
      "connection_error": 150,
      "http_5xx": 50
    }
  },
  "assertions": [
    {
      "name": "p99 latency under 100ms",
      "passed": true,
      "expected": "p99 < 100ms",
      "actual": "89.4ms"
    },
    {
      "name": "error rate under 1%",
      "passed": true,
      "expected": "error_rate < 1%",
      "actual": "0.4%"
    }
  ]
}
```

## Summary Text

Human-readable report:

```
Z6 Load Test Results
====================

Run ID: run_2025-10-31_120000
Scenario: API Load Test v1.0
Started: 2025-10-31 12:00:00 UTC
Duration: 60.0s
Seed: 42

Configuration
-------------
Virtual Users: 100
HTTP Version: HTTP/2
Target: https://api.example.com

Requests
--------
Total:    120,000
Success:  119,500 (99.6%)
Failed:   500 (0.4%)

By Method:
  GET:    90,000 (75.0%)
  POST:   30,000 (25.0%)

By Status:
  2xx:    119,500 (99.6%)
  4xx:    100 (0.1%)
  5xx:    400 (0.3%)

Latency (milliseconds)
----------------------
Min:     5.2
Max:     523.1
Mean:    42.3 ± 15.2
Median:  38.5

Percentiles:
  p50:   38.5
  p90:   67.2
  p95:   89.4
  p99:   142.7
  p999:  318.2

Throughput
----------
Average:  2,000 req/s
Peak:     2,341 req/s
Minimum:  1,689 req/s

Connections
-----------
Established:  150
Reused:       149,850 (99.9%)
Failed:       50 (0.03%)
Avg Connect:  12.5ms

Errors (500 total, 0.4%)
------------------------
Timeout:           300 (60.0%)
Connection Error:  150 (30.0%)
HTTP 5xx:          50 (10.0%)

Assertions
----------
✓ p99 latency under 100ms
  Expected: p99 < 100ms
  Actual:   89.4ms

✓ error rate under 1%
  Expected: error_rate < 1%
  Actual:   0.4%

✓ success rate above 99%
  Expected: success_rate > 99%
  Actual:   99.6%

Result: PASS (3/3 assertions passed)
```

## Time-Series CSV

For graphing and analysis:

```csv
tick,timestamp_ns,rps,latency_min_ns,latency_p50_ns,latency_p99_ns,errors,active_vus
0,1698753600000000000,0,0,0,0,0,0
1000,1698753601000000000,1850,5200000,35200000,98300000,2,100
2000,1698753602000000000,2100,5100000,38100000,105700000,3,100
3000,1698753603000000000,2050,5300000,37900000,102400000,1,100
...
```

Columns:

- `tick` — Logical tick
- `timestamp_ns` — Wall-clock time (nanoseconds since epoch)
- `rps` — Requests per second in this interval
- `latency_min_ns` — Minimum latency in interval
- `latency_p50_ns` — Median latency in interval
- `latency_p99_ns` — p99 latency in interval
- `errors` — Errors in this interval
- `active_vus` — Active VUs

## Metadata JSON

Run metadata:

```json
{
  "run_id": "run_2025-10-31_120000",
  "z6_version": "1.0.0",
  "zig_version": "0.11.0",
  "hostname": "loadtest-01",
  "os": "Linux 6.1.0",
  "cpu": "AMD EPYC 7763",
  "memory_gb": 128,
  "scenario_file": "/path/to/scenario.toml",
  "scenario_hash": "a3b5c7d9...",
  "command": "z6 run scenario.toml --seed 42",
  "start_time": "2025-10-31T12:00:00Z",
  "end_time": "2025-10-31T12:01:00Z",
  "exit_code": 0
}
```

## Diff Output

Comparing two runs:

### Text Format

```
Z6 Diff: run1 vs run2
=====================

Requests
--------
Total:        120,000 → 125,000  (+4.2%)
Success Rate: 99.6%   → 99.8%    (+0.2pp)

Latency (ms)
------------
                run1    run2     delta
Min:            5.2     4.8      -7.7%   ✓
p50:            38.5    35.2     -8.6%   ✓
p90:            67.2    61.3     -8.8%   ✓
p99:            142.7   128.3    -10.1%  ✓
Max:            523.1   489.2    -6.5%   ✓

Throughput
----------
RPS:            2,000   2,083    +4.2%

Errors
------
Total:          500     250      -50.0%  ✓
Timeout:        300     100      -66.7%  ✓
Connection:     150     100      -33.3%  ✓
HTTP 5xx:       50      50       0.0%

Legend: ✓ = improved, ✗ = regressed, - = unchanged
```

### JSON Format

```json
{
  "run1": "run_2025-10-31_120000",
  "run2": "run_2025-10-31_130000",
  "comparison": {
    "requests": {
      "total": { "run1": 120000, "run2": 125000, "delta": 5000, "delta_pct": 4.2 },
      "success_rate": { "run1": 0.996, "run2": 0.998, "delta": 0.002 }
    },
    "latency": {
      "p99_ns": { "run1": 142700000, "run2": 128300000, "delta": -14400000, "delta_pct": -10.1, "improved": true }
    },
    "errors": {
      "total": { "run1": 500, "run2": 250, "delta": -250, "delta_pct": -50.0, "improved": true }
    }
  }
}
```

## Export Formats

### Prometheus

```
# HELP z6_requests_total Total number of requests
# TYPE z6_requests_total counter
z6_requests_total{scenario="api_test"} 120000

# HELP z6_latency_seconds Request latency
# TYPE z6_latency_seconds summary
z6_latency_seconds{scenario="api_test",quantile="0.5"} 0.0385
z6_latency_seconds{scenario="api_test",quantile="0.99"} 0.1427
z6_latency_seconds_count{scenario="api_test"} 120000
```

### InfluxDB Line Protocol

```
z6_requests,scenario=api_test,run=run1 total=120000,success=119500,failed=500 1698753600000000000
z6_latency,scenario=api_test,run=run1 p50=38500000,p99=142700000 1698753600000000000
z6_errors,scenario=api_test,run=run1 total=500,timeout=300 1698753600000000000
```

## Parsing Event Logs

Z6 provides a library for parsing event logs:

```zig
const z6 = @import("z6");

const log = try z6.EventLog.open("events.log");
defer log.close();

// Verify checksum
try log.verify();

// Read metadata
const metadata = try log.read_header();
std.debug.print("Seed: {}\n", .{metadata.seed});

// Iterate events
var iter = log.iterator();
while (iter.next()) |event| {
    if (event.event_type == .response_received) {
        const payload = event.payload.cast(ResponseReceivedPayload);
        std.debug.print("Latency: {}ns\n", .{payload.latency_ns});
    }
}
```

---

## Summary

Z6's output is:

- **Complete** — Everything you need for analysis
- **Structured** — Machine and human readable
- **Auditable** — Traceable to source events
- **Standard** — Works with existing tools

---

**Version 1.0 — October 2025**
