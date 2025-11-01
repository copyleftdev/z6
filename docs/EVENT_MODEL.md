# Z6 Event Model

> "Events are the source of truth. Everything else is derived."

## Overview

In Z6, **everything that happens is recorded as an immutable event**. The event log is the single source of truth for:

- What was executed
- When it was executed (logical time)
- What the results were
- Why failures occurred

Events enable deterministic replay, forensic analysis, and provable correctness.

## Event as Ledger Entry

Think of Z6's event log like TigerBeetle's accounting ledger:

- **Transfers** (TigerBeetle) = **Requests** (Z6)
- **Accounts** (TigerBeetle) = **Virtual Users** (Z6)
- **Balances** (TigerBeetle) = **Metrics** (Z6)

Just as TigerBeetle guarantees financial correctness through immutable ledger entries, Z6 guarantees measurement correctness through immutable events.

## Event Structure

All events share a common header:

```zig
const EventHeader = struct {
    /// Logical timestamp (monotonic, deterministic)
    tick: u64,
    
    /// Virtual user that emitted this event
    vu_id: u32,
    
    /// Event type discriminator
    event_type: EventType,
    
    /// Reserved for alignment
    _reserved: u32,
};
```

Total header size: 24 bytes

## Event Types

### Core Event Types

```zig
const EventType = enum(u16) {
    // Lifecycle Events
    vu_spawned,
    vu_ready,
    vu_complete,
    
    // Request Events
    request_issued,
    request_timeout,
    request_cancelled,
    
    // Response Events
    response_received,
    response_error,
    
    // Connection Events
    conn_established,
    conn_closed,
    conn_error,
    
    // Scheduler Events
    scheduler_tick,
    
    // Assertion Events
    assertion_passed,
    assertion_failed,
    
    // Error Events
    error_dns,
    error_tcp,
    error_tls,
    error_http,
    error_timeout,
    error_protocol_violation,
    error_resource_exhausted,
};
```

### Event Payload Structure

Each event type has a fixed-size payload (240 bytes). Payloads are zero-padded.

```zig
const Event = struct {
    header: EventHeader,          // 24 bytes
    payload: [240]u8,             // 240 bytes
    checksum: u64,                // 8 bytes (CRC64)
};
```

Total event size: **272 bytes** (aligned to cache line)

## Event Schemas

### 1. VU Spawned

```zig
const VUSpawnedPayload = struct {
    vu_id: u32,
    scenario_id: u32,
    _padding: [232]u8,
};
```

**When emitted:** VU initialization

**Semantics:** A virtual user has been allocated and is ready to begin execution.

### 2. Request Issued

```zig
const RequestIssuedPayload = struct {
    request_id: u64,
    method: [8]u8,           // "GET", "POST", etc. (fixed-width)
    url_hash: u64,           // SHA256 hash of full URL
    header_count: u16,
    body_size: u32,
    _padding: [206]u8,
};
```

**When emitted:** VU issues an HTTP request

**Semantics:** A request has been constructed and sent to the protocol handler.

### 3. Response Received

```zig
const ResponseReceivedPayload = struct {
    request_id: u64,
    status_code: u16,
    header_size: u32,
    body_size: u32,
    latency_ns: u64,         // Nanosecond precision
    _padding: [202]u8,
};
```

**When emitted:** HTTP response fully received

**Semantics:** A response was successfully received. Latency is measured from request issuance to full body reception.

### 4. Connection Established

```zig
const ConnEstablishedPayload = struct {
    conn_id: u64,
    remote_addr_hash: u64,   // Hash of IP:port
    protocol: u8,            // 0=HTTP/1.1, 1=HTTP/2, 2=gRPC, etc.
    tls: bool,
    conn_time_ns: u64,
    _padding: [215]u8,
};
```

**When emitted:** TCP connection established (before request)

**Semantics:** Network connection successfully created.

### 5. Error Events

```zig
const ErrorPayload = struct {
    request_id: u64,
    error_code: u32,         // Maps to ErrorTaxonomy
    error_context: [200]u8,  // Human-readable context (truncated)
    _padding: [28]u8,
};
```

**When emitted:** Any failure condition

**Semantics:** Something went wrong. `error_code` maps to the error taxonomy. `error_context` provides debugging information.

### 6. Scheduler Tick

```zig
const SchedulerTickPayload = struct {
    tick: u64,
    active_vus: u32,
    pending_events: u32,
    _padding: [224]u8,
};
```

**When emitted:** Every scheduler tick (configurable interval, e.g., every 1000 ticks)

**Semantics:** Periodic heartbeat for replay synchronization.

### 7. Assertion Failed

```zig
const AssertionFailedPayload = struct {
    assertion_id: u32,
    expected_value: f64,
    actual_value: f64,
    description: [200]u8,    // Assertion description
    _padding: [20]u8,
};
```

**When emitted:** Post-run assertion check fails

**Semantics:** A declared assertion (e.g., "p99 < 100ms") was violated.

## Event Ordering Guarantees

### Total Order

Events are **totally ordered** by `(tick, vu_id, sequence_number)`:

1. **Primary key:** `tick` — Logical timestamp
2. **Secondary key:** `vu_id` — Virtual user ID
3. **Tertiary key:** `sequence_number` — Monotonic counter per VU

This guarantees deterministic ordering even when multiple events occur at the same logical tick.

### Causality

Events respect happens-before relationships:

- `request_issued` ≺ `response_received` (same `request_id`)
- `vu_spawned` ≺ `request_issued` (same `vu_id`)
- `conn_established` ≺ `request_issued` (if new connection required)

Violations of causality indicate replay corruption.

## Event Log Format

### Binary Layout

The event log is a flat binary file:

```
┌────────────────────────────────────┐
│  Header (64 bytes)                 │
│  - Magic number: 0x5A36_4556_5420  │
│  - Version: u16                    │
│  - PRNG seed: u64                  │
│  - Scenario hash: [32]u8           │
├────────────────────────────────────┤
│  Event 0 (272 bytes)               │
├────────────────────────────────────┤
│  Event 1 (272 bytes)               │
├────────────────────────────────────┤
│  ...                               │
├────────────────────────────────────┤
│  Event N (272 bytes)               │
├────────────────────────────────────┤
│  Footer (64 bytes)                 │
│  - Event count: u64                │
│  - Log checksum: [32]u8 (SHA256)   │
└────────────────────────────────────┘
```

### Append Semantics

- **Append-only** — Events are never modified
- **Lock-free** — Single writer (scheduler), single reader (metrics reducer)
- **Bounded buffer** — Ring buffer with backpressure when full
- **Crash-safe** — Events flushed to disk periodically (configurable)

### Size Limits

| Limit | Default | Rationale |
|-------|---------|-----------|
| Max events | 10 million | Prevents unbounded growth |
| Max log size | 2.5 GB | ~10M events × 272 bytes |
| Flush interval | 10,000 events | Balance safety/performance |

When limits are reached:

- **Backpressure:** Scheduler pauses until space available
- **Overflow:** Test aborts with `ResourceExhausted` error

## Determinism Properties

### Replay Invariants

For a run to be **deterministically replayable**, the following must hold:

1. **Same PRNG seed** → Same random values
2. **Same scenario** → Same VU behavior
3. **Same logical ticks** → Same event ordering
4. **Same event log** → Bit-for-bit identical events

### Non-Deterministic Sources (Eliminated)

| Source | How Z6 Eliminates It |
|--------|---------------------|
| Wall-clock time | Use logical ticks only |
| Thread scheduling | Single-threaded execution |
| Network timing | Model latency explicitly, don't depend on actual network |
| Memory addresses | Never log pointers |
| Hash table iteration | Use deterministic data structures |
| System calls (time, random) | Seed PRNG deterministically, use logical clock |

## Event Log Analysis

### Post-Run Queries

The event log supports queries like:

- **What was the latency distribution?**
  - Filter `response_received` events → extract `latency_ns` → compute HDR histogram

- **Which requests failed and why?**
  - Filter `error_*` events → group by `error_code` → analyze context

- **What was the throughput over time?**
  - Group `response_received` by `tick` → count per interval

- **Did any VUs stall?**
  - Find VUs with long gaps between `request_issued` and `response_received`

### Diff Analysis

Compare two event logs to find behavioral differences:

```bash
z6 diff run1.log run2.log
```

Output:
- Events present in one but not the other
- Events with different payloads (e.g., different latencies)
- Causality violations

## Metrics Derivation

All metrics are **derived from events**:

```
Event Log → Filter → Map → Reduce → Metrics
```

Example: Computing p99 latency

```
1. Filter: event_type == response_received
2. Map: Extract latency_ns field
3. Reduce: Build HDR histogram
4. Query: Get 99th percentile
```

No metrics are computed during the run. All computation happens post-run from the immutable event log.

## Event Integrity

### Checksums

Each event has a CRC64 checksum covering `header + payload`.

### Log Checksum

The entire log has a SHA256 checksum in the footer.

### Verification

```zig
fn verify_event_log(log: []const Event) !void {
    // 1. Verify individual event checksums
    for (log) |event| {
        const computed = crc64(event.header, event.payload);
        if (computed != event.checksum) return error.EventCorrupted;
    }
    
    // 2. Verify event ordering
    for (log[1..]) |event, i| {
        if (!is_before(log[i], event)) return error.OrderingViolation;
    }
    
    // 3. Verify causality
    // (request_issued must precede response_received, etc.)
}
```

## Replay Mechanism

To replay a run:

1. **Load event log**
2. **Extract PRNG seed** from log header
3. **Load scenario** (verify hash matches)
4. **Execute scheduler** with same seed
5. **Compare emitted events** to logged events

If events match **bit-for-bit**, replay is successful.

## Storage Considerations

### Compression

Event logs are **not compressed** during the run. Compression:

- Introduces non-determinism (compressor state)
- Adds latency (CPU overhead)
- Complicates replay

Post-run, logs can be compressed for archival.

### Retention

Event logs should be retained for:

- **Immediate analysis:** Until metrics are computed
- **Debugging:** Until issues are resolved
- **Compliance:** Per organizational requirements

## Example Event Sequence

A simple GET request produces this event sequence:

```
tick=1000, vu=0: vu_spawned
tick=1001, vu=0: conn_established (conn_id=42)
tick=1002, vu=0: request_issued (request_id=1, method="GET")
tick=1050, vu=0: response_received (request_id=1, status=200, latency=48000ns)
tick=1051, vu=0: request_issued (request_id=2, method="GET")
tick=1099, vu=0: response_received (request_id=2, status=200, latency=48000ns)
tick=2000, vu=0: vu_complete
```

From this sequence, we can derive:

- **Requests:** 2
- **Successes:** 2 (100%)
- **Mean latency:** 48μs
- **Throughput:** 2 requests / 1000 ticks

---

## Summary

The event model is Z6's foundation. It provides:

1. **Determinism** — Same input = same events
2. **Auditability** — Every action is recorded
3. **Reproducibility** — Replay from events
4. **Correctness** — Metrics provably derived from truth

Without events, Z6 is just another load tester. With events, Z6 is a **precision instrument**.

---

**Version 1.0 — October 2025**
