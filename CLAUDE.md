# Z6 Project Configuration

> **Z6** is a deterministic, high-performance, auditable load testing tool written in Zig.
> Built with Tiger Style philosophy: safety, performance, developer experience.

## Project Overview

- **Language:** Zig (0.11.0+)
- **Architecture:** Single-threaded, async I/O, deterministic scheduler
- **Philosophy:** Tiger Style (TigerBeetle-inspired discipline)
- **Status:** Pre-alpha, ~10,300 lines across 17 modules

### Key Directories

```
src/           # Core implementation (17 modules)
tests/         # Unit, integration, fuzz tests
docs/          # Technical specifications
scripts/       # Development tooling & pre-commit hooks
examples/      # Working demonstrations
```

### Build Commands

```bash
zig build              # Build project
zig build test         # Run all tests
zig fmt src/ tests/    # Format code
```

---

## GitHub Workflow Integration

### Branch & Issue Tracking

This project uses GitHub Issues for task management. **Always check context before working:**

```bash
# Check current branch
git branch --show-current

# Check open issues assigned to you
gh issue list --assignee @me

# Check open PRs
gh pr list --state open

# View specific issue
gh issue view <issue-number>
```

### Branch Naming Convention

| Type | Format | Example |
|------|--------|---------|
| Feature | `feat/TASK-XXX-description` | `feat/TASK-301-vu-execution-engine` |
| Bug fix | `fix/TASK-XXX-description` | `fix/TASK-201-http-parser-overflow` |
| Docs | `docs/TASK-XXX-description` | `docs/TASK-600-api-documentation` |
| Refactor | `refactor/TASK-XXX-description` | `refactor/TASK-150-memory-pools` |
| Test | `test/TASK-XXX-description` | `test/TASK-500-fuzz-infrastructure` |

### Commit Message Format (Conventional Commits)

```
<type>(<scope>): <subject> (TASK-XXX)

<body>

<footer>
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `chore`

**Examples:**
```
feat(http): implement HTTP/2 frame parser (TASK-203)

Add RFC 7540 compliant frame parsing with header compression.
Includes 28 unit tests and fuzz test coverage.

Closes #62
```

### Pull Request Workflow

1. **Before creating PR:**
   - Ensure branch is up to date with main
   - All tests pass locally (`zig build test`)
   - Pre-commit hook passes
   - Code formatted (`zig fmt`)

2. **PR Title Format:** `feat: Description (TASK-XXX)`

3. **Required sections in PR description:**
   - Problem (what issue does this solve?)
   - Solution (approach and key decisions)
   - Testing (tests added/run)
   - Tiger Style Compliance checklist

4. **Link to issue:** Include `Fixes #<issue-number>` or `Closes #<issue-number>`

---

## Tiger Style Rules (MANDATORY)

### Core Philosophy

- **Simplicity over complexity** - The simple solution is easier to verify
- **Do it right the first time** - Zero technical debt policy
- **Test before implement** - Write failing tests, then make them pass
- **Fail fast** - Assertions downgrade bugs into liveness issues
- **Explicit over implicit** - No hidden state, no magic

### Assertions (Non-Negotiable)

**Minimum 2 assertions per function:**

```zig
fn process(data: []const u8) !Result {
    assert(data.len > 0);           // precondition
    assert(data.len <= MAX_SIZE);   // bound check

    const result = try compute(data);

    assert(result.isValid());       // postcondition
    assert(result.size <= data.len); // invariant
    return result;
}
```

- Assert all function arguments (preconditions)
- Assert all return values (postconditions)
- Assert invariants throughout execution
- Test files are exempt from assertion density requirements

### Bounded Loops (Non-Negotiable)

**All loops MUST be provably bounded:**

```zig
// GOOD: Bounded by slice length
for (items) |item| { ... }

// GOOD: Bounded by explicit limit
var i: usize = 0;
while (i < MAX_ITERATIONS) : (i += 1) { ... }

// GOOD: Event loop with unreachable
while (true) {
    // event loop body
}
unreachable;

// FORBIDDEN: Unbounded without assertion
while (condition) { ... }  // Must have explicit bound
```

- **No recursion** - All executions must be provably bounded
- Prefer `for` loops with explicit iteration counts
- Event loops (`while (true)`) must be followed by `unreachable` or `assert`

### Error Handling (Non-Negotiable)

**All errors MUST be explicit - no silent failures:**

```zig
// FORBIDDEN - Silent error suppression
something() catch {};

// REQUIRED - Explicit handling
something() catch |err| {
    log.err("Failed: {}", .{err});
    return error.OperationFailed;
};

// REQUIRED - Propagation
try something();
```

- Use `try` to propagate errors up the call stack
- Define specific error sets, not `anyerror`
- Document all error cases in function comments
- Use `errdefer` for partial cleanup

### Memory Management

```zig
// Pair allocations with deallocations
const buffer = try allocator.alloc(u8, size);
defer allocator.free(buffer);
```

- **All allocations must be bounded** - No unbounded growth
- Document memory ownership explicitly
- Use `defer` for cleanup immediately after allocation
- Check allocation results - never assume success
- Specify maximum memory limits for all data structures

### Determinism Requirements

- **Single-threaded by design** for core execution
- Use logical ticks, not wall-clock time
- All operations must be deterministic given same seed
- PRNG must be seeded explicitly
- No system calls that introduce non-determinism in core logic

---

## Zig Best Practices

### Memory Safety

- **Avoid `@ptrCast`** unless absolutely necessary
- **Never use `@ptrFromInt`** with arbitrary values
- **Use slices over raw pointers** - Slices carry length information
- **Always check allocation results**
- **Initialize all memory** - Uninitialized memory is UB
- Use `defer` for RAII-like cleanup

### Integer Safety

```zig
// Use explicit overflow handling
const result = @addWithOverflow(a, b);
if (result[1] != 0) return error.Overflow;

// Use sized integers, not usize
const count: u32 = @intCast(value);

// Use saturating arithmetic where appropriate
const safe_value = @min(calculated_value, MAX_ALLOWED);
```

### Type Safety

- Use explicit sized types: `u32`, `i64` (avoid `usize` unless necessary)
- Validate all enum values from external sources
- Use optionals (`?T`) for "might not exist"
- Use error unions (`!T`) for "might fail"
- Use `std.mem.eql` for slice equality (not `==`)

### Comptime Best Practices

```zig
comptime {
    assert(@sizeOf(Header) == 24);
    assert(@alignOf(Header) == 8);
}
```

- Use `comptime` for validation at compile time
- Type-level programming for zero-cost abstractions
- Document comptime parameters clearly

### Security Considerations

- **Validate all external input** - Never trust user data
- Use constant-time comparison for secrets: `std.crypto.utils.timingSafeEql`
- Clear sensitive data: `std.crypto.utils.secureZero`
- Check buffer sizes to prevent overflows
- Limit resource usage to prevent DoS

---

## Testing Requirements

### Test-Driven Development

1. **Write tests FIRST** - Create failing test
2. **Run tests** - Verify they fail (`zig build test`)
3. **Implement feature** - Make tests pass
4. **Refactor** - Clean up while tests stay green

### Coverage Requirements

- **Minimum 90% test coverage target**
- Test happy path AND error paths
- Test boundary conditions (min, max, zero, one-off)
- Property-based tests for complex logic
- **Fuzz tests for all parsers** (minimum 1M inputs)

### Test File Organization

```
tests/
  unit/           # Unit tests for individual modules
  integration/    # Integration tests for component interaction
  fuzz/           # Fuzzing tests for parsers
  fixtures/       # Test data files
```

---

## Pre-Commit Checks

The pre-commit hook enforces Tiger Style. **All checks must pass:**

1. **Code formatting** - `zig fmt --check`
2. **Assertion density** - Minimum 2 per function
3. **Bounded loops** - No unbounded `while(true)` without assertion
4. **Explicit error handling** - No `catch {}`
5. **Build success** - `zig build`
6. **All tests pass** - `zig build test`

**To install hooks:**
```bash
./scripts/install-hooks.sh
```

**Bypass is FORBIDDEN except for:**
- Emergency hotfixes (with follow-up PR)
- Documentation-only changes (no code)

---

## Forbidden Practices

| Practice | Reason |
|----------|--------|
| `catch {}` | Silent error suppression |
| `while (true)` without unreachable | Unbounded loop |
| Recursion | Unbounded execution |
| `usize` for data sizes | Architecture-dependent |
| Functions with < 2 assertions | Insufficient invariant checking |
| Magic numbers | Use named constants |
| Global mutable state | Hidden state |
| Implicit allocations | Hidden memory behavior |
| `@as` to bypass type safety | Find proper solution |
| `catch unreachable` on fallible ops | Hides potential failures |

---

## Code Style

- Use `zig fmt` - formatting must be consistent
- Descriptive variable names (no single letters except loop counters)
- Comments explain **WHY**, not **WHAT**
- Group related functionality
- One struct per file for major types
- Use `pub` intentionally - minimal public API

---

## Project-Specific Context

### Key Architecture Decisions

1. **Deterministic Reproducibility** - Same seed = identical execution
2. **Immutable Event Log** - All actions logged as fixed-size (272B) events
3. **Logical Ticks** - Not wall-clock time
4. **Bounded Resources** - 100K VUs, 10M events, 16GB RAM max
5. **Protocol Abstraction** - Pluggable handlers (HTTP/1.1, HTTP/2, gRPC)

### Current Development Phases

| Phase | Status | Focus |
|-------|--------|-------|
| Phase 0-3 | Complete | Foundation, Core, HTTP, Execution |
| Phase 4 | ~85% | Metrics (HDR Histogram, Reducers) |
| Phase 5 | Pending | Testing (Fuzz, Integration, Property) |
| Phase 6 | Pending | Polish (Docs, Limits, Benchmarks) |
| Phase 7 | Pending | Release v1.0.0 |

### Important Files

| File | Purpose |
|------|---------|
| `src/main.zig` | CLI entry point |
| `src/scheduler.zig` | Deterministic microkernel |
| `src/event.zig` | Immutable event model |
| `src/protocol.zig` | Protocol interface |
| `src/http1_handler.zig` | HTTP/1.1 implementation |
| `docs/MANIFESTO.md` | Design philosophy |
| `ROADMAP.md` | Task tracking |

---

## Quick Reference

### Before Starting Work

```bash
git checkout main && git pull
gh issue list --assignee @me
git checkout -b feat/TASK-XXX-description
```

### Before Committing

```bash
zig fmt src/ tests/
zig build test
git add .
git commit -m "feat(scope): description (TASK-XXX)"
```

### Before Creating PR

```bash
git fetch origin
git rebase origin/main
zig build test
git push -u origin feat/TASK-XXX-description
gh pr create --title "feat: Description (TASK-XXX)" --body "..."
```

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

*Tiger Style: Do it right the first time.*
