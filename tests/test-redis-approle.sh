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

# Detect which Redis nodes are running (dynamic 1-3 based on profile)
REDIS_NODES=()
for node in redis-1 redis-2 redis-3; do
    if docker ps --format '{{.Names}}' | /usr/bin/grep -q "dev-$node"; then
        REDIS_NODES+=("$node")
    fi
done

if [ ${#REDIS_NODES[@]} -eq 0 ]; then
    echo -e "${RED}ERROR: No Redis containers running${NC}"
    exit 1
fi

echo -e "${BLUE}Detected ${#REDIS_NODES[@]} Redis node(s): ${REDIS_NODES[*]}${NC}"
echo ""

# Get Redis password from Vault (all nodes share same password from secret/redis-1)
password=$(docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN=$(cat ${VAULT_CONFIG_DIR}/root-token) dev-vault vault kv get -field=password secret/redis-1 2>/dev/null || echo "")

# Test 1-3: Container running, entrypoint, and AppRole credentials for each node
for node in "${REDIS_NODES[@]}"; do
    # Test: Container is running
    if docker ps --format '{{.Names}}' | /usr/bin/grep -q "dev-$node"; then
        print_result "$node container is running" "PASS"
    else
        print_result "$node container is running" "FAIL"
    fi

    # Test: Container uses init-approle.sh entrypoint
    entrypoint=$(docker inspect dev-$node --format '{{json .Config.Entrypoint}}')
    if echo "$entrypoint" | /usr/bin/grep -q "init-approle.sh"; then
        print_result "$node uses init-approle.sh entrypoint" "PASS"
    else
        print_result "$node uses init-approle.sh entrypoint" "FAIL"
    fi

    # Test: AppRole credentials are mounted
    if docker exec dev-$node test -f /vault-approles/redis/role-id && \
       docker exec dev-$node test -f /vault-approles/redis/secret-id; then
        print_result "$node AppRole credentials are mounted" "PASS"
    else
        print_result "$node AppRole credentials are mounted" "FAIL"
    fi
done

# Test: No VAULT_TOKEN in environment for first node
node="${REDIS_NODES[0]}"
env_vars=$(docker exec dev-$node env)
if echo "$env_vars" | /usr/bin/grep -q "^VAULT_TOKEN="; then
    print_result "No VAULT_TOKEN in $node environment" "FAIL"
else
    print_result "No VAULT_TOKEN in $node environment" "PASS"
fi

# Test: VAULT_APPROLE_DIR environment variable is set for first node
approle_dir=$(docker exec dev-$node printenv VAULT_APPROLE_DIR 2>/dev/null || echo "")
if [ -n "$approle_dir" ]; then
    print_result "VAULT_APPROLE_DIR environment variable is set in $node" "PASS"
else
    print_result "VAULT_APPROLE_DIR environment variable is set in $node" "FAIL"
fi

# Test: Redis nodes started successfully (connection test for each node)
for node in "${REDIS_NODES[@]}"; do
    if docker exec dev-$node redis-cli -a "$password" PING > /dev/null 2>&1; then
        print_result "$node started successfully (PING)" "PASS"
    else
        print_result "$node started successfully (PING)" "FAIL"
    fi
done

# Test: AppRole authentication logs present for each node
for node in "${REDIS_NODES[@]}"; do
    logs=$(docker compose logs $node 2>&1)
    if echo "$logs" | /usr/bin/grep -E "AppRole authentication successful.*token:" > /dev/null; then
        print_result "$node AppRole authentication logs present" "PASS"
    else
        print_result "$node AppRole authentication logs present" "FAIL"
    fi
done

# Test: Redis operations work with AppRole credentials for first node
node="${REDIS_NODES[0]}"
if docker exec dev-$node sh -c "redis-cli -a $password SET test_key 'AppRole works' > /dev/null 2>&1 && redis-cli -a $password GET test_key > /dev/null 2>&1 && redis-cli -a $password DEL test_key > /dev/null 2>&1"; then
    print_result "Redis operations work with AppRole credentials ($node)" "PASS"
else
    print_result "Redis operations work with AppRole credentials ($node)" "FAIL"
fi

# Test: No root token in container logs for first node
node="${REDIS_NODES[0]}"
logs=$(docker compose logs $node 2>&1)
root_token=$(cat ${VAULT_CONFIG_DIR}/root-token 2>/dev/null || echo "")
if [ -n "$root_token" ] && echo "$logs" | /usr/bin/grep -q "$root_token"; then
    print_result "No root token in $node logs" "FAIL"
else
    print_result "No root token in $node logs" "PASS"
fi

# Test: Temporary token obtained via AppRole for first node
node="${REDIS_NODES[0]}"
logs=$(docker compose logs $node 2>&1)
if echo "$logs" | /usr/bin/grep -E "AppRole authentication successful.*token:.*hvs\." > /dev/null; then
    temp_token=$(echo "$logs" | /usr/bin/grep -E "AppRole authentication successful" | /usr/bin/grep -oE "hvs\.[A-Za-z0-9]+" | head -1)
    if [ "$temp_token" = "$root_token" ]; then
        print_result "Temporary token obtained via AppRole ($node)" "FAIL"
    else
        print_result "Temporary token obtained via AppRole ($node)" "PASS"
    fi
else
    print_result "Temporary token obtained via AppRole ($node)" "FAIL"
fi

# Test: Policy enforcement - redis cannot access postgres secret
role_id=$(cat "${APPROLE_DIR}/redis/role-id" 2>/dev/null || echo "")
secret_id=$(cat "${APPROLE_DIR}/redis/secret-id" 2>/dev/null || echo "")
if [ -n "$role_id" ] && [ -n "$secret_id" ]; then
    token=$(docker exec -e VAULT_ADDR=http://vault:8200 dev-vault \
        vault write -field=token auth/approle/login \
        role_id="$role_id" secret_id="$secret_id" 2>/dev/null || echo "")
    if [ -n "$token" ]; then
        if docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN="$token" dev-vault \
            vault kv get secret/postgres > /dev/null 2>&1; then
            print_result "Policy enforcement: redis cannot access postgres secret" "FAIL"
        else
            print_result "Policy enforcement: redis cannot access postgres secret" "PASS"
        fi
    else
        print_result "Policy enforcement: redis cannot access postgres secret" "FAIL" "Failed to auth"
    fi
else
    print_result "Policy enforcement: redis cannot access postgres secret" "FAIL" "Cannot read credentials"
fi

# Test: init-approle.sh script exists and is executable
if [ -f "${PROJECT_ROOT}/configs/redis/scripts/init-approle.sh" ] && \
   [ -x "${PROJECT_ROOT}/configs/redis/scripts/init-approle.sh" ]; then
    print_result "init-approle.sh script exists and is executable" "PASS"
else
    print_result "init-approle.sh script exists and is executable" "FAIL"
fi

# Test: docker-compose.yml has correct AppRole configuration for all nodes
compose_file="${PROJECT_ROOT}/docker-compose.yml"
failures=0
for node in redis-1 redis-2 redis-3; do
    # Check entrypoint
    if ! /usr/bin/grep -A 12 "^  $node:" "$compose_file" | /usr/bin/grep -q "init-approle.sh"; then
        failures=$((failures + 1))
    fi
    # Check AppRole volume mount
    if ! /usr/bin/grep -A 30 "^  $node:" "$compose_file" | /usr/bin/grep -q "vault/approles/redis"; then
        failures=$((failures + 1))
    fi
    # Check VAULT_APPROLE_DIR env var
    if ! /usr/bin/grep -A 20 "^  $node:" "$compose_file" | /usr/bin/grep -q "VAULT_APPROLE_DIR"; then
        failures=$((failures + 1))
    fi
done

if [ $failures -eq 0 ]; then
    print_result "docker-compose.yml has correct AppRole configuration" "PASS"
else
    print_result "docker-compose.yml has correct AppRole configuration" "FAIL" "$failures check(s) failed"
fi

# Test: All nodes share same password from secret/redis-1
if [ -n "$password" ]; then
    all_same=true
    for node in "${REDIS_NODES[@]}"; do
        if ! docker exec dev-$node redis-cli -a "$password" PING > /dev/null 2>&1; then
            all_same=false
            break
        fi
    done
    if [ "$all_same" = true ]; then
        print_result "All nodes share same password from secret/redis-1" "PASS"
    else
        print_result "All nodes share same password from secret/redis-1" "FAIL"
    fi
else
    print_result "All nodes share same password from secret/redis-1" "FAIL" "Cannot retrieve password"
fi

print_summary
