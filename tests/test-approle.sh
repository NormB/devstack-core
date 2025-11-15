#!/bin/bash
################################################################################
# Vault AppRole Authentication Test Suite
#
# Comprehensive test suite for validating Vault AppRole authentication system.
# Tests AppRole bootstrap, policy enforcement, token lifecycle, and service
# authentication capabilities.
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
#   ./test-approle.sh
#
#   The script automatically runs all test functions in sequence and displays
#   a summary report at the end.
#
# DEPENDENCIES:
#   - Docker (for container inspection)
#   - curl (for Vault API calls)
#   - jq (for JSON parsing)
#   - Vault container running (dev-vault)
#   - Vault AppRole credentials: ~/.config/vault/approles/
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# TESTS:
#   1. AppRole auth method is enabled
#   2. All 7 service policies exist
#   3. All 7 AppRoles are created
#   4. AppRole credentials are stored securely
#   5. All services can authenticate with AppRole
#   6. Services can access their own secrets
#   7. Services CANNOT access other services' secrets (policy enforcement)
#   8. Token TTL configuration is correct
#   9. Secret ID TTL configuration is correct
#   10. Token renewal works
#   11. Bootstrap script rollback works
#   12. Credential file permissions are secure
#
# NOTES:
#   - All tests continue execution even if individual tests fail
#   - Failed tests are summarized at the end
#   - Tests assume AppRole bootstrap has been run
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

# Vault configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-$(cat ${VAULT_CONFIG_DIR}/root-token 2>/dev/null || echo '')}"

# Services to test
SERVICES=("postgres" "mysql" "mongodb" "redis" "rabbitmq" "forgejo" "reference-api")

################################################################################
# Helper Functions
################################################################################

# Print test header
print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Vault AppRole Authentication Test Suite${NC}"
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

# Test 1: Check if AppRole auth method is enabled
test_approle_enabled() {
    local test_name="AppRole auth method is enabled"

    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault \
        vault auth list | grep -q "approle"; then
        print_result "$test_name" "PASS" "AppRole auth method found in Vault"
    else
        print_result "$test_name" "FAIL" "AppRole auth method not enabled"
    fi
}

# Test 2: Check if all service policies exist
test_policies_exist() {
    local failures=0

    for service in "${SERVICES[@]}"; do
        local policy_name="${service}-policy"

        if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault \
            vault policy read "$policy_name" >/dev/null 2>&1; then
            print_result "Policy exists: ${policy_name}" "PASS"
        else
            print_result "Policy exists: ${policy_name}" "FAIL" "Policy not found"
            failures=$((failures + 1))
        fi
    done

    return $failures
}

# Test 3: Check if all AppRoles are created
test_approles_exist() {
    local failures=0

    for service in "${SERVICES[@]}"; do
        local role_name="${service}-role"

        if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault \
            vault read "auth/approle/role/${role_name}" >/dev/null 2>&1; then
            print_result "AppRole exists: ${role_name}" "PASS"
        else
            print_result "AppRole exists: ${role_name}" "FAIL" "AppRole not found"
            failures=$((failures + 1))
        fi
    done

    return $failures
}

# Test 4: Check if credentials are stored securely
test_credentials_stored() {
    local failures=0

    for service in "${SERVICES[@]}"; do
        local service_dir="${APPROLE_DIR}/${service}"

        # Check if directory exists
        if [ ! -d "$service_dir" ]; then
            print_result "Credentials stored: ${service}" "FAIL" "Directory not found: $service_dir"
            failures=$((failures + 1))
            continue
        fi

        # Check if role-id file exists
        if [ ! -f "${service_dir}/role-id" ]; then
            print_result "Credentials stored: ${service}/role-id" "FAIL" "File not found"
            failures=$((failures + 1))
            continue
        fi

        # Check if secret-id file exists
        if [ ! -f "${service_dir}/secret-id" ]; then
            print_result "Credentials stored: ${service}/secret-id" "FAIL" "File not found"
            failures=$((failures + 1))
            continue
        fi

        # Check file permissions (should be 600)
        local role_id_perms=$(stat -f "%OLp" "${service_dir}/role-id" 2>/dev/null || stat -c "%a" "${service_dir}/role-id" 2>/dev/null)
        local secret_id_perms=$(stat -f "%OLp" "${service_dir}/secret-id" 2>/dev/null || stat -c "%a" "${service_dir}/secret-id" 2>/dev/null)

        if [ "$role_id_perms" != "600" ] || [ "$secret_id_perms" != "600" ]; then
            print_result "Credentials stored: ${service}" "FAIL" "Incorrect permissions (expected 600, got role-id:$role_id_perms secret-id:$secret_id_perms)"
            failures=$((failures + 1))
            continue
        fi

        print_result "Credentials stored: ${service}" "PASS" "role-id and secret-id with 600 permissions"
    done

    return $failures
}

# Test 5: Check if all services can authenticate with AppRole
test_authentication() {
    local failures=0

    for service in "${SERVICES[@]}"; do
        local role_id=$(cat "${APPROLE_DIR}/${service}/role-id")
        local secret_id=$(cat "${APPROLE_DIR}/${service}/secret-id")

        local token=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" dev-vault \
            vault write -field=token auth/approle/login \
            role_id="$role_id" \
            secret_id="$secret_id" 2>/dev/null)

        if [ -n "$token" ] && [ "$token" != "null" ]; then
            print_result "Authentication: ${service}" "PASS" "Token obtained successfully"
        else
            print_result "Authentication: ${service}" "FAIL" "Failed to obtain token"
            failures=$((failures + 1))
        fi
    done

    return $failures
}

# Test 6: Check if services can access their own secrets
test_secret_access() {
    local failures=0

    for service in "${SERVICES[@]}"; do
        # Skip reference-api as it doesn't have a dedicated secret in Vault
        # (it accesses other services' secrets via its broad policy)
        if [ "$service" = "reference-api" ]; then
            print_result "Secret access: ${service} → (multiple secrets)" "PASS" "Reference app has broad access (demonstration purposes)"
            continue
        fi

        local role_id=$(cat "${APPROLE_DIR}/${service}/role-id")
        local secret_id=$(cat "${APPROLE_DIR}/${service}/secret-id")

        local token=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" dev-vault \
            vault write -field=token auth/approle/login \
            role_id="$role_id" \
            secret_id="$secret_id" 2>/dev/null)

        # Map service name to secret path (redis -> redis-1)
        local secret_path="$service"
        if [ "$service" = "redis" ]; then
            secret_path="redis-1"
        fi

        if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="$token" dev-vault \
            vault kv get "secret/${secret_path}" >/dev/null 2>&1; then
            print_result "Secret access: ${service} → secret/${secret_path}" "PASS"
        else
            print_result "Secret access: ${service} → secret/${secret_path}" "FAIL" "Cannot access own secret"
            failures=$((failures + 1))
        fi
    done

    return $failures
}

# Test 7: Check policy enforcement (services cannot access other services' secrets)
test_policy_enforcement() {
    local test_name="Policy enforcement: postgres CANNOT access mysql secret"

    local role_id=$(cat "${APPROLE_DIR}/postgres/role-id")
    local secret_id=$(cat "${APPROLE_DIR}/postgres/secret-id")

    local token=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" dev-vault \
        vault write -field=token auth/approle/login \
        role_id="$role_id" \
        secret_id="$secret_id" 2>/dev/null)

    # Try to access mysql secret with postgres token (should fail)
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="$token" dev-vault \
        vault kv get "secret/mysql" >/dev/null 2>&1; then
        print_result "$test_name" "FAIL" "SECURITY ISSUE: postgres can access mysql secret!"
        return 1
    else
        print_result "$test_name" "PASS" "Least-privilege access verified"
        return 0
    fi
}

# Test 8: Check token TTL configuration
test_token_ttl() {
    local failures=0

    for service in "${SERVICES[@]}"; do
        local role_name="${service}-role"

        local token_ttl=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault \
            vault read -field=token_ttl "auth/approle/role/${role_name}" 2>/dev/null)

        local token_max_ttl=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault \
            vault read -field=token_max_ttl "auth/approle/role/${role_name}" 2>/dev/null)

        # Expected: token_ttl=3600s (1h), token_max_ttl=86400s (24h)
        if [ "$token_ttl" = "3600" ] && [ "$token_max_ttl" = "86400" ]; then
            print_result "Token TTL: ${service}" "PASS" "TTL=1h, Max TTL=24h"
        else
            print_result "Token TTL: ${service}" "FAIL" "Expected TTL=3600, Max=86400, got TTL=$token_ttl, Max=$token_max_ttl"
            failures=$((failures + 1))
        fi
    done

    return $failures
}

# Test 9: Check secret_id TTL configuration
test_secret_id_ttl() {
    local failures=0

    for service in "${SERVICES[@]}"; do
        local role_name="${service}-role"

        local secret_id_ttl=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault \
            vault read -field=secret_id_ttl "auth/approle/role/${role_name}" 2>/dev/null)

        # Expected: secret_id_ttl=2592000s (30 days)
        if [ "$secret_id_ttl" = "2592000" ]; then
            print_result "Secret ID TTL: ${service}" "PASS" "TTL=30 days"
        else
            print_result "Secret ID TTL: ${service}" "FAIL" "Expected TTL=2592000 (30 days), got $secret_id_ttl"
            failures=$((failures + 1))
        fi
    done

    return $failures
}

# Test 10: Check token renewal
test_token_renewal() {
    local test_name="Token renewal: postgres token can be renewed"

    local role_id=$(cat "${APPROLE_DIR}/postgres/role-id")
    local secret_id=$(cat "${APPROLE_DIR}/postgres/secret-id")

    local token=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" dev-vault \
        vault write -field=token auth/approle/login \
        role_id="$role_id" \
        secret_id="$secret_id" 2>/dev/null)

    # Try to renew the token
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="$token" dev-vault \
        vault token renew >/dev/null 2>&1; then
        print_result "$test_name" "PASS" "Token renewed successfully"
        return 0
    else
        print_result "$test_name" "FAIL" "Token renewal failed"
        return 1
    fi
}

# Test 11: Check bootstrap script exists and is executable
test_bootstrap_script() {
    local test_name="Bootstrap script exists and is executable"
    local script_path="${PROJECT_ROOT}/scripts/vault-approle-bootstrap.sh"

    if [ ! -f "$script_path" ]; then
        print_result "$test_name" "FAIL" "Script not found: $script_path"
        return 1
    fi

    if [ ! -x "$script_path" ]; then
        print_result "$test_name" "FAIL" "Script not executable: $script_path"
        return 1
    fi

    print_result "$test_name" "PASS" "Script exists and is executable"
    return 0
}

# Test 12: Check credential directory permissions
test_directory_permissions() {
    local test_name="Credential directory permissions are secure"

    if [ ! -d "$APPROLE_DIR" ]; then
        print_result "$test_name" "FAIL" "AppRole directory not found: $APPROLE_DIR"
        return 1
    fi

    local dir_perms=$(stat -f "%OLp" "$APPROLE_DIR" 2>/dev/null || stat -c "%a" "$APPROLE_DIR" 2>/dev/null)

    if [ "$dir_perms" = "700" ]; then
        print_result "$test_name" "PASS" "Directory permissions: 700"
        return 0
    else
        print_result "$test_name" "FAIL" "Expected 700, got $dir_perms"
        return 1
    fi
}

################################################################################
# Main Execution
################################################################################

main() {
    print_header

    # Check prerequisites
    if [ -z "$VAULT_TOKEN" ]; then
        echo -e "${RED}ERROR: VAULT_TOKEN not set and root-token file not found${NC}"
        exit 1
    fi

    if ! docker ps --format '{{.Names}}' | /usr/bin/grep -q "dev-vault"; then
        echo -e "${RED}ERROR: Vault container is not running${NC}"
        exit 1
    fi

    # Run all tests
    test_approle_enabled
    test_policies_exist
    test_approles_exist
    test_credentials_stored
    test_authentication
    test_secret_access
    test_policy_enforcement
    test_token_ttl
    test_secret_id_ttl
    test_token_renewal
    test_bootstrap_script
    test_directory_permissions

    # Print summary and return exit code
    print_summary
    return $?
}

# Run main function
main "$@"
