# Z6 Limits

> "Put a limit on everything. Unbounded systems cannot be reasoned about."

## Philosophy

Every resource in Z6 has an explicit upper bound. This ensures:

1. **Predictable behavior** — No surprises
2. **Deterministic execution** — Same limits always
3. **Resource planning** — Calculate requirements upfront
4. **Fail-fast** — Hit limits immediately, not in production

## Virtual Users

```zig
const VULimits = struct {
    max_vus: u32 = 100_000,          // Maximum VUs per run
    vu_memory_bytes: u32 = 65_536,   // 64 KB per VU
};
```

### Calculations

```
Total VU Memory = max_vus × vu_memory_bytes
                = 100,000 × 64 KB
                = 6.4 GB
```

### Why 100,000?

- One machine can reasonably manage 100K VUs
- Beyond that, distribution complexity not worth it
- 100K VUs can saturate most network links

## Event Log

```zig
const EventLogLimits = struct {
    max_events: u32 = 10_000_000,        // 10 million events
    event_size_bytes: u32 = 272,         // Fixed event size
    max_log_size_bytes: u64 = 2_720_000_000, // ~2.7 GB
    flush_interval_ticks: u32 = 10_000,  // Flush every 10K ticks
};
```

### Calculations

```
Max Log Size = max_events × event_size_bytes
             = 10,000,000 × 272 bytes
             = 2.72 GB
```

### Event Rate

```
Events per VU per second ≈ 2 (request + response)
Max VUs = 100,000
Max event rate = 200,000 events/second
Duration to fill log = 10,000,000 / 200,000 = 50 seconds
```

If log fills before test completes, increase flush rate or reduce VUs.

## Requests

```zig
const RequestLimits = struct {
    max_request_size: usize = 1_048_576,    // 1 MB
    max_response_size: usize = 10_485_760,  // 10 MB
    max_headers: u16 = 100,                 // Max headers per request/response
    max_header_size: usize = 8192,          // 8 KB per header
    max_url_length: usize = 2048,           // 2 KB URL
    max_body_size: usize = 10_485_760,      // 10 MB body
};
```

### Why These Limits?

- **1 MB request:** Most APIs don't need larger requests
- **10 MB response:** Reasonable for JSON/XML payloads
- **100 headers:** More than any reasonable API
- **8 KB header:** HTTP spec recommends 8 KB
- **2 KB URL:** Browsers support ~2000 chars

## Connections

```zig
const ConnectionLimits = struct {
    max_connections: u32 = 10_000,           // Per target
    max_connections_per_vu: u16 = 10,        // Per VU
    connection_timeout_ms: u32 = 10_000,     // 10 seconds
    idle_timeout_ms: u32 = 30_000,           // 30 seconds
    max_requests_per_conn: u32 = 1000,       // HTTP/1.1 keep-alive
};
```

### File Descriptors

```
FD Usage = max_connections + overhead
         = 10,000 + 100
         = 10,100 FDs

Check system limit:
ulimit -n
# Should be >10,100
```

If insufficient, increase:

```bash
ulimit -n 65536
```

## Memory

```zig
const MemoryLimits = struct {
    max_total_memory_gb: u32 = 16,           // 16 GB total
    vu_pool_memory_gb: u32 = 6,              // VU state
    event_log_memory_gb: u32 = 3,            // Event log
    protocol_handler_memory_mb: u32 = 512,   // Connections, buffers
    scheduler_memory_mb: u32 = 256,          // Scheduler state
};
```

### Total Memory Budget

```
VUs:               6.4 GB
Event Log:         2.7 GB
Protocol Handlers: 512 MB
Scheduler:         256 MB
Overhead:          1 GB
----------------------------
Total:            ~10.9 GB
```

Recommended minimum: **16 GB RAM**

## Timeouts

```zig
const TimeoutLimits = struct {
    dns_timeout_ms: u32 = 5_000,         // 5 seconds
    connection_timeout_ms: u32 = 10_000, // 10 seconds
    tls_timeout_ms: u32 = 10_000,        // 10 seconds
    request_timeout_ms: u32 = 30_000,    // 30 seconds
    read_timeout_ms: u32 = 30_000,       // 30 seconds
    write_timeout_ms: u32 = 30_000,      // 30 seconds
    
    // Maximum timeout (1 hour)
    max_timeout_ms: u32 = 3_600_000,
};
```

All timeouts are configurable but bounded by `max_timeout_ms`.

## Scheduler

```zig
const SchedulerLimits = struct {
    max_event_queue_size: u32 = 1_000_000,   // 1M pending events
    max_ticks: u64 = 86_400_000_000,         // 1 day at 1μs/tick
    cohort_max_size: u32 = 10_000,           // Max VUs in cohort
};
```

### Event Queue

```
Event Queue Size = max_event_queue_size × @sizeOf(ScheduledEvent)
                 = 1,000,000 × 32 bytes
                 = 32 MB
```

## Protocol-Specific Limits

### HTTP/1.1

```zig
const HTTP1Limits = struct {
    max_status_line_length: usize = 1024,
    max_header_line_length: usize = 8192,
    max_chunk_size: usize = 16_777_216,      // 16 MB
    max_redirects: u8 = 0,                   // No redirects
};
```

### HTTP/2

```zig
const HTTP2Limits = struct {
    max_concurrent_streams: u32 = 100,
    max_header_list_size: u32 = 8192,
    max_frame_size: u32 = 16_777_215,        // HTTP/2 spec max
    initial_window_size: u32 = 65_535,       // HTTP/2 default
    max_window_size: u32 = 2_147_483_647,    // HTTP/2 spec max
};
```

## Scenario Limits

```zig
const ScenarioLimits = struct {
    max_requests: u16 = 1000,                // Request definitions
    max_targets: u16 = 100,                  // Target endpoints
    max_scenario_size_mb: u32 = 10,          // TOML file size
    max_duration_seconds: u32 = 86_400,      // 24 hours
};
```

## Assertions

```zig
const AssertionLimits = struct {
    max_assertions: u16 = 100,               // Per scenario
};
```

## Output

```zig
const OutputLimits = struct {
    max_summary_length: usize = 1_048_576,   // 1 MB summary
    max_csv_rows: u32 = 1_000_000,           // 1M rows
    max_json_size_mb: u32 = 100,             // 100 MB JSON
};
```

## Disk I/O

```zig
const DiskLimits = struct {
    min_free_space_mb: u32 = 1024,           // 1 GB free required
    max_log_file_size_gb: u32 = 10,          // 10 GB max log
    flush_buffer_size_mb: u32 = 64,          // 64 MB flush buffer
};
```

## CPU

```zig
const CPULimits = struct {
    max_cpu_cores: u8 = 1,                   // Single-threaded
};
```

Z6 is single-threaded by design. No CPU limits beyond OS scheduling.

## Network

```zig
const NetworkLimits = struct {
    max_bandwidth_mbps: u32 = 10_000,        // 10 Gbps
    max_packet_size: usize = 9000,           // Jumbo frame
    max_retries: u8 = 3,                     // Connection retries
};
```

## Configuring Limits

Limits can be adjusted in the scenario:

```toml
[limits]
max_vus = 50000              # Lower than default
max_connections = 5000
max_event_log_size_mb = 5000
request_timeout_ms = 60000   # 1 minute
```

But never beyond compile-time maximum:

```zig
fn validate_limits(config: Config) !void {
    if (config.limits.max_vus > ABSOLUTE_MAX_VUS) {
        return error.VULimitExceeded;
    }
    
    if (config.limits.max_connections > ABSOLUTE_MAX_CONNECTIONS) {
        return error.ConnectionLimitExceeded;
    }
    
    // etc.
}
```

## Runtime Limit Checks

```zig
fn check_limits(scheduler: *Scheduler) !void {
    // Check VU count
    if (scheduler.vus.len > scheduler.config.limits.max_vus) {
        return error.TooManyVUs;
    }
    
    // Check event queue
    if (scheduler.events.len > scheduler.config.limits.max_event_queue_size) {
        return error.EventQueueFull;
    }
    
    // Check memory usage
    const memory_used = get_memory_usage();
    if (memory_used > scheduler.config.limits.max_total_memory_gb * 1_073_741_824) {
        return error.MemoryBudgetExceeded;
    }
}
```

## Exceeding Limits

When a limit is hit:

1. **Log error event**
2. **Apply backpressure** (if soft limit)
3. **Abort test** (if hard limit)

Example: Event log full

```zig
fn append_event(log: *EventLog, event: Event) !void {
    if (log.count >= log.limits.max_events) {
        try log.flush_to_disk();  // Try to make space
        
        if (log.count >= log.limits.max_events) {
            return error.EventLogFull;  // Hard limit
        }
    }
    
    log.buffer[log.count] = event;
    log.count += 1;
}
```

## Calculating Requirements

Use this formula to plan test requirements:

```
Memory (GB) = (VUs × 0.000064) + (Duration_seconds × RPS × 0.000000544) + 1

Where:
- VUs = Virtual users
- Duration_seconds = Test duration
- RPS = Requests per second
- 0.000064 = 64 KB per VU
- 0.000000544 = 544 bytes per request (2 events × 272 bytes)
- 1 = Overhead (scheduler, protocol handlers)
```

Example: 10K VUs, 60s, 10K RPS

```
Memory = (10,000 × 0.000064) + (60 × 10,000 × 0.000000544) + 1
       = 0.64 + 0.33 + 1
       = 1.97 GB
```

## Comparison to Other Tools

| Limit | K6 | Locust | Z6 |
|-------|-----|--------|-----|
| Max VUs | Unlimited* | Unlimited* | 100,000 |
| Max memory | Unlimited* | Unlimited* | 16 GB |
| Max event log | N/A | N/A | 10M events |
| Max request size | Configurable | Configurable | 1 MB |

*"Unlimited" until system resources exhausted. Z6 is explicit.

## Raising Limits

To increase limits, edit compile-time constants:

```zig
// src/limits.zig

pub const ABSOLUTE_MAX_VUS: u32 = 100_000;        // Change here
pub const ABSOLUTE_MAX_CONNECTIONS: u32 = 10_000;
pub const ABSOLUTE_MAX_EVENTS: u32 = 10_000_000;
```

Then rebuild:

```bash
zig build -Doptimize=ReleaseSafe
```

**Warning:** Raising limits increases memory usage. Ensure system has sufficient resources.

## Monitoring Limits

Z6 reports limit usage:

```
Resource Usage:
  VUs:           10,000 / 100,000 (10%)
  Connections:   5,000 / 10,000 (50%)
  Event Log:     2.5M / 10M events (25%)
  Memory:        4.2 GB / 16 GB (26%)
```

---

## Summary

Z6's limits are:

- **Explicit** — Every resource bounded
- **Predictable** — Calculate requirements upfront
- **Configurable** — Adjust per scenario
- **Enforced** — Violations fail fast

No surprises. No unbounded growth. This is Tiger Style.

---

**Version 1.0 — October 2025**
