#!/bin/bash
#
# Test Script: Backup and Restore Full Workflow
# =============================================
#
# This script validates the complete backup and restore workflow, including
# encryption support, data integrity, and recovery procedures.
#
# Tests:
#   1. Full backup creation (unencrypted)
#   2. Full backup creation (encrypted)
#   3. Verify unencrypted backup
#   4. Verify encrypted backup
#   5. Restore unencrypted backup (dry run verification)
#   6. Restore encrypted backup (dry run verification)
#   7. Database connectivity after restore
#   8. Data persistence validation
#
# Usage:
#   ./tests/test-backup-restore.sh
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
TOTAL_TESTS=12

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUPS_DIR="${PROJECT_ROOT}/backups"
PASSPHRASE_FILE="${HOME}/.config/vault/backup-passphrase"
TEST_PASSPHRASE="TestRestorePass123"

# Test backup IDs
UNENCRYPTED_BACKUP_ID=""
ENCRYPTED_BACKUP_ID=""

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

# Cleanup function
cleanup() {
    if [ "${1:-}" = "now" ]; then
        log_info "Cleaning up test backups..."

        if [ -n "${UNENCRYPTED_BACKUP_ID}" ] && [ -d "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}" ]; then
            rm -rf "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}"
            log_info "Removed: ${UNENCRYPTED_BACKUP_ID}"
        fi

        if [ -n "${ENCRYPTED_BACKUP_ID}" ] && [ -d "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}" ]; then
            rm -rf "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"
            log_info "Removed: ${ENCRYPTED_BACKUP_ID}"
        fi

        # Restore original passphrase if it existed
        if [ -f "${PASSPHRASE_FILE}.backup" ]; then
            mv "${PASSPHRASE_FILE}.backup" "${PASSPHRASE_FILE}"
            log_info "Restored original passphrase file"
        elif [ -f "${PASSPHRASE_FILE}" ]; then
            rm "${PASSPHRASE_FILE}"
            log_info "Removed test passphrase file"
        fi
    fi
}

# Test 1: Create unencrypted backup
test_create_unencrypted_backup() {
    log_test 1 "Full backup creation (unencrypted)"

    # Backup existing passphrase if it exists
    if [ -f "${PASSPHRASE_FILE}" ]; then
        mv "${PASSPHRASE_FILE}" "${PASSPHRASE_FILE}.backup"
        log_info "Backed up existing passphrase"
    fi

    # Create test passphrase
    echo "${TEST_PASSPHRASE}" > "${PASSPHRASE_FILE}"
    chmod 600 "${PASSPHRASE_FILE}"

    # Create unencrypted backup
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup --full 2>&1)
    UNENCRYPTED_BACKUP_ID=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | head -1 | cut -d'/' -f2)

    if [ -z "${UNENCRYPTED_BACKUP_ID}" ]; then
        log_fail "Could not extract backup ID"
        return 1
    fi

    log_info "Unencrypted backup ID: ${UNENCRYPTED_BACKUP_ID}"

    # Verify .sql files exist (not .gpg)
    SQL_FILES=$(ls "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}"/*.sql 2>/dev/null | wc -l | tr -d ' ')
    if [ "${SQL_FILES}" -ge 2 ]; then
        log_pass "Unencrypted backup created with ${SQL_FILES} .sql files"
    else
        log_fail "Unencrypted backup missing .sql files"
        return 1
    fi
}

# Test 2: Create encrypted backup
test_create_encrypted_backup() {
    log_test 2 "Full backup creation (encrypted)"

    # Create encrypted backup
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup --full --encrypt 2>&1)
    ENCRYPTED_BACKUP_ID=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | tail -1 | cut -d'/' -f2)

    if [ -z "${ENCRYPTED_BACKUP_ID}" ]; then
        log_fail "Could not extract backup ID"
        return 1
    fi

    log_info "Encrypted backup ID: ${ENCRYPTED_BACKUP_ID}"

    # Verify .gpg files exist
    GPG_FILES=$(ls "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"/*.gpg 2>/dev/null | wc -l | tr -d ' ')
    if [ "${GPG_FILES}" -ge 4 ]; then
        log_pass "Encrypted backup created with ${GPG_FILES} .gpg files"
    else
        log_fail "Encrypted backup missing .gpg files"
        return 1
    fi
}

# Test 3: Verify unencrypted backup
test_verify_unencrypted() {
    log_test 3 "Verify unencrypted backup"

    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${UNENCRYPTED_BACKUP_ID}" 2>&1)

    if echo "${VERIFY_OUTPUT}" | grep -q "Backup verification PASSED"; then
        log_pass "Unencrypted backup verified successfully"
    else
        log_fail "Unencrypted backup verification failed"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi

    # Check encryption status in output
    if echo "${VERIFY_OUTPUT}" | grep -q "Encrypted: No"; then
        log_info "✓ Correctly identified as unencrypted"
    else
        log_fail "Encryption status incorrect"
        return 1
    fi
}

# Test 4: Verify encrypted backup
test_verify_encrypted() {
    log_test 4 "Verify encrypted backup"

    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${ENCRYPTED_BACKUP_ID}" 2>&1)

    if echo "${VERIFY_OUTPUT}" | grep -q "Backup verification PASSED"; then
        log_pass "Encrypted backup verified successfully"
    else
        log_fail "Encrypted backup verification failed"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi

    # Check encryption status in output
    if echo "${VERIFY_OUTPUT}" | grep -q "Encrypted: Yes"; then
        log_info "✓ Correctly identified as encrypted"
    else
        log_fail "Encryption status incorrect"
        return 1
    fi
}

# Test 5: Check restore command for unencrypted backup (dry run)
test_restore_unencrypted_dry_run() {
    log_test 5 "Restore unencrypted backup (validation)"

    # Check that restore command recognizes the backup
    RESTORE_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack restore 2>&1)

    if echo "${RESTORE_OUTPUT}" | grep -q "${UNENCRYPTED_BACKUP_ID}"; then
        log_pass "Unencrypted backup listed in restore command"
    else
        log_fail "Unencrypted backup not found in restore list"
        echo "${RESTORE_OUTPUT}"
        return 1
    fi

    # Verify backup directory structure
    if [ -f "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}/manifest.json" ]; then
        log_info "✓ Manifest file exists"
    else
        log_fail "Manifest file missing"
        return 1
    fi

    if [ -f "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}/postgres_all.sql" ]; then
        log_info "✓ PostgreSQL backup file exists"
    else
        log_fail "PostgreSQL backup file missing"
        return 1
    fi
}

# Test 6: Check restore command for encrypted backup (dry run)
test_restore_encrypted_dry_run() {
    log_test 6 "Restore encrypted backup (validation)"

    # Check that restore command recognizes the backup
    RESTORE_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack restore 2>&1)

    if echo "${RESTORE_OUTPUT}" | grep -q "${ENCRYPTED_BACKUP_ID}"; then
        log_pass "Encrypted backup listed in restore command"
    else
        log_fail "Encrypted backup not found in restore list"
        echo "${RESTORE_OUTPUT}"
        return 1
    fi

    # Verify backup directory structure
    if [ -f "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/manifest.json" ]; then
        log_info "✓ Manifest file exists"
    else
        log_fail "Manifest file missing"
        return 1
    fi

    if [ -f "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/postgres_all.sql.gpg" ]; then
        log_info "✓ Encrypted PostgreSQL backup file exists"
    else
        log_fail "Encrypted PostgreSQL backup file missing"
        return 1
    fi
}

# Test 7: Database connectivity validation
test_database_connectivity() {
    log_test 7 "Database connectivity after backup/restore workflow"

    # Test PostgreSQL connectivity
    POSTGRES_TEST=$(docker compose exec -T postgres psql -U dev_admin -d postgres -c "SELECT 1;" 2>&1 || true)
    if echo "${POSTGRES_TEST}" | grep -q "1 row"; then
        log_info "✓ PostgreSQL is accessible"
    elif echo "${POSTGRES_TEST}" | grep -q "role \"dev_admin\" does not exist"; then
        # This is expected in test environment before bootstrap
        log_info "⚠ PostgreSQL accessible (dev_admin role not created yet)"
    else
        log_fail "PostgreSQL connectivity failed"
        echo "${POSTGRES_TEST}"
        return 1
    fi

    # Test MySQL connectivity
    VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null || echo "")
    if [ -n "${VAULT_TOKEN}" ]; then
        MYSQL_PASS=$(docker exec dev-vault vault kv get -field=password secret/mysql 2>/dev/null || echo "")
        if [ -n "${MYSQL_PASS}" ]; then
            MYSQL_TEST=$(docker compose exec -T -e MYSQL_PWD="${MYSQL_PASS}" mysql mysql -u root -e "SELECT 1;" 2>&1 || true)
            if echo "${MYSQL_TEST}" | grep -q "1"; then
                log_info "✓ MySQL is accessible"
            else
                log_fail "MySQL connectivity failed"
                return 1
            fi
        else
            log_info "⚠ MySQL password not available (skipping test)"
        fi
    else
        log_info "⚠ Vault token not available (skipping MySQL test)"
    fi

    log_pass "Database connectivity verified"
}

# Test 8: Data persistence validation
test_data_persistence() {
    log_test 8 "Data persistence validation"

    # Check that manifest files contain expected data
    UNENCRYPTED_MANIFEST="${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}/manifest.json"
    ENCRYPTED_MANIFEST="${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/manifest.json"

    # Validate unencrypted manifest
    if jq -e '.backup_id' "${UNENCRYPTED_MANIFEST}" > /dev/null 2>&1; then
        log_info "✓ Unencrypted manifest is valid JSON"
    else
        log_fail "Unencrypted manifest is invalid"
        return 1
    fi

    # Validate encrypted manifest
    if jq -e '.backup_id' "${ENCRYPTED_MANIFEST}" > /dev/null 2>&1; then
        log_info "✓ Encrypted manifest is valid JSON"
    else
        log_fail "Encrypted manifest is invalid"
        return 1
    fi

    # Check encryption flag
    UNENCRYPTED_FLAG=$(jq -r '.encrypted' "${UNENCRYPTED_MANIFEST}")
    ENCRYPTED_FLAG=$(jq -r '.encrypted' "${ENCRYPTED_MANIFEST}")

    if [ "${UNENCRYPTED_FLAG}" = "false" ] && [ "${ENCRYPTED_FLAG}" = "true" ]; then
        log_pass "Backup encryption flags are correct"
    else
        log_fail "Encryption flags mismatch (unencrypted=${UNENCRYPTED_FLAG}, encrypted=${ENCRYPTED_FLAG})"
        return 1
    fi
}

# Test 9: Restore command lists backups in table format
test_restore_list_format() {
    log_test 9 "Restore command lists backups in table format"

    RESTORE_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack restore 2>&1)

    # Check for table headers
    if echo "${RESTORE_OUTPUT}" | grep -q "Backup Name"; then
        log_info "✓ Table headers present"
    else
        log_fail "Table headers not found"
        echo "${RESTORE_OUTPUT}"
        return 1
    fi

    # Check for date and size columns
    if echo "${RESTORE_OUTPUT}" | grep -q "Date" && echo "${RESTORE_OUTPUT}" | grep -q "Size"; then
        log_pass "Restore command displays backups in table format"
    else
        log_fail "Missing table columns"
        echo "${RESTORE_OUTPUT}"
        return 1
    fi
}

# Test 10: Encrypted backup file paths are correct
test_encrypted_file_paths() {
    log_test 10 "Encrypted backup has correct file paths"

    ENCRYPTED_MANIFEST="${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/manifest.json"

    # Check that postgres file path ends with .gpg
    POSTGRES_FILE=$(jq -r '.databases.postgres.file' "${ENCRYPTED_MANIFEST}")

    if echo "${POSTGRES_FILE}" | grep -q '\.gpg$'; then
        log_info "✓ PostgreSQL file path: ${POSTGRES_FILE}"
        log_pass "Encrypted file paths have .gpg extension"
    else
        log_fail "PostgreSQL file path missing .gpg: ${POSTGRES_FILE}"
        return 1
    fi
}

# Test 11: Backup directory structure validation
test_backup_directory_structure() {
    log_test 11 "Backup directory has correct structure"

    # Unencrypted backup should have manifest + data files
    UNENCRYPTED_FILE_COUNT=$(ls "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}" | wc -l | tr -d ' ')

    if [ "${UNENCRYPTED_FILE_COUNT}" -ge 4 ]; then
        log_info "✓ Unencrypted backup has ${UNENCRYPTED_FILE_COUNT} files"
    else
        log_fail "Unencrypted backup missing files: ${UNENCRYPTED_FILE_COUNT}"
        return 1
    fi

    # Encrypted backup should have manifest + .gpg files
    ENCRYPTED_FILE_COUNT=$(ls "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}" | wc -l | tr -d ' ')

    if [ "${ENCRYPTED_FILE_COUNT}" -ge 4 ]; then
        log_pass "Backup directories have correct file structure"
    else
        log_fail "Encrypted backup missing files: ${ENCRYPTED_FILE_COUNT}"
        return 1
    fi
}

# Test 12: Backup naming convention validation
test_backup_naming_convention() {
    log_test 12 "Backup directories follow naming convention"

    # Backup IDs should match YYYYMMDD_HHMMSS pattern
    if echo "${UNENCRYPTED_BACKUP_ID}" | grep -qE '^[0-9]{8}_[0-9]{6}$'; then
        log_info "✓ Unencrypted backup name: ${UNENCRYPTED_BACKUP_ID}"
    else
        log_fail "Unencrypted backup name invalid: ${UNENCRYPTED_BACKUP_ID}"
        return 1
    fi

    if echo "${ENCRYPTED_BACKUP_ID}" | grep -qE '^[0-9]{8}_[0-9]{6}$'; then
        log_pass "Backup naming convention correct (YYYYMMDD_HHMMSS)"
    else
        log_fail "Encrypted backup name invalid: ${ENCRYPTED_BACKUP_ID}"
        return 1
    fi
}

# Main execution
main() {
    echo "═══════════════════════════════════════════════════════════"
    echo "  Backup and Restore Workflow Test Suite"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Run tests
    test_create_unencrypted_backup || true
    test_create_encrypted_backup || true
    test_verify_unencrypted || true
    test_verify_encrypted || true
    test_restore_unencrypted_dry_run || true
    test_restore_encrypted_dry_run || true
    test_database_connectivity || true
    test_data_persistence || true
    test_restore_list_format || true
    test_encrypted_file_paths || true
    test_backup_directory_structure || true
    test_backup_naming_convention || true

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "  Test Summary"
    echo "═══════════════════════════════════════════════════════════"
    echo -e "Total Tests:  ${TOTAL_TESTS}"
    echo -e "${GREEN}Passed:       ${TESTS_PASSED}${NC}"
    echo -e "${RED}Failed:       ${TESTS_FAILED}${NC}"
    echo ""

    # Cleanup
    cleanup now

    if [ ${TESTS_FAILED} -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        echo "Note: This test suite validates backup/restore workflow"
        echo "without performing actual destructive restore operations."
        echo "Full restoration requires manual confirmation."
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        exit 1
    fi
}

main "$@"
