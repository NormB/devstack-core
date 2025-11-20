#!/usr/bin/env bash

# AppRole Authentication Security Test Suite
# Phase 3 - Task 3.3.1: Test AppRole authentication failure scenarios
#
# Tests:
# 1. Invalid role_id (should fail)
# 2. Invalid secret_id (should fail)
# 3. Missing AppRole credentials (should fail gracefully)
# 4. Cross-service authentication attempts (should fail - policy enforcement)
# 5. AppRole token expiration (1 hour TTL)
# 6. Successful authentication validation
# 7. Policy-based access control enforcement

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Vault configuration
VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200}
VAULT_TOKEN=${VAULT_TOKEN:-$(cat ~/.config/vault/root-token 2>/dev/null || echo "")}

if [ -z "$VAULT_TOKEN" ]; then
    echo "ERROR: VAULT_TOKEN not set and ~/.config/vault/root-token not found"
    exit 1
fi

export VAULT_ADDR VAULT_TOKEN

# Helper functions
print_test() {
    echo -e "\n${YELLOW}TEST $((TESTS_RUN + 1)):${NC} $1"
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++)) || true
    ((TESTS_RUN++)) || true
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++)) || true
    ((TESTS_RUN++)) || true
}

# Test Suite
echo "========================================="
echo "AppRole Authentication Security Tests"
echo "Phase 3 - Task 3.3.1"
echo "========================================="

# Test 1: Verify Vault is accessible
print_test "Vault is accessible and unsealed"
if vault status &>/dev/null; then
    pass
else
    fail "Vault is not accessible"
    exit 1
fi

# Test 2: Verify AppRole auth method is enabled
print_test "AppRole auth method is enabled"
if vault auth list | grep -q "approle"; then
    pass
else
    fail "AppRole auth method not enabled"
fi

# Test 3: Test invalid role_id authentication (should fail)
print_test "Invalid role_id authentication fails"
INVALID_ROLE_ID="invalid-role-id-12345"
POSTGRES_SECRET_ID=$(cat ~/.config/vault/approles/postgres/secret-id 2>/dev/null || echo "")

if [ -n "$POSTGRES_SECRET_ID" ]; then
    if vault write auth/approle/login role_id="$INVALID_ROLE_ID" secret_id="$POSTGRES_SECRET_ID" 2>&1 | grep -q "invalid role ID"; then
        pass
    else
        # Command might fail differently
        if ! vault write auth/approle/login role_id="$INVALID_ROLE_ID" secret_id="$POSTGRES_SECRET_ID" &>/dev/null; then
            pass
        else
            fail "Invalid role_id was accepted"
        fi
    fi
else
    fail "Could not read postgres secret_id for testing"
fi

# Test 4: Test invalid secret_id authentication (should fail)
print_test "Invalid secret_id authentication fails"
POSTGRES_ROLE_ID=$(cat ~/.config/vault/approles/postgres/role-id 2>/dev/null || echo "")
INVALID_SECRET_ID="invalid-secret-id-67890"

if [ -n "$POSTGRES_ROLE_ID" ]; then
    if vault write auth/approle/login role_id="$POSTGRES_ROLE_ID" secret_id="$INVALID_SECRET_ID" 2>&1 | grep -q "invalid secret id"; then
        pass
    else
        # Command might fail differently
        if ! vault write auth/approle/login role_id="$POSTGRES_ROLE_ID" secret_id="$INVALID_SECRET_ID" &>/dev/null; then
            pass
        else
            fail "Invalid secret_id was accepted"
        fi
    fi
else
    fail "Could not read postgres role_id for testing"
fi

# Test 5: Test missing role_id (should fail)
print_test "Missing role_id authentication fails"
if ! vault write auth/approle/login secret_id="$POSTGRES_SECRET_ID" &>/dev/null; then
    pass
else
    fail "Authentication succeeded without role_id"
fi

# Test 6: Test missing secret_id (should fail)
print_test "Missing secret_id authentication fails"
if ! vault write auth/approle/login role_id="$POSTGRES_ROLE_ID" &>/dev/null; then
    pass
else
    fail "Authentication succeeded without secret_id"
fi

# Test 7: Validate successful PostgreSQL AppRole authentication
print_test "Valid PostgreSQL AppRole authentication succeeds"
POSTGRES_TOKEN=""
if [ -n "$POSTGRES_ROLE_ID" ] && [ -n "$POSTGRES_SECRET_ID" ]; then
    POSTGRES_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$POSTGRES_ROLE_ID" \
        secret_id="$POSTGRES_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$POSTGRES_TOKEN" ]; then
        pass
    else
        fail "Valid PostgreSQL AppRole authentication failed"
    fi
else
    fail "Missing PostgreSQL AppRole credentials"
fi

# Test 8: Verify PostgreSQL token has correct policies
print_test "PostgreSQL token has correct policies attached"
if [ -n "$POSTGRES_TOKEN" ]; then
    TOKEN_POLICIES=$(VAULT_TOKEN="$POSTGRES_TOKEN" vault token lookup -format=json | jq -r '.data.policies[]' 2>/dev/null | tr '\n' ' ')

    if echo "$TOKEN_POLICIES" | grep -q "postgres-policy"; then
        pass
    else
        fail "PostgreSQL token missing postgres-policy. Policies: $TOKEN_POLICIES"
    fi
else
    fail "No PostgreSQL token to verify"
fi

# Test 9: Verify PostgreSQL token can access postgres secrets
print_test "PostgreSQL token can access postgres secrets"
if [ -n "$POSTGRES_TOKEN" ]; then
    if VAULT_TOKEN="$POSTGRES_TOKEN" vault kv get secret/postgres &>/dev/null; then
        pass
    else
        fail "PostgreSQL token cannot access postgres secrets"
    fi
else
    fail "No PostgreSQL token to test"
fi

# Test 10: Verify PostgreSQL token CANNOT access MySQL secrets (cross-service prevention)
print_test "PostgreSQL token cannot access MySQL secrets (policy enforcement)"
if [ -n "$POSTGRES_TOKEN" ]; then
    if VAULT_TOKEN="$POSTGRES_TOKEN" vault kv get secret/mysql &>/dev/null; then
        fail "PostgreSQL token accessed MySQL secrets (policy violation)"
    else
        pass
    fi
else
    fail "No PostgreSQL token to test"
fi

# Test 11: Test MySQL AppRole authentication
print_test "Valid MySQL AppRole authentication succeeds"
MYSQL_ROLE_ID=$(cat ~/.config/vault/approles/mysql/role-id 2>/dev/null || echo "")
MYSQL_SECRET_ID=$(cat ~/.config/vault/approles/mysql/secret-id 2>/dev/null || echo "")
MYSQL_TOKEN=""

if [ -n "$MYSQL_ROLE_ID" ] && [ -n "$MYSQL_SECRET_ID" ]; then
    MYSQL_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$MYSQL_ROLE_ID" \
        secret_id="$MYSQL_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$MYSQL_TOKEN" ]; then
        pass
    else
        fail "Valid MySQL AppRole authentication failed"
    fi
else
    fail "Missing MySQL AppRole credentials"
fi

# Test 12: Verify MySQL token can access MySQL secrets
print_test "MySQL token can access MySQL secrets"
if [ -n "$MYSQL_TOKEN" ]; then
    if VAULT_TOKEN="$MYSQL_TOKEN" vault kv get secret/mysql &>/dev/null; then
        pass
    else
        fail "MySQL token cannot access MySQL secrets"
    fi
else
    fail "No MySQL token to test"
fi

# Test 13: Verify MySQL token CANNOT access PostgreSQL secrets
print_test "MySQL token cannot access PostgreSQL secrets (policy enforcement)"
if [ -n "$MYSQL_TOKEN" ]; then
    if VAULT_TOKEN="$MYSQL_TOKEN" vault kv get secret/postgres &>/dev/null; then
        fail "MySQL token accessed PostgreSQL secrets (policy violation)"
    else
        pass
    fi
else
    fail "No MySQL token to test"
fi

# Test 14: Test Redis AppRole authentication
print_test "Valid Redis AppRole authentication succeeds"
REDIS_ROLE_ID=$(cat ~/.config/vault/approles/redis/role-id 2>/dev/null || echo "")
REDIS_SECRET_ID=$(cat ~/.config/vault/approles/redis/secret-id 2>/dev/null || echo "")
REDIS_TOKEN=""

if [ -n "$REDIS_ROLE_ID" ] && [ -n "$REDIS_SECRET_ID" ]; then
    REDIS_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$REDIS_ROLE_ID" \
        secret_id="$REDIS_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$REDIS_TOKEN" ]; then
        pass
    else
        fail "Valid Redis AppRole authentication failed"
    fi
else
    fail "Missing Redis AppRole credentials"
fi

# Test 15: Verify Redis token can access Redis secrets
print_test "Redis token can access Redis secrets"
if [ -n "$REDIS_TOKEN" ]; then
    if VAULT_TOKEN="$REDIS_TOKEN" vault kv get secret/redis-1 &>/dev/null; then
        pass
    else
        fail "Redis token cannot access Redis secrets"
    fi
else
    fail "No Redis token to test"
fi

# Test 16: Test MongoDB AppRole authentication
print_test "Valid MongoDB AppRole authentication succeeds"
MONGODB_ROLE_ID=$(cat ~/.config/vault/approles/mongodb/role-id 2>/dev/null || echo "")
MONGODB_SECRET_ID=$(cat ~/.config/vault/approles/mongodb/secret-id 2>/dev/null || echo "")
MONGODB_TOKEN=""

if [ -n "$MONGODB_ROLE_ID" ] && [ -n "$MONGODB_SECRET_ID" ]; then
    MONGODB_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$MONGODB_ROLE_ID" \
        secret_id="$MONGODB_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$MONGODB_TOKEN" ]; then
        pass
    else
        fail "Valid MongoDB AppRole authentication failed"
    fi
else
    fail "Missing MongoDB AppRole credentials"
fi

# Test 17: Test RabbitMQ AppRole authentication
print_test "Valid RabbitMQ AppRole authentication succeeds"
RABBITMQ_ROLE_ID=$(cat ~/.config/vault/approles/rabbitmq/role-id 2>/dev/null || echo "")
RABBITMQ_SECRET_ID=$(cat ~/.config/vault/approles/rabbitmq/secret-id 2>/dev/null || echo "")
RABBITMQ_TOKEN=""

if [ -n "$RABBITMQ_ROLE_ID" ] && [ -n "$RABBITMQ_SECRET_ID" ]; then
    RABBITMQ_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$RABBITMQ_ROLE_ID" \
        secret_id="$RABBITMQ_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$RABBITMQ_TOKEN" ]; then
        pass
    else
        fail "Valid RabbitMQ AppRole authentication failed"
    fi
else
    fail "Missing RabbitMQ AppRole credentials"
fi

# Test 18: Test Forgejo AppRole authentication
print_test "Valid Forgejo AppRole authentication succeeds"
FORGEJO_ROLE_ID=$(cat ~/.config/vault/approles/forgejo/role-id 2>/dev/null || echo "")
FORGEJO_SECRET_ID=$(cat ~/.config/vault/approles/forgejo/secret-id 2>/dev/null || echo "")
FORGEJO_TOKEN=""

if [ -n "$FORGEJO_ROLE_ID" ] && [ -n "$FORGEJO_SECRET_ID" ]; then
    FORGEJO_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$FORGEJO_ROLE_ID" \
        secret_id="$FORGEJO_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$FORGEJO_TOKEN" ]; then
        pass
    else
        fail "Valid Forgejo AppRole authentication failed"
    fi
else
    fail "Missing Forgejo AppRole credentials"
fi

# Test 19: Test Reference API AppRole authentication
print_test "Valid Reference API AppRole authentication succeeds"
REFERENCE_API_ROLE_ID=$(cat ~/.config/vault/approles/reference-api/role-id 2>/dev/null || echo "")
REFERENCE_API_SECRET_ID=$(cat ~/.config/vault/approles/reference-api/secret-id 2>/dev/null || echo "")
REFERENCE_API_TOKEN=""

if [ -n "$REFERENCE_API_ROLE_ID" ] && [ -n "$REFERENCE_API_SECRET_ID" ]; then
    REFERENCE_API_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$REFERENCE_API_ROLE_ID" \
        secret_id="$REFERENCE_API_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$REFERENCE_API_TOKEN" ]; then
        pass
    else
        fail "Valid Reference API AppRole authentication failed"
    fi
else
    fail "Missing Reference API AppRole credentials"
fi

# Test 20: Test API-First AppRole authentication
print_test "Valid API-First AppRole authentication succeeds"
API_FIRST_ROLE_ID=$(cat ~/.config/vault/approles/api-first/role-id 2>/dev/null || echo "")
API_FIRST_SECRET_ID=$(cat ~/.config/vault/approles/api-first/secret-id 2>/dev/null || echo "")
API_FIRST_TOKEN=""

if [ -n "$API_FIRST_ROLE_ID" ] && [ -n "$API_FIRST_SECRET_ID" ]; then
    API_FIRST_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$API_FIRST_ROLE_ID" \
        secret_id="$API_FIRST_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$API_FIRST_TOKEN" ]; then
        pass
    else
        fail "Valid API-First AppRole authentication failed"
    fi
else
    fail "Missing API-First AppRole credentials"
fi

# Test 21: Test Golang API AppRole authentication
print_test "Valid Golang API AppRole authentication succeeds"
GOLANG_API_ROLE_ID=$(cat ~/.config/vault/approles/golang-api/role-id 2>/dev/null || echo "")
GOLANG_API_SECRET_ID=$(cat ~/.config/vault/approles/golang-api/secret-id 2>/dev/null || echo "")
GOLANG_API_TOKEN=""

if [ -n "$GOLANG_API_ROLE_ID" ] && [ -n "$GOLANG_API_SECRET_ID" ]; then
    GOLANG_API_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$GOLANG_API_ROLE_ID" \
        secret_id="$GOLANG_API_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$GOLANG_API_TOKEN" ]; then
        pass
    else
        fail "Valid Golang API AppRole authentication failed"
    fi
else
    fail "Missing Golang API AppRole credentials"
fi

# Test 22: Test Node.js API AppRole authentication
print_test "Valid Node.js API AppRole authentication succeeds"
NODEJS_API_ROLE_ID=$(cat ~/.config/vault/approles/nodejs-api/role-id 2>/dev/null || echo "")
NODEJS_API_SECRET_ID=$(cat ~/.config/vault/approles/nodejs-api/secret-id 2>/dev/null || echo "")
NODEJS_API_TOKEN=""

if [ -n "$NODEJS_API_ROLE_ID" ] && [ -n "$NODEJS_API_SECRET_ID" ]; then
    NODEJS_API_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$NODEJS_API_ROLE_ID" \
        secret_id="$NODEJS_API_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$NODEJS_API_TOKEN" ]; then
        pass
    else
        fail "Valid Node.js API AppRole authentication failed"
    fi
else
    fail "Missing Node.js API AppRole credentials"
fi

# Test 23: Test Rust API AppRole authentication
print_test "Valid Rust API AppRole authentication succeeds"
RUST_API_ROLE_ID=$(cat ~/.config/vault/approles/rust-api/role-id 2>/dev/null || echo "")
RUST_API_SECRET_ID=$(cat ~/.config/vault/approles/rust-api/secret-id 2>/dev/null || echo "")
RUST_API_TOKEN=""

if [ -n "$RUST_API_ROLE_ID" ] && [ -n "$RUST_API_SECRET_ID" ]; then
    RUST_API_TOKEN=$(vault write -field=token auth/approle/login \
        role_id="$RUST_API_ROLE_ID" \
        secret_id="$RUST_API_SECRET_ID" 2>/dev/null || echo "")

    if [ -n "$RUST_API_TOKEN" ]; then
        pass
    else
        fail "Valid Rust API AppRole authentication failed"
    fi
else
    fail "Missing Rust API AppRole credentials"
fi

# Test 24: Verify API-First token can access infrastructure secrets (postgres, mysql, etc.)
print_test "API-First token can access infrastructure secrets (postgres)"
if [ -n "$API_FIRST_TOKEN" ]; then
    if VAULT_TOKEN="$API_FIRST_TOKEN" vault kv get secret/postgres &>/dev/null; then
        pass
    else
        fail "API-First token cannot access postgres secrets"
    fi
else
    fail "No API-First token to test"
fi

# Test 25: Verify token TTL is 1 hour (3600 seconds)
print_test "AppRole tokens have 1 hour TTL (3600s)"
if [ -n "$POSTGRES_TOKEN" ]; then
    TOKEN_TTL=$(VAULT_TOKEN="$POSTGRES_TOKEN" vault token lookup -format=json | jq -r '.data.ttl' 2>/dev/null || echo "0")

    # TTL should be close to 3600 (allow for a few seconds variance during testing)
    if [ "$TOKEN_TTL" -ge 3500 ] && [ "$TOKEN_TTL" -le 3600 ]; then
        pass
    else
        fail "Token TTL is $TOKEN_TTL seconds, expected ~3600s"
    fi
else
    fail "No token to verify TTL"
fi

# Test 26: Verify token is renewable
print_test "AppRole tokens are renewable"
if [ -n "$POSTGRES_TOKEN" ]; then
    TOKEN_RENEWABLE=$(VAULT_TOKEN="$POSTGRES_TOKEN" vault token lookup -format=json | jq -r '.data.renewable' 2>/dev/null || echo "false")

    if [ "$TOKEN_RENEWABLE" = "true" ]; then
        pass
    else
        fail "Token is not renewable"
    fi
else
    fail "No token to verify renewable status"
fi

# Results
echo ""
echo "========================================="
echo "Test Results"
echo "========================================="
echo "Tests Run:    $TESTS_RUN"
echo -e "${GREEN}Tests Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Tests Failed: $TESTS_FAILED${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "\n${GREEN}✓ ALL TESTS PASSED${NC}"
    echo "AppRole authentication security: validated"
    echo "Policy enforcement: working correctly"
    echo "Cross-service access prevention: verified"
    exit 0
else
    echo -e "\n${RED}✗ SOME TESTS FAILED${NC}"
    exit 1
fi
