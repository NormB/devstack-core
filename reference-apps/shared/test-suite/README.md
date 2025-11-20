# Shared Test Suite

## Table of Contents

- [Overview](#overview)
- [Test Categories](#test-categories)
  - [1. **Parity Tests** (`@pytest.mark.parity`)](#1-parity-tests-pytestmarkparity)
  - [2. **Comparison Tests** (`@pytest.mark.comparison`)](#2-comparison-tests-pytestmarkcomparison)
- [Prerequisites](#prerequisites)
  - [1. Start Both APIs](#1-start-both-apis)
  - [2. Verify APIs Are Running](#2-verify-apis-are-running)
- [Running Tests](#running-tests)
  - [Install Dependencies](#install-dependencies)
  - [Run All Tests](#run-all-tests)
  - [Run Specific Test Categories](#run-specific-test-categories)
  - [Run Tests for Single Implementation](#run-tests-for-single-implementation)
- [Environment Variables](#environment-variables)
- [Test Files](#test-files)
- [Expected Results](#expected-results)
  - [Example Output](#example-output)
- [Troubleshooting](#troubleshooting)
  - [APIs Not Running](#apis-not-running)
  - [Tests Failing Due to Response Differences](#tests-failing-due-to-response-differences)
  - [Port Already in Use](#port-already-in-use)
- [CI/CD Integration](#cicd-integration)
- [Contributing](#contributing)
- [Success Criteria](#success-criteria)

---

**Purpose:** Validate that both API implementations (code-first and API-first) behave identically.

## Overview

This test suite ensures **API contract compliance** by running the same tests against both implementations:

- **Code-First API** (`localhost:8000`) - FastAPI implementation
- **API-First API** (`localhost:8001`) - Generated from OpenAPI spec

## Test Categories

### 1. **Parity Tests** (`@pytest.mark.parity`)
Tests that run against **both** implementations using parametrized fixtures.

**Example:**
```python
async def test_health_check(self, api_url, http_client):
    # Runs twice: once for each API
    response = await http_client.get(f"{api_url}/health/")
    assert response.status_code == 200
```

### 2. **Comparison Tests** (`@pytest.mark.comparison`)
Tests that **directly compare** responses from both APIs to ensure identical behavior.

**Example:**
```python
async def test_responses_match(self, both_api_urls, http_client):
    code_first = await http_client.get(f"{both_api_urls['code-first']}/health/")
    api_first = await http_client.get(f"{both_api_urls['api-first']}/health/")
    assert code_first.json() == api_first.json()
```

## Prerequisites

### 1. Start Both APIs

**Terminal 1 - Code-First:**
```bash
cd reference-apps
make start-code-first
# Or: docker compose up dev-reference-api
```

**Terminal 2 - API-First:**
```bash
cd reference-apps
make start-api-first
# Or: docker compose up dev-api-first-app
```

### 2. Verify APIs Are Running

```bash
curl http://localhost:8000/health/
curl http://localhost:8001/health/
```

## Running Tests

### Install Dependencies

```bash
cd reference-apps/shared/test-suite
pip install -r requirements.txt
```

### Run All Tests

```bash
pytest -v
```

### Run Specific Test Categories

```bash
# Health checks only
pytest -v -m health

# Parity tests only
pytest -v -m parity

# Comparison tests only
pytest -v -m comparison
```

### Run Tests for Single Implementation

```bash
# Test code-first only
CODE_FIRST_API_URL=http://localhost:8000 pytest -v

# Test API-first only
API_FIRST_API_URL=http://localhost:8001 pytest -v
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CODE_FIRST_API_URL` | `http://localhost:8000` | Code-first API base URL |
| `API_FIRST_API_URL` | `http://localhost:8001` | API-first API base URL |

## Test Files

| File | Purpose |
|------|---------|
| `conftest.py` | Pytest configuration and fixtures |
| `pytest.ini` | Pytest settings |
| `test_health_checks.py` | Health endpoint validation |
| `test_api_parity.py` | Comprehensive API parity tests |
| `requirements.txt` | Python dependencies |

## Expected Results

**All tests should pass** when both implementations are running and properly synchronized.

### Example Output

```
test_health_checks.py::TestHealthEndpoints::test_simple_health_check[code-first] PASSED
test_health_checks.py::TestHealthEndpoints::test_simple_health_check[api-first] PASSED
test_health_checks.py::TestHealthParity::test_health_responses_match PASSED
test_api_parity.py::TestRootEndpoint::test_root_endpoint_returns_info[code-first] PASSED
test_api_parity.py::TestRootEndpoint::test_root_endpoint_returns_info[api-first] PASSED
test_api_parity.py::TestRootEndpoint::test_root_endpoint_structure_matches PASSED
...

========================== 26 passed in 2.34s ===========================
```

**Note:** The suite contains 16 test functions, but due to parametrization (tests run against both APIs), pytest executes 26 total test runs.

## Troubleshooting

### APIs Not Running

**Error:** `httpx.ConnectError: [Errno 61] Connection refused`

**Solution:** Ensure both APIs are started:
```bash
make start-code-first  # Terminal 1
make start-api-first   # Terminal 2
```

### Tests Failing Due to Response Differences

If tests fail because responses don't match:

1. **Check synchronization:**
   ```bash
   make validate-sync
   ```

2. **Review the diff:** Test output will show exact differences

3. **Sync implementations:**
   ```bash
   make sync-api-first
   ```

### Port Already in Use

**Error:** `Bind for 0.0.0.0:8000 failed: port is already allocated`

**Solution:**
```bash
# Stop existing containers
docker compose down

# Start fresh
make start-code-first
make start-api-first
```

## CI/CD Integration

This test suite can be integrated into GitHub Actions:

```yaml
- name: Run Shared Test Suite
  run: |
    # Start both APIs
    docker compose up -d dev-reference-api dev-api-first-app

    # Wait for health checks
    sleep 10

    # Run tests
    cd reference-apps/shared/test-suite
    pip install -r requirements.txt
    pytest -v
```

## Contributing

See our [Contributing Guide](../../../.github/CONTRIBUTING.md) for detailed instructions on how to contribute to DevStack Core.

When adding new endpoints:

1. **Add parity test** to validate endpoint works on both implementations
2. **Add comparison test** if response must be identical
3. **Update this README** with new test categories if needed

## Success Criteria

✅ All parity tests pass for both implementations
✅ All comparison tests show identical responses
✅ Test coverage includes all shared endpoints
✅ Tests run in CI/CD pipeline
