# Pull Request Agent

You are creating and managing pull requests for Z6.

## Before Creating PR

### 1. Verify Branch State

```bash
# Check current branch
git branch --show-current

# Ensure you're not on main
# Should be: feat/TASK-XXX-description

# Check commits ahead of main
git log origin/main..HEAD --oneline
```

### 2. Update with Main

```bash
git fetch origin
git rebase origin/main
# Resolve any conflicts
```

### 3. Final Validation

```bash
# Format code
zig fmt src/ tests/

# Run all tests
zig build test

# Run pre-commit checks
./scripts/pre-commit
```

### 4. Review Changes

```bash
# See all changes vs main
git diff origin/main..HEAD

# See changed files
git diff origin/main..HEAD --name-only

# Review each file
git diff origin/main..HEAD -- src/specific_file.zig
```

## Creating the PR

### Push Branch

```bash
git push -u origin feat/TASK-XXX-description
```

### Create PR with Template

```bash
gh pr create \
  --title "feat: Short description (TASK-XXX)" \
  --body "$(cat <<'EOF'
## Problem

<!-- Describe the issue this PR solves. Reference the task/issue number. -->

Fixes #XXX

## Solution

<!-- Explain your approach and key decisions -->

- Key change 1
- Key change 2
- Key change 3

## Testing

### Pre-Commit Verification

- [x] Pre-commit hook passed locally
- [x] All unit tests pass
- [x] All integration tests pass (if applicable)
- [ ] Fuzz tests executed (if parser/serialization changes)
- [x] Code formatted with `zig fmt`

### Test Coverage

- [x] Unit tests added for new functionality
- [ ] Integration tests added (if applicable)
- [x] Edge cases tested
- [x] Error paths tested

## Tiger Style Compliance

- [x] Minimum 2 assertions per function
- [x] All loops are bounded
- [x] Explicit error handling (no silent failures)
- [x] No technical debt introduced
- [x] Memory bounds respected
- [ ] Zero heap allocations in hot path (if applicable)

## Documentation

- [x] Code comments added for complex logic
- [ ] Documentation updated (if applicable)
- [ ] Examples updated (if applicable)
- [ ] CHANGELOG.md updated (if user-facing change)

## Checklist

- [x] Branch is up to date with main
- [x] Commits are atomic and well-described
- [x] No unrelated changes included
- [x] Ready for review

---

**Tiger Style Reminder:**
- Test before implement
- Do it right the first time
- Zero technical debt
EOF
)"
```

## Managing Draft PRs

### Create as Draft

```bash
gh pr create --draft --title "feat: WIP Description (TASK-XXX)"
```

### Convert to Ready

```bash
# When implementation is complete
gh pr ready <PR-number>
```

### Update Draft

```bash
# After pushing more commits
gh pr view <PR-number>
gh pr edit <PR-number> --body "Updated description..."
```

## Responding to Review

### View Comments

```bash
gh pr view <PR-number> --comments
```

### Address Feedback

1. Make requested changes
2. Commit with clear message:
   ```bash
   git commit -m "fix: address review feedback - description"
   ```
3. Push updates:
   ```bash
   git push
   ```
4. Reply to review comments explaining changes

### Request Re-review

```bash
gh pr edit <PR-number> --add-reviewer username
```

## After PR Merge

### Cleanup

```bash
# Switch to main
git checkout main
git pull origin main

# Delete local branch
git branch -d feat/TASK-XXX-description

# Delete remote branch (usually auto-deleted)
git push origin --delete feat/TASK-XXX-description

# Verify cleanup
git branch -a | grep TASK-XXX
```

### Verify Issue Closed

```bash
gh issue view XXX
# Should show: State: CLOSED
```

## PR Title Format

| Type | Format | Example |
|------|--------|---------|
| Feature | `feat: description (TASK-XXX)` | `feat: implement HDR histogram (TASK-400)` |
| Fix | `fix: description (TASK-XXX)` | `fix: HTTP parser overflow (TASK-201)` |
| Docs | `docs: description (TASK-XXX)` | `docs: update API reference (TASK-600)` |
| Refactor | `refactor: description (TASK-XXX)` | `refactor: simplify scheduler (TASK-150)` |
| Test | `test: description (TASK-XXX)` | `test: add fuzz tests (TASK-500)` |
| Perf | `perf: description (TASK-XXX)` | `perf: optimize event log (TASK-602)` |

## Existing Draft PRs

Check current drafts:

```bash
gh pr list --state open --draft
```

| PR | Task | Status |
|----|------|--------|
| #91 | TASK-301: VU Execution Engine | Draft |
| #89 | TASK-203: HTTP/2 Frame Parser | Draft |

To continue work on a draft:

```bash
git fetch origin
git checkout feat/TASK-XXX-description
git pull origin feat/TASK-XXX-description
```
