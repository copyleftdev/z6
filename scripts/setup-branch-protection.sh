#!/bin/bash
#
# Configure Branch Protection for Z6
#
# Run this AFTER initial push to main branch

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "🐅 Z6 Branch Protection Setup"
echo "============================="
echo ""

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo -e "${RED}Error: GitHub CLI (gh) not found${NC}"
    exit 1
fi

# Get repository info
USERNAME=$(gh api user -q .login)
REPO_NAME="z6"
REPO="$USERNAME/$REPO_NAME"

echo -e "${BLUE}Repository: $REPO${NC}"
echo ""

# Check if main branch exists
if ! gh api "repos/$REPO/branches/main" &> /dev/null; then
    echo -e "${RED}Error: main branch not found${NC}"
    echo "Push to main branch first:"
    echo "  git push -u origin main"
    exit 1
fi

echo "→ Configuring branch protection for 'main'..."

# Apply branch protection rules
gh api \
    --method PUT \
    -H "Accept: application/vnd.github+json" \
    "/repos/$REPO/branches/main/protection" \
    -f required_status_checks[strict]=true \
    -f required_status_checks[contexts][]='verify-local-validation' \
    -f required_pull_request_reviews[dismiss_stale_reviews]=true \
    -f required_pull_request_reviews[require_code_owner_reviews]=false \
    -f required_pull_request_reviews[required_approving_review_count]=1 \
    -f required_conversation_resolution[enabled]=true \
    -f enforce_admins=true \
    -f required_linear_history=true \
    -f allow_force_pushes=false \
    -f allow_deletions=false

echo -e "${GREEN}✓ Branch protection configured${NC}"

echo ""
echo "→ Configuring merge options..."

# Configure merge settings
gh api \
    --method PATCH \
    -H "Accept: application/vnd.github+json" \
    "/repos/$REPO" \
    -f allow_squash_merge=true \
    -f allow_merge_commit=false \
    -f allow_rebase_merge=false \
    -f delete_branch_on_merge=true \
    -f allow_auto_merge=false

echo -e "${GREEN}✓ Merge options configured${NC}"

echo ""
echo "=============================="
echo -e "${GREEN}✓ Branch protection complete${NC}"
echo ""
echo "Main branch protection rules:"
echo "  • Require pull request reviews (1 approval)"
echo "  • Dismiss stale reviews"
echo "  • Require conversation resolution"
echo "  • Require status check: verify-local-validation"
echo "  • Require linear history"
echo "  • No force pushes"
echo "  • Squash merge only"
echo ""
echo "See .github/BRANCH_PROTECTION.md for full philosophy"
