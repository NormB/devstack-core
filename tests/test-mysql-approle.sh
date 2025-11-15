#!/bin/bash
################################################################################
# MySQL AppRole Integration Test Suite
#
# Comprehensive test suite for validating MySQL AppRole authentication
# migration. Tests that MySQL successfully authenticates using AppRole
# instead of root token, and that all database functionality works correctly.
#
# GLOBALS:
#   SCRIPT_DIR - Directory containing this script
#   PROJECT_ROOT - Root directory of the project
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for output formatting
#   TESTS_RUN - Counter for total number of tests executed
#   TESTS_PASSED - Counter for successfully passed tests
#   TESTS_FAILED - Counter for failed tests
#   FAILED_TESTS - Array containing names of failed tests
#
# USAGE:
#   ./test-mysql-approle.sh
#
# DEPENDENCIES:
#   - Docker (for container inspection)
#   - docker compose (for service management)
#   - MySQL container running (dev-mysql)
#   - Vault AppRole credentials for mysql
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# TESTS:
#   1. MySQL container is running
#   2. Container uses init-approle.sh entrypoint
#   3. AppRole credentials are mounted
#   4. No VAULT_TOKEN in environment (root token removed)
#   5. VAULT_APPROLE_DIR is set correctly
#   6. MySQL started successfully with AppRole
#   7. AppRole authentication logs present
#   8. Database connection works
#   9. Database operations work (CREATE, INSERT, SELECT, DROP)
#   10. No root token in logs
#   11. Temporary token obtained (not root token)
#   12. Service can only access mysql secrets (policy enforcement)
#
# NOTES:
#   - All tests continue execution even if individual tests fail
#   - Failed tests are summarized at the end
#   - Tests assume MySQL has been migrated to AppRole
#
# AUTHOR: DevStack Core Team
# VERSION: 1.0
# DATE: November 14, 2025
################################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VAULT_CONFIG_DIR="${HOME}/.config/vault"
APPROLE_DIR="${VAULT_CONFIG_DIR}/approles"

################################################################################
# Helper Functions
################################################################################

# Print test header
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  MySQL AppRole Integration Test Suite${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Print test result
print_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        [ -n "$message" ] && echo -e "  ${BLUE}→${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        [ -n "$message" ] && echo -e "  ${RED}→${NC} $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Test Summary${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Total Tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo ""
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        echo ""
        return 0
    fi
}

################################################################################
# Test Functions
################################################################################

# Test 1: Check if MySQL container is running
test_container_running() {
    local test_name="MySQL container is running"

    if docker ps --format '{{.Names}}' | /usr/bin/grep -q "dev-mysql"; then
        print_result "$test_name" "PASS" "Container dev-mysql is running"
    else
        print_result "$test_name" "FAIL" "Container not found"
    fi
}

# Test 2: Check if container uses init-approle.sh entrypoint
test_approle_entrypoint() {
    local test_name="Container uses init-approle.sh entrypoint"

    local entrypoint=$(docker inspect dev-mysql --format '{{json .Config.Entrypoint}}')

    if echo "$entrypoint" | /usr/bin/grep -q "init-approle.sh"; then
        print_result "$test_name" "PASS" "Entrypoint: init-approle.sh"
    else
        print_result "$test_name" "FAIL" "Entrypoint not set to init-approle.sh (found: $entrypoint)"
    fi
}

# Test 3: Check if AppRole credentials are mounted
test_approle_mounted() {
    local test_name="AppRole credentials are mounted in container"

    if docker exec dev-mysql test -f /vault-approles/mysql/role-id && \
       docker exec dev-mysql test -f /vault-approles/mysql/secret-id; then
        print_result "$test_name" "PASS" "role-id and secret-id files present"
    else
        print_result "$test_name" "FAIL" "AppRole credential files not found in container"
    fi
}

# Test 4: Check that VAULT_TOKEN is NOT in environment (root token removed)
test_no_root_token() {
    local test_name="No VAULT_TOKEN in environment (root token removed)"

    local env_vars=$(docker exec dev-mysql env)

    if echo "$env_vars" | /usr/bin/grep -q "^VAULT_TOKEN="; then
        print_result "$test_name" "FAIL" "VAULT_TOKEN still present in environment"
    else
        print_result "$test_name" "PASS" "VAULT_TOKEN removed from environment"
    fi
}

# Test 5: Check that VAULT_APPROLE_DIR is set
test_approle_dir_set() {
    local test_name="VAULT_APPROLE_DIR environment variable is set"

    local approle_dir=$(docker exec dev-mysql printenv VAULT_APPROLE_DIR 2>/dev/null || echo "")

    if [ -n "$approle_dir" ]; then
        print_result "$test_name" "PASS" "VAULT_APPROLE_DIR=$approle_dir"
    else
        print_result "$test_name" "FAIL" "VAULT_APPROLE_DIR not set"
    fi
}

# Test 6: Check that MySQL started successfully
test_mysql_started() {
    local test_name="MySQL started successfully"

    if docker exec dev-mysql mysqladmin ping -h localhost > /dev/null 2>&1; then
        print_result "$test_name" "PASS" "MySQL is ready to accept connections"
    else
        print_result "$test_name" "FAIL" "MySQL is not ready"
    fi
}

# Test 7: Check for AppRole authentication in logs
test_approle_auth_logs() {
    local test_name="AppRole authentication logs present"

    local logs=$(docker compose logs mysql 2>&1)

    if echo "$logs" | /usr/bin/grep -q "AppRole authentication successful"; then
        print_result "$test_name" "PASS" "AppRole authentication log found"
    else
        print_result "$test_name" "FAIL" "AppRole authentication log not found"
    fi
}

# Test 8: Check database connection works
test_db_connection() {
    local test_name="Database connection works with AppRole credentials"

    # Get credentials from Vault
    local password=$(docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN=$(cat ${VAULT_CONFIG_DIR}/root-token) dev-vault \
        vault kv get -field=password secret/mysql 2>/dev/null)

    if docker compose exec -T mysql mysql -u devuser -p${password} -D devdb -e "SELECT 1" > /dev/null 2>&1; then
        print_result "$test_name" "PASS" "Connection successful"
    else
        print_result "$test_name" "FAIL" "Connection failed"
    fi
}

# Test 9: Check database operations (CRUD)
test_db_operations() {
    local test_name="Database operations work (CREATE, INSERT, SELECT, DROP)"

    # Get credentials from Vault
    local password=$(docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN=$(cat ${VAULT_CONFIG_DIR}/root-token) dev-vault \
        vault kv get -field=password secret/mysql 2>/dev/null)

    # Create test table
    if ! docker compose exec -T mysql mysql -u devuser -p${password} -D devdb -e \
        "CREATE TABLE IF NOT EXISTS approle_test (id INT AUTO_INCREMENT PRIMARY KEY, message TEXT);" > /dev/null 2>&1; then
        print_result "$test_name" "FAIL" "Failed to create table"
        return
    fi

    # Insert test data
    if ! docker compose exec -T mysql mysql -u devuser -p${password} -D devdb -e \
        "INSERT INTO approle_test (message) VALUES ('AppRole authentication works!');" > /dev/null 2>&1; then
        print_result "$test_name" "FAIL" "Failed to insert data"
        return
    fi

    # Select test data
    local result=$(docker compose exec -T mysql mysql -u devuser -p${password} -D devdb -N -e \
        "SELECT message FROM approle_test WHERE message LIKE '%AppRole%';" 2>&1 | /usr/bin/grep -v "Using a password" | tr -d '[:space:]')

    if [ "$result" != "AppRoleauthenticationworks!" ]; then
        print_result "$test_name" "FAIL" "Failed to select data (got: $result)"
        return
    fi

    # Drop test table
    if ! docker compose exec -T mysql mysql -u devuser -p${password} -D devdb -e \
        "DROP TABLE approle_test;" > /dev/null 2>&1; then
        print_result "$test_name" "FAIL" "Failed to drop table"
        return
    fi

    print_result "$test_name" "PASS" "CREATE, INSERT, SELECT, DROP all successful"
}

# Test 10: Verify no root token in logs
test_no_root_token_in_logs() {
    local test_name="No root token in container logs"

    local logs=$(docker compose logs mysql 2>&1)
    local root_token=$(cat ${VAULT_CONFIG_DIR}/root-token 2>/dev/null || echo "")

    if [ -n "$root_token" ] && echo "$logs" | /usr/bin/grep -q "$root_token"; then
        print_result "$test_name" "FAIL" "Root token found in logs (security issue)"
    else
        print_result "$test_name" "PASS" "No root token in logs"
    fi
}

# Test 11: Verify temporary token obtained (not root token)
test_temporary_token() {
    local test_name="Temporary token obtained via AppRole (not root token)"

    local logs=$(docker compose logs mysql 2>&1)
    local root_token=$(cat ${VAULT_CONFIG_DIR}/root-token 2>/dev/null || echo "")

    # Look for "AppRole authentication successful (token: hvs.CAESIJ..." pattern
    if echo "$logs" | /usr/bin/grep -q "AppRole authentication successful (token: hvs\."; then
        # Extract the token from logs
        local temp_token=$(echo "$logs" | /usr/bin/grep "AppRole authentication successful" | /usr/bin/grep -o "token: hvs\.[^)]*" | cut -d' ' -f2 | head -1)

        if [ "$temp_token" = "$root_token" ]; then
            print_result "$test_name" "FAIL" "Using root token instead of temporary token"
        else
            print_result "$test_name" "PASS" "Temporary token obtained (${temp_token:0:20}...)"
        fi
    else
        print_result "$test_name" "FAIL" "No AppRole token found in logs"
    fi
}

# Test 12: Verify policy enforcement (mysql cannot access postgres secrets)
test_policy_enforcement() {
    local test_name="Policy enforcement: mysql AppRole cannot access postgres secret"

    # Get mysql AppRole credentials
    local role_id=$(cat "${APPROLE_DIR}/mysql/role-id" 2>/dev/null || echo "")
    local secret_id=$(cat "${APPROLE_DIR}/mysql/secret-id" 2>/dev/null || echo "")

    if [ -z "$role_id" ] || [ -z "$secret_id" ]; then
        print_result "$test_name" "FAIL" "Cannot read mysql AppRole credentials"
        return
    fi

    # Authenticate with mysql AppRole
    local token=$(docker exec -e VAULT_ADDR=http://vault:8200 dev-vault \
        vault write -field=token auth/approle/login \
        role_id="$role_id" \
        secret_id="$secret_id" 2>/dev/null || echo "")

    if [ -z "$token" ]; then
        print_result "$test_name" "FAIL" "Failed to authenticate with mysql AppRole"
        return
    fi

    # Try to access postgres secret (should fail)
    if docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN="$token" dev-vault \
        vault kv get secret/postgres > /dev/null 2>&1; then
        print_result "$test_name" "FAIL" "SECURITY ISSUE: mysql can access postgres secret"
    else
        print_result "$test_name" "PASS" "Least-privilege enforced: mysql cannot access postgres"
    fi
}

# Test 13: Verify init-approle.sh script exists and is executable
test_init_script_exists() {
    local test_name="init-approle.sh script exists and is executable"

    if [ ! -f "${PROJECT_ROOT}/configs/mysql/scripts/init-approle.sh" ]; then
        print_result "$test_name" "FAIL" "Script not found"
        return
    fi

    if [ ! -x "${PROJECT_ROOT}/configs/mysql/scripts/init-approle.sh" ]; then
        print_result "$test_name" "FAIL" "Script not executable"
        return
    fi

    print_result "$test_name" "PASS" "Script exists and is executable"
}

# Test 14: Verify docker-compose.yml has correct configuration
test_docker_compose_config() {
    local test_name="docker-compose.yml has correct AppRole configuration"

    local compose_file="${PROJECT_ROOT}/docker-compose.yml"
    local failures=0

    # Check entrypoint
    if ! /usr/bin/grep -A 5 "mysql:" "$compose_file" | /usr/bin/grep -q "init-approle.sh"; then
        echo "  ${RED}→${NC} Entrypoint not set to init-approle.sh"
        failures=$((failures + 1))
    fi

    # Check AppRole volume mount
    if ! /usr/bin/grep -A 30 "mysql:" "$compose_file" | /usr/bin/grep -q "vault/approles/mysql"; then
        echo "  ${RED}→${NC} AppRole credentials not mounted"
        failures=$((failures + 1))
    fi

    # Check VAULT_APPROLE_DIR env var
    if ! /usr/bin/grep -A 20 "mysql:" "$compose_file" | /usr/bin/grep -q "VAULT_APPROLE_DIR"; then
        echo "  ${RED}→${NC} VAULT_APPROLE_DIR not set"
        failures=$((failures + 1))
    fi

    if [ $failures -eq 0 ]; then
        print_result "$test_name" "PASS" "All configuration correct"
    else
        print_result "$test_name" "FAIL" "$failures configuration issue(s) found"
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header

    # Check prerequisites
    if ! docker ps --format '{{.Names}}' | /usr/bin/grep -q "dev-mysql"; then
        echo -e "${RED}ERROR: MySQL container is not running${NC}"
        echo "Start with: docker compose --profile standard up -d mysql"
        exit 1
    fi

    if ! docker ps --format '{{.Names}}' | /usr/bin/grep -q "dev-vault"; then
        echo -e "${RED}ERROR: Vault container is not running${NC}"
        exit 1
    fi

    # Run all tests
    test_container_running
    test_approle_entrypoint
    test_approle_mounted
    test_no_root_token
    test_approle_dir_set
    test_mysql_started
    test_approle_auth_logs
    test_db_connection
    test_db_operations
    test_no_root_token_in_logs
    test_temporary_token
    test_policy_enforcement
    test_init_script_exists
    test_docker_compose_config

    # Print summary and return exit code
    print_summary
    return $?
}

# Run main function
main "$@"
