#!/bin/bash
# Mirror the core documentation files into wiki/.
#
# The wiki/ directory holds verbatim copies of a fixed set of files from
# docs/, README.md and .github/CHANGELOG.md. This script is the one place
# that set is defined: it copies the files, and with --check it verifies
# the copies without touching anything. CI runs the check; a developer who
# changes a source file runs the copy before committing.
#
# Usage:
#   ./scripts/wiki-mirror.sh           # copy every source over its wiki copy
#   ./scripts/wiki-mirror.sh --check   # exit 1 if any copy is out of date
#
# Exit codes:
#   0 - copies made, or (--check) every copy is current
#   1 - (--check) at least one copy is out of date or a source is missing
#   2 - bad usage

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# source path => wiki page, one pair per line
MIRROR_MAP="
docs/README.md              wiki/Documentation-Index.md
docs/ARCHITECTURE.md        wiki/Architecture-Overview.md
docs/INSTALLATION.md        wiki/Installation-Guide.md
docs/USAGE.md               wiki/Usage-Guide.md
docs/TROUBLESHOOTING.md     wiki/Troubleshooting-Guide.md
docs/PERFORMANCE_TUNING.md  wiki/Performance-Tuning.md
docs/DISASTER_RECOVERY.md   wiki/Disaster-Recovery.md
docs/VAULT_SECURITY.md      wiki/Vault-Security.md
docs/SECURITY_ASSESSMENT.md wiki/Security-Assessment.md
docs/TESTING_APPROACH.md    wiki/Testing-Approach.md
docs/SERVICE_CATALOG.md     wiki/Service-Catalog.md
docs/SERVICE_PROFILES.md    wiki/Service-Profiles.md
docs/UPGRADE_GUIDE.md       wiki/Upgrade-Guide.md
docs/ROLLBACK_PROCEDURES.md wiki/Rollback-Procedures.md
README.md                   wiki/Home.md
.github/CHANGELOG.md        wiki/Changelog.md
"

mode="copy"
case "${1:-}" in
    "") ;;
    --check) mode="check" ;;
    *)
        echo "Usage: $0 [--check]" >&2
        exit 2
        ;;
esac

cd "$PROJECT_ROOT"

stale=0
missing=0
copied=0
current=0

while read -r src dest; do
    [ -n "$src" ] || continue

    if [ ! -f "$src" ]; then
        echo "missing source: $src"
        missing=$((missing + 1))
        continue
    fi

    if cmp -s "$src" "$dest" 2>/dev/null; then
        current=$((current + 1))
        continue
    fi

    if [ "$mode" = "check" ]; then
        echo "out of date: $dest (source: $src)"
        stale=$((stale + 1))
    else
        cp "$src" "$dest"
        echo "copied: $src -> $dest"
        copied=$((copied + 1))
    fi
done <<< "$MIRROR_MAP"

if [ "$mode" = "check" ]; then
    if [ "$stale" -eq 0 ] && [ "$missing" -eq 0 ]; then
        echo "wiki mirror is current ($current files)"
        exit 0
    fi
    echo "wiki mirror check failed: $stale out of date, $missing missing"
    echo "Run ./scripts/wiki-mirror.sh and commit the wiki/ changes."
    exit 1
fi

echo "wiki mirror: $copied copied, $current already current, $missing missing"
[ "$missing" -eq 0 ]
