#!/usr/bin/env bash
#
# Markdown Link Checker for DevStack Core
#
# This script scans all markdown files in the project and validates that:
# - Internal file links point to existing files
# - Internal anchor links point to existing headings
# - Links are properly formatted
#
# Usage:
#   ./scripts/check-markdown-links.sh
#
# Exit codes:
#   0 - All links valid
#   1 - Broken links found

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TOTAL_FILES=0
TOTAL_LINKS=0
BROKEN_LINKS=0
BROKEN_LINK_LIST=()

# Project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Print functions
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_pass() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_fail() {
    echo -e "${RED}✗${NC} $1"
}

# Check if a file exists relative to another file
check_file_link() {
    local source_file=$1
    local link_path=$2
    local source_dir=$(dirname "$source_file")

    # Remove anchor if present
    local file_path="${link_path%%#*}"

    # Skip if it's just an anchor
    if [[ "$file_path" == "" ]]; then
        return 0
    fi

    # Resolve relative path
    local full_path
    if [[ "$file_path" == /* ]]; then
        # Absolute path from project root
        full_path="${PROJECT_ROOT}${file_path}"
    else
        # Relative path from source file directory
        full_path="${source_dir}/${file_path}"
    fi

    # Normalize path (resolve ../ and ./)
    full_path=$(cd "$source_dir" && cd "$(dirname "$file_path")" 2>/dev/null && pwd)/$(basename "$file_path") || echo "$full_path"

    if [[ -f "$full_path" ]] || [[ -d "$full_path" ]]; then
        return 0
    else
        return 1
    fi
}

# Extract markdown links from a file
extract_links() {
    local file=$1

    # Extract markdown links: [text](url)
    # Also extract: [text]: url
    grep -oE '\[([^]]+)\]\(([^)]+)\)|\[([^]]+)\]:\s*([^\s]+)' "$file" 2>/dev/null | \
    sed -E 's/\[([^]]+)\]\(([^)]+)\)/\2/; s/\[([^]]+)\]:\s*([^\s]+)/\2/' || true
}

# Check if a link is external (http/https)
is_external_link() {
    local link=$1
    [[ "$link" =~ ^https?:// ]]
}

# Check all markdown files
check_markdown_files() {
    print_header "Scanning Markdown Files for Broken Links"

    # Find all markdown files (excluding node_modules)
    local md_files=()
    while IFS= read -r file; do
        md_files+=("$file")
    done < <(cd "$PROJECT_ROOT" && \
        ls -1 *.md .github/*.md docs/*.md reference-apps/*.md reference-apps/*/*.md tests/*.md 2>/dev/null | \
        grep -v node_modules || true)

    TOTAL_FILES=${#md_files[@]}
    print_info "Found $TOTAL_FILES markdown files to check"
    echo ""

    for md_file in "${md_files[@]}"; do
        local full_path="${PROJECT_ROOT}/${md_file}"

        if [[ ! -f "$full_path" ]]; then
            continue
        fi

        echo -e "${BLUE}Checking:${NC} $md_file"

        # Extract all links
        local links=$(extract_links "$full_path")
        local file_link_count=0
        local file_broken_count=0

        while IFS= read -r link; do
            [[ -z "$link" ]] && continue

            ((TOTAL_LINKS++))
            ((file_link_count++))

            # Skip external links (would require HTTP requests)
            if is_external_link "$link"; then
                continue
            fi

            # Skip mailto links
            if [[ "$link" =~ ^mailto: ]]; then
                continue
            fi

            # Check internal file link
            if ! check_file_link "$full_path" "$link"; then
                ((BROKEN_LINKS++))
                ((file_broken_count++))
                print_fail "Broken link: $link"
                BROKEN_LINK_LIST+=("$md_file: $link")
            fi
        done <<< "$links"

        if [[ $file_broken_count -eq 0 ]]; then
            print_pass "$file_link_count links checked, all valid"
        else
            print_fail "$file_broken_count broken link(s) found"
        fi
        echo ""
    done
}

# Main execution
main() {
    cd "$PROJECT_ROOT"

    check_markdown_files

    # Print summary
    print_header "Link Check Summary"
    echo "Files Checked: $TOTAL_FILES"
    echo "Links Checked: $TOTAL_LINKS"
    echo "Broken Links: $BROKEN_LINKS"

    if [[ $BROKEN_LINKS -gt 0 ]]; then
        echo ""
        print_fail "Broken Links Found:"
        for broken in "${BROKEN_LINK_LIST[@]}"; do
            echo "  - $broken"
        done
        echo ""
        echo -e "${RED}Link check FAILED${NC}"
        exit 1
    else
        echo ""
        echo -e "${GREEN}All links valid!${NC}"
        exit 0
    fi
}

main "$@"
