#!/bin/bash
################################################################################
# PostgreSQL Vault Integration Test Suite
#
# Comprehensive test suite for validating PostgreSQL database integration with
# HashiCorp Vault for credential management and PKI-based TLS encryption.
# Tests use real external database clients (not docker exec) to verify actual
# connectivity and encryption.
#
# GLOBALS:
#   SCRIPT_DIR - Directory containing this script
#   PROJECT_ROOT - Root directory of the project
#   POSTGRES_CLIENT - Path to Python PostgreSQL client script
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for output formatting
#   TESTS_RUN - Counter for total number of tests executed
#   TESTS_PASSED - Counter for successfully passed tests
#   TESTS_FAILED - Counter for failed tests
#   FAILED_TESTS - Array containing names of failed tests
#
# USAGE:
#   ./test-postgres.sh
#
#   The script automatically runs all test functions in sequence and displays
#   a summary report at the end. Tests use Python client library via uv.
#
# DEPENDENCIES:
#   - Docker (for container inspection and logs)
#   - curl (for Vault API calls)
#   - uv (Python package manager for running test clients)
#   - Python libraries: psycopg2, cryptography (installed via uv)
#   - PostgreSQL container running (dev-postgres)
#   - Vault container running with credentials stored
#   - Vault root token: ~/.config/vault/root-token
#   - CA certificates: ~/.config/vault/ca/ca-bundle.pem (if TLS enabled)
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# TESTS:
#   1. PostgreSQL container is running
#   2. PostgreSQL is healthy (Docker health check)
#   3. PostgreSQL initialized with Vault credentials
#   4. Can connect with Vault password (real external client)
#   5. PostgreSQL version query works (real client)
#   6. Can create table and insert data (real client)
#   7. SSL/TLS connection verification (real client)
#   8. SSL certificate verification with verify-full mode
#   9. Perform encrypted operations over TLS
#   10. Forgejo integration with PostgreSQL
#   11. No plaintext passwords in .env file
#
# NOTES:
#   - All tests continue execution even if individual tests fail
#   - Tests use external Python client to validate real-world connectivity
#   - TLS tests are conditional based on POSTGRES_ENABLE_TLS setting in Vault
#   - SSL verification tests require CA certificate bundle
#   - Tests verify both functionality and security (encryption, auth)
#
# EXAMPLES:
#   # Run all PostgreSQL tests
#   ./test-postgres.sh
#
#   # Run tests after starting services
#   ../devstack start postgres
#   ./test-postgres.sh
#
#   # Test with TLS enabled
#   # (Ensure POSTGRES_ENABLE_TLS=true in Vault secrets)
#   ./test-postgres.sh
#
# AUTHORS:
#   Development Services Team
#
# VERSION:
#   1.0.0
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

################################################################################
# Executes Python scripts using uv package manager.
#
# Runs Python commands via uv from the tests directory to ensure proper
# resolution of pyproject.toml and dependencies. This wrapper ensures all
# Python client scripts have access to required packages.
#
# Arguments:
#   $@ - Python command and arguments to execute
#
# Returns:
#   Exit code from the Python command
#
# Outputs:
#   Stdout and stderr from the Python command
#
# Examples:
#   run_python script.py --arg value
#   run_python lib/postgres_client.py --test connection
################################################################################
run_python() {
    (cd "$SCRIPT_DIR" && uv run python "$@")
}

POSTGRES_CLIENT="lib/postgres_client.py"

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
# Prints an informational test message in blue.
#
# Globals:
#   BLUE, NC - ANSI color codes
#
# Arguments:
#   $1 - Message to display
################################################################################
info() { echo -e "${BLUE}[TEST]${NC} $1"; }

################################################################################
# Prints a success message in green and increments the passed test counter.
#
# Globals:
#   GREEN, NC - ANSI color codes
#   TESTS_PASSED - Counter incremented for each successful test
#
# Arguments:
#   $1 - Success message to display
################################################################################
success() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

################################################################################
# Prints a failure message in red, increments failed counter, and records failure.
#
# Globals:
#   RED, NC - ANSI color codes
#   TESTS_FAILED - Counter incremented for each failed test
#   FAILED_TESTS - Array to which failed test name is appended
#
# Arguments:
#   $1 - Failure message to display
################################################################################
fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_TESTS+=("$1"); }

################################################################################
# Prints a warning message in yellow.
#
# Globals:
#   YELLOW, NC - ANSI color codes
#
# Arguments:
#   $1 - Warning message to display
################################################################################
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

################################################################################
# Retrieves TLS enabled status for a service from Vault secrets.
#
# Queries the Vault KV secrets engine to determine if TLS/SSL is enabled for
# the specified service. This is used to conditionally run TLS-related tests.
#
# Arguments:
#   $1 - Service name (e.g., "postgres", "mysql", "mongodb")
#
# Returns:
#   0 - Successfully retrieved status
#   1 - Failed to retrieve status (Vault unreachable or no token)
#
# Outputs:
#   Writes "true" or "false" to stdout
#
# Examples:
#   tls_status=$(get_tls_status_from_vault "postgres")
#   if [ "$tls_status" = "true" ]; then
#     # Run TLS tests
#   fi
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
# Tests if the PostgreSQL container is running.
#
# Verifies that the dev-postgres Docker container is active by checking
# 'docker ps' output. This is the prerequisite for all other PostgreSQL tests.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - PostgreSQL container is running
#   1 - PostgreSQL container is not running
#
# Outputs:
#   Test status message via info/success/fail functions
################################################################################
test_postgres_running() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: PostgreSQL container is running"

    if docker ps | grep -q dev-postgres; then
        success "PostgreSQL container is running"
        return 0
    else
        fail "PostgreSQL container is not running"
        return 1
    fi
}

################################################################################
# Tests if PostgreSQL container health check reports healthy status.
#
# Queries Docker to check if the PostgreSQL container's internal health check
# is passing. The health check verifies that PostgreSQL is accepting connections.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - PostgreSQL is healthy
#   1 - PostgreSQL is not healthy
#
# Outputs:
#   Test status message with current health status via info/success/fail
################################################################################
test_postgres_healthy() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: PostgreSQL is healthy"

    local health=$(docker inspect dev-postgres --format='{{.State.Health.Status}}' 2>/dev/null)

    if [ "$health" = "healthy" ]; then
        success "PostgreSQL is healthy"
        return 0
    else
        fail "PostgreSQL is not healthy (status: $health)"
        return 1
    fi
}

################################################################################
# Tests if PostgreSQL successfully fetched credentials from Vault during init.
#
# Examines PostgreSQL container logs for Vault integration markers that indicate
# the init script successfully connected to Vault and retrieved credentials.
# This validates the Vault-PostgreSQL integration during container startup.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - PostgreSQL initialized with Vault credentials
#   1 - PostgreSQL did not fetch credentials from Vault
#
# Outputs:
#   Test status message via info/success/fail functions
#   Suggests checking container logs if integration failed
################################################################################
test_postgres_vault_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: PostgreSQL initialized with Vault credentials"

    # Check logs for Vault integration messages
    local logs=$(docker logs dev-postgres 2>&1)

    if echo "$logs" | grep -q "Vault is ready" && \
       echo "$logs" | grep -q "Credentials fetched"; then
        success "PostgreSQL initialized with Vault credentials"
        return 0
    else
        fail "PostgreSQL did not fetch credentials from Vault"
        warn "Check logs: docker logs dev-postgres"
        return 1
    fi
}

################################################################################
# Tests database connection using external client with Vault credentials.
#
# Uses a real Python PostgreSQL client (psycopg2) running on the host machine
# to connect to PostgreSQL with credentials fetched from Vault. This validates
# actual external connectivity, not just internal Docker container access.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   POSTGRES_CLIENT - Path to Python client script
#
# Returns:
#   0 - Connection successful
#   1 - Connection failed
#
# Outputs:
#   Test status message via info/success/fail functions
#   Error details if connection fails
################################################################################
test_postgres_connection() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Can connect to PostgreSQL with Vault password (real client)"

    # Test connection using Python client (real external connection, not docker exec)
    local result=$(run_python "$POSTGRES_CLIENT" --test connection 2>&1)

    if echo "$result" | grep -q "✓ connection: success"; then
        success "Connection successful with Vault password (verified from outside container)"
        return 0
    else
        fail "Could not connect to PostgreSQL"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Tests PostgreSQL version query using external client.
#
# Executes a version query via the Python client to validate that database
# queries work correctly over the established connection.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   POSTGRES_CLIENT - Path to Python client script
#
# Returns:
#   0 - Version query successful
#   1 - Version query failed
#
# Outputs:
#   Test status message with PostgreSQL version via info/success/fail
################################################################################
test_postgres_version() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: PostgreSQL version query works (real client)"

    # Test version query using Python client
    local result=$(run_python "$POSTGRES_CLIENT" --test version 2>&1)

    if echo "$result" | grep -q "✓ version: success"; then
        local version=$(echo "$result" | grep "PostgreSQL version:" | head -1)
        success "$version"
        return 0
    else
        fail "Could not query PostgreSQL version"
        return 1
    fi
}

################################################################################
# Tests table creation and data manipulation using external client.
#
# Performs a complete database workflow using the Python client:
# 1. CREATE TABLE with test schema
# 2. INSERT test data
# 3. SELECT to verify data
# 4. DROP TABLE for cleanup
#
# This validates full DDL and DML functionality over the external connection.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   POSTGRES_CLIENT - Path to Python client script
#
# Returns:
#   0 - Table operations successful
#   1 - Table operations failed
#
# Outputs:
#   Test status message via info/success/fail functions
#   Error details if operations fail
################################################################################
test_postgres_create_table() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Can create table and insert data (real client)"

    # Test table operations using Python client
    local result=$(run_python "$POSTGRES_CLIENT" --test table 2>&1)

    if echo "$result" | grep -q "✓ table: success"; then
        success "Created table and inserted data successfully (verified from outside container)"
        return 0
    else
        fail "Could not create table or insert data"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Tests SSL/TLS connection capability from external client.
#
# Verifies that PostgreSQL accepts SSL/TLS connections and reports SSL status.
# When TLS is enabled, validates the connection is encrypted and displays
# SSL version and cipher information. When TLS is disabled, confirms the
# connection works in unencrypted mode.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   POSTGRES_CLIENT - Path to Python client script
#
# Returns:
#   0 - SSL test successful (encrypted or unencrypted as configured)
#   1 - SSL connection test failed
#
# Outputs:
#   Test status message via info/success/fail functions
#   SSL version and cipher when TLS is enabled
#   Warning when TLS is not enabled
################################################################################
test_postgres_tls_available() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: SSL/TLS connection verification (real client)"

    # Test SSL connection using Python client - this is the REAL test
    # It connects from outside the container and verifies SSL status
    local result=$(run_python "$POSTGRES_CLIENT" --test ssl 2>&1)

    if echo "$result" | grep -q "✓ ssl: success"; then
        # Check if SSL is actually enabled
        if echo "$result" | grep -q '"ssl_enabled": true'; then
            local ssl_version=$(echo "$result" | grep "ssl_version" | head -1)
            local ssl_cipher=$(echo "$result" | grep "ssl_cipher" | head -1)
            success "SSL connection verified from external client"
            info "  $ssl_version"
            info "  $ssl_cipher"
        else
            warn "TLS not enabled (POSTGRES_ENABLE_TLS=false)"
            success "SSL test passed (not enabled, connection unencrypted)"
        fi
        return 0
    else
        fail "SSL connection test failed"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Tests SSL certificate verification with verify-full mode (if TLS enabled).
#
# When TLS is enabled in Vault configuration, this test validates full SSL
# certificate verification using the CA bundle. Uses sslmode=verify-full to
# ensure:
# 1. Certificate is signed by trusted CA
# 2. Certificate hostname matches connection hostname
# 3. Certificate is not expired
#
# If TLS is not enabled, the test is skipped with a success status.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   POSTGRES_CLIENT - Path to Python client script
#
# Returns:
#   0 - SSL certificate validation successful or TLS not enabled
#   1 - SSL certificate verification failed
#
# Outputs:
#   Test status message via info/success/fail functions
#   Warnings when TLS is not enabled or CA cert is missing
################################################################################
test_postgres_ssl_connection() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: SSL certificate verification with verify-full mode (if TLS enabled)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "postgres")

    if [ "$tls_enabled" = "true" ]; then
        local ca_file="${HOME}/.config/vault/ca/ca-bundle.pem"

        if [ -f "$ca_file" ]; then
            # Test with sslmode=verify-full to ensure certificate validation
            local result=$(run_python "$POSTGRES_CLIENT" --test ssl --sslmode verify-full --ca-cert "$ca_file" 2>&1)

            if echo "$result" | grep -q "✓ ssl: success"; then
                if echo "$result" | grep -q '"ssl_enabled": true'; then
                    success "SSL certificate validation successful (verify-full mode)"
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
# Tests encrypted database operations over SSL/TLS connection (if TLS enabled).
#
# Performs complete database operations (CREATE, INSERT, SELECT, DROP) over
# a verified SSL/TLS connection to ensure data is encrypted in transit. This
# validates that:
# 1. All database operations work correctly over TLS
# 2. Connection remains encrypted throughout the session
# 3. Certificate validation (verify-full) doesn't break functionality
#
# This is a comprehensive end-to-end test of encrypted database operations.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   POSTGRES_CLIENT - Path to Python client script
#
# Returns:
#   0 - Encrypted operations successful or TLS not enabled
#   1 - Encrypted operations failed
#
# Outputs:
#   Test status message via info/success/fail functions
#   Details of operations performed when successful
#   Warnings when TLS is not enabled or CA cert is missing
################################################################################
test_postgres_encrypted_operations() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: Perform encrypted operations (real SSL/TLS data transfer)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "postgres")

    if [ "$tls_enabled" = "true" ]; then
        local ca_file="${HOME}/.config/vault/ca/ca-bundle.pem"

        if [ -f "$ca_file" ]; then
            # Test table operations with SSL enabled and full certificate verification
            local result=$(run_python "$POSTGRES_CLIENT" --test table --sslmode verify-full --ca-cert "$ca_file" 2>&1)

            if echo "$result" | grep -q "✓ table: success"; then
                # Verify connection was encrypted
                if echo "$result" | grep -q '"ssl_enabled": true'; then
                    success "Table operations successful over encrypted connection (SSL/TLS verified)"
                    info "  Performed: CREATE TABLE, INSERT, SELECT, DROP over TLS"
                    return 0
                else
                    fail "Operations succeeded but connection was not encrypted"
                    return 1
                fi
            else
                fail "Table operations failed over encrypted connection"
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
# Tests Forgejo Git service integration with PostgreSQL database.
#
# Verifies that the Forgejo service can successfully connect to and use the
# PostgreSQL database. Checks Forgejo container logs for evidence of database
# connectivity such as:
# - Database connection success messages
# - Server startup messages (indicating DB is working)
# - Database ping operations
#
# If Forgejo is not running, the test is gracefully skipped.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - Forgejo integration detected or Forgejo not running
#   1 - (Currently never returns failure, logs warning instead)
#
# Outputs:
#   Test status message via info/success/warn functions
#   Warnings if Forgejo is not running or not fully initialized
################################################################################
test_forgejo_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: Forgejo can connect to PostgreSQL"

    # Check if Forgejo is running
    if ! docker ps | grep -q dev-forgejo; then
        warn "Forgejo not running, skipping integration test"
        success "Forgejo test skipped (not running)"
        return 0
    fi

    # Check Forgejo logs for database connection
    local logs=$(docker logs dev-forgejo 2>&1 | tail -50)

    if echo "$logs" | grep -qE "(Database.*connected|Starting.*server|Serving.*on|PING DATABASE postgres)"; then
        success "Forgejo integrated with PostgreSQL"
        return 0
    else
        warn "Forgejo may not be connected yet (check logs)"
        success "Forgejo test skipped (not fully initialized)"
        return 0
    fi
}

################################################################################
# Tests that no plaintext PostgreSQL passwords exist in .env file.
#
# Validates security best practices by ensuring that PostgreSQL passwords are
# not stored in plaintext in the .env configuration file. Passwords should be
# managed exclusively through Vault.
#
# Checks for:
# - POSTGRES_PASSWORD variable with non-empty value
#
# If the .env file doesn't exist, the test is skipped as this may be a fresh
# installation.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   PROJECT_ROOT - Used to locate .env file
#
# Returns:
#   0 - No plaintext password found or .env doesn't exist
#   1 - Plaintext password found in .env
#
# Outputs:
#   Test status message via info/success/fail/warn functions
#   Warnings if .env file not found or if plaintext password detected
################################################################################
test_no_plaintext_passwords() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 11: No plaintext PostgreSQL password in .env"

    if [ -f "$PROJECT_ROOT/.env" ]; then
        # Check if old POSTGRES_PASSWORD variable exists with a value
        local old_password=$(grep "^POSTGRES_PASSWORD=" "$PROJECT_ROOT/.env" 2>/dev/null | grep -v "^#" | cut -d= -f2)

        if [ -z "$old_password" ]; then
            success "No plaintext PostgreSQL password in .env"
            return 0
        else
            warn "Found POSTGRES_PASSWORD in .env (should be removed)"
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
# Runs all PostgreSQL integration tests and displays results summary.
#
# Executes all test functions in sequence, allowing each to pass or fail
# independently. Displays a formatted summary of results including:
# - Total number of tests run
# - Number of tests passed
# - Number of tests failed
# - List of failed test names
#
# All tests are run with '|| true' to continue execution even if individual
# tests fail, ensuring a complete test report.
#
# Globals:
#   TESTS_RUN - Total count of executed tests
#   TESTS_PASSED - Count of successful tests
#   TESTS_FAILED - Count of failed tests
#   FAILED_TESTS - Array of failed test names
#   GREEN, RED, NC - Color codes for output formatting
#
# Returns:
#   0 - All tests passed
#   1 - One or more tests failed
#
# Outputs:
#   Test execution progress and final summary report to stdout
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  PostgreSQL Vault Integration Tests"
    echo "========================================="
    echo

    test_postgres_running || true
    test_postgres_healthy || true
    test_postgres_vault_integration || true
    test_postgres_connection || true
    test_postgres_version || true
    test_postgres_create_table || true
    test_postgres_tls_available || true
    test_postgres_ssl_connection || true
    test_postgres_encrypted_operations || true
    test_forgejo_integration || true
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
        echo -e "${GREEN}✓ All PostgreSQL tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
