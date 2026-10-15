#!/bin/bash
################################################################################
# Tests for scripts/check-markdown-links.sh
################################################################################
# Copies the checker into a temporary tree with fixture Markdown files and
# checks what it reports. The checker finds the tree from its own location
# (scripts/..), so the copy checks only the fixtures. Needs no services.
#
# Usage: ./tests/test-check-markdown-links.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="${CHECKER:-$SCRIPT_DIR/../scripts/check-markdown-links.sh}"

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

# Builds a tree with the checker and the given docs/a.md content, runs the
# checker, and leaves its exit code in RC and its output (colors removed) in
# OUT.
run_checker() {
  rm -rf "${WORK:?}/tree"
  mkdir -p "$WORK/tree/scripts" "$WORK/tree/docs"
  cp "$CHECKER" "$WORK/tree/scripts/check-markdown-links.sh"
  printf '%s\n' "$1" > "$WORK/tree/docs/a.md"
  printf '# B\n' > "$WORK/tree/docs/b.md"
  RC=0
  OUT=$(bash "$WORK/tree/scripts/check-markdown-links.sh" 2>&1) || RC=$?
  OUT=$(printf '%s\n' "$OUT" | sed 's/\x1b\[[0-9;]*m//g')
}

# 1. Every link is counted; the checker does not stop after the first one.
run_checker '[one](b.md) [two](b.md) [three](b.md)'
if [ "$RC" -eq 0 ] && printf '%s\n' "$OUT" | grep -q "Links Checked: 3"; then
  pass "counts all three valid links and exits 0"
else
  fail "counts all three valid links and exits 0 (exit $RC)"
  printf '%s\n' "$OUT" | tail -5
fi

# 2. A broken file link is reported and fails the run.
run_checker '[ok](b.md) [gone](missing.md)'
if [ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -q "docs/a.md: missing.md"; then
  pass "reports a link to a missing file and exits 1"
else
  fail "reports a link to a missing file and exits 1 (exit $RC)"
  printf '%s\n' "$OUT" | tail -5
fi

# 3. A reference definition with an https URL is external, not a file link.
run_checker '[ref]: https://example.com/page'
if [ "$RC" -eq 0 ] && ! printf '%s\n' "$OUT" | grep -q "docs/a.md: http"; then
  pass "treats a reference definition with an https URL as external"
else
  fail "treats a reference definition with an https URL as external (exit $RC)"
  printf '%s\n' "$OUT" | tail -5
fi

# 4. Bracket text inside a fenced code block is not a link.
run_checker '```typescript
data: { [key: string]: string },
```'
if [ "$RC" -eq 0 ] && ! printf '%s\n' "$OUT" | grep -q "docs/a.md: string"; then
  pass "ignores bracket text inside a fenced code block"
else
  fail "ignores bracket text inside a fenced code block (exit $RC)"
  printf '%s\n' "$OUT" | tail -5
fi

echo
echo "Tests run: $TESTS_RUN, failed: $TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
