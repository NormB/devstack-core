#!/bin/bash
################################################################################
# Tests for scripts/check-python-deps.sh
################################################################################
# Copies the checker into a temporary tree with fixture requirements.txt files
# and puts a stub `safety` first on PATH. The stub exits with the code chosen
# for each file, so every outcome can be driven without the network. Safety
# 3.8.1's codes (safety/constants.py, measured 2026-10-22): 0 nothing found,
# 64 vulnerabilities found, 67 local database missing, 68 vulnerability
# database could not be fetched. Needs no services.
#
# Usage: ./tests/test-check-python-deps.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="${CHECKER:-$SCRIPT_DIR/../scripts/check-python-deps.sh}"

TESTS_RUN=0
TESTS_FAILED=0

pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  echo "PASS: $1"
}

fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "FAIL: $1"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cat > "$WORK/bin/safety" << 'STUB'
#!/bin/bash
# Stub Safety: `safety check --file F --output text` exits with the code
# listed for F in $STUB_RC_MAP ("path code" per line), 0 when F is not listed.
file=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--file" ]; then file="$2"; shift; fi
  shift
done
echo "$file" >> "$STUB_CALLS"
rc=$(awk -v f="$file" '$1 == f { print $2 }' "$STUB_RC_MAP")
echo "stub safety: $file"
exit "${rc:-0}"
STUB
chmod +x "$WORK/bin/safety"

# Builds a tree with the checker and one requirements.txt per argument
# ("dir:code"), runs the checker with the stub, and leaves its exit code in
# RC, its output in OUT and the files the stub was asked about in CALLS.
run_checker() {
  rm -rf "${WORK:?}/tree"
  mkdir -p "$WORK/tree/scripts"
  cp "$CHECKER" "$WORK/tree/scripts/check-python-deps.sh"
  : > "$WORK/rcmap"
  : > "$WORK/calls"
  local spec dir code
  for spec in "$@"; do
    dir="${spec%%:*}"
    code="${spec#*:}"
    mkdir -p "$WORK/tree/$dir"
    printf 'six==1.17.0\n' > "$WORK/tree/$dir/requirements.txt"
    echo "./$dir/requirements.txt $code" >> "$WORK/rcmap"
  done
  RC=0
  OUT=$(PATH="$WORK/bin:$PATH" STUB_RC_MAP="$WORK/rcmap" STUB_CALLS="$WORK/calls" \
    bash "$WORK/tree/scripts/check-python-deps.sh" 2>&1) || RC=$?
  CALLS=$(cat "$WORK/calls")
}

# 1. Nothing found anywhere: exit 0, no failure line.
run_checker "a:0" "b:0"
if [ "$RC" -eq 0 ] && ! printf '%s\n' "$OUT" | grep -q "✗"; then
  pass "exits 0 when Safety finds nothing in any file"
else
  fail "exits 0 when Safety finds nothing in any file (exit $RC)"
  printf '%s\n' "$OUT" | tail -5
fi

# 2. Exit 64 is a vulnerability finding and is reported as one.
run_checker "a:64"
if [ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q "✗ Known vulnerabilities in ./a/requirements.txt"; then
  pass "reports exit 64 as known vulnerabilities and fails"
else
  fail "reports exit 64 as known vulnerabilities and fails (exit $RC)"
  printf '%s\n' "$OUT" | tail -5
fi

# 3. Exit 68 (database could not be fetched) is not a finding: it must fail,
#    name Safety's exit code, and never claim a vulnerability.
run_checker "a:68"
if [ "$RC" -ne 0 ] \
    && printf '%s\n' "$OUT" | grep -q "✗ Could not check ./a/requirements.txt (safety exit 68)" \
    && ! printf '%s\n' "$OUT" | grep -q "Known vulnerabilities"; then
  pass "reports a database fetch failure as a failed check, not a vulnerability"
else
  fail "reports a database fetch failure as a failed check, not a vulnerability (exit $RC)"
  printf '%s\n' "$OUT" | tail -5
fi

# 4. Any other non-zero code (here 67, local database missing) is also a
#    failed check, not a finding.
run_checker "a:67"
if [ "$RC" -ne 0 ] \
    && printf '%s\n' "$OUT" | grep -q "✗ Could not check ./a/requirements.txt (safety exit 67)" \
    && ! printf '%s\n' "$OUT" | grep -q "Known vulnerabilities"; then
  pass "reports any other Safety error as a failed check"
else
  fail "reports any other Safety error as a failed check (exit $RC)"
  printf '%s\n' "$OUT" | tail -5
fi

# 5. One file failing does not stop the rest: every file is checked and each
#    gets its own verdict.
run_checker "a:68" "b:64" "c:0"
expected=$'./a/requirements.txt\n./b/requirements.txt\n./c/requirements.txt'
if [ "$RC" -ne 0 ] && [ "$CALLS" = "$expected" ] \
    && printf '%s\n' "$OUT" | grep -q "✗ Could not check ./a/requirements.txt (safety exit 68)" \
    && printf '%s\n' "$OUT" | grep -q "✗ Known vulnerabilities in ./b/requirements.txt" \
    && ! printf '%s\n' "$OUT" | grep "✗" | grep -q "\./c/"; then
  pass "checks every file and reports each one's own outcome"
else
  fail "checks every file and reports each one's own outcome (exit $RC)"
  printf 'calls:\n%s\n' "$CALLS"
  printf '%s\n' "$OUT" | tail -8
fi

echo ""
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
