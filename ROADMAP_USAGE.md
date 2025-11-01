# Z6 Roadmap Usage Guide

> "Programmatic issue creation. Zero ambiguity. Full traceability."

## Overview

The Z6 roadmap is designed for programmatic GitHub issue creation. Every task maps directly to documentation with complete acceptance criteria.

## Files

```
ROADMAP.md                          # Master roadmap (32 tasks, 7 phases)
scripts/generate-issues.py          # GitHub issue generator
scripts/pre-commit                  # Tiger Style enforcement hook
scripts/install-hooks.sh            # Hook installer
.github/workflows/pr-verification.yml    # PR verification (NO CI/CD builds)
.github/PULL_REQUEST_TEMPLATE.md    # PR template
.github/BRANCH_PROTECTION.md        # Branch protection strategy
```

## Quick Start

### 1. Install Pre-Commit Hook

```bash
cd /home/sigma/Projects/Z6
./scripts/install-hooks.sh
```

This is **mandatory**. The hook enforces:
- Code formatting (`zig fmt`)
- Assertion density (min 2 per function)
- Bounded loops
- Explicit error handling
- Build success
- All tests pass

### 2. Generate GitHub Issues

Preview issues:

```bash
python3 scripts/generate-issues.py --dry-run
```

Create all issues:

```bash
python3 scripts/generate-issues.py --create
```

Create specific phase:

```bash
python3 scripts/generate-issues.py --create --filter "TASK-0"  # Phase 0 only
python3 scripts/generate-issues.py --create --filter "TASK-1"  # Phase 1 only
```

### 3. Configure Branch Protection

Follow `.github/BRANCH_PROTECTION.md` to set up GitHub branch protection for `main`.

Key settings:
- Require PR reviews (1-2 approvals)
- Require status checks (PR verification only)
- No direct pushes to main
- Squash merge only

## Workflow

### Phase-by-Phase Execution

Execute phases in order:

1. **Phase 0: Foundation** (TASK-000 to TASK-002)
   - Repository structure
   - Pre-commit hooks
   - Build system

2. **Phase 1: Core** (TASK-100 to TASK-102)
   - Event model
   - Memory model
   - Scheduler

3. **Phase 2: HTTP Protocol** (TASK-200 to TASK-204)
   - Protocol interface
   - HTTP/1.1 parser & handler
   - HTTP/2 parser & handler

4. **Phase 3: Execution** (TASK-300 to TASK-302)
   - Scenario parser
   - VU engine
   - CLI

5. **Phase 4: Metrics** (TASK-400 to TASK-402)
   - HDR histogram
   - Metrics reducer
   - Output formatters

6. **Phase 5: Testing** (TASK-500 to TASK-502)
   - Fuzz infrastructure
   - Integration tests
   - Property-based tests

7. **Phase 6: Polish** (TASK-600 to TASK-602)
   - Documentation
   - Limits validation
   - Performance benchmarking

8. **Phase 7: Release** (TASK-700)
   - Final verification
   - v1.0.0 release

### Task Execution

For each task:

1. **Read the task** in GitHub issue
2. **Read related documentation** (referenced in task)
3. **Write tests FIRST** (test-first requirements)
4. **Implement code** (follow acceptance criteria)
5. **Run pre-commit hook** (automatic on commit)
6. **Create PR** (use template)
7. **Code review** (maintainer approval)
8. **Squash merge** (to main)

## Tiger Style Development

### Test-First Discipline

Every task with code changes requires:

1. **Write failing test**
   ```bash
   # Create test file
   # Write test that fails (feature not implemented)
   zig build test  # Should fail
   ```

2. **Implement minimum code to pass**
   ```bash
   # Write implementation
   # Add assertions (min 2 per function)
   zig build test  # Should pass
   ```

3. **Refactor if needed**
   ```bash
   # Improve code
   # Tests still pass
   zig build test  # Should still pass
   ```

### Pre-Commit Hook Workflow

The hook runs automatically on `git commit`:

```bash
git add src/event.zig tests/event_test.zig
git commit -m "feat: implement event serialization (#100)"

# Hook runs:
# ✓ Code formatting
# ✓ Assertion density
# ✓ Bounded loops
# ✓ Explicit errors
# ✓ Build success
# ✓ All tests pass

# If all checks pass → commit succeeds
# If any check fails → commit blocked
```

### No CI/CD Builds

Z6 does **NOT** run builds or tests in GitHub Actions.

**Why?**
- Slow feedback (wait for CI)
- "Push and pray" culture
- Resource waste
- Developer should know code works

**Instead:**
- Pre-commit hook enforces quality
- Tests run locally before commit
- Immediate feedback
- Developer ownership

## Issue Management

### Labels

- `foundation` — Repository setup
- `core` — Event model, scheduler, memory
- `protocol` — HTTP, gRPC, WebSocket
- `parser` — Parsing implementations
- `fuzz-required` — Must add fuzz tests
- `tiger-style` — Always present (philosophy)
- `phase-N` — Phase identifier

### Dependencies

Tasks have explicit dependencies:

```
TASK-100 (Event Model) depends on TASK-002 (Build System)
TASK-102 (Scheduler) depends on TASK-100, TASK-101
TASK-201 (HTTP Parser) depends on TASK-200 (Protocol Interface)
```

Start with dependency-free tasks (Phase 0), then follow the tree.

### Acceptance Criteria

Every task has checkboxes for acceptance criteria:

```markdown
- [ ] Event Header struct defined
- [ ] Serialization functions implemented
- [ ] Minimum 2 assertions per function
- [ ] >95% test coverage
- [ ] All tests pass
- [ ] Fuzz test runs 1M inputs
```

**Definition of Done:** All checkboxes checked + PR approved + merged

## Customization

### Adding New Tasks

Edit `ROADMAP.md`:

```markdown
### TASK-XXX: Task Title

**Description:** Brief description

**Test-First Requirements:**
- [ ] Test requirement 1
- [ ] Test requirement 2

**Acceptance Criteria:**
- [ ] Criterion 1
- [ ] Criterion 2

**Dependencies:** TASK-YYY, TASK-ZZZ

**Labels:** `label1`, `label2`

**Estimated Effort:** N hours

**Files:**
```
file1.zig
file2.zig
```
```

Then regenerate issues:

```bash
python3 scripts/generate-issues.py --dry-run  # Preview
python3 scripts/generate-issues.py --create   # Create
```

### Modifying Pre-Commit Hook

Edit `scripts/pre-commit`:

```bash
# Add new check
echo "→ Checking new requirement..."
if ! my_check; then
    echo -e "${RED}✗ Check failed${NC}"
    FAILURES=$((FAILURES + 1))
fi
```

Reinstall:

```bash
./scripts/install-hooks.sh
```

## Progress Tracking

### GitHub Project Board

Create project board with columns:

1. **Backlog** — All issues
2. **Ready** — Dependencies met
3. **In Progress** — Assigned and started
4. **Review** — PR open
5. **Done** — Merged to main

### Burndown

Track completion:

```bash
# Total tasks
grep "^### TASK-" ROADMAP.md | wc -l  # 32

# Completed (closed issues)
gh issue list --state closed --label "tiger-style" | wc -l

# Progress = Completed / Total
```

### Milestones

- **Milestone 1:** Phase 0-1 complete (Foundation + Core)
- **Milestone 2:** Phase 2 complete (HTTP working)
- **Milestone 3:** Phase 3 complete (End-to-end scenarios)
- **Milestone 4:** Phase 4-5 complete (Metrics + Testing)
- **Milestone 5:** Phase 6-7 complete (Release)

## Common Questions

### Q: Can I skip the pre-commit hook?

**A:** No. Use `--no-verify` only for:
- Emergency hotfixes (with follow-up PR)
- Documentation-only changes

Any other bypass will be **rejected in code review**.

### Q: What if the hook is too slow?

**A:** The hook should run in <30 seconds. If slower:
- Reduce test scope (move integration tests out)
- Parallelize checks
- Profile and optimize

Do **not** disable checks.

### Q: Can I use traditional CI/CD?

**A:** No. Tiger Style philosophy requires:
- All validation local
- No "push and pray"
- Developer ownership
- Immediate feedback

CI/CD builds violate these principles.

### Q: What about fuzz tests (1M inputs)?

**A:** Fuzz tests run separately:

```bash
# During development (1 minute)
./scripts/run-fuzz.sh --timeout 60

# Before PR (10 minutes)
./scripts/run-fuzz.sh --timeout 600

# Pre-release (24 hours)
./scripts/run-fuzz.sh --timeout 86400
```

Not in pre-commit hook (too slow).

### Q: How do I know which task to start?

**A:** Follow dependency tree:

1. Check task dependencies
2. Ensure dependencies are complete (merged to main)
3. If dependencies met → task is ready
4. If multiple ready → choose by phase order

## Summary

Z6's roadmap provides:

- **32 tasks** across 7 phases
- **~710 hours** estimated effort
- **Programmatic issue creation**
- **Complete acceptance criteria**
- **Full Tiger Style compliance**

Development workflow:

1. Install pre-commit hook ✓
2. Generate GitHub issues ✓
3. Execute phase-by-phase ✓
4. Test-first discipline ✓
5. Pre-commit validation ✓
6. Code review ✓
7. Squash merge ✓

**Tiger Style: Do it right the first time.**

---

**Version 1.0 — October 2025**
