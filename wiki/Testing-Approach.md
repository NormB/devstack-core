# Testing Approach - Best Practices

## Table of Contents

- [Overview](#overview)
- [Test Architecture](#test-architecture)
  - [Total Test Count: 431 Tests (355 run, 76 skipped)](#total-test-count-431-tests-355-run-76-skipped)
- [Best Approach (Implemented in `run-all-tests.sh`)](#best-approach-implemented-in-run-all-testssh)
  - [1. Bash Integration Tests](#1-bash-integration-tests)
  - [2. Python Unit Tests (FastAPI)](#2-python-unit-tests-fastapi)
  - [3. Python Parity Tests](#3-python-parity-tests)
- [Running All Tests](#running-all-tests)
  - [Simple (Recommended)](#simple-recommended)
  - [Manual Container Startup (Faster)](#manual-container-startup-faster)
- [Prerequisites](#prerequisites)
  - [Required Tools](#required-tools)
  - [Required Containers](#required-containers)
- [Test Execution Details](#test-execution-details)
  - [Unit Tests (Inside Container)](#unit-tests-inside-container)
  - [Parity Tests (From Host with uv)](#parity-tests-from-host-with-uv)
- [Troubleshooting](#troubleshooting)
  - [Container Not Running](#container-not-running)
  - [uv Not Found](#uv-not-found)
  - [Tests Fail](#tests-fail)
- [Why Not Other Approaches?](#why-not-other-approaches)
  - [Why not run everything in containers?](#why-not-run-everything-in-containers)
  - [Why not run everything locally with uv?](#why-not-run-everything-locally-with-uv)
  - [Why not use virtualenv or pip directly?](#why-not-use-virtualenv-or-pip-directly)
- [Success Metrics](#success-metrics)
- [Integration with CI/CD](#integration-with-cicd)
- [Summary](#summary)

---

## Overview

This document explains the **best practices** for running the 571+ tests in the devstack-core repository (95.2% of 600-test goal).

## Test Architecture

### Total Test Count: 571+ Tests (495+ run, 76 skipped)

1. **Bash Integration Tests** (20 suites, 244+ tests)
   - Infrastructure, databases, cache, messaging, applications, backup system
   - Performance regression, AppRole security, Redis failover, TLS, load testing
   - Run directly on host using bash scripts

2. **Python Unit Tests** (pytest, 254 tests: 178 passed + 76 skipped)
   - FastAPI application unit tests
   - Run **inside Docker container**
   - **84.39% code coverage** (exceeds 80% target)

3. **Python Parity Tests** (pytest, 64 tests from 38 unique test functions)
   - API implementation comparison tests
   - Run **from host with uv**
   - Some tests parametrized to run against both APIs

## Best Approach (Implemented in `run-all-tests.sh`)

### 1. Bash Integration Tests
**Method:** Direct execution on host
```bash
./tests/test-vault.sh
./tests/test-postgres.sh
./tests/test-approle-auth.sh
./tests/test-backup-encryption.sh
# ... etc
```

**Why:** These tests interact with Docker containers from outside, testing real service integration.

**Test Suites:**
- **Infrastructure:** test-vault.sh (10 tests), test-approle-auth.sh (15 tests)
- **Databases:** test-postgres.sh, test-mysql.sh, test-mongodb.sh
- **Cache & Messaging:** test-redis-cluster.sh (12 tests), test-rabbitmq.sh
- **Applications:** test-fastapi.sh (14 tests)
- **Backup System (Task 2.1):**
  - test-incremental-backup.sh (12 tests) - Manifest tracking, checksums
  - test-backup-encryption.sh (12 tests) - GPG/AES256 encryption
  - test-backup-verification.sh (12 tests) - Integrity verification
  - test-backup-restore.sh (12 tests) - Full restore workflow
- **Phase 3 Tests (November 2025):**
  - **test-performance-regression.sh** (4 tests) - Database and cache performance benchmarks
    - PostgreSQL: 8,162 TPS (target: ≥5,000)
    - MySQL: 20,449 rows/sec (target: ≥10,000)
    - MongoDB: 106,382 docs/sec (target: ≥50,000)
    - Redis: 86,956 ops/sec (target: ≥30,000)
  - **test-approle-security.sh** (21 tests) - AppRole authentication and policy enforcement
    - Invalid credentials rejected
    - Service-specific policy validation (7 services)
    - Token TTL and renewability
    - Cross-service access prevention
  - **test-redis-failover.sh** (16 tests) - Redis cluster resilience
    - Cluster health validation
    - Master failover scenarios
    - Data persistence across failovers
    - Recovery time: <3 seconds
  - **test-tls-connections.sh** (24 tests, 29% validated) - TLS dual-mode support
    - Certificate validation
    - Service-specific TLS configuration
    - Dual-mode acceptance (TLS and non-TLS)
  - **test-load.sh** (7 tests, deferred) - System behavior under load
    - Sustained, spike, and ramp load scenarios
    - Database connection pool testing
    - Cache performance under load
    - Resource utilization monitoring

**Total:** 176+ integration tests across 20 suites

**Phase 3 Test Validation Status:**
- ✅ test-performance-regression.sh: 4/4 passing (100%)
- ✅ test-approle-security.sh: 21/21 passing (100%)
- ✅ test-redis-failover.sh: 16/16 passing (100%)
- ⚠️ test-tls-connections.sh: 7/24 validated (29%, infrastructure gap)
- ⏸️ test-load.sh: Deferred (resource-intensive, 3-5 min runtime)

See [Phase 3 Test Validation Report](../tests/PHASE_3_TEST_VALIDATION.md) for comprehensive details.

See [Task 2.1 Testing Documentation](../docs/.private/TASK_2.1_TESTING.md) for comprehensive backup system test details.

### 2. Python Unit Tests (FastAPI)
**Method:** Execute inside Docker container
```bash
docker exec dev-reference-api pytest tests/ -v
```

**Why this is the BEST approach:**
- ✅ **Correct Python version** (3.11) - avoids Python 3.14 compatibility issues
- ✅ **All dependencies pre-installed** - no local environment setup needed
- ✅ **Production-like environment** - tests run in same env as production code
- ✅ **No native extension build issues** - asyncpg, etc. already compiled
- ✅ **Consistent across developers** - everyone uses same container image

**Alternatives rejected:**
- ❌ Local Python 3.14: asyncpg build fails with C compilation errors
- ❌ Local venv: Requires manual dependency management, version conflicts

### 3. Python Parity Tests
**Method:** Run from host using `uv`
```bash
cd reference-apps/shared/test-suite
uv venv && uv pip install -r requirements.txt && uv run pytest -v
```

**Why this is the BEST approach:**
- ✅ **Must access both APIs via localhost** - localhost:8000 and localhost:8001
- ✅ **Client perspective testing** - tests as external client would use APIs
- ✅ **Lightweight dependencies** - only httpx, pytest (no heavy native extensions)
- ✅ **uv handles environment** - automatic venv creation and dependency management

**Alternatives rejected:**
- ❌ Inside container: Would need container networking, can't access localhost ports
- ❌ Local Python 3.14 directly: Works but uv provides better isolation

## Running All Tests

### Simple (Recommended)
```bash
# Auto-starts required containers and runs all 494 tests
./tests/run-all-tests.sh
```

The script:
1. Checks if containers are running
2. Auto-starts them if needed (`docker compose up -d`)
3. Runs bash tests (176 tests across 15 suites)
4. Runs pytest in container (254 tests: 178 passed + 76 skipped)
5. Runs parity tests with uv (64 tests)
6. Shows comprehensive summary

**Run individual test categories:**
```bash
# Infrastructure tests only
./tests/test-vault.sh
./tests/test-approle-auth.sh

# Backup system tests only (Task 2.1)
./tests/test-incremental-backup.sh
./tests/test-backup-encryption.sh
./tests/test-backup-verification.sh
./tests/test-backup-restore.sh

# All backup tests
for test in tests/test-{incremental-backup,backup-encryption,backup-verification,backup-restore,approle-auth}.sh; do
    $test
done
```

### Manual Container Startup (Faster)
```bash
# Pre-start containers
docker compose up -d reference-api api-first

# Run tests
./tests/run-all-tests.sh
```

## Prerequisites

### Required Tools
1. **Docker + Docker Compose** (for all services)
   ```bash
   docker --version
   docker compose version
   ```

2. **uv** (Python package manager)
   ```bash
   # Install
   curl -LsSf https://astral.sh/uv/install.sh | sh
   # or
   brew install uv

   # Verify
   uv --version
   ```

3. **bash** (>= 3.2)

### Required Containers
- `dev-reference-api` - FastAPI code-first implementation
- `dev-api-first` - FastAPI API-first implementation
- All infrastructure containers (vault, postgres, redis, etc.)

## Test Execution Details

### Unit Tests (Inside Container)
```bash
# The script runs this command:
docker exec dev-reference-api pytest tests/ -v --tb=short

# Output:
# ================= 178 passed, 76 skipped, 6 warnings in 1.28s ==================
# Coverage: 84.39% (exceeds 80% requirement)
```

**What runs:**
- Service unit tests (vault, cache, database)
- Router unit tests (health, vault, cache, database, messaging, redis)
- Exception handler tests
- Request validator tests
- Middleware tests (caching, circuit breaker, rate limiting)
- CORS tests

### Parity Tests (From Host with uv)
```bash
# The script runs this:
cd reference-apps/shared/test-suite
uv venv --quiet
uv pip install -r requirements.txt
uv run pytest -v

# Output:
# ============================== 26 passed in 0.35s ===============================
```

**What runs:**
- Root endpoint parity
- OpenAPI spec matching
- Vault endpoint parity
- Cache endpoint parity
- Metrics format matching
- Error handling parity
- Health check parity

## Troubleshooting

### Container Not Running
```bash
# Error: "dev-reference-api container not running"
# Solution: Script auto-starts it, or manually:
docker compose up -d reference-api
```

### uv Not Found
```bash
# Error: "uv not found - required for parity tests"
# Solution:
curl -LsSf https://astral.sh/uv/install.sh | sh
# or
brew install uv
```

### Tests Fail
```bash
# Check service health first
./devstack.sh health

# Check specific container logs
docker logs dev-reference-api

# Restart infrastructure
./devstack.sh restart
```

## Why Not Other Approaches?

### Why not run everything in containers?
- Parity tests need to access localhost:8000 and localhost:8001
- Running from inside container would require complex networking setup
- Client-perspective testing requires external access

### Why not run everything locally with uv?
- Python 3.14 has compatibility issues with asyncpg (C extension build failures)
- Would require matching exact Python version (3.11) locally
- Defeats purpose of containerization
- Inconsistent across developer environments

### Why not use virtualenv or pip directly?
- uv is faster and handles dependency resolution better
- uv creates isolated environments automatically
- uv is the modern standard for Python package management
- No manual venv creation/activation needed

## Success Metrics

All tests passing produces this output:
```
Test Suites Run: 12
Passed: 12

Results by suite:
  ✓ Vault Integration
  ✓ PostgreSQL Vault Integration
  ✓ MySQL Vault Integration
  ✓ MongoDB Vault Integration
  ✓ Redis Vault Integration
  ✓ Redis Cluster
  ✓ RabbitMQ Integration
  ✓ FastAPI Reference App
  ✓ Performance & Load Testing
  ✓ Negative Testing & Error Handling
  ✓ FastAPI Unit Tests (pytest)
  ✓ API Parity Tests (pytest)

✓ ALL TESTS PASSED!
```

## Integration with CI/CD

The same approach works in CI/CD:
```yaml
# GitHub Actions example
- name: Run all tests
  run: |
    docker compose up -d reference-api api-first
    ./tests/run-all-tests.sh
```

## Summary

**Best approach is a hybrid:**
- **Bash tests:** Direct host execution ✓
- **Unit tests:** Inside Docker containers ✓
- **Parity tests:** From host with uv ✓

This provides:
- Maximum compatibility (no Python version issues)
- Minimum setup (auto-starts containers, uv manages deps)
- Maximum reliability (production-like environment)
- Maximum clarity (each test type uses optimal approach)
