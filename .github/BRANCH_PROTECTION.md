# Branch Protection Strategy

## Philosophy

Z6 follows **Tiger Style** development:

> "All validation happens locally. Pre-commit hooks are the gatekeeper. CI/CD builds waste developer time and foster 'push and pray' culture."

## Main Branch Protection

Configure GitHub branch protection for `main`:

### Required Settings

1. **Require pull requests before merging**
   - ✅ Enabled
   - Require 1-2 approvals
   - Dismiss stale reviews

2. **Require status checks to pass**
   - ✅ `verify-local-validation` (from PR workflow)
   - ✅ `verify-issue-reference`
   - ✅ `check-pr-description`

3. **Require conversation resolution**
   - ✅ Enabled

4. **Do not allow bypassing the above settings**
   - ✅ Include administrators

5. **Require linear history**
   - ✅ Squash merging only
   - No merge commits
   - No rebase merging

### What We DON'T Do

❌ **NO CI/CD builds in GitHub Actions**
- Developers MUST run full test suite locally
- Pre-commit hook enforces this
- Failures caught before push, not after

❌ **NO automatic testing in CI**
- Tests run on developer machine
- Full control over test environment
- Immediate feedback

❌ **NO deployment pipelines in GitHub**
- Releases are manual and deliberate
- Tagged by maintainer after verification

## Pre-Commit Hook Enforcement

The **pre-commit hook** is the ONLY gatekeeper:

```bash
./scripts/install-hooks.sh
```

### What It Checks

1. **Code Formatting**
   - `zig fmt --check`
   - No unformatted code allowed

2. **Assertion Density**
   - Minimum 2 assertions per function
   - Enforces defensive programming

3. **Bounded Loops**
   - No unbounded `while(true)` without assertion
   - All loops provably terminate

4. **Explicit Error Handling**
   - No silent failures (`catch {}`)
   - Errors must be handled or propagated

5. **Build Success**
   - `zig build` must succeed
   - No broken builds committed

6. **All Tests Pass**
   - `zig build test` must pass
   - Zero test failures allowed

### Bypass Policy

The hook can be bypassed with `--no-verify`:

```bash
git commit --no-verify
```

**This is FORBIDDEN except for:**
- Emergency hotfixes (with follow-up PR)
- Documentation-only changes (no code)

Any other bypass will be **rejected in code review**.

## Development Workflow

### For Contributors

1. **Install pre-commit hook**
   ```bash
   ./scripts/install-hooks.sh
   ```

2. **Create feature branch**
   ```bash
   git checkout -b feat/TASK-123
   ```

3. **Write tests FIRST**
   ```bash
   # Create test file
   # Write failing test
   # Run: zig build test (should fail)
   ```

4. **Implement feature**
   ```bash
   # Write code
   # Add assertions (min 2 per function)
   # Run: zig build test (should pass)
   ```

5. **Format code**
   ```bash
   zig fmt src/ tests/
   ```

6. **Commit (hook runs automatically)**
   ```bash
   git add .
   git commit -m "feat: implement feature (#123)"
   # Hook runs: format, assertions, loops, build, tests
   ```

7. **Push and create PR**
   ```bash
   git push origin feat/TASK-123
   # Create PR on GitHub
   ```

### For Reviewers

Review checklist:

- [ ] Linked to task/issue
- [ ] PR description complete
- [ ] Tests were written first
- [ ] Acceptance criteria met
- [ ] Tiger Style compliance
  - [ ] Assertion density
  - [ ] Bounded loops
  - [ ] Explicit errors
- [ ] No technical debt
- [ ] Documentation updated

### For Maintainers

Merging checklist:

- [ ] Code review approved
- [ ] All checks passed
- [ ] Tests verified locally (if high-risk change)
- [ ] Fuzz tests run (if parser changes)
- [ ] Documentation reviewed

**Merge method:** Squash and merge only

## Why No CI/CD?

### Traditional CI/CD Problems

1. **Slow feedback loop**
   - Push → wait → see failure → fix → repeat
   - Wastes 5-30 minutes per iteration

2. **"Push and pray" culture**
   - Developers rely on CI to catch errors
   - Don't run tests locally
   - Multiple failed CI runs per PR

3. **Resource waste**
   - CI runs duplicate what should run locally
   - GitHub Actions minutes consumed
   - Environmental cost

4. **False sense of security**
   - Green CI ≠ correct code
   - Tests might be insufficient
   - Edge cases not covered

### Tiger Style Solution

1. **Immediate feedback**
   - Pre-commit hook runs in seconds
   - Errors caught before commit
   - No waiting for CI

2. **Developer ownership**
   - Full test suite on developer machine
   - Complete control
   - Understands failures immediately

3. **Resource efficiency**
   - Tests run once (locally)
   - No redundant CI builds
   - Faster iteration

4. **Genuine quality**
   - Tests must pass before commit
   - No bypassing checks
   - Quality enforced, not suggested

## Configuration

### GitHub Settings

```bash
# Branch protection rules for 'main'
gh api repos/:owner/:repo/branches/main/protection \
  --method PUT \
  --field required_status_checks[strict]=true \
  --field required_status_checks[contexts][]=verify-local-validation \
  --field required_pull_request_reviews[required_approving_review_count]=1 \
  --field required_pull_request_reviews[dismiss_stale_reviews]=true \
  --field required_conversation_resolution=true \
  --field enforce_admins=true \
  --field required_linear_history=true \
  --field allow_squash_merge=true \
  --field allow_merge_commit=false \
  --field allow_rebase_merge=false
```

### Repository Settings

- Automatically delete head branches: ✅
- Allow auto-merge: ❌
- Always suggest updating pull request branches: ✅

## Exception Policy

Exceptions to these rules require:

1. **Documented reason** in PR description
2. **Approval from 2+ maintainers**
3. **Follow-up task** to remove exception
4. **Added to technical debt log**

**No exceptions for:**
- Test failures
- Build failures
- Unformatted code

## Summary

Z6's branch protection is **developer-centric**:

- Pre-commit hooks enforce quality
- No CI/CD builds (by design)
- Immediate feedback
- Developer ownership
- Zero tolerance for broken code

**Tiger Style: Do it right the first time.**

---

**Version 1.0 — October 2025**
