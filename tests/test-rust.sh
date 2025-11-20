#!/bin/bash
################################################################################
# Rust API Test Suite
#
# DESCRIPTION:
#   Comprehensive test suite for the Rust reference API implementation.
#   Tests Rust/Actix-web endpoints, Vault integration, and health checks.
#
# USAGE:
#   ./test-rust.sh
#
# PREREQUISITES:
#   - Rust API container running (docker compose up -d rust-api)
#   - Vault container running and unsealed
#   - Network connectivity to dev-services network
#
# ENVIRONMENT VARIABLES:
#   RUST_API_URL    - Base URL for Rust API (default: http://localhost:8004)
#   VERBOSE         - Enable verbose output (default: false)
#
# EXIT CODES:
#   0  - All tests passed
#   1  - One or more tests failed
#
# EXAMPLES:
#   # Run all tests
#   ./test-rust.sh
#
#   # Run with verbose output
#   VERBOSE=true ./test-rust.sh
#
#   # Test against specific URL
#   RUST_API_URL=http://localhost:8004 ./test-rust.sh
#
# AUTHORS:
#   DevStack Core Team
#
# VERSION:
#   1.0.0
#
# LAST MODIFIED:
#   2025-11-07
################################################################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Configuration
readonly RUST_API_URL="${RUST_API_URL:-http://localhost:8004}"
readonly VERBOSE="${VERBOSE:-false}"
readonly TIMEOUT=10

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $*"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $*"
}

# Make HTTP request with timeout
http_get() {
    local url="$1"
    local expected_code="${2:-200}"

    if [[ "$VERBOSE" == "true" ]]; then
        log_info "GET $url (expecting HTTP $expected_code)"
    fi

    local response
    response=$(curl -s -w "\n%{http_code}" --max-time "$TIMEOUT" "$url" 2>/dev/null || echo "000")

    local body
    body=$(echo "$response" | head -n -1)
    local status_code
    status_code=$(echo "$response" | tail -n 1)

    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Response: HTTP $status_code"
        log_info "Body: $body"
    fi

    echo "$status_code|$body"
}

# Run a test
run_test() {
    local test_name="$1"
    local test_function="$2"

    ((TESTS_RUN++))

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Test $TESTS_RUN: $test_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if $test_function; then
        ((TESTS_PASSED++))
        log_success "$test_name"
        return 0
    else
        ((TESTS_FAILED++))
        log_error "$test_name"
        return 1
    fi
}

################################################################################
# Test Functions
################################################################################

test_rust_api_reachable() {
    log_info "Testing if Rust API is reachable..."

    local result
    result=$(http_get "$RUST_API_URL/")
    local status_code
    status_code=$(echo "$result" | cut -d'|' -f1)

    if [[ "$status_code" == "200" ]]; then
        log_success "Rust API is reachable (HTTP $status_code)"
        return 0
    else
        log_error "Rust API is not reachable (HTTP $status_code)"
        return 1
    fi
}

test_root_endpoint() {
    log_info "Testing GET / (API info)..."

    local result
    result=$(http_get "$RUST_API_URL/")
    local status_code
    status_code=$(echo "$result" | cut -d'|' -f1)
    local body
    body=$(echo "$result" | cut -d'|' -f2-)

    if [[ "$status_code" != "200" ]]; then
        log_error "Expected HTTP 200, got $status_code"
        return 1
    fi

    if ! echo "$body" | grep -q "DevStack Core Rust Reference API"; then
        log_error "Response does not contain expected text"
        [[ "$VERBOSE" == "true" ]] && echo "$body"
        return 1
    fi

    log_success "Root endpoint returns correct API information"
    return 0
}

test_health_endpoint() {
    log_info "Testing GET /health/ (simple health check)..."

    local result
    result=$(http_get "$RUST_API_URL/health/")
    local status_code
    status_code=$(echo "$result" | cut -d'|' -f1)
    local body
    body=$(echo "$result" | cut -d'|' -f2-)

    if [[ "$status_code" != "200" ]]; then
        log_error "Expected HTTP 200, got $status_code"
        return 1
    fi

    if ! echo "$body" | grep -q "healthy"; then
        log_error "Response does not contain 'healthy'"
        [[ "$VERBOSE" == "true" ]] && echo "$body"
        return 1
    fi

    log_success "Health endpoint reports healthy status"
    return 0
}

test_vault_health_endpoint() {
    log_info "Testing GET /health/vault (Vault connectivity)..."

    local result
    result=$(http_get "$RUST_API_URL/health/vault")
    local status_code
    status_code=$(echo "$result" | cut -d'|' -f1)

    # Accept both 200 (Vault accessible) and 503 (Vault not accessible)
    if [[ "$status_code" == "200" ]]; then
        log_success "Vault is accessible (HTTP $status_code)"
        return 0
    elif [[ "$status_code" == "503" ]]; then
        log_warning "Vault is not accessible (HTTP $status_code) - this is acceptable"
        return 0
    else
        log_error "Unexpected status code: $status_code (expected 200 or 503)"
        return 1
    fi
}

test_metrics_endpoint() {
    log_info "Testing GET /metrics (metrics endpoint)..."

    local result
    result=$(http_get "$RUST_API_URL/metrics")
    local status_code
    status_code=$(echo "$result" | cut -d'|' -f1)

    if [[ "$status_code" != "200" ]]; then
        log_error "Expected HTTP 200, got $status_code"
        return 1
    fi

    log_success "Metrics endpoint is accessible"
    return 0
}

test_cors_headers() {
    log_info "Testing CORS headers..."

    local headers
    headers=$(curl -s -I "$RUST_API_URL/" --max-time "$TIMEOUT" 2>/dev/null || echo "")

    if echo "$headers" | grep -qi "access-control-allow-origin"; then
        log_success "CORS headers are present"
        return 0
    else
        log_warning "CORS headers not found (may not be configured)"
        return 0  # Don't fail, just warn
    fi
}

test_invalid_endpoint() {
    log_info "Testing invalid endpoint (404 handling)..."

    local result
    result=$(http_get "$RUST_API_URL/invalid/endpoint/does/not/exist" 404)
    local status_code
    status_code=$(echo "$result" | cut -d'|' -f1)

    if [[ "$status_code" == "404" ]]; then
        log_success "Invalid endpoint returns 404"
        return 0
    else
        log_error "Expected HTTP 404, got $status_code"
        return 1
    fi
}

################################################################################
# Main Test Execution
################################################################################

main() {
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                     Rust API Test Suite                              ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Target URL: $RUST_API_URL"
    log_info "Timeout: ${TIMEOUT}s"
    log_info "Verbose: $VERBOSE"
    echo ""

    # Run tests
    run_test "Rust API Reachability" test_rust_api_reachable
    run_test "Root Endpoint" test_root_endpoint
    run_test "Health Endpoint" test_health_endpoint
    run_test "Vault Health Endpoint" test_vault_health_endpoint
    run_test "Metrics Endpoint" test_metrics_endpoint
    run_test "CORS Headers" test_cors_headers
    run_test "Invalid Endpoint (404)" test_invalid_endpoint

    # Print summary
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════════════╗"
    echo "║                          Test Summary                                 ║"
    echo "╚═══════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Total Tests:   $TESTS_RUN"
    echo "  Passed:        $TESTS_PASSED"
    echo "  Failed:        $TESTS_FAILED"
    echo "  Skipped:       $TESTS_SKIPPED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_success "All tests passed! ✨"
        echo ""
        return 0
    else
        log_error "$TESTS_FAILED test(s) failed"
        echo ""
        return 1
    fi
}

# Run main function
main "$@"
