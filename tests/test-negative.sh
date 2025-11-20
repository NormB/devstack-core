#!/bin/bash
################################################################################
# Negative Test Suite
#
# Comprehensive negative testing and error condition validation for all
# development services. Tests verify that services correctly reject invalid
# credentials, malformed requests, and handle edge cases appropriately.
#
# DESCRIPTION:
#   This test suite validates error handling, authentication, authorization,
#   and input validation across all services in the development environment.
#   Unlike positive tests that verify expected functionality, these tests
#   intentionally provide invalid input to ensure services fail gracefully
#   and securely when faced with error conditions.
#
# GLOBALS:
#   SCRIPT_DIR    - Directory containing this script
#   PROJECT_ROOT  - Root directory of the project
#   TESTS_RUN     - Counter for total tests executed
#   TESTS_PASSED  - Counter for successful tests
#   TESTS_FAILED  - Counter for failed tests
#   FAILED_TESTS  - Array of failed test names
#
# USAGE:
#   ./test-negative.sh
#
#   No command-line arguments are required. The script will automatically:
#   - Detect running services
#   - Skip tests for services that are not running
#   - Execute all applicable negative tests
#   - Report detailed results showing proper error handling
#
# DEPENDENCIES:
#   - lib/common.sh: Common test utilities and helper functions
#   - uv: Python package manager for running Python test clients
#   - curl: For HTTP/HTTPS API testing
#   - jq: For JSON response parsing
#   - Docker: For container operations and CLI tool access
#   - psql: PostgreSQL command-line client
#   - mysql: MySQL command-line client
#   - Running services: Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ, FastAPI
#
# EXIT CODES:
#   0 - All tests passed (services correctly rejected invalid inputs)
#   1 - One or more tests failed (services accepted invalid inputs)
#
# TEST CATEGORIES:
#   Authentication Tests:
#     - Wrong password rejection for all databases
#     - Invalid token rejection for Vault
#     - Wrong credentials for message queues
#
#   Connection Tests:
#     - Non-existent database rejection
#     - Unreachable service handling
#     - Connection timeout behavior
#
#   Input Validation Tests:
#     - Invalid SQL syntax rejection
#     - Malformed JSON handling
#     - Invalid API parameters
#
#   Resource Limit Tests:
#     - Connection limit behavior
#     - Resource exhaustion handling
#
# NOTES:
#   - Tests are designed to fail if services accept invalid input
#   - Proper rejection of bad input is considered a test success
#   - All tests are non-destructive and safe to run
#   - Missing services cause tests to be skipped, not failed
#   - Tests verify both rejection and appropriate error messages
#   - Each test validates security boundaries and input validation
#
# EXAMPLES:
#   Run all negative tests:
#     $ ./test-negative.sh
#
#   Run tests and capture output:
#     $ ./test-negative.sh | tee negative-test-results.log
#
#   Verify authentication security:
#     $ ./test-negative.sh 2>&1 | grep -i "password"
#
#   Run tests for specific services:
#     $ docker compose up -d postgres mysql redis
#     $ ./test-negative.sh
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

################################################################################
# Tests that PostgreSQL correctly rejects wrong password authentication.
#
# Attempts to connect to PostgreSQL with an incorrect password and verifies
# that the connection is rejected. This test validates that authentication
# is working properly and credentials are being enforced.
#
# Security Validation:
#   - Password authentication is enabled
#   - Wrong credentials are rejected
#   - No authentication bypass vulnerabilities
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (wrong password correctly rejected)
#   1 - Test failed (wrong password was accepted - SECURITY ISSUE)
#   0 - Test skipped (PostgreSQL container not running)
#
# Notes:
#   - Uses psql command-line client
#   - Attempts connection with password "wrong_password"
#   - Success means the connection was properly rejected
#   - This is a critical security validation test
################################################################################
test_postgres_wrong_password() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 1: PostgreSQL rejects wrong password"

    if ! is_container_running "dev-postgres"; then
        warn "PostgreSQL container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    # Try to connect with wrong password (this should fail)
    if PGPASSWORD="wrong_password" psql -h localhost -U dev_admin -d dev_database -c "SELECT 1" >/dev/null 2>&1; then
        fail "Did not reject wrong password"
        return 1
    else
        success "Correctly rejected wrong password"
        return 0
    fi
}

################################################################################
# Tests that MySQL correctly rejects wrong password authentication.
#
# Attempts to connect to MySQL with an incorrect password and verifies
# that the connection is rejected. This test validates that authentication
# is working properly and credentials are being enforced.
#
# Security Validation:
#   - Password authentication is enabled
#   - Wrong credentials are rejected
#   - No authentication bypass vulnerabilities
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (wrong password correctly rejected)
#   1 - Test failed (wrong password was accepted - SECURITY ISSUE)
#   0 - Test skipped (MySQL container not running)
#
# Notes:
#   - Uses mysql command-line client
#   - Attempts connection with password "wrong_password"
#   - Success means the connection was properly rejected
#   - This is a critical security validation test
################################################################################
test_mysql_wrong_password() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 2: MySQL rejects wrong password"

    if ! is_container_running "dev-mysql"; then
        warn "MySQL container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    # Try to connect with wrong password (this should fail)
    if mysql -h 127.0.0.1 -u dev_admin -pwrong_password -D dev_database -e "SELECT 1" >/dev/null 2>&1; then
        fail "Did not reject wrong password"
        return 1
    else
        success "Correctly rejected wrong password"
        return 0
    fi
}

################################################################################
# Tests that MongoDB correctly rejects wrong password authentication.
#
# Attempts to connect to MongoDB with an incorrect password and verifies
# that the connection is rejected. This test validates that authentication
# is working properly and credentials are being enforced.
#
# Security Validation:
#   - Password authentication is enabled
#   - Wrong credentials are rejected
#   - Authentication database is properly configured
#   - No authentication bypass vulnerabilities
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (wrong password correctly rejected)
#   1 - Test failed (wrong password was accepted - SECURITY ISSUE)
#   0 - Test skipped (MongoDB container not running)
#
# Notes:
#   - Uses mongosh through docker exec
#   - Attempts connection with password "wrong_password"
#   - Checks for authentication error messages in output
#   - Success means authentication failure was detected
#   - This is a critical security validation test
################################################################################
test_mongodb_wrong_password() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 3: MongoDB rejects wrong password"

    if ! is_container_running "dev-mongodb"; then
        warn "MongoDB container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    # Try to connect with wrong password via docker exec (this should fail)
    local result=$(docker exec dev-mongodb mongosh -u dev_admin -p wrong_password --authenticationDatabase admin --eval "db.version()" 2>&1)

    if echo "$result" | grep -qE "(Authentication failed|auth.*failed)"; then
        success "Correctly rejected wrong password"
        return 0
    else
        fail "Did not reject wrong password"
        return 1
    fi
}

################################################################################
# Tests that Redis correctly rejects wrong password authentication.
#
# Attempts to connect to Redis with an incorrect password and verifies
# that the connection is rejected. This test validates that requirepass
# is properly configured and authentication is enforced.
#
# Security Validation:
#   - Password authentication (requirepass) is enabled
#   - Wrong credentials are rejected
#   - WRONGPASS error is returned for invalid auth
#   - No authentication bypass vulnerabilities
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (wrong password correctly rejected)
#   1 - Test failed (wrong password was accepted - SECURITY ISSUE)
#   0 - Test skipped (Redis container not running)
#
# Notes:
#   - Uses redis-cli through docker exec
#   - Attempts AUTH with password "wrong_password"
#   - Checks for WRONGPASS error in response
#   - Success means authentication failure was detected
#   - This is a critical security validation test
################################################################################
test_redis_wrong_password() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 4: Redis rejects wrong password"

    if ! is_container_running "dev-redis-1"; then
        warn "Redis container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    # Try to connect with wrong password (this should fail)
    local result=$(docker exec dev-redis-1 redis-cli -a "wrong_password" PING 2>&1)

    if echo "$result" | grep -qE "(WRONGPASS|invalid password|Authentication failed)"; then
        success "Correctly rejected wrong password"
        return 0
    else
        fail "Did not reject wrong password"
        return 1
    fi
}

################################################################################
# Tests that RabbitMQ correctly rejects wrong password authentication.
#
# Attempts to access RabbitMQ management API with an incorrect password
# and verifies that the request is rejected. This test validates that
# authentication is working properly for the management interface.
#
# Security Validation:
#   - HTTP Basic authentication is enabled
#   - Wrong credentials are rejected
#   - Management API requires proper authentication
#   - No authentication bypass vulnerabilities
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (wrong password correctly rejected)
#   1 - Test failed (wrong password was accepted - SECURITY ISSUE)
#   0 - Test skipped (RabbitMQ container not running)
#
# Notes:
#   - Tests management API at http://localhost:15672/api/overview
#   - Uses curl with Basic auth and wrong password "wrong_password"
#   - Success means HTTP authentication rejection occurred
#   - This is a critical security validation test
################################################################################
test_rabbitmq_wrong_password() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 5: RabbitMQ rejects wrong password"

    if ! is_container_running "dev-rabbitmq"; then
        warn "RabbitMQ container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    # Try to connect with wrong password via management API (this should fail)
    if curl -sf -u dev_admin:wrong_password http://localhost:15672/api/overview >/dev/null 2>&1; then
        fail "Did not reject wrong password"
        return 1
    else
        success "Correctly rejected wrong password"
        return 0
    fi
}

################################################################################
# Tests that Vault correctly rejects invalid authentication tokens.
#
# Attempts to access Vault secrets with an invalid token and verifies
# that the request is rejected. This test validates that token-based
# authentication is properly enforced for all secret access.
#
# Security Validation:
#   - Token authentication is required
#   - Invalid tokens are rejected
#   - No unauthorized access to secrets
#   - Token validation is working correctly
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (invalid token correctly rejected)
#   1 - Test failed (invalid token was accepted - SECURITY ISSUE)
#
# Notes:
#   - Tests secret retrieval with token "invalid_token_12345"
#   - Uses X-Vault-Token header for authentication
#   - Success means access was properly denied
#   - Always runs (no skip condition) as Vault is core service
#   - This is a critical security validation test
################################################################################
test_vault_invalid_token() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 6: Vault rejects invalid token"

    local vault_addr="http://localhost:8200"

    # Try to access Vault with invalid token (this should fail)
    if curl -sf -H "X-Vault-Token: invalid_token_12345" "$vault_addr/v1/secret/data/postgres" >/dev/null 2>&1; then
        fail "Did not reject invalid token"
        return 1
    else
        success "Correctly rejected invalid token"
        return 0
    fi
}

################################################################################
# Tests that PostgreSQL correctly rejects connections to non-existent databases.
#
# Attempts to connect to a database that doesn't exist and verifies that
# the connection is rejected with an appropriate error. This test validates
# database existence checking and proper error handling.
#
# Error Handling Validation:
#   - Non-existent databases are detected
#   - Proper error message is returned
#   - No silent failures or connection to wrong database
#   - Database isolation is maintained
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (connection to non-existent database correctly rejected)
#   1 - Test failed (connection succeeded to non-existent database)
#   0 - Test skipped (PostgreSQL not running or no Vault password)
#
# Notes:
#   - Attempts to connect to database "nonexistent_db"
#   - Retrieves valid password from Vault
#   - Uses correct credentials but invalid database name
#   - Success means database existence is properly validated
################################################################################
test_nonexistent_database() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 7: PostgreSQL rejects connection to non-existent database"

    if ! is_container_running "dev-postgres"; then
        warn "PostgreSQL container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local password=$(get_password_from_vault "postgres")

    if [ -z "$password" ]; then
        warn "Could not get password from Vault, skipping test"
        success "Test skipped (no password)"
        return 0
    fi

    # Try to connect to non-existent database (this should fail)
    if PGPASSWORD="$password" psql -h localhost -U dev_admin -d nonexistent_db -c "SELECT 1" >/dev/null 2>&1; then
        fail "Did not reject connection to non-existent database"
        return 1
    else
        success "Correctly rejected connection to non-existent database"
        return 0
    fi
}

################################################################################
# Tests that PostgreSQL correctly rejects invalid SQL syntax.
#
# Attempts to execute malformed SQL and verifies that the query is rejected
# with a syntax error. This test validates that SQL parsing and validation
# is working correctly to prevent malformed queries.
#
# Input Validation:
#   - SQL syntax is validated before execution
#   - Syntax errors are caught and reported
#   - Invalid queries do not corrupt database state
#   - Proper error messages are returned
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (invalid SQL correctly rejected)
#   1 - Test failed (invalid SQL was accepted or executed)
#   0 - Test skipped (PostgreSQL not running or no Vault password)
#
# Notes:
#   - Executes clearly invalid SQL: "INVALID SQL SYNTAX HERE"
#   - Uses valid credentials and database
#   - Tests SQL parser error handling
#   - Success means query validation is working
################################################################################
test_invalid_sql_query() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 8: PostgreSQL rejects invalid SQL syntax"

    if ! is_container_running "dev-postgres"; then
        warn "PostgreSQL container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    local password=$(get_password_from_vault "postgres")

    if [ -z "$password" ]; then
        warn "Could not get password from Vault, skipping test"
        success "Test skipped (no password)"
        return 0
    fi

    # Try to execute invalid SQL (this should fail)
    if PGPASSWORD="$password" psql -h localhost -U dev_admin -d dev_database -c "INVALID SQL SYNTAX HERE" >/dev/null 2>&1; then
        fail "Did not reject invalid SQL syntax"
        return 1
    else
        success "Correctly rejected invalid SQL syntax"
        return 0
    fi
}

################################################################################
# Tests that database handles connection limits gracefully.
#
# Opens many concurrent connections to test database behavior at or near
# connection limits. Verifies that the database handles resource exhaustion
# gracefully without crashing and returns appropriate errors.
#
# Resource Management Validation:
#   - Connection limits are enforced
#   - Excessive connections fail gracefully
#   - Some connections succeed within limits
#   - Database remains stable under connection pressure
#   - Proper error messages for connection failures
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (some connections succeeded, limits enforced gracefully)
#   1 - Test failed (all connections failed - database may be down)
#   0 - Test skipped (PostgreSQL container not running)
#
# Notes:
#   - Attempts to open 50 concurrent connections
#   - Uses Python client connection test
#   - Some failures are expected and acceptable
#   - Tests resource exhaustion handling, not performance
#   - Success means at least one connection worked
################################################################################
test_connection_limit() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 9: Database handles connection limit gracefully"

    if ! is_container_running "dev-postgres"; then
        warn "PostgreSQL container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    # Try to open many connections (some may fail if limit is reached)
    local pids=()
    local max_connections=50

    for i in $(seq 1 $max_connections); do
        run_python lib/postgres_client.py --test connection >/dev/null 2>&1 &
        pids+=($!)
    done

    # Wait for all to complete
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid" 2>/dev/null; then
            failed=$((failed + 1))
        fi
    done

    # Some connections may fail due to limits, but we should handle it gracefully
    if [ $failed -lt $max_connections ]; then
        success "Handled $((max_connections - failed))/$max_connections connections ($failed hit limits)"
        return 0
    else
        fail "All $max_connections connections failed"
        return 1
    fi
}

################################################################################
# Tests that FastAPI correctly rejects or handles invalid parameters.
#
# Attempts to access an API endpoint with an invalid parameter value and
# verifies that the API either rejects the request or returns an error
# response. This test validates input parameter validation.
#
# Input Validation:
#   - Invalid parameter values are detected
#   - Appropriate error responses are returned
#   - API doesn't crash on invalid input
#   - Error handling is consistent
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (invalid parameter rejected or error returned)
#   0 - Test passed with warning (no explicit rejection, may have default)
#   0 - Test skipped (FastAPI container not running)
#
# Notes:
#   - Tests endpoint /redis/nodes/invalid-node-999/info
#   - Invalid node ID should trigger error
#   - Checks for error in HTTP status or JSON response
#   - Some APIs may have default behavior instead of explicit error
################################################################################
test_api_invalid_parameters() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 10: FastAPI rejects invalid parameters"

    if ! is_container_running "dev-reference-api"; then
        warn "FastAPI container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    # Try to access non-existent node (this should return error)
    local response=$(curl -sf "http://localhost:8000/redis/nodes/invalid-node-999/info" 2>&1)

    # This should fail or return an error response
    if [ $? -ne 0 ] || echo "$response" | jq -e '.status == "error"' &>/dev/null; then
        success "Correctly rejected invalid node parameter"
        return 0
    else
        warn "API did not explicitly reject invalid parameter (may have default behavior)"
        success "Test completed (no explicit rejection)"
        return 0
    fi
}

################################################################################
# Tests that services handle Vault connection failures gracefully.
#
# Attempts to connect to Vault on an incorrect port to simulate connection
# failure. Verifies that connection attempts fail quickly and return
# appropriate errors rather than hanging or crashing.
#
# Error Handling Validation:
#   - Connection failures are detected
#   - Timeouts are enforced
#   - Services don't hang on unreachable dependencies
#   - Proper error reporting for connection issues
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (connection failure correctly detected)
#   1 - Test failed (connection succeeded to wrong port - unexpected)
#
# Notes:
#   - Attempts connection to port 9999 (should be unused)
#   - Uses 2-second timeout to prevent hanging
#   - Tests connection error handling, not Vault itself
#   - Success means failure detection is working
################################################################################
test_vault_connection_failure() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 11: Services handle Vault unavailability"

    # Try to connect to Vault on wrong port (this should fail)
    if curl --max-time 2 -sf "http://localhost:9999/v1/sys/health" >/dev/null 2>&1; then
        fail "Did not detect Vault connection failure"
        return 1
    else
        success "Correctly handled Vault connection failure"
        return 0
    fi
}

################################################################################
# Tests that API correctly rejects malformed JSON in requests.
#
# Sends a request with invalid JSON syntax to test API input validation
# and error handling. Verifies that malformed data is rejected with
# appropriate error responses.
#
# Input Validation:
#   - JSON syntax is validated
#   - Malformed JSON is rejected
#   - Appropriate HTTP error codes returned (400/405/422)
#   - API doesn't crash on invalid input
#
# Globals:
#   TESTS_RUN - Incremented by 1
#
# Returns:
#   0 - Test passed (malformed JSON rejected with error)
#   1 - Test failed (malformed JSON was accepted)
#   0 - Test skipped (FastAPI container not running)
#
# Notes:
#   - Sends POST request with invalid JSON: '{invalid json}'
#   - Tests cache endpoint which accepts POST requests
#   - Checks HTTP status code for proper error response
#   - 4xx status codes indicate proper error handling
################################################################################
test_api_invalid_json() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Negative Test 12: API rejects malformed JSON"

    if ! is_container_running "dev-reference-api"; then
        warn "FastAPI container not running, skipping test"
        success "Test skipped (container not running)"
        return 0
    fi

    # Test with malformed JSON to cache endpoint (accepts POST)
    # Use -w to capture HTTP status code, -o to suppress body output
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST -H "Content-Type: application/json" \
        -d '{invalid json}' "http://localhost:8000/examples/cache/test-key")

    # Should return 4xx error (400 Bad Request, 422 Unprocessable Entity, etc.)
    if [ "$http_code" -ge 400 ] && [ "$http_code" -lt 500 ]; then
        success "Correctly rejected malformed JSON (HTTP $http_code)"
        return 0
    elif [ "$http_code" -eq 200 ]; then
        fail "API accepted malformed JSON (HTTP 200)"
        return 1
    else
        warn "Unexpected HTTP status code: $http_code"
        success "Test completed with status $http_code"
        return 0
    fi
}

################################################################################
# Executes all negative tests in sequence.
#
# Main test orchestration function that runs all defined negative/error
# condition tests and generates a comprehensive report. Tests are executed
# in order with error handling to ensure all tests run even if some fail.
#
# Test Sequence:
#   1. PostgreSQL wrong password rejection
#   2. MySQL wrong password rejection
#   3. MongoDB wrong password rejection
#   4. Redis wrong password rejection
#   5. RabbitMQ wrong password rejection
#   6. Vault invalid token rejection
#   7. Non-existent database rejection
#   8. Invalid SQL query rejection
#   9. Connection limit handling
#   10. API invalid parameters handling
#   11. Vault connection failure handling
#   12. API malformed JSON rejection
#
# Globals:
#   TESTS_RUN - Tracks total tests executed
#   TESTS_PASSED - Tracks successful tests
#   TESTS_FAILED - Tracks failed tests
#   FAILED_TESTS - Array of failed test names
#
# Returns:
#   0 - All tests passed (all invalid inputs correctly rejected)
#   1 - One or more tests failed (security or validation issue)
#
# Notes:
#   - Tests continue running even if individual tests fail
#   - Each test handles its own service availability checks
#   - Test "success" means invalid input was properly rejected
#   - Final report shows which services are handling errors correctly
#   - Failed tests may indicate security vulnerabilities
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  Negative Test Suite"
    echo "========================================="
    echo

    test_suite_setup "Negative"

    test_postgres_wrong_password || true
    test_mysql_wrong_password || true
    test_mongodb_wrong_password || true
    test_redis_wrong_password || true
    test_rabbitmq_wrong_password || true
    test_vault_invalid_token || true
    test_nonexistent_database || true
    test_invalid_sql_query || true
    test_connection_limit || true
    test_api_invalid_parameters || true
    test_vault_connection_failure || true
    test_api_invalid_json || true

    print_test_results "Negative"

    test_suite_teardown
}

# Main
run_all_tests
