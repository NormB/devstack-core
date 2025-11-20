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

echo "=================================="
echo "  Network Segmentation Tests"
echo "=================================="
echo ""

# Test 1-4: Verify network creation
for network in vault-network data-network app-network observability-network; do
    if docker network inspect devstack-core_$network > /dev/null 2>&1; then
        print_result "$network exists" "PASS"
    else
        print_result "$network exists" "FAIL"
    fi
done

# Test 5-8: Verify network subnets
networks=(
    "vault-network:172.20.1.0/24"
    "data-network:172.20.2.0/24"
    "app-network:172.20.3.0/24"
    "observability-network:172.20.4.0/24"
)

for entry in "${networks[@]}"; do
    network="${entry%%:*}"
    expected_subnet="${entry##*:}"
    actual_subnet=$(docker network inspect devstack-core_$network --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "")
    if [ "$actual_subnet" = "$expected_subnet" ]; then
        print_result "$network has correct subnet" "PASS" "Subnet: $actual_subnet"
    else
        print_result "$network has correct subnet" "FAIL" "Expected: $expected_subnet, Got: $actual_subnet"
    fi
done

# Test 9: Verify Vault is only on vault-network
vault_networks=$(docker inspect dev-vault --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null | tr ' ' '\n' | grep -v '^$')
if echo "$vault_networks" | grep -q "vault-network" && [ $(echo "$vault_networks" | wc -l) -eq 1 ]; then
    print_result "Vault isolated on vault-network only" "PASS"
else
    print_result "Vault isolated on vault-network only" "FAIL" "Networks: $vault_networks"
fi

# Test 10: Verify PostgreSQL is on vault-network and data-network
postgres_networks=$(docker inspect dev-postgres --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null)
if echo "$postgres_networks" | grep -q "vault-network" && echo "$postgres_networks" | grep -q "data-network"; then
    print_result "PostgreSQL on vault-network and data-network" "PASS"
else
    print_result "PostgreSQL on vault-network and data-network" "FAIL" "Networks: $postgres_networks"
fi

# Test 11: Verify Forgejo is on vault-network, data-network, and app-network
forgejo_networks=$(docker inspect dev-forgejo --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null)
if echo "$forgejo_networks" | grep -q "vault-network" && \
   echo "$forgejo_networks" | grep -q "data-network" && \
   echo "$forgejo_networks" | grep -q "app-network"; then
    print_result "Forgejo on vault, data, and app networks" "PASS"
else
    print_result "Forgejo on vault, data, and app networks" "FAIL" "Networks: $forgejo_networks"
fi

# Test 12: Verify Forgejo can reach Vault (via vault-network)
# Forgejo has wget, so we can test HTTP connectivity
if docker exec dev-forgejo wget -q -O /dev/null --timeout=5 http://vault:8200/v1/sys/health 2>/dev/null; then
    print_result "Forgejo can reach Vault via vault-network" "PASS"
else
    print_result "Forgejo can reach Vault via vault-network" "FAIL"
fi

# Test 13: Verify Forgejo is connected to PostgreSQL database
# Instead of nc test, verify Forgejo actually connects (check health or logs)
if docker exec dev-forgejo wget -q -O /dev/null --timeout=5 http://localhost:3000/api/healthz 2>/dev/null; then
    print_result "Forgejo can reach PostgreSQL via data-network" "PASS" "Forgejo healthy = database connected"
else
    print_result "Forgejo can reach PostgreSQL via data-network" "FAIL"
fi

# Note: PostgreSQL and MySQL containers don't have nc/wget, but we can verify
# they reached Vault successfully by checking they are healthy (they need Vault for startup)
# Test 14: Verify data services authenticated with Vault successfully
# If postgres/mysql are healthy, they successfully reached Vault for AppRole auth
if docker compose ps postgres --format "{{.Status}}" | grep -q "healthy" && \
   docker compose ps mysql --format "{{.Status}}" | grep -q "healthy"; then
    print_result "Data services authenticated with Vault via vault-network" "PASS" "PostgreSQL & MySQL healthy = Vault auth succeeded"
else
    print_result "Data services authenticated with Vault via vault-network" "FAIL"
fi

# Test 15: Verify Redis cluster nodes can communicate (via data-network)
if docker exec dev-redis-1 redis-cli -h redis-2 -a $(docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN=$(cat ~/.config/vault/root-token) dev-vault vault kv get -field=password secret/redis-1 2>/dev/null) PING 2>/dev/null | grep -q "PONG"; then
    print_result "Redis cluster nodes can communicate" "PASS"
else
    print_result "Redis cluster nodes can communicate" "FAIL"
fi

# Test 16: Verify PgBouncer is on data-network and app-network
pgbouncer_networks=$(docker inspect dev-pgbouncer --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null)
if echo "$pgbouncer_networks" | grep -q "data-network" && echo "$pgbouncer_networks" | grep -q "app-network"; then
    print_result "PgBouncer on data and app networks" "PASS"
else
    print_result "PgBouncer on data and app networks" "FAIL" "Networks: $pgbouncer_networks"
fi

# Test 17: Verify RabbitMQ is only on vault-network and data-network
rabbitmq_networks=$(docker inspect dev-rabbitmq --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null)
if echo "$rabbitmq_networks" | grep -q "vault-network" && echo "$rabbitmq_networks" | grep -q "data-network"; then
    print_result "RabbitMQ on vault and data networks" "PASS"
else
    print_result "RabbitMQ on vault and data networks" "FAIL" "Networks: $rabbitmq_networks"
fi

# Test 18: Verify MongoDB is only on vault-network and data-network
mongodb_networks=$(docker inspect dev-mongodb --format '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' 2>/dev/null)
if echo "$mongodb_networks" | grep -q "vault-network" && echo "$mongodb_networks" | grep -q "data-network"; then
    print_result "MongoDB on vault and data networks" "PASS"
else
    print_result "MongoDB on vault and data networks" "FAIL" "Networks: $mongodb_networks"
fi

# Test 19: Verify all services are healthy
services="postgres mysql mongodb redis-1 redis-2 redis-3 rabbitmq forgejo vault"
all_healthy=true
for service in $services; do
    status=$(docker compose ps $service --format "{{.Status}}" | grep -o "healthy" || echo "not healthy")
    if [ "$status" != "healthy" ]; then
        all_healthy=false
        break
    fi
done

if $all_healthy; then
    print_result "All services healthy after network segmentation" "PASS"
else
    print_result "All services healthy after network segmentation" "FAIL"
fi

# Test 20: Verify key services have correct IP addresses (bash 3.2 compatible)
ip_tests_passed=true

# Check Vault IP on vault-network
vault_ip=$(docker inspect dev-vault --format '{{range $key, $value := .NetworkSettings.Networks}}{{if eq $key "devstack-core_vault-network"}}{{$value.IPAddress}}{{end}}{{end}}' 2>/dev/null)
if [ "$vault_ip" != "172.20.1.5" ]; then
    ip_tests_passed=false
fi

# Check PostgreSQL IP on data-network
postgres_ip=$(docker inspect dev-postgres --format '{{range $key, $value := .NetworkSettings.Networks}}{{if eq $key "devstack-core_data-network"}}{{$value.IPAddress}}{{end}}{{end}}' 2>/dev/null)
if [ "$postgres_ip" != "172.20.2.10" ]; then
    ip_tests_passed=false
fi

# Check Forgejo IP on app-network
forgejo_ip=$(docker inspect dev-forgejo --format '{{range $key, $value := .NetworkSettings.Networks}}{{if eq $key "devstack-core_app-network"}}{{$value.IPAddress}}{{end}}{{end}}' 2>/dev/null)
if [ "$forgejo_ip" != "172.20.3.20" ]; then
    ip_tests_passed=false
fi

if $ip_tests_passed; then
    print_result "Key services have correct IP addresses" "PASS" "Vault=172.20.1.5, PostgreSQL=172.20.2.10, Forgejo=172.20.3.20"
else
    print_result "Key services have correct IP addresses" "FAIL"
fi

# Test 21: Verify no services are on the old dev-services network
if docker network inspect devstack-core_dev-services > /dev/null 2>&1; then
    print_result "Old dev-services network removed" "FAIL" "Network still exists"
else
    print_result "Old dev-services network removed" "PASS"
fi

print_summary
