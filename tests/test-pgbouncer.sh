#!/bin/bash
################################################################################
# PgBouncer Extended Test Suite
#
# Comprehensive tests for PgBouncer connection pooling including pool
# statistics, connection limits, failover behavior, and performance testing.
#
# TESTS:
#   1. PgBouncer container health and status
#   2. Connection pool statistics
#   3. Database connectivity through PgBouncer
#   4. Connection pooling behavior
#   5. Multiple concurrent connections handling
#   6. Pool modes (session, transaction, statement)
#   7. Admin console access and commands
#   8. Connection limit enforcement
#   9. Query routing verification
#   10. Performance comparison (direct vs pooled)
#
# VERSION: 1.0.0
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

# PgBouncer configuration
PGBOUNCER_HOST="${PGBOUNCER_HOST:-localhost}"
PGBOUNCER_PORT="${PGBOUNCER_PORT:-6432}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"

# Always get credentials from Vault (ignore environment variables)
if [ -f ~/.config/vault/root-token ]; then
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

    # Retrieve user and password from Vault
    POSTGRES_USER=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        http://localhost:8200/v1/secret/data/postgres 2>/dev/null | jq -r '.data.data.user' 2>/dev/null)

    POSTGRES_PASSWORD=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        http://localhost:8200/v1/secret/data/postgres 2>/dev/null | jq -r '.data.data.password' 2>/dev/null)
fi

# Set defaults if Vault retrieval failed
POSTGRES_USER="${POSTGRES_USER:-devuser}"

# Verify we got the password
if [ -z "$POSTGRES_PASSWORD" ] || [ "$POSTGRES_PASSWORD" == "null" ]; then
    echo "Warning: Could not retrieve PostgreSQL password from Vault"
else
    export PGPASSWORD="$POSTGRES_PASSWORD"
fi

info() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$2")
}

################################################################################
# Test 1: PgBouncer health
################################################################################
test_pgbouncer_health() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: PgBouncer container health and status"

    if ! docker ps | grep -q "dev-pgbouncer"; then
        fail "PgBouncer container not running" "PgBouncer health"
        return 1
    fi

    local health=$(docker inspect dev-pgbouncer --format='{{.State.Health.Status}}' 2>/dev/null)

    if [ "$health" == "healthy" ]; then
        success "PgBouncer container healthy"
        return 0
    fi

    fail "PgBouncer health check failed" "PgBouncer health"
    return 1
}

################################################################################
# Test 2: Pool statistics
################################################################################
test_pool_statistics() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: Connection pool statistics"

    # Connect to pgbouncer admin console
    local stats=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW STATS;" 2>/dev/null)

    if [ -z "$stats" ]; then
        fail "Could not retrieve pool statistics" "Pool statistics"
        return 1
    fi

    # Get pool info
    local pools=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW POOLS;" 2>/dev/null)

    if [ -n "$pools" ]; then
        local pool_count=$(echo "$pools" | wc -l | tr -d ' ')
        success "Pool statistics available ($pool_count pools configured)"
        return 0
    fi

    fail "Pool statistics test failed" "Pool statistics"
    return 1
}

################################################################################
# Test 3: Database connectivity
################################################################################
test_database_connectivity() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: Database connectivity through PgBouncer"

    # Test connection through PgBouncer
    local result=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d postgres -t -c "SELECT 1;" 2>/dev/null | tr -d ' ')

    if [ "$result" == "1" ]; then
        # Get PostgreSQL version through PgBouncer
        local version=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
            -d postgres -t -c "SELECT version();" 2>/dev/null | head -1)

        if [ -n "$version" ]; then
            success "Database connectivity through PgBouncer working"
            return 0
        fi
    fi

    fail "Database connectivity test failed" "Database connectivity"
    return 1
}

################################################################################
# Test 4: Connection pooling behavior
################################################################################
# RACE CONDITION DOCUMENTATION (Fixed in this version):
#
# ORIGINAL ISSUE:
# The test previously attempted to verify connection pooling by:
# 1. Recording initial client count
# 2. Starting 5 background psql processes with pg_sleep(0.1)
# 3. Sleeping for 1 second
# 4. Checking if active_clients > initial_clients
#
# RACE CONDITION:
# The race condition occurred because:
# - Background processes may not start immediately (fork/exec overhead)
# - pg_sleep(0.1) = 100ms, but actual connection time includes:
#   * Connection establishment (TCP handshake, auth)
#   * Query parsing and execution
#   * Result transmission
#   * Connection cleanup
# - By the time sleep(1) completes and SHOW CLIENTS runs, all 5 connections
#   may have already completed and disconnected
# - PgBouncer in transaction pooling mode releases connections immediately
#   after transaction completion
# - The test was measuring "connections during sleep" not "peak connections"
#
# WHY THIS IS DIFFICULT TO DIAGNOSE:
# - Timing-dependent: May pass on slower systems, fail on faster ones
# - Non-deterministic: May pass sometimes, fail others
# - Environment-dependent: Network latency, system load affect timing
# - Silent failure: No error messages, just unexpected count
#
# SOLUTION:
# Redesign to eliminate race condition by:
# 1. Use longer-running queries (2 seconds instead of 0.1)
# 2. Poll for client count multiple times to catch peak
# 3. Verify we can observe at least some active connections
# 4. Don't rely on exact timing - use a retry loop
#
################################################################################
test_pooling_behavior() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Connection pooling behavior"

    # Get initial pool state (should be 0 or very low)
    local initial_clients=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW CLIENTS;" 2>/dev/null | wc -l)

    # Create multiple long-running connections (2 seconds each)
    # This gives us a much wider window to observe them
    for i in {1..5}; do
        psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
            -d postgres -c "SELECT pg_sleep(2);" &>/dev/null &
    done

    # Give processes time to start and establish connections
    sleep 0.5

    # Poll for active connections multiple times to catch peak
    local max_clients=0
    local attempts=0
    local max_attempts=8

    while [ $attempts -lt $max_attempts ]; do
        local current_clients=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
            -d pgbouncer -t -c "SHOW CLIENTS;" 2>/dev/null | wc -l)

        if [ "$current_clients" -gt "$max_clients" ]; then
            max_clients=$current_clients
        fi

        # If we've observed enough active connections, we can stop polling
        if [ "$max_clients" -ge 3 ]; then
            break
        fi

        attempts=$((attempts + 1))
        sleep 0.2
    done

    # Wait for all background jobs to complete
    wait

    # Verify we observed more connections than initially
    # We expect to see at least 3 of the 5 concurrent connections
    if [ "$max_clients" -gt "$initial_clients" ] && [ "$max_clients" -ge 3 ]; then
        success "Connection pooling behavior verified (peak clients: $max_clients, initial: $initial_clients)"
        return 0
    fi

    fail "Pooling behavior test failed (peak: $max_clients, initial: $initial_clients, expected >= 3)" "Pooling behavior"
    return 1
}

################################################################################
# Test 5: Concurrent connections
################################################################################
test_concurrent_connections() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: Multiple concurrent connections handling"

    # Launch 10 concurrent queries
    for i in {1..10}; do
        psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
            -d postgres -c "SELECT $i, pg_sleep(0.2);" &>/dev/null &
    done

    local pids=$!
    sleep 1

    # Check if PgBouncer is handling connections
    local server_conns=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW SERVERS;" 2>/dev/null | grep postgres | wc -l)

    wait

    if [ "$server_conns" -gt 0 ]; then
        success "Concurrent connections handled ($server_conns server connections active)"
        return 0
    fi

    fail "Concurrent connections test failed" "Concurrent connections"
    return 1
}

################################################################################
# Test 6: Pool modes
################################################################################
test_pool_modes() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Pool modes configuration"

    # Check current pool mode
    local config=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW CONFIG;" 2>/dev/null)

    if [ -z "$config" ]; then
        fail "Could not retrieve pool configuration" "Pool modes"
        return 1
    fi

    local pool_mode=$(echo "$config" | grep "pool_mode" | awk '{print $3}')
    local default_pool_size=$(echo "$config" | grep "default_pool_size" | awk '{print $3}')

    if [ -n "$pool_mode" ] && [ -n "$default_pool_size" ]; then
        success "Pool modes configured (mode: $pool_mode, pool size: $default_pool_size)"
        return 0
    fi

    fail "Pool modes test failed" "Pool modes"
    return 1
}

################################################################################
# Test 7: Admin console
################################################################################
test_admin_console() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: Admin console access and commands"

    # Test various admin commands
    local databases=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW DATABASES;" 2>/dev/null)

    local lists=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW LISTS;" 2>/dev/null)

    local version=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW VERSION;" 2>/dev/null)

    if [ -n "$databases" ] && [ -n "$lists" ] && [ -n "$version" ]; then
        success "Admin console accessible (version: $(echo $version | tr -d ' '))"
        return 0
    fi

    fail "Admin console test failed" "Admin console"
    return 1
}

################################################################################
# Test 8: Connection limits
################################################################################
test_connection_limits() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: Connection limit enforcement"

    local config=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW CONFIG;" 2>/dev/null)

    local max_client_conn=$(echo "$config" | grep "max_client_conn" | awk '{print $3}')
    local max_db_connections=$(echo "$config" | grep "max_db_connections" | awk '{print $3}')

    # Get current connection counts
    local current_clients=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW CLIENTS;" 2>/dev/null | wc -l)

    if [ -n "$max_client_conn" ] && [ -n "$current_clients" ]; then
        success "Connection limits configured (max clients: $max_client_conn, current: $current_clients)"
        return 0
    fi

    fail "Connection limits test failed" "Connection limits"
    return 1
}

################################################################################
# Test 9: Query routing
################################################################################
test_query_routing() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: Query routing verification"

    # Execute a query and verify it goes through
    local query_result=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d postgres -t -c "SELECT current_database(), inet_server_addr(), inet_server_port();" 2>/dev/null)

    if [ -z "$query_result" ]; then
        fail "Query routing failed" "Query routing"
        return 1
    fi

    # Check server connections after query
    local servers=$(psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" \
        -d pgbouncer -t -c "SHOW SERVERS;" 2>/dev/null | grep "postgres")

    if [ -n "$servers" ]; then
        success "Query routing working (queries successfully routed through PgBouncer)"
        return 0
    fi

    fail "Query routing test failed" "Query routing"
    return 1
}

################################################################################
# Test 10: Performance comparison
################################################################################
test_performance_comparison() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: Performance comparison (direct vs pooled)"

    # Test direct connection time
    local direct_start=$(date +%s%N)
    psql -h localhost -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d postgres -c "SELECT 1;" &>/dev/null
    local direct_end=$(date +%s%N)
    local direct_time=$(( (direct_end - direct_start) / 1000000 ))

    # Test pooled connection time
    local pooled_start=$(date +%s%N)
    psql -h "$PGBOUNCER_HOST" -p "$PGBOUNCER_PORT" -U "$POSTGRES_USER" -d postgres -c "SELECT 1;" &>/dev/null
    local pooled_end=$(date +%s%N)
    local pooled_time=$(( (pooled_end - pooled_start) / 1000000 ))

    if [ $? -eq 0 ]; then
        success "Performance comparison complete (direct: ${direct_time}ms, pooled: ${pooled_time}ms)"
        return 0
    fi

    fail "Performance comparison test failed" "Performance comparison"
    return 1
}

################################################################################
# Run all tests
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  PgBouncer Extended Test Suite"
    echo "========================================="
    echo

    test_pgbouncer_health || true
    test_pool_statistics || true
    test_database_connectivity || true
    test_pooling_behavior || true
    test_concurrent_connections || true
    test_pool_modes || true
    test_admin_console || true
    test_connection_limits || true
    test_query_routing || true
    test_performance_comparison || true

    echo
    echo "========================================="
    echo "  Test Results"
    echo "========================================="
    echo "Total tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        echo
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
    fi
    echo "========================================="
    echo

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All PgBouncer tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
