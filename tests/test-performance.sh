#!/bin/bash
################################################################################
# Performance Test Suite
#
# Comprehensive performance and load testing for all development services
# including databases, message queues, secrets management, and APIs. Tests
# measure response times, concurrent connection handling, and system behavior
# under sustained load conditions.
#
# DESCRIPTION:
#   This test suite validates performance characteristics of the development
#   environment by measuring response times for individual operations and
#   testing behavior under load. Each test compares actual performance against
#   predefined thresholds and reports both timing metrics and success rates.
#
# GLOBALS:
#   SCRIPT_DIR              - Directory containing this script
#   PROJECT_ROOT            - Root directory of the project
#   TESTS_RUN               - Counter for total tests executed
#   TESTS_PASSED            - Counter for successful tests
#   TESTS_FAILED            - Counter for failed tests
#   FAILED_TESTS            - Array of failed test names
#   VAULT_THRESHOLD         - Maximum acceptable Vault response time (200ms)
#   API_THRESHOLD           - Maximum acceptable API response time (500ms)
#   DB_QUERY_THRESHOLD      - Maximum acceptable DB query time (1000ms)
#   DB_CONNECTION_THRESHOLD - Maximum acceptable DB connection time (2000ms)
#
# USAGE:
#   ./test-performance.sh
#
#   No command-line arguments are required. The script will automatically:
#   - Detect running services
#   - Skip tests for services that are not running
#   - Execute all applicable performance tests
#   - Report detailed results with timing metrics
#
# DEPENDENCIES:
#   - lib/common.sh: Common test utilities and helper functions
#   - uv: Python package manager for running Python test clients
#   - curl: For HTTP/HTTPS API testing
#   - jq: For JSON response parsing
#   - Docker: For container status checks and operations
#   - Python test clients: postgres_client.py, mysql_client.py, mongodb_client.py,
#     redis_client.py, rabbitmq_client.py
#   - Running services: Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ, FastAPI
#
# EXIT CODES:
#   0 - All tests passed or were skipped (no failures)
#   1 - One or more tests failed
#
# PERFORMANCE THRESHOLDS:
#   - Vault operations:     < 200ms per request
#   - API endpoints:        < 500ms per request
#   - Database queries:     < 1000ms per query
#   - Database connections: < 2000ms per connection
#   - Redis commands:       < 500ms per command
#
# NOTES:
#   - Tests are non-destructive and read-only where possible
#   - Missing services will cause tests to be skipped, not failed
#   - Performance warnings are logged but do not cause test failures
#   - Concurrent connection tests verify connection pooling behavior
#   - Load tests measure both throughput and error rates
#   - All timing measurements use nanosecond precision
#   - Results include both individual and aggregate metrics
#
# EXAMPLES:
#   Run all performance tests:
#     $ ./test-performance.sh
#
#   Run tests and capture output:
#     $ ./test-performance.sh | tee performance-results.log
#
#   Run tests for specific services (by starting only those services):
#     $ docker compose up -d postgres vault
#     $ ./test-performance.sh
#
# AUTHORS:
#   Development Infrastructure Team
#
# VERSION:
#   1.0.0
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load common test library
source "$SCRIPT_DIR/lib/common.sh"

################################################################################
# Helper function to execute Python scripts using uv package manager.
#
# Runs Python scripts from the test directory with proper environment and
# dependency management through uv.
#
# Arguments:
#   $@ - Command-line arguments to pass to Python
#
# Returns:
#   Exit code from the Python script
################################################################################
run_python() {
    (cd "$SCRIPT_DIR" && uv run python "$@")
}

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

# Performance thresholds (milliseconds)
VAULT_THRESHOLD=200
API_THRESHOLD=500
DB_QUERY_THRESHOLD=1000
DB_CONNECTION_THRESHOLD=2000

################################################################################
# Tests Vault API response time for secret retrieval operations.
#
# Measures the time required to retrieve a secret from Vault and compares it
# against the defined threshold. This test validates that Vault is performing
# adequately for production workloads.
#
# Test Details:
#   - Fetches PostgreSQL credentials from Vault KV store
#   - Measures end-to-end HTTP request time
#   - Compares against 200ms threshold
#   - Logs warning if threshold is exceeded but does not fail
#
# Globals:
#   TESTS_RUN - Incremented by 1
#   VAULT_THRESHOLD - Performance threshold (200ms)
#
# Returns:
#   0 - Test passed (query succeeded, timing logged)
#   1 - Test failed (query failed or error occurred)
#   0 - Test skipped (Vault token not available)
#
# Notes:
#   - Requires Vault token at ~/.config/vault/root-token
#   - Slow performance logs warning but does not fail test
#   - Uses nanosecond precision for accurate measurement
################################################################################
test_vault_response_time() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 1: Vault API response time"

    local vault_addr="http://localhost:8200"
    local vault_token=$(cat ~/.config/vault/root-token 2>/dev/null)

    if [ -z "$vault_token" ]; then
        warn "Vault token not found, skipping test"
        success "Test skipped (no Vault token)"
        return 0
    fi

    local start=$(date +%s%N)
    local response=$(curl -sf -H "X-Vault-Token: $vault_token" "$vault_addr/v1/secret/data/postgres" 2>/dev/null)
    local exit_code=$?
    local end=$(date +%s%N)

    local duration_ms=$(( (end - start) / 1000000 ))

    if [ $exit_code -eq 0 ] && [ -n "$response" ]; then
        if [ $duration_ms -lt $VAULT_THRESHOLD ]; then
            success "Vault query completed in ${duration_ms}ms (< ${VAULT_THRESHOLD}ms threshold)"
            return 0
        else
            warn "Vault query took ${duration_ms}ms (exceeds ${VAULT_THRESHOLD}ms threshold)"
            success "Performance test completed (slow)"
            return 0
        fi
    else
        fail "Vault query failed"
        return 1
    fi
}

################################################################################
# Tests PostgreSQL query response time.
#
# Measures the time required to execute a version query against PostgreSQL
# and compares it against the database query threshold. This test validates
# that PostgreSQL is responding quickly to basic queries.
#
# Test Details:
#   - Executes version query through Python client
#   - Measures total query execution time including connection overhead
#   - Compares against 1000ms threshold
#   - Logs warning if threshold is exceeded but does not fail
#
# Globals:
#   TESTS_RUN - Incremented by 1
#   DB_QUERY_THRESHOLD - Performance threshold (1000ms)
#
# Returns:
#   0 - Test passed (query succeeded, timing logged)
#   1 - Test failed (query failed or error occurred)
#   0 - Test skipped (PostgreSQL container not running)
#
# Notes:
#   - Requires dev-postgres container to be running
#   - Uses postgres_client.py for database interaction
#   - Includes connection establishment time in measurement
################################################################################
test_postgres_response_time() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 2: PostgreSQL query response time"

    if ! is_container_running "dev-postgres"; then
        warn "PostgreSQL container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local start=$(date +%s%N)
    local result=$(run_python lib/postgres_client.py --test version 2>&1)
    local exit_code=$?
    local end=$(date +%s%N)

    local duration_ms=$(( (end - start) / 1000000 ))

    if [ $exit_code -eq 0 ] && echo "$result" | grep -q "✓ version: success"; then
        if [ $duration_ms -lt $DB_QUERY_THRESHOLD ]; then
            success "PostgreSQL query completed in ${duration_ms}ms (< ${DB_QUERY_THRESHOLD}ms threshold)"
            return 0
        else
            warn "PostgreSQL query took ${duration_ms}ms (exceeds ${DB_QUERY_THRESHOLD}ms threshold)"
            success "Performance test completed (slow)"
            return 0
        fi
    else
        fail "PostgreSQL query failed"
        return 1
    fi
}

################################################################################
# Tests MySQL query response time.
#
# Measures the time required to execute a version query against MySQL
# and compares it against the database query threshold. This test validates
# that MySQL is responding quickly to basic queries.
#
# Test Details:
#   - Executes version query through Python client
#   - Measures total query execution time including connection overhead
#   - Compares against 1000ms threshold
#   - Logs warning if threshold is exceeded but does not fail
#
# Globals:
#   TESTS_RUN - Incremented by 1
#   DB_QUERY_THRESHOLD - Performance threshold (1000ms)
#
# Returns:
#   0 - Test passed (query succeeded, timing logged)
#   1 - Test failed (query failed or error occurred)
#   0 - Test skipped (MySQL container not running)
#
# Notes:
#   - Requires dev-mysql container to be running
#   - Uses mysql_client.py for database interaction
#   - Includes connection establishment time in measurement
################################################################################
test_mysql_response_time() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 3: MySQL query response time"

    if ! is_container_running "dev-mysql"; then
        warn "MySQL container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local start=$(date +%s%N)
    local result=$(run_python lib/mysql_client.py --test version 2>&1)
    local exit_code=$?
    local end=$(date +%s%N)

    local duration_ms=$(( (end - start) / 1000000 ))

    if [ $exit_code -eq 0 ] && echo "$result" | grep -q "✓ version: success"; then
        if [ $duration_ms -lt $DB_QUERY_THRESHOLD ]; then
            success "MySQL query completed in ${duration_ms}ms (< ${DB_QUERY_THRESHOLD}ms threshold)"
            return 0
        else
            warn "MySQL query took ${duration_ms}ms (exceeds ${DB_QUERY_THRESHOLD}ms threshold)"
            success "Performance test completed (slow)"
            return 0
        fi
    else
        fail "MySQL query failed"
        return 1
    fi
}

################################################################################
# Tests MongoDB query response time.
#
# Measures the time required to execute a version query against MongoDB
# and compares it against the database query threshold. This test validates
# that MongoDB is responding quickly to basic queries.
#
# Test Details:
#   - Executes version query through Python client
#   - Measures total query execution time including connection overhead
#   - Compares against 1000ms threshold
#   - Logs warning if threshold is exceeded but does not fail
#
# Globals:
#   TESTS_RUN - Incremented by 1
#   DB_QUERY_THRESHOLD - Performance threshold (1000ms)
#
# Returns:
#   0 - Test passed (query succeeded, timing logged)
#   1 - Test failed (query failed or error occurred)
#   0 - Test skipped (MongoDB container not running)
#
# Notes:
#   - Requires dev-mongodb container to be running
#   - Uses mongodb_client.py for database interaction
#   - Includes connection establishment time in measurement
################################################################################
test_mongodb_response_time() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 4: MongoDB query response time"

    if ! is_container_running "dev-mongodb"; then
        warn "MongoDB container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local start=$(date +%s%N)
    local result=$(run_python lib/mongodb_client.py --test version 2>&1)
    local exit_code=$?
    local end=$(date +%s%N)

    local duration_ms=$(( (end - start) / 1000000 ))

    if [ $exit_code -eq 0 ] && echo "$result" | grep -q "✓ version: success"; then
        if [ $duration_ms -lt $DB_QUERY_THRESHOLD ]; then
            success "MongoDB query completed in ${duration_ms}ms (< ${DB_QUERY_THRESHOLD}ms threshold)"
            return 0
        else
            warn "MongoDB query took ${duration_ms}ms (exceeds ${DB_QUERY_THRESHOLD}ms threshold)"
            success "Performance test completed (slow)"
            return 0
        fi
    else
        fail "MongoDB query failed"
        return 1
    fi
}

################################################################################
# Tests Redis command response time.
#
# Measures the time required to execute an INFO command against Redis
# and compares it against the Redis-specific threshold. This test validates
# that Redis is responding with expected sub-second latency.
#
# Test Details:
#   - Executes INFO command through Python client
#   - Measures total command execution time including connection overhead
#   - Compares against 500ms threshold (Redis should be faster than databases)
#   - Logs warning if threshold is exceeded but does not fail
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (command succeeded, timing logged)
#   1 - Test failed (command failed or error occurred)
#   0 - Test skipped (Redis container not running)
#
# Notes:
#   - Requires dev-redis-1 container to be running
#   - Uses redis_client.py for Redis interaction
#   - Redis has lower threshold (500ms) due to in-memory architecture
################################################################################
test_redis_response_time() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 5: Redis command response time"

    if ! is_container_running "dev-redis-1"; then
        warn "Redis container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local start=$(date +%s%N)
    local result=$(run_python lib/redis_client.py --test info 2>&1)
    local exit_code=$?
    local end=$(date +%s%N)

    local duration_ms=$(( (end - start) / 1000000 ))

    if [ $exit_code -eq 0 ] && echo "$result" | grep -q "✓ info: success"; then
        # Redis should be very fast
        if [ $duration_ms -lt 500 ]; then
            success "Redis command completed in ${duration_ms}ms (< 500ms threshold)"
            return 0
        else
            warn "Redis command took ${duration_ms}ms (exceeds 500ms threshold)"
            success "Performance test completed (slow)"
            return 0
        fi
    else
        fail "Redis command failed"
        return 1
    fi
}

################################################################################
# Tests RabbitMQ operation response time.
#
# Measures the time required to query RabbitMQ version information
# and compares it against the database query threshold. This test validates
# that RabbitMQ is responding quickly to management operations.
#
# Test Details:
#   - Executes version query through Python client
#   - Measures total operation time including connection overhead
#   - Compares against 1000ms threshold
#   - Logs warning if threshold is exceeded but does not fail
#
# Globals:
#   TESTS_RUN - Incremented by 1
#   DB_QUERY_THRESHOLD - Performance threshold (1000ms)
#
# Returns:
#   0 - Test passed (operation succeeded, timing logged)
#   1 - Test failed (operation failed or error occurred)
#   0 - Test skipped (RabbitMQ container not running)
#
# Notes:
#   - Requires dev-rabbitmq container to be running
#   - Uses rabbitmq_client.py for RabbitMQ interaction
#   - Includes connection establishment time in measurement
################################################################################
test_rabbitmq_response_time() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 6: RabbitMQ operation response time"

    if ! is_container_running "dev-rabbitmq"; then
        warn "RabbitMQ container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local start=$(date +%s%N)
    local result=$(run_python lib/rabbitmq_client.py --test version 2>&1)
    local exit_code=$?
    local end=$(date +%s%N)

    local duration_ms=$(( (end - start) / 1000000 ))

    if [ $exit_code -eq 0 ] && echo "$result" | grep -q "✓ version: success"; then
        if [ $duration_ms -lt $DB_QUERY_THRESHOLD ]; then
            success "RabbitMQ operation completed in ${duration_ms}ms (< ${DB_QUERY_THRESHOLD}ms threshold)"
            return 0
        else
            warn "RabbitMQ operation took ${duration_ms}ms (exceeds ${DB_QUERY_THRESHOLD}ms threshold)"
            success "Performance test completed (slow)"
            return 0
        fi
    else
        fail "RabbitMQ operation failed"
        return 1
    fi
}

################################################################################
# Tests FastAPI endpoint response time.
#
# Measures the time required for the FastAPI reference application to respond
# to a root endpoint request. This test validates that the API is responding
# quickly to HTTP requests.
#
# Test Details:
#   - Executes GET request to root endpoint (/)
#   - Measures total HTTP request time
#   - Validates JSON response contains expected 'name' field
#   - Compares against 500ms API threshold
#   - Logs warning if threshold is exceeded but does not fail
#
# Globals:
#   TESTS_RUN - Incremented by 1
#   API_THRESHOLD - Performance threshold (500ms)
#
# Returns:
#   0 - Test passed (request succeeded, timing logged)
#   1 - Test failed (request failed or invalid response)
#   0 - Test skipped (FastAPI container not running)
#
# Notes:
#   - Requires dev-reference-api container to be running
#   - Tests endpoint at http://localhost:8000/
#   - Validates response is valid JSON with expected structure
################################################################################
test_fastapi_response_time() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 7: FastAPI endpoint response time"

    if ! is_container_running "dev-reference-api"; then
        warn "FastAPI container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local url="http://localhost:8000/"

    local start=$(date +%s%N)
    local response=$(curl -sf "$url" 2>/dev/null)
    local exit_code=$?
    local end=$(date +%s%N)

    local duration_ms=$(( (end - start) / 1000000 ))

    if [ $exit_code -eq 0 ] && echo "$response" | jq -e '.name' &>/dev/null; then
        if [ $duration_ms -lt $API_THRESHOLD ]; then
            success "FastAPI endpoint responded in ${duration_ms}ms (< ${API_THRESHOLD}ms threshold)"
            return 0
        else
            warn "FastAPI endpoint took ${duration_ms}ms (exceeds ${API_THRESHOLD}ms threshold)"
            success "Performance test completed (slow)"
            return 0
        fi
    else
        fail "FastAPI endpoint failed"
        return 1
    fi
}

################################################################################
# Tests concurrent database connection handling.
#
# Validates that PostgreSQL can handle multiple simultaneous connections
# and that connection pooling is working correctly. This test simulates
# realistic concurrent access patterns.
#
# Test Details:
#   - Opens 10 parallel database connections
#   - Each connection performs a connection test
#   - Measures total time for all connections to complete
#   - Reports both timing and success rate
#   - All connections must succeed for test to pass
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (all 10 connections succeeded)
#   1 - Test failed (one or more connections failed)
#   0 - Test skipped (PostgreSQL container not running)
#
# Notes:
#   - Uses PostgreSQL for concurrent testing
#   - Spawns background processes for true parallelism
#   - Tests connection pool limits and behavior
#   - Reports timing for complete concurrent operation set
################################################################################
test_concurrent_connections() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 8: Concurrent database connections (10 parallel)"

    if ! is_container_running "dev-postgres"; then
        warn "PostgreSQL container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local start=$(date +%s%N)

    # Run 10 concurrent connections
    local pids=()
    for i in {1..10}; do
        run_python lib/postgres_client.py --test connection >/dev/null 2>&1 &
        pids+=($!)
    done

    # Wait for all to complete
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=$((failed + 1))
        fi
    done

    local end=$(date +%s%N)
    local duration_ms=$(( (end - start) / 1000000 ))

    if [ $failed -eq 0 ]; then
        success "Handled 10 concurrent connections in ${duration_ms}ms (0 failures)"
        return 0
    else
        fail "Failed $failed/10 concurrent connections"
        return 1
    fi
}

################################################################################
# Tests Vault performance under sustained load.
#
# Validates that Vault can handle multiple sequential requests without
# degradation in performance or reliability. This test simulates sustained
# production usage patterns.
#
# Test Details:
#   - Executes 20 sequential secret retrieval requests
#   - Measures total time and calculates average per-request time
#   - Reports both total time and per-request average
#   - All requests must succeed for test to pass
#   - No specific threshold, but reports metrics for analysis
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (all 20 requests succeeded)
#   1 - Test failed (one or more requests failed)
#   0 - Test skipped (Vault token not available)
#
# Notes:
#   - Requires Vault token at ~/.config/vault/root-token
#   - Tests sequential rather than concurrent load
#   - Helps identify performance degradation under sustained use
#   - Reports both aggregate and average timing metrics
################################################################################
test_vault_under_load() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 9: Vault under load (20 sequential requests)"

    local vault_addr="http://localhost:8200"
    local vault_token=$(cat ~/.config/vault/root-token 2>/dev/null)

    if [ -z "$vault_token" ]; then
        warn "Vault token not found, skipping test"
        success "Test skipped (no Vault token)"
        return 0
    fi

    local start=$(date +%s%N)
    local failed=0

    for i in {1..20}; do
        if ! curl -sf -H "X-Vault-Token: $vault_token" "$vault_addr/v1/secret/data/postgres" >/dev/null 2>&1; then
            failed=$((failed + 1))
        fi
    done

    local end=$(date +%s%N)
    local duration_ms=$(( (end - start) / 1000000 ))
    local avg_ms=$((duration_ms / 20))

    if [ $failed -eq 0 ]; then
        success "Vault handled 20 requests in ${duration_ms}ms (avg: ${avg_ms}ms per request, 0 failures)"
        return 0
    else
        fail "Vault failed $failed/20 requests"
        return 1
    fi
}

################################################################################
# Tests FastAPI performance under sustained load.
#
# Validates that the FastAPI application can handle multiple sequential
# requests without degradation in performance or reliability. This test
# simulates sustained production traffic patterns.
#
# Test Details:
#   - Executes 50 sequential HTTP GET requests
#   - Measures total time and calculates average per-request time
#   - Reports both total time and per-request average
#   - All requests must succeed for test to pass
#   - No specific threshold, but reports metrics for analysis
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (all 50 requests succeeded)
#   1 - Test failed (one or more requests failed)
#   0 - Test skipped (FastAPI container not running)
#
# Notes:
#   - Requires dev-reference-api container to be running
#   - Tests sequential rather than concurrent load
#   - Helps identify performance degradation or memory leaks
#   - Reports both aggregate and average timing metrics
################################################################################
test_api_under_load() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Performance Test 10: FastAPI under load (50 sequential requests)"

    if ! is_container_running "dev-reference-api"; then
        warn "FastAPI container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local url="http://localhost:8000/"
    local start=$(date +%s%N)
    local failed=0

    for i in {1..50}; do
        if ! curl -sf "$url" >/dev/null 2>&1; then
            failed=$((failed + 1))
        fi
    done

    local end=$(date +%s%N)
    local duration_ms=$(( (end - start) / 1000000 ))
    local avg_ms=$((duration_ms / 50))

    if [ $failed -eq 0 ]; then
        success "FastAPI handled 50 requests in ${duration_ms}ms (avg: ${avg_ms}ms per request, 0 failures)"
        return 0
    else
        fail "FastAPI failed $failed/50 requests"
        return 1
    fi
}

################################################################################
# Executes all performance tests in sequence.
#
# Main test orchestration function that runs all defined performance tests
# and generates a comprehensive report. Tests are executed in order with
# error handling to ensure all tests run even if some fail.
#
# Test Sequence:
#   1. Vault API response time
#   2. PostgreSQL query response time
#   3. MySQL query response time
#   4. MongoDB query response time
#   5. Redis command response time
#   6. RabbitMQ operation response time
#   7. FastAPI endpoint response time
#   8. Concurrent database connections (10 parallel)
#   9. Vault under load (20 sequential requests)
#   10. FastAPI under load (50 sequential requests)
#
# Globals:
#   TESTS_RUN - Tracks total tests executed
#   TESTS_PASSED - Tracks successful tests
#   TESTS_FAILED - Tracks failed tests
#   FAILED_TESTS - Array of failed test names
#
# Returns:
#   0 - All tests passed or were skipped
#   1 - One or more tests failed
#
# Notes:
#   - Tests continue running even if individual tests fail
#   - Each test handles its own service availability checks
#   - Final report includes pass/fail counts and timing metrics
#   - Uses test_suite_setup and test_suite_teardown from common.sh
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  Performance Test Suite"
    echo "========================================="
    echo

    test_suite_setup "Performance"

    test_vault_response_time || true
    test_postgres_response_time || true
    test_mysql_response_time || true
    test_mongodb_response_time || true
    test_redis_response_time || true
    test_rabbitmq_response_time || true
    test_fastapi_response_time || true
    test_concurrent_connections || true
    test_vault_under_load || true
    test_api_under_load || true

    print_test_results "Performance"

    test_suite_teardown
}

# Main
run_all_tests
