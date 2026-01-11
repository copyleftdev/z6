# Claude Code Configuration

This directory contains configuration files for Claude Code AI assistant.

## Structure

```
.claude/
├── README.md           # This file
├── settings.json       # Project settings and metadata
└── commands/           # Specialized agent prompts
    ├── implement.md    # Implementation workflow guide
    ├── review.md       # Code review checklist
    ├── task.md         # Task management workflow
    ├── debug.md        # Debugging guide
    └── pr.md           # Pull request workflow
```

## Files

### settings.json

Project-level configuration including:
- Code style preferences (Zig, formatting)
- Testing configuration and targets
- Git workflow conventions (branch naming, commits)
- Quality gates (Tiger Style requirements)
- Issue tracking integration

### commands/

Specialized prompts for different workflows:

| File | Purpose |
|------|---------|
| `implement.md` | Guide for implementing features with Tiger Style |
| `review.md` | Code review checklist for Tiger Style compliance |
| `task.md` | GitHub issue-based task management workflow |
| `debug.md` | Debugging techniques for Z6 codebase |
| `pr.md` | Pull request creation and management |

## Usage

These files provide context for Claude Code when working on Z6. The main `CLAUDE.md` in the project root contains the consolidated rules and is the primary reference.

## Related Files

- `/CLAUDE.md` - Main project configuration for Claude Code
- `/.windsurf/rules/` - Original Windsurf rules (preserved for reference)
- `/.github/PULL_REQUEST_TEMPLATE.md` - PR template
- `/.github/BRANCH_PROTECTION.md` - Branch protection strategy

## Tiger Style Quick Reference

1. **Minimum 2 assertions per function**
2. **All loops must be bounded**
3. **No silent error handling (`catch {}`)**
4. **Explicit memory management**
5. **Test before implement (TDD)**
6. **Zero technical debt**

## Version

Created: January 2025
Compatible with: Claude Code CLI
