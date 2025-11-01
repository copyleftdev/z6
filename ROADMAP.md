# Z6 Development Roadmap

> "Test before implement. Do it right the first time. Zero technical debt."

## Roadmap Structure

This roadmap is designed for programmatic GitHub issue creation. Each task includes:
- **Phase** — Development milestone
- **Dependencies** — Prerequisites
- **Acceptance Criteria** — Definition of done
- **Labels** — For GitHub automation

## Metadata

```yaml
version: "1.0"
philosophy: "Tiger Style"
principles:
  - "Test before implement"
  - "Zero technical debt"
  - "Assertions > 2 per function"
  - "Fuzz everything that parses"
  - "Bounded complexity"
```

---

## Phase 0: Foundation & Tooling

**Goal:** Set up development infrastructure with Tiger Style discipline

### TASK-000: Repository Structure

**Description:** Initialize repository with proper structure

**Acceptance Criteria:**
- [ ] Directory structure matches documentation
- [ ] All 20 documentation files in `/docs`
- [ ] `.gitignore` configured for Zig
- [ ] `LICENSE` file added (MIT or Apache 2.0)
- [ ] `README.md` with quick start
- [ ] `CONTRIBUTORS.md` initialized

**Dependencies:** None

**Labels:** `foundation`, `setup`

**Estimated Effort:** 2 hours

---

### TASK-001: Pre-Commit Hook System

**Description:** Implement comprehensive pre-commit validation enforcing Tiger Style

**Acceptance Criteria:**
- [ ] Pre-commit hook installed via `.git/hooks/pre-commit`
- [ ] Hook runs `zig fmt --check src/` (fails if unformatted)
- [ ] Hook runs all unit tests (`zig build test`)
- [ ] Hook validates assertion density (min 2 per function)
- [ ] Hook checks for unbounded loops
- [ ] Hook verifies all errors are explicit (no silent failures)
- [ ] Hook execution time < 30 seconds
- [ ] Installation script: `./scripts/install-hooks.sh`
- [ ] Documentation in `docs/CONTRIBUTING.md` updated

**Dependencies:** TASK-000

**Labels:** `foundation`, `tooling`, `tiger-style`

**Estimated Effort:** 8 hours

**Files:**
```
.git/hooks/pre-commit
scripts/install-hooks.sh
scripts/check-assertions.zig
scripts/check-bounded-loops.zig
```

---

### TASK-002: Build System

**Description:** Implement Zig build system per `BUILD.md`

**Acceptance Criteria:**
- [ ] `build.zig` with all targets defined
- [ ] Build modes: Debug, ReleaseSafe, ReleaseFast, ReleaseSmall
- [ ] Targets: `z6` (main), `test`, `test-integration`, `fuzz-targets`, `docs`
- [ ] Vendored dependencies in `vendor/` (BoringSSL, zlib, HDR histogram)
- [ ] Cross-compilation support verified (Linux, macOS)
- [ ] Static linking option (`-Dstatic=true`)
- [ ] Build completes in < 60s (ReleaseFast)
- [ ] Reproducible builds verified (two builds produce identical binaries)

**Dependencies:** TASK-000

**Labels:** `foundation`, `build`

**Estimated Effort:** 16 hours

---

## Phase 1: Core Architecture

**Goal:** Implement deterministic foundation (Event Model, Scheduler, Memory)

### TASK-100: Event Model Implementation

**Description:** Implement immutable event log per `EVENT_MODEL.md`

**Test-First Requirements:**
- [ ] Write tests BEFORE implementation
- [ ] Test event serialization (round-trip)
- [ ] Test event ordering invariants
- [ ] Test checksum validation
- [ ] Fuzz event deserialization (1M inputs minimum)

**Acceptance Criteria:**
- [ ] `EventHeader` struct (24 bytes: tick, vu_id, event_type)
- [ ] `Event` struct (272 bytes total, fixed size)
- [ ] Event types: `request_issued`, `response_received`, `error_*`
- [ ] Serialization functions: `serialize_event()`, `deserialize_event()`
- [ ] CRC64 checksum per event
- [ ] Event log file format with header/footer per `OUTPUT_FORMAT.md`
- [ ] Append-only writes (no in-place modification)
- [ ] Minimum 2 assertions per function
- [ ] >95% test coverage
- [ ] All tests pass
- [ ] Fuzz test runs 1M inputs without crash

**Dependencies:** TASK-002

**Labels:** `phase-1`, `core`, `event-model`

**Estimated Effort:** 24 hours

**Files:**
```
src/event.zig
src/event_log.zig
tests/unit/event_test.zig
tests/fuzz/event_serialization_fuzz.zig
```

---

### TASK-101: Memory Model Implementation

**Description:** Implement bounded memory allocation per `MEMORY_MODEL.md`

**Test-First Requirements:**
- [ ] Test arena allocation/reset
- [ ] Test pool allocation/deallocation
- [ ] Test memory budget enforcement
- [ ] Test OOM handling
- [ ] Property test: no memory leaks

**Acceptance Criteria:**
- [ ] Arena allocator with fixed buffer
- [ ] Pool allocator for fixed-size objects
- [ ] Memory budget configuration (default 16 GB)
- [ ] Per-VU memory: 64 KB
- [ ] Event log memory: 2.7 GB
- [ ] `OutOfMemory` error when budget exceeded
- [ ] Memory measurement functions
- [ ] Zero heap allocations in hot path
- [ ] Alignment guarantees (8-byte minimum)
- [ ] Minimum 2 assertions per function
- [ ] >98% test coverage (critical subsystem)
- [ ] All tests pass
- [ ] Valgrind reports zero leaks

**Dependencies:** TASK-002

**Labels:** `phase-1`, `core`, `memory`

**Estimated Effort:** 20 hours

**Files:**
```
src/memory.zig
src/arena.zig
src/pool.zig
tests/unit/memory_test.zig
tests/integration/memory_budget_test.zig
```

---

### TASK-102: Scheduler Implementation

**Description:** Implement deterministic scheduler per `SCHEDULER.md`

**Test-First Requirements:**
- [ ] Test logical tick advancement
- [ ] Test VU state transitions
- [ ] Test event queue ordering
- [ ] Test deterministic PRNG (same seed = same output)
- [ ] Test cohort scheduling
- [ ] Property test: tick monotonicity

**Acceptance Criteria:**
- [ ] `Scheduler` struct with logical tick counter
- [ ] VU state machine: `idle`, `waiting`, `active`, `completed`
- [ ] Priority queue for scheduled events (sorted by tick)
- [ ] Deterministic PRNG (PCG algorithm, configurable seed)
- [ ] Cohort scheduling (max 10K VUs per cohort)
- [ ] Event emission to event log
- [ ] Tick advancement: `advance_tick()`
- [ ] Main loop: `run_until(duration_ticks)`
- [ ] Bounded event queue (max 1M events)
- [ ] Minimum 2 assertions per function
- [ ] >95% test coverage
- [ ] Determinism test: same seed produces identical event log (bit-for-bit)
- [ ] All tests pass

**Dependencies:** TASK-100, TASK-101

**Labels:** `phase-1`, `core`, `scheduler`

**Estimated Effort:** 32 hours

**Files:**
```
src/scheduler.zig
src/prng.zig
src/vu.zig
tests/unit/scheduler_test.zig
tests/integration/determinism_test.zig
```

---

## Phase 2: HTTP Protocol (First Implementation)

**Goal:** Prove the model with HTTP/1.1 and HTTP/2

### TASK-200: Protocol Interface Definition

**Description:** Define generic protocol handler interface per `PROTOCOL_INTERFACE.md`

**Acceptance Criteria:**
- [ ] `ProtocolHandler` trait/interface defined
- [ ] Core types: `Request`, `Response`, `ConnectionId`, `Target`
- [ ] Lifecycle methods: `init()`, `deinit()`, `connect()`, `send()`, `receive()`
- [ ] Error taxonomy: `ProtocolError` enum
- [ ] Connection pooling interface
- [ ] Timeout handling specification
- [ ] Event emission hooks
- [ ] Documentation complete with examples
- [ ] Minimum 2 assertions per function
- [ ] Interface verified with mock implementation
- [ ] All tests pass

**Dependencies:** TASK-102

**Labels:** `phase-2`, `protocol`, `interface`

**Estimated Effort:** 12 hours

**Files:**
```
src/protocol.zig
tests/unit/protocol_test.zig
tests/unit/mock_protocol.zig
```

---

### TASK-201: HTTP/1.1 Parser Implementation

**Description:** Implement HTTP/1.1 response parser per `HTTP_PROTOCOL.md`

**Test-First Requirements:**
- [ ] Test status line parsing (valid/invalid)
- [ ] Test header parsing (100+ test cases)
- [ ] Test chunked encoding (fragmented, complete, invalid)
- [ ] Test content-length handling
- [ ] Fuzz parser with 10M inputs minimum

**Acceptance Criteria:**
- [ ] Parse HTTP/1.1 status line
- [ ] Parse headers (max 100, max 8 KB per header)
- [ ] Parse chunked transfer encoding
- [ ] Parse content-length bodies
- [ ] Handle keep-alive connections
- [ ] Error handling: `InvalidStatusLine`, `InvalidHeader`, etc.
- [ ] Bounds checking: max response size 10 MB
- [ ] Zero-copy parsing (reference original buffer)
- [ ] Minimum 2 assertions per function
- [ ] >98% test coverage
- [ ] Fuzz test: 10M inputs, zero crashes
- [ ] All tests pass

**Dependencies:** TASK-200

**Labels:** `phase-2`, `http`, `parser`, `fuzz-required`

**Estimated Effort:** 40 hours

**Files:**
```
src/http/parser.zig
src/http/http1.zig
tests/unit/http1_parser_test.zig
tests/fuzz/http1_response_fuzz.zig
corpus/http1_response/...
```

---

### TASK-202: HTTP/1.1 Handler Implementation

**Description:** Implement HTTP/1.1 protocol handler

**Test-First Requirements:**
- [ ] Test request serialization
- [ ] Test connection establishment
- [ ] Test connection reuse (keep-alive)
- [ ] Test timeout handling
- [ ] Integration test with mock HTTP server

**Acceptance Criteria:**
- [ ] Implement `ProtocolHandler` interface for HTTP/1.1
- [ ] Request serialization (method, path, headers, body)
- [ ] Connection pooling (max 10K connections)
- [ ] Keep-alive support (max 100 requests per connection)
- [ ] Timeout enforcement (connection, request, read, write)
- [ ] TLS support via BoringSSL
- [ ] Event logging: `request_issued`, `response_received`, `error_*`
- [ ] Error handling: all network/protocol errors logged
- [ ] Minimum 2 assertions per function
- [ ] >90% test coverage
- [ ] Integration test: end-to-end request/response with mock server
- [ ] All tests pass

**Dependencies:** TASK-201

**Labels:** `phase-2`, `http`, `handler`

**Estimated Effort:** 36 hours

---

### TASK-203: HTTP/2 Frame Parser Implementation

**Description:** Implement HTTP/2 frame parsing per `HTTP_PROTOCOL.md`

**Test-First Requirements:**
- [ ] Test all frame types (DATA, HEADERS, SETTINGS, etc.)
- [ ] Test HPACK header compression
- [ ] Test flow control
- [ ] Fuzz all frame types (1M inputs per type)

**Acceptance Criteria:**
- [ ] Parse HTTP/2 frame header (9 bytes)
- [ ] Parse frame types: DATA, HEADERS, PRIORITY, RST_STREAM, SETTINGS, PING, GOAWAY, WINDOW_UPDATE
- [ ] HPACK decoder (static + dynamic table)
- [ ] Flow control tracking (stream + connection level)
- [ ] Error detection: `ProtocolError`, `FlowControlError`, etc.
- [ ] Frame size limits (16 MB max per spec)
- [ ] Minimum 2 assertions per function
- [ ] >98% test coverage
- [ ] Fuzz test: 1M inputs per frame type, zero crashes
- [ ] All tests pass

**Dependencies:** TASK-200

**Labels:** `phase-2`, `http`, `http2`, `parser`, `fuzz-required`

**Estimated Effort:** 48 hours

**Files:**
```
src/http/http2.zig
src/http/hpack.zig
tests/unit/http2_test.zig
tests/fuzz/http2_frame_fuzz.zig
tests/fuzz/hpack_fuzz.zig
corpus/http2_frame/...
```

---

### TASK-204: HTTP/2 Handler Implementation

**Description:** Implement HTTP/2 protocol handler

**Test-First Requirements:**
- [ ] Test connection preface
- [ ] Test stream multiplexing
- [ ] Test ALPN negotiation
- [ ] Integration test with HTTP/2 server

**Acceptance Criteria:**
- [ ] Implement `ProtocolHandler` interface for HTTP/2
- [ ] Connection preface handling
- [ ] ALPN negotiation ("h2")
- [ ] Stream management (max 100 concurrent)
- [ ] Flow control enforcement
- [ ] SETTINGS frame exchange
- [ ] Stream prioritization (basic)
- [ ] Server push handling (receive and ignore)
- [ ] Event logging for all HTTP/2 operations
- [ ] Minimum 2 assertions per function
- [ ] >90% test coverage
- [ ] Integration test with real HTTP/2 server
- [ ] All tests pass

**Dependencies:** TASK-203

**Labels:** `phase-2`, `http`, `http2`, `handler`

**Estimated Effort:** 40 hours

---

## Phase 3: Scenario Execution

**Goal:** End-to-end scenario execution with CLI

### TASK-300: TOML Scenario Parser

**Description:** Implement scenario file parser per `SCENARIO_FORMAT.md`

**Test-First Requirements:**
- [ ] Test valid scenarios (10+ examples)
- [ ] Test invalid scenarios (missing fields, wrong types)
- [ ] Test all schedule types
- [ ] Fuzz TOML parser

**Acceptance Criteria:**
- [ ] Parse TOML scenario files
- [ ] Validate required fields: `runtime`, `target`, `requests`
- [ ] Parse request definitions (method, path, headers, body)
- [ ] Parse schedule types: constant, ramp, spike, steps
- [ ] Parse assertions
- [ ] Parse limits configuration
- [ ] Validation: URL format, timeout ranges, VU count
- [ ] Error messages: clear, actionable
- [ ] Scenario size limit: 10 MB
- [ ] Minimum 2 assertions per function
- [ ] >95% test coverage
- [ ] Fuzz test: malformed TOML, 100K inputs
- [ ] All tests pass

**Dependencies:** TASK-102

**Labels:** `phase-3`, `scenario`, `parser`, `fuzz-required`

**Estimated Effort:** 24 hours

**Files:**
```
src/scenario.zig
tests/unit/scenario_test.zig
tests/fuzz/scenario_parser_fuzz.zig
tests/fixtures/scenarios/...
```

---

### TASK-301: VU Execution Engine

**Description:** Implement VU lifecycle and request execution

**Test-First Requirements:**
- [ ] Test VU state transitions
- [ ] Test request selection (weighted)
- [ ] Test think time
- [ ] Property test: request count = responses + errors

**Acceptance Criteria:**
- [ ] VU lifecycle: spawn, execute requests, complete
- [ ] Request selection by weight
- [ ] Think time between requests
- [ ] Protocol handler invocation
- [ ] Event emission for all VU actions
- [ ] Error handling: VU continues on request failure
- [ ] State tracking: idle, active, waiting
- [ ] Memory bounds: 64 KB per VU
- [ ] Minimum 2 assertions per function
- [ ] >90% test coverage
- [ ] Property test verified
- [ ] All tests pass

**Dependencies:** TASK-102, TASK-202 or TASK-204

**Labels:** `phase-3`, `vu`, `execution`

**Estimated Effort:** 28 hours

**Files:**
```
src/vu_engine.zig
tests/unit/vu_engine_test.zig
tests/integration/vu_lifecycle_test.zig
```

---

### TASK-302: CLI Implementation

**Description:** Implement command-line interface per `CLI_INTERFACE.md`

**Test-First Requirements:**
- [ ] Test argument parsing
- [ ] Test all commands with valid/invalid inputs
- [ ] Test exit codes

**Acceptance Criteria:**
- [ ] Commands: `run`, `replay`, `analyze`, `diff`, `validate`, `version`, `help`
- [ ] Command `run`: execute scenario, output results
- [ ] Command `replay`: verify deterministic replay
- [ ] Command `analyze`: recompute metrics from event log
- [ ] Command `diff`: compare two runs
- [ ] Command `validate`: check scenario file
- [ ] Argument parsing using `clap` library
- [ ] Output formats: summary (default), JSON, CSV
- [ ] Progress indicators (live mode)
- [ ] Signal handling: SIGINT (graceful shutdown)
- [ ] Exit codes: 0 (success), 1 (assertion failure), 2 (config error), 3 (runtime error)
- [ ] Minimum 2 assertions per function
- [ ] >85% test coverage
- [ ] All tests pass

**Dependencies:** TASK-300, TASK-301

**Labels:** `phase-3`, `cli`, `interface`

**Estimated Effort:** 32 hours

**Files:**
```
src/main.zig
src/cli.zig
tests/unit/cli_test.zig
tests/integration/cli_test.sh
```

---

## Phase 4: Metrics & Output

**Goal:** Post-run analysis and reporting

### TASK-400: HDR Histogram Integration

**Description:** Integrate HDR Histogram for latency metrics per `METRICS.md`

**Test-First Requirements:**
- [ ] Test histogram accuracy (known inputs)
- [ ] Test percentile calculations
- [ ] Test memory bounds

**Acceptance Criteria:**
- [ ] Vendor HDR Histogram C library
- [ ] Zig bindings for HDR Histogram
- [ ] Configuration: 1ns to 1 hour, 3 significant figures
- [ ] Record latencies from event log
- [ ] Compute percentiles: p50, p90, p95, p99, p999
- [ ] Bounded memory usage (independent of sample count)
- [ ] Minimum 2 assertions per function
- [ ] >90% test coverage
- [ ] Accuracy verified against known distributions
- [ ] All tests pass

**Dependencies:** TASK-100

**Labels:** `phase-4`, `metrics`, `histogram`

**Estimated Effort:** 16 hours

**Files:**
```
vendor/hdrhistogram/...
src/hdr_histogram.zig
tests/unit/hdr_test.zig
```

---

### TASK-401: Metrics Reducer Implementation

**Description:** Implement post-run metrics computation per `METRICS.md`

**Test-First Requirements:**
- [ ] Test request count metrics
- [ ] Test latency metrics
- [ ] Test throughput calculations
- [ ] Test error rate computation
- [ ] Property test: metrics consistency with event log

**Acceptance Criteria:**
- [ ] Read event log post-run
- [ ] Compute request metrics (total, by method, by status)
- [ ] Compute latency distribution (HDR histogram)
- [ ] Compute throughput (RPS, peak, min)
- [ ] Compute connection metrics
- [ ] Compute error metrics (total, by type)
- [ ] Assertion evaluation (pass/fail)
- [ ] Single-pass algorithm (O(N))
- [ ] Metrics computation < 3s for 10M events
- [ ] Minimum 2 assertions per function
- [ ] >95% test coverage
- [ ] Property test verified
- [ ] All tests pass

**Dependencies:** TASK-400, TASK-100

**Labels:** `phase-4`, `metrics`, `reducer`

**Estimated Effort:** 28 hours

**Files:**
```
src/metrics.zig
tests/unit/metrics_test.zig
tests/integration/metrics_accuracy_test.zig
```

---

### TASK-402: Output Formatters

**Description:** Implement output formats per `OUTPUT_FORMAT.md`

**Test-First Requirements:**
- [ ] Test summary text generation
- [ ] Test JSON output (schema validation)
- [ ] Test CSV generation
- [ ] Test diff output

**Acceptance Criteria:**
- [ ] Summary text formatter (human-readable)
- [ ] JSON formatter (machine-readable, schema-compliant)
- [ ] CSV time-series formatter
- [ ] Diff formatter (compare two runs)
- [ ] Metadata JSON generation
- [ ] Output directory structure per spec
- [ ] File I/O with error handling
- [ ] UTF-8 encoding validation
- [ ] Minimum 2 assertions per function
- [ ] >90% test coverage
- [ ] All output formats validated
- [ ] All tests pass

**Dependencies:** TASK-401

**Labels:** `phase-4`, `output`, `formatting`

**Estimated Effort:** 24 hours

**Files:**
```
src/output/summary.zig
src/output/json.zig
src/output/csv.zig
src/output/diff.zig
tests/unit/output_test.zig
```

---

## Phase 5: Testing & Verification

**Goal:** Comprehensive test suite and fuzzing infrastructure

### TASK-500: Fuzz Infrastructure Setup

**Description:** Set up fuzzing infrastructure per `FUZZ_TARGETS.md`

**Acceptance Criteria:**
- [ ] Fuzz targets for all parsers (HTTP/1.1, HTTP/2, HPACK, event, scenario)
- [ ] Corpus directories organized
- [ ] Seed corpus for each target (100+ files)
- [ ] Fuzzing build target: `zig build fuzz-targets`
- [ ] Integration with AFL++ or libFuzzer
- [ ] Sanitizers enabled (AddressSanitizer, UBSan)
- [ ] Fuzzing scripts: `scripts/run-fuzz.sh`
- [ ] Corpus minimization scripts
- [ ] Coverage tracking
- [ ] All fuzz targets compile
- [ ] Each target runs 1M inputs without crash

**Dependencies:** TASK-201, TASK-203, TASK-100, TASK-300

**Labels:** `phase-5`, `testing`, `fuzzing`

**Estimated Effort:** 40 hours

**Files:**
```
tests/fuzz/*.zig
corpus/*/...
scripts/run-fuzz.sh
scripts/minimize-corpus.sh
```

---

### TASK-501: Integration Test Suite

**Description:** End-to-end integration tests per `TESTING_STRATEGY.md`

**Acceptance Criteria:**
- [ ] Simple GET test (HTTP/1.1)
- [ ] POST request test (with body)
- [ ] HTTP/2 multiplexing test
- [ ] Concurrent VU test (1000+ VUs)
- [ ] Long-duration test (10+ minutes)
- [ ] Error scenario tests (timeouts, connection failures)
- [ ] Determinism verification test (replay)
- [ ] Metric accuracy test (known workload)
- [ ] All tests use mock servers (no external dependencies)
- [ ] Test execution time < 5 minutes
- [ ] All integration tests pass

**Dependencies:** TASK-302

**Labels:** `phase-5`, `testing`, `integration`

**Estimated Effort:** 32 hours

**Files:**
```
tests/integration/*.zig
tests/integration/mock_server.zig
tests/integration/fixtures/...
```

---

### TASK-502: Property-Based Testing

**Description:** Implement property tests per `TESTING_STRATEGY.md`

**Acceptance Criteria:**
- [ ] Property: request count = responses + errors
- [ ] Property: events respect happens-before ordering
- [ ] Property: metrics consistent with event log
- [ ] Property: memory usage within bounds
- [ ] Property: deterministic replay (same seed = same events)
- [ ] Run each property with 1000+ random inputs
- [ ] All property tests pass

**Dependencies:** TASK-401

**Labels:** `phase-5`, `testing`, `property-based`

**Estimated Effort:** 24 hours

**Files:**
```
tests/property/*.zig
```

---

## Phase 6: Documentation & Polish

**Goal:** Production-ready release

### TASK-600: Documentation Review & Examples

**Description:** Complete documentation with working examples

**Acceptance Criteria:**
- [ ] All 20 doc files reviewed and updated
- [ ] Example scenarios in `examples/`
  - Simple GET
  - API test (multiple endpoints)
  - Ramp test
  - Spike test
- [ ] README.md with:
  - Quick start
  - Installation
  - Basic usage
  - Links to docs
- [ ] Architecture diagrams updated
- [ ] API documentation generated
- [ ] No broken links in documentation
- [ ] All code examples tested and working

**Dependencies:** TASK-302

**Labels:** `phase-6`, `documentation`

**Estimated Effort:** 16 hours

---

### TASK-601: Limits Validation & Enforcement

**Description:** Validate all limits per `LIMITS.md` are enforced

**Acceptance Criteria:**
- [ ] VU limit enforced (100K max)
- [ ] Event log limit enforced (10M events)
- [ ] Memory budget enforced (16 GB)
- [ ] Connection limits enforced
- [ ] Request/response size limits enforced
- [ ] Timeout limits enforced
- [ ] All limit violations logged as errors
- [ ] Graceful degradation when soft limits hit
- [ ] Hard failures when hard limits exceeded
- [ ] Limits tested in integration suite
- [ ] All limit tests pass

**Dependencies:** TASK-101, TASK-301

**Labels:** `phase-6`, `limits`, `validation`

**Estimated Effort:** 16 hours

---

### TASK-602: Performance Benchmarking

**Description:** Verify performance targets from documentation

**Acceptance Criteria:**
- [ ] Event log append < 1μs
- [ ] HTTP/1.1 parse < 10μs
- [ ] Scheduler tick < 100ns
- [ ] Metrics computation < 3s for 10M events
- [ ] 100K VU scenario executes successfully
- [ ] Memory usage within predicted bounds
- [ ] Benchmark suite in `tests/benchmarks/`
- [ ] Benchmark results documented
- [ ] All performance targets met

**Dependencies:** TASK-401, TASK-501

**Labels:** `phase-6`, `performance`, `benchmarking`

**Estimated Effort:** 24 hours

**Files:**
```
tests/benchmarks/*.zig
```

---

## Phase 7: Release Preparation

### TASK-700: Release Checklist

**Description:** Final verification before v1.0 release

**Acceptance Criteria:**
- [ ] All unit tests pass (>90% coverage)
- [ ] All integration tests pass
- [ ] All fuzz targets run 24 hours without crash
- [ ] All property tests pass
- [ ] All benchmarks meet targets
- [ ] Documentation complete
- [ ] Examples tested
- [ ] Pre-commit hooks enforced
- [ ] Reproducible builds verified
- [ ] Memory leaks: zero (Valgrind)
- [ ] Static analysis clean
- [ ] CHANGELOG.md complete
- [ ] Version tagged: v1.0.0

**Dependencies:** All previous tasks

**Labels:** `phase-7`, `release`

**Estimated Effort:** 40 hours

---

## Summary

**Total Tasks:** 32
**Total Estimated Effort:** ~710 hours (~18 weeks single developer)

**Critical Path:**
1. Foundation (TASK-000 → TASK-002)
2. Core (TASK-100 → TASK-102)
3. HTTP (TASK-200 → TASK-204)
4. Execution (TASK-300 → TASK-302)
5. Metrics (TASK-400 → TASK-402)
6. Testing (TASK-500 → TASK-502)
7. Polish (TASK-600 → TASK-602)
8. Release (TASK-700)

**Philosophy Enforcement:**
- Every task requires tests FIRST
- Minimum 2 assertions per function
- Fuzzing for all parsers
- >90% coverage minimum
- Zero technical debt
- Pre-commit hooks prevent non-compliant code

---

**Version 1.0 — October 2025**
