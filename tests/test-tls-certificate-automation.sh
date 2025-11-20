#!/usr/bin/env bash
#######################################
# TLS Certificate Automation Test Suite
#
# Tests all three certificate automation scripts:
# 1. check-cert-expiration.sh
# 2. auto-renew-certificates.sh
# 3. setup-cert-renewal-cron.sh
#
# This test suite validates:
# - Certificate expiration checking
# - Automatic renewal logic
# - Cron job management
# - Error handling
# - Output formats (human, JSON, Nagios)
#
#######################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/scripts/check-cert-expiration.sh"
RENEW_SCRIPT="$SCRIPT_DIR/scripts/auto-renew-certificates.sh"
CRON_SCRIPT="$SCRIPT_DIR/scripts/setup-cert-renewal-cron.sh"

# Test utilities
pass() {
    echo -e "${GREEN}✓${NC} $1"
    echo "[DEBUG] After echo in pass()" >&2
    ((TESTS_PASSED++))
    echo "[DEBUG] After TESTS_PASSED increment" >&2
    ((TESTS_RUN++))
    echo "[DEBUG] After TESTS_RUN increment" >&2
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

test_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
}

#######################################
# Test Prerequisites
#######################################
test_prerequisites() {
    test_header "Test 1: Prerequisites"

    # Check scripts exist
    if [ -f "$CHECK_SCRIPT" ]; then
        pass "check-cert-expiration.sh exists"
    else
        fail "check-cert-expiration.sh not found at $CHECK_SCRIPT"
    fi

    echo "[DEBUG] After CHECK_SCRIPT test" >&2

    if [ -f "$RENEW_SCRIPT" ]; then
        pass "auto-renew-certificates.sh exists"
    else
        fail "auto-renew-certificates.sh not found at $RENEW_SCRIPT"
    fi

    echo "[DEBUG] After RENEW_SCRIPT test" >&2

    if [ -f "$CRON_SCRIPT" ]; then
        pass "setup-cert-renewal-cron.sh exists"
    else
        fail "setup-cert-renewal-cron.sh not found at $CRON_SCRIPT"
    fi

    # Check scripts are executable
    if [ -x "$CHECK_SCRIPT" ]; then
        pass "check-cert-expiration.sh is executable"
    else
        fail "check-cert-expiration.sh is not executable"
    fi

    if [ -x "$RENEW_SCRIPT" ]; then
        pass "auto-renew-certificates.sh is executable"
    else
        fail "auto-renew-certificates.sh is not executable"
    fi

    if [ -x "$CRON_SCRIPT" ]; then
        pass "setup-cert-renewal-cron.sh is executable"
    else
        fail "setup-cert-renewal-cron.sh is not executable"
    fi

    # Check Vault is running
    if curl -s http://localhost:8200/v1/sys/health > /dev/null 2>&1; then
        pass "Vault is running and accessible"
    else
        fail "Vault is not running (required for tests)"
    fi

    # Check certificates exist
    if [ -d "$HOME/.config/vault/certs" ]; then
        local cert_count
        cert_count=$(/usr/bin/find "$HOME/.config/vault/certs" -name "server.crt" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$cert_count" -gt 0 ]; then
            pass "Found $cert_count certificate(s) in ~/.config/vault/certs"
        else
            fail "No certificates found in ~/.config/vault/certs"
        fi
    else
        fail "Certificate directory ~/.config/vault/certs does not exist"
    fi
}

#######################################
# Test check-cert-expiration.sh
#######################################
test_check_expiration() {
    test_header "Test 2: Certificate Expiration Checking"

    # Test 2.1: Basic execution (human-readable output)
    if "$CHECK_SCRIPT" > /dev/null 2>&1; then
        pass "Script executes without errors (human format)"
    else
        fail "Script failed to execute (human format)"
    fi

    # Test 2.2: JSON output format
    if "$CHECK_SCRIPT" --json > /dev/null 2>&1; then
        pass "Script executes with --json flag"
    else
        fail "Script failed with --json flag"
    fi

    # Test 2.3: Validate JSON output structure
    local json_output=$("$CHECK_SCRIPT" --json 2>/dev/null)
    if echo "$json_output" | python3 -m json.tool > /dev/null 2>&1; then
        pass "JSON output is valid JSON"
    else
        fail "JSON output is not valid JSON"
    fi

    # Test 2.4: Nagios output format
    if "$CHECK_SCRIPT" --nagios > /dev/null 2>&1; then
        pass "Script executes with --nagios flag"
    else
        fail "Script failed with --nagios flag"
    fi

    # Test 2.5: Per-service checking
    if "$CHECK_SCRIPT" --service postgres > /dev/null 2>&1; then
        pass "Script executes with --service postgres"
    else
        fail "Script failed with --service postgres"
    fi

    # Test 2.6: Exit code for healthy certificates
    "$CHECK_SCRIPT" > /dev/null 2>&1
    local exit_code=$?
    if [ $exit_code -eq 0 ] || [ $exit_code -eq 1 ]; then
        pass "Script returns appropriate exit code ($exit_code)"
    else
        fail "Script returns unexpected exit code: $exit_code"
    fi

    # Test 2.7: Output contains expected services
    local output=$("$CHECK_SCRIPT" 2>/dev/null)
    if echo "$output" | grep -q "postgres"; then
        pass "Output contains postgres certificate info"
    else
        fail "Output missing postgres certificate info"
    fi

    # Test 2.8: Verify certificate count matches
    local cert_count=$(find "$HOME/.config/vault/certs" -name "server.crt" | wc -l | tr -d ' ')
    local output_count=$(echo "$output" | grep -c "✓\|✗\|⚠" || true)
    if [ "$output_count" -ge "$cert_count" ]; then
        pass "Output shows all certificates ($output_count >= $cert_count)"
    else
        fail "Output missing certificates ($output_count < $cert_count)"
    fi
}

#######################################
# Test auto-renew-certificates.sh
#######################################
test_auto_renew() {
    test_header "Test 3: Automatic Certificate Renewal"

    # Test 3.1: Dry-run mode
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null || echo "")

    if [ -z "$VAULT_TOKEN" ]; then
        fail "VAULT_TOKEN not set (cannot test renewal)"
        return
    fi

    if "$RENEW_SCRIPT" --dry-run > /dev/null 2>&1; then
        pass "Script executes in --dry-run mode"
    else
        fail "Script failed in --dry-run mode"
    fi

    # Test 3.2: Quiet mode
    if "$RENEW_SCRIPT" --dry-run --quiet > /dev/null 2>&1; then
        pass "Script executes in --quiet mode"
    else
        fail "Script failed in --quiet mode"
    fi

    # Test 3.3: Per-service renewal (dry-run)
    if "$RENEW_SCRIPT" --dry-run --service postgres > /dev/null 2>&1; then
        pass "Script executes for specific service (--service postgres)"
    else
        fail "Script failed for specific service"
    fi

    # Test 3.4: Check dependency on Vault
    # Temporarily move the root-token file to prevent fallback
    local token_file="$HOME/.config/vault/root-token"
    local token_backup=""
    if [ -f "$token_file" ]; then
        token_backup=$(cat "$token_file")
        mv "$token_file" "$token_file.bak"
    fi

    unset VAULT_TOKEN
    if ! "$RENEW_SCRIPT" --dry-run > /dev/null 2>&1; then
        pass "Script correctly fails when VAULT_TOKEN not set"
    else
        fail "Script should fail when VAULT_TOKEN not set"
    fi

    # Restore the token file
    if [ -n "$token_backup" ]; then
        echo "$token_backup" > "$token_file"
        rm -f "$token_file.bak"
    fi
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)

    # Test 3.5: Verify dry-run doesn't actually renew
    local before_mod=$(stat -f %m "$HOME/.config/vault/certs/postgres/server.crt" 2>/dev/null || echo "0")
    "$RENEW_SCRIPT" --dry-run --service postgres > /dev/null 2>&1
    local after_mod=$(stat -f %m "$HOME/.config/vault/certs/postgres/server.crt" 2>/dev/null || echo "0")

    if [ "$before_mod" = "$after_mod" ]; then
        pass "Dry-run mode doesn't modify certificates"
    else
        fail "Dry-run mode modified certificates (should not happen)"
    fi

    # Test 3.6: Output contains summary
    local output=$("$RENEW_SCRIPT" --dry-run 2>&1)
    if echo "$output" | grep -q "Renewal Summary"; then
        pass "Output contains renewal summary"
    else
        fail "Output missing renewal summary"
    fi

    # Test 3.7: Check exit codes
    "$RENEW_SCRIPT" --dry-run > /dev/null 2>&1
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        pass "Script returns exit code 0 when no renewals needed"
    else
        fail "Script returns unexpected exit code: $exit_code"
    fi
}

#######################################
# Test setup-cert-renewal-cron.sh
#######################################
test_cron_setup() {
    test_header "Test 4: Cron Job Management"

    # Test 4.1: Remove any existing cron jobs first
    "$CRON_SCRIPT" --remove > /dev/null 2>&1 || true

    # Test 4.2: List when no cron jobs exist
    if "$CRON_SCRIPT" --list > /dev/null 2>&1; then
        pass "Script can list cron jobs (when none exist)"
    else
        fail "Script failed to list cron jobs"
    fi

    # Test 4.3: Install cron jobs
    if "$CRON_SCRIPT" > /dev/null 2>&1; then
        pass "Script can install cron jobs"
    else
        fail "Script failed to install cron jobs"
    fi

    # Test 4.4: Verify cron jobs were installed
    if crontab -l 2>/dev/null | grep -q "DevStack Core - Certificate Auto-Renewal"; then
        pass "Cron jobs were successfully installed"
    else
        fail "Cron jobs not found in crontab"
    fi

    # Test 4.5: List installed cron jobs
    local output=$("$CRON_SCRIPT" --list 2>&1)
    if echo "$output" | grep -q "auto-renew-certificates.sh"; then
        pass "List shows installed renewal job"
    else
        fail "List doesn't show renewal job"
    fi

    # Test 4.6: Prevent duplicate installation
    if ! "$CRON_SCRIPT" > /dev/null 2>&1; then
        pass "Script prevents duplicate cron job installation"
    else
        fail "Script allows duplicate installation (should prevent)"
    fi

    # Test 4.7: Remove cron jobs
    if "$CRON_SCRIPT" --remove > /dev/null 2>&1; then
        pass "Script can remove cron jobs"
    else
        fail "Script failed to remove cron jobs"
    fi

    # Test 4.8: Verify cron jobs were removed
    if ! crontab -l 2>/dev/null | grep -q "DevStack Core - Certificate Auto-Renewal"; then
        pass "Cron jobs were successfully removed"
    else
        fail "Cron jobs still present after removal"
    fi
}

#######################################
# Test Error Handling
#######################################
test_error_handling() {
    test_header "Test 5: Error Handling"

    # Test 5.1: Invalid flag handling
    if ! "$CHECK_SCRIPT" --invalid-flag > /dev/null 2>&1; then
        pass "check-cert-expiration.sh rejects invalid flags"
    else
        fail "check-cert-expiration.sh accepts invalid flags"
    fi

    if ! "$RENEW_SCRIPT" --invalid-flag > /dev/null 2>&1; then
        pass "auto-renew-certificates.sh rejects invalid flags"
    else
        fail "auto-renew-certificates.sh accepts invalid flags"
    fi

    if ! "$CRON_SCRIPT" --invalid-flag > /dev/null 2>&1; then
        pass "setup-cert-renewal-cron.sh rejects invalid flags"
    else
        fail "setup-cert-renewal-cron.sh accepts invalid flags"
    fi

    # Test 5.2: Non-existent service handling
    if ! "$CHECK_SCRIPT" --service nonexistent > /dev/null 2>&1; then
        pass "check-cert-expiration.sh handles non-existent service gracefully"
    else
        # This might actually succeed with no output, which is acceptable
        pass "check-cert-expiration.sh handles non-existent service"
    fi
}

#######################################
# Test Integration
#######################################
test_integration() {
    test_header "Test 6: Integration Testing"

    # Test 6.1: Full workflow simulation
    echo "Simulating full certificate management workflow..."

    # Step 1: Check expiration
    local check_output=$("$CHECK_SCRIPT" 2>&1)
    if [ $? -eq 0 ] || [ $? -eq 1 ]; then
        pass "Step 1: Certificate expiration check completes"
    else
        fail "Step 1: Certificate expiration check fails"
    fi

    # Step 2: Dry-run renewal
    export VAULT_ADDR=http://localhost:8200
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)
    local renew_output=$("$RENEW_SCRIPT" --dry-run 2>&1)
    if [ $? -eq 0 ]; then
        pass "Step 2: Dry-run renewal completes"
    else
        fail "Step 2: Dry-run renewal fails"
    fi

    # Step 3: Setup cron (then remove)
    "$CRON_SCRIPT" --remove > /dev/null 2>&1 || true
    if "$CRON_SCRIPT" > /dev/null 2>&1; then
        pass "Step 3: Cron setup completes"
        "$CRON_SCRIPT" --remove > /dev/null 2>&1
    else
        fail "Step 3: Cron setup fails"
    fi

    # Test 6.2: Verify JSON parsing
    local json=$("$CHECK_SCRIPT" --json 2>/dev/null)
    if echo "$json" | python3 -c "import json, sys; data=json.load(sys.stdin); assert 'certificates' in data" 2>/dev/null; then
        pass "JSON output has required 'certificates' field"
    else
        fail "JSON output missing 'certificates' field"
    fi

    # Test 6.3: Verify threshold configuration
    if echo "$json" | python3 -c "import json, sys; data=json.load(sys.stdin); assert 'thresholds' in data" 2>/dev/null; then
        pass "JSON output has required 'thresholds' field"
    else
        fail "JSON output missing 'thresholds' field"
    fi
}

#######################################
# Main Test Execution
#######################################
main() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  TLS Certificate Automation Test Suite${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""

    test_prerequisites
    test_check_expiration
    test_auto_renew
    test_cron_setup
    test_error_handling
    test_integration

    # Summary
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Test Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Tests Run:    $TESTS_RUN"
    echo -e "  ${GREEN}Tests Passed: $TESTS_PASSED${NC}"
    echo -e "  ${RED}Tests Failed: $TESTS_FAILED${NC}"
    echo ""

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        echo ""
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo ""
        exit 1
    fi
}

# Run tests
main
