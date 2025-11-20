#!/usr/bin/env bash
#
# Generate detailed synchronization report for API implementations.
#
# This script creates a comprehensive comparison report showing differences
# between code-first and API-first implementations.
#
# Usage:
#     ./scripts/sync-report.sh [output_file]
#
# Arguments:
#     output_file: Optional output file (default: stdout)
#
# Environment Variables:
#     CODE_FIRST_URL: Code-first API URL (default: http://localhost:8000)
#     API_FIRST_URL: API-first API URL (default: http://localhost:8001)
#     SHARED_SPEC: Path to shared spec (default: reference-apps/shared/openapi.yaml)
#
# Returns:
#     0: Report generated successfully
#     1: Error generating report
#
# Examples:
#     # Print report to stdout
#     ./scripts/sync-report.sh
#
#     # Save report to file
#     ./scripts/sync-report.sh sync-report.txt
#
# Author:
#     Development Team
#
# Date:
#     2025-10-27
#

set -e
set -u
set -o pipefail

# Script directory and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
readonly CODE_FIRST_URL="${CODE_FIRST_URL:-http://localhost:8000}"
readonly API_FIRST_URL="${API_FIRST_URL:-http://localhost:8001}"
readonly SHARED_SPEC="${SHARED_SPEC:-${PROJECT_ROOT}/reference-apps/shared/openapi.yaml}"
readonly OUTPUT_FILE="${1:-/dev/stdout}"

# Temporary directory
readonly TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

#######################################
# Generate synchronization report.
#
# Creates a detailed markdown report comparing implementations.
#
# Arguments:
#   None
#
# Returns:
#   0 - Report generated successfully
#
# Outputs:
#   Markdown report to OUTPUT_FILE
#######################################
generate_report() {
    local report_file="$OUTPUT_FILE"

    cat > "$report_file" << EOF
# API Synchronization Report

**Generated:** $(date '+%Y-%m-%d %H:%M:%S')
**Project:** DevStack Core Reference API

---

## Summary

This report compares the code-first and API-first implementations against
the shared OpenAPI specification to ensure synchronization.

### Implementations

| Implementation | URL | Status |
|---------------|-----|--------|
EOF

    # Check code-first
    if curl -sf "${CODE_FIRST_URL}/health" >/dev/null 2>&1; then
        echo "| Code-First | ${CODE_FIRST_URL} | ✅ Running |" >> "$report_file"
        extract_spec_for_report "$CODE_FIRST_URL" "code-first"
    else
        echo "| Code-First | ${CODE_FIRST_URL} | ❌ Not Running |" >> "$report_file"
    fi

    # Check API-first
    if curl -sf "${API_FIRST_URL}/health" >/dev/null 2>&1; then
        echo "| API-First | ${API_FIRST_URL} | ✅ Running |" >> "$report_file"
        extract_spec_for_report "$API_FIRST_URL" "api-first"
    else
        echo "| API-First | ${API_FIRST_URL} | ❌ Not Running |" >> "$report_file"
    fi

    echo "" >> "$report_file"

    # Shared spec info
    cat >> "$report_file" << EOF
### Shared OpenAPI Specification

- **Location:** ${SHARED_SPEC}
- **Exists:** $([ -f "$SHARED_SPEC" ] && echo "✅ Yes" || echo "❌ No")
EOF

    if [ -f "$SHARED_SPEC" ]; then
        local endpoints=$(yq eval '.paths | length' "$SHARED_SPEC" 2>/dev/null || echo "?")
        local schemas=$(yq eval '.components.schemas | length' "$SHARED_SPEC" 2>/dev/null || echo "?")
        cat >> "$report_file" << EOF
- **Endpoints:** ${endpoints}
- **Schemas:** ${schemas}
EOF
    fi

    cat >> "$report_file" << EOF

---

## Comparison Results

EOF

    # Compare implementations if both are running
    if [ -f "${TEMP_DIR}/code-first.yaml" ] && [ -f "${TEMP_DIR}/api-first.yaml" ]; then
        echo "### Code-First vs API-First" >> "$report_file"
        echo "" >> "$report_file"
        compare_for_report "${TEMP_DIR}/code-first.yaml" "${TEMP_DIR}/api-first.yaml" >> "$report_file"
    fi

    # Compare against shared spec
    if [ -f "$SHARED_SPEC" ]; then
        if [ -f "${TEMP_DIR}/code-first.yaml" ]; then
            echo "### Code-First vs Shared Spec" >> "$report_file"
            echo "" >> "$report_file"
            compare_for_report "${TEMP_DIR}/code-first.yaml" "$SHARED_SPEC" >> "$report_file"
        fi

        if [ -f "${TEMP_DIR}/api-first.yaml" ]; then
            echo "### API-First vs Shared Spec" >> "$report_file"
            echo "" >> "$report_file"
            compare_for_report "${TEMP_DIR}/api-first.yaml" "$SHARED_SPEC" >> "$report_file"
        fi
    fi

    cat >> "$report_file" << EOF

---

## Recommendations

EOF

    if [ -f "${TEMP_DIR}/diff.txt" ] && [ -s "${TEMP_DIR}/diff.txt" ]; then
        cat >> "$report_file" << EOF
⚠️ **Implementations are out of sync!**

### Steps to Fix:

1. **Review Differences** above to understand what changed
2. **Update Shared Spec** if code-first has the correct implementation:
   \`\`\`bash
   ./scripts/extract-openapi.sh
   # Manually update reference-apps/shared/openapi.yaml
   \`\`\`

3. **Regenerate API-First** from updated spec:
   \`\`\`bash
   make regenerate
   \`\`\`

4. **Validate** synchronization:
   \`\`\`bash
   make sync-check
   \`\`\`

### Workflow Decision Tree:

- **If code-first is correct:** Extract → Update shared spec → Regenerate API-first
- **If shared spec is correct:** Regenerate API-first → Update code-first manually
- **If API-first is correct:** Update shared spec → Update code-first manually

EOF
    else
        cat >> "$report_file" << EOF
✅ **All implementations are synchronized!**

No action required. Both implementations match the shared OpenAPI specification.

EOF
    fi

    cat >> "$report_file" << EOF

---

*Report generated by \`scripts/sync-report.sh\`*
EOF
}

#######################################
# Extract spec for report generation.
#
# Downloads and stores spec in temp directory for comparison.
#
# Arguments:
#   $1 - API URL
#   $2 - Implementation name
#
# Returns:
#   0 - Success
#######################################
extract_spec_for_report() {
    local url="$1"
    local name="$2"

    curl -sf "${url}/openapi.json" -o "${TEMP_DIR}/${name}.json" 2>/dev/null || return 1
    yq eval -P . "${TEMP_DIR}/${name}.json" > "${TEMP_DIR}/${name}.yaml" 2>/dev/null || return 1
}

#######################################
# Compare specs for report.
#
# Generates markdown comparison output.
#
# Arguments:
#   $1 - First spec file
#   $2 - Second spec file
#
# Returns:
#   None
#
# Outputs:
#   Markdown comparison to stdout
#######################################
compare_for_report() {
    local spec1="$1"
    local spec2="$2"

    # Normalize specs
    local norm1="${TEMP_DIR}/norm1.yaml"
    local norm2="${TEMP_DIR}/norm2.yaml"

    yq eval 'del(.servers) | del(.info.description) | walk(if type == "object" then del(.operationId) else . end)' \
        "$spec1" > "$norm1"
    yq eval 'del(.servers) | del(.info.description) | walk(if type == "object" then del(.operationId) else . end)' \
        "$spec2" > "$norm2"

    # Compare
    if diff -u "$norm1" "$norm2" > "${TEMP_DIR}/diff.txt" 2>&1; then
        echo "**Status:** ✅ Synchronized"
        echo ""
        echo "No differences found."
    else
        echo "**Status:** ❌ Out of Sync"
        echo ""
        echo "<details>"
        echo "<summary>Click to view differences</summary>"
        echo ""
        echo "\`\`\`diff"
        cat "${TEMP_DIR}/diff.txt"
        echo "\`\`\`"
        echo ""
        echo "</details>"
    fi
    echo ""
}

# Main execution
echo -e "${BLUE}[INFO]${NC} Generating synchronization report..."
generate_report
if [ "$OUTPUT_FILE" != "/dev/stdout" ]; then
    echo -e "${GREEN}[SUCCESS]${NC} Report saved to: $OUTPUT_FILE"
else
    echo ""
fi
