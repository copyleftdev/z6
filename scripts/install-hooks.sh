#!/bin/bash
#
# Install Git hooks for Z6
#
# This script installs the Tiger Style pre-commit hook that enforces:
# - Code formatting
# - Test execution
# - Assertion density
# - Bounded loops
# - Explicit error handling

set -e

HOOK_SOURCE="scripts/pre-commit"
HOOK_DEST=".git/hooks/pre-commit"

echo "🐅 Installing Tiger Style Pre-Commit Hook"
echo "========================================="
echo ""

# Check if .git directory exists
if [ ! -d ".git" ]; then
    echo "Error: .git directory not found"
    echo "Run this script from the repository root"
    exit 1
fi

# Check if hook source exists
if [ ! -f "$HOOK_SOURCE" ]; then
    echo "Error: $HOOK_SOURCE not found"
    exit 1
fi

# Backup existing hook if present
if [ -f "$HOOK_DEST" ]; then
    echo "→ Backing up existing hook to $HOOK_DEST.backup"
    cp "$HOOK_DEST" "$HOOK_DEST.backup"
fi

# Copy hook
echo "→ Installing pre-commit hook"
cp "$HOOK_SOURCE" "$HOOK_DEST"
chmod +x "$HOOK_DEST"

echo ""
echo "✓ Pre-commit hook installed successfully"
echo ""
echo "The hook will run on every commit and check:"
echo "  • Code formatting (zig fmt)"
echo "  • Assertion density (min 2 per function)"
echo "  • Bounded loops"
echo "  • Explicit error handling"
echo "  • Build success"
echo "  • All tests pass"
echo ""
echo "To test the hook:"
echo "  git add <files>"
echo "  git commit -m \"test\""
echo ""
echo "To bypass (NOT RECOMMENDED):"
echo "  git commit --no-verify"
echo ""
echo "🐅 Tiger Style enabled"
