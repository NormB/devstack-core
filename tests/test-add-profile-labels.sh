#!/bin/bash
################################################################################
# Tests for scripts/add-profile-labels.py
################################################################################
# Runs a copy of the script in a temporary tree that has no
# docker-compose.yml, so main() returns 1 without touching any file. The run
# uses `python3 -S`, which skips the site module: the exit status must still
# come from main(), not from a NameError on the site-provided exit().
#
# Usage: ./tests/test-add-profile-labels.sh
################################################################################

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/scripts"
cp "$SCRIPT_DIR/../scripts/add-profile-labels.py" "$WORK/scripts/"

rc=0
out=$(python3 -S "$WORK/scripts/add-profile-labels.py" 2>&1) || rc=$?

if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "not found" &&
  ! printf '%s\n' "$out" | grep -q "NameError"; then
  echo "PASS: exits 1 from main() when docker-compose.yml is missing, without the site module"
else
  echo "FAIL: exits 1 from main() when docker-compose.yml is missing, without the site module (exit $rc)"
  printf '%s\n' "$out" | tail -3
  exit 1
fi
