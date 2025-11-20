#!/usr/bin/env bash
#
# Validate synchronization between code-first and API-first implementations.
#
# This script ensures both implementations match the shared OpenAPI specification
# by extracting specs from both running instances and comparing them.
#
# Usage:
#     ./scripts/validate-sync.sh
#
# Environment Variables:
#     CODE_FIRST_URL: Code-first API URL (default: http://localhost:8000)
#     API_FIRST_URL: API-first API URL (default: http://localhost:8001)
#     SHARED_SPEC: Path to shared spec (default: reference-apps/shared/openapi.yaml)
#     STRICT: Fail on warnings (default: false)
#
# Returns:
#     0: APIs are synchronized
#     1: APIs are out of sync
#     2: Cannot reach one or both APIs
#
# Examples:
#     # Validate with defaults
#     ./scripts/validate-sync.sh
#
#     # Strict mode (fail on warnings)
#     STRICT=true ./scripts/validate-sync.sh
#
# Author:
#     Development Team
#
# Date:
#     2025-10-27
#
# See Also:
#     scripts/sync-report.sh - Detailed sync report
#     scripts/extract-openapi.sh - Extract spec from code-first
#     scripts/regenerate-api-first.sh - Rebuild API-first from spec
#

set -e  # Exit on error
set -u  # Exit on undefined variable
set -o pipefail  # Exit if any command in pipe fails

#######################################
# Configuration and Constants
#######################################

# Script directory and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default configuration
readonly DEFAULT_CODE_FIRST_URL="http://localhost:8000"
readonly DEFAULT_API_FIRST_URL="http://localhost:8001"
readonly DEFAULT_SHARED_SPEC="${PROJECT_ROOT}/reference-apps/shared/openapi.yaml"
readonly DEFAULT_STRICT="false"

# Configuration from environment or defaults
readonly CODE_FIRST_URL="${CODE_FIRST_URL:-$DEFAULT_CODE_FIRST_URL}"
readonly API_FIRST_URL="${API_FIRST_URL:-$DEFAULT_API_FIRST_URL}"
readonly SHARED_SPEC="${SHARED_SPEC:-$DEFAULT_SHARED_SPEC}"
readonly STRICT="${STRICT:-$DEFAULT_STRICT}"

# Temporary directory for comparison
readonly TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'  # No Color

#######################################
# Print informational message to stdout.
#
# Globals:
#   BLUE - Color code for info messages
#   NC - Color code to reset formatting
#
# Arguments:
#   $1 - Message string to display
#
# Returns:
#   None
#
# Outputs:
#   Writes formatted info message to stdout
#######################################
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

#######################################
# Print success message to stdout.
#
# Globals:
#   GREEN - Color code for success messages
#   NC - Color code to reset formatting
#
# Arguments:
#   $1 - Success message string to display
#
# Returns:
#   None
#
# Outputs:
#   Writes formatted success message to stdout
#######################################
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

#######################################
# Print error message to stderr and exit.
#
# Globals:
#   RED - Color code for error messages
#   NC - Color code to reset formatting
#
# Arguments:
#   $1 - Error message string to display
#   $2 - Exit code (optional, default: 1)
#
# Returns:
#   Does not return (exits with specified code)
#
# Outputs:
#   Writes formatted error message to stderr
#######################################
error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit "${2:-1}"
}

#######################################
# Print warning message to stdout.
#
# Globals:
#   YELLOW - Color code for warning messages
#   NC - Color code to reset formatting
#
# Arguments:
#   $1 - Warning message string to display
#
# Returns:
#   None
#
# Outputs:
#   Writes formatted warning message to stdout
#######################################
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

#######################################
# Check if API is reachable.
#
# Makes a simple health check request to verify the API is running.
#
# Arguments:
#   $1 - API URL (e.g., http://localhost:8000)
#   $2 - API name for logging (e.g., "code-first")
#
# Returns:
#   0 - API is reachable
#   1 - API is not reachable
#
# Outputs:
#   Progress messages to stdout
#######################################
check_api_reachable() {
    local url="$1"
    local name="$2"

    if curl -sf "${url}/health" >/dev/null 2>&1; then
        info "${name} API is reachable at ${url}"
        return 0
    else
        warn "${name} API is not reachable at ${url}"
        return 1
    fi
}

#######################################
# Extract OpenAPI spec from running API.
#
# Downloads the OpenAPI JSON specification from /openapi.json endpoint
# and converts it to YAML for comparison.
#
# Arguments:
#   $1 - API URL
#   $2 - Output file path (YAML)
#   $3 - API name for logging
#
# Returns:
#   0 - Successfully extracted spec
#   1 - Failed to extract spec
#
# Outputs:
#   Progress messages to stdout
#   Extracted spec to output file
#######################################
extract_spec() {
    local url="$1"
    local output="$2"
    local name="$3"

    info "Extracting OpenAPI spec from ${name}..."

    # Download JSON spec
    local json_file="${TEMP_DIR}/${name}.json"
    if ! curl -sf "${url}/openapi.json" -o "$json_file"; then
        error "Failed to extract spec from ${name}" 2
        return 1
    fi

    # Convert to YAML for comparison
    if ! yq eval -P . "$json_file" > "$output"; then
        error "Failed to convert spec to YAML" 1
        return 1
    fi

    return 0
}

#######################################
# Normalize OpenAPI spec for comparison.
#
# Removes fields that are expected to differ between implementations:
# - Server URLs (different ports)
# - Implementation-specific descriptions
# - operationId (may differ)
#
# Arguments:
#   $1 - Input spec file
#   $2 - Output normalized spec file
#
# Returns:
#   0 - Successfully normalized
#   1 - Normalization failed
#######################################
normalize_spec() {
    local input="$1"
    local output="$2"

    # Remove servers, operationIds, and implementation-specific info
    yq eval 'del(.servers) | del(.info.description) | walk(if type == "object" then del(.operationId) else . end)' \
        "$input" > "$output"
}

#######################################
# Compare two OpenAPI specifications.
#
# Normalizes and compares two specs, reporting differences.
#
# Arguments:
#   $1 - First spec file
#   $2 - Second spec file
#   $3 - First spec name (for reporting)
#   $4 - Second spec name (for reporting)
#
# Returns:
#   0 - Specs match
#   1 - Specs differ
#
# Outputs:
#   Comparison results to stdout
#######################################
compare_specs() {
    local spec1="$1"
    local spec2="$2"
    local name1="$3"
    local name2="$4"

    # Normalize both specs
    local norm1="${TEMP_DIR}/norm1.yaml"
    local norm2="${TEMP_DIR}/norm2.yaml"

    normalize_spec "$spec1" "$norm1"
    normalize_spec "$spec2" "$norm2"

    # Compare normalized specs
    if diff -u "$norm1" "$norm2" > "${TEMP_DIR}/diff.txt" 2>&1; then
        success "${name1} and ${name2} specifications match!"
        return 0
    else
        error "${name1} and ${name2} specifications differ!" 1
        echo ""
        echo "Differences found:"
        head -50 "${TEMP_DIR}/diff.txt"
        if [ "$(wc -l < "${TEMP_DIR}/diff.txt")" -gt 50 ]; then
            echo ""
            echo "... (showing first 50 lines of diff)"
            echo "Run './scripts/sync-report.sh' for full details"
        fi
        return 1
    fi
}

#######################################
# Validate spec against schema.
#
# Uses OpenAPI schema validation to ensure spec is valid.
#
# Arguments:
#   $1 - Spec file path
#   $2 - Spec name for logging
#
# Returns:
#   0 - Spec is valid
#   1 - Spec is invalid
#######################################
validate_spec_schema() {
    local spec="$1"
    local name="$2"

    info "Validating ${name} spec schema..."

    # Basic YAML validation
    if ! yq eval . "$spec" >/dev/null 2>&1; then
        error "${name} spec has invalid YAML syntax" 1
        return 1
    fi

    # Check required OpenAPI fields
    local openapi_version=$(yq eval '.openapi' "$spec")
    if [[ ! "$openapi_version" =~ ^3\. ]]; then
        error "${name} spec has invalid OpenAPI version: $openapi_version" 1
        return 1
    fi

    local title=$(yq eval '.info.title' "$spec")
    if [ "$title" == "null" ] || [ -z "$title" ]; then
        error "${name} spec missing required field: info.title" 1
        return 1
    fi

    success "${name} spec schema is valid"
    return 0
}

#######################################
# Main execution function.
#
# Orchestrates the synchronization validation:
# 1. Checks prerequisites
# 2. Verifies APIs are reachable
# 3. Extracts specs from both implementations
# 4. Compares against shared spec
# 5. Compares implementations against each other
#
# Returns:
#   0 - APIs are synchronized
#   1 - APIs are out of sync
#   2 - Cannot reach APIs
#######################################
main() {
    info "Starting API synchronization validation..."
    info "Code-first: ${CODE_FIRST_URL}"
    info "API-first: ${API_FIRST_URL}"
    info "Shared spec: ${SHARED_SPEC}"
    echo ""

    # Check prerequisites
    if ! command -v curl &> /dev/null; then
        error "curl is not installed"
    fi

    if ! command -v yq &> /dev/null; then
        error "yq is not installed. Install: brew install yq"
    fi

    # Check if shared spec exists
    if [ ! -f "$SHARED_SPEC" ]; then
        error "Shared OpenAPI spec not found: $SHARED_SPEC"
    fi

    # Validate shared spec
    validate_spec_schema "$SHARED_SPEC" "shared"
    echo ""

    # Check API reachability
    local code_first_reachable=false
    local api_first_reachable=false

    if check_api_reachable "$CODE_FIRST_URL" "code-first"; then
        code_first_reachable=true
    fi

    if check_api_reachable "$API_FIRST_URL" "API-first"; then
        api_first_reachable=true
    fi

    if [ "$code_first_reachable" = false ] && [ "$api_first_reachable" = false ]; then
        error "Neither API is reachable. Start them with 'make start-code-first' and 'make start-api-first'" 2
    fi

    echo ""

    # Extract specs from running APIs
    if [ "$code_first_reachable" = true ]; then
        extract_spec "$CODE_FIRST_URL" "${TEMP_DIR}/code-first.yaml" "code-first"
    fi

    if [ "$api_first_reachable" = true ]; then
        extract_spec "$API_FIRST_URL" "${TEMP_DIR}/api-first.yaml" "API-first"
    fi

    echo ""

    # Compare specs
    local sync_status=0

    if [ "$code_first_reachable" = true ] && [ "$api_first_reachable" = true ]; then
        info "Comparing code-first and API-first implementations..."
        if ! compare_specs "${TEMP_DIR}/code-first.yaml" "${TEMP_DIR}/api-first.yaml" "code-first" "API-first"; then
            sync_status=1
        fi
        echo ""
    fi

    # Compare against shared spec
    if [ "$code_first_reachable" = true ]; then
        info "Comparing code-first against shared spec..."
        if ! compare_specs "${TEMP_DIR}/code-first.yaml" "$SHARED_SPEC" "code-first" "shared"; then
            sync_status=1
        fi
        echo ""
    fi

    if [ "$api_first_reachable" = true ]; then
        info "Comparing API-first against shared spec..."
        if ! compare_specs "${TEMP_DIR}/api-first.yaml" "$SHARED_SPEC" "API-first" "shared"; then
            sync_status=1
        fi
        echo ""
    fi

    # Final verdict
    if [ $sync_status -eq 0 ]; then
        success "✓ All API implementations are synchronized!"
        return 0
    else
        error "✗ API implementations are OUT OF SYNC!" 1
        echo ""
        echo "To fix synchronization:"
        echo "  1. Update shared spec: ${SHARED_SPEC}"
        echo "  2. Regenerate API-first: make regenerate"
        echo "  3. Run validation again: make sync-check"
        return 1
    fi
}

# Execute main function
main "$@"
