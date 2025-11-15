#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VAULT_CONFIG_DIR="${HOME}/.config/vault"
APPROLE_DIR="${VAULT_CONFIG_DIR}/approles"

print_result() {
    local test_name="$1"
    local result="$2"
    local message="${3:-}"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$result" = "PASS" ]; then
        echo -e "${GREEN}✓ PASS${NC}: $test_name"
        [ -n "$message" ] && echo -e "  ${BLUE}→${NC} $message"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗ FAIL${NC}: $test_name"
        [ -n "$message" ] && echo -e "  ${RED}→${NC} $message"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        FAILED_TESTS+=("$test_name")
    fi
}

print_summary() {
    echo ""
    echo "Total Tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo ""
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

# Test 1
if docker ps --format '{{.Names}}' | /usr/bin/grep -q "dev-mongodb"; then
    print_result "MongoDB container is running" "PASS"
else
    print_result "MongoDB container is running" "FAIL"
fi

# Test 2
entrypoint=$(docker inspect dev-mongodb --format '{{json .Config.Entrypoint}}')
if echo "$entrypoint" | /usr/bin/grep -q "init-approle.sh"; then
    print_result "Container uses init-approle.sh entrypoint" "PASS"
else
    print_result "Container uses init-approle.sh entrypoint" "FAIL"
fi

# Test 3
if docker exec dev-mongodb test -f /vault-approles/mongodb/role-id && \
   docker exec dev-mongodb test -f /vault-approles/mongodb/secret-id; then
    print_result "AppRole credentials are mounted" "PASS"
else
    print_result "AppRole credentials are mounted" "FAIL"
fi

# Test 4
env_vars=$(docker exec dev-mongodb env)
if echo "$env_vars" | /usr/bin/grep -q "^VAULT_TOKEN="; then
    print_result "No VAULT_TOKEN in environment" "FAIL"
else
    print_result "No VAULT_TOKEN in environment" "PASS"
fi

# Test 5
approle_dir=$(docker exec dev-mongodb printenv VAULT_APPROLE_DIR 2>/dev/null || echo "")
if [ -n "$approle_dir" ]; then
    print_result "VAULT_APPROLE_DIR environment variable is set" "PASS"
else
    print_result "VAULT_APPROLE_DIR environment variable is set" "FAIL"
fi

# Test 6
if docker exec dev-mongodb mongosh --eval "db.adminCommand('ping')" --quiet > /dev/null 2>&1; then
    print_result "MongoDB started successfully" "PASS"
else
    print_result "MongoDB started successfully" "FAIL"
fi

# Test 7 - Get logs and grep for AppRole auth (handle escape codes)
logs=$(docker compose logs mongodb 2>&1)
if echo "$logs" | /usr/bin/grep -E "AppRole authentication successful.*token:" > /dev/null; then
    print_result "AppRole authentication logs present" "PASS"
else
    print_result "AppRole authentication logs present" "FAIL"
fi

# Test 8
password=$(docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN=$(cat ${VAULT_CONFIG_DIR}/root-token) dev-vault vault kv get -field=password secret/mongodb 2>/dev/null)
if docker compose exec -T mongodb mongosh -u devuser -p ${password} --authenticationDatabase admin --eval "db.runCommand({ping: 1})" > /dev/null 2>&1; then
    print_result "Database connection works with AppRole credentials" "PASS"
else
    print_result "Database connection works with AppRole credentials" "FAIL"
fi

# Test 9
if docker compose exec -T mongodb mongosh -u devuser -p ${password} --authenticationDatabase admin --eval "
    use devdb;
    db.approle_test.insertOne({message: 'AppRole authentication works!'});
    var result = db.approle_test.findOne({message: /AppRole/});
    db.approle_test.drop();
    result ? true : false;
" > /dev/null 2>&1; then
    print_result "Database operations work (CREATE, INSERT, SELECT, DROP)" "PASS"
else
    print_result "Database operations work (CREATE, INSERT, SELECT, DROP)" "FAIL"
fi

# Test 10
root_token=$(cat ${VAULT_CONFIG_DIR}/root-token 2>/dev/null || echo "")
if [ -n "$root_token" ] && echo "$logs" | /usr/bin/grep -q "$root_token"; then
    print_result "No root token in container logs" "FAIL"
else
    print_result "No root token in container logs" "PASS"
fi

# Test 11 - Extract token with proper escape handling
if echo "$logs" | /usr/bin/grep -E "AppRole authentication successful.*token:.*hvs\." > /dev/null; then
    temp_token=$(echo "$logs" | /usr/bin/grep -E "AppRole authentication successful" | /usr/bin/grep -oE "hvs\.[A-Za-z0-9]+" | head -1)
    if [ "$temp_token" = "$root_token" ]; then
        print_result "Temporary token obtained via AppRole" "FAIL"
    else
        print_result "Temporary token obtained via AppRole" "PASS"
    fi
else
    print_result "Temporary token obtained via AppRole" "FAIL"
fi

# Test 12
role_id=$(cat "${APPROLE_DIR}/mongodb/role-id" 2>/dev/null || echo "")
secret_id=$(cat "${APPROLE_DIR}/mongodb/secret-id" 2>/dev/null || echo "")
if [ -n "$role_id" ] && [ -n "$secret_id" ]; then
    token=$(docker exec -e VAULT_ADDR=http://vault:8200 dev-vault \
        vault write -field=token auth/approle/login \
        role_id="$role_id" secret_id="$secret_id" 2>/dev/null || echo "")
    if [ -n "$token" ]; then
        if docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN="$token" dev-vault \
            vault kv get secret/postgres > /dev/null 2>&1; then
            print_result "Policy enforcement: mongodb cannot access postgres secret" "FAIL"
        else
            print_result "Policy enforcement: mongodb cannot access postgres secret" "PASS"
        fi
    else
        print_result "Policy enforcement: mongodb cannot access postgres secret" "FAIL" "Failed to auth"
    fi
else
    print_result "Policy enforcement: mongodb cannot access postgres secret" "FAIL" "Cannot read credentials"
fi

# Test 13
if [ -f "${PROJECT_ROOT}/configs/mongodb/scripts/init-approle.sh" ] && \
   [ -x "${PROJECT_ROOT}/configs/mongodb/scripts/init-approle.sh" ]; then
    print_result "init-approle.sh script exists and is executable" "PASS"
else
    print_result "init-approle.sh script exists and is executable" "FAIL"
fi

# Test 14
compose_file="${PROJECT_ROOT}/docker-compose.yml"
failures=0
if ! /usr/bin/grep -A 12 "^  mongodb:" "$compose_file" | /usr/bin/grep -q "init-approle.sh"; then
    failures=$((failures + 1))
fi
if ! /usr/bin/grep -A 30 "^  mongodb:" "$compose_file" | /usr/bin/grep -q "vault/approles/mongodb"; then
    failures=$((failures + 1))
fi
if ! /usr/bin/grep -A 20 "^  mongodb:" "$compose_file" | /usr/bin/grep -q "VAULT_APPROLE_DIR"; then
    failures=$((failures + 1))
fi
if [ $failures -eq 0 ]; then
    print_result "docker-compose.yml has correct AppRole configuration" "PASS"
else
    print_result "docker-compose.yml has correct AppRole configuration" "FAIL"
fi

print_summary
