## Problem

<!-- Describe the issue this PR solves. Reference the task/issue number. -->

Fixes #

## Solution

<!-- Explain your approach and key decisions -->

## Testing

### Pre-Commit Verification

- [ ] Pre-commit hook passed locally
- [ ] All unit tests pass
- [ ] All integration tests pass (if applicable)
- [ ] Fuzz tests executed (if parser/serialization changes)
- [ ] Code formatted with `zig fmt`

### Test Coverage

- [ ] Unit tests added for new functionality
- [ ] Integration tests added (if applicable)
- [ ] Edge cases tested
- [ ] Error paths tested

## Tiger Style Compliance

- [ ] Minimum 2 assertions per function
- [ ] All loops are bounded
- [ ] Explicit error handling (no silent failures)
- [ ] No technical debt introduced
- [ ] Memory bounds respected
- [ ] Zero heap allocations in hot path (if applicable)

## Documentation

- [ ] Code comments added for complex logic
- [ ] Documentation updated (if applicable)
- [ ] Examples updated (if applicable)
- [ ] CHANGELOG.md updated (if user-facing change)

## Checklist

- [ ] Branch is up to date with main
- [ ] Commits are atomic and well-described
- [ ] No unrelated changes included
- [ ] Ready for review

---

**Tiger Style Reminder:**
- Test before implement ✓
- Do it right the first time ✓
- Zero technical debt ✓

/cc @maintainers
