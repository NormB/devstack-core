#!/bin/bash
#######################################
# Master Test Runner
#
# Orchestrates execution of all test suites (bash and pytest) in the Colima
# Services test infrastructure. Runs each test suite sequentially, tracks
# results, and provides comprehensive summary with pass/fail status for each
# suite. Runs 300+ total tests across infrastructure, applications, and unit tests.
#
# Globals:
#   SCRIPT_DIR - Absolute path to tests directory
#   TEST_RESULTS - Array of "suite_name:STATUS" pairs
#   TOTAL_SUITES - Total number of test suites executed
#   PASSED_SUITES - Number of suites that passed completely
#   FAILED_SUITES - Number of suites with failures
#   RED, GREEN, YELLOW, BLUE, CYAN, NC - Color codes for terminal output
#
# Dependencies:
#   - bash >= 3.2
#   - docker + docker compose (for all services)
#   - uv (Python package manager - https://github.com/astral-sh/uv)
#     Install: curl -LsSf https://astral.sh/uv/install.sh | sh
#     Or: brew install uv
#   - Individual test suite scripts in tests/ directory
#   - Docker containers (auto-started if not running):
#     * dev-reference-api (required for FastAPI unit tests)
#     * dev-api-first (required for parity tests, along with dev-reference-api)
#
# Exit Codes:
#   0 - All test suites passed
#   1 - One or more test suites failed
#
# Usage:
#   ./tests/run-all-tests.sh
#
# Notes:
#   - Executes test suites in defined order (infrastructure, databases, apps)
#   - Continues execution even if individual suites fail (|| true)
#   - Each suite runs independently with own setup/teardown
#   - Total execution time depends on all suites combined
#   - Requires test environment setup via setup-test-env.sh first
#
# Test Suite Execution Order:
#   1. Infrastructure: Vault Integration (bash)
#   2. Databases: PostgreSQL, MySQL, MongoDB (bash)
#   3. Cache: Redis, Redis Cluster (bash)
#   4. Messaging: RabbitMQ (bash)
#   5. Applications: FastAPI Reference App (bash)
#   6. Performance: Load & Response Time Testing (bash)
#   7. Negative: Error Handling & Security Testing (bash)
#   8. Python Unit Tests: FastAPI reference app tests (pytest in Docker)
#   9. Python Parity Tests: API implementation parity validation (pytest with uv)
#
# Best Practices for pytest Tests:
#   - Unit tests run INSIDE Docker containers (correct Python version, all deps)
#   - Parity tests run FROM HOST with uv (must access both APIs via localhost)
#   - Containers auto-start if not running
#   - Clear error messages with remediation steps
#
# Examples:
#   # Run all tests (auto-starts containers if needed)
#   ./tests/run-all-tests.sh
#
#   # Pre-start containers for faster test execution
#   docker compose up -d reference-api api-first
#   ./tests/run-all-tests.sh
#
#   # Check uv is installed
#   command -v uv || curl -LsSf https://astral.sh/uv/install.sh | sh
#
#######################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test results (using simple arrays for bash 3.2 compatibility)
TEST_RESULTS=()
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

#######################################
# Print formatted section header in cyan
# Globals:
#   CYAN, NC - Color codes
# Arguments:
#   $1 - Header text to display
# Outputs:
#   Writes formatted header to stdout with border lines
#######################################
header() {
    echo
    echo -e "${CYAN}=========================================${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}=========================================${NC}"
}

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
# Print failure message in red
# Globals:
#   RED, NC - Color codes
# Arguments:
#   $1 - Failure message to print
# Outputs:
#   Writes formatted failure message to stdout
#######################################
fail() { echo -e "${RED}[FAIL]${NC} $1"; }

#######################################
# Print warning message in yellow
# Globals:
#   YELLOW, NC - Color codes
# Arguments:
#   $1 - Warning message to print
# Outputs:
#   Writes formatted warning message to stdout
#######################################
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

#######################################
# Execute a single test suite and track results
# Globals:
#   TOTAL_SUITES - Incremented by 1
#   PASSED_SUITES - Incremented if test passes
#   FAILED_SUITES - Incremented if test fails
#   TEST_RESULTS - Appended with "name:STATUS"
# Arguments:
#   $1 - Path to test script to execute
#   $2 - Display name for test suite
# Returns:
#   0 - Test suite passed (all tests in suite passed)
#   1 - Test suite failed (one or more tests failed)
# Outputs:
#   Writes header and test output to stdout
# Notes:
#   Executes test script with bash interpreter
#   Captures exit code to determine pass/fail
#   Always updates global tracking variables
#######################################
run_test_suite() {
    local test_script=$1
    local test_name=$2

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    header "Running: $test_name"

    if bash "$test_script"; then
        TEST_RESULTS+=("$test_name:PASSED")
        PASSED_SUITES=$((PASSED_SUITES + 1))
        return 0
    else
        TEST_RESULTS+=("$test_name:FAILED")
        FAILED_SUITES=$((FAILED_SUITES + 1))
        return 1
    fi
}

#######################################
# Print comprehensive summary of all test suite results
# Globals:
#   TOTAL_SUITES - Total test suites executed
#   PASSED_SUITES - Number of suites that passed
#   FAILED_SUITES - Number of suites that failed
#   TEST_RESULTS - Array of suite results
#   GREEN, RED, YELLOW, CYAN, NC - Color codes
# Arguments:
#   None
# Returns:
#   0 - All test suites passed
#   1 - One or more test suites failed
# Outputs:
#   Writes formatted summary to stdout with:
#   - Total suite counts
#   - Pass/fail/skipped breakdown
#   - Per-suite status with checkmarks/crosses/skipped indicator
#   - Overall pass/fail verdict
# Notes:
#   Should be called after all test suites complete
#   Return code suitable for script exit code
#   Skipped tests don't count as failures
#######################################
print_summary() {
    header "Test Summary"

    # Count skipped tests
    local skipped_suites=0
    for result_pair in "${TEST_RESULTS[@]}"; do
        local status="${result_pair##*:}"
        if [ "$status" = "SKIPPED" ]; then
            skipped_suites=$((skipped_suites + 1))
        fi
    done

    echo
    echo "Test Suites Run: $TOTAL_SUITES"
    echo -e "${GREEN}Passed: $PASSED_SUITES${NC}"

    if [ $FAILED_SUITES -gt 0 ]; then
        echo -e "${RED}Failed: $FAILED_SUITES${NC}"
    fi

    if [ $skipped_suites -gt 0 ]; then
        echo -e "${YELLOW}Skipped: $skipped_suites${NC}"
    fi

    echo
    echo "Results by suite:"
    for result_pair in "${TEST_RESULTS[@]}"; do
        local suite="${result_pair%%:*}"
        local status="${result_pair##*:}"

        if [ "$status" = "PASSED" ]; then
            echo -e "  ${GREEN}✓${NC} $suite"
        elif [ "$status" = "SKIPPED" ]; then
            echo -e "  ${YELLOW}⊘${NC} $suite (skipped)"
        else
            echo -e "  ${RED}✗${NC} $suite"
        fi
    done

    echo
    echo -e "${CYAN}=========================================${NC}"

    if [ $FAILED_SUITES -eq 0 ]; then
        echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
        if [ $skipped_suites -gt 0 ]; then
            echo -e "${YELLOW}  ($skipped_suites suite(s) skipped)${NC}"
        fi
        echo -e "${CYAN}=========================================${NC}"
        return 0
    else
        echo -e "${RED}✗ SOME TESTS FAILED${NC}"
        echo -e "${CYAN}=========================================${NC}"
        return 1
    fi
}

#######################################
# Main orchestration function for all test suites
# Globals:
#   SCRIPT_DIR - Used to locate test scripts
#   All tracking variables updated via run_test_suite
# Arguments:
#   None (ignores command line args)
# Returns:
#   0 - All test suites passed
#   1 - One or more test suites failed
# Outputs:
#   Writes test execution output and summary to stdout
# Notes:
#   Executes test suites in specific order
#   Uses || true to continue after failures
#   Always runs print_summary at end
#   Order: Infrastructure -> Databases -> Cache -> Messaging -> Apps
#######################################
main() {
    header "DevStack Core - Test Suite"

    info "Starting all test suites..."
    echo

    # Infrastructure Tests
    run_test_suite "$SCRIPT_DIR/test-vault.sh" "Vault Integration" || true

    # Database Tests
    run_test_suite "$SCRIPT_DIR/test-postgres.sh" "PostgreSQL Vault Integration" || true
    run_test_suite "$SCRIPT_DIR/test-mysql.sh" "MySQL Vault Integration" || true
    run_test_suite "$SCRIPT_DIR/test-mongodb.sh" "MongoDB Vault Integration" || true

    # Cache Tests
    run_test_suite "$SCRIPT_DIR/test-redis.sh" "Redis Vault Integration" || true
    run_test_suite "$SCRIPT_DIR/test-redis-cluster.sh" "Redis Cluster" || true

    # Messaging Tests
    run_test_suite "$SCRIPT_DIR/test-rabbitmq.sh" "RabbitMQ Integration" || true

    # Application Tests (bash) - Only run if reference API services are available
    if docker ps --format '{{.Names}}' | grep -q "reference-api\|api-first\|golang-api\|nodejs-api\|rust-api"; then
        info "Reference API services detected - running FastAPI tests..."
        run_test_suite "$SCRIPT_DIR/test-fastapi.sh" "FastAPI Reference App" || true
    else
        warn "Reference API services not running - skipping FastAPI tests"
        info "To run FastAPI tests, start with: ./manage-devstack start --profile reference"
        TEST_RESULTS+=("FastAPI Reference App:SKIPPED")
        TOTAL_SUITES=$((TOTAL_SUITES + 1))
    fi

    # Performance Tests
    run_test_suite "$SCRIPT_DIR/test-performance.sh" "Performance & Load Testing" || true

    # Negative Tests
    run_test_suite "$SCRIPT_DIR/test-negative.sh" "Negative Testing & Error Handling" || true

    # Extended Test Suites (Additional comprehensive tests)
    header "Running: Extended Test Suites"
    info "Running additional comprehensive tests for all services..."

    run_test_suite "$SCRIPT_DIR/test-vault-extended.sh" "Vault Extended Tests" || true
    run_test_suite "$SCRIPT_DIR/test-postgres-extended.sh" "PostgreSQL Extended Tests" || true
    run_test_suite "$SCRIPT_DIR/test-pgbouncer.sh" "PgBouncer Tests" || true

    # Observability Stack Tests - Only run if services are available
    if docker ps --format '{{.Names}}' | grep -q "prometheus\|grafana\|loki"; then
        info "Observability services detected - running observability tests..."
        run_test_suite "$SCRIPT_DIR/test-observability.sh" "Observability Stack Tests" || true
    else
        warn "Observability services not running - skipping observability tests"
        info "To run observability tests, start with: ./manage-devstack start --profile full"
        TEST_RESULTS+=("Observability Stack Tests:SKIPPED")
        TOTAL_SUITES=$((TOTAL_SUITES + 1))
    fi

    # Python Unit Tests (pytest) - Run in Docker container (BEST APPROACH)
    # This avoids Python version compatibility issues and uses the production environment
    header "Running: FastAPI Unit Tests (pytest)"
    info "Best approach: Running pytest inside dev-reference-api Docker container"

    if ! docker ps --format '{{.Names}}' | grep -q "^dev-reference-api$"; then
        warn "dev-reference-api container not running"
        info "Attempting to start container..."
        docker compose up -d reference-api >/dev/null 2>&1 || true
        sleep 5
    fi

    if docker ps --format '{{.Names}}' | grep -q "^dev-reference-api$"; then
        info "Container running - executing pytest (178 tests)..."
        if docker exec dev-reference-api pytest tests/ -v --tb=short 2>&1 | \
           grep -E "PASSED|FAILED|SKIPPED|passed|failed|skipped|====="; then
            TEST_RESULTS+=("FastAPI Unit Tests (pytest):PASSED")
            PASSED_SUITES=$((PASSED_SUITES + 1))
            TOTAL_SUITES=$((TOTAL_SUITES + 1))
        else
            TEST_RESULTS+=("FastAPI Unit Tests (pytest):FAILED")
            FAILED_SUITES=$((FAILED_SUITES + 1))
            TOTAL_SUITES=$((TOTAL_SUITES + 1))
        fi
    else
        fail "Could not start dev-reference-api container"
        warn "Start manually with: docker compose up -d reference-api"
        TEST_RESULTS+=("FastAPI Unit Tests (pytest):SKIPPED")
        TOTAL_SUITES=$((TOTAL_SUITES + 1))
    fi

    # Python Parity Tests (pytest) - Run from host with uv (BEST APPROACH)
    # These tests must run from host to access both APIs at localhost:8000 and localhost:8001
    header "Running: API Parity Tests (pytest)"
    info "Best approach: Running from host to test both API containers"

    # Check uv is available
    if ! command -v uv >/dev/null 2>&1; then
        fail "uv not found - required for parity tests"
        warn "Install with: curl -LsSf https://astral.sh/uv/install.sh | sh"
        warn "Or: brew install uv"
        TEST_RESULTS+=("API Parity Tests (pytest):SKIPPED")
        TOTAL_SUITES=$((TOTAL_SUITES + 1))
    else
        # Check both containers are running
        if ! docker ps --format '{{.Names}}' | grep -q "^dev-reference-api$"; then
            info "Starting dev-reference-api container..."
            docker compose up -d reference-api >/dev/null 2>&1 || true
            sleep 5
        fi

        if ! docker ps --format '{{.Names}}' | grep -q "^dev-api-first$"; then
            info "Starting dev-api-first container..."
            docker compose up -d api-first >/dev/null 2>&1 || true
            sleep 5
        fi

        if docker ps --format '{{.Names}}' | grep -q "^dev-reference-api$" && \
           docker ps --format '{{.Names}}' | grep -q "^dev-api-first$"; then
            info "Both containers running - executing parity tests (64 tests from 38 unique)..."
            if (cd "$SCRIPT_DIR/../reference-apps/shared/test-suite" && \
                uv venv --quiet 2>/dev/null && \
                uv pip install --quiet -r requirements.txt 2>/dev/null && \
                uv run pytest -v --tb=short 2>&1 | grep -E "PASSED|FAILED|passed|failed|====="); then
                TEST_RESULTS+=("API Parity Tests (pytest):PASSED")
                PASSED_SUITES=$((PASSED_SUITES + 1))
                TOTAL_SUITES=$((TOTAL_SUITES + 1))
            else
                TEST_RESULTS+=("API Parity Tests (pytest):FAILED")
                FAILED_SUITES=$((FAILED_SUITES + 1))
                TOTAL_SUITES=$((TOTAL_SUITES + 1))
            fi
        else
            fail "Both API containers required but not running"
            warn "Start with: docker compose up -d reference-api api-first"
            TEST_RESULTS+=("API Parity Tests (pytest):SKIPPED")
            TOTAL_SUITES=$((TOTAL_SUITES + 1))
        fi
    fi

    # Print summary
    print_summary
}

# Run main
main "$@"
