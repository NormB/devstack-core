#!/usr/bin/env bash
#
# Extract OpenAPI specification from code-first FastAPI implementation.
#
# This script starts the code-first FastAPI service (if not running), waits for
# it to be healthy, extracts the OpenAPI JSON specification from the /openapi.json
# endpoint, and saves it to the shared directory.
#
# The extracted spec serves as the basis for comparison and synchronization between
# the code-first and API-first implementations.
#
# Usage:
#     ./scripts/extract-openapi.sh
#
# Environment Variables:
#     CODE_FIRST_URL: Base URL of code-first API (default: http://localhost:8000)
#     OUTPUT_FILE: Output file path (default: reference-apps/shared/openapi.json)
#     TIMEOUT: Maximum wait time in seconds (default: 120)
#
# Returns:
#     0: Success - OpenAPI spec extracted and saved
#     1: Error - API not accessible or extraction failed
#
# Examples:
#     # Extract with defaults
#     ./scripts/extract-openapi.sh
#
#     # Extract from custom URL
#     CODE_FIRST_URL=http://192.168.1.100:8000 ./scripts/extract-openapi.sh
#
#     # Extract with custom output file
#     OUTPUT_FILE=/tmp/openapi.json ./scripts/extract-openapi.sh
#
# Author:
#     Development Team
#
# Date:
#     2025-10-27
#
# See Also:
#     scripts/validate-sync.sh - Validates both implementations match
#     scripts/regenerate-api-first.sh - Regenerates API-first from spec
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
readonly DEFAULT_OUTPUT_FILE="${PROJECT_ROOT}/reference-apps/shared/openapi.json"
readonly DEFAULT_TIMEOUT=120

# Configuration from environment or defaults
readonly CODE_FIRST_URL="${CODE_FIRST_URL:-$DEFAULT_CODE_FIRST_URL}"
readonly OUTPUT_FILE="${OUTPUT_FILE:-$DEFAULT_OUTPUT_FILE}"
readonly TIMEOUT="${TIMEOUT:-$DEFAULT_TIMEOUT}"

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
# Wait for code-first API to become healthy.
#
# Repeatedly polls the /health endpoint until it returns a successful response
# or the timeout is reached. Uses exponential backoff for retries.
#
# Globals:
#   CODE_FIRST_URL - Base URL of the API to check
#   TIMEOUT - Maximum wait time in seconds
#
# Arguments:
#   None
#
# Returns:
#   0 - API is healthy and accessible
#   1 - Timeout reached without successful health check
#
# Outputs:
#   Progress messages to stdout
#
# Examples:
#   if wait_for_api_healthy; then
#       echo "API is ready"
#   else
#       echo "API failed to start"
#   fi
#######################################
wait_for_api_healthy() {
    local start_time=$(date +%s)
    local end_time=$((start_time + TIMEOUT))
    local attempt=1
    local max_backoff=10

    info "Waiting for API to be healthy at ${CODE_FIRST_URL}..."

    while [ $(date +%s) -lt $end_time ]; do
        # Try health endpoint
        if curl -sf "${CODE_FIRST_URL}/health" >/dev/null 2>&1; then
            local elapsed=$(($(date +%s) - start_time))
            success "API is healthy (took ${elapsed}s)"
            return 0
        fi

        # Calculate backoff delay (exponential with max)
        local delay=$((attempt < max_backoff ? attempt : max_backoff))

        # Show progress
        local remaining=$((end_time - $(date +%s)))
        info "Attempt ${attempt}: API not ready yet, retrying in ${delay}s (${remaining}s remaining)..."

        sleep "$delay"
        attempt=$((attempt + 1))
    done

    error "Timeout: API did not become healthy within ${TIMEOUT}s"
    return 1
}

#######################################
# Extract OpenAPI specification from API.
#
# Downloads the OpenAPI JSON specification from the /openapi.json endpoint
# and saves it to the specified output file. Validates that the response
# is valid JSON before saving.
#
# Globals:
#   CODE_FIRST_URL - Base URL of the API
#   OUTPUT_FILE - Destination file path
#
# Arguments:
#   None
#
# Returns:
#   0 - Successfully extracted and saved spec
#   1 - Failed to extract or invalid JSON
#
# Outputs:
#   Progress messages to stdout
#   Downloaded spec to OUTPUT_FILE
#
# Examples:
#   if extract_openapi_spec; then
#       echo "Spec saved to $OUTPUT_FILE"
#   fi
#######################################
extract_openapi_spec() {
    local url="${CODE_FIRST_URL}/openapi.json"

    info "Extracting OpenAPI spec from ${url}..."

    # Download spec to temporary file
    local temp_file=$(mktemp)
    if ! curl -sf "$url" -o "$temp_file"; then
        rm -f "$temp_file"
        error "Failed to download OpenAPI spec from ${url}"
        return 1
    fi

    # Validate JSON
    if ! jq empty "$temp_file" 2>/dev/null; then
        rm -f "$temp_file"
        error "Downloaded spec is not valid JSON"
        return 1
    fi

    # Create output directory if needed
    local output_dir=$(dirname "$OUTPUT_FILE")
    mkdir -p "$output_dir"

    # Move to final location
    mv "$temp_file" "$OUTPUT_FILE"

    # Show file info
    local file_size=$(du -h "$OUTPUT_FILE" | cut -f1)
    success "OpenAPI spec saved to ${OUTPUT_FILE} (${file_size})"

    return 0
}

#######################################
# Display specification summary.
#
# Parses the extracted OpenAPI JSON and displays key information including
# API title, version, number of endpoints, and tags.
#
# Globals:
#   OUTPUT_FILE - Path to OpenAPI spec file
#
# Arguments:
#   None
#
# Returns:
#   0 - Successfully displayed summary
#   1 - Failed to parse spec
#
# Outputs:
#   Summary information to stdout
#######################################
display_spec_summary() {
    info "Specification Summary:"

    # Extract key information using jq
    local title=$(jq -r '.info.title // "Unknown"' "$OUTPUT_FILE")
    local version=$(jq -r '.info.version // "Unknown"' "$OUTPUT_FILE")
    local endpoint_count=$(jq -r '.paths | length' "$OUTPUT_FILE")
    local schema_count=$(jq -r '.components.schemas | length' "$OUTPUT_FILE")

    echo "  Title: $title"
    echo "  Version: $version"
    echo "  Endpoints: $endpoint_count"
    echo "  Schemas: $schema_count"

    # List tags
    echo "  Tags:"
    jq -r '.paths | to_entries | .[].value | .. | .tags? | select(. != null) | .[]' "$OUTPUT_FILE" | \
        sort -u | \
        sed 's/^/    - /'

    return 0
}

#######################################
# Main execution function.
#
# Orchestrates the OpenAPI extraction process:
# 1. Validates prerequisites
# 2. Waits for API to be healthy
# 3. Extracts OpenAPI specification
# 4. Displays summary
#
# Globals:
#   CODE_FIRST_URL - API URL to extract from
#   OUTPUT_FILE - Destination file
#
# Arguments:
#   None
#
# Returns:
#   0 - Successfully extracted spec
#   1 - Extraction failed
#
# Outputs:
#   Progress messages and summary to stdout
#######################################
main() {
    info "Starting OpenAPI extraction..."
    info "Source: ${CODE_FIRST_URL}"
    info "Output: ${OUTPUT_FILE}"
    echo ""

    # Check prerequisites
    if ! command -v curl &> /dev/null; then
        error "curl is not installed. Please install it first."
    fi

    if ! command -v jq &> /dev/null; then
        error "jq is not installed. Please install it first."
    fi

    # Wait for API
    if ! wait_for_api_healthy; then
        error "API is not accessible. Is the service running?"
    fi

    echo ""

    # Extract spec
    if ! extract_openapi_spec; then
        error "Failed to extract OpenAPI specification"
    fi

    echo ""

    # Show summary
    display_spec_summary

    echo ""
    success "OpenAPI extraction complete!"

    return 0
}

# Execute main function
main "$@"
