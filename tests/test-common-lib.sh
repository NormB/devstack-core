#!/bin/bash
################################################################################
# Tests for tests/lib/common.sh
################################################################################
# Checks that the shared test library is tracked by git, that it defines the
# helpers tests/test-negative.sh and tests/test-performance.sh call, and that
# both scripts run to completion when no DevStack container is running (every
# service test then reports itself as skipped). Needs no services: a stub
# `docker` on PATH lists no containers, and HOME points at an empty directory
# so no Vault token is found.
#
# Usage: ./tests/test-common-lib.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
LIB="$SCRIPT_DIR/lib/common.sh"

RUN=0
FAILURES=0

pass() {
  RUN=$((RUN + 1))
  echo "PASS: $1"
}

failed() {
  RUN=$((RUN + 1))
  FAILURES=$((FAILURES + 1))
  echo "FAIL: $1"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/home"
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin/docker"
chmod +x "$WORK/bin/docker"

# 1. The library is not excluded by .gitignore.
if ! git -C "$REPO_ROOT" check-ignore -q tests/lib/common.sh; then
  pass ".gitignore does not exclude tests/lib/common.sh"
else
  failed ".gitignore does not exclude tests/lib/common.sh"
fi

# 2. The library exists and defines every helper the two scripts call.
if [ -f "$LIB" ]; then
  pass "tests/lib/common.sh exists"
else
  failed "tests/lib/common.sh exists"
fi

missing=$(
  # shellcheck source=/dev/null
  source "$LIB" > /dev/null 2>&1 || exit 0
  for fn in info success warn fail is_container_running get_password_from_vault \
    print_test_results test_suite_setup test_suite_teardown; do
    declare -F "$fn" > /dev/null || printf '%s ' "$fn"
  done
)
if [ -f "$LIB" ] && [ -z "$missing" ]; then
  pass "defines all nine helpers"
else
  failed "defines all nine helpers (missing: ${missing:-library not found})"
fi

# 3. success and fail update the counters the scripts declare.
counts=$(
  TESTS_PASSED=0
  TESTS_FAILED=0
  FAILED_TESTS=()
  # shellcheck source=/dev/null
  source "$LIB" > /dev/null 2>&1 || exit 0
  success "a" > /dev/null
  success "b" > /dev/null
  fail "c went wrong" > /dev/null
  echo "$TESTS_PASSED $TESTS_FAILED ${FAILED_TESTS[*]}"
)
if [ "$counts" = "2 1 c went wrong" ]; then
  pass "success and fail update TESTS_PASSED, TESTS_FAILED and FAILED_TESTS"
else
  failed "success and fail update TESTS_PASSED, TESTS_FAILED and FAILED_TESTS (got '$counts')"
fi

# 4. print_test_results exits 0 without failures and 1 with them, and names
#    the failed tests.
results=$(
  # shellcheck source=/dev/null
  source "$LIB" > /dev/null 2>&1 || exit 0
  TESTS_RUN=2 TESTS_PASSED=2 TESTS_FAILED=0 FAILED_TESTS=()
  print_test_results "Demo" > /dev/null
  clean=$?
  # shellcheck disable=SC2034 # read by print_test_results
  TESTS_RUN=2 TESTS_PASSED=1 TESTS_FAILED=1 FAILED_TESTS=("broken thing")
  out=$(print_test_results "Demo")
  dirty=$?
  printf '%s %s %s' "$clean" "$dirty" "$(printf '%s' "$out" | grep -c "broken thing")"
)
if [ "$results" = "0 1 1" ]; then
  pass "print_test_results returns 0 or 1 and lists failed tests"
else
  failed "print_test_results returns 0 or 1 and lists failed tests (got '$results')"
fi

# 5. Container and Vault helpers fail cleanly when nothing is running.
helpers=$(
  export PATH="$WORK/bin:$PATH" HOME="$WORK/home"
  unset VAULT_TOKEN
  # shellcheck source=/dev/null
  source "$LIB" > /dev/null 2>&1 || exit 0
  is_container_running dev-postgres && echo "running" || echo "not-running"
  pw=$(get_password_from_vault postgres 2> /dev/null) && echo "got:$pw" || echo "no-password:${pw}"
)
if [ "$helpers" = "not-running
no-password:" ]; then
  pass "is_container_running and get_password_from_vault fail with no stack"
else
  failed "is_container_running and get_password_from_vault fail with no stack (got '$helpers')"
fi

# 6. Both scripts parse and run every test to completion with no stack.
for entry in test-negative.sh:12 test-performance.sh:10; do
  script=${entry%%:*}
  count=${entry##*:}
  if ! bash -n "$SCRIPT_DIR/$script"; then
    failed "$script passes bash -n"
    continue
  fi
  rc=0
  out=$(PATH="$WORK/bin:$PATH" HOME="$WORK/home" VAULT_TOKEN='' \
    bash "$SCRIPT_DIR/$script" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q "Tests run: $count\$"; then
    pass "$script runs all $count tests and exits 0 with no stack"
  else
    failed "$script runs all $count tests and exits 0 with no stack (exit $rc)"
    printf '%s\n' "$out" | tail -5
  fi
done

echo
echo "Tests run: $RUN, failed: $FAILURES"
[ "$FAILURES" -eq 0 ]
