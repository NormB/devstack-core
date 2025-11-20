#!/bin/bash
################################################################################
# RabbitMQ Vault Integration Test Suite
#
# DESCRIPTION:
#   Comprehensive test suite for validating RabbitMQ deployment with Vault
#   integration, TLS/SSL support, and message queue operations. Tests use real
#   external clients (Python pika library) to verify connectivity from outside
#   the container, ensuring production-like testing conditions.
#
# GLOBALS:
#   SCRIPT_DIR         - Directory containing this script
#   PROJECT_ROOT       - Root directory of the project
#   RABBITMQ_CLIENT    - Path to RabbitMQ Python client library
#   RED, GREEN, YELLOW, BLUE, NC - Color codes for terminal output
#   TESTS_RUN          - Counter for total tests executed
#   TESTS_PASSED       - Counter for passed tests
#   TESTS_FAILED       - Counter for failed tests
#   FAILED_TESTS       - Array of failed test descriptions
#
# USAGE:
#   ./test-rabbitmq.sh
#
# DEPENDENCIES:
#   - Docker and Docker Compose for container management
#   - uv (Python package manager) for running Python test clients
#   - pika Python library (installed via uv) for RabbitMQ connectivity
#   - curl for Vault API communication
#   - jq for JSON parsing (optional, used for enhanced output)
#   - Vault server running on localhost:8200 with root token
#   - RabbitMQ container (dev-rabbitmq) running
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# NOTES:
#   - This script uses real external client connections (not docker exec)
#     to accurately simulate production access patterns
#   - TLS tests are conditionally executed based on Vault configuration
#   - Tests cover message queuing operations: declare, publish, consume
#   - All operations use Vault-sourced credentials, never plaintext passwords
#   - Tests continue execution even if individual tests fail (|| true)
#   - RabbitMQ uses AMQP protocol on port 5672 (or 5671 for TLS)
#   - Color output can be disabled by redirecting to file or pipe
#
# EXAMPLES:
#   # Run all RabbitMQ tests
#   ./test-rabbitmq.sh
#
#   # Run tests and save output to file
#   ./test-rabbitmq.sh > rabbitmq-test-results.txt 2>&1
#
#   # Run tests with verbose Docker logging
#   DOCKER_VERBOSE=1 ./test-rabbitmq.sh
#
# AUTHOR:
#   DevStack Core Project
#
# SEE ALSO:
#   - lib/rabbitmq_client.py - Python RabbitMQ client used for testing
#   - ../docker/rabbitmq/init.sh - RabbitMQ initialization script
#   - test-fastapi.sh - Tests RabbitMQ integration with FastAPI
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
#   run_python lib/rabbitmq_client.py --test connection
################################################################################
run_python() {
    (cd "$SCRIPT_DIR" && uv run python "$@")
}

RABBITMQ_CLIENT="lib/rabbitmq_client.py"

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
#   $1 - Service name (e.g., "rabbitmq", "postgres", "redis-1")
#
# OUTPUTS:
#   Prints "true" if TLS is enabled, "false" otherwise
#
# RETURNS:
#   0 - Successfully retrieved TLS status
#   1 - Failed to retrieve status (no token or connection error)
#
# EXAMPLE:
#   tls_status=$(get_tls_status_from_vault "rabbitmq")
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
# Test: Verifies RabbitMQ container is running
#
# DESCRIPTION:
#   Checks Docker to ensure the RabbitMQ container (dev-rabbitmq) is in
#   running state.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - RabbitMQ container is running
#   1 - Container is not running
################################################################################
test_rabbitmq_running() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: RabbitMQ container is running"

    if docker ps | grep -q dev-rabbitmq; then
        success "RabbitMQ container is running"
        return 0
    else
        fail "RabbitMQ container is not running"
        return 1
    fi
}

################################################################################
# Test: Verifies RabbitMQ container passes health checks
#
# DESCRIPTION:
#   Uses Docker inspect to check the health status of RabbitMQ container.
#   Health checks are defined in docker-compose.yml and typically test
#   RabbitMQ management interface responsiveness.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - RabbitMQ container reports healthy status
#   1 - Container is unhealthy or health check failing
################################################################################
test_rabbitmq_healthy() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: RabbitMQ is healthy"

    local health=$(docker inspect dev-rabbitmq --format='{{.State.Health.Status}}' 2>/dev/null)

    if [ "$health" = "healthy" ]; then
        success "RabbitMQ is healthy"
        return 0
    else
        fail "RabbitMQ is not healthy (status: $health)"
        return 1
    fi
}

################################################################################
# Test: Verifies RabbitMQ container successfully initialized with Vault
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
#   0 - RabbitMQ container shows Vault integration
#   1 - Container failed Vault initialization
################################################################################
test_rabbitmq_vault_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: RabbitMQ initialized with Vault credentials"

    # Check logs for Vault integration messages
    local logs=$(docker logs dev-rabbitmq 2>&1)

    if echo "$logs" | grep -q "Vault is ready" && \
       echo "$logs" | grep -q "Credentials fetched"; then
        success "RabbitMQ initialized with Vault credentials"
        return 0
    else
        fail "RabbitMQ did not fetch credentials from Vault"
        warn "Check logs: docker logs dev-rabbitmq"
        return 1
    fi
}

################################################################################
# Test: Verifies external client connection to RabbitMQ
#
# DESCRIPTION:
#   Uses external Python client (pika library) to connect to RabbitMQ from
#   outside the container network. Authenticates using Vault-sourced
#   credentials. Tests AMQP protocol on port 5672.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() with error details
#
# RETURNS:
#   0 - Successfully connected to RabbitMQ
#   1 - Connection attempt failed
#
# NOTES:
#   This is a real external connection test, not using docker exec
################################################################################
test_rabbitmq_connection() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Can connect to RabbitMQ with Vault password (real client)"

    # Test connection using Python client (real external connection, not docker exec)
    local result=$(run_python "$RABBITMQ_CLIENT" --test connection 2>&1)

    if echo "$result" | grep -q "✓ connection: success"; then
        success "Connection successful with Vault password (verified from outside container)"
        return 0
    else
        fail "Could not connect to RabbitMQ"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Test: Verifies RabbitMQ version query
#
# DESCRIPTION:
#   Queries RabbitMQ server version using external client. Tests management
#   API accessibility and proper authentication. Displays version information
#   on success.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Version query successful, version displayed
#   1 - Version query failed
#
# NOTES:
#   Uses RabbitMQ management API to retrieve version
################################################################################
test_rabbitmq_version() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: RabbitMQ version query works (real client)"

    # Test version query using Python client
    local result=$(run_python "$RABBITMQ_CLIENT" --test version 2>&1)

    if echo "$result" | grep -q "✓ version: success"; then
        local version=$(echo "$result" | grep "RabbitMQ version:" | head -1)
        success "$version"
        return 0
    else
        fail "Could not query RabbitMQ version"
        return 1
    fi
}

################################################################################
# Test: Verifies RabbitMQ queue operations
#
# DESCRIPTION:
#   Executes basic RabbitMQ operations (queue declare, publish, consume)
#   using external client. Tests core message queuing functionality.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() with error details
#   Creates and deletes temporary test queue
#
# RETURNS:
#   0 - Operations successful
#   1 - Operations failed
#
# NOTES:
#   Tests fundamental AMQP operations
#   Verifies message can be published and consumed
################################################################################
test_rabbitmq_operations() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Can perform queue operations (real client)"

    # Test queue operations using Python client
    local result=$(run_python "$RABBITMQ_CLIENT" --test operations 2>&1)

    if echo "$result" | grep -q "✓ operations: success"; then
        success "Queue declare, publish, and consume successful (verified from outside container)"
        return 0
    else
        fail "Could not perform queue operations"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Test: Verifies SSL/TLS connection availability
#
# DESCRIPTION:
#   Tests whether RabbitMQ accepts SSL/TLS connections using external client.
#   If TLS is enabled in Vault, attempts connection on SSL port (5671) with
#   CA certificate validation.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() if TLS is disabled or CA cert missing
#
# RETURNS:
#   0 - SSL test passed (connected via SSL or SSL disabled)
#   1 - SSL connection test failed or CA cert not found
#
# NOTES:
#   Only runs when TLS is enabled in Vault configuration
#   Requires CA certificate at ~/.config/vault/ca/ca-bundle.pem
################################################################################
test_rabbitmq_tls_available() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: SSL/TLS connection verification (real client)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "rabbitmq")

    if [ "$tls_enabled" = "true" ]; then
        local ca_file="${HOME}/.config/vault/ca/ca-bundle.pem"

        if [ -f "$ca_file" ]; then
            # Test SSL connection on SSL port with SSL enabled
            local result=$(run_python "$RABBITMQ_CLIENT" --port 5671 --test ssl --ssl --ca-cert "$ca_file" 2>&1)

            if echo "$result" | grep -q "✓ ssl: success"; then
                if echo "$result" | grep -q '"connection_type": "SSL/TLS"'; then
                    success "SSL/TLS connection verified from external client"
                    return 0
                else
                    fail "SSL not enabled despite TLS configuration"
                    return 1
                fi
            else
                fail "SSL connection test failed"
                warn "Error: $result"
                return 1
            fi
        else
            fail "CA certificate not found at $ca_file"
            return 1
        fi
    else
        warn "TLS not enabled in Vault - skipping SSL/TLS test"
        success "SSL test skipped (TLS not enabled)"
        return 0
    fi
}

################################################################################
# Test: Verifies SSL certificate validation with CA
#
# DESCRIPTION:
#   If TLS is enabled in Vault, tests SSL connection with CA certificate
#   validation on the SSL port (5671). Verifies connection is actually
#   using TLS encryption.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() if TLS is disabled
#
# RETURNS:
#   0 - SSL certificate validation passed or test skipped (TLS disabled)
#   1 - SSL certificate validation failed or CA cert not found
#
# NOTES:
#   Only runs when TLS is enabled in Vault configuration
#   Requires CA certificate at ~/.config/vault/ca/ca-bundle.pem
################################################################################
test_rabbitmq_ssl_connection() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: SSL certificate verification with CA (if TLS enabled)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "rabbitmq")

    if [ "$tls_enabled" = "true" ]; then
        local ca_file="${HOME}/.config/vault/ca/ca-bundle.pem"

        if [ -f "$ca_file" ]; then
            # Test with SSL enabled and CA verification on SSL port (5671)
            local result=$(run_python "$RABBITMQ_CLIENT" --port 5671 --test ssl --ssl --ca-cert "$ca_file" 2>&1)

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
        warn "TLS not enabled, skipping certificate verification test"
        success "SSL certificate test skipped (TLS not enabled)"
        return 0
    fi
}

################################################################################
# Test: Performs RabbitMQ operations over encrypted TLS connection
#
# DESCRIPTION:
#   If TLS is enabled, executes RabbitMQ operations (declare, publish,
#   consume) over an encrypted connection and verifies the connection is
#   actually using TLS. This confirms end-to-end encrypted message transfer.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() if CA cert missing
#   Creates and deletes temporary test queue over TLS
#
# RETURNS:
#   0 - Encrypted operations successful or test skipped appropriately
#   1 - Encrypted operations failed
#
# NOTES:
#   Only runs when TLS is enabled in Vault
#   Tests actual message transfer (declare/publish/consume) not just connection
#   Verifies connection_type is SSL/TLS in response
################################################################################
test_rabbitmq_encrypted_operations() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: Perform encrypted operations (real SSL/TLS data transfer)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "rabbitmq")

    if [ "$tls_enabled" = "true" ]; then
        local ca_file="${HOME}/.config/vault/ca/ca-bundle.pem"

        if [ -f "$ca_file" ]; then
            # Test queue operations with SSL enabled on SSL port (5671)
            local result=$(run_python "$RABBITMQ_CLIENT" --port 5671 --test operations --ssl --ca-cert "$ca_file" 2>&1)

            if echo "$result" | grep -q "✓ operations: success"; then
                # Verify connection was encrypted
                if echo "$result" | grep -q '"connection_type": "SSL/TLS"'; then
                    success "Queue operations successful over encrypted connection (SSL/TLS verified)"
                    info "  Performed: declare, publish, consume over TLS"
                    return 0
                else
                    fail "Operations succeeded but connection was not encrypted"
                    return 1
                fi
            else
                fail "Queue operations failed over encrypted connection"
                warn "Error: $result"
                return 1
            fi
        else
            warn "CA certificate not found at $ca_file"
            success "Encrypted operations test skipped (no CA certificate)"
            return 0
        fi
    else
        info "TLS not enabled, skipping encrypted operations test"
        success "Encrypted operations test skipped (TLS not enabled)"
        return 0
    fi
}

################################################################################
# Test: Ensures no plaintext passwords in .env file
#
# DESCRIPTION:
#   Security test that verifies .env file does not contain plaintext RabbitMQ
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
#   Looks for RABBITMQ_PASSWORD variable specifically
################################################################################
test_no_plaintext_passwords() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: No plaintext RabbitMQ password in .env"

    if [ -f "$PROJECT_ROOT/.env" ]; then
        # Check if old RABBITMQ_PASSWORD variable exists with a value
        local old_password=$(grep "^RABBITMQ_PASSWORD=" "$PROJECT_ROOT/.env" 2>/dev/null | grep -v "^#" | cut -d= -f2)

        if [ -z "$old_password" ]; then
            success "No plaintext RabbitMQ password in .env"
            return 0
        else
            warn "Found RABBITMQ_PASSWORD in .env (should be removed)"
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
# Executes all RabbitMQ tests and reports results
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
    echo "  RabbitMQ Vault Integration Tests"
    echo "========================================="
    echo

    test_rabbitmq_running || true
    test_rabbitmq_healthy || true
    test_rabbitmq_vault_integration || true
    test_rabbitmq_connection || true
    test_rabbitmq_version || true
    test_rabbitmq_operations || true
    test_rabbitmq_tls_available || true
    test_rabbitmq_ssl_connection || true
    test_rabbitmq_encrypted_operations || true
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
        echo -e "${GREEN}✓ All RabbitMQ tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
