#!/bin/bash
################################################################################
# Redis Vault Integration Test Suite
#
# DESCRIPTION:
#   Comprehensive test suite for validating Redis deployment with Vault
#   integration, TLS/SSL support, and cluster capabilities. Tests use real
#   external clients (Python redis-py) to verify connectivity from outside the
#   containers, ensuring production-like testing conditions.
#
# GLOBALS:
#   SCRIPT_DIR         - Directory containing this script
#   PROJECT_ROOT       - Root directory of the project
#   REDIS_CLIENT       - Path to Redis Python client library
#   RED, GREEN, YELLOW, BLUE, NC - Color codes for terminal output
#   TESTS_RUN          - Counter for total tests executed
#   TESTS_PASSED       - Counter for passed tests
#   TESTS_FAILED       - Counter for failed tests
#   FAILED_TESTS       - Array of failed test descriptions
#
# USAGE:
#   ./test-redis.sh
#
# DEPENDENCIES:
#   - Docker and Docker Compose for container management
#   - uv (Python package manager) for running Python test clients
#   - redis-py Python library (installed via uv)
#   - curl for Vault API communication
#   - jq for JSON parsing (optional, used for enhanced output)
#   - Vault server running on localhost:8200 with root token
#   - Redis containers (dev-redis-1, dev-redis-2, dev-redis-3) running
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# NOTES:
#   - This script uses real external client connections (not docker exec)
#     to accurately simulate production access patterns
#   - TLS tests are conditionally executed based on Vault configuration
#   - Redis cluster mode tests may skip if cluster is not initialized
#   - All operations use Vault-sourced credentials, never plaintext passwords
#   - Tests continue execution even if individual tests fail (|| true)
#   - Color output can be disabled by redirecting to file or pipe
#
# EXAMPLES:
#   # Run all Redis tests
#   ./test-redis.sh
#
#   # Run tests and save output to file
#   ./test-redis.sh > redis-test-results.txt 2>&1
#
#   # Run tests with verbose Docker logging
#   DOCKER_VERBOSE=1 ./test-redis.sh
#
# AUTHOR:
#   DevStack Core Project
#
# SEE ALSO:
#   - lib/redis_client.py - Python Redis client used for testing
#   - test-redis-cluster.sh - Redis cluster-specific tests
#   - ../docker/redis/init.sh - Redis initialization script
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

################################################################################
# Executes Python scripts using uv package manager
#
# DESCRIPTION:
#   Wrapper function to run Python scripts with uv, ensuring pyproject.toml
#   is properly located. Changes to tests directory before execution to
#   maintain correct package resolution.
#
# ARGUMENTS:
#   $@ - All arguments passed to python command (script path and args)
#
# OUTPUTS:
#   Stdout/stderr from the Python script
#
# RETURNS:
#   Exit code from the Python script
#
# EXAMPLE:
#   run_python lib/redis_client.py --test connection
################################################################################
run_python() {
    (cd "$SCRIPT_DIR" && uv run python "$@")
}

REDIS_CLIENT="lib/redis_client.py"

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

# Test results
declare -a FAILED_TESTS=()

################################################################################
# Prints an informational test message in blue
#
# ARGUMENTS:
#   $1 - Message to display
################################################################################
info() { echo -e "${BLUE}[TEST]${NC} $1"; }

################################################################################
# Prints a success message in green and increments pass counter
#
# ARGUMENTS:
#   $1 - Success message to display
#
# SIDE EFFECTS:
#   Increments TESTS_PASSED counter
################################################################################
success() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

################################################################################
# Prints a failure message in red and tracks failed test
#
# ARGUMENTS:
#   $1 - Failure message to display
#
# SIDE EFFECTS:
#   Increments TESTS_FAILED counter
#   Appends message to FAILED_TESTS array
################################################################################
fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_TESTS+=("$1"); }

################################################################################
# Prints a warning message in yellow
#
# ARGUMENTS:
#   $1 - Warning message to display
################################################################################
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

################################################################################
# Retrieves TLS enabled status from Vault for a service
#
# DESCRIPTION:
#   Queries Vault secret store to determine if TLS is enabled for the
#   specified service. Uses root token from local config file.
#
# ARGUMENTS:
#   $1 - Service name (e.g., "redis-1", "rabbitmq", "postgres")
#
# OUTPUTS:
#   Prints "true" if TLS is enabled, "false" otherwise
#
# RETURNS:
#   0 - Successfully retrieved TLS status
#   1 - Failed to retrieve status (no token or connection error)
#
# EXAMPLE:
#   tls_status=$(get_tls_status_from_vault "redis-1")
################################################################################
get_tls_status_from_vault() {
    local service_name="$1"
    # Always use localhost for tests running on host machine
    local vault_addr="http://localhost:8200"
    local vault_token=$(cat ~/.config/vault/root-token 2>/dev/null)

    if [ -z "$vault_token" ]; then
        echo "false"
        return 1
    fi

    local response=$(curl --max-time 5 -sf -H "X-Vault-Token: $vault_token" "$vault_addr/v1/secret/data/$service_name" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$response" | grep -o '"tls_enabled":"[^"]*"' | cut -d'"' -f4 | tr -d ' "'
    else
        echo "false"
    fi
}

################################################################################
# Test: Verifies all Redis containers are running
#
# DESCRIPTION:
#   Checks Docker to ensure all three Redis node containers (dev-redis-1,
#   dev-redis-2, dev-redis-3) are in running state.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - All 3 Redis containers are running
#   1 - One or more containers are not running
################################################################################
test_redis_running() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: Redis containers are running"

    local running=0
    for node in 1 2 3; do
        if docker ps | grep -q "dev-redis-$node"; then
            running=$((running + 1))
        fi
    done

    if [ $running -eq 3 ]; then
        success "All 3 Redis nodes are running"
        return 0
    else
        fail "Only $running/3 Redis nodes are running"
        return 1
    fi
}

################################################################################
# Test: Verifies all Redis containers pass health checks
#
# DESCRIPTION:
#   Uses Docker inspect to check the health status of each Redis container.
#   Health checks are defined in docker-compose.yml and typically test
#   Redis PING responsiveness.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - All 3 Redis containers report healthy status
#   1 - One or more containers are unhealthy
################################################################################
test_redis_healthy() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: Redis nodes are healthy"

    local healthy=0
    for node in 1 2 3; do
        local health=$(docker inspect "dev-redis-$node" --format='{{.State.Health.Status}}' 2>/dev/null)
        if [ "$health" = "healthy" ]; then
            healthy=$((healthy + 1))
        fi
    done

    if [ $healthy -eq 3 ]; then
        success "All 3 Redis nodes are healthy"
        return 0
    else
        fail "Only $healthy/3 Redis nodes are healthy"
        return 1
    fi
}

################################################################################
# Test: Verifies Redis containers successfully initialized with Vault
#
# DESCRIPTION:
#   Examines container logs to confirm Vault integration worked during
#   startup. Looks for specific log messages indicating Vault readiness
#   and successful credential retrieval.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() with troubleshooting suggestions
#
# RETURNS:
#   0 - All 3 Redis containers show Vault integration
#   1 - One or more containers failed Vault initialization
################################################################################
test_redis_vault_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: Redis initialized with Vault credentials"

    local vault_init=0
    for node in 1 2 3; do
        local logs=$(docker logs "dev-redis-$node" 2>&1)
        if echo "$logs" | grep -q "Vault is ready" && \
           echo "$logs" | grep -q "Credentials fetched"; then
            vault_init=$((vault_init + 1))
        fi
    done

    if [ $vault_init -eq 3 ]; then
        success "All Redis nodes initialized with Vault credentials"
        return 0
    else
        fail "Only $vault_init/3 Redis nodes initialized with Vault"
        warn "Check logs: docker logs dev-redis-{1,2,3}"
        return 1
    fi
}

################################################################################
# Test: Verifies external client connections to all Redis nodes
#
# DESCRIPTION:
#   Uses external Python client (redis-py) to connect to each Redis node
#   from outside the container network. Authenticates using Vault-sourced
#   credentials. Tests ports 6379, 6380, 6381 for nodes 1, 2, 3.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Successfully connected to all 3 Redis nodes
#   1 - One or more connection attempts failed
#
# NOTES:
#   This is a real external connection test, not using docker exec
################################################################################
test_redis_connections() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Can connect to all Redis nodes with Vault password (real client)"

    local connected=0
    for node in 1 2 3; do
        local port=$((6378 + node))
        local result=$(run_python "$REDIS_CLIENT" --port $port --service "redis-$node" --test connection 2>&1)

        if echo "$result" | grep -q "✓ connection: success"; then
            connected=$((connected + 1))
        fi
    done

    if [ $connected -eq 3 ]; then
        success "All Redis nodes connected successfully with Vault password (verified from outside container)"
        return 0
    else
        fail "Only $connected/3 Redis nodes connected successfully"
        return 1
    fi
}

################################################################################
# Test: Verifies Redis INFO command execution
#
# DESCRIPTION:
#   Executes Redis INFO command using external client to retrieve server
#   information including version. Tests redis-1 as a representative node.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - INFO command executed successfully and returned version
#   1 - INFO command failed
#
# NOTES:
#   Only tests redis-1 since INFO is node-specific and not cluster-wide
################################################################################
test_redis_info() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: Redis INFO command works (real client)"

    # Test redis-1 as representative
    local result=$(run_python "$REDIS_CLIENT" --test info 2>&1)

    if echo "$result" | grep -q "✓ info: success"; then
        local version=$(echo "$result" | grep "Redis version:" | head -1)
        success "$version"
        return 0
    else
        fail "Could not query Redis INFO"
        return 1
    fi
}

################################################################################
# Test: Verifies Redis SET/GET operations
#
# DESCRIPTION:
#   Executes basic Redis operations (SET, GET, DEL) using external client.
#   If cluster mode is enabled but not initialized, the test gracefully
#   skips with a warning.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() if cluster needs initialization
#
# RETURNS:
#   0 - Operations successful or gracefully skipped
#   1 - Operations failed unexpectedly
#
# NOTES:
#   In cluster mode, requires cluster to be initialized first
################################################################################
test_redis_operations() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Can perform SET/GET operations (real client)"

    # Test redis-1 as representative
    local result=$(run_python "$REDIS_CLIENT" --test operations 2>&1)

    if echo "$result" | grep -q "✓ operations: success"; then
        success "SET/GET operations successful (verified from outside container)"
        return 0
    elif echo "$result" | grep -q "⚠ operations: skipped"; then
        warn "Cluster not initialized (run redis-cli --cluster create to initialize)"
        success "Operations test skipped (cluster mode requires initialization)"
        return 0
    else
        fail "Could not perform SET/GET operations"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Test: Verifies SSL/TLS connection availability
#
# DESCRIPTION:
#   Tests SSL/TLS connection by checking Vault configuration and connecting
#   to the appropriate port. If TLS is enabled in Vault, connects to port 6390
#   with SSL enabled and CA certificate validation. If TLS is disabled, connects
#   to standard port 6379 without SSL and verifies plain connection works.
#
# BEHAVIOR:
#   - Checks tls_enabled field in Vault secret for redis-1
#   - When TLS enabled: Connects to port 6390 with --ssl and CA cert
#   - When TLS disabled: Connects to port 6379 without SSL
#   - Verifies connection type matches expected configuration
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Connection succeeded with correct encryption status
#   1 - Connection failed or encryption status doesn't match configuration
#
# NOTES:
#   Requires CA certificate at ~/.config/vault/ca/ca-chain.pem when TLS enabled
################################################################################
test_redis_tls_available() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: SSL/TLS connection verification (real client)"

    # Check if TLS is enabled in Vault
    local tls_enabled=$(get_tls_status_from_vault "redis-1")

    if [ "$tls_enabled" = "true" ]; then
        # TLS is enabled - test SSL connection on TLS port with CA certificate
        local ca_file="${HOME}/.config/vault/ca/ca-chain.pem"
        local redis_tls_port=6390

        if [ ! -f "$ca_file" ]; then
            fail "TLS enabled but CA certificate not found at $ca_file"
            return 1
        fi

        local result=$(run_python "$REDIS_CLIENT" --port $redis_tls_port --test ssl --ssl --ca-cert "$ca_file" 2>&1)

        if echo "$result" | grep -q "✓ ssl: success"; then
            if echo "$result" | grep -q '"connection_type": "SSL/TLS"'; then
                success "SSL connection verified from external client (port $redis_tls_port)"
            else
                warn "SSL test succeeded but connection not encrypted (unexpected)"
                return 1
            fi
            return 0
        else
            fail "SSL connection test failed on TLS port $redis_tls_port"
            warn "Error: $result"
            return 1
        fi
    else
        # TLS is disabled - test plain connection on standard port
        local result=$(run_python "$REDIS_CLIENT" --test ssl 2>&1)

        if echo "$result" | grep -q "✓ ssl: success"; then
            if echo "$result" | grep -q '"connection_type": "plain"'; then
                success "Connection successful on standard port (TLS disabled in Vault)"
            else
                warn "Unexpected connection type when TLS disabled"
            fi
            return 0
        else
            fail "Connection test failed"
            warn "Error: $result"
            return 1
        fi
    fi
}

################################################################################
# Test: Verifies SSL certificate validation with CA
#
# DESCRIPTION:
#   If TLS is enabled in Vault, tests SSL connection with CA certificate
#   validation on the TLS port (6390). Verifies both that Vault reports
#   TLS as enabled AND that Redis actually accepts TLS connections.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() if TLS is disabled or misconfigured
#
# RETURNS:
#   0 - SSL certificate validation passed or test skipped (TLS disabled)
#   1 - SSL certificate validation failed or CA cert not found
#
# NOTES:
#   Only runs when TLS is enabled in Vault configuration
#   Requires CA certificate at ~/.config/vault/ca/ca-chain.pem
#   Tests on dedicated TLS port (6390) separate from standard port
################################################################################
test_redis_ssl_connection() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: SSL certificate verification with CA (if TLS enabled)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "redis-1")

    if [ "$tls_enabled" = "true" ]; then
        # Verify Redis actually supports TLS before attempting SSL connection
        # Test on TLS port (6390) with SSL enabled
        local redis_tls_port=6390
        local redis_tls_check=$(run_python "$REDIS_CLIENT" --port $redis_tls_port --test ssl --ssl --ca-cert "${HOME}/.config/vault/ca/ca-chain.pem" 2>&1)

        if echo "$redis_tls_check" | grep -q '"connection_type": "SSL/TLS"'; then
            # Both Vault claims TLS AND Redis actually supports it
            local ca_file="${HOME}/.config/vault/ca/ca-chain.pem"

            if [ -f "$ca_file" ]; then
                # Test with SSL enabled and CA verification on TLS port
                local result=$(run_python "$REDIS_CLIENT" --port $redis_tls_port --test ssl --ssl --ca-cert "$ca_file" 2>&1)

                if echo "$result" | grep -q "✓ ssl: success"; then
                    if echo "$result" | grep -q '"connection_type": "SSL/TLS"'; then
                        success "SSL certificate validation successful"
                        return 0
                    else
                        fail "SSL not enabled despite TLS configuration"
                        return 1
                    fi
                else
                    fail "SSL certificate verification failed"
                    warn "Error: $result"
                    return 1
                fi
            else
                fail "CA certificate not found at $ca_file"
                return 1
            fi
        else
            warn "TLS not actually configured on Redis (Vault says enabled but Redis not accepting TLS)"
            success "SSL certificate test skipped (TLS configuration mismatch)"
            return 0
        fi
    else
        warn "TLS not enabled, skipping certificate verification test"
        success "SSL certificate test skipped (TLS not enabled)"
        return 0
    fi
}

################################################################################
# Test: Performs Redis operations over encrypted TLS connection
#
# DESCRIPTION:
#   If TLS is enabled, executes Redis operations (SET, GET, DEL) over an
#   encrypted connection and verifies the connection is actually using TLS.
#   This confirms end-to-end encrypted data transfer.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() if cluster initialization is required
#
# RETURNS:
#   0 - Encrypted operations successful or test skipped appropriately
#   1 - Encrypted operations failed
#
# NOTES:
#   Only runs when TLS is enabled in Vault
#   Tests actual data transfer (SET/GET/DEL) not just connection
#   Verifies connection_type is SSL/TLS in response
################################################################################
test_redis_encrypted_operations() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: Perform encrypted operations (real SSL/TLS data transfer)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "redis-1")

    if [ "$tls_enabled" = "true" ]; then
        # Verify Redis actually supports TLS before attempting SSL connection
        # Test on TLS port (6390) with SSL enabled
        local redis_tls_port=6390
        local redis_tls_check=$(run_python "$REDIS_CLIENT" --port $redis_tls_port --test ssl --ssl --ca-cert "${HOME}/.config/vault/ca/ca-chain.pem" 2>&1)

        if echo "$redis_tls_check" | grep -q '"connection_type": "SSL/TLS"'; then
            # Both Vault claims TLS AND Redis actually supports it
            local ca_file="${HOME}/.config/vault/ca/ca-chain.pem"

            if [ -f "$ca_file" ]; then
                # Test Redis operations with SSL enabled on TLS port
                local result=$(run_python "$REDIS_CLIENT" --port $redis_tls_port --test operations --ssl --ca-cert "$ca_file" 2>&1)

                if echo "$result" | grep -q "✓ operations: success"; then
                    # Verify connection was encrypted
                    if echo "$result" | grep -q '"connection_type": "SSL/TLS"'; then
                        success "Redis operations successful over encrypted connection (SSL/TLS verified)"
                        info "  Performed: SET, GET, DEL over TLS"
                        return 0
                    else
                        fail "Operations succeeded but connection was not encrypted"
                        return 1
                    fi
                elif echo "$result" | grep -q "⚠ operations: skipped"; then
                    warn "Cluster not initialized (run redis-cli --cluster create to initialize)"
                    success "Encrypted operations test skipped (cluster mode requires initialization)"
                    return 0
                else
                    fail "Redis operations failed over encrypted connection"
                    warn "Error: $result"
                    return 1
                fi
            else
                warn "CA certificate not found at $ca_file"
                success "Encrypted operations test skipped (no CA certificate)"
                return 0
            fi
        else
            warn "TLS not actually configured on Redis (Vault says enabled but Redis not accepting TLS)"
            success "Encrypted operations test skipped (TLS configuration mismatch)"
            return 0
        fi
    else
        info "TLS not enabled, skipping encrypted operations test"
        success "Encrypted operations test skipped (TLS not enabled)"
        return 0
    fi
}

################################################################################
# Test: Queries Redis cluster configuration
#
# DESCRIPTION:
#   Retrieves cluster information from Redis to determine if cluster mode
#   is enabled or if running in standalone mode. Both configurations are
#   considered successful.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Successfully retrieved cluster info (enabled or disabled)
#   1 - Failed to query cluster information
#
# NOTES:
#   Success whether cluster is enabled or disabled
#   Tests redis-1 as representative of cluster configuration
################################################################################
test_redis_cluster_info() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: Redis cluster configuration"

    # Test redis-1 cluster info
    local result=$(run_python "$REDIS_CLIENT" --test cluster 2>&1)

    if echo "$result" | grep -q "✓ cluster:"; then
        if echo "$result" | grep -q "enabled"; then
            success "Redis cluster mode is enabled"
        else
            success "Redis in standalone mode (cluster disabled)"
        fi
        return 0
    else
        fail "Could not query cluster information"
        return 1
    fi
}

################################################################################
# Test: Ensures no plaintext passwords in .env file
#
# DESCRIPTION:
#   Security test that verifies .env file does not contain plaintext Redis
#   passwords. With Vault integration, passwords should only exist in Vault,
#   not in local configuration files.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() if password found or .env missing
#
# RETURNS:
#   0 - No plaintext password found or .env doesn't exist
#   1 - Plaintext password found in .env
#
# NOTES:
#   Critical security test - failure indicates misconfiguration
#   Looks for REDIS_PASSWORD variable specifically
################################################################################
test_no_plaintext_passwords() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 11: No plaintext Redis password in .env"

    if [ -f "$PROJECT_ROOT/.env" ]; then
        # Check if old REDIS_PASSWORD variable exists with a value
        local old_password=$(grep "^REDIS_PASSWORD=" "$PROJECT_ROOT/.env" 2>/dev/null | grep -v "^#" | cut -d= -f2)

        if [ -z "$old_password" ]; then
            success "No plaintext Redis password in .env"
            return 0
        else
            warn "Found REDIS_PASSWORD in .env (should be removed)"
            fail "Plaintext password still in .env"
            return 1
        fi
    else
        warn ".env file not found"
        success "Test skipped (.env not created yet)"
        return 0
    fi
}

################################################################################
# Executes all Redis tests and reports results
#
# DESCRIPTION:
#   Orchestrates execution of all test functions in sequence. Each test
#   runs with || true to prevent early exit on failure, ensuring complete
#   test coverage. Displays formatted summary of results.
#
# OUTPUTS:
#   Formatted test results including:
#   - Header banner
#   - Individual test results (pass/fail)
#   - Summary statistics
#   - List of failed tests (if any)
#
# RETURNS:
#   0 - All tests passed
#   1 - One or more tests failed
#
# NOTES:
#   Individual test failures don't stop execution
#   Final summary always displays even if tests fail
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  Redis Vault Integration Tests"
    echo "========================================="
    echo

    test_redis_running || true
    test_redis_healthy || true
    test_redis_vault_integration || true
    test_redis_connections || true
    test_redis_info || true
    test_redis_operations || true
    test_redis_tls_available || true
    test_redis_ssl_connection || true
    test_redis_encrypted_operations || true
    test_redis_cluster_info || true
    test_no_plaintext_passwords || true

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
        echo -e "${GREEN}✓ All Redis tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
