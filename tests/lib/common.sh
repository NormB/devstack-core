#!/bin/bash
################################################################################
# Shared helpers for tests/test-negative.sh and tests/test-performance.sh
################################################################################
# Sourced, not executed. The calling script declares the counters
# TESTS_RUN, TESTS_PASSED, TESTS_FAILED and the array FAILED_TESTS; each test
# function increments TESTS_RUN itself and reports through success or fail.
#
# Functions:
#   info, success, warn, fail      - print a colored line; success and fail
#                                    also update the counters
#   is_container_running NAME      - 0 if a container with that exact name runs
#   get_password_from_vault SVC    - print secret/SVC's password from Vault
#   test_suite_setup NAME          - print the suite name and record the start
#   print_test_results NAME        - print the summary; 1 if any test failed
#   test_suite_teardown            - print the elapsed time
#
# Tests in tests/test-common-lib.sh.
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[TEST]${NC} $1"; }

success() {
  echo -e "${GREEN}[PASS]${NC} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILED_TESTS+=("$1")
}

# Returns 0 if a running container has exactly this name. Without docker, or
# with the daemon unreachable, nothing is running.
is_container_running() {
  local name=$1
  docker ps --format '{{.Names}}' 2> /dev/null | grep -qx -- "$name"
}

# Prints the password stored at secret/<service> in Vault (KV v2). Uses
# VAULT_ADDR (default http://localhost:8200) and VAULT_TOKEN, or the token in
# ~/.config/vault/root-token. Returns 1 and prints nothing when there is no
# token, Vault does not answer, or the secret has no password.
get_password_from_vault() {
  local service=$1
  local addr=${VAULT_ADDR:-http://localhost:8200}
  local token=${VAULT_TOKEN:-}
  if [ -z "$token" ]; then
    token=$(cat "$HOME/.config/vault/root-token" 2> /dev/null) || token=""
  fi
  [ -n "$token" ] || return 1

  local password
  password=$(curl -sf --max-time 5 -H "X-Vault-Token: $token" \
    "$addr/v1/secret/data/$service" 2> /dev/null |
    jq -r '.data.data.password // empty' 2> /dev/null) || password=""
  [ -n "$password" ] || return 1
  printf '%s\n' "$password"
}

test_suite_setup() {
  TEST_SUITE_NAME=${1:-Test}
  TEST_SUITE_START=$(date +%s)
  info "Starting $TEST_SUITE_NAME test suite"
  echo
}

# Prints the counters and the names of failed tests. Returns 1 if any test
# failed, so the calling script exits non-zero under set -e.
print_test_results() {
  local name=${1:-Test}
  echo
  echo "========================================="
  echo "  $name Test Results"
  echo "========================================="
  echo "Tests run: $TESTS_RUN"
  echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
  if [ "$TESTS_FAILED" -gt 0 ]; then
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    local t
    for t in "${FAILED_TESTS[@]}"; do
      echo -e "  ${RED}✗${NC} $t"
    done
    echo
    return 1
  fi
  echo
  echo -e "${GREEN}All $name tests passed${NC}"
  echo
  return 0
}

test_suite_teardown() {
  local start=${TEST_SUITE_START:-$(date +%s)}
  info "${TEST_SUITE_NAME:-Test} test suite finished in $(($(date +%s) - start))s"
}
