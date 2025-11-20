#!/bin/bash
#
# Test Script: Backup Encryption Functionality
# ==============================================
#
# This script validates GPG-based backup encryption with AES256 symmetric
# encryption, passphrase management, and manifest tracking.
#
# Tests:
#   1. GPG is installed and available
#   2. Passphrase file can be created with secure permissions
#   3. Encrypted backup creates .gpg files
#   4. Manifest reflects encryption status
#   5. Encrypted files can be decrypted
#   6. Decrypted content matches original
#   7. Unencrypted backups still work
#   8. Encryption metadata in manifest is correct
#
# Usage:
#   ./tests/test-backup-encryption.sh
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
TEST_PASSPHRASE="TestEncryptionPass123"

# Test backup IDs
ENCRYPTED_BACKUP_ID=""
UNENCRYPTED_BACKUP_ID=""

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

        if [ -n "${ENCRYPTED_BACKUP_ID}" ] && [ -d "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}" ]; then
            rm -rf "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"
            log_info "Removed: ${ENCRYPTED_BACKUP_ID}"
        fi

        if [ -n "${UNENCRYPTED_BACKUP_ID}" ] && [ -d "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}" ]; then
            rm -rf "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}"
            log_info "Removed: ${UNENCRYPTED_BACKUP_ID}"
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

# Test 1: GPG is installed
test_gpg_installed() {
    log_test 1 "GPG is installed and available"

    if which gpg > /dev/null 2>&1; then
        GPG_VERSION=$(gpg --version | head -1)
        log_pass "GPG found: ${GPG_VERSION}"
    else
        log_fail "GPG not found in PATH"
        return 1
    fi
}

# Test 2: Passphrase file creation
test_passphrase_creation() {
    log_test 2 "Passphrase file can be created with secure permissions"

    # Backup existing passphrase if it exists
    if [ -f "${PASSPHRASE_FILE}" ]; then
        mv "${PASSPHRASE_FILE}" "${PASSPHRASE_FILE}.backup"
        log_info "Backed up existing passphrase"
    fi

    # Create test passphrase
    echo "${TEST_PASSPHRASE}" > "${PASSPHRASE_FILE}"
    chmod 600 "${PASSPHRASE_FILE}"

    # Verify permissions
    PERMS=$(stat -f%Lp "${PASSPHRASE_FILE}")
    if [ "${PERMS}" = "600" ]; then
        log_pass "Passphrase file created with correct permissions (600)"
    else
        log_fail "Passphrase file has wrong permissions: ${PERMS}"
        return 1
    fi
}

# Test 3: Encrypted backup creates .gpg files
test_encrypted_backup_files() {
    log_test 3 "Encrypted backup creates .gpg files"

    # Run encrypted backup
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup --encrypt 2>&1)
    ENCRYPTED_BACKUP_ID=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | head -1 | cut -d'/' -f2)

    if [ -z "${ENCRYPTED_BACKUP_ID}" ]; then
        log_fail "Could not extract backup ID"
        return 1
    fi

    log_info "Encrypted backup ID: ${ENCRYPTED_BACKUP_ID}"

    # Count .gpg files
    GPG_FILES=$(ls "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"/*.gpg 2>/dev/null | wc -l | tr -d ' ')

    if [ "${GPG_FILES}" -ge 4 ]; then
        log_pass "Found ${GPG_FILES} encrypted .gpg files"
    else
        log_fail "Expected at least 4 .gpg files, found: ${GPG_FILES}"
        return 1
    fi

    # Verify no unencrypted database files exist
    SQL_FILES=$(ls "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"/*.sql 2>/dev/null | wc -l | tr -d ' ')
    if [ "${SQL_FILES}" -eq 0 ]; then
        log_info "✓ No unencrypted .sql files found (security confirmed)"
    else
        log_fail "Found ${SQL_FILES} unencrypted .sql files (security risk)"
        return 1
    fi
}

# Test 4: Manifest reflects encryption status
test_manifest_encryption() {
    log_test 4 "Manifest reflects encryption status"

    MANIFEST_FILE="${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/manifest.json"

    # Check encrypted flag
    ENCRYPTED=$(jq -r '.encrypted' "${MANIFEST_FILE}")
    if [ "${ENCRYPTED}" != "true" ]; then
        log_fail "Manifest encrypted flag is not true: ${ENCRYPTED}"
        return 1
    fi

    # Check encryption metadata
    ALGORITHM=$(jq -r '.encryption.algorithm' "${MANIFEST_FILE}")
    METHOD=$(jq -r '.encryption.method' "${MANIFEST_FILE}")

    if [ "${ALGORITHM}" = "AES256" ] && [ "${METHOD}" = "GPG symmetric" ]; then
        log_pass "Encryption metadata correct (${ALGORITHM}, ${METHOD})"
    else
        log_fail "Encryption metadata incorrect"
        return 1
    fi
}

# Test 5: Encrypted files can be decrypted
test_file_decryption() {
    log_test 5 "Encrypted files can be decrypted"

    POSTGRES_GPG="${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/postgres_all.sql.gpg"
    TEST_OUTPUT="/tmp/test_decrypt_$$.sql"

    if [ ! -f "${POSTGRES_GPG}" ]; then
        log_fail "PostgreSQL encrypted file not found"
        return 1
    fi

    # Decrypt file
    if gpg --decrypt --batch --yes --passphrase "${TEST_PASSPHRASE}" \
        --output "${TEST_OUTPUT}" "${POSTGRES_GPG}" 2>/dev/null; then
        log_pass "File decryption successful"
        rm -f "${TEST_OUTPUT}"
    else
        log_fail "File decryption failed"
        return 1
    fi
}

# Test 6: Decrypted content matches original structure
test_decrypted_content() {
    log_test 6 "Decrypted content matches original database dump structure"

    POSTGRES_GPG="${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/postgres_all.sql.gpg"
    TEST_OUTPUT="/tmp/test_decrypt_$$.sql"

    # Decrypt file
    gpg --decrypt --batch --yes --passphrase "${TEST_PASSPHRASE}" \
        --output "${TEST_OUTPUT}" "${POSTGRES_GPG}" 2>/dev/null

    # Check for PostgreSQL dump header
    if grep -q "PostgreSQL database cluster dump" "${TEST_OUTPUT}"; then
        log_info "✓ PostgreSQL dump header found"
    else
        log_fail "PostgreSQL dump header not found in decrypted file"
        rm -f "${TEST_OUTPUT}"
        return 1
    fi

    # Check for role definitions
    if grep -q "CREATE ROLE" "${TEST_OUTPUT}"; then
        log_info "✓ Database role definitions found"
    else
        log_fail "Database role definitions not found"
        rm -f "${TEST_OUTPUT}"
        return 1
    fi

    log_pass "Decrypted content structure verified"
    rm -f "${TEST_OUTPUT}"
}

# Test 7: Unencrypted backups still work
test_unencrypted_backup() {
    log_test 7 "Unencrypted backups still work normally"

    # Run unencrypted backup
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup 2>&1)
    UNENCRYPTED_BACKUP_ID=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | tail -1 | cut -d'/' -f2)

    if [ -z "${UNENCRYPTED_BACKUP_ID}" ]; then
        log_fail "Could not extract unencrypted backup ID"
        return 1
    fi

    log_info "Unencrypted backup ID: ${UNENCRYPTED_BACKUP_ID}"

    # Verify .sql files exist (not .gpg)
    SQL_FILES=$(ls "${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}"/*.sql 2>/dev/null | wc -l | tr -d ' ')
    if [ "${SQL_FILES}" -ge 2 ]; then
        log_info "✓ Found ${SQL_FILES} unencrypted .sql files"
    else
        log_fail "Unencrypted backup missing .sql files"
        return 1
    fi

    # Check manifest encrypted flag
    MANIFEST_FILE="${BACKUPS_DIR}/${UNENCRYPTED_BACKUP_ID}/manifest.json"
    ENCRYPTED=$(jq -r '.encrypted' "${MANIFEST_FILE}")

    if [ "${ENCRYPTED}" = "false" ]; then
        log_pass "Unencrypted backup working correctly"
    else
        log_fail "Unencrypted backup marked as encrypted"
        return 1
    fi
}

# Test 8: File metadata in manifest
test_encrypted_file_metadata() {
    log_test 8 "Encryption metadata in manifest is complete"

    MANIFEST_FILE="${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/manifest.json"

    # Check postgres metadata
    POSTGRES_FILE=$(jq -r '.databases.postgres.file' "${MANIFEST_FILE}")
    ORIGINAL_FILE=$(jq -r '.databases.postgres.original_file' "${MANIFEST_FILE}")
    CHECKSUM=$(jq -r '.databases.postgres.checksum' "${MANIFEST_FILE}")

    if [ "${POSTGRES_FILE}" = "postgres_all.sql.gpg" ]; then
        log_info "✓ Encrypted filename correct"
    else
        log_fail "Encrypted filename wrong: ${POSTGRES_FILE}"
        return 1
    fi

    if [ "${ORIGINAL_FILE}" = "postgres_all.sql" ]; then
        log_info "✓ Original filename tracked"
    else
        log_fail "Original filename not tracked: ${ORIGINAL_FILE}"
        return 1
    fi

    if [[ "${CHECKSUM}" == sha256:* ]]; then
        log_info "✓ Checksum present for encrypted file"
    else
        log_fail "Checksum missing or invalid"
        return 1
    fi

    log_pass "All encryption metadata fields present and correct"
}

# Test 9: Encryption algorithm verification
test_encryption_algorithm() {
    log_test 9 "Encryption uses AES256 algorithm"

    MANIFEST_FILE="${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/manifest.json"

    ALGORITHM=$(jq -r '.encryption.algorithm' "${MANIFEST_FILE}")

    if [ "${ALGORITHM}" = "AES256" ]; then
        log_pass "Correct encryption algorithm (AES256)"
    else
        log_fail "Wrong encryption algorithm: ${ALGORITHM}"
        return 1
    fi
}

# Test 10: Encrypted file cannot be read without decryption
test_encrypted_file_unreadable() {
    log_test 10 "Encrypted files cannot be read without decryption"

    POSTGRES_GPG="${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}/postgres_all.sql.gpg"

    # Try to read encrypted file as text (should not find SQL markers)
    if head -n 20 "${POSTGRES_GPG}" | grep -q "PostgreSQL database cluster dump"; then
        log_fail "Encrypted file contains readable SQL (not encrypted properly)"
        return 1
    else
        log_pass "Encrypted file is not readable as plaintext"
    fi
}

# Test 11: Passphrase file has secure permissions
test_passphrase_permissions() {
    log_test 11 "Passphrase file has secure permissions (600)"

    PERMS=$(stat -f%Lp "${PASSPHRASE_FILE}" 2>/dev/null || stat -c%a "${PASSPHRASE_FILE}" 2>/dev/null)

    if [ "${PERMS}" = "600" ]; then
        log_pass "Passphrase file has secure permissions (600)"
    else
        log_fail "Passphrase file has insecure permissions: ${PERMS}"
        return 1
    fi
}

# Test 12: Original files deleted after encryption
test_original_files_deleted() {
    log_test 12 "Original unencrypted files deleted after encryption"

    # Check that no .sql files exist in encrypted backup (only .gpg)
    SQL_FILES=$(ls "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"/*.sql 2>/dev/null | wc -l | tr -d ' ')

    if [ "${SQL_FILES}" -eq 0 ]; then
        log_pass "Original unencrypted files properly deleted"
    else
        log_fail "Found ${SQL_FILES} unencrypted .sql files (security risk)"
        return 1
    fi

    # Verify .gpg files exist
    GPG_FILES=$(ls "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"/*.gpg 2>/dev/null | wc -l | tr -d ' ')
    if [ "${GPG_FILES}" -ge 4 ]; then
        log_info "✓ Encrypted .gpg files present: ${GPG_FILES}"
    else
        log_fail "Missing .gpg files"
        return 1
    fi
}

# Main execution
main() {
    echo "═══════════════════════════════════════════════════════════"
    echo "  Backup Encryption Test Suite"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Run tests
    test_gpg_installed || true
    test_passphrase_creation || true
    test_encrypted_backup_files || true
    test_manifest_encryption || true
    test_file_decryption || true
    test_decrypted_content || true
    test_unencrypted_backup || true
    test_encrypted_file_metadata || true
    test_encryption_algorithm || true
    test_encrypted_file_unreadable || true
    test_passphrase_permissions || true
    test_original_files_deleted || true

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
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        exit 1
    fi
}

main "$@"
