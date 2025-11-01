#!/bin/bash
#
# Create GitHub Repository for Z6
#
# This script:
# - Creates public GitHub repository
# - Sets repository description and topics
# - Configures branch protection
# - Prepares for issue generation

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🐅 Z6 GitHub Repository Setup"
echo "=============================="
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) not found${NC}"
    echo "Install from: https://cli.github.com/"
    exit 1
fi

# Check if authenticated
if ! gh auth status &> /dev/null; then
    echo -e "${RED}Error: Not authenticated with GitHub${NC}"
    echo "Run: gh auth login"
    exit 1
fi

# Get username
USERNAME=$(gh api user -q .login)
echo -e "${BLUE}GitHub username: $USERNAME${NC}"
echo ""

# Repository details
REPO_NAME="z6"
DESCRIPTION="Deterministic load testing tool built with Tiger Style philosophy — precision, correctness, and auditability over convenience"
HOMEPAGE="https://github.com/$USERNAME/z6"

# Confirm creation
echo "Repository details:"
echo "  Name: $REPO_NAME"
echo "  Owner: $USERNAME"
echo "  Visibility: public"
echo "  Description: $DESCRIPTION"
echo ""

read -p "Create repository? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Aborted"
    exit 0
fi

echo ""
echo "→ Creating repository..."

# Create repository
gh repo create "$USERNAME/$REPO_NAME" \
    --public \
    --description "$DESCRIPTION" \
    --homepage "$HOMEPAGE" \
    --disable-wiki \
    --disable-issues=false \
    --gitignore="" \
    --license=""

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Repository created${NC}"
else
    echo -e "${RED}✗ Failed to create repository${NC}"
    exit 1
fi

echo ""
echo "→ Setting repository topics..."

# Set topics (tags)
gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/$USERNAME/$REPO_NAME/topics" \
    -f names='["load-testing","performance-testing","zig","tigerbeetle","deterministic","tiger-style","http2","benchmarking","testing-tools","systems-programming"]'

echo -e "${GREEN}✓ Topics set${NC}"

echo ""
echo "→ Updating repository settings..."

# Enable vulnerability alerts
gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/$USERNAME/$REPO_NAME/vulnerability-alerts"

# Set default branch to main
gh api \
    --method PATCH \
    -H "Accept: application/vnd.github+json" \
    "/repos/$USERNAME/$REPO_NAME" \
    -f default_branch='main'

# Enable discussions
gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/$USERNAME/$REPO_NAME/discussions"

echo -e "${GREEN}✓ Settings updated${NC}"

echo ""
echo "→ Configuring Git remote..."

# Add remote if not exists
if ! git remote get-url origin &> /dev/null; then
    git remote add origin "https://github.com/$USERNAME/$REPO_NAME.git"
    echo -e "${GREEN}✓ Remote added${NC}"
else
    echo -e "${YELLOW}⚠ Remote already exists, updating...${NC}"
    git remote set-url origin "https://github.com/$USERNAME/$REPO_NAME.git"
    echo -e "${GREEN}✓ Remote updated${NC}"
fi

echo ""
echo "→ Updating README badge URLs..."

# Update README.md with correct username
sed -i "s|yourusername|$USERNAME|g" README.md

echo -e "${GREEN}✓ README updated${NC}"

echo ""
echo "=============================="
echo -e "${GREEN}✓ Repository setup complete${NC}"
echo ""
echo "Repository URL: https://github.com/$USERNAME/$REPO_NAME"
echo ""
echo "Next steps:"
echo "  1. Review and commit changes:"
echo "     git add ."
echo "     git commit -m \"Initial commit: Z6 documentation and roadmap\""
echo ""
echo "  2. Push to GitHub:"
echo "     git branch -M main"
echo "     git push -u origin main"
echo ""
echo "  3. Configure branch protection (after first push):"
echo "     ./scripts/setup-branch-protection.sh"
echo ""
echo "  4. Generate GitHub issues:"
echo "     python3 scripts/generate-issues.py --create --filter \"TASK-0\""
echo ""
echo "🐅 Tiger Style repository ready!"
