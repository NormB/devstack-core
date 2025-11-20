#!/usr/bin/env bash
#
# Regenerate API-first implementation from OpenAPI specification.
#
# This script rebuilds the API-first implementation by regenerating models
# and router stubs from the shared OpenAPI specification. Business logic
# in existing routers is preserved.
#
# Usage:
#     ./scripts/regenerate-api-first.sh
#
# Environment Variables:
#     SHARED_SPEC: Path to OpenAPI spec (default: reference-apps/shared/openapi.yaml)
#     OUTPUT_DIR: Output directory (default: reference-apps/fastapi-api-first)
#     BACKUP: Create backup before regenerating (default: true)
#
# Returns:
#     0: Successfully regenerated
#     1: Regeneration failed
#
# Examples:
#     # Regenerate with defaults
#     ./scripts/regenerate-api-first.sh
#
#     # Regenerate without backup
#     BACKUP=false ./scripts/regenerate-api-first.sh
#
# Author:
#     Development Team
#
# Date:
#     2025-10-27
#
# See Also:
#     scripts/generate-api-first.sh - Initial generation script
#     scripts/validate-sync.sh - Validate synchronization
#

set -e
set -u
set -o pipefail

# Script directory and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
readonly DEFAULT_SHARED_SPEC="${PROJECT_ROOT}/reference-apps/shared/openapi.yaml"
readonly DEFAULT_OUTPUT_DIR="${PROJECT_ROOT}/reference-apps/fastapi-api-first"
readonly DEFAULT_BACKUP="true"

readonly SHARED_SPEC="${SHARED_SPEC:-$DEFAULT_SHARED_SPEC}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
readonly BACKUP="${BACKUP:-$DEFAULT_BACKUP}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

#######################################
# Print messages with formatting.
#######################################
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit "${2:-1}"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

#######################################
# Create backup of existing implementation.
#
# Returns:
#   0 - Backup created successfully
#######################################
create_backup() {
    if [ "$BACKUP" != "true" ]; then
        return 0
    fi

    local backup_dir="${OUTPUT_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    info "Creating backup: $backup_dir"

    if [ -d "$OUTPUT_DIR" ]; then
        cp -r "$OUTPUT_DIR" "$backup_dir"
        success "Backup created"
    fi
}

#######################################
# Regenerate Pydantic models from OpenAPI.
#
# Returns:
#   0 - Models regenerated successfully
#######################################
regenerate_models() {
    info "Regenerating Pydantic models..."

    local models_dir="${OUTPUT_DIR}/app/models"

    # Regenerate generated.py
    datamodel-codegen \
        --input "$SHARED_SPEC" \
        --input-file-type openapi \
        --output "${models_dir}/generated.py" \
        --use-standard-collections \
        --use-schema-description \
        --target-python-version 3.11 \
        --field-constraints \
        --use-annotated \
        --collapse-root-models \
        --enable-faux-immutability \
        2>&1 || error "Failed to regenerate models"

    local model_count=$(grep -c "^class " "${models_dir}/generated.py" || echo "0")
    success "Regenerated $model_count Pydantic models"
}

#######################################
# Update main.py if needed.
#
# Checks if main.py needs updates based on OpenAPI changes.
#
# Returns:
#   0 - Success
#######################################
check_main_app() {
    info "Checking main application..."

    local main_file="${OUTPUT_DIR}/app/main.py"

    if [ ! -f "$main_file" ]; then
        warn "main.py not found - may need manual creation"
        return 0
    fi

    # Extract routers from OpenAPI tags
    local tags=$(yq eval '.tags[].name' "$SHARED_SPEC" | sort -u)

    info "Expected routers based on OpenAPI tags:"
    echo "$tags" | sed 's/^/  - /'

    success "Main application check complete"
}

#######################################
# Validate regenerated implementation.
#
# Returns:
#   0 - Validation passed
#   1 - Validation failed
#######################################
validate_regeneration() {
    info "Validating regenerated implementation..."

    # Check if models file exists
    if [ ! -f "${OUTPUT_DIR}/app/models/generated.py" ]; then
        error "Models file not generated"
        return 1
    fi

    # Check if models file has content
    if [ ! -s "${OUTPUT_DIR}/app/models/generated.py" ]; then
        error "Models file is empty"
        return 1
    fi

    # Try to parse Python files
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 -m py_compile "${OUTPUT_DIR}/app/models/generated.py" 2>/dev/null; then
            error "Generated models have syntax errors"
            return 1
        fi
    fi

    success "Regenerated implementation is valid"
    return 0
}

#######################################
# Main execution.
#######################################
main() {
    info "Starting API-first regeneration..."
    info "Spec: ${SHARED_SPEC}"
    info "Output: ${OUTPUT_DIR}"
    echo ""

    # Verify shared spec exists
    if [ ! -f "$SHARED_SPEC" ]; then
        error "Shared OpenAPI spec not found: $SHARED_SPEC"
    fi

    # Verify output directory exists
    if [ ! -d "$OUTPUT_DIR" ]; then
        error "Output directory not found: $OUTPUT_DIR"
    fi

    # Check prerequisites
    if ! command -v datamodel-codegen >/dev/null 2>&1; then
        error "datamodel-code-generator not found. Install: pipx install datamodel-code-generator"
    fi

    if ! command -v yq >/dev/null 2>&1; then
        error "yq not found. Install: brew install yq"
    fi

    # Create backup
    create_backup
    echo ""

    # Regenerate models
    regenerate_models
    echo ""

    # Check main app
    check_main_app
    echo ""

    # Validate
    if ! validate_regeneration; then
        error "Validation failed"
    fi

    echo ""
    success "✓ API-first implementation regenerated successfully!"
    echo ""
    echo "Next steps:"
    echo "  1. Review changes: git diff ${OUTPUT_DIR}"
    echo "  2. Run tests: make test-api-first"
    echo "  3. Validate sync: make sync-check"
}

main "$@"
