# Task Management Agent

You are managing development tasks for Z6 using GitHub Issues.

## Starting a New Task

### 1. Get Current Context

```bash
# Check what's assigned to you
gh issue list --assignee @me

# Check current branch
git branch --show-current

# Check for any uncommitted work
git status
```

### 2. Select and Understand Task

```bash
# View the issue
gh issue view <issue-number>

# Check issue labels and milestone
gh issue view <issue-number> --json labels,milestone,assignees
```

### 3. Create Feature Branch

```bash
# Ensure main is up to date
git checkout main
git pull origin main

# Create branch following naming convention
git checkout -b feat/TASK-XXX-description
# or: fix/TASK-XXX-description
# or: docs/TASK-XXX-description

# Push and set upstream
git push -u origin feat/TASK-XXX-description
```

### 4. Update Issue Status

```bash
# Add comment that work has started
gh issue comment <issue-number> --body "Starting work on this issue"

# If using project boards, move to "In Progress"
```

## During Development

### Track Progress

```bash
# Regular commits with good messages
git commit -m "feat(module): progress description (TASK-XXX)"

# Push updates
git push

# Comment on issue with progress
gh issue comment <issue-number> --body "Progress update: completed X, working on Y"
```

### Stay Updated with Main

```bash
git fetch origin
git rebase origin/main
# or: git merge origin/main
```

## Completing a Task

### 1. Final Verification

```bash
zig fmt src/ tests/
zig build test
```

### 2. Create Pull Request

```bash
gh pr create \
  --title "feat: Description (TASK-XXX)" \
  --body "$(cat <<'EOF'
## Problem

Fixes #<issue-number>

## Solution

<explanation of approach>

## Testing

- [ ] Unit tests added
- [ ] Integration tests (if applicable)
- [ ] Fuzz tests (if parser changes)

## Tiger Style Compliance

- [ ] Minimum 2 assertions per function
- [ ] All loops bounded
- [ ] Explicit error handling
- [ ] Memory bounds respected

## Documentation

- [ ] Code comments added
- [ ] Docs updated (if applicable)
EOF
)"
```

### 3. After PR Merge

```bash
# Switch to main and update
git checkout main
git pull origin main

# Delete feature branch
git branch -d feat/TASK-XXX-description
git push origin --delete feat/TASK-XXX-description

# Verify issue was closed
gh issue view <issue-number>
```

## Task Priority Guide

| Phase | Priority | Focus |
|-------|----------|-------|
| Phase 4 | High | Metrics (TASK-400, 401, 402) |
| Phase 3 | High | VU Execution (TASK-301) |
| Phase 2 | Medium | HTTP/2 (TASK-203, 204) |
| Phase 5 | Medium | Testing infrastructure |
| Phase 6-7 | Lower | Polish and release |

## Open Issues Quick Reference

```bash
# List all open issues
gh issue list --state open

# Filter by phase
gh issue list --label "phase-4"

# Filter by type
gh issue list --label "tiger-style"
```

## Draft PRs (Work in Progress)

```bash
# Check draft PRs
gh pr list --state open --draft

# View specific draft
gh pr view <PR-number>

# Convert draft to ready
gh pr ready <PR-number>
```
