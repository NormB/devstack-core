#!/bin/bash
# Sync wiki directory to GitHub Wiki
#
# Usage:
#   ./scripts/sync-wiki.sh                    # Sync with default message
#   ./scripts/sync-wiki.sh "custom message"   # Sync with custom message

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WIKI_DIR="$PROJECT_ROOT/wiki"
WIKI_REPO="https://github.com/NormB/devstack-core.wiki.git"
TEMP_DIR=$(mktemp -d)

# Cleanup on exit
trap 'rm -rf "$TEMP_DIR"' EXIT

echo -e "${BLUE}📝 Syncing wiki to GitHub...${NC}\n"

# Validate wiki directory exists
if [ ! -d "$WIKI_DIR" ]; then
  echo -e "${RED}❌ Error: Wiki directory not found at $WIKI_DIR${NC}"
  exit 1
fi

# Count local wiki files
LOCAL_COUNT=$(find "$WIKI_DIR" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
echo -e "${BLUE}📊 Found $LOCAL_COUNT wiki files locally${NC}"

if [ "$LOCAL_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}⚠️  Warning: No .md files found in wiki directory${NC}"
  exit 1
fi

# Clone wiki repo
echo -e "${BLUE}1/5 Cloning wiki repository...${NC}"
if ! git clone "$WIKI_REPO" "$TEMP_DIR" --depth 1 --quiet; then
  echo -e "${RED}❌ Error: Failed to clone wiki repository${NC}"
  echo -e "${YELLOW}💡 Make sure the wiki is initialized on GitHub${NC}"
  echo -e "${YELLOW}   Visit: https://github.com/NormB/devstack-core/wiki${NC}"
  exit 1
fi

# Copy files
echo -e "${BLUE}2/5 Copying wiki files...${NC}"
cp -r "$WIKI_DIR"/*.md "$TEMP_DIR/" 2> /dev/null || true

# Count copied files
COPIED_COUNT=$(find "$TEMP_DIR" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
echo -e "${GREEN}   ✅ Copied $COPIED_COUNT files${NC}"

# Change to temp directory
cd "$TEMP_DIR"

# Check for changes
echo -e "${BLUE}3/5 Checking for changes...${NC}"
git add .

if git diff --quiet HEAD; then
  echo -e "${YELLOW}ℹ️  No changes to sync - wiki is already up to date${NC}"
  exit 0
fi

# Show changes summary
ADDED=$(git diff --cached --numstat | awk '{sum+=$1} END {print sum+0}')
DELETED=$(git diff --cached --numstat | awk '{sum+=$2} END {print sum+0}')
FILES=$(git diff --cached --name-only | wc -l | tr -d ' ')

echo -e "${GREEN}   📝 Changes detected:${NC}"
echo -e "${GREEN}      Files modified: $FILES${NC}"
echo -e "${GREEN}      Lines added:    +$ADDED${NC}"
echo -e "${GREEN}      Lines deleted:  -$DELETED${NC}"
echo ""

# Show changed files
echo -e "${BLUE}   Changed files:${NC}"
git diff --cached --name-only | sed 's/^/      - /'
echo ""

# Commit changes
COMMIT_MSG="${1:-docs: sync wiki updates}"
echo -e "${BLUE}4/5 Committing changes...${NC}"
echo -e "${BLUE}   Message: \"$COMMIT_MSG\"${NC}"

git config user.name "Wiki Sync Script"
git config user.email "wiki-sync@devstack-core"
git commit -m "$COMMIT_MSG" --quiet

# Push to GitHub
echo -e "${BLUE}5/5 Pushing to GitHub Wiki...${NC}"
if git push origin master --quiet; then
  echo ""
  echo -e "${GREEN}✅ Wiki synced successfully!${NC}"
  echo -e "${GREEN}   View at: https://github.com/NormB/devstack-core/wiki${NC}"
else
  echo -e "${RED}❌ Error: Failed to push to GitHub${NC}"
  echo -e "${YELLOW}💡 Check your network connection and GitHub credentials${NC}"
  exit 1
fi

# Verification
echo ""
echo -e "${BLUE}📊 Sync Summary:${NC}"
echo -e "   Local files:  $LOCAL_COUNT"
echo -e "   Synced files: $COPIED_COUNT"
echo -e "   Files changed: $FILES"
echo -e "   Lines changed: +$ADDED / -$DELETED"
echo ""
echo -e "${GREEN}✨ Sync complete!${NC}"
