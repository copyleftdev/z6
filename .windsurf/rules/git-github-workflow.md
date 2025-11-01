---
trigger: always_on
description: "Expert-level Git and GitHub workflow etiquette - branch awareness, ticket tracking, and lifecycle management"
---

# Git & GitHub Workflow Excellence

## Branch Awareness (CRITICAL)

<branch_awareness>
- **ALWAYS check current branch before any action**:
  ```bash
  git branch --show-current
  ```
- **State what branch you're on** when discussing changes
- **Never assume branch context** - verify explicitly
- **Know the branch state**:
  - Is it ahead/behind remote?
  - Are there uncommitted changes?
  - Is it up to date with main?
- **Check status before operations**:
  ```bash
  git status
  git log --oneline -5
  git branch -vv  # shows tracking info
  ```
</branch_awareness>

## Branch Naming Convention

<branch_naming>
- **Feature branches:** `feat/TASK-XXX-short-description`
  - Example: `feat/TASK-100-event-model-implementation`
- **Bug fixes:** `fix/TASK-XXX-short-description`
  - Example: `fix/TASK-201-http-parser-overflow`
- **Documentation:** `docs/TASK-XXX-short-description`
  - Example: `docs/TASK-600-api-documentation`
- **Refactoring:** `refactor/TASK-XXX-short-description`
- **Testing:** `test/TASK-XXX-short-description`
- **Hotfix:** `hotfix/issue-XXX-short-description`

**Format rules:**
- All lowercase
- Use hyphens, not underscores
- Include task/issue number
- Max 50 characters total
- Descriptive but concise
</branch_naming>

## Issue/Ticket Awareness

<ticket_tracking>
- **Always reference the current task** you're working on
- **Know the issue number** before starting work
- **Check issue status** before and after work:
  ```bash
  gh issue view TASK-100
  gh issue list --assignee @me
  ```
- **State acceptance criteria** from the issue
- **Track which criteria are complete** vs pending
- **Update issue with progress** regularly
- **Link commits to issues** with issue number in commit message
- **Close issues properly** through PRs or commits
</ticket_tracking>

## Commit Message Standards

<commit_messages>
**Format (Conventional Commits):**
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Type (required):**
- `feat:` - New feature (maps to MINOR in semver)
- `fix:` - Bug fix (maps to PATCH in semver)
- `docs:` - Documentation only
- `style:` - Formatting, no code change
- `refactor:` - Code change that neither fixes nor adds feature
- `perf:` - Performance improvement
- `test:` - Adding or updating tests
- `chore:` - Maintenance, dependencies, tooling

**Subject line rules:**
- Max 50 characters
- Imperative mood ("add" not "added")
- No period at end
- Capitalize first letter
- Reference issue: `feat: implement event serialization (#100)`

**Body (optional but recommended):**
- Wrap at 72 characters
- Explain WHAT and WHY, not HOW
- Separate from subject with blank line

**Footer (for breaking changes or issue references):**
```
Fixes #100
Closes #200
BREAKING CHANGE: API signature changed
```

**Examples:**
```
feat: implement HDR histogram integration (#400)

Add HdrHistogram C library bindings for latency metrics.
Configured for 1ns to 1 hour range with 3 significant figures.

Closes #400

---

fix: prevent buffer overflow in HTTP parser (#201)

Add bounds checking before writing to response buffer.
Adds assertion for buffer size validation.

Fixes #201

---

test: add fuzz tests for event serialization (#100)

Run 1M random inputs through event deserializer.
All tests pass without crashes.

Relates to #100
```
</commit_messages>

## Pre-Commit Workflow

<pre_commit_workflow>
**Before EVERY commit:**

1. **Check current branch:**
   ```bash
   git branch --show-current
   ```

2. **Review what's staged:**
   ```bash
   git status
   git diff --staged
   ```

3. **Verify tests pass:**
   ```bash
   zig build test
   ```

4. **Verify pre-commit hook passes:**
   ```bash
   .git/hooks/pre-commit
   ```

5. **Review files being committed:**
   ```bash
   git diff --staged --name-only
   ```

6. **Check for sensitive data:**
   - No API keys, passwords, tokens
   - No personal information
   - No absolute paths (use relative)

7. **Verify commit message quality:**
   - Follows conventional commits format
   - References issue number
   - Clear and descriptive
</pre_commit_workflow>

## Pull Request Workflow

<pr_workflow>
**Before creating PR:**

1. **Ensure branch is up to date:**
   ```bash
   git fetch origin
   git rebase origin/main  # or merge if preferred
   ```

2. **Verify all tests pass locally:**
   ```bash
   zig build test
   ./scripts/run-fuzz.sh --timeout 60  # if parser changes
   ```

3. **Review all changes:**
   ```bash
   git diff main...HEAD
   ```

4. **Ensure commits are clean:**
   - Squash fixup commits
   - Rewrite unclear messages
   - Group related changes

**Creating the PR:**

1. **Use the PR template** (`.github/PULL_REQUEST_TEMPLATE.md`)

2. **Title format:**
   ```
   TASK-XXX: Brief description of changes
   ```

3. **Fill ALL sections:**
   - Problem (what issue does this solve?)
   - Solution (how did you solve it?)
   - Testing (what tests did you add/run?)
   - Tiger Style Compliance (checklist)
   - Documentation (what docs did you update?)

4. **Reference the issue:**
   ```markdown
   Fixes #100
   Closes TASK-100
   ```

5. **Add reviewers** if known

6. **Self-review first:**
   - Read through the diff on GitHub
   - Add comments explaining complex parts
   - Verify all acceptance criteria met

**PR states to track:**
- Draft (work in progress)
- Ready for Review (complete, tests passing)
- Changes Requested (address feedback)
- Approved (ready to merge)
</pr_workflow>

## Branch Lifecycle Management

<branch_lifecycle>
**Branch creation:**
```bash
# Start from main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feat/TASK-100-event-model

# Push and set upstream
git push -u origin feat/TASK-100-event-model
```

**During development:**
```bash
# Regularly check status
git status
git log --oneline origin/main..HEAD  # commits ahead

# Keep updated with main (daily)
git fetch origin
git rebase origin/main  # or merge

# Push updates
git push origin feat/TASK-100-event-model
```

**After PR merge:**
```bash
# Switch to main
git checkout main
git pull origin main

# Delete local branch
git branch -d feat/TASK-100-event-model

# Delete remote branch (if not auto-deleted)
git push origin --delete feat/TASK-100-event-model

# Verify cleanup
git branch -a | grep TASK-100  # should be empty
```

**Branch hygiene:**
- Delete merged branches promptly
- Don't reuse old branches
- Keep branch count low (< 5 active)
- Archive long-lived branches if needed
</branch_lifecycle>

## Git Etiquette

<git_etiquette>
**DO:**
- ✅ Commit early, commit often (in feature branches)
- ✅ Write meaningful commit messages
- ✅ Reference issues in commits
- ✅ Keep commits atomic (one logical change)
- ✅ Rebase to keep history clean
- ✅ Pull before push
- ✅ Review your own code first
- ✅ Communicate in PR comments
- ✅ Test before committing
- ✅ Keep branches short-lived (< 3 days)

**DON'T:**
- ❌ Commit directly to main
- ❌ Force push to shared branches
- ❌ Commit broken code
- ❌ Mix unrelated changes in one commit
- ❌ Use vague commit messages ("fix stuff", "wip")
- ❌ Commit commented-out code
- ❌ Ignore merge conflicts
- ❌ Push without testing
- ❌ Rewrite public history
- ❌ Leave stale branches around
</git_etiquette>

## Status Awareness Commands

<status_commands>
**Current state check:**
```bash
# What branch am I on?
git branch --show-current

# What's changed?
git status

# What's staged?
git diff --staged

# What commits are ahead?
git log origin/main..HEAD --oneline

# What commits are behind?
git log HEAD..origin/main --oneline

# Show tracking info
git branch -vv

# Show remote status
git fetch --dry-run
```

**Issue state check:**
```bash
# My assigned issues
gh issue list --assignee @me

# View specific issue
gh issue view TASK-100

# Check issue status
gh issue view TASK-100 --json state,title,assignees

# List open issues in phase
gh issue list --label "phase-1"
```

**PR state check:**
```bash
# My PRs
gh pr list --author @me

# View PR status
gh pr view 42

# Check PR checks
gh pr checks 42

# View PR diff
gh pr diff 42
```
</status_commands>

## Working with Multiple Issues

<multi_issue_workflow>
**Context switching:**

1. **Save current work:**
   ```bash
   # If work is incomplete
   git stash push -m "WIP: TASK-100 event model"
   
   # Note where you left off
   echo "Working on event serialization tests" > .task-100-notes.txt
   git add .task-100-notes.txt
   git commit -m "chore: save progress notes"
   ```

2. **Switch to new task:**
   ```bash
   git checkout main
   git pull
   git checkout -b feat/TASK-200-protocol-interface
   
   # Update issue status
   gh issue comment TASK-200 --body "Starting work on this issue"
   ```

3. **Return to previous work:**
   ```bash
   git checkout feat/TASK-100-event-model
   git stash pop
   cat .task-100-notes.txt  # recall context
   ```

**Parallel work tracking:**
- Keep notes in branch-specific files
- Update issue comments with status
- Use project boards for visual tracking
- Set issue milestones
</multi_issue_workflow>

## Conflict Resolution

<conflict_resolution>
**When conflicts occur:**

1. **Understand the conflict:**
   ```bash
   git status  # shows conflicted files
   git diff    # shows conflict markers
   ```

2. **Resolve thoughtfully:**
   - Understand both changes
   - Preserve intent of both sides when possible
   - Don't blindly accept yours or theirs
   - Test after resolution

3. **Mark as resolved:**
   ```bash
   git add <resolved-file>
   git rebase --continue  # or git merge --continue
   ```

4. **Verify result:**
   ```bash
   zig build test
   git log --oneline -5  # check history
   ```

**Avoid conflicts:**
- Pull/rebase frequently
- Keep branches short-lived
- Coordinate on shared files
- Communicate in team chat
</conflict_resolution>

## Code Review Etiquette

<code_review_etiquette>
**As author:**
- Respond to all comments
- Be open to feedback
- Don't take criticism personally
- Ask questions if unclear
- Push fixes in new commits (before squashing)
- Mark conversations as resolved
- Thank reviewers

**As reviewer:**
- Be respectful and constructive
- Explain reasoning for changes
- Distinguish between must-fix and nice-to-have
- Approve when acceptance criteria met
- Use suggestion feature for small changes
- Review promptly (within 24 hours)
</code_review_etiquette>

## Emergency Procedures

<emergency_procedures>
**If you committed to wrong branch:**
```bash
# Cherry-pick to correct branch
git checkout correct-branch
git cherry-pick <commit-hash>

# Remove from wrong branch
git checkout wrong-branch
git reset --hard HEAD~1
```

**If you need to undo last commit:**
```bash
# Keep changes, undo commit
git reset --soft HEAD~1

# Discard changes and commit
git reset --hard HEAD~1  # DANGEROUS
```

**If main is broken:**
```bash
# Create hotfix branch
git checkout -b hotfix/critical-issue main
# Fix and test
# Create PR with "HOTFIX:" prefix
```

**If you pushed sensitive data:**
1. Rotate credentials immediately
2. Contact admin to purge history
3. Force push cleaned history (if allowed)
4. Update .gitignore to prevent repeat
</emergency_procedures>

## Daily Workflow Checklist

<daily_checklist>
**Start of day:**
- [ ] `git checkout main && git pull`
- [ ] Check assigned issues: `gh issue list --assignee @me`
- [ ] Review PR feedback: `gh pr list --author @me`
- [ ] Create/switch to feature branch
- [ ] Update issue status to "In Progress"

**During work:**
- [ ] Commit frequently with good messages
- [ ] Push to remote branch regularly
- [ ] Keep branch updated with main
- [ ] Run tests before each commit
- [ ] Update issue with progress

**End of day:**
- [ ] Commit all work (even WIP)
- [ ] Push to remote
- [ ] Comment on issue with status
- [ ] Update project board if used
- [ ] Plan next day's work
</daily_checklist>

---

**Remember:** Git is a communication tool. Your commits, branches, and PRs tell a story. Make it a clear, professional story that your team (and future you) will appreciate.