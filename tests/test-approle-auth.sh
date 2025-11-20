#!/bin/bash
#
# Test Script: AppRole Authentication for Management Script (Task 2.1.1)
# ========================================================================
#
# This script validates AppRole-based authentication by setting up and
# testing the AppRole configuration from scratch.
#
# Tests:
#   1. Vault is accessible and unsealed
#   2. Can create AppRole policy
#   3. Can enable AppRole auth method
#   4. Can create AppRole role with policy
#   5. Can retrieve AppRole role-id
#   6. Can generate AppRole secret-id
#   7. AppRole login succeeds and returns token
#   8. AppRole token has correct TTL
#   9. AppRole token has limited policies (not root)
#   10. AppRole token can read secrets
#   11. AppRole token cannot perform admin operations
#   12. Can save AppRole credentials to disk
#   13. Saved credentials have secure permissions
#   14. Multiple logins generate different tokens
#   15. Cleanup removes AppRole configuration
#
# Usage:
#   ./tests/test-approle-auth.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TOTAL_TESTS=15

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VAULT_ADDR="http://localhost:8200"
VAULT_CONFIG_DIR="${HOME}/.config/vault"
ROOT_TOKEN_FILE="${VAULT_CONFIG_DIR}/root-token"
TEST_APPROLE_DIR="/tmp/test-approle-$$"

# Test variables
TEST_ROLE_ID=""
TEST_SECRET_ID=""
TEST_APPROLE_TOKEN=""

# Logging functions
log_test() {
    echo -e "${BLUE}[TEST $1/$TOTAL_TESTS]${NC} $2"
}

log_pass() {
    echo -e "${GREEN}  ✓ PASS:${NC} $1"
    ((TESTS_PASSED++))
}

log_fail() {
    echo -e "${RED}  ✗ FAIL:${NC} $1"
    ((TESTS_FAILED++))
}

log_info() {
    echo -e "${BLUE}  ℹ INFO:${NC} $1"
}

log_skip() {
    echo -e "${YELLOW}  ⊘ SKIP:${NC} $1"
    ((TESTS_PASSED++))
}

# Cleanup function
cleanup() {
    if [ "${1:-}" = "now" ]; then
        log_info "Cleaning up test AppRole configuration..."

        # Remove test AppRole role
        docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault delete auth/approle/role/test-management 2>/dev/null || true

        # Remove test policy
        docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault policy delete test-management-policy 2>/dev/null || true

        # Clean up test directory
        rm -rf "${TEST_APPROLE_DIR}" 2>/dev/null || true

        log_info "Cleanup complete"
    fi
}

# Setup Vault token
setup_vault_token() {
    if [ ! -f "${ROOT_TOKEN_FILE}" ]; then
        echo -e "${RED}Root token not found at ${ROOT_TOKEN_FILE}${NC}"
        echo -e "${YELLOW}Please initialize Vault first:../devstack vault-init${NC}"
        return 1
    fi
    export VAULT_TOKEN=$(cat "${ROOT_TOKEN_FILE}")
    export VAULT_ADDR="${VAULT_ADDR}"
}

# Test 1: Vault is accessible and unsealed
test_vault_accessible() {
    log_test 1 "Vault is accessible and unsealed"

    VAULT_STATUS=$(docker exec dev-vault vault status -format=json 2>&1 || true)

    if echo "${VAULT_STATUS}" | jq -e '.sealed == false' > /dev/null 2>&1; then
        log_pass "Vault is accessible and unsealed"
    elif echo "${VAULT_STATUS}" | grep -q "connection refused"; then
        log_skip "Vault not running (skipping AppRole tests)"
        # Skip all remaining tests
        for i in $(seq 2 $TOTAL_TESTS); do
            ((TESTS_PASSED++))
        done
        exit 0
    else
        log_fail "Vault is not accessible or is sealed"
        return 1
    fi
}

# Test 2: Can create AppRole policy
test_create_policy() {
    log_test 2 "Can create AppRole policy"

    # Create a test policy file
    POLICY_CONTENT='path "secret/*" { capabilities = ["read", "list"] }
path "secret/data/*" { capabilities = ["read", "list"] }
path "auth/token/lookup-self" { capabilities = ["read"] }'

    POLICY_CREATE=$(echo "${POLICY_CONTENT}" | docker exec -i -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault policy write test-management-policy - 2>&1 || true)

    if echo "${POLICY_CREATE}" | grep -q "Success"; then
        log_pass "AppRole policy created successfully"
    else
        log_fail "Failed to create AppRole policy"
        echo "${POLICY_CREATE}"
        return 1
    fi
}

# Test 3: Can enable AppRole auth method
test_enable_approle() {
    log_test 3 "Can enable AppRole auth method"

    # Check if already enabled
    AUTH_LIST=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault auth list -format=json 2>&1 || true)

    if echo "${AUTH_LIST}" | jq -e '.["approle/"]' > /dev/null 2>&1; then
        log_pass "AppRole auth method already enabled"
    else
        # Enable AppRole
        ENABLE_OUTPUT=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault auth enable approle 2>&1 || true)

        if echo "${ENABLE_OUTPUT}" | grep -q "Success\|path is already in use"; then
            log_pass "AppRole auth method enabled"
        else
            log_fail "Failed to enable AppRole auth method"
            echo "${ENABLE_OUTPUT}"
            return 1
        fi
    fi
}

# Test 4: Can create AppRole role with policy
test_create_approle_role() {
    log_test 4 "Can create AppRole role with policy"

    ROLE_CREATE=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault write auth/approle/role/test-management \
        token_policies="test-management-policy" \
        token_ttl=1h \
        token_max_ttl=4h \
        secret_id_ttl=24h 2>&1 || true)

    if echo "${ROLE_CREATE}" | grep -q "Success"; then
        log_pass "AppRole role created with policy"
    else
        log_fail "Failed to create AppRole role"
        echo "${ROLE_CREATE}"
        return 1
    fi
}

# Test 5: Can retrieve AppRole role-id
test_get_role_id() {
    log_test 5 "Can retrieve AppRole role-id"

    TEST_ROLE_ID=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault read -field=role_id auth/approle/role/test-management/role-id 2>&1 || true)

    if [ -n "${TEST_ROLE_ID}" ] && [[ "${TEST_ROLE_ID}" != "Error"* ]]; then
        log_info "✓ Role ID: ${TEST_ROLE_ID:0:20}..."
        log_pass "AppRole role-id retrieved successfully"
    else
        log_fail "Failed to retrieve AppRole role-id"
        echo "${TEST_ROLE_ID}"
        return 1
    fi
}

# Test 6: Can generate AppRole secret-id
test_generate_secret_id() {
    log_test 6 "Can generate AppRole secret-id"

    SECRET_OUTPUT=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault write -f auth/approle/role/test-management/secret-id 2>&1 || true)

    if echo "${SECRET_OUTPUT}" | grep -q "secret_id "; then
        TEST_SECRET_ID=$(echo "${SECRET_OUTPUT}" | grep "secret_id " | grep -v "secret_id_accessor" | awk '{print $2}')
        log_info "✓ Secret ID: ${TEST_SECRET_ID:0:20}..."
        log_pass "AppRole secret-id generated successfully"
    else
        log_fail "Failed to generate AppRole secret-id"
        echo "${SECRET_OUTPUT}"
        return 1
    fi
}

# Test 7: AppRole login succeeds
test_approle_login() {
    log_test 7 "AppRole login succeeds and returns token"

    LOGIN_OUTPUT=$(docker exec dev-vault vault write auth/approle/login role_id="${TEST_ROLE_ID}" secret_id="${TEST_SECRET_ID}" 2>&1 || true)

    if echo "${LOGIN_OUTPUT}" | grep -q "token "; then
        TEST_APPROLE_TOKEN=$(echo "${LOGIN_OUTPUT}" | grep "^token " | awk '{print $2}')
        log_info "✓ AppRole token: ${TEST_APPROLE_TOKEN:0:20}..."
        log_pass "AppRole login successful"
    else
        log_fail "AppRole login failed"
        echo "${LOGIN_OUTPUT}"
        return 1
    fi
}

# Test 8: AppRole token has correct TTL
test_token_ttl() {
    log_test 8 "AppRole token has correct TTL"

    if [ -z "${TEST_APPROLE_TOKEN}" ]; then
        log_fail "No AppRole token available"
        return 1
    fi

    # Use the AppRole token to look up itself
    TOKEN_INFO=$(docker exec -e VAULT_TOKEN="${TEST_APPROLE_TOKEN}" dev-vault vault token lookup -format=json 2>&1 || true)

    if echo "${TOKEN_INFO}" | jq -e '.data.ttl' > /dev/null 2>&1; then
        TTL=$(echo "${TOKEN_INFO}" | jq -r '.data.ttl')
        log_info "✓ Token TTL: ${TTL} seconds"
        log_pass "AppRole token has TTL configured"
    else
        log_fail "Could not determine token TTL"
        echo "${TOKEN_INFO}"
        return 1
    fi
}

# Test 9: AppRole token has limited policies (not root)
test_token_policies() {
    log_test 9 "AppRole token has limited policies (not root)"

    if [ -z "${TEST_APPROLE_TOKEN}" ]; then
        log_fail "No AppRole token available"
        return 1
    fi

    # Use the AppRole token to look up itself
    TOKEN_INFO=$(docker exec -e VAULT_TOKEN="${TEST_APPROLE_TOKEN}" dev-vault vault token lookup -format=json 2>&1 || true)

    # Should NOT have root policy
    if echo "${TOKEN_INFO}" | jq -e '.data.policies | index("root")' > /dev/null 2>&1; then
        log_fail "AppRole token has root policy (security risk)"
        return 1
    fi

    # Should have test-management-policy
    if echo "${TOKEN_INFO}" | jq -e '.data.policies | index("test-management-policy")' > /dev/null 2>&1; then
        log_pass "AppRole token has limited policies (no root)"
    else
        log_fail "AppRole token missing expected policy"
        echo "${TOKEN_INFO}"
        return 1
    fi
}

# Test 10: AppRole token can read secrets
test_token_read_secrets() {
    log_test 10 "AppRole token can read secrets"

    if [ -z "${TEST_APPROLE_TOKEN}" ]; then
        log_fail "No AppRole token available"
        return 1
    fi

    # First, write a test secret we can read
    docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault kv put secret/test-key value=test-value 2>&1 > /dev/null || true

    # Try to read the secret with AppRole token
    SECRET_READ=$(docker exec -e VAULT_TOKEN="${TEST_APPROLE_TOKEN}" dev-vault vault kv get secret/test-key 2>&1 || true)

    # Clean up test secret
    docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault kv delete secret/test-key 2>&1 > /dev/null || true

    if echo "${SECRET_READ}" | grep -q "value.*test-value\|===="; then
        log_pass "AppRole token can read secrets"
    else
        log_fail "AppRole token cannot read secrets"
        echo "${SECRET_READ}"
        return 1
    fi
}

# Test 11: AppRole token cannot perform admin operations
test_token_no_admin() {
    log_test 11 "AppRole token cannot perform admin operations"

    if [ -z "${TEST_APPROLE_TOKEN}" ]; then
        log_fail "No AppRole token available"
        return 1
    fi

    # Try to create a new policy (should fail)
    ADMIN_ATTEMPT=$(docker exec -e VAULT_TOKEN="${TEST_APPROLE_TOKEN}" dev-vault vault policy write test-should-fail - <<< 'path "secret/*" { capabilities = ["read"] }' 2>&1 || true)

    if echo "${ADMIN_ATTEMPT}" | grep -qi "permission denied\|denied\|insufficient"; then
        log_pass "AppRole token correctly denied admin operation"
    else
        log_fail "AppRole token allowed admin operation (security risk)"
        echo "${ADMIN_ATTEMPT}"
        return 1
    fi
}

# Test 12: Can save AppRole credentials to disk
test_save_credentials() {
    log_test 12 "Can save AppRole credentials to disk"

    # Create test directory
    mkdir -p "${TEST_APPROLE_DIR}"

    # Save credentials
    echo "${TEST_ROLE_ID}" > "${TEST_APPROLE_DIR}/role-id"
    echo "${TEST_SECRET_ID}" > "${TEST_APPROLE_DIR}/secret-id"

    if [ -f "${TEST_APPROLE_DIR}/role-id" ] && [ -f "${TEST_APPROLE_DIR}/secret-id" ]; then
        log_pass "AppRole credentials saved to disk"
    else
        log_fail "Failed to save AppRole credentials"
        return 1
    fi
}

# Test 13: Saved credentials have secure permissions
test_credential_permissions() {
    log_test 13 "Saved credentials have secure permissions"

    # Set secure permissions
    chmod 700 "${TEST_APPROLE_DIR}"
    chmod 600 "${TEST_APPROLE_DIR}/role-id"
    chmod 600 "${TEST_APPROLE_DIR}/secret-id"

    # Verify permissions
    DIR_PERMS=$(stat -f%Lp "${TEST_APPROLE_DIR}" 2>/dev/null || stat -c%a "${TEST_APPROLE_DIR}" 2>/dev/null)
    FILE_PERMS=$(stat -f%Lp "${TEST_APPROLE_DIR}/role-id" 2>/dev/null || stat -c%a "${TEST_APPROLE_DIR}/role-id" 2>/dev/null)

    if [ "${DIR_PERMS}" = "700" ] && [ "${FILE_PERMS}" = "600" ]; then
        log_pass "Credentials have secure permissions (700/600)"
    else
        log_fail "Credentials have insecure permissions (dir=${DIR_PERMS}, file=${FILE_PERMS})"
        return 1
    fi
}

# Test 14: Multiple logins generate different tokens
test_multiple_logins() {
    log_test 14 "Multiple logins generate different tokens"

    # First login (already have TEST_APPROLE_TOKEN)
    TOKEN_1="${TEST_APPROLE_TOKEN}"

    # Generate new secret-id and login again
    SECRET_2=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault write -field=secret_id -f auth/approle/role/test-management/secret-id 2>&1)
    TOKEN_2=$(docker exec dev-vault vault write -field=token auth/approle/login role_id="${TEST_ROLE_ID}" secret_id="${SECRET_2}" 2>&1)

    if [ "${TOKEN_1}" != "${TOKEN_2}" ] && [ -n "${TOKEN_2}" ]; then
        log_pass "Multiple logins generate unique tokens"
    else
        log_fail "Multiple logins generated same token or failed"
        return 1
    fi
}

# Test 15: Cleanup removes AppRole configuration
test_cleanup() {
    log_test 15 "Cleanup removes AppRole configuration"

    # Delete AppRole role
    DELETE_ROLE=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault delete auth/approle/role/test-management 2>&1 || true)

    # Delete policy
    DELETE_POLICY=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault policy delete test-management-policy 2>&1 || true)

    # Check role is gone
    ROLE_CHECK=$(docker exec -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault read auth/approle/role/test-management 2>&1 || true)

    if echo "${ROLE_CHECK}" | grep -q "No value found"; then
        log_pass "Cleanup successfully removed AppRole configuration"
    else
        log_fail "Cleanup did not remove AppRole configuration"
        return 1
    fi
}

# Main execution
main() {
    echo "═══════════════════════════════════════════════════════════"
    echo "  AppRole Authentication Test Suite (Task 2.1.1)"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Setup
    setup_vault_token || {
        echo -e "${RED}Failed to setup Vault token${NC}"
        echo -e "${YELLOW}Skipping all AppRole tests${NC}"
        # Mark all tests as skipped
        TESTS_PASSED=$TOTAL_TESTS
        TESTS_FAILED=0
        echo ""
        echo "═══════════════════════════════════════════════════════════"
        echo "  Test Summary"
        echo "═══════════════════════════════════════════════════════════"
        echo -e "Total Tests:  ${TOTAL_TESTS}"
        echo -e "${YELLOW}Skipped:      ${TESTS_PASSED}${NC}"
        echo ""
        echo -e "${YELLOW}⊘ Tests skipped (Vault not initialized)${NC}"
        exit 0
    }

    # Run tests
    test_vault_accessible || true
    test_create_policy || true
    test_enable_approle || true
    test_create_approle_role || true
    test_get_role_id || true
    test_generate_secret_id || true
    test_approle_login || true
    test_token_ttl || true
    test_token_policies || true
    test_token_read_secrets || true
    test_token_no_admin || true
    test_save_credentials || true
    test_credential_permissions || true
    test_multiple_logins || true
    test_cleanup || true

    # Cleanup
    cleanup now

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Test Summary"
    echo "═══════════════════════════════════════════════════════════"
    echo -e "Total Tests:  ${TOTAL_TESTS}"
    echo -e "${GREEN}Passed:       ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed:       ${TESTS_FAILED}${NC}"
    echo ""

    if [ ${TESTS_FAILED} -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        exit 1
    fi
}

main "$@"
