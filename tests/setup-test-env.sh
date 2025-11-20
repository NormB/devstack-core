#!/bin/bash
#######################################
# Test Environment Setup Script
#
# Sets up Python environment using uv package manager and installs all
# dependencies required for the DevStack Core test suite. Validates
# installation and provides usage instructions.
#
# Globals:
#   SCRIPT_DIR - Absolute path to tests directory
#   RED, GREEN, BLUE, NC - Color codes for terminal output
#
# Dependencies:
#   - uv (Python package manager)
#   - python3 (>= 3.8)
#   - Docker (for running tests)
#
# Exit Codes:
#   0 - Environment setup completed successfully
#   1 - Missing required dependency (uv or python3)
#   1 - Dependency installation or verification failed
#
# Usage:
#   ./tests/setup-test-env.sh
#
# Notes:
#   - Script must be run from repository root or tests directory
#   - Uses uv sync to install dependencies from pyproject.toml
#   - Validates psycopg2 installation as smoke test
#   - Safe to run multiple times (idempotent)
#   - Creates/updates Python virtual environment managed by uv
#
# Examples:
#   # Initial setup
#   cd /path/to/devstack-core
#   ./tests/setup-test-env.sh
#
#   # Re-run after updating dependencies
#   ./tests/setup-test-env.sh
#
#######################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print informational message in blue
# Globals:
#   BLUE, NC - Color codes
# Arguments:
#   $1 - Message to print
# Outputs:
#   Writes formatted message to stdout
#######################################
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

#######################################
# Print success message in green
# Globals:
#   GREEN, NC - Color codes
# Arguments:
#   $1 - Success message to print
# Outputs:
#   Writes formatted success message to stdout
#######################################
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

#######################################
# Print error message and exit with code 1
# Globals:
#   RED, NC - Color codes
# Arguments:
#   $1 - Error message to print
# Outputs:
#   Writes formatted error message to stderr
# Notes:
#   Always exits with code 1
#   Does not return to caller
#######################################
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo
echo "==========================================="
echo "  Test Environment Setup (using uv)"
echo "==========================================="
echo

# Check if uv is installed
info "Checking for uv..."
if ! command -v uv &> /dev/null; then
    error "uv is not installed. Install it with: brew install uv"
fi

UV_VERSION=$(uv --version)
info "Found: $UV_VERSION"

# Check Python version
info "Checking Python version..."
if ! command -v python3 &> /dev/null; then
    error "Python 3 is required but not installed"
fi

PYTHON_VERSION=$(python3 --version)
info "Found: $PYTHON_VERSION"

# Sync dependencies using uv
info "Syncing dependencies with uv..."
cd "$SCRIPT_DIR"
uv sync

success "Dependencies synced"

# Verify installations
info "Verifying installations..."
uv run python -c "import psycopg2; print('  ✓ psycopg2:', psycopg2.__version__)" || error "psycopg2 installation failed"

success "All dependencies verified"

echo
echo "==========================================="
success "Test environment ready!"
echo "==========================================="
echo
info "To use the test clients:"
echo "  cd tests && uv run python lib/postgres_client.py --help"
echo "  cd tests && uv run python lib/vault_client.py --help"
echo
info "To run tests:"
echo "  ./tests/run-all-tests.sh"
echo "  ./tests/test-postgres.sh"
echo "  ./tests/test-vault.sh"
echo
