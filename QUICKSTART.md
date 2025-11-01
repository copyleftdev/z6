# Z6 Quick Start Guide

> "From zero to GitHub in 5 minutes"

## Prerequisites

- GitHub CLI installed (`gh`)
- Git configured
- GitHub account authenticated (`gh auth login`)

## Step 1: Create GitHub Repository

```bash
# Run the setup script
./scripts/create-github-repo.sh

# This will:
# ✓ Create public repository
# ✓ Set description and topics
# ✓ Configure repository settings
# ✓ Add git remote
# ✓ Update README badges
```

## Step 2: Initialize Git and Commit

```bash
# Initialize repository (if not already done)
git init

# Stage all files
git add .

# Create initial commit
git commit -m "Initial commit: Z6 documentation and roadmap

- 21 complete technical specifications
- 32-task roadmap with full acceptance criteria
- Pre-commit hook for Tiger Style enforcement
- GitHub workflows and templates
- Programmatic issue generation
- Branch protection strategy"

# Rename branch to main
git branch -M main

# Push to GitHub
git push -u origin main
```

## Step 3: Configure Branch Protection

```bash
# After successful push, configure branch protection
./scripts/setup-branch-protection.sh

# This will:
# ✓ Require PR reviews (1 approval)
# ✓ Require status checks
# ✓ Enforce linear history
# ✓ Enable squash merge only
```

## Step 4: Generate GitHub Issues

```bash
# Preview issues for Phase 0 (Foundation)
python3 scripts/generate-issues.py --dry-run --filter "TASK-0"

# Create Phase 0 issues
python3 scripts/generate-issues.py --create --filter "TASK-0"

# Or create all 32 issues at once
python3 scripts/generate-issues.py --create
```

## Step 5: Install Pre-Commit Hook (Development)

```bash
# Install hook for local development
./scripts/install-hooks.sh

# Hook will validate:
# ✓ Code formatting (zig fmt)
# ✓ Assertion density (min 2 per function)
# ✓ Bounded loops
# ✓ Explicit error handling
# ✓ Build success
# ✓ All tests pass
```

## Step 6: Start Development

```bash
# Pick first task (TASK-000: Repository Structure)
# Read task description in GitHub issue

# Create branch
git checkout -b feat/TASK-000

# Complete acceptance criteria
# (See ROADMAP.md for details)

# Commit (pre-commit hook runs)
git commit -m "feat: repository structure (#000)"

# Push and create PR
git push origin feat/TASK-000
gh pr create
```

## Repository URL

After setup, your repository will be at:
```
https://github.com/YOUR_USERNAME/z6
```

## What You Get

### Documentation (21 files, ~220 KB)
- Complete technical specifications
- Architecture, design, protocols
- Testing strategy, fuzz targets
- Contributing guidelines

### Development Infrastructure
- **32 GitHub issues** with full acceptance criteria
- **Pre-commit hook** enforcing Tiger Style
- **Branch protection** (no direct commits to main)
- **PR templates** with required sections
- **No CI/CD** (local validation only)

### Roadmap Structure
- **Phase 0:** Foundation (3 tasks)
- **Phase 1:** Core Architecture (3 tasks)
- **Phase 2:** HTTP Protocol (5 tasks)
- **Phase 3:** Execution (3 tasks)
- **Phase 4:** Metrics (3 tasks)
- **Phase 5:** Testing (3 tasks)
- **Phase 6:** Polish (3 tasks)
- **Phase 7:** Release (1 task)

## Next Steps

### Immediate
1. ✅ Create repository (`./scripts/create-github-repo.sh`)
2. ✅ Initial commit and push
3. ✅ Configure branch protection
4. ✅ Generate Phase 0 issues

### Week 1
1. Install pre-commit hook
2. Complete TASK-000 (Repository Structure)
3. Complete TASK-001 (Pre-Commit Hook)
4. Complete TASK-002 (Build System)

### Month 1
1. Complete Phase 0 (Foundation)
2. Complete Phase 1 (Core Architecture)
3. Prove determinism with event model

### Months 2-5
1. Complete remaining phases
2. Comprehensive testing
3. v1.0.0 release

## Troubleshooting

### "gh: command not found"
Install GitHub CLI: https://cli.github.com/

### "not authenticated"
```bash
gh auth login
```

### "repository already exists"
Delete existing repo or use different name in script

### Pre-commit hook fails
This is intentional! Fix the issues it reports:
- Run `zig fmt src/`
- Add assertions (min 2 per function)
- Fix unbounded loops
- Ensure tests pass

## Support

- **Documentation:** [docs/](docs/)
- **Roadmap:** [ROADMAP.md](ROADMAP.md)
- **Contributing:** [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md)
- **Branch Protection:** [.github/BRANCH_PROTECTION.md](.github/BRANCH_PROTECTION.md)

---

**🐅 Tiger Style: Do it right the first time.**
