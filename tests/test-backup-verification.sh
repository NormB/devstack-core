#!/bin/bash
#
# Test Script: Backup Verification Functionality
# ==============================================
#
# This script validates checksum-based backup verification, ensuring backup
# integrity can be verified using SHA256 checksums from manifest files.
#
# Tests:
#   1. Valid backup verification (all checksums match)
#   2. Corrupted file detection (checksum mismatch)
#   3. Missing file detection
#   4. Missing manifest handling
#   5. Corrupted manifest handling
#   6. Encrypted backup verification
#   7. Unencrypted backup verification
#   8. Verify --all flag functionality
#
# Usage:
#   ./tests/test-backup-verification.sh
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
TEST_PASSPHRASE="TestVerifyPass123"

# Test backup IDs
VALID_BACKUP_ID=""
CORRUPTED_BACKUP_ID=""
MISSING_FILE_BACKUP_ID=""

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

        if [ -n "${VALID_BACKUP_ID}" ] && [ -d "${BACKUPS_DIR}/${VALID_BACKUP_ID}" ]; then
            rm -rf "${BACKUPS_DIR}/${VALID_BACKUP_ID}"
            log_info "Removed: ${VALID_BACKUP_ID}"
        fi

        if [ -n "${CORRUPTED_BACKUP_ID}" ] && [ -d "${BACKUPS_DIR}/${CORRUPTED_BACKUP_ID}" ]; then
            rm -rf "${BACKUPS_DIR}/${CORRUPTED_BACKUP_ID}"
            log_info "Removed: ${CORRUPTED_BACKUP_ID}"
        fi

        if [ -n "${MISSING_FILE_BACKUP_ID}" ] && [ -d "${BACKUPS_DIR}/${MISSING_FILE_BACKUP_ID}" ]; then
            rm -rf "${BACKUPS_DIR}/${MISSING_FILE_BACKUP_ID}"
            log_info "Removed: ${MISSING_FILE_BACKUP_ID}"
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

# Test 1: Valid backup verification
test_valid_backup() {
    log_test 1 "Valid backup verification (all checksums match)"

    # Backup existing passphrase if it exists
    if [ -f "${PASSPHRASE_FILE}" ]; then
        mv "${PASSPHRASE_FILE}" "${PASSPHRASE_FILE}.backup"
        log_info "Backed up existing passphrase"
    fi

    # Create test passphrase
    echo "${TEST_PASSPHRASE}" > "${PASSPHRASE_FILE}"
    chmod 600 "${PASSPHRASE_FILE}"

    # Create valid backup
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup --full 2>&1)
    VALID_BACKUP_ID=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | head -1 | cut -d'/' -f2)

    if [ -z "${VALID_BACKUP_ID}" ]; then
        log_fail "Could not extract backup ID"
        return 1
    fi

    log_info "Valid backup ID: ${VALID_BACKUP_ID}"

    # Verify backup
    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${VALID_BACKUP_ID}" 2>&1)

    if echo "${VERIFY_OUTPUT}" | grep -q "Backup verification PASSED"; then
        log_pass "Valid backup verified successfully"
    else
        log_fail "Valid backup verification failed"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 2: Corrupted file detection
test_corrupted_file() {
    log_test 2 "Corrupted file detection (checksum mismatch)"

    # Create backup for corruption test
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup --full 2>&1)
    CORRUPTED_BACKUP_ID=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | tail -1 | cut -d'/' -f2)

    if [ -z "${CORRUPTED_BACKUP_ID}" ]; then
        log_fail "Could not extract backup ID"
        return 1
    fi

    log_info "Corrupted backup ID: ${CORRUPTED_BACKUP_ID}"

    # Corrupt a file (append data to change checksum)
    MYSQL_FILE="${BACKUPS_DIR}/${CORRUPTED_BACKUP_ID}/mysql_all.sql"
    echo "-- CORRUPTED DATA" >> "${MYSQL_FILE}"

    # Verify backup (should fail)
    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${CORRUPTED_BACKUP_ID}" 2>&1 || true)

    if echo "${VERIFY_OUTPUT}" | grep -q "Backup verification FAILED"; then
        log_info "✓ Verification correctly detected corruption"
    else
        log_fail "Verification did not detect corrupted file"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi

    if echo "${VERIFY_OUTPUT}" | grep -q "mysql_all.sql.*Checksum mismatch"; then
        log_pass "Checksum mismatch correctly reported"
    else
        log_fail "Checksum mismatch not reported correctly"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 3: Missing file detection
test_missing_file() {
    log_test 3 "Missing file detection"

    # Create backup for missing file test
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup --full 2>&1)
    MISSING_FILE_BACKUP_ID=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | tail -1 | cut -d'/' -f2)

    if [ -z "${MISSING_FILE_BACKUP_ID}" ]; then
        log_fail "Could not extract backup ID"
        return 1
    fi

    log_info "Missing file backup ID: ${MISSING_FILE_BACKUP_ID}"

    # Delete a file
    MONGODB_FILE="${BACKUPS_DIR}/${MISSING_FILE_BACKUP_ID}/mongodb_dump.archive"
    rm -f "${MONGODB_FILE}"

    # Verify backup (should fail)
    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${MISSING_FILE_BACKUP_ID}" 2>&1 || true)

    if echo "${VERIFY_OUTPUT}" | grep -q "Backup verification FAILED"; then
        log_info "✓ Verification correctly detected missing file"
    else
        log_fail "Verification did not detect missing file"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi

    if echo "${VERIFY_OUTPUT}" | grep -q "mongodb_dump.archive.*FILE MISSING"; then
        log_pass "Missing file correctly reported"
    else
        log_fail "Missing file not reported correctly"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 4: Missing manifest handling
test_missing_manifest() {
    log_test 4 "Missing manifest handling"

    # Create temporary backup directory without manifest
    TEMP_BACKUP_ID="test_no_manifest_$(date +%Y%m%d_%H%M%S)"
    TEMP_BACKUP_DIR="${BACKUPS_DIR}/${TEMP_BACKUP_ID}"
    mkdir -p "${TEMP_BACKUP_DIR}"

    # Try to verify (should fail gracefully)
    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${TEMP_BACKUP_ID}" 2>&1 || true)

    # Clean up temp directory
    rm -rf "${TEMP_BACKUP_DIR}"

    if echo "${VERIFY_OUTPUT}" | grep -qi "manifest.*not found\|cannot verify"; then
        log_pass "Missing manifest handled gracefully"
    else
        log_fail "Missing manifest not handled properly"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 5: Corrupted manifest handling
test_corrupted_manifest() {
    log_test 5 "Corrupted manifest handling"

    # Use the valid backup and corrupt its manifest
    MANIFEST_FILE="${BACKUPS_DIR}/${VALID_BACKUP_ID}/manifest.json"

    # Backup original manifest
    cp "${MANIFEST_FILE}" "${MANIFEST_FILE}.backup"

    # Corrupt manifest (invalid JSON)
    echo "{ corrupted json data" > "${MANIFEST_FILE}"

    # Try to verify (should fail gracefully)
    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${VALID_BACKUP_ID}" 2>&1 || true)

    # Restore original manifest
    mv "${MANIFEST_FILE}.backup" "${MANIFEST_FILE}"

    if echo "${VERIFY_OUTPUT}" | grep -qi "manifest.*corrupted\|Expecting property name"; then
        log_pass "Corrupted manifest handled gracefully"
    else
        log_fail "Corrupted manifest not handled properly"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 6: Encrypted backup verification
test_encrypted_backup() {
    log_test 6 "Encrypted backup verification"

    # Create encrypted backup
    BACKUP_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack backup --full --encrypt 2>&1)
    ENCRYPTED_BACKUP_ID=$(echo "${BACKUP_OUTPUT}" | grep -o 'backups/[0-9]\{8\}_[0-9]\{6\}' | tail -1 | cut -d'/' -f2)

    if [ -z "${ENCRYPTED_BACKUP_ID}" ]; then
        log_fail "Could not extract encrypted backup ID"
        return 1
    fi

    log_info "Encrypted backup ID: ${ENCRYPTED_BACKUP_ID}"

    # Verify .gpg files exist
    GPG_FILES=$(ls "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"/*.gpg 2>/dev/null | wc -l | tr -d ' ')
    if [ "${GPG_FILES}" -ge 4 ]; then
        log_info "✓ Found ${GPG_FILES} encrypted files"
    else
        log_fail "Expected at least 4 .gpg files, found: ${GPG_FILES}"
        rm -rf "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"
        return 1
    fi

    # Verify encrypted backup
    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${ENCRYPTED_BACKUP_ID}" 2>&1)

    # Clean up encrypted backup
    rm -rf "${BACKUPS_DIR}/${ENCRYPTED_BACKUP_ID}"

    if echo "${VERIFY_OUTPUT}" | grep -q "Backup verification PASSED"; then
        log_pass "Encrypted backup verified successfully"
    else
        log_fail "Encrypted backup verification failed"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 7: Unencrypted backup verification
test_unencrypted_backup() {
    log_test 7 "Unencrypted backup verification"

    # Verify the valid backup (which is unencrypted)
    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${VALID_BACKUP_ID}" 2>&1)

    # Check for unencrypted indicator
    if echo "${VERIFY_OUTPUT}" | grep -q "Encrypted: No"; then
        log_info "✓ Correctly identified as unencrypted"
    else
        log_fail "Encryption status not reported correctly"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi

    # Verify .sql files exist (not .gpg)
    SQL_FILES=$(ls "${BACKUPS_DIR}/${VALID_BACKUP_ID}"/*.sql 2>/dev/null | wc -l | tr -d ' ')
    if [ "${SQL_FILES}" -ge 2 ]; then
        log_info "✓ Found ${SQL_FILES} unencrypted .sql files"
    else
        log_fail "Expected at least 2 .sql files, found: ${SQL_FILES}"
        return 1
    fi

    if echo "${VERIFY_OUTPUT}" | grep -q "Backup verification PASSED"; then
        log_pass "Unencrypted backup verified successfully"
    else
        log_fail "Unencrypted backup verification failed"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 8: Verify --all flag
test_verify_all() {
    log_test 8 "Verify --all flag functionality"

    # Run verify --all
    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify --all 2>&1 || true)

    # Should show results for multiple backups
    PASSED_COUNT=$(echo "${VERIFY_OUTPUT}" | grep -c "PASS" || true)
    FAILED_COUNT=$(echo "${VERIFY_OUTPUT}" | grep -c "FAIL" || true)

    log_info "Passed: ${PASSED_COUNT}, Failed: ${FAILED_COUNT}"

    # We created at least 3 backups (valid, corrupted, missing file)
    # Some will pass, some will fail
    if [ $((PASSED_COUNT + FAILED_COUNT)) -ge 6 ]; then
        log_info "✓ Verified multiple backups"
    else
        log_fail "--all flag did not verify expected number of backups"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi

    # Check that summary is shown
    if echo "${VERIFY_OUTPUT}" | grep -q "Summary:"; then
        log_pass "--all flag verified multiple backups with summary"
    else
        log_fail "Summary not displayed"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 9: Verification performance
test_verification_performance() {
    log_test 9 "Verification completes in reasonable time"

    START_TIME=$(date +%s)

    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${VALID_BACKUP_ID}" 2>&1)

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    # Verification should complete in under 5 seconds
    if [ "${DURATION}" -lt 5 ]; then
        log_info "✓ Verification time: ${DURATION} seconds"
        log_pass "Verification performance acceptable"
    else
        log_fail "Verification too slow: ${DURATION} seconds"
        return 1
    fi
}

# Test 10: Verification reports file sizes
test_verification_reports_sizes() {
    log_test 10 "Verification reports file sizes in output"

    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${VALID_BACKUP_ID}" 2>&1)

    # Check for size reporting (KB, MB, etc.)
    if echo "${VERIFY_OUTPUT}" | grep -qE '[0-9]+\.[0-9]+ (KB|MB|GB|bytes)'; then
        log_pass "File sizes reported in verification output"
    else
        log_fail "File sizes not reported"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 11: Verification detects extra files
test_verification_extra_files() {
    log_test 11 "Verification handles extra files correctly"

    # Create an extra file in backup directory
    EXTRA_FILE="${BACKUPS_DIR}/${VALID_BACKUP_ID}/extra_file.txt"
    echo "unexpected file" > "${EXTRA_FILE}"

    VERIFY_OUTPUT=$(cd "${PROJECT_ROOT}" &&../devstack verify "${VALID_BACKUP_ID}" 2>&1)

    # Clean up extra file
    rm -f "${EXTRA_FILE}"

    # Verification should still pass (extra files are not an error, missing files are)
    if echo "${VERIFY_OUTPUT}" | grep -q "PASSED"; then
        log_pass "Verification handles extra files gracefully"
    else
        log_fail "Verification failed due to extra file"
        echo "${VERIFY_OUTPUT}"
        return 1
    fi
}

# Test 12: Verification exit codes
test_verification_exit_codes() {
    log_test 12 "Verification returns correct exit codes"

    # Valid backup should return 0
    cd "${PROJECT_ROOT}" &&../devstack verify "${VALID_BACKUP_ID}" > /dev/null 2>&1
    VALID_EXIT=$?

    if [ "${VALID_EXIT}" -eq 0 ]; then
        log_info "✓ Valid backup returns exit code 0"
    else
        log_fail "Valid backup returned exit code: ${VALID_EXIT}"
        return 1
    fi

    # Corrupted backup should return non-zero
    cd "${PROJECT_ROOT}" &&../devstack verify "${CORRUPTED_BACKUP_ID}" > /dev/null 2>&1 || CORRUPTED_EXIT=$?

    if [ "${CORRUPTED_EXIT}" -ne 0 ]; then
        log_pass "Exit codes correctly indicate verification status"
    else
        log_fail "Corrupted backup returned exit code 0 (should fail)"
        return 1
    fi
}

# Main execution
main() {
    echo "═══════════════════════════════════════════════════════════"
    echo "  Backup Verification Test Suite"
    echo "═══════════════════════════════════════════════════════════"
    echo ""

    # Run tests
    test_valid_backup || true
    test_corrupted_file || true
    test_missing_file || true
    test_missing_manifest || true
    test_corrupted_manifest || true
    test_encrypted_backup || true
    test_unencrypted_backup || true
    test_verify_all || true
    test_verification_performance || true
    test_verification_reports_sizes || true
    test_verification_extra_files || true
    test_verification_exit_codes || true

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
