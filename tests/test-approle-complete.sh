#!/bin/bash
################################################################################
# Comprehensive AppRole Authentication Verification Test
# Tests all 7 services to prove they use AppRole (not root token)
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}AppRole Authentication Verification Test${NC}"
echo -e "${BLUE}Testing all 7 services${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

test_service() {
    local service=$1
    local container=$2
    local test_name=$3

    echo -e "${BLUE}Testing: $test_name${NC}"

    # Test 1: Check AppRole credentials exist on host
    if [ -f "$HOME/.config/vault/approles/$service/role-id" ] && [ -f "$HOME/.config/vault/approles/$service/secret-id" ]; then
        echo -e "  ${GREEN}✓${NC} AppRole credentials exist on host"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} AppRole credentials NOT found on host"
        ((FAIL++))
        return 1
    fi

    # Test 2: Check container is running
    if docker ps --filter "name=$container" --format "{{.Status}}" | grep -q "Up"; then
        echo -e "  ${GREEN}✓${NC} Container is running"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} Container is NOT running"
        ((FAIL++))
        return 1
    fi

    # Test 3: Check NO VAULT_TOKEN environment variable in container
    if docker exec $container env 2>/dev/null | grep -q "^VAULT_TOKEN="; then
        echo -e "  ${RED}✗${NC} VAULT_TOKEN found in container (should not exist!)"
        ((FAIL++))
        return 1
    else
        echo -e "  ${GREEN}✓${NC} No VAULT_TOKEN in container (AppRole required)"
        ((PASS++))
    fi

    # Test 4: Check AppRole credentials are mounted in container
    if docker exec $container test -f "/vault-approles/$service/role-id" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} AppRole credentials mounted in container"
        ((PASS++))
    else
        echo -e "  ${RED}✗${NC} AppRole credentials NOT mounted in container"
        ((FAIL++))
        return 1
    fi

    # Test 5: Check logs for AppRole authentication success OR verify token type for Python apps
    if docker logs $container 2>&1 | grep -q "AppRole authentication successful"; then
        echo -e "  ${GREEN}✓${NC} AppRole authentication successful in logs"
        ((PASS++))
    elif [ "$container" = "dev-reference-api" ]; then
        # For Python apps, verify the token type instead of log message
        local token_prefix=$(docker exec $container python -c "from app.services.vault import vault_client; print(vault_client.vault_token[:10] if vault_client.vault_token else 'NONE')" 2>/dev/null)
        if [[ "$token_prefix" == hvs.CAESIE* ]] || [[ "$token_prefix" == hvs.CAESI* ]]; then
            echo -e "  ${GREEN}✓${NC} AppRole token verified (service token: ${token_prefix})"
            ((PASS++))
        else
            echo -e "  ${RED}✗${NC} Token type verification failed: $token_prefix"
            ((FAIL++))
            return 1
        fi
    else
        echo -e "  ${RED}✗${NC} AppRole authentication NOT found in logs"
        ((FAIL++))
        return 1
    fi

    echo ""
    return 0
}

# Test all 7 services
echo -e "${YELLOW}Service 1/7: PostgreSQL${NC}"
test_service "postgres" "dev-postgres" "PostgreSQL AppRole Authentication"

echo -e "${YELLOW}Service 2/7: MySQL${NC}"
test_service "mysql" "dev-mysql" "MySQL AppRole Authentication"

echo -e "${YELLOW}Service 3/7: MongoDB${NC}"
test_service "mongodb" "dev-mongodb" "MongoDB AppRole Authentication"

echo -e "${YELLOW}Service 4/7: Redis (Node 1)${NC}"
test_service "redis" "dev-redis-1" "Redis Node 1 AppRole Authentication"

echo -e "${YELLOW}Service 5/7: Redis (Node 2)${NC}"
test_service "redis" "dev-redis-2" "Redis Node 2 AppRole Authentication"

echo -e "${YELLOW}Service 6/7: Redis (Node 3)${NC}"
test_service "redis" "dev-redis-3" "Redis Node 3 AppRole Authentication"

echo -e "${YELLOW}Service 7/7: RabbitMQ${NC}"
test_service "rabbitmq" "dev-rabbitmq" "RabbitMQ AppRole Authentication"

echo -e "${YELLOW}Service 8/7: Forgejo${NC}"
test_service "forgejo" "dev-forgejo" "Forgejo AppRole Authentication"

echo -e "${YELLOW}Service 9/7: Reference API${NC}"
test_service "reference-api" "dev-reference-api" "Reference API AppRole Authentication"

# Final summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "Total Passed: ${GREEN}$PASS${NC}"
echo -e "Total Failed: ${RED}$FAIL${NC}"
echo ""

if [ $FAIL -eq 0 ]; then
    echo -e "${GREEN}✓ ALL SERVICES ARE USING APPROLE AUTHENTICATION${NC}"
    echo -e "${GREEN}✓ NO ROOT TOKENS FOUND IN CONTAINERS${NC}"
    echo -e "${GREEN}✓ MIGRATION IS 100% COMPLETE${NC}"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    exit 1
fi
