#!/usr/bin/env bash
#
# Automated Service Profile Testing Script
#
# This script runs automated tests for all service profiles to ensure they
# function correctly. It validates service startup, health checks, and basic
# functionality for each profile.
#
# Usage:
#   ./scripts/test-profiles.sh [profile]
#
# Examples:
#   ./scripts/test-profiles.sh           # Test all profiles
#   ./scripts/test-profiles.sh minimal   # Test only minimal profile
#   ./scripts/test-profiles.sh standard  # Test only standard profile
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Test results
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

# Print functions
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}\n"
}

print_test() {
    echo -e "${YELLOW}▶ Testing:${NC} $1"
}

print_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

print_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$1")
}

print_info() {
    echo -e "${BLUE}ℹ INFO:${NC} $1"
}

# Cleanup function
cleanup() {
    print_info "Cleaning up test environment..."
    docker compose down -v > /dev/null 2>&1 || true
    colima stop > /dev/null 2>&1 || true
}

# Test profile service count
test_profile_service_count() {
    local profile=$1
    local expected_count=$2

    print_test "Profile '$profile' service count"

    local actual_count
    actual_count=$(docker compose --profile "$profile" config --services 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$actual_count" -eq "$expected_count" ]]; then
        print_pass "Profile '$profile' has $expected_count services"
        return 0
    else
        print_fail "Profile '$profile': Expected $expected_count services, got $actual_count"
        return 1
    fi
}

# Test profile startup
test_profile_startup() {
    local profile=$1

    print_test "Profile '$profile' startup"

    # Clean environment
    cleanup

    # Start profile
    if ./devstack.py start --profile "$profile" > /tmp/test-profile-startup.log 2>&1; then
        print_pass "Profile '$profile' started successfully"
        return 0
    else
        print_fail "Profile '$profile' failed to start"
        echo "Last 20 lines of startup log:"
        tail -20 /tmp/test-profile-startup.log
        return 1
    fi
}

# Test service health
test_service_health() {
    local profile=$1

    print_test "Profile '$profile' service health"

    # Wait for services to be healthy (max 3 minutes)
    print_info "Waiting up to 3 minutes for services to become healthy..."
    local timeout=180
    local elapsed=0
    local interval=10

    while [[ $elapsed -lt $timeout ]]; do
        sleep $interval
        elapsed=$((elapsed + interval))

        # Check if all services are healthy
        local unhealthy_count
        unhealthy_count=$(docker compose ps --format json 2>/dev/null | jq -r '.Health' | grep -c -E "starting|unhealthy" || true)

        if [[ "$unhealthy_count" -eq 0 ]]; then
            print_pass "All services in profile '$profile' are healthy"
            return 0
        fi

        print_info "Waiting for services... ($elapsed/$timeout seconds)"
    done

    print_fail "Profile '$profile': Some services failed to become healthy within $timeout seconds"
    docker compose ps
    return 1
}

# Test Redis cluster (for standard/full profiles)
test_redis_cluster() {
    local profile=$1

    # Only test for standard and full profiles
    if [[ "$profile" != "standard" && "$profile" != "full" ]]; then
        return 0
    fi

    print_test "Profile '$profile' Redis cluster initialization"

    # Initialize cluster
    if ./devstack.py redis-cluster-init > /tmp/test-redis-cluster.log 2>&1; then
        # Verify cluster
        local cluster_state
        cluster_state=$(docker exec dev-redis-1 redis-cli -a "password123" CLUSTER INFO 2>/dev/null | grep cluster_state | cut -d: -f2 | tr -d '\r\n' || echo "error")

        if [[ "$cluster_state" == "ok" ]]; then
            print_pass "Redis cluster initialized successfully"
            return 0
        else
            print_fail "Redis cluster state is '$cluster_state', expected 'ok'"
            return 1
        fi
    else
        print_fail "Redis cluster initialization failed"
        tail -20 /tmp/test-redis-cluster.log
        return 1
    fi
}

# Test minimal profile
test_minimal_profile() {
    print_header "Testing Minimal Profile"

    test_profile_service_count "minimal" 5 || true
    test_profile_startup "minimal" || true
    test_service_health "minimal" || true

    # Test Redis standalone mode
    print_test "Redis standalone mode"
    local cluster_enabled
    cluster_enabled=$(docker exec dev-redis-1 redis-cli INFO cluster 2>/dev/null | grep cluster_enabled | cut -d: -f2 | tr -d '\r\n' || echo "error")

    if [[ "$cluster_enabled" == "0" ]]; then
        print_pass "Redis in standalone mode"
    else
        print_fail "Redis cluster enabled in minimal profile (should be standalone)"
    fi

    cleanup
}

# Test standard profile
test_standard_profile() {
    print_header "Testing Standard Profile"

    test_profile_service_count "standard" 10 || true
    test_profile_startup "standard" || true
    test_service_health "standard" || true
    test_redis_cluster "standard" || true

    # Test all databases accessible
    print_test "Database connectivity"

    local all_dbs_ok=true

    if docker exec dev-postgres pg_isready -U dev_admin > /dev/null 2>&1; then
        print_pass "PostgreSQL accessible"
    else
        print_fail "PostgreSQL not accessible"
        all_dbs_ok=false
    fi

    if docker exec dev-mysql mysqladmin ping > /dev/null 2>&1; then
        print_pass "MySQL accessible"
    else
        print_fail "MySQL not accessible"
        all_dbs_ok=false
    fi

    if docker exec dev-mongodb mongosh --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
        print_pass "MongoDB accessible"
    else
        print_fail "MongoDB not accessible"
        all_dbs_ok=false
    fi

    cleanup
}

# Test full profile
test_full_profile() {
    print_header "Testing Full Profile"

    test_profile_service_count "full" 18 || true
    test_profile_startup "full" || true
    test_service_health "full" || true
    test_redis_cluster "full" || true

    # Test observability services
    print_test "Observability services"

    if curl -s http://localhost:9090/-/ready > /dev/null 2>&1; then
        print_pass "Prometheus accessible"
    else
        print_fail "Prometheus not accessible"
    fi

    if curl -s http://localhost:3001/api/health > /dev/null 2>&1; then
        print_pass "Grafana accessible"
    else
        print_fail "Grafana not accessible"
    fi

    if curl -s http://localhost:3100/ready > /dev/null 2>&1; then
        print_pass "Loki accessible"
    else
        print_fail "Loki not accessible"
    fi

    cleanup
}

# Test reference profile
test_reference_profile() {
    print_header "Testing Reference Profile (Combined with Standard)"

    # Reference profile must be combined with standard/full
    test_profile_service_count "reference" 5 || true

    print_test "Starting standard + reference profiles"
    cleanup

    if ./devstack.py start --profile standard --profile reference > /tmp/test-reference-startup.log 2>&1; then
        print_pass "Standard + reference profiles started"
    else
        print_fail "Failed to start standard + reference profiles"
        tail -20 /tmp/test-reference-startup.log
        cleanup
        return 1
    fi

    # Wait for services
    sleep 30

    # Test reference APIs
    print_test "Reference API accessibility"

    local apis_ok=true

    for port in 8000 8001 8002 8003 8004; do
        if curl -s http://localhost:$port/health > /dev/null 2>&1; then
            print_pass "API on port $port accessible"
        else
            print_fail "API on port $port not accessible"
            apis_ok=false
        fi
    done

    cleanup
}

# Main test function
run_tests() {
    local profile="${1:-all}"

    cd "$PROJECT_ROOT" || exit 1

    print_header "Service Profile Automated Testing"
    print_info "Testing profile: $profile"
    print_info "Project root: $PROJECT_ROOT"

    # Verify prerequisites
    print_info "Checking prerequisites..."

    if ! command -v docker > /dev/null 2>&1; then
        echo "Error: docker not found"
        exit 1
    fi

    if ! command -v colima > /dev/null 2>&1; then
        echo "Error: colima not found"
        exit 1
    fi

    if [[ ! -f "./devstack.py" ]]; then
        echo "Error: devstack.py not found"
        exit 1
    fi

    # Run tests based on profile
    case "$profile" in
        minimal)
            test_minimal_profile
            ;;
        standard)
            test_standard_profile
            ;;
        full)
            test_full_profile
            ;;
        reference)
            test_reference_profile
            ;;
        all)
            test_minimal_profile
            test_standard_profile
            test_full_profile
            test_reference_profile
            ;;
        *)
            echo "Error: Unknown profile '$profile'"
            echo "Valid profiles: minimal, standard, full, reference, all"
            exit 1
            ;;
    esac

    # Print summary
    print_header "Test Summary"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"

    if [[ $TESTS_FAILED -gt 0 ]]; then
        echo -e "\n${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        exit 1
    else
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    fi
}

# Handle script interruption
trap cleanup EXIT INT TERM

# Run tests
run_tests "${1:-all}"
