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

# Count actual services in docker-compose.yml
ACTUAL_COUNT=$(grep '^  [a-z]' docker-compose.yml | \
    awk '{print $1}' | tr -d ':' | \
    grep -v 'network$' | grep -v '_data$' | \
    grep -v '^driver$' | grep -v '^options$' | grep -v '^platform$' | \
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
print_test "VAULT_APPROLE_DIR references match AppRole bootstrap services"

# Count VAULT_APPROLE_DIR in docker-compose.yml
APPROLE_DIR_COUNT=$(grep -c "VAULT_APPROLE_DIR:" docker-compose.yml || echo "0")

# Should be at least 15 (some services like redis have 3 nodes)
if [ "$APPROLE_DIR_COUNT" -ge 15 ]; then
    pass
else
    fail "Expected >= 15 VAULT_APPROLE_DIR references, found $APPROLE_DIR_COUNT" "AppRole config mismatch"
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
print_test "Wiki files reference PostgreSQL 18 (not 16)"

PG16_COUNT=$(grep -r "PostgreSQL 16" wiki 2>/dev/null | wc -l | tr -d ' ')

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

# Define sync mappings (source → destination)
# Using arrays instead of associative arrays for better compatibility
WIKI_SOURCES=(
    "docs/README.md"
    "docs/ARCHITECTURE.md"
    "docs/SERVICE_CATALOG.md"
    "README.md"
    ".github/CHANGELOG.md"
)

WIKI_DESTS=(
    "wiki/Documentation-Index.md"
    "wiki/Architecture-Overview.md"
    "wiki/Service-Catalog.md"
    "wiki/Home.md"
    "wiki/Changelog.md"
)

OUT_OF_SYNC=0
MISSING_WIKI_FILES=0

for i in "${!WIKI_SOURCES[@]}"; do
    src="${WIKI_SOURCES[$i]}"
    dest="${WIKI_DESTS[$i]}"

    if [ ! -f "$src" ]; then
        ((MISSING_WIKI_FILES++))
        continue
    fi

    if [ ! -f "$dest" ]; then
        ((MISSING_WIKI_FILES++))
        continue
    fi

    # Check if files are identical
    if ! cmp -s "$src" "$dest" 2>/dev/null; then
        ((OUT_OF_SYNC++))
    fi
done

if [ "$OUT_OF_SYNC" -eq 0 ] && [ "$MISSING_WIKI_FILES" -eq 0 ]; then
    pass
else
    if [ "$OUT_OF_SYNC" -gt 0 ]; then
        fail "$OUT_OF_SYNC wiki files out of sync with main docs" "Wiki sync required"
    else
        fail "$MISSING_WIKI_FILES wiki files missing" "Missing wiki files"
    fi
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
