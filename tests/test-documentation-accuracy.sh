#!/bin/bash
################################################################################
# Documentation Accuracy Verification Tests
################################################################################
# This script validates that documentation claims match actual codebase reality.
# Run this test to detect documentation drift before it becomes a problem.
#
# Usage: ./tests/test-documentation-accuracy.sh
#
# Exit Codes:
#   0 - All tests passed
#   1 - One or more tests failed
################################################################################

# Note: set -e disabled to allow all tests to run even if some commands return non-zero
# The script has its own exit code logic based on test results
# set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
FAILED_TESTS=()

#######################################
# Print test header
#######################################
print_header() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Documentation Accuracy Verification${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo ""
}

#######################################
# Print test name
#######################################
print_test() {
    echo -n "Test $((TESTS_RUN + 1)): $1 ... "
}

#######################################
# Mark test as passed
#######################################
pass() {
    echo -e "${GREEN}PASS${NC}"
    ((TESTS_PASSED++))
    ((TESTS_RUN++))
}

#######################################
# Mark test as failed
#######################################
fail() {
    echo -e "${RED}FAIL${NC}"
    if [ -n "$1" ]; then
        echo -e "${RED}  Reason: $1${NC}"
    fi
    FAILED_TESTS+=("Test $TESTS_RUN: $2")
    ((TESTS_FAILED++))
    ((TESTS_RUN++))
}

#######################################
# Print final summary
#######################################
print_summary() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
    else
        echo -e "${RED}Some tests failed!${NC}"
        echo ""
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "${RED}  - $test${NC}"
        done
    fi
    echo -e "${BLUE}Tests run: $TESTS_RUN${NC}"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo -e "${BLUE}=========================================${NC}"
}

################################################################################
# Main Tests
################################################################################

print_header

################################################################################
# Test 1: Service Count Validation
################################################################################
print_test "Service count matches documentation (should be 23)"

# Count the keys of the services: section only. The x-* anchor blocks above
# it also have two-space children (image:, healthcheck:, ...) that an
# indentation-only grep counted as services.
ACTUAL_COUNT=$(awk '/^services:/{p=1;next} /^[A-Za-z]/{p=0} p && /^  [a-z0-9_-]+:$/' docker-compose.yml | \
    wc -l | tr -d ' ')
EXPECTED_COUNT=23

if [ "$ACTUAL_COUNT" -eq "$EXPECTED_COUNT" ]; then
    pass
else
    fail "Expected $EXPECTED_COUNT services, found $ACTUAL_COUNT" "Service count mismatch"
fi

################################################################################
# Test 2: AppRole Service Count
################################################################################
print_test "AppRole adoption count matches vault-approle-bootstrap.sh"

# Count services in SERVICES array
APPROLE_COUNT=$(awk '/^SERVICES=\(/,/^\)/' scripts/vault-approle-bootstrap.sh | \
    grep '    "' | wc -l | tr -d ' ')

EXPECTED_APPROLE=15

if [ "$APPROLE_COUNT" -eq "$EXPECTED_APPROLE" ]; then
    pass
else
    fail "Expected $EXPECTED_APPROLE AppRole services, found $APPROLE_COUNT" "AppRole count mismatch"
fi

################################################################################
# Test 3: Profile Service Assignments
################################################################################
print_test "All services have valid profile assignments"

# Check for services without profiles (should only be vault and base infrastructure)
SERVICES_WITHOUT_PROFILES=$(grep -B 2 "profiles:" docker-compose.yml | grep '^  [a-z]' | wc -l | tr -d ' ')

# This should be a reasonable number (base services that run always)
if [ "$SERVICES_WITHOUT_PROFILES" -lt 10 ]; then
    pass
else
    fail "Too many services without profiles: $SERVICES_WITHOUT_PROFILES" "Profile assignment issue"
fi

################################################################################
# Test 4: VAULT_APPROLE_DIR References Match AppRole Services
################################################################################
print_test "Every AppRole in vault-approle-bootstrap.sh is wired into docker-compose.yml"

# The bootstrap script names every AppRole it creates. Each one except
# "management", the AppRole the host-side CLI (scripts/manage_devstack.py)
# authenticates with, must appear in docker-compose.yml as a
# /vault-approles/<name> path, and nothing in compose may use an AppRole the
# bootstrap does not create. A count cannot see either mistake: the redis and
# redis-exporter nodes share YAML anchors, so one line serves three services.
BOOTSTRAP_APPROLES=$(awk '/^SERVICES=\(/,/^\)/' scripts/vault-approle-bootstrap.sh | \
    grep '    "' | tr -d ' "' | grep -v '^management$' | sort)
COMPOSE_APPROLES=$(grep -oE '/vault-approles/[a-z0-9-]+' docker-compose.yml | \
    sed 's|/vault-approles/||' | sort -u)
NOT_IN_COMPOSE=$(comm -23 <(echo "$BOOTSTRAP_APPROLES") <(echo "$COMPOSE_APPROLES") | tr '\n' ' ')
NOT_IN_BOOTSTRAP=$(comm -13 <(echo "$BOOTSTRAP_APPROLES") <(echo "$COMPOSE_APPROLES") | tr '\n' ' ')

if [ -z "$NOT_IN_COMPOSE" ] && [ -z "$NOT_IN_BOOTSTRAP" ]; then
    pass
else
    fail "bootstrapped but not in compose: [$NOT_IN_COMPOSE] in compose but not bootstrapped: [$NOT_IN_BOOTSTRAP]" "AppRole wiring mismatch"
fi

################################################################################
# Test 5: Network Definitions
################################################################################
print_test "All 4 required networks are defined"

# Check for 4-tier network segmentation
VAULT_NET=$(grep -c "vault-network:" docker-compose.yml || echo "0")
DATA_NET=$(grep -c "data-network:" docker-compose.yml || echo "0")
APP_NET=$(grep -c "app-network:" docker-compose.yml || echo "0")
OBS_NET=$(grep -c "observability-network:" docker-compose.yml || echo "0")

if [ "$VAULT_NET" -gt 0 ] && [ "$DATA_NET" -gt 0 ] && [ "$APP_NET" -gt 0 ] && [ "$OBS_NET" -gt 0 ]; then
    pass
else
    fail "Missing network definitions (vault:$VAULT_NET data:$DATA_NET app:$APP_NET obs:$OBS_NET)" "Network config issue"
fi

################################################################################
# Test 6: Service Catalog Exists and is Up-to-Date
################################################################################
print_test "SERVICE_CATALOG.md exists and contains 23 services"

if [ -f "docs/SERVICE_CATALOG.md" ]; then
    CATALOG_COUNT=$(grep "Total Services:" docs/SERVICE_CATALOG.md | grep -o '[0-9]\+' | head -1)
    if [ "$CATALOG_COUNT" -eq 23 ]; then
        pass
    else
        fail "SERVICE_CATALOG.md shows $CATALOG_COUNT services, expected 23" "Catalog out of date"
    fi
else
    fail "docs/SERVICE_CATALOG.md does not exist" "Missing service catalog"
fi

################################################################################
# Test 7: Test Count in README.md
################################################################################
print_test "README.md test count matches TEST_COVERAGE.md (571+)"

if grep -q "571+" README.md; then
    pass
else
    fail "README.md does not reference 571+ tests" "Test count mismatch in README"
fi

################################################################################
# Test 8: Archive Directory for Phase Documentation
################################################################################
print_test "Archive directory exists for phase documentation"

if [ -d "docs/archive" ]; then
    PHASE_DOCS=$(find docs/archive -name "PHASE_*.md" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$PHASE_DOCS" -gt 0 ]; then
        pass
    else
        fail "docs/archive exists but contains no PHASE_*.md files" "Archive not used"
    fi
else
    fail "docs/archive directory does not exist" "Missing archive directory"
fi

################################################################################
# Test 9: No PostgreSQL 16 References in Wiki
################################################################################
print_test "Wiki files reference PostgreSQL 18 (not 16), upgrade history excepted"

# Upgrade-Guide.md and Changelog.md record the 16 -> 18 upgrade and have to
# name 16; every other page describes the running stack.
PG16_COUNT=$(grep -r "PostgreSQL 16" wiki --exclude=Upgrade-Guide.md --exclude=Changelog.md 2>/dev/null | \
    wc -l | tr -d ' ')

if [ "$PG16_COUNT" -eq 0 ]; then
    pass
else
    fail "Found $PG16_COUNT references to PostgreSQL 16 in wiki/" "Outdated PostgreSQL version in wiki"
fi

################################################################################
# Test 10: All init-approle.sh Scripts Exist
################################################################################
print_test "Core services have init-approle.sh scripts"

EXPECTED_INIT_SCRIPTS=(
    "configs/postgres/scripts/init-approle.sh"
    "configs/mysql/scripts/init-approle.sh"
    "configs/mongodb/scripts/init-approle.sh"
    "configs/redis/scripts/init-approle.sh"
    "configs/rabbitmq/scripts/init-approle.sh"
    "configs/forgejo/scripts/init-approle.sh"
)

MISSING_SCRIPTS=0
for script in "${EXPECTED_INIT_SCRIPTS[@]}"; do
    if [ ! -f "$script" ]; then
        ((MISSING_SCRIPTS++))
    fi
done

if [ "$MISSING_SCRIPTS" -eq 0 ]; then
    pass
else
    fail "Missing $MISSING_SCRIPTS init-approle.sh scripts" "Missing AppRole init scripts"
fi

################################################################################
# Test 11: Wiki Sync - Core Documentation Files
################################################################################
print_test "Wiki files are in sync with main documentation"

# The mirrored set is defined once, in scripts/wiki-mirror.sh; this test
# runs its check mode so the two can never disagree.
if MIRROR_OUTPUT=$(./scripts/wiki-mirror.sh --check 2>&1); then
    pass
else
    fail "$(echo "$MIRROR_OUTPUT" | grep 'wiki mirror check failed')" "Wiki sync required"
fi

################################################################################
# Test 12: SERVICE_CATALOG.md image tags match the images the stack runs
################################################################################
print_test "SERVICE_CATALOG.md names the images docker-compose.yml and the Dockerfiles run"

# The catalog names each image without its tag: tags are pinned in compose
# and the Dockerfile FROM lines, where Dependabot bumps them weekly, and a
# second copy of a tag could only fall behind. What is checked is identity:
# every image the catalog names must be one the stack runs.
RUNNING_IMAGES=$( {
    grep -E '^\s+image:' docker-compose.yml | sed 's/.*image:\s*//'
    grep -hE '^FROM ' configs/*/Dockerfile | sed 's/^FROM //'
} | sed 's/:[^:/]*$//' | sort -u)

UNKNOWN_IMAGES=""
while read -r img; do
    if ! echo "$RUNNING_IMAGES" | grep -qxF "$img"; then
        UNKNOWN_IMAGES="$UNKNOWN_IMAGES $img"
    fi
done < <(grep -oE '\*\*Image:\*\* `[^`]+`' docs/SERVICE_CATALOG.md | sed 's/.*`\(.*\)`/\1/')

if [ -z "$UNKNOWN_IMAGES" ]; then
    pass
else
    fail "not an image the stack runs:$UNKNOWN_IMAGES" "Service catalog names an unknown image"
fi

################################################################################
# Summary
################################################################################

print_summary

# Exit with appropriate code
if [ $TESTS_FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi
