#!/bin/bash
################################################################################
# MongoDB Vault Integration Test Suite
#
# Comprehensive test suite for validating MongoDB database integration with
# HashiCorp Vault for credential management and PKI-based TLS encryption.
# Tests use real external database clients (not docker exec) to verify actual
# connectivity and encryption.
#
# GLOBALS:
#   SCRIPT_DIR - Directory containing this script
#   PROJECT_ROOT - Root directory of the project
#   MONGODB_CLIENT - Path to Python MongoDB client script
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for output formatting
#   TESTS_RUN - Counter for total number of tests executed
#   TESTS_PASSED - Counter for successfully passed tests
#   TESTS_FAILED - Counter for failed tests
#   FAILED_TESTS - Array containing names of failed tests
#
# USAGE:
#   ./test-mongodb.sh
#
#   The script automatically runs all test functions in sequence and displays
#   a summary report at the end. Tests use Python client library via uv.
#
# DEPENDENCIES:
#   - Docker (for container inspection and logs)
#   - curl (for Vault API calls)
#   - uv (Python package manager for running test clients)
#   - Python libraries: pymongo (installed via uv)
#   - MongoDB container running (dev-mongodb)
#   - Vault container running with credentials stored
#   - Vault root token: ~/.config/vault/root-token
#   - CA certificates: ~/.config/vault/ca/ca-bundle.pem (if TLS enabled)
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# TESTS:
#   1. MongoDB container is running
#   2. MongoDB is healthy (Docker health check)
#   3. MongoDB initialized with Vault credentials
#   4. Can connect with Vault password (real external client)
#   5. MongoDB version query works (real client)
#   6. Can perform document operations (insert, find, delete)
#   7. Can list databases (real client)
#   8. Authentication works (real client)
#   9. SSL/TLS connection verification (real client)
#   10. SSL certificate verification with CA bundle
#   11. Perform encrypted operations over TLS
#   12. No plaintext passwords in .env file
#
# NOTES:
#   - All tests continue execution even if individual tests fail
#   - Tests use external Python client to validate real-world connectivity
#   - TLS tests are conditional based on MONGODB_ENABLE_TLS setting in Vault
#   - MongoDB supports preferTLS mode (accepts both encrypted and unencrypted)
#   - Tests verify both functionality and security (encryption, auth)
#
# EXAMPLES:
#   # Run all MongoDB tests
#   ./test-mongodb.sh
#
#   # Run tests after starting services
#   ../devstack start mongodb
#   ./test-mongodb.sh
#
#   # Test with TLS enabled
#   # (Ensure MONGODB_ENABLE_TLS=true in Vault secrets)
#   ./test-mongodb.sh
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
# Arguments:
#   $@ - Python command and arguments to execute
#
# Returns:
#   Exit code from the Python command
################################################################################
run_python() {
    (cd "$SCRIPT_DIR" && uv run python "$@")
}

MONGODB_CLIENT="lib/mongodb_client.py"

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
# Arguments:
#   $1 - Message to display
################################################################################
info() { echo -e "${BLUE}[TEST]${NC} $1"; }

################################################################################
# Prints a success message and increments passed counter.
#
# Arguments:
#   $1 - Success message to display
################################################################################
success() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

################################################################################
# Prints a failure message and increments failed counter.
#
# Arguments:
#   $1 - Failure message to display
################################################################################
fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_TESTS+=("$1"); }

################################################################################
# Prints a warning message in yellow.
#
# Arguments:
#   $1 - Warning message to display
################################################################################
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

################################################################################
# Retrieves TLS enabled status for a service from Vault secrets.
#
# Arguments:
#   $1 - Service name (e.g., "mongodb")
#
# Returns:
#   0 - Successfully retrieved status
#   1 - Failed to retrieve status
#
# Outputs:
#   Writes "true" or "false" to stdout
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
# Tests if the MongoDB container is running.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - MongoDB container is running
#   1 - MongoDB container is not running
################################################################################
test_mongodb_running() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: MongoDB container is running"

    if docker ps | grep -q dev-mongodb; then
        success "MongoDB container is running"
        return 0
    else
        fail "MongoDB container is not running"
        return 1
    fi
}

################################################################################
# Tests if MongoDB container health check reports healthy status.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - MongoDB is healthy
#   1 - MongoDB is not healthy
################################################################################
test_mongodb_healthy() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: MongoDB is healthy"

    local health=$(docker inspect dev-mongodb --format='{{.State.Health.Status}}' 2>/dev/null)

    if [ "$health" = "healthy" ]; then
        success "MongoDB is healthy"
        return 0
    else
        fail "MongoDB is not healthy (status: $health)"
        return 1
    fi
}

################################################################################
# Tests if MongoDB successfully fetched credentials from Vault during init.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - MongoDB initialized with Vault credentials
#   1 - MongoDB did not fetch credentials from Vault
################################################################################
test_mongodb_vault_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: MongoDB initialized with Vault credentials"

    # Check logs for Vault integration messages
    local logs=$(docker logs dev-mongodb 2>&1)

    if echo "$logs" | grep -q "Vault is ready" && \
       echo "$logs" | grep -q "Credentials fetched"; then
        success "MongoDB initialized with Vault credentials"
        return 0
    else
        fail "MongoDB did not fetch credentials from Vault"
        warn "Check logs: docker logs dev-mongodb"
        return 1
    fi
}

################################################################################
# Tests database connection using external client with Vault credentials.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   MONGODB_CLIENT - Path to Python client script
#
# Returns:
#   0 - Connection successful
#   1 - Connection failed
################################################################################
test_mongodb_connection() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Can connect to MongoDB with Vault password (real client)"

    # Test connection using Python client (real external connection, not docker exec)
    local result=$(run_python "$MONGODB_CLIENT" --test connection 2>&1)

    if echo "$result" | grep -q "✓ connection: success"; then
        success "Connection successful with Vault password (verified from outside container)"
        return 0
    else
        fail "Could not connect to MongoDB"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Tests MongoDB version query using external client.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   MONGODB_CLIENT - Path to Python client script
#
# Returns:
#   0 - Version query successful
#   1 - Version query failed
################################################################################
test_mongodb_version() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: MongoDB version query works (real client)"

    # Test version query using Python client
    local result=$(run_python "$MONGODB_CLIENT" --test version 2>&1)

    if echo "$result" | grep -q "✓ version: success"; then
        local version=$(echo "$result" | grep "MongoDB version:" | head -1)
        success "$version"
        return 0
    else
        fail "Could not query MongoDB version"
        return 1
    fi
}

################################################################################
# Tests document operations using external client.
#
# Performs INSERT, FIND, and DELETE operations on test documents.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   MONGODB_CLIENT - Path to Python client script
#
# Returns:
#   0 - Document operations successful
#   1 - Document operations failed
################################################################################
test_mongodb_operations() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Can perform document operations (real client)"

    # Test document operations using Python client
    local result=$(run_python "$MONGODB_CLIENT" --test operations 2>&1)

    if echo "$result" | grep -q "✓ operations: success"; then
        success "Document insert, find, and delete successful (verified from outside container)"
        return 0
    else
        fail "Could not perform document operations"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Tests database listing using external client.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   MONGODB_CLIENT - Path to Python client script
#
# Returns:
#   0 - Database listing successful
#   1 - Database listing failed
################################################################################
test_mongodb_databases() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: Can list databases (real client)"

    # Test listing databases using Python client
    local result=$(run_python "$MONGODB_CLIENT" --test databases 2>&1)

    if echo "$result" | grep -q "✓ databases: success"; then
        local count=$(echo "$result" | grep "Found" | head -1)
        success "Database listing successful: $count"
        return 0
    else
        fail "Could not list databases"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Tests authentication using external client.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   MONGODB_CLIENT - Path to Python client script
#
# Returns:
#   0 - Authentication successful
#   1 - Authentication failed
################################################################################
test_mongodb_authentication() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: Authentication works (real client)"

    # Test authentication using Python client
    local result=$(run_python "$MONGODB_CLIENT" --test authentication 2>&1)

    if echo "$result" | grep -q "✓ authentication: success"; then
        success "Authentication successful"
        return 0
    else
        fail "Authentication failed"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Tests SSL/TLS connection capability from external client.
#
# Verifies SSL/TLS encryption status. MongoDB supports preferTLS mode which
# accepts both encrypted and unencrypted connections.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   MONGODB_CLIENT - Path to Python client script
#
# Returns:
#   0 - SSL test successful
#   1 - SSL connection test failed
################################################################################
test_mongodb_tls_available() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: SSL/TLS connection verification (real client)"

    # Test SSL connection using Python client
    local result=$(run_python "$MONGODB_CLIENT" --test ssl 2>&1)

    if echo "$result" | grep -q "✓ ssl: success"; then
        # Check if SSL is actually being used
        if echo "$result" | grep -q '"connection_type": "SSL/TLS"'; then
            success "SSL connection verified from external client (encrypted)"
        else
            # MongoDB is configured in preferTLS mode (dual-mode)
            # It accepts both encrypted and unencrypted connections
            success "Connection successful (MongoDB in preferTLS mode - accepts both encrypted and unencrypted)"
        fi
        return 0
    else
        fail "SSL connection test failed"
        warn "Error: $result"
        return 1
    fi
}

################################################################################
# Tests SSL certificate verification with CA bundle (if TLS enabled).
#
# When TLS is enabled, validates SSL certificate using the CA bundle to ensure:
# 1. Certificate is signed by trusted CA
# 2. Connection is properly encrypted
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   MONGODB_CLIENT - Path to Python client script
#
# Returns:
#   0 - SSL certificate validation successful or TLS not enabled
#   1 - SSL certificate verification failed or CA cert missing
################################################################################
test_mongodb_ssl_connection() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: SSL certificate verification with CA (if TLS enabled)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "mongodb")

    if [ "$tls_enabled" = "true" ]; then
        local ca_file="${HOME}/.config/vault/ca/ca-bundle.pem"

        if [ -f "$ca_file" ]; then
            # Test with SSL enabled and CA verification
            local result=$(run_python "$MONGODB_CLIENT" --test ssl --ssl --ca-cert "$ca_file" 2>&1)

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
# Tests encrypted document operations over SSL/TLS connection (if TLS enabled).
#
# Performs document operations (insert, find, delete) over an encrypted
# connection to ensure data is protected in transit.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   MONGODB_CLIENT - Path to Python client script
#
# Returns:
#   0 - Encrypted operations successful or TLS not enabled
#   1 - Encrypted operations failed
################################################################################
test_mongodb_encrypted_operations() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 11: Perform encrypted operations (real SSL/TLS data transfer)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "mongodb")

    if [ "$tls_enabled" = "true" ]; then
        local ca_file="${HOME}/.config/vault/ca/ca-bundle.pem"

        if [ -f "$ca_file" ]; then
            # Test document operations with SSL enabled
            local result=$(run_python "$MONGODB_CLIENT" --test operations --ssl --ca-cert "$ca_file" 2>&1)

            if echo "$result" | grep -q "✓ operations: success"; then
                # Verify connection was encrypted
                if echo "$result" | grep -q '"connection_type": "SSL/TLS"'; then
                    success "Document operations successful over encrypted connection (SSL/TLS verified)"
                    info "  Performed: insert, find, and delete operations over TLS"
                    return 0
                else
                    fail "Operations succeeded but connection was not encrypted"
                    return 1
                fi
            else
                fail "Document operations failed over encrypted connection"
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
# Tests that no plaintext MongoDB password exists in .env file.
#
# Validates security best practices by ensuring that MongoDB passwords are not
# stored in plaintext in the .env configuration file. Checks for:
# - MONGODB_PASSWORD variable with non-empty value
#
# Passwords should be managed exclusively through Vault.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   PROJECT_ROOT - Used to locate .env file
#
# Returns:
#   0 - No plaintext password found or .env doesn't exist
#   1 - Plaintext password found in .env
################################################################################
test_no_plaintext_passwords() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 12: No plaintext MongoDB password in .env"

    if [ -f "$PROJECT_ROOT/.env" ]; then
        # Check if old MONGODB_PASSWORD variable exists with a value
        local old_password=$(grep "^MONGODB_PASSWORD=" "$PROJECT_ROOT/.env" 2>/dev/null | grep -v "^#" | cut -d= -f2)

        if [ -z "$old_password" ]; then
            success "No plaintext MongoDB password in .env"
            return 0
        else
            warn "Found MONGODB_PASSWORD in .env (should be removed)"
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
# Runs all MongoDB integration tests and displays results summary.
#
# Executes all test functions in sequence, allowing each to pass or fail
# independently. Displays a formatted summary of results.
#
# Globals:
#   TESTS_RUN, TESTS_PASSED, TESTS_FAILED, FAILED_TESTS - Test counters
#   GREEN, RED, NC - Color codes for output formatting
#
# Returns:
#   0 - All tests passed
#   1 - One or more tests failed
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  MongoDB Vault Integration Tests"
    echo "========================================="
    echo

    test_mongodb_running || true
    test_mongodb_healthy || true
    test_mongodb_vault_integration || true
    test_mongodb_connection || true
    test_mongodb_version || true
    test_mongodb_operations || true
    test_mongodb_databases || true
    test_mongodb_authentication || true
    test_mongodb_tls_available || true
    test_mongodb_ssl_connection || true
    test_mongodb_encrypted_operations || true
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
        echo -e "${GREEN}✓ All MongoDB tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
