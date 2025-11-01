# Z6 Architecture

> "The design is not just what it looks like and feels like. The design is how it works." — Steve Jobs

## System Overview

Z6 is a **single-node, deterministic load testing system** built as a simulation ledger. It does not coordinate across machines. It does not scale horizontally. One machine, one process, maximum clarity.

## Design Principles

1. **Single-threaded by default** — Concurrency through async I/O, not parallelism
2. **Event-driven architecture** — Everything is an event
3. **Deterministic execution** — Same input = same output, always
4. **Explicit state machines** — No implicit state transitions
5. **Zero shared mutable state** — Each component owns its data

## Component Topology

```
┌─────────────────────────────────────────────────────────────┐
│                         Z6 Runtime                          │
│                                                             │
│  ┌──────────────┐      ┌─────────────────┐                │
│  │   CLI        │─────▶│  Scenario       │                │
│  │   Parser     │      │  Loader         │                │
│  └──────────────┘      └────────┬────────┘                │
│                                 │                          │
│                                 ▼                          │
│                        ┌─────────────────┐                │
│                        │   Scheduler     │                │
│                        │  (Microkernel)  │                │
│                        └────────┬────────┘                │
│                                 │                          │
│                    ┌────────────┼────────────┐            │
│                    │            │            │            │
│                    ▼            ▼            ▼            │
│            ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│            │  VU #1   │  │  VU #2   │  │  VU #N   │      │
│            │  Pool    │  │  Pool    │  │  Pool    │      │
│            └────┬─────┘  └────┬─────┘  └────┬─────┘      │
│                 │             │             │            │
│                 └─────────────┼─────────────┘            │
│                               │                          │
│                               ▼                          │
│                      ┌─────────────────┐                │
│                      │  Protocol       │                │
│                      │  Engine Layer   │                │
│                      └────────┬────────┘                │
│                               │                          │
│                   ┌───────────┼───────────┐             │
│                   │           │           │             │
│                   ▼           ▼           ▼             │
│            ┌──────────┐ ┌──────────┐ ┌──────────┐      │
│            │   HTTP   │ │   gRPC   │ │WebSocket │      │
│            │ Handler  │ │ Handler  │ │ Handler  │      │
│            └────┬─────┘ └────┬─────┘ └────┬─────┘      │
│                 │            │            │             │
│                 └────────────┼────────────┘             │
│                              │                          │
│                              ▼                          │
│                     ┌─────────────────┐                │
│                     │  Event Logger   │                │
│                     └────────┬────────┘                │
│                              │                          │
│                              ▼                          │
│                     ┌─────────────────┐                │
│                     │  Event Log      │                │
│                     │  (Immutable)    │                │
│                     └─────────────────┘                │
│                                                         │
└─────────────────────────────────────────────────────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │  Metrics        │
                     │  Reducer        │
                     │  (Post-run)     │
                     └────────┬────────┘
                              │
                              ▼
                     ┌─────────────────┐
                     │  Output         │
                     │  Formatter      │
                     └─────────────────┘
```

## Core Components

### 1. Scheduler (Microkernel)

**Purpose:** Deterministic event dispatch and VU lifecycle management

**Responsibilities:**
- Maintains logical clock (ticks, not wall time)
- Schedules VU activations based on scenario definition
- Dispatches events to appropriate handlers
- Enforces determinism through seeded PRNG
- Implements cohort scheduling for cache efficiency

**Does NOT:**
- Perform I/O directly
- Aggregate metrics
- Parse protocols
- Make non-deterministic decisions

**State:**
- Current logical tick
- VU state table (status per VU)
- Event queue (priority queue by tick)
- PRNG state (seeded, restorable)

### 2. Virtual User (VU) Pool

**Purpose:** Stateful execution context for simulated users

**Responsibilities:**
- Owns VU-specific state (cookies, connection pool, variables)
- Executes scenario steps sequentially
- Emits request events
- Handles response events
- Transitions through lifecycle states

**Lifecycle States:**
```
SPAWNED → READY → EXECUTING → WAITING → READY → ... → COMPLETE
```

**Does NOT:**
- Perform network I/O directly (delegates to protocol handlers)
- Schedule itself (scheduler controls activation)
- Aggregate metrics

### 3. Protocol Engine Layer

**Purpose:** Abstract interface for protocol implementations

**Responsibilities:**
- Defines common protocol operations (connect, send, receive, close)
- Routes requests to appropriate protocol handler
- Ensures all handlers emit events consistently
- Manages connection pooling per protocol

**Handlers:**
- HTTP/1.1 and HTTP/2
- gRPC (future)
- WebSocket (future)

Each handler is **self-contained, minimal, and fuzzed**.

### 4. Event Logger

**Purpose:** Immutable append-only event recording

**Responsibilities:**
- Appends events to binary log
- Guarantees event ordering
- Enforces log size limits (backpressure)
- Provides replay interface
- No parsing, no aggregation

**Event Structure:**
```zig
struct Event {
    tick: u64,           // Logical timestamp
    vu_id: u32,          // Which VU emitted this
    event_type: EventType,
    payload: [256]u8,    // Fixed-size payload
}
```

### 5. Metrics Reducer (Post-run)

**Purpose:** Deterministic metric computation from event log

**Responsibilities:**
- Reads immutable event log
- Computes summary statistics (p50, p99, etc.)
- Produces reproducible output
- Runs **after** the simulation completes

**Does NOT:**
- Operate during the run (no live aggregation)
- Mutate events
- Make estimates (exact computation only)

### 6. Scenario Loader

**Purpose:** Parse and validate scenario files

**Responsibilities:**
- Parse TOML/YAML scenario definitions
- Validate schema
- Convert to internal representation
- Fail fast on invalid scenarios

**Does NOT:**
- Execute scenarios (scheduler does this)
- Interpret scripts (Z6 has no scripting)

## Data Flow

### Initialization Phase

```
CLI Args → Scenario Loader → Validation → Scheduler Init
                                              ↓
                                    PRNG Seeding (deterministic)
                                              ↓
                                    VU Pool Allocation
                                              ↓
                                    Event Log Creation
```

### Execution Phase

```
Scheduler Tick
     ↓
Check VU Schedule (which VUs activate this tick?)
     ↓
Activate VUs → Execute Scenario Step → Issue Request Event
     ↓
Protocol Handler → Network I/O (async)
     ↓
Response Received → Response Event → Emit to Event Log
     ↓
VU State Update (EXECUTING → WAITING → READY)
     ↓
Next Scheduler Tick
```

### Teardown Phase

```
All VUs Complete
     ↓
Flush Event Log
     ↓
Metrics Reducer Reads Log
     ↓
Compute Statistics
     ↓
Format Output (JSON, summary report)
     ↓
Write Results
```

## Threading Model

**Single-threaded event loop** with async I/O:

- Main thread runs the scheduler
- All I/O is non-blocking (epoll/kqueue/IOCP)
- No thread pools, no parallelism
- No locks, no atomics, no synchronization primitives

**Why?** Determinism requires single-threaded execution. Multi-threading introduces non-deterministic scheduling. Async I/O provides concurrency without parallelism.

**Trade-off:** Cannot utilize multiple cores. **Acceptable** because:
1. Network I/O is the bottleneck, not CPU
2. One core can saturate a network link
3. Determinism > throughput
4. If one machine isn't enough, you need a bigger machine

## Memory Layout

```
┌─────────────────────────────────────────────┐
│  Stack (scenario, config)                   │  ~1MB
├─────────────────────────────────────────────┤
│  VU Pool (fixed allocation)                 │  VUs × 64KB
├─────────────────────────────────────────────┤
│  Protocol Handlers (connection pools)       │  ~16MB
├─────────────────────────────────────────────┤
│  Event Log Buffer (ring buffer)             │  Configurable (default 1GB)
├─────────────────────────────────────────────┤
│  Temporary I/O Buffers (fixed pool)         │  ~64MB
└─────────────────────────────────────────────┘
```

All allocations happen at initialization. No allocations during the hot path.

## Error Handling

- Every component returns `Result(T, Error)`
- Errors propagate up to the scheduler
- Scheduler logs error events
- Test continues (fail-open) or aborts (fail-closed) based on scenario config
- Assertions crash immediately (programmer errors)

## Component Boundaries

### What the Scheduler CAN'T See

- Network details (TCP sockets, TLS handshakes)
- Protocol parsing (HTTP headers, gRPC frames)
- Metric computations (latency percentiles)

### What Protocol Handlers CAN'T See

- Other VUs
- The scheduler's internal state
- The event log structure

### What the Event Logger CAN'T Do

- Parse events
- Aggregate metrics
- Replay events (separate component)

## Determinism Guarantees

1. **Seeded PRNG** — All randomness is reproducible
2. **Logical clock** — No system time dependencies
3. **Fixed event ordering** — Events ordered by (tick, vu_id)
4. **No external inputs during run** — No signals, no user input, no network variability affecting control flow
5. **Bounded loops** — All iteration counts deterministic

## Replay Mechanism

To replay a run:

1. Load original scenario
2. Load original event log
3. Seed PRNG with original seed
4. Execute scheduler with same logical ticks
5. Verify events match original log bit-for-bit

**Replay success = perfect determinism proof**

## Performance Characteristics

| Metric | Target | Rationale |
|--------|--------|-----------|
| VU spawn overhead | <10μs | Minimal abstraction |
| Event log latency | <1μs | Lock-free append |
| Scheduler tick overhead | <100ns | Tight loop, no syscalls |
| Memory overhead per VU | <64KB | Fixed state size |
| Max VUs per core | 100,000+ | Lightweight state machines |

## Extension Points

Z6 is **not** designed for plugins. Extensions require:

1. **New Protocol Handler** — Implement protocol interface, fuzz exhaustively
2. **Custom Metrics** — Extend event payload types (requires schema update)
3. **Output Formats** — Add new formatter to metrics reducer

No runtime plugin system. Extensions are compiled in.

## Non-Goals (Architecture Won't Support)

- Distributed testing (multiple machines)
- Dynamic scenario generation (scripting)
- Real-time metric streaming (post-run only)
- Mocking/stubbing backends (integration testing tool, not a mock server)
- Browser automation (not a browser)

## Comparison to Other Architectures

| System | Architecture | Z6 Difference |
|--------|--------------|---------------|
| K6 | Multi-threaded JS runtime | Single-threaded, no scripting |
| Locust | Python event loop + workers | No Python, no distribution |
| Gatling | Akka actors (JVM) | No actors, no GC pauses |
| wrk2 | Multi-threaded C | Single-threaded, deterministic |

---

## Implementation Phases

### Phase 1: Skeleton (HTTP only)
- Scheduler + VU pool
- Basic HTTP handler
- Event logger
- Minimal metrics reducer

### Phase 2: Determinism Proof
- Replay mechanism
- Seed management
- Bit-for-bit verification tests

### Phase 3: Production Readiness
- Fuzzing all components
- Complete error taxonomy
- Full HTTP/1.1 and HTTP/2 support

### Phase 4: Additional Protocols
- gRPC handler
- WebSocket handler

---

**Version 1.0 — October 2025**
