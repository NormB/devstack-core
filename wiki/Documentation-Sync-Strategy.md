# Documentation Sync Strategy

Guide for keeping the wiki directory and GitHub Wiki in sync.

## Table of Contents

- [Overview](#overview)
- [Documentation Architecture](#documentation-architecture)
- [Sync Workflow](#sync-workflow)
  - [Method 1: Manual Sync (Current)](#method-1-manual-sync-current)
  - [Method 2: Automated Sync with GitHub Actions](#method-2-automated-sync-with-github-actions)
  - [Method 3: Git Submodule Approach](#method-3-git-submodule-approach)
  - [Method 4: Pre-Commit Hook](#method-4-pre-commit-hook)
- [Recommended Approach](#recommended-approach)
- [Sync Script](#sync-script)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Overview

The DevStack Core documentation exists in two places:

1. **Local wiki directory**: `/Users/gator/devstack-core/wiki/` (tracked in main repo)
2. **GitHub Wiki**: `https://github.com/NormB/devstack-core.wiki.git` (separate git repo)

**Why two locations?**
- **Local directory** allows version control with main codebase, easy editing
- **GitHub Wiki** provides easy web access, searchability, navigation sidebar

**The Challenge**: Keeping both in sync when changes are made.

---

## Documentation Architecture

```
devstack-core/                    # Main repository
├── wiki/                           # Local wiki directory (source of truth)
│   ├── Home.md
│   ├── Installation.md
│   └── ... (55 files)
└── .github/
    └── workflows/
        └── sync-wiki.yml           # Automation (optional)

devstack-core.wiki/               # Separate GitHub Wiki repository
├── Home.md
├── Installation.md
└── ... (same 55 files)
```

**Design Decision**: The `wiki/` directory in the main repo should be the **source of truth**.

---

## Sync Workflow

### Method 1: Manual Sync (Current)

**Best for**: Infrequent wiki updates, full control over what gets synced

**Process:**

```bash
# 1. Make changes in local wiki directory
cd ~/devstack-core/wiki
nano Installation.md  # Edit files

# 2. Clone GitHub Wiki
cd /tmp
git clone https://github.com/NormB/devstack-core.wiki.git

# 3. Copy updated files
cp ~/devstack-core/wiki/*.md /tmp/devstack-core.wiki/

# 4. Commit and push to wiki
cd /tmp/devstack-core.wiki
git add .
git commit -m "docs: sync wiki updates"
git push origin master

# 5. Cleanup
cd ~
rm -rf /tmp/devstack-core.wiki

# 6. Commit changes to main repo
cd ~/devstack-core
git add wiki/
git commit -m "docs: update wiki documentation"
git push origin main
```

**Pros:**
- ✅ Full control over sync timing
- ✅ Can review changes before syncing
- ✅ Simple, no automation to maintain

**Cons:**
- ❌ Manual process, easy to forget
- ❌ Can get out of sync
- ❌ Requires two commits (main repo + wiki)

---

### Method 2: Automated Sync with GitHub Actions

**Best for**: Frequent wiki updates, automated workflow

**Setup:**

Create `.github/workflows/sync-wiki.yml`:

```yaml
name: Sync Wiki

on:
  push:
    branches: [main]
    paths:
      - 'wiki/**'

jobs:
  sync-wiki:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout main repo
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Clone wiki repo
        run: |
          git clone https://github.com/${{ github.repository }}.wiki.git wiki-repo

      - name: Copy wiki files
        run: |
          cp -r wiki/* wiki-repo/

      - name: Commit and push to wiki
        run: |
          cd wiki-repo
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add .
          git diff --quiet && git diff --staged --quiet || \
            (git commit -m "docs: sync from main repo (${{ github.sha }})" && \
             git push origin master)
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Enable:**

```bash
# 1. Create workflow file
mkdir -p .github/workflows
cat > .github/workflows/sync-wiki.yml << 'EOF'
# (paste YAML above)
EOF

# 2. Commit and push
git add .github/workflows/sync-wiki.yml
git commit -m "ci: add wiki sync workflow"
git push origin main
```

**Usage:**

```bash
# 1. Edit wiki files
nano wiki/Installation.md

# 2. Commit to main repo
git add wiki/
git commit -m "docs: update installation guide"
git push origin main

# 3. GitHub Action automatically syncs to wiki! ✅
```

**Pros:**
- ✅ Fully automated
- ✅ Always in sync
- ✅ No manual intervention needed
- ✅ Single commit workflow

**Cons:**
- ❌ Requires GitHub Actions
- ❌ Slightly delayed sync (action takes ~30 seconds)
- ❌ Needs proper permissions setup

---

### Method 3: Git Submodule Approach

**Best for**: Advanced users, direct wiki editing

**Setup:**

```bash
# 1. Remove local wiki directory
cd ~/devstack-core
rm -rf wiki/

# 2. Add wiki as submodule
git submodule add https://github.com/NormB/devstack-core.wiki.git wiki

# 3. Initialize submodule
git submodule update --init --recursive

# 4. Commit submodule
git add .gitmodules wiki/
git commit -m "docs: add wiki as submodule"
git push origin main
```

**Usage:**

```bash
# 1. Enter wiki directory (submodule)
cd ~/devstack-core/wiki

# 2. Make changes
nano Installation.md

# 3. Commit to wiki repo
git add Installation.md
git commit -m "docs: update installation guide"
git push origin master

# 4. Update main repo to reference new commit
cd ~/devstack-core
git add wiki/
git commit -m "docs: update wiki submodule reference"
git push origin main
```

**Pros:**
- ✅ Direct connection between repos
- ✅ Single source of truth
- ✅ Git tracks the connection

**Cons:**
- ❌ Submodules can be confusing
- ❌ Two-step commit process
- ❌ Clone complexity for contributors

---

### Method 4: Pre-Commit Hook

**Best for**: Ensuring sync on every commit

**Setup:**

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash
# Pre-commit hook to sync wiki

# Check if wiki files changed
if git diff --cached --name-only | grep -q '^wiki/'; then
    echo "📝 Wiki files changed, syncing to GitHub Wiki..."

    # Clone wiki repo
    WIKI_TEMP=$(mktemp -d)
    git clone https://github.com/NormB/devstack-core.wiki.git "$WIKI_TEMP" 2>/dev/null

    # Copy wiki files
    cp -r wiki/* "$WIKI_TEMP/"

    # Commit and push
    cd "$WIKI_TEMP"
    git add .
    if ! git diff --quiet HEAD; then
        git commit -m "docs: sync from main repo"
        git push origin master
        echo "✅ Wiki synced successfully!"
    else
        echo "ℹ️  No wiki changes to sync"
    fi

    # Cleanup
    rm -rf "$WIKI_TEMP"
fi

exit 0
```

**Enable:**

```bash
# Make hook executable
chmod +x .git/hooks/pre-commit
```

**Pros:**
- ✅ Automatic sync on commit
- ✅ No CI/CD dependency
- ✅ Immediate feedback

**Cons:**
- ❌ Slows down commit process
- ❌ Requires internet during commit
- ❌ Not shared with team (hooks aren't versioned)

---

## Recommended Approach

**For this project, I recommend Method 2 (GitHub Actions) for these reasons:**

1. **Automation** - No manual steps to forget
2. **Simplicity** - Single commit to main repo
3. **Reliability** - Actions run in consistent environment
4. **Visibility** - See sync status in Actions tab
5. **Team-friendly** - Works for all contributors

**Alternative for local-only**: Use the sync script below.

---

## Sync Script

Create `scripts/sync-wiki.sh`:

```bash
#!/bin/bash
# Sync wiki directory to GitHub Wiki

set -e

WIKI_DIR="$HOME/devstack-core/wiki"
WIKI_REPO="https://github.com/NormB/devstack-core.wiki.git"
TEMP_DIR=$(mktemp -d)

echo "📝 Syncing wiki to GitHub..."

# Clone wiki repo
echo "1/4 Cloning wiki repo..."
git clone "$WIKI_REPO" "$TEMP_DIR" --depth 1 --quiet

# Copy files
echo "2/4 Copying wiki files..."
cp -r "$WIKI_DIR"/*.md "$TEMP_DIR/"

# Commit and push
echo "3/4 Committing changes..."
cd "$TEMP_DIR"
git add .

if git diff --quiet HEAD; then
    echo "ℹ️  No changes to sync"
else
    COMMIT_MSG="${1:-docs: sync wiki updates}"
    git commit -m "$COMMIT_MSG"

    echo "4/4 Pushing to GitHub..."
    git push origin master

    echo "✅ Wiki synced successfully!"
fi

# Cleanup
rm -rf "$TEMP_DIR"
```

**Usage:**

```bash
# Make executable
chmod +x scripts/sync-wiki.sh

# Sync with default message
./scripts/sync-wiki.sh

# Sync with custom message
./scripts/sync-wiki.sh "docs: add new troubleshooting guide"
```

**Add to your workflow:**

```bash
# After making wiki changes
nano wiki/Installation.md

# Commit to main repo
git add wiki/
git commit -m "docs: update installation guide"

# Sync to wiki
./scripts/sync-wiki.sh "docs: update installation guide"

# Push to main repo
git push origin main
```

---

## Verification

**Check sync status:**

```bash
# 1. Check local wiki files
ls -l ~/devstack-core/wiki/*.md | wc -l

# 2. Clone and check GitHub Wiki
git clone https://github.com/NormB/devstack-core.wiki.git /tmp/wiki-check
ls -l /tmp/wiki-check/*.md | wc -l

# 3. Compare counts (should match)
diff <(ls ~/devstack-core/wiki/*.md | xargs -n1 basename | sort) \
     <(ls /tmp/wiki-check/*.md | xargs -n1 basename | sort)

# 4. Cleanup
rm -rf /tmp/wiki-check
```

**Verify specific file:**

```bash
# Compare local vs GitHub Wiki
WIKI_FILE="Installation.md"

# Get local file hash
LOCAL_HASH=$(md5 -q ~/devstack-core/wiki/$WIKI_FILE)

# Get GitHub Wiki file hash
git clone https://github.com/NormB/devstack-core.wiki.git /tmp/wiki-verify
WIKI_HASH=$(md5 -q /tmp/wiki-verify/$WIKI_FILE)

if [ "$LOCAL_HASH" = "$WIKI_HASH" ]; then
    echo "✅ $WIKI_FILE is in sync"
else
    echo "❌ $WIKI_FILE is out of sync"
fi

rm -rf /tmp/wiki-verify
```

---

## Troubleshooting

### Wiki is out of sync

```bash
# Option 1: Sync script (recommended)
./scripts/sync-wiki.sh

# Option 2: Manual sync
git clone https://github.com/NormB/devstack-core.wiki.git /tmp/wiki-fix
cp ~/devstack-core/wiki/*.md /tmp/wiki-fix/
cd /tmp/wiki-fix
git add .
git commit -m "docs: fix wiki sync"
git push origin master
rm -rf /tmp/wiki-fix
```

### Merge conflicts in wiki

```bash
# Clone wiki
git clone https://github.com/NormB/devstack-core.wiki.git /tmp/wiki-conflict

# Manual merge
cd /tmp/wiki-conflict
# Edit conflicting files
nano Installation.md

# Commit resolution
git add .
git commit -m "docs: resolve wiki merge conflict"
git push origin master

# Update local copy
cp /tmp/wiki-conflict/Installation.md ~/devstack-core/wiki/

# Commit to main repo
cd ~/devstack-core
git add wiki/Installation.md
git commit -m "docs: sync wiki conflict resolution"
git push origin main

rm -rf /tmp/wiki-conflict
```

### GitHub Actions failing

```bash
# Check Actions tab on GitHub
# Common issues:

# 1. Permissions error
# Solution: Add GITHUB_TOKEN with write access to wiki

# 2. Wiki not initialized
# Solution: Create at least one page manually on GitHub Wiki

# 3. Workflow syntax error
# Solution: Use https://www.yamllint.com/ to validate YAML
```

---

## Best Practices

### 1. Establish Source of Truth

**Decision**: `wiki/` directory in main repo is the source of truth.

```bash
# ✅ CORRECT: Edit local, sync to GitHub
nano ~/devstack-core/wiki/Installation.md
./scripts/sync-wiki.sh
git add wiki/ && git commit -m "docs: update"

# ❌ WRONG: Edit on GitHub Wiki directly
# (will be overwritten on next sync)
```

### 2. Sync Frequency

**Recommendation**: Sync after every wiki change

```bash
# Good workflow
nano wiki/FAQ.md          # 1. Edit
git add wiki/             # 2. Stage
git commit -m "docs: ..."  # 3. Commit
./scripts/sync-wiki.sh    # 4. Sync to wiki
git push origin main       # 5. Push to main
```

### 3. Commit Message Convention

**Use consistent commit messages:**

```bash
# Good commit messages
git commit -m "docs: add troubleshooting guide"
git commit -m "docs: update installation steps"
git commit -m "docs: fix broken links in FAQ"

# Avoid vague messages
git commit -m "update docs"  # ❌ Too vague
git commit -m "wiki"         # ❌ Not descriptive
```

### 4. Review Before Sync

**Always review changes before syncing:**

```bash
# Check what changed
git diff wiki/

# Review staged changes
git diff --cached wiki/

# Then sync
./scripts/sync-wiki.sh
```

### 5. Backup Strategy

**GitHub Wiki has its own git history:**

```bash
# Clone wiki repo for backup
git clone https://github.com/NormB/devstack-core.wiki.git ~/wiki-backup

# Create backup archive
tar czf wiki-backup-$(date +%Y%m%d).tar.gz ~/wiki-backup

# Store offsite (Google Drive, Dropbox, etc.)
```

### 6. Team Coordination

**If multiple people edit wiki:**

1. **Communicate** - Let team know you're editing
2. **Pull first** - Always pull latest changes before editing
3. **Sync promptly** - Don't let local changes sit unsynced
4. **Use branches** - For major wiki overhauls, use feature branches

```bash
# Team member workflow
git checkout -b wiki-overhaul
# Edit wiki files
git add wiki/
git commit -m "docs: major wiki restructure"
git push origin wiki-overhaul
# Create PR for review
```

---

## Summary

### Quick Reference

**Manual Sync:**
```bash
./scripts/sync-wiki.sh
```

**Automated Sync:**
```bash
# Setup once
Enable GitHub Actions workflow

# Then just commit
git add wiki/ && git commit -m "docs: update"
git push  # Automatically syncs!
```

**Verify Sync:**
```bash
diff <(ls ~/devstack-core/wiki/*.md | xargs -n1 basename | sort) \
     <(git clone --quiet https://github.com/NormB/devstack-core.wiki.git /tmp/w && ls /tmp/w/*.md | xargs -n1 basename | sort)
```

### Recommended Setup

For DevStack Core:

1. ✅ Keep `wiki/` directory in main repo as source of truth
2. ✅ Use `scripts/sync-wiki.sh` for manual syncs
3. ✅ Consider adding GitHub Actions for automation
4. ✅ Sync after every wiki commit
5. ✅ Never edit directly on GitHub Wiki

---

## Related Pages

- [Contributing-Guide](Contributing-Guide) - Contributing to documentation
- [Development-Workflow](Development-Workflow) - Daily development workflow
- [CI-CD-Integration](CI-CD-Integration) - GitHub Actions automation

---

**Questions?** Open an issue at [devstack-core/issues](https://github.com/NormB/devstack-core/issues)
