# DevStack Core Test Suite

## Table of Contents

- [Quick Start](#quick-start)
- [Test Suites](#test-suites)
  - [Infrastructure Tests](#infrastructure-tests)
  - [Database Tests](#database-tests)
  - [Cache & Messaging Tests](#cache-messaging-tests)
  - [Application Tests](#application-tests)
- [New Features (Latest Update)](#new-features-latest-update)
  - [1. Redis Cluster Testing (`test-redis-cluster.sh`)](#1-redis-cluster-testing-test-redis-clustersh)
  - [2. FastAPI Application Testing (`test-fastapi.sh`)](#2-fastapi-application-testing-test-fastapish)
  - [3. Enhanced Test Runner (`run-all-tests.sh`)](#3-enhanced-test-runner-run-all-testssh)
- [Prerequisites](#prerequisites)
  - [System Dependencies](#system-dependencies)
  - [Python Dependencies](#python-dependencies)
- [Test Output Example](#test-output-example)
- [Running Individual Tests](#running-individual-tests)
  - [Test FastAPI and Redis Cluster APIs](#test-fastapi-and-redis-cluster-apis)
  - [Test Redis Cluster Configuration](#test-redis-cluster-configuration)
  - [Test All Infrastructure](#test-all-infrastructure)
- [Test Coverage Summary](#test-coverage-summary)
- [What Gets Validated](#what-gets-validated)
  - [✅ Infrastructure](#-infrastructure)
  - [✅ Data Layer](#-data-layer)
  - [✅ Cache Layer (New!)](#-cache-layer-new)
  - [✅ Application Layer (New!)](#-application-layer-new)
- [Continuous Testing](#continuous-testing)
- [Test Philosophy](#test-philosophy)
  - [External Client Testing](#external-client-testing)
  - [Why This Matters](#why-this-matters)
- [Troubleshooting](#troubleshooting)
  - [Test Failures](#test-failures)
  - [Dependencies Missing](#dependencies-missing)
- [Contributing Tests](#contributing-tests)
  - [Test Template](#test-template)
- [Documentation](#documentation)
- [Summary](#summary)

---

Comprehensive test coverage for all infrastructure components and applications.

## Quick Start

```bash
# Run all tests (auto-detects running services)
./tests/run-all-tests.sh

# Run specific test suite
./tests/test-fastapi.sh
./tests/test-redis-cluster.sh

# Run tests with specific profile
./devstack start --profile full
./tests/run-all-tests.sh  # Runs all available tests

# Run tests with minimal profile
./devstack start --profile minimal
./tests/run-all-tests.sh  # Skips observability and reference API tests
```

## Test Suites

### Infrastructure Tests
- **`test-vault.sh`** - Vault PKI, secrets management, auto-unseal (10 tests)

### Database Tests
- **`test-postgres.sh`** - PostgreSQL with Vault integration
- **`test-mysql.sh`** - MySQL with Vault integration
- **`test-mongodb.sh`** - MongoDB with Vault integration

### Cache & Messaging Tests
- **`test-redis-cluster.sh`** - Redis cluster operations (12 tests)
- **`test-rabbitmq.sh`** - RabbitMQ messaging

### Application Tests
- **`test-fastapi.sh`** - FastAPI reference app with Redis Cluster APIs (14 tests)
- **`test-rust.sh`** - Rust reference app with Actix-web (7 tests)

## New Features (Latest Update)

### 1. Redis Cluster Testing (`test-redis-cluster.sh`)
Comprehensive 12-test suite validating:
- ✅ All 3 containers running and reachable
- ✅ Cluster mode enabled on all nodes
- ✅ Cluster initialization (state: ok)
- ✅ All 16384 hash slots assigned
- ✅ 3 master nodes with slot distribution
- ✅ Data sharding and automatic redirection
- ✅ Vault password integration
- ✅ Keyslot calculation

**Why it matters:**
- Ensures Redis cluster is properly initialized
- Validates complete slot coverage (100%)
- Tests real-world data operations
- Verifies Vault-managed authentication

### 2. FastAPI Application Testing (`test-fastapi.sh`)
Comprehensive 14-test suite validating:

**Container & Endpoints:**
- ✅ HTTP endpoint (port 8000)
- ✅ HTTPS endpoint (port 8443, when TLS enabled)
- ✅ Health checks return cluster information

**Redis Cluster API Tests (4 new endpoints):**
- ✅ `/redis/cluster/nodes` - All nodes with slot assignments
- ✅ `/redis/cluster/slots` - 100% slot coverage verification
- ✅ `/redis/cluster/info` - Cluster state and statistics
- ✅ `/redis/nodes/{node}/info` - Per-node detailed information

**Integration Tests:**
- ✅ Vault integration via health endpoint
- ✅ All databases (PostgreSQL, MySQL, MongoDB)
- ✅ RabbitMQ messaging
- ✅ API documentation (Swagger UI, OpenAPI schema)

**Why it matters:**
- Validates all new Redis Cluster inspection APIs
- Tests dual HTTP/HTTPS support
- Ensures all service integrations work
- Verifies API documentation generation

### 3. Enhanced Test Runner (`run-all-tests.sh`)
Updated to run all 7 test suites in organized sequence:
1. Infrastructure (Vault)
2. Databases (PostgreSQL, MySQL, MongoDB)
3. Cache (Redis Cluster)
4. Messaging (RabbitMQ)
5. Applications (FastAPI)

**Output Features:**
- Color-coded pass/fail indicators
- Real-time progress
- Comprehensive summary
- Failed test listing

## Prerequisites

### System Dependencies
```bash
# macOS
brew install jq

# Ubuntu/Debian
apt-get install jq

# curl is usually pre-installed
```

### Python Dependencies
```bash
# Install from tests directory
pip3 install -r tests/requirements.txt
```

Required packages:
- `psycopg2-binary` - PostgreSQL client

## Test Output Example

```bash
$ ./tests/test-fastapi.sh

=========================================
  FastAPI Reference App Test Suite
=========================================

[TEST] Test 1: FastAPI container is running
[PASS] FastAPI container is running

[TEST] Test 6: Redis cluster nodes API endpoint
[PASS] Redis cluster nodes API returns 3 nodes with slot assignments

[TEST] Test 7: Redis cluster slots API endpoint
[PASS] Redis cluster slots API shows 100% coverage (16384 slots)

=========================================
  Test Results
=========================================
Total tests: 14
Passed: 13

✓ All FastAPI tests passed!
```

## Running Individual Tests

### Test FastAPI and Redis Cluster APIs
```bash
./tests/test-fastapi.sh
```
Tests all new Redis Cluster inspection endpoints and service integrations.

### Test Redis Cluster Configuration
```bash
./tests/test-redis-cluster.sh
```
Tests cluster initialization, slot distribution, and data operations.

### Test All Infrastructure
```bash
./tests/run-all-tests.sh
```
Runs all 7 test suites and provides comprehensive summary.

## Test Coverage Summary

| Component | Tests | Coverage |
|-----------|-------|----------|
| Vault | 10 | PKI, secrets, certificates, auto-unseal |
| PostgreSQL | ~10 | Container, credentials, connectivity, SSL |
| MySQL | ~9 | Container, credentials, connectivity, SSL |
| MongoDB | ~10 | Container, credentials, connectivity, SSL |
| **Redis Cluster** | **12** | **Cluster config, slots, sharding, failover** |
| RabbitMQ | ~5 | Container, credentials, messaging |
| **FastAPI** | **14** | **APIs, health, cluster endpoints, integrations** |

**Total: ~70+ tests** across all components

## Profile-Aware Testing

The test suite automatically adapts to your active service profile, skipping tests for services that aren't running.

### How It Works

**Automatic Service Detection:**
- Tests check for running containers before execution
- Services not in active profile are automatically skipped
- Exit code 0 (success) even with skipped tests
- Skipped tests clearly marked in output

**Test Behavior by Profile:**

| Profile | Infrastructure Tests | Database Tests | Observability Tests | Reference API Tests | pytest Tests |
|---------|---------------------|----------------|---------------------|---------------------|--------------|
| **minimal** | ✅ Vault | ✅ PostgreSQL | ⊘ Skipped | ⊘ Skipped | ⊘ Skipped |
| **standard** | ✅ All | ✅ All | ⊘ Skipped | ⊘ Skipped | ⊘ Skipped |
| **full** | ✅ All | ✅ All | ✅ All | ⊘ Skipped | ⊘ Skipped |
| **standard + reference** | ✅ All | ✅ All | ⊘ Skipped | ✅ All | ✅ All |
| **full + reference** | ✅ All | ✅ All | ✅ All | ✅ All | ✅ All |

**Example Output:**
```bash
$ ./tests/run-all-tests.sh  # With minimal profile

Test Suites Run: 16
Passed: 12
Skipped: 4

Results by suite:
  ✓ Vault Integration
  ✓ PostgreSQL Vault Integration
  ⊘ Observability Stack Tests (skipped)
  ⊘ FastAPI Reference App (skipped)
  ⊘ FastAPI Unit Tests (pytest) (skipped)
  ⊘ API Parity Tests (pytest) (skipped)

✓ ALL TESTS PASSED!
  (4 suite(s) skipped)
```

### Skip vs Fail

**Understanding Test States:**

- **PASSED (✓):** All tests in suite completed successfully
- **FAILED (✗):** One or more tests failed (exit code 1)
- **SKIPPED (⊘):** Service not running, tests not executed (exit code 0)

**Key Difference:**
- ❌ **Failure:** Indicates a bug or misconfiguration that needs fixing
- ⊘ **Skip:** Expected behavior when service isn't in active profile

### Running Full Test Suite

To run **all tests** without skips:

```bash
# Start with full + reference profiles
./devstack start --profile full --profile reference

# Run complete test suite (all 16 test suites)
./tests/run-all-tests.sh
# Expected: 16/16 passed, 0 skipped
```

### Troubleshooting Skipped Tests

**If tests are unexpectedly skipped:**

```bash
# 1. Check running containers
docker ps --format "table {{.Name}}\t{{.Status}}"

# 2. Verify profile services started
./devstack status

# 3. Start missing services
./devstack start --profile full --profile reference

# 4. Re-run tests
./tests/run-all-tests.sh
```

## What Gets Validated

### ✅ Infrastructure
- Vault PKI and secrets management
- Auto-unseal functionality
- Certificate issuance for all services

### ✅ Data Layer
- Database containers running
- Vault credential integration
- Real client connectivity (not docker exec)
- SSL/TLS when enabled

### ✅ Cache Layer (New!)
- Redis cluster initialization
- Complete slot coverage (16384 slots)
- Data sharding across nodes
- Automatic redirection

### ✅ Application Layer (New!)
- HTTP/HTTPS dual-mode operation
- Redis Cluster inspection APIs
- Health checks with cluster details
- All service integrations
- API documentation generation

## Continuous Testing

Run tests after:
- ✅ Initial setup (`./devstack start`)
- ✅ Configuration changes
- ✅ Certificate regeneration
- ✅ Service restarts
- ✅ Application deployments
- ✅ Vault bootstrap operations

## Test Philosophy

### External Client Testing
All tests use **real external clients**, not `docker exec`:
- ✅ Tests actual network stack
- ✅ Validates SSL/TLS properly
- ✅ Catches firewall/routing issues
- ✅ Verifies encryption
- ✅ Production-like testing

### Why This Matters
Using `docker exec` bypasses the network and can't validate:
- ❌ Certificate validation
- ❌ Network routing
- ❌ SSL/TLS encryption
- ❌ Connection security

Our tests connect from **outside the container** like real applications would.

## Troubleshooting

### Test Failures

**Redis Cluster Tests Fail:**
```bash
# Reinitialize cluster
./configs/redis/scripts/redis-cluster-init.sh

# Verify cluster state
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD CLUSTER INFO
```

**FastAPI Tests Fail:**
```bash
# Check container logs
docker logs dev-reference-api

# Verify container is running
docker ps | grep reference-api

# Test endpoints manually
curl http://localhost:8000/health/all
```

**Database Tests Fail:**
```bash
# Check Vault credentials
./devstack vault-show-password postgres

# Check container health
docker ps
```

### Dependencies Missing

**jq not found:**
```bash
# macOS
brew install jq

# Ubuntu
sudo apt-get install jq
```

**Python library errors:**
```bash
pip3 install -r tests/requirements.txt
```

## Contributing Tests

When adding new infrastructure or features:

1. Create test file: `tests/test-{component}.sh`
2. Follow existing test patterns (see `test-fastapi.sh`)
3. Add to `run-all-tests.sh`
4. Update `TEST_COVERAGE.md`
5. Test with: `./tests/test-{component}.sh`

### Test Template
```bash
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

info() { echo "[TEST] $1"; }
success() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

test_example() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: Description"

    # Your test logic here

    success "Test passed"
}

# Run tests
test_example

# Summary
if [ $TESTS_FAILED -eq 0 ]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
```

## Documentation

- **`TEST_COVERAGE.md`** - Detailed test coverage documentation
- **`README.md`** - This file (quick start guide)
- **`requirements.txt`** - Python and system dependencies

## Summary

The test suite provides **comprehensive validation** of:
- ✅ Infrastructure security (Vault, PKI, secrets)
- ✅ Database integration (PostgreSQL, MySQL, MongoDB)
- ✅ **Redis Cluster** (initialization, slots, sharding)
- ✅ Messaging (RabbitMQ)
- ✅ **FastAPI application** (APIs, health, integrations)
- ✅ **Redis Cluster APIs** (nodes, slots, info, per-node)

**Run with:** `./tests/run-all-tests.sh`
