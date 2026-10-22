#!/bin/bash
################################################################################
# Checks every requirements.txt in the repository with Safety.
################################################################################
# Run by the Dependency Scanning job in .github/workflows/security.yml.
# Finds the tree from its own location (scripts/..).
#
# Usage: ./scripts/check-python-deps.sh
#
# Only Safety's exit code 64 means vulnerabilities were found. Every other
# non-zero code is Safety failing to check the file (67: local database
# missing, 68: vulnerability database could not be fetched, and so on; see
# safety/constants.py). An unchecked file is not a clean one, so that also
# fails, but it is reported as what it is: on 2026-10-15 a database fetch
# failure was reported as "Known vulnerabilities" in a file Safety never read.
#
# Exit Codes:
#   0 - Every requirements.txt was checked and none has a known vulnerability
#   1 - At least one has a known vulnerability or could not be checked
################################################################################

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

readonly SAFETY_VULNERABILITIES_FOUND=64

failed=0
while read -r req_file; do
  echo "Checking $req_file..."
  rc=0
  safety check --file "$req_file" --output text || rc=$?
  if [ "$rc" -eq "$SAFETY_VULNERABILITIES_FOUND" ]; then
    echo "✗ Known vulnerabilities in $req_file"
    failed=1
  elif [ "$rc" -ne 0 ]; then
    echo "✗ Could not check $req_file (safety exit $rc)"
    failed=1
  fi
done < <(find . -name "requirements.txt" -type f | sort)
exit $failed
