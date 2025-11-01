# Z6 Tiger Style Manifesto

> "In programming, style is not something to pursue directly. Style is necessary only where understanding is missing."  
> — Let Over Lambda

## What Z6 Is

**Z6 is a deterministic, high-performance, auditable simulation ledger for distributed system behavior.**

Z6 is not "a faster K6." It is a precision instrument built under martial discipline. Every design decision serves three goals, in order:

1. **Safety** — Correctness over convenience
2. **Performance** — Predictability over throughput
3. **Developer Experience** — Clarity over flexibility

## Design Goals

### 1. Deterministic Reproducibility

Every load test must be **exactly reproducible**, bit-for-bit.

- All randomness is seeded
- Scheduling uses logical ticks, not wall-clock time
- Event logs can replay any run identically
- Network timing variations are modeled, not emergent

**Why:** Non-deterministic tests hide bugs. If you can't reproduce a failure, you can't prove you fixed it.

### 2. Auditability as a First-Class Citizen

Every request, response, metric, and scheduling decision must be traceable.

- No hidden state
- No aggregated metrics without raw event logs
- Every error has a deterministic cause
- Post-run analysis can reconstruct the complete execution graph

**Why:** Load testing is forensic work. Without audit trails, you're guessing.

### 3. Memory Safety and Explicit Resource Management

Z6 is written in Zig. Every allocation is explicit. Every bound is checked.

- No garbage collection pauses
- No hidden allocations
- Fixed memory budgets for all subsystems
- Allocations are pooled and reused

**Why:** Unpredictable memory behavior makes latency measurements meaningless.

### 4. Bounded Complexity

Every subsystem must have provably bounded behavior.

- All loops have fixed upper bounds
- No unbounded queues
- No recursion
- Event logs have size limits with backpressure

**Why:** Unbounded systems cannot be reasoned about. They fail in production, not in testing.

### 5. Correctness Before Performance

Performance optimizations must not compromise correctness guarantees.

- Fuzz every protocol handler
- Property-based tests for all invariants
- Assertions have minimum density of 2 per function
- No "it's fast enough" without "it's correct"

**Why:** A fast but wrong load tester produces fast but wrong conclusions.

## What Z6 Is Not

Understanding constraints is as important as understanding capabilities.

### Z6 is NOT a scripting playground

- No dynamic JavaScript/Lua/Python execution
- No arbitrary control flow in scenarios
- Scenarios are **declared**, not **scripted**

**Rationale:** Dynamic scripting introduces non-determinism, hidden allocations, and unbounded complexity. Flexibility is the enemy of reproducibility.

### Z6 is NOT optimized for convenience

- No "just works" magic
- No auto-tuning that hides system behavior
- No implicit timeouts or retries
- Errors fail fast with explicit causes

**Rationale:** Convenience features paper over complexity. Z6 makes complexity explicit so you can reason about it.

### Z6 is NOT a general-purpose HTTP client

- Supports only load testing use cases
- No web scraping, no API consumption, no browser automation
- Protocol implementations are minimal and verified

**Rationale:** General-purpose tools have general-purpose bugs. Specialized tools have specialized correctness.

### Z6 is NOT a distributed system

- Single-node architecture
- No coordination protocols
- No consensus mechanisms
- Horizontal scaling is not a goal

**Rationale:** If one machine can't generate your target load, you need bigger machines, not more complexity. Distributed load testing introduces distributed bugs.

## Core Principles

### The Ledger Model

Z6 treats load testing as **accounting for events**.

- Each virtual user (VU) is an account
- Each request is a transaction
- Each metric is a balance update
- Runs produce deterministic ledgers

Just as TigerBeetle guarantees financial correctness, Z6 guarantees measurement correctness.

### The Scheduler as Microkernel

The scheduler is the beating heart of Z6. It must be **deterministic and minimal**.

- Uses logical ticks, not wall-clock time
- Schedules events, not threads
- Cohort scheduling for cache efficiency
- No preemption, no time-slicing, no context switches

### Metrics as Immutable Events

Metrics are never aggregated on-the-fly. They are:

1. Appended as immutable events during the run
2. Reduced deterministically after the run
3. Verifiable through replay

This enables:

- Bit-exact metric reproduction
- Alternative analysis methods without re-running tests
- Cryptographic proofs of test integrity

### Failure as First-Class Result

TigerBeetle treats failures with dignity. So does Z6.

- Every component returns `Result(T, Error)`
- Error types are semantic: `Timeout`, `ConnReset`, `ProtocolViolation`
- No panics except for programmer errors (assertions)
- Every failure is traceable to a deterministic cause

### Protocols as Verified Modules

Each protocol (HTTP, gRPC, WebSocket) is:

- A small, self-contained module
- Fuzzed for correctness
- Minimal in scope
- Composable with others

We support fewer protocols than K6, but every protocol we support is **correct**.

## Technical Constraints

### Language: Zig

- Explicit memory management
- No hidden control flow
- Compile-time guarantees
- C interop for existing protocol implementations when needed

### No Dependencies for Core

- Zero external dependencies for the core runtime
- Protocol implementations may use minimal, audited libraries
- Build system is simple and reproducible

**Why:** Dependencies are liabilities. Every dependency is a potential source of non-determinism, bugs, and supply chain risk.

### Explicit Sizing

- Use `u32`, `u64`, never `usize`
- All buffers have fixed sizes
- All timeouts are explicit
- All limits are documented

### Assertions Everywhere

- Minimum 2 assertions per function
- Assert all preconditions, postconditions, invariants
- Assertions pair: if you check on input, check on output
- Assertion failures crash immediately

**Why:** Assertions downgrade correctness bugs into liveness bugs. Better to crash than to corrupt.

## Development Discipline

### Zero Technical Debt

When we find showstoppers, we fix them. No "TODO" comments without issue tickets. No "we'll optimize later" without proof it's correct now.

**Why:** The second time may never come. Do it right the first time.

### Simplicity Through Revision

First attempts are sketches. Real simplicity requires:

- Multiple design passes
- Willingness to throw away code
- Identifying the "super idea" that solves multiple constraints simultaneously

### Test Before Implement

- Write property-based tests for invariants first
- Fuzz protocol handlers before declaring them complete
- Integration tests must be deterministic and fast

### Documentation is Design

- Write the manifesto before the code
- Document constraints, not just capabilities
- Every design decision has a "why"

## The Z6 Way

Z6 is not for everyone. It's for teams who:

- Need reproducible load tests for mission-critical systems
- Value correctness over convenience
- Want to treat load testing as a science, not an art
- Understand that the cost of doing it right is less than the cost of doing it wrong

Z6 is for engineers who know that:

> "Simplicity and elegance are unpopular because they require hard work and discipline to achieve."  
> — Edsger Dijkstra

---

## Implementation Tenets

When making technical decisions, ask:

1. **Does this preserve determinism?**
2. **Can this be audited and replayed?**
3. **Is the memory behavior explicit and bounded?**
4. **Does this make the system simpler or more complex?**
5. **Can we prove this is correct?**

If the answer to any is "no" or "I don't know," the feature is not ready.

---

## Success Criteria

Z6 succeeds when:

- A load test can be replayed bit-for-bit months later
- Every metric can be traced to its source events
- Memory and CPU behavior are predictable within 5%
- Protocol implementations have zero known correctness bugs
- Engineers trust the results enough to make production decisions

Z6 fails when:

- Tests produce different results on replay
- Metrics cannot be explained
- Performance is unpredictable
- Bugs are found in core protocol handlers
- Teams choose other tools because "it's easier"

We accept the last failure. Correctness is not easy.

---

## The Path Forward

1. **Build the skeleton** — Simplest deterministic HTTP load generator
2. **Prove the model** — Demonstrate replay determinism
3. **Fuzz relentlessly** — Find bugs before users do
4. **Document everything** — Make the invisible visible
5. **Ship when ready** — Not before

---

*This manifesto is a living document. As we learn, it evolves. But the principles do not change: safety, performance, developer experience. In that order.*

---

**Version 1.0 — October 2025**
