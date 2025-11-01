# Contributing to Z6

> "Zero technical debt. Do it right the first time."

## Welcome

Z6 follows Tiger Style — a disciplined approach to systems programming inspired by TigerBeetle. Contributions must meet high standards for:

1. **Safety** — Correctness over convenience
2. **Performance** — Predictability over throughput  
3. **Developer Experience** — Clarity over flexibility

## Before You Contribute

### Read the Philosophy

- `MANIFESTO.md` — Core principles
- `ARCHITECTURE.md` — System design
- Tiger Style guidelines (in repository root)

### Understand the Constraints

- No dynamic scripting
- No garbage collection
- No unbounded complexity
- Zero technical debt policy

## Code of Conduct

Be respectful, professional, and collaborative. We're building precision tools, not fighting.

## How to Contribute

### 1. Find or Create an Issue

Before writing code:

- Check existing issues
- For bugs: Provide reproduction steps
- For features: Discuss design first

**Do not submit PRs without an associated issue.**

### 2. Fork and Branch

```bash
git clone https://github.com/yourorg/z6.git
cd z6
git checkout -b fix/issue-123
```

Branch naming:

- `fix/issue-N` — Bug fixes
- `feat/issue-N` — New features
- `docs/issue-N` — Documentation
- `test/issue-N` — Tests only

### 3. Write Code

Follow Tiger Style:

#### Assertions

Minimum 2 assertions per function:

```zig
fn send_request(handler: *HTTPHandler, req: Request) !Response {
    assert(handler != null);
    assert(req.path.len > 0);
    assert(req.timeout_ns > 0);
    
    // Implementation...
    
    assert(response.request_id == req.id);
    return response;
}
```

#### Error Handling

All errors are explicit:

```zig
// BAD: Silent failure
fn parse(data: []const u8) ?Response {
    if (invalid(data)) return null;
    // ...
}

// GOOD: Explicit error
fn parse(data: []const u8) !Response {
    if (invalid(data)) return error.InvalidResponse;
    // ...
}
```

#### Bounds

Everything has limits:

```zig
// BAD: Unbounded
while (condition) {
    process_item();
}

// GOOD: Bounded
for (0..MAX_ITERATIONS) |i| {
    if (!condition) break;
    process_item();
}
assert(i < MAX_ITERATIONS); // Loop must terminate
```

#### Simplicity

Choose clarity over cleverness:

```zig
// BAD: Clever bit manipulation
const result = (x & 0xFF) | ((y & 0xFF) << 8);

// GOOD: Clear intent
const result = pack_u16(x, y);
```

### 4. Write Tests

#### Before Implementation

Test-driven development is mandatory:

```zig
test "HTTPParser: parse status line" {
    const parser = HTTPParser.init();
    const result = try parser.parse_status_line("HTTP/1.1 200 OK\r\n");
    
    try std.testing.expectEqual(200, result.status_code);
}
```

#### After Implementation

Verify tests pass:

```bash
zig build test
```

#### Coverage

Aim for >90% coverage:

```bash
zig build test -Dcoverage
```

### 5. Install Pre-Commit Hooks

**REQUIRED:** Install Tiger Style pre-commit hooks:

```bash
./scripts/install-hooks.sh
```

The pre-commit hook automatically enforces:
- **Code formatting** — Runs `zig fmt --check`
- **Assertion density** — Minimum 2 per function
- **Bounded loops** — No unbounded `while(true)` without markers
- **Explicit errors** — No silent `catch {}` 
- **Build success** — Runs `zig build`
- **All tests pass** — Runs `zig build test`

Hook execution time is < 30 seconds.

**To bypass (NOT RECOMMENDED):**
```bash
git commit --no-verify
```

### 6. Format Code

```bash
zig fmt src/
```

Z6 uses standard Zig formatting. No custom style.

### 7. Run Full Test Suite

```bash
# Unit tests
zig build test

# Integration tests
zig build test-integration

# Fuzz tests (1 minute)
zig build fuzz --timeout 60
```

All must pass.

### 8. Commit

#### Commit Message Format

```
<type>: <summary> (#issue)

<body>

<footer>
```

**Types:**
- `fix:` — Bug fix
- `feat:` — New feature
- `docs:` — Documentation
- `test:` — Tests
- `refactor:` — Code restructuring
- `perf:` — Performance improvement

**Example:**

```
fix: Handle ConnectionReset in HTTP parser (#42)

The HTTP parser didn't properly log ConnectionReset errors,
causing them to be lost. Now all connection errors emit
proper error events.

Added regression test to verify logging behavior.

Fixes #42
```

#### Commit Guidelines

- One logical change per commit
- Reference issue number
- Explain **why**, not just what
- Keep commits small and focused

### 9. Push and Create PR

```bash
git push origin fix/issue-123
```

Create pull request on GitHub.

## Pull Request Requirements

### PR Description Template

```markdown
## Problem

Describe the issue this PR solves.

## Solution

Explain your approach.

## Testing

- [ ] Unit tests added
- [ ] Integration tests added (if applicable)
- [ ] Fuzz tests added (if parsing/serialization)
- [ ] All tests pass
- [ ] Code formatted with `zig fmt`

## Checklist

- [ ] Assertions added (min 2 per function)
- [ ] Error handling is explicit
- [ ] All loops are bounded
- [ ] No technical debt introduced
- [ ] Documentation updated

Fixes #N
```

### Review Process

1. **Automated checks**
   - Tests pass
   - Formatting correct
   - No linter errors

2. **Code review**
   - Correctness
   - Tiger Style compliance
   - Performance implications
   - Test coverage

3. **Approval**
   - Requires 1-2 approvals
   - From maintainers

4. **Merge**
   - Squash and merge
   - Delete branch

## What We Look For

### ✅ Good PR

- Solves one problem
- Has comprehensive tests
- Follows Tiger Style
- Clear commit messages
- No technical debt

### ❌ Bad PR

- Multiple unrelated changes
- Missing tests
- Violates Tiger Style
- Vague commit messages
- Introduces technical debt

## Areas for Contribution

### High Priority

- **Protocol handlers** — gRPC, WebSocket
- **Fuzz testing** — New fuzz targets
- **Documentation** — Examples, guides
- **Bug fixes** — See issues

### Medium Priority

- **Performance** — Profiling, optimization
- **Metrics** — New metric types
- **Output formats** — New exporters

### Low Priority

- **UI/UX** — CLI improvements
- **Integrations** — CI/CD examples

## Protocol Contributions

To add a new protocol (e.g., gRPC):

### 1. Specification

Create `GRPC_PROTOCOL.md`:

- Supported features
- Unsupported features
- Error handling
- Limits

### 2. Implementation

Implement `ProtocolHandler` interface:

```zig
const GRPCHandler = struct {
    pub fn init(allocator: Allocator, config: GRPCConfig) !*GRPCHandler {
        // ...
    }
    
    pub fn connect(self: *GRPCHandler, target: Target) !ConnectionId {
        // ...
    }
    
    // ... rest of interface
};
```

### 3. Tests

- Unit tests for all functions
- Integration test with mock server
- Fuzz test for protobuf parsing

### 4. Documentation

- Update `PROTOCOL_INTERFACE.md`
- Add examples to `docs/examples/`

## Bug Reports

Good bug reports include:

### Template

```markdown
## Description

Clear description of the bug.

## Reproduction

Steps to reproduce:

1. Run `z6 run scenario.toml`
2. Observe error

## Expected

What should happen.

## Actual

What actually happens.

## Environment

- Z6 version: `z6 version`
- OS: Linux/macOS/Windows
- Scenario: (attach or link)

## Logs

```
Error logs here
```

## Suggested Fix

(Optional) Your ideas for fixing it.
```

## Feature Requests

Good feature requests include:

### Template

```markdown
## Use Case

Why is this needed? What problem does it solve?

## Proposed Solution

How would this work?

## Alternatives Considered

What other approaches did you consider?

## Compatibility

Does this affect existing functionality?

## Scope

How much work is this? (small/medium/large)
```

## Design Discussions

For significant changes:

1. Open issue with `[RFC]` prefix
2. Provide detailed design document
3. Discuss trade-offs
4. Reach consensus
5. Implement

## Maintainer Responsibilities

Maintainers must:

- Review PRs within 48 hours
- Provide constructive feedback
- Enforce Tiger Style
- Maintain zero technical debt
- Be responsive to contributors

## License

By contributing, you agree that your contributions will be licensed under the same license as Z6 (MIT or Apache 2.0, TBD).

## Attribution

Contributors are listed in `CONTRIBUTORS.md`.

## Questions?

- GitHub Discussions — General questions
- GitHub Issues — Bug reports, feature requests
- Email — [email address] — Security issues only

---

## Summary

Contributing to Z6 requires:

- **Discipline** — Tiger Style is non-negotiable
- **Tests** — Comprehensive coverage
- **Documentation** — Clear explanations
- **Patience** — Reviews are thorough

We maintain high standards because correctness matters.

---

**Version 1.0 — October 2025**
