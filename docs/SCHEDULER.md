# Z6 Scheduler

> "We don't schedule actors, we schedule events with proofs."

## Overview

The scheduler is Z6's **deterministic microkernel**. It is the beating heart that coordinates all activity while maintaining perfect reproducibility.

## Design Principles

1. **Determinism über alles** — Same input = same output, always
2. **Logical time, not wall time** — System clock is never consulted during execution
3. **Event-driven dispatch** — No polling, no busy-waiting
4. **Single-threaded execution** — No races, no locks, no atomic operations
5. **Bounded complexity** — All operations have provable upper bounds

## Logical Time Model

### The Tick

A **tick** is the fundamental unit of logical time:

```zig
const Tick = u64;
```

Properties:

- **Monotonic** — Ticks always increase
- **Deterministic** — Same scenario → same ticks
- **No relation to wall time** — 1 tick ≠ 1 millisecond

The tick granularity is **implementation-defined** but must be consistent across runs.

### Tick Advancement

Ticks advance when:

1. All VUs for the current tick have been processed
2. All events for the current tick have been logged
3. The scheduler is ready for the next tick

The scheduler **never** advances ticks based on wall-clock time.

## Scheduler State

```zig
const Scheduler = struct {
    /// Current logical time
    current_tick: Tick,
    
    /// Virtual user state table
    vus: []VU,
    
    /// Event queue (priority queue, sorted by tick)
    events: PriorityQueue(ScheduledEvent),
    
    /// Deterministic PRNG
    prng: PRNG,
    
    /// Event logger
    logger: *EventLogger,
    
    /// Protocol engine
    protocol_engine: *ProtocolEngine,
    
    /// Scenario definition
    scenario: *Scenario,
    
    /// Statistics (non-critical, not logged)
    stats: SchedulerStats,
};
```

## VU State Machine

Each Virtual User progresses through well-defined states:

```
   SPAWNED
      │
      ▼
    READY ◄──────┐
      │          │
      ▼          │
  EXECUTING      │
      │          │
      ▼          │
   WAITING ──────┘
      │
      ▼
  COMPLETE
```

### State Definitions

- **SPAWNED** — VU allocated, not yet ready to execute
- **READY** — VU ready to execute next scenario step
- **EXECUTING** — VU actively performing an action (usually issuing a request)
- **WAITING** — VU blocked on I/O (waiting for response)
- **COMPLETE** — VU has finished all scenario steps

### State Transitions

| From | To | Trigger |
|------|-----|---------|
| SPAWNED | READY | VU initialization complete |
| READY | EXECUTING | Scheduler activates VU |
| EXECUTING | WAITING | Request issued, awaiting response |
| WAITING | READY | Response received (or timeout) |
| READY | COMPLETE | All scenario steps done |
| WAITING | COMPLETE | Fatal error (connection lost, etc.) |

Transitions are **deterministic** — same event sequence → same state sequence.

## Event Queue

The scheduler maintains a priority queue of events sorted by tick:

```zig
const ScheduledEvent = struct {
    tick: Tick,          // When this event fires
    vu_id: u32,          // Which VU owns this event
    event_type: EventType,
    payload: EventPayload,
};
```

Operations:

- **Enqueue:** `O(log N)` insertion
- **Dequeue:** `O(log N)` removal of minimum tick event
- **Peek:** `O(1)` view of next event

The queue is **bounded** — maximum queue size is configured at startup. If the queue fills, backpressure is applied.

## Cohort Scheduling

To maximize cache efficiency, Z6 uses **cohort scheduling**:

### What is a Cohort?

A cohort is a group of VUs that:

- Execute the same scenario step
- Are scheduled at the same tick
- Share instruction cache and data access patterns

### Cohort Execution

```
For each tick:
  1. Group all READY VUs by scenario step
  2. Execute cohorts sequentially
  3. All VUs in a cohort execute the same step back-to-back
```

Benefits:

- **Instruction cache reuse** — Same code path for all VUs in cohort
- **Data cache reuse** — Similar memory access patterns
- **Branch prediction** — Predictor learns pattern once, applies to all VUs

This is inspired by TigerBeetle's batch processing model.

## Scheduler Loop

The main scheduler loop:

```zig
fn run(scheduler: *Scheduler) !void {
    while (!scheduler.is_complete()) {
        // 1. Process all events for current tick
        while (scheduler.events.peek()) |event| {
            if (event.tick > scheduler.current_tick) break;
            
            const scheduled_event = scheduler.events.dequeue();
            try scheduler.handle_event(scheduled_event);
        }
        
        // 2. Activate all READY VUs (cohort scheduling)
        try scheduler.activate_ready_vus();
        
        // 3. Poll for I/O completions (non-blocking)
        try scheduler.protocol_engine.poll();
        
        // 4. Advance logical time
        scheduler.current_tick += 1;
        
        // 5. Periodic event log flush
        if (scheduler.current_tick % 10000 == 0) {
            try scheduler.logger.flush();
        }
    }
    
    // Final flush
    try scheduler.logger.flush();
}
```

### Step-by-Step

#### 1. Process Events

Dequeue and handle all events scheduled for `current_tick`:

- VU spawn events
- Timeout events
- Scheduled retries
- Assertion checks

#### 2. Activate VUs

Group all READY VUs by scenario step, then execute cohorts:

```zig
fn activate_ready_vus(scheduler: *Scheduler) !void {
    // Group by scenario step
    var cohorts = CohortMap.init();
    for (scheduler.vus) |*vu| {
        if (vu.state == .READY) {
            cohorts.add(vu.scenario_step, vu);
        }
    }
    
    // Execute cohorts
    var it = cohorts.iterator();
    while (it.next()) |cohort| {
        for (cohort.vus) |vu| {
            try scheduler.execute_vu_step(vu);
        }
    }
}
```

#### 3. Poll I/O

Non-blocking check for completed I/O operations:

```zig
fn poll(engine: *ProtocolEngine) !void {
    const completions = try engine.io_uring.poll(); // or epoll/kqueue
    
    for (completions) |completion| {
        const vu = engine.find_vu_by_request_id(completion.request_id);
        
        // Emit response event
        try engine.logger.log_response(vu.id, completion);
        
        // Transition VU state: WAITING → READY
        vu.state = .READY;
    }
}
```

#### 4. Advance Time

Increment `current_tick`. This is the **only** place ticks advance.

#### 5. Flush Events

Periodically flush the event log to disk for crash safety.

## Deterministic Randomness

All randomness is **seeded and reproducible**:

```zig
const PRNG = struct {
    state: u64,
    
    fn init(seed: u64) PRNG {
        return .{ .state = seed };
    }
    
    fn next(prng: *PRNG) u64 {
        // xorshift64* algorithm (deterministic)
        prng.state ^= prng.state >> 12;
        prng.state ^= prng.state << 25;
        prng.state ^= prng.state >> 27;
        return prng.state *% 0x2545F4914F6CDD1D;
    }
};
```

Usage:

- **VU jitter** — Random delay before VU spawn
- **Request delays** — Think time between requests
- **Connection selection** — Which connection from pool to use

The seed is stored in the event log header for replay.

## Backpressure Mechanisms

When resources are constrained, the scheduler applies backpressure:

### Event Queue Full

If the event queue reaches capacity:

1. **Log warning event**
2. **Pause VU activations**
3. **Wait for events to drain**
4. **Resume when space available**

This prevents unbounded memory growth.

### Event Log Full

If the event log ring buffer fills:

1. **Flush to disk immediately**
2. **Pause all activity**
3. **Wait for flush completion**
4. **Resume when space available**

If disk writes are too slow, the test **aborts** with `ResourceExhausted`.

### Connection Pool Exhausted

If all connections are in use:

1. **VU transitions to WAITING**
2. **Schedule retry event** (deterministic delay)
3. **VU retries when connection available**

## Timeout Handling

Timeouts are **explicitly scheduled events**:

```zig
fn issue_request(scheduler: *Scheduler, vu: *VU, request: Request) !void {
    // Issue the request
    try scheduler.protocol_engine.send(request);
    
    // Schedule timeout event
    const timeout_tick = scheduler.current_tick + request.timeout_ticks;
    try scheduler.events.enqueue(.{
        .tick = timeout_tick,
        .vu_id = vu.id,
        .event_type = .request_timeout,
        .payload = .{ .request_id = request.id },
    });
    
    // Transition VU to WAITING
    vu.state = .WAITING;
}
```

When a timeout fires:

```zig
fn handle_timeout(scheduler: *Scheduler, event: ScheduledEvent) !void {
    const vu = &scheduler.vus[event.vu_id];
    
    // Log timeout event
    try scheduler.logger.log_timeout(event);
    
    // Cancel pending request
    scheduler.protocol_engine.cancel_request(event.payload.request_id);
    
    // Transition VU: WAITING → READY
    vu.state = .READY;
}
```

## Scheduler Guarantees

### Determinism Guarantee

**Given:**

- Same scenario
- Same PRNG seed
- Same initial state

**Then:**

- Same tick sequence
- Same event sequence
- Same VU state transitions
- Bit-for-bit identical event log

### Fairness Guarantee

The scheduler provides **cooperative fairness**:

- All VUs at the same scenario step execute before advancing to the next cohort
- No VU is starved (bounded wait time)
- FIFO ordering within a cohort

**Not guaranteed:**

- Equal execution time per VU (depends on I/O)
- Strict round-robin (cohort scheduling prioritizes cache efficiency)

### Progress Guarantee

The scheduler guarantees **forward progress**:

- If any VU is READY, it will eventually execute
- If all VUs are WAITING, I/O polling will eventually unblock them
- The test will complete in finite time (bounded loops)

## Performance Characteristics

| Operation | Time Complexity | Notes |
|-----------|-----------------|-------|
| Event enqueue | O(log N) | Priority queue insertion |
| Event dequeue | O(log N) | Priority queue removal |
| VU activation | O(V) | Linear in number of VUs |
| Cohort grouping | O(V) | Single pass over VUs |
| I/O poll | O(C) | Linear in completions |
| Tick advance | O(1) | Simple increment |

Where:

- N = events in queue
- V = number of VUs
- C = completed I/O operations

## Scheduler Statistics

The scheduler tracks (but does not log) runtime statistics:

```zig
const SchedulerStats = struct {
    total_ticks: u64,
    events_processed: u64,
    vus_spawned: u32,
    vus_completed: u32,
    cohorts_executed: u64,
    avg_cohort_size: f32,
    max_queue_depth: u32,
};
```

These are reported in the final summary but are **not** part of the event log (to avoid measurement perturbation).

## Edge Cases

### Empty Event Queue

If no events are scheduled and no VUs are READY:

- **All VUs WAITING:** Continue polling I/O
- **All VUs COMPLETE:** Test finishes
- **Invalid state:** Assertion failure (scheduler bug)

### Very Long Waits

If a VU waits >1 million ticks:

- **Log warning event**
- **Continue waiting** (may indicate backend slowness)
- **Timeout event will eventually fire**

### Assertion Failures

If an assertion fails **during** the run:

- **Log assertion failure event**
- **Complete current tick**
- **Abort scheduler gracefully**
- **Flush event log**
- **Exit with error code**

## Scheduler Configuration

Configurable parameters:

```zig
const SchedulerConfig = struct {
    max_vus: u32 = 100_000,
    max_events: u32 = 1_000_000,
    event_flush_interval: u32 = 10_000,  // ticks
    timeout_default_ticks: u32 = 30_000, // ~30 seconds at 1ms/tick
    prng_seed: u64 = 0,                  // 0 = random seed
};
```

All parameters have sensible defaults but can be overridden per scenario.

## Comparison to Other Schedulers

| System | Scheduler Type | Z6 Difference |
|--------|----------------|---------------|
| K6 | Go goroutines | Logical ticks, deterministic |
| Locust | Python asyncio | Zig async, cohort scheduling |
| Gatling | Akka actors | No actors, explicit state machines |
| wrk2 | Multi-threaded | Single-threaded, event-driven |

## Replay Verification

To verify determinism:

```bash
# Run 1
z6 run scenario.toml --seed 42 --output run1.log

# Run 2 (same seed)
z6 run scenario.toml --seed 42 --output run2.log

# Compare
diff run1.log run2.log
# Expected: no differences
```

If logs differ, determinism is broken (scheduler bug).

## Future Extensions

Possible scheduler enhancements (post-v1):

- **Distributed replay** — Replay across multiple machines (read-only)
- **Time travel debugging** — Step backward through ticks
- **Snapshot/restore** — Checkpoint scheduler state for partial replay

All extensions must preserve determinism.

---

## Summary

The scheduler is simple:

- Logical ticks, not wall time
- Event-driven dispatch
- Cohort scheduling for cache efficiency
- Deterministic PRNG
- Bounded complexity

This simplicity enables **perfect reproducibility**, which is Z6's superpower.

---

**Version 1.0 — October 2025**
