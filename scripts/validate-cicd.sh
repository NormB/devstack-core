#!/usr/bin/env bash
################################################################################
# Local CI/CD Validation Script
# Tests all checks that GitHub Actions workflows perform
################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

echo "=================================="
echo "  CI/CD Validation Tests"
echo "=================================="
echo ""

# Test 1: ShellCheck
echo "Test 1: Running ShellCheck on all shell scripts..."
if command -v shellcheck &> /dev/null; then
    if shellcheck configs/forgejo/scripts/init.sh configs/pgbouncer/scripts/init.sh; then
        echo -e "${GREEN}✓ ShellCheck passed${NC}"
    else
        echo -e "${RED}✗ ShellCheck failed${NC}"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${YELLOW}⚠ ShellCheck not installed, skipping${NC}"
fi
echo ""

# Test 2: Docker Compose validation
echo "Test 2: Validating docker-compose.yml..."
if docker compose config --quiet; then
    echo -e "${GREEN}✓ Docker Compose syntax valid${NC}"
else
    echo -e "${RED}✗ Docker Compose syntax invalid${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 3: Required environment variables
echo "Test 3: Checking required environment variables..."
REQUIRED_VARS=("VAULT_ADDR" "VAULT_TOKEN" "POSTGRES_USER" "POSTGRES_DB" "POSTGRES_PASSWORD" "MYSQL_USER" "MYSQL_DATABASE" "RABBITMQ_VHOST" "MONGODB_USER" "MONGODB_DATABASE")
MISSING=0
for var in "${REQUIRED_VARS[@]}"; do
    if ! /usr/bin/grep -q "^${var}=" .env.example; then
        echo -e "${RED}✗ Missing variable: $var${NC}"
        MISSING=$((MISSING + 1))
    fi
done
if [ $MISSING -eq 0 ]; then
    echo -e "${GREEN}✓ All required variables present${NC}"
else
    echo -e "${RED}✗ Missing $MISSING required variables${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 4: Script executable permissions
echo "Test 4: Checking script executable permissions..."
SCRIPTS=("devstack" "configs/vault/scripts/vault-init.sh" "configs/vault/scripts/vault-bootstrap.sh" "configs/forgejo/scripts/init.sh" "configs/pgbouncer/scripts/init.sh")
NON_EXEC=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ] && [ ! -x "$script" ]; then
        echo -e "${RED}✗ Not executable: $script${NC}"
        NON_EXEC=$((NON_EXEC + 1))
    fi
done
if [ $NON_EXEC -eq 0 ]; then
    echo -e "${GREEN}✓ All scripts are executable${NC}"
else
    echo -e "${RED}✗ $NON_EXEC scripts not executable${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 5: Script shebangs
echo "Test 5: Checking script shebangs..."
BAD_SHEBANGS=0
for script in "${SCRIPTS[@]}"; do
    if [ -f "$script" ]; then
        shebang=$(head -n 1 "$script")
        if [[ ! "$shebang" =~ ^#!/bin/bash$ ]] && \
           [[ ! "$shebang" =~ ^#!/usr/bin/env\ bash$ ]] && \
           [[ ! "$shebang" =~ ^#!/bin/sh$ ]]; then
            echo -e "${RED}✗ Invalid shebang in $script: $shebang${NC}"
            BAD_SHEBANGS=$((BAD_SHEBANGS + 1))
        fi
    fi
done
if [ $BAD_SHEBANGS -eq 0 ]; then
    echo -e "${GREEN}✓ All script shebangs are valid${NC}"
else
    echo -e "${RED}✗ $BAD_SHEBANGS scripts have invalid shebangs${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 6: .gitignore contains .env
echo "Test 6: Checking .gitignore for .env..."
if /usr/bin/grep -q "^\.env$" .gitignore; then
    echo -e "${GREEN}✓ .env is gitignored${NC}"
else
    echo -e "${RED}✗ .env not in .gitignore${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 7: README.md exists and has content
echo "Test 7: Checking README.md..."
if [ -f README.md ] && [ -s README.md ]; then
    echo -e "${GREEN}✓ README.md exists and has content${NC}"
else
    echo -e "${RED}✗ README.md missing or empty${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Test 8: Python syntax
echo "Test 8: Checking Python syntax..."
PYTHON_ERRORS=0
for pyfile in reference-apps/fastapi/app/main.py reference-apps/fastapi-api-first/app/main.py; do
    if [ -f "$pyfile" ]; then
        if ! python3 -m py_compile "$pyfile" 2>/dev/null; then
            echo -e "${RED}✗ Syntax error in: $pyfile${NC}"
            PYTHON_ERRORS=$((PYTHON_ERRORS + 1))
        fi
    fi
done
if [ $PYTHON_ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Python syntax valid${NC}"
else
    echo -e "${RED}✗ $PYTHON_ERRORS Python files have syntax errors${NC}"
    FAILED=$((FAILED + 1))
fi
echo ""

# Summary
echo "=================================="
echo "  Summary"
echo "=================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All CI/CD validation tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ $FAILED test(s) failed${NC}"
    echo ""
    echo "Please fix the issues above before pushing."
    exit 1
fi
