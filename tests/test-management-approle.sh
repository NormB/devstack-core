#!/bin/bash
#
# Test Script: Management Script AppRole Authentication
# ======================================================
#
# This script validates that manage_devstack.py uses AppRole authentication
# for backup operations with proper fallback to root token.
#
# Tests:
#   1. Management AppRole credentials exist
#   2. Management policy is loaded in Vault
#   3. AppRole authentication works
#   4. Can retrieve secrets with AppRole token
#   5. Backup command works with AppRole
#   6. Fallback to root token works when AppRole unavailable
#   7. Backup data integrity verification
#
# Usage:
#   ./tests/test-management-approle.sh
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
TOTAL_TESTS=7

# Configuration
VAULT_ADDR="http://localhost:8200"
VAULT_CONFIG_DIR="${HOME}/.config/vault"
APPROLE_DIR="${VAULT_CONFIG_DIR}/approles/management"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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

# Test 1: Management AppRole credentials exist
test_approle_credentials_exist() {
    log_test 1 "Checking if management AppRole credentials exist"

    if [ -f "${APPROLE_DIR}/role-id" ] && [ -f "${APPROLE_DIR}/secret-id" ]; then
        log_pass "AppRole credentials exist at ${APPROLE_DIR}"
        log_info "role-id size: $(wc -c < "${APPROLE_DIR}/role-id" | tr -d ' ') bytes"
        log_info "secret-id size: $(wc -c < "${APPROLE_DIR}/secret-id" | tr -d ' ') bytes"
    else
        log_fail "AppRole credentials not found at ${APPROLE_DIR}"
        return 1
    fi
}

# Test 2: Management policy is loaded in Vault
test_management_policy_loaded() {
    log_test 2 "Checking if management policy is loaded in Vault"

    VAULT_TOKEN=$(cat "${VAULT_CONFIG_DIR}/root-token")
    export VAULT_TOKEN

    if docker exec -e VAULT_ADDR=http://localhost:8200 -e VAULT_TOKEN="${VAULT_TOKEN}" \
        dev-vault vault policy read management &>/dev/null; then
        log_pass "Management policy is loaded in Vault"

        # Count the number of paths in the policy
        POLICY_PATHS=$(docker exec -e VAULT_ADDR=http://localhost:8200 -e VAULT_TOKEN="${VAULT_TOKEN}" \
            dev-vault vault policy read management | grep -c '^path ' || true)
        log_info "Policy grants access to ${POLICY_PATHS} paths"
    else
        log_fail "Management policy not found in Vault"
        return 1
    fi
}

# Test 3: AppRole authentication works
test_approle_authentication() {
    log_test 3 "Testing AppRole authentication"

    ROLE_ID=$(cat "${APPROLE_DIR}/role-id")
    SECRET_ID=$(cat "${APPROLE_DIR}/secret-id")

    MGMT_TOKEN=$(docker exec -e VAULT_ADDR=http://localhost:8200 \
        dev-vault vault write -field=token auth/approle/login \
        role_id="${ROLE_ID}" secret_id="${SECRET_ID}" 2>/dev/null || echo "")

    if [ -n "${MGMT_TOKEN}" ] && [[ "${MGMT_TOKEN}" == hvs.* ]]; then
        log_pass "AppRole authentication successful"
        log_info "Token prefix: ${MGMT_TOKEN:0:15}..."
        log_info "Token length: ${#MGMT_TOKEN} characters"
    else
        log_fail "AppRole authentication failed"
        return 1
    fi
}

# Test 4: Can retrieve secrets with AppRole token
test_secret_retrieval() {
    log_test 4 "Testing secret retrieval with AppRole token"

    ROLE_ID=$(cat "${APPROLE_DIR}/role-id")
    SECRET_ID=$(cat "${APPROLE_DIR}/secret-id")

    MGMT_TOKEN=$(docker exec -e VAULT_ADDR=http://localhost:8200 \
        dev-vault vault write -field=token auth/approle/login \
        role_id="${ROLE_ID}" secret_id="${SECRET_ID}" 2>/dev/null)

    # Test retrieving postgres password
    POSTGRES_PASS=$(docker exec -e VAULT_ADDR=http://localhost:8200 -e VAULT_TOKEN="${MGMT_TOKEN}" \
        dev-vault vault kv get -field=password secret/postgres 2>/dev/null || echo "")

    if [ -n "${POSTGRES_PASS}" ]; then
        log_pass "Successfully retrieved postgres password with AppRole token"
        log_info "Password length: ${#POSTGRES_PASS} characters"
    else
        log_fail "Failed to retrieve postgres password with AppRole token"
        return 1
    fi
}

# Test 5: Backup command works with AppRole
test_backup_with_approle() {
    log_test 5 "Testing backup command with AppRole authentication"

    # Run backup
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup 2>&1)
    BACKUP_EXIT=$?

    if [ ${BACKUP_EXIT} -eq 0 ]; then
        # Extract backup directory from output
        BACKUP_DIR=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | tail -1)

        if [ -d "${PROJECT_ROOT}/${BACKUP_DIR}" ]; then
            log_pass "Backup completed successfully with AppRole"
            log_info "Backup location: ${BACKUP_DIR}"

            # Check backup files
            POSTGRES_SIZE=$(stat -f%z "${PROJECT_ROOT}/${BACKUP_DIR}/postgres_all.sql" 2>/dev/null || echo "0")
            MYSQL_SIZE=$(stat -f%z "${PROJECT_ROOT}/${BACKUP_DIR}/mysql_all.sql" 2>/dev/null || echo "0")
            MONGODB_SIZE=$(stat -f%z "${PROJECT_ROOT}/${BACKUP_DIR}/mongodb_dump.archive" 2>/dev/null || echo "0")

            log_info "PostgreSQL backup: ${POSTGRES_SIZE} bytes"
            log_info "MySQL backup: ${MYSQL_SIZE} bytes"
            log_info "MongoDB backup: ${MONGODB_SIZE} bytes"
        else
            log_fail "Backup directory not found: ${BACKUP_DIR}"
            return 1
        fi
    else
        log_fail "Backup command failed with exit code ${BACKUP_EXIT}"
        return 1
    fi
}

# Test 6: Fallback to root token works
test_fallback_to_root_token() {
    log_test 6 "Testing fallback to root token when AppRole unavailable"

    # Temporarily move AppRole credentials
    if [ -d "${APPROLE_DIR}" ]; then
        mv "${APPROLE_DIR}" "${APPROLE_DIR}.backup"
        log_info "Temporarily disabled AppRole credentials"
    fi

    # Run backup (should fallback to root token)
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup 2>&1)
    BACKUP_EXIT=$?

    # Restore AppRole credentials
    if [ -d "${APPROLE_DIR}.backup" ]; then
        mv "${APPROLE_DIR}.backup" "${APPROLE_DIR}"
        log_info "Restored AppRole credentials"
    fi

    if [ ${BACKUP_EXIT} -eq 0 ]; then
        log_pass "Backup succeeded using root token fallback"

        # Extract and verify backup
        BACKUP_DIR=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | tail -1)
        if [ -f "${PROJECT_ROOT}/${BACKUP_DIR}/postgres_all.sql" ]; then
            log_info "Fallback backup location: ${BACKUP_DIR}"
        fi
    else
        log_fail "Backup failed even with root token fallback"
        return 1
    fi
}

# Test 7: Backup data integrity
test_backup_data_integrity() {
    log_test 7 "Testing backup data integrity"

    # Find most recent backup
    LATEST_BACKUP=$(ls -td "${PROJECT_ROOT}"/backups/2025*/ 2>/dev/null | head -1)

    if [ -z "${LATEST_BACKUP}" ]; then
        log_fail "No backup directory found"
        return 1
    fi

    log_info "Checking backup: ${LATEST_BACKUP}"

    # Check PostgreSQL backup integrity
    if grep -q "PostgreSQL database cluster dump" "${LATEST_BACKUP}/postgres_all.sql" 2>/dev/null; then
        log_info "✓ PostgreSQL backup contains valid dump header"
    else
        log_fail "PostgreSQL backup missing dump header"
        return 1
    fi

    # Check PostgreSQL backup has CREATE ROLE statements
    if grep -q "CREATE ROLE" "${LATEST_BACKUP}/postgres_all.sql" 2>/dev/null; then
        log_info "✓ PostgreSQL backup contains role definitions"
    else
        log_fail "PostgreSQL backup missing role definitions"
        return 1
    fi

    # Check MySQL backup integrity
    if grep -q "MySQL dump" "${LATEST_BACKUP}/mysql_all.sql" 2>/dev/null; then
        log_info "✓ MySQL backup contains valid dump header"
    else
        log_fail "MySQL backup missing dump header"
        return 1
    fi

    # Check MongoDB backup exists and is not empty
    if [ -s "${LATEST_BACKUP}/mongodb_dump.archive" ]; then
        MONGO_SIZE=$(stat -f%z "${LATEST_BACKUP}/mongodb_dump.archive")
        log_info "✓ MongoDB backup exists (${MONGO_SIZE} bytes)"
    else
        log_fail "MongoDB backup is empty or missing"
        return 1
    fi

    log_pass "Backup data integrity verified"
}

# Main execution
main() {
    echo "═══════════════════════════════════════════════════════════"
    echo "  Management Script AppRole Authentication Test Suite"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Run tests
    test_approle_credentials_exist || true
    test_management_policy_loaded || true
    test_approle_authentication || true
    test_secret_retrieval || true
    test_backup_with_approle || true
    test_fallback_to_root_token || true
    test_backup_data_integrity || true

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
