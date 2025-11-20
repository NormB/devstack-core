#!/bin/bash
# Rust API Tests
# Tests the Rust reference API endpoints

set -e

BASE_URL="${TEST_URL:-http://localhost:8004}"
FAILED=0

echo "Testing Rust API at ${BASE_URL}"
echo "================================"

# Test root endpoint
echo -n "GET / (API info)... "
RESPONSE=$(curl -s "${BASE_URL}/")
if echo "$RESPONSE" | grep -q "DevStack Core Rust Reference API"; then
    echo "✓ PASSED"
else
    echo "✗ FAILED"
    FAILED=$((FAILED + 1))
fi

# Test health endpoint
echo -n "GET /health/ (simple health)... "
RESPONSE=$(curl -s "${BASE_URL}/health/")
if echo "$RESPONSE" | grep -q "healthy"; then
    echo "✓ PASSED"
else
    echo "✗ FAILED"
    FAILED=$((FAILED + 1))
fi

# Test Vault health endpoint
echo -n "GET /health/vault (Vault health)... "
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/health/vault")
if [ "$STATUS_CODE" = "200" ] || [ "$STATUS_CODE" = "503" ]; then
    echo "✓ PASSED (HTTP $STATUS_CODE)"
else
    echo "✗ FAILED (HTTP $STATUS_CODE)"
    FAILED=$((FAILED + 1))
fi

# Test metrics endpoint
echo -n "GET /metrics (metrics)... "
STATUS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/metrics")
if [ "$STATUS_CODE" = "200" ]; then
    echo "✓ PASSED"
else
    echo "✗ FAILED (HTTP $STATUS_CODE)"
    FAILED=$((FAILED + 1))
fi

echo "================================"
if [ $FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ $FAILED test(s) failed"
    exit 1
fi
