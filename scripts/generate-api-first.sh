#!/usr/bin/env bash
#
# Generate API-first FastAPI implementation from OpenAPI specification.
#
# This script generates a FastAPI server implementation from the shared OpenAPI
# specification using datamodel-codegen. The generated code serves as the skeleton
# for the API-first implementation, which is then enhanced with business logic.
#
# The script performs:
# 1. Validation of OpenAPI spec
# 2. Generation of Pydantic models from schemas
# 3. Generation of FastAPI route stubs
# 4. Setup of project structure and dependencies
#
# Usage:
#     ./scripts/generate-api-first.sh
#
# Environment Variables:
#     OPENAPI_SPEC: Path to OpenAPI spec (default: reference-apps/shared/openapi.yaml)
#     OUTPUT_DIR: Output directory (default: reference-apps/fastapi-api-first)
#     CLEAN: Set to 'true' to clean output directory before generation (default: false)
#
# Returns:
#     0: Success - Code generated successfully
#     1: Error - Generation failed or spec invalid
#
# Examples:
#     # Generate with defaults
#     ./scripts/generate-api-first.sh
#
#     # Clean and regenerate
#     CLEAN=true ./scripts/generate-api-first.sh
#
#     # Generate from custom spec
#     OPENAPI_SPEC=custom.yaml ./scripts/generate-api-first.sh
#
# Author:
#     Development Team
#
# Date:
#     2025-10-27
#
# See Also:
#     scripts/extract-openapi.sh - Extracts spec from code-first implementation
#     scripts/validate-sync.sh - Validates both implementations match
#     reference-apps/API_PATTERNS.md - Documentation on API patterns
#
# Prerequisites:
#     - Python 3.11+
#     - datamodel-code-generator (pip install datamodel-code-generator)
#     - yq (for YAML validation)
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
readonly DEFAULT_OPENAPI_SPEC="${PROJECT_ROOT}/reference-apps/shared/openapi.yaml"
readonly DEFAULT_OUTPUT_DIR="${PROJECT_ROOT}/reference-apps/fastapi-api-first"
readonly DEFAULT_CLEAN="false"

# Configuration from environment or defaults
readonly OPENAPI_SPEC="${OPENAPI_SPEC:-$DEFAULT_OPENAPI_SPEC}"
readonly OUTPUT_DIR="${OUTPUT_DIR:-$DEFAULT_OUTPUT_DIR}"
readonly CLEAN="${CLEAN:-$DEFAULT_CLEAN}"

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
# Validate OpenAPI specification.
#
# Checks that the OpenAPI spec file exists and is valid YAML.
# Also validates that it contains required OpenAPI 3.x structure.
#
# Globals:
#   OPENAPI_SPEC - Path to OpenAPI specification file
#
# Arguments:
#   None
#
# Returns:
#   0 - Spec is valid
#   1 - Spec is invalid or missing
#
# Outputs:
#   Progress messages to stdout
#   Error messages to stderr
#
# Examples:
#   if validate_openapi_spec; then
#       echo "Spec is valid"
#   fi
#######################################
validate_openapi_spec() {
    info "Validating OpenAPI specification..."

    # Check if file exists
    if [ ! -f "$OPENAPI_SPEC" ]; then
        error "OpenAPI spec not found: $OPENAPI_SPEC"
        return 1
    fi

    # Validate YAML syntax
    if ! yq eval . "$OPENAPI_SPEC" >/dev/null 2>&1; then
        error "Invalid YAML syntax in $OPENAPI_SPEC"
        return 1
    fi

    # Check OpenAPI version
    local openapi_version=$(yq eval '.openapi' "$OPENAPI_SPEC")
    if [[ ! "$openapi_version" =~ ^3\. ]]; then
        error "Unsupported OpenAPI version: $openapi_version (requires 3.x)"
        return 1
    fi

    # Check required fields
    local title=$(yq eval '.info.title' "$OPENAPI_SPEC")
    local paths_count=$(yq eval '.paths | length' "$OPENAPI_SPEC")

    if [ "$title" == "null" ]; then
        error "OpenAPI spec missing required field: info.title"
        return 1
    fi

    if [ "$paths_count" == "0" ]; then
        warn "OpenAPI spec has no paths defined"
    fi

    success "OpenAPI spec is valid (version: $openapi_version, paths: $paths_count)"
    return 0
}

#######################################
# Check prerequisites for code generation.
#
# Verifies that all required tools are installed:
# - Python 3.11+
# - datamodel-code-generator
# - yq
#
# Globals:
#   None
#
# Arguments:
#   None
#
# Returns:
#   0 - All prerequisites met
#   1 - Missing prerequisites
#
# Outputs:
#   Error messages for missing tools
#######################################
check_prerequisites() {
    info "Checking prerequisites..."

    # Check Python
    if ! command -v python3 &> /dev/null; then
        error "python3 is not installed. Please install Python 3.11+"
    fi

    local python_version=$(python3 --version | awk '{print $2}')
    info "Found Python $python_version"

    # Check yq
    if ! command -v yq &> /dev/null; then
        error "yq is not installed. Please install it first."
    fi

    # Check if datamodel-code-generator is available via pipx or pip
    if ! command -v datamodel-codegen &> /dev/null && \
       ! python3 -c "import datamodel_code_generator" 2>/dev/null; then
        warn "datamodel-code-generator not found"

        # Try pipx first (recommended for externally-managed Python)
        if command -v pipx &> /dev/null; then
            info "Installing datamodel-code-generator via pipx..."
            pipx install "datamodel-code-generator[http]>=0.25.0" || \
                error "Failed to install datamodel-code-generator via pipx"
        else
            info "Installing datamodel-code-generator (may require --break-system-packages)..."
            pip3 install --break-system-packages -q "datamodel-code-generator[http]>=0.25.0" || \
                error "Failed to install datamodel-code-generator. Try: brew install pipx && pipx install datamodel-code-generator"
        fi
    fi

    success "All prerequisites met"
    return 0
}

#######################################
# Clean output directory.
#
# Removes existing generated files from the output directory
# while preserving manually written implementation files.
#
# Globals:
#   OUTPUT_DIR - Target directory to clean
#   CLEAN - Whether to perform cleaning
#
# Arguments:
#   None
#
# Returns:
#   0 - Success
#
# Outputs:
#   Progress messages to stdout
#######################################
clean_output_dir() {
    if [ "$CLEAN" != "true" ]; then
        return 0
    fi

    info "Cleaning output directory..."

    if [ -d "$OUTPUT_DIR/app/models" ]; then
        rm -rf "$OUTPUT_DIR/app/models"
        info "Removed generated models"
    fi

    success "Output directory cleaned"
    return 0
}

#######################################
# Generate Pydantic models from OpenAPI schemas.
#
# Uses datamodel-code-generator to create Pydantic model classes
# from the schema definitions in the OpenAPI specification.
#
# Globals:
#   OPENAPI_SPEC - Source OpenAPI specification
#   OUTPUT_DIR - Target directory for generated code
#
# Arguments:
#   None
#
# Returns:
#   0 - Models generated successfully
#   1 - Generation failed
#
# Outputs:
#   Generated Python files in OUTPUT_DIR/app/models/
#   Progress messages to stdout
#######################################
generate_models() {
    info "Generating Pydantic models from OpenAPI schemas..."

    local models_dir="$OUTPUT_DIR/app/models"
    mkdir -p "$models_dir"

    # Generate models using datamodel-code-generator
    datamodel-codegen \
        --input "$OPENAPI_SPEC" \
        --input-file-type openapi \
        --output "$models_dir/generated.py" \
        --use-standard-collections \
        --use-schema-description \
        --target-python-version 3.11 \
        --field-constraints \
        --use-annotated \
        --collapse-root-models \
        --enable-faux-immutability \
        2>&1 || error "Failed to generate models"

    # Create __init__.py
    echo '"""Generated Pydantic models from OpenAPI specification."""' > "$models_dir/__init__.py"

    local model_count=$(grep -c "^class " "$models_dir/generated.py" || echo "0")
    success "Generated $model_count Pydantic models"

    return 0
}

#######################################
# Generate FastAPI router stubs.
#
# Creates FastAPI router files with endpoint stubs based on the
# paths defined in the OpenAPI specification. Stubs include proper
# type hints, response models, and documentation strings.
#
# Globals:
#   OPENAPI_SPEC - Source OpenAPI specification
#   OUTPUT_DIR - Target directory for generated code
#
# Arguments:
#   None
#
# Returns:
#   0 - Routers generated successfully
#   1 - Generation failed
#
# Outputs:
#   Generated Python router files in OUTPUT_DIR/app/routers/
#   Progress messages to stdout
#######################################
generate_routers() {
    info "Generating FastAPI router stubs..."

    local routers_dir="$OUTPUT_DIR/app/routers"
    mkdir -p "$routers_dir"

    # Extract tags from OpenAPI spec
    local tags=$(yq eval '.tags[].name' "$OPENAPI_SPEC" | sort -u)

    # Create router stub for each tag
    while IFS= read -r tag; do
        if [ -z "$tag" ] || [ "$tag" == "null" ]; then
            continue
        fi

        # Convert tag to valid Python module name (lowercase, replace spaces with underscores)
        local router_name=$(echo "$tag" | tr '[:upper:]' '[:lower:]' | tr ' ' '_' | tr '-' '_')
        local router_file="$routers_dir/${router_name}.py"

        info "  Creating router: $router_name"

        # Create router file with stub
        cat > "$router_file" << EOF
"""
${tag} Router

Auto-generated router stub from OpenAPI specification.
Implement the business logic for ${tag} endpoints here.
"""

from fastapi import APIRouter, HTTPException, status
from typing import Any

router = APIRouter(
    prefix="",
    tags=["${tag}"],
)

# TODO: Implement endpoints for ${tag}
# Add your endpoint implementations here
EOF

    done <<< "$tags"

    # Create __init__.py
    echo '"""API routers generated from OpenAPI specification."""' > "$routers_dir/__init__.py"

    local router_count=$(ls -1 "$routers_dir"/*.py 2>/dev/null | grep -v __init__ | wc -l || echo "0")
    success "Generated $router_count router stubs"

    return 0
}

#######################################
# Generate main FastAPI application.
#
# Creates the main FastAPI application file with:
# - App initialization
# - Router registration
# - Middleware configuration
# - CORS settings
# - Startup/shutdown events
#
# Globals:
#   OUTPUT_DIR - Target directory for generated code
#   OPENAPI_SPEC - Source OpenAPI specification (for metadata)
#
# Arguments:
#   None
#
# Returns:
#   0 - App generated successfully
#
# Outputs:
#   Generated main.py file
#   Progress messages to stdout
#######################################
generate_main_app() {
    info "Generating main FastAPI application..."

    local app_file="$OUTPUT_DIR/app/main.py"

    # Extract API metadata from spec
    local api_title=$(yq eval '.info.title' "$OPENAPI_SPEC")
    local api_version=$(yq eval '.info.version' "$OPENAPI_SPEC")
    local api_description=$(yq eval '.info.description' "$OPENAPI_SPEC")

    cat > "$app_file" << 'EOF'
"""
Main FastAPI Application (API-First Implementation)

Auto-generated from OpenAPI specification.
This implementation is generated from the OpenAPI spec and enhanced
with business logic to match the code-first implementation.
"""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

# Create FastAPI app
app = FastAPI(
    title="DevStack Core - Reference API (API-First)",
    version="1.0.0",
    description="API-First implementation generated from OpenAPI specification",
)

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# TODO: Import and include routers
# from app.routers import health_checks, vault_examples
# app.include_router(health_checks.router)
# app.include_router(vault_examples.router)


@app.on_event("startup")
async def startup_event():
    """Application startup event handler."""
    logger.info("Starting API-First FastAPI application...")
    # TODO: Initialize connections, load configuration


@app.on_event("shutdown")
async def shutdown_event():
    """Application shutdown event handler."""
    logger.info("Shutting down API-First FastAPI application...")
    # TODO: Close connections, cleanup resources


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "name": "DevStack Core - Reference API (API-First)",
        "version": "1.0.0",
        "implementation": "api-first",
        "description": "Generated from OpenAPI specification",
    }


@app.get("/health")
async def health_check():
    """Simple health check endpoint."""
    return {"status": "healthy", "implementation": "api-first"}
EOF

    success "Generated main application file"
    return 0
}

#######################################
# Generate project configuration files.
#
# Creates supporting files:
# - requirements.txt
# - Dockerfile
# - README.md
# - pytest.ini (for testing)
#
# Globals:
#   OUTPUT_DIR - Target directory for generated code
#
# Arguments:
#   None
#
# Returns:
#   0 - Configuration files generated successfully
#
# Outputs:
#   Generated configuration files
#   Progress messages to stdout
#######################################
generate_config_files() {
    info "Generating project configuration files..."

    # Generate requirements.txt
    cat > "$OUTPUT_DIR/requirements.txt" << 'EOF'
# API-First Implementation Dependencies
# Generated from OpenAPI specification

# Core FastAPI dependencies
fastapi==0.115.5
uvicorn[standard]==0.32.1
pydantic==2.10.2
pydantic-settings==2.6.1

# Infrastructure clients (match code-first implementation)
hvac==2.3.0              # HashiCorp Vault
psycopg2-binary==2.9.10  # PostgreSQL
pymongo==4.10.1          # MongoDB
pymysql==1.1.1           # MySQL
redis==5.2.0             # Redis
pika==1.3.2              # RabbitMQ
cryptography==44.0.0     # TLS/PKI support

# Monitoring and observability
prometheus-client==0.21.0

# Development and testing
pytest==8.3.4
pytest-asyncio==0.24.0
httpx==0.28.0
EOF

    # Generate minimal README
    cat > "$OUTPUT_DIR/README.md" << 'EOF'
# API-First FastAPI Implementation

This implementation is **generated from the OpenAPI specification** in
`reference-apps/shared/openapi.yaml`.

## Overview

This is the API-first implementation of the DevStack Core Reference API.
The code structure is generated from the OpenAPI spec and enhanced with
business logic to match the code-first implementation.

## Generation

To regenerate this implementation from the OpenAPI spec:

```bash
./scripts/generate-api-first.sh
```

## Architecture

- **Generated Code**: Models and router stubs generated by datamodel-code-generator
- **Business Logic**: Manually implemented to match code-first behavior
- **Synchronization**: Kept in sync with code-first via shared test suite

## Running

```bash
cd reference-apps/fastapi-api-first
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

Access the API at: http://localhost:8001/docs

## Testing

```bash
pytest tests/
```

## Synchronization

See `reference-apps/API_PATTERNS.md` for details on how this implementation
is kept synchronized with the code-first implementation.
EOF

    # Generate pytest.ini
    cat > "$OUTPUT_DIR/pytest.ini" << 'EOF'
[pytest]
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
asyncio_mode = auto
EOF

    # Create empty __init__.py files
    touch "$OUTPUT_DIR/app/__init__.py"
    touch "$OUTPUT_DIR/app/routers/__init__.py"
    touch "$OUTPUT_DIR/app/services/__init__.py"
    touch "$OUTPUT_DIR/app/models/__init__.py"
    touch "$OUTPUT_DIR/tests/__init__.py"

    success "Generated project configuration files"
    return 0
}

#######################################
# Display generation summary.
#
# Shows summary of generated files and next steps.
#
# Globals:
#   OUTPUT_DIR - Target directory with generated code
#   OPENAPI_SPEC - Source specification file
#
# Arguments:
#   None
#
# Returns:
#   0 - Success
#
# Outputs:
#   Summary information to stdout
#######################################
display_summary() {
    info "Generation Summary:"

    echo "  Specification: $OPENAPI_SPEC"
    echo "  Output Directory: $OUTPUT_DIR"
    echo ""
    echo "  Generated Files:"
    echo "    - Pydantic models: app/models/generated.py"
    echo "    - Router stubs: app/routers/*.py"
    echo "    - Main application: app/main.py"
    echo "    - Configuration: requirements.txt, README.md, pytest.ini"
    echo ""
    echo "  Next Steps:"
    echo "    1. Review generated code in $OUTPUT_DIR"
    echo "    2. Implement business logic in router files"
    echo "    3. Add service layer implementations"
    echo "    4. Run: cd $OUTPUT_DIR && pip install -r requirements.txt"
    echo "    5. Run: uvicorn app.main:app --port 8001 --reload"
    echo "    6. Test: pytest tests/"
    echo ""

    return 0
}

#######################################
# Main execution function.
#
# Orchestrates the code generation process:
# 1. Validates prerequisites
# 2. Validates OpenAPI spec
# 3. Cleans output directory (if requested)
# 4. Generates models
# 5. Generates routers
# 6. Generates main app
# 7. Generates config files
# 8. Displays summary
#
# Globals:
#   OPENAPI_SPEC - Source specification
#   OUTPUT_DIR - Target directory
#
# Arguments:
#   None
#
# Returns:
#   0 - Generation successful
#   1 - Generation failed
#
# Outputs:
#   Progress messages and summary to stdout
#######################################
main() {
    info "Starting API-First code generation..."
    info "Specification: $OPENAPI_SPEC"
    info "Output: $OUTPUT_DIR"
    echo ""

    # Check prerequisites
    check_prerequisites

    echo ""

    # Validate OpenAPI spec
    if ! validate_openapi_spec; then
        error "OpenAPI spec validation failed"
    fi

    echo ""

    # Clean if requested
    clean_output_dir

    echo ""

    # Generate models
    if ! generate_models; then
        error "Model generation failed"
    fi

    echo ""

    # Generate routers
    if ! generate_routers; then
        error "Router generation failed"
    fi

    echo ""

    # Generate main app
    if ! generate_main_app; then
        error "Main app generation failed"
    fi

    echo ""

    # Generate config files
    if ! generate_config_files; then
        error "Config file generation failed"
    fi

    echo ""

    # Display summary
    display_summary

    success "API-First code generation complete!"

    return 0
}

# Execute main function
main "$@"
