# Test Suite Coverage

## Table of Contents

- [Overview](#overview)
- [1. Infrastructure Integration Tests (Shell Scripts)](#1-infrastructure-integration-tests-shell-scripts)
  - [1.1 Vault Integration Tests (`test-vault.sh`)](#11-vault-integration-tests-test-vaultsh)
  - [1.2 Database Integration Tests](#12-database-integration-tests)
    - [PostgreSQL (`test-postgres.sh`)](#postgresql-test-postgressh)
    - [MySQL (`test-mysql.sh`)](#mysql-test-mysqlsh)
    - [MongoDB (`test-mongodb.sh`)](#mongodb-test-mongodbsh)
  - [1.3 Redis Cluster Tests (`test-redis-cluster.sh`)](#13-redis-cluster-tests-test-redis-clustersh)
  - [1.4 RabbitMQ Integration Tests (`test-rabbitmq.sh`)](#14-rabbitmq-integration-tests-test-rabbitmqsh)
  - [1.5 FastAPI Container Tests (`test-fastapi.sh`)](#15-fastapi-container-tests-test-fastapish)
    - [Container & Endpoints](#container-endpoints)
    - [Redis Cluster API Tests](#redis-cluster-api-tests)
    - [API Documentation Tests](#api-documentation-tests)
    - [Service Integration Tests](#service-integration-tests)
- [2. FastAPI Application Tests (Pytest)](#2-fastapi-application-tests-pytest)
  - [Test Suite Overview](#test-suite-overview)
  - [2.1 Caching Tests (`test_caching.py`)](#21-caching-tests-test_cachingpy)
    - [Cache Key Generation (5 tests)](#cache-key-generation-5-tests)
    - [Cache Manager (4 tests)](#cache-manager-4-tests)
    - [Cache Invalidation (4 tests)](#cache-invalidation-4-tests)
    - [Endpoint Caching (4 tests - SKIPPED)](#endpoint-caching-4-tests-skipped)
    - [Cache Configuration & Metrics (6 tests)](#cache-configuration-metrics-6-tests)
  - [2.2 Cache Demo Unit Tests (`test_cache_demo_unit.py`)](#22-cache-demo-unit-tests-test_cache_demo_unitpy)
  - [2.3 Circuit Breaker Tests (`test_circuit_breaker.py`)](#23-circuit-breaker-tests-test_circuit_breakerpy)
    - [Event Listeners (4 tests)](#event-listeners-4-tests)
    - [Metrics (2 tests)](#metrics-2-tests)
    - [Behavior (3 tests)](#behavior-3-tests)
    - [Integration (1 test)](#integration-1-test)
  - [2.4 CORS Tests (`test_cors.py`)](#24-cors-tests-test_corspy)
    - [Headers (2 tests)](#headers-2-tests)
    - [Preflight Requests (4 tests)](#preflight-requests-4-tests)
    - [Methods & Origins (5 tests)](#methods-origins-5-tests)
    - [Integration (2 tests)](#integration-2-tests)
  - [2.5 Database Demo Tests (`test_database_demo.py`)](#25-database-demo-tests-test_database_demopy)
    - [PostgreSQL (3 tests)](#postgresql-3-tests)
    - [MySQL (3 tests)](#mysql-3-tests)
    - [MongoDB (3 tests)](#mongodb-3-tests)
  - [2.6 Exception Handler Tests (`test_exception_handlers.py` + `test_exception_handlers_unit.py`)](#26-exception-handler-tests-test_exception_handlerspy-test_exception_handlers_unitpy)
    - [Exception Handlers (12 tests)](#exception-handlers-12-tests)
    - [Unit Tests (23 tests)](#unit-tests-23-tests)
  - [2.7 Exception Hierarchy Tests (`test_exceptions.py`)](#27-exception-hierarchy-tests-test_exceptionspy)
    - [Exception Creation (9 tests)](#exception-creation-9-tests)
    - [Exception Hierarchy (5 tests)](#exception-hierarchy-5-tests)
    - [Exception Helpers (6 tests)](#exception-helpers-6-tests)
  - [2.8 Health Router Tests (`test_health_routers.py`)](#28-health-router-tests-test_health_routerspy)
    - [Individual Service Health (6 tests - SKIPPED)](#individual-service-health-6-tests-skipped)
    - [Aggregated Health (12 tests)](#aggregated-health-12-tests)
  - [2.9 Rate Limiting Tests (`test_rate_limiting.py`)](#29-rate-limiting-tests-test_rate_limitingpy)
  - [2.10 Redis Cluster Tests (`test_redis_cluster.py`)](#210-redis-cluster-tests-test_redis_clusterpy)
    - [Cluster Operations (10 tests - SKIPPED)](#cluster-operations-10-tests-skipped)
    - [Unit Tests (5 tests)](#unit-tests-5-tests)
  - [2.11 Request Validation Tests (`test_request_validation.py`)](#211-request-validation-tests-test_request_validationpy)
    - [Path Parameters (6 tests)](#path-parameters-6-tests)
    - [Input Sanitization (4 tests)](#input-sanitization-4-tests)
    - [Content Type (3 tests)](#content-type-3-tests)
    - [Query Parameters (2 tests)](#query-parameters-2-tests)
  - [2.12 Request Validators Tests (`test_request_validators.py`)](#212-request-validators-tests-test_request_validatorspy)
  - [2.13 Router Unit Tests (`test_routers_unit.py`)](#213-router-unit-tests-test_routers_unitpy)
    - [Cache Demo Routers (11 tests)](#cache-demo-routers-11-tests)
    - [Vault Demo Routers (2 tests - SKIPPED)](#vault-demo-routers-2-tests-skipped)
    - [Database Routers (3 tests)](#database-routers-3-tests)
    - [Messaging Routers (3 tests - 2 SKIPPED)](#messaging-routers-3-tests-2-skipped)
    - [Redis Cluster Routers (4 tests)](#redis-cluster-routers-4-tests)
  - [2.14 Vault Service Tests (`test_vault_service.py`)](#214-vault-service-tests-test_vault_servicepy)
    - [Secret Retrieval (9 tests)](#secret-retrieval-9-tests)
    - [Health Checks (5 tests)](#health-checks-5-tests)
    - [Integration Flows (3 tests)](#integration-flows-3-tests)
- [3. Shared Test Suite (API Parity Tests)](#3-shared-test-suite-api-parity-tests)
  - [3.1 Test Categories](#31-test-categories)
    - [Parity Tests (`@pytest.mark.parity`)](#parity-tests-pytestmarkparity)
    - [Comparison Tests (`@pytest.mark.comparison`)](#comparison-tests-pytestmarkcomparison)
  - [3.2 Health Check Tests (`test_health_checks.py`)](#32-health-check-tests-test_health_checkspy)
    - [Parity Tests (6 test runs from 3 functions)](#parity-tests-6-test-runs-from-3-functions)
    - [Comparison Tests (1 test run)](#comparison-tests-1-test-run)
  - [3.3 API Parity Tests (`test_api_parity.py`)](#33-api-parity-tests-test_api_paritypy)
    - [Root Endpoint Tests (3 test runs)](#root-endpoint-tests-3-test-runs)
    - [OpenAPI Spec Tests (5 test runs)](#openapi-spec-tests-5-test-runs)
    - [Vault Endpoints Tests (2 test runs)](#vault-endpoints-tests-2-test-runs)
    - [Cache Endpoints Tests (3 test runs)](#cache-endpoints-tests-3-test-runs)
    - [Metrics Endpoint Tests (3 test runs)](#metrics-endpoint-tests-3-test-runs)
    - [Error Handling Tests (3 test runs)](#error-handling-tests-3-test-runs)
  - [3.4 Test Infrastructure](#34-test-infrastructure)
    - [Fixtures (`conftest.py`)](#fixtures-conftestpy)
    - [Configuration (`pytest.ini`)](#configuration-pytestini)
  - [3.5 Coverage Areas](#35-coverage-areas)
  - [3.6 Running Shared Test Suite](#36-running-shared-test-suite)
    - [Prerequisites](#prerequisites)
    - [Run Tests](#run-tests)
    - [Expected Results](#expected-results)
    - [Run Specific Categories](#run-specific-categories)
  - [3.7 What Gets Validated](#37-what-gets-validated)
  - [3.8 Success Criteria](#38-success-criteria)
  - [3.9 Maintenance](#39-maintenance)
- [Running Tests](#running-tests)
  - [Infrastructure Tests (Shell Scripts)](#infrastructure-tests-shell-scripts)
    - [Run All Infrastructure Tests](#run-all-infrastructure-tests)
    - [Run Individual Test Suites](#run-individual-test-suites)
  - [FastAPI Application Tests (Pytest)](#fastapi-application-tests-pytest)
    - [Run All Tests](#run-all-tests)
    - [Run with Coverage](#run-with-coverage)
    - [Run Specific Test File](#run-specific-test-file)
    - [Run Specific Test](#run-specific-test)
    - [Run Only Unit Tests](#run-only-unit-tests)
    - [Run Only Integration Tests](#run-only-integration-tests)
- [Test Dependencies](#test-dependencies)
  - [System Tools (Infrastructure Tests)](#system-tools-infrastructure-tests)
  - [Python Dependencies (Application Tests)](#python-dependencies-application-tests)
- [Test Results Format](#test-results-format)
  - [Infrastructure Tests Output](#infrastructure-tests-output)
  - [Pytest Output](#pytest-output)
- [Coverage Summary](#coverage-summary)
  - [Infrastructure Tests (Shell Scripts)](#infrastructure-tests-shell-scripts)
  - [Application Tests (Pytest)](#application-tests-pytest)
  - [Shared Test Suite (Pytest)](#shared-test-suite-pytest)
- [4. Go Reference API](#4-go-reference-api)
  - [4.1 Implementation Features](#41-implementation-features)
    - [Core Capabilities](#core-capabilities)
    - [Go-Specific Features](#go-specific-features)
  - [4.2 API Endpoints](#42-api-endpoints)
    - [Available Endpoints](#available-endpoints)
  - [4.3 Manual Testing Results](#43-manual-testing-results)
    - [✅ Verified Working Endpoints](#-verified-working-endpoints)
    - [Expected Behavior - Vault Secrets Not Bootstrapped](#expected-behavior---vault-secrets-not-bootstrapped)
  - [4.4 Architecture Highlights](#44-architecture-highlights)
    - [Project Structure](#project-structure)
    - [Key Design Patterns](#key-design-patterns)
  - [4.5 Comparison with Python Implementation](#45-comparison-with-python-implementation)
  - [4.6 Testing Status](#46-testing-status)
    - [✅ Completed](#-completed)
    - [🔄 Requires Infrastructure Bootstrap](#-requires-infrastructure-bootstrap)
  - [4.9 Automated Test Suite](#49-automated-test-suite)
    - [Test Files Created](#test-files-created)
    - [Test Coverage by Package](#test-coverage-by-package)
    - [Test Execution](#test-execution)
    - [Test Patterns Used](#test-patterns-used)
    - [📝 Future Testing Enhancements](#-future-testing-enhancements)
  - [4.7 Running the Go API](#47-running-the-go-api)
    - [Start Service](#start-service)
    - [Test Endpoints](#test-endpoints)
  - [4.8 Dependencies](#48-dependencies)
- [Total Test Coverage](#total-test-coverage)
- [Continuous Testing](#continuous-testing)
- [Test Quality Metrics](#test-quality-metrics)
  - [Infrastructure Tests](#infrastructure-tests)
  - [Application Tests](#application-tests)
- [CI/CD Considerations](#cicd-considerations)
  - [Recommended CI Pipeline](#recommended-ci-pipeline)
  - [Test Environments](#test-environments)
- [Future Test Improvements](#future-test-improvements)
- [Documentation](#documentation)

---

This document describes the comprehensive test coverage for the DevStack Core infrastructure and reference applications.

## Overview

The DevStack Core project has four distinct test suites and implementations:
1. **Infrastructure Tests** (Shell scripts) - Test Docker containers, services, and integration
2. **FastAPI Application Tests** (Pytest) - Test Python FastAPI reference application code
3. **Shared Test Suite** (Pytest) - Validate code-first and API-first implementation parity
4. **Go Reference API** (Manual testing + planned automated tests) - Go implementation with Gin framework

**Total Coverage:** 330+ tests across all components, plus Go manual validation

---

## 1. Infrastructure Integration Tests (Shell Scripts)

### 1.1 Vault Integration Tests (`test-vault.sh`)
**10 tests** - Core infrastructure security and certificate management

- Vault container running
- Vault auto-unseal functionality
- Vault keys and token file existence
- PKI bootstrap (Root CA, Intermediate CA)
- Certificate roles for all services
- Service credentials stored in Vault
- PostgreSQL credentials validation
- Certificate issuance functionality
- CA certificate export
- Management script commands

**What it validates:**
- HashiCorp Vault operational
- PKI infrastructure properly configured
- Auto-unseal working correctly
- All service credentials stored
- Certificate issuance functional

---

### 1.2 Database Integration Tests

#### PostgreSQL (`test-postgres.sh`)
**~5 tests** - PostgreSQL container, Vault credential integration, connectivity

- Container health and running state
- Vault credentials retrieval
- Database connectivity with Vault credentials
- PostgreSQL version query
- Configuration validation

#### MySQL (`test-mysql.sh`)
**~5 tests** - MySQL container, Vault credential integration, connectivity

- Container health and running state
- Vault credentials retrieval
- Database connectivity with Vault credentials
- MySQL version query
- Configuration validation

#### MongoDB (`test-mongodb.sh`)
**~5 tests** - MongoDB container, Vault credential integration, connectivity

- Container health and running state
- Vault credentials retrieval
- Database connectivity with Vault credentials
- MongoDB version query
- Configuration validation

---

### 1.3 Redis Cluster Tests (`test-redis-cluster.sh`)
**12 tests** - Comprehensive cluster configuration and operations

- All 3 Redis containers running
- Node reachability (PING test)
- Cluster mode enabled on all nodes
- Cluster initialization state (OK)
- All 16384 hash slots assigned
- 3 master nodes present
- Slot distribution across masters
- Data sharding functionality
- Automatic redirection with `-c` flag
- Vault password integration
- Comprehensive cluster health check
- Keyslot calculation

**What it validates:**
- Proper cluster initialization
- Complete slot coverage (16384 slots)
- Data distribution and retrieval
- Cross-node operations
- Vault-managed authentication
- Master-replica topology

---

### 1.4 RabbitMQ Integration Tests (`test-rabbitmq.sh`)
**~5 tests** - RabbitMQ container, Vault credential integration, messaging functionality

- Container health and running state
- Vault credentials retrieval
- RabbitMQ connectivity
- Queue creation and messaging
- Management interface accessibility

---

### 1.5 FastAPI Container Tests (`test-fastapi.sh`)
**14 tests** - Container deployment and API endpoint testing

#### Container & Endpoints
1. FastAPI container running
2. HTTP endpoint accessible (port 8000)
3. HTTPS endpoint accessible when TLS enabled (port 8443)
4. Health check endpoint (`/health/all`)

#### Redis Cluster API Tests
5. Redis health check with cluster details
   - Validates `cluster_enabled: true`
   - Validates `cluster_state: ok`
   - Validates `total_nodes: 3`

6. Redis cluster nodes API (`/redis/cluster/nodes`)
   - Returns all 3 nodes
   - All nodes have slot assignments
   - Node IDs, roles, and slot ranges present

7. Redis cluster slots API (`/redis/cluster/slots`)
   - 16384 total slots
   - 100% coverage
   - Slot distribution across masters

8. Redis cluster info API (`/redis/cluster/info`)
   - Cluster state: ok
   - All slots assigned
   - Cluster statistics present

9. Per-node info API (`/redis/nodes/{node_name}/info`)
   - Detailed node information
   - Redis version present
   - Cluster enabled flag correct

#### API Documentation Tests
10. Swagger UI accessible (`/docs`)
11. OpenAPI schema valid and accessible (`/openapi.json`)

#### Service Integration Tests
12. Vault integration (health check)
13. Database connectivity (PostgreSQL, MySQL, MongoDB)
14. RabbitMQ integration

**What it validates:**
- All Redis Cluster inspection APIs work correctly
- Dual HTTP/HTTPS support
- Health checks return cluster information
- All service integrations functional
- API documentation generated correctly

---

## 2. FastAPI Application Tests (Pytest)

### Test Suite Overview

**Location:** `reference-apps/fastapi/tests/`

**Total Tests:** 254 tests
- **Executed:** 178 unit tests (100% pass rate)
- **Skipped:** 76 integration tests (require full infrastructure)

**Code Coverage:** 84.39% (exceeds 80% requirement)

**Test Framework:** pytest with async support, mocking, and coverage reporting

---

### 2.1 Caching Tests (`test_caching.py`)
**23 tests** - Cache middleware and operations

#### Cache Key Generation (5 tests)
- Basic cache key generation with function name and path params
- Cache keys with query parameters (sorted for consistency)
- Namespace prefixes for cache organization
- Long key hashing (>200 chars → MD5 hash)
- Cache key consistency across requests

#### Cache Manager (4 tests)
- Redis connection initialization
- Graceful failure handling when Redis unavailable
- Connection cleanup on shutdown
- Clear all cache entries functionality

#### Cache Invalidation (4 tests)
- Pattern-based cache invalidation (wildcards)
- No-match pattern handling
- Specific key invalidation
- Non-existent key handling

#### Endpoint Caching (4 tests - SKIPPED)
- Cache consistency across requests
- Backend call reduction verification
- Different params = different cache keys
- Health endpoint caching behavior

#### Cache Configuration & Metrics (6 tests)
- TTL configuration (5min for Vault, 30s for health)
- Cache expiration behavior
- Prometheus metrics (hits/misses/invalidations)
- Redis client operations (get/set/delete)

---

### 2.2 Cache Demo Unit Tests (`test_cache_demo_unit.py`)
**11 tests** - Cache router operations

- Get existing value from cache
- Get nonexistent value (returns null)
- Get value with no expiration
- Set value without TTL
- Set value with TTL
- Delete existing key
- Delete nonexistent key
- Redis connection error handling
- Get Redis client initialization

---

### 2.3 Circuit Breaker Tests (`test_circuit_breaker.py`)
**10 tests** - Circuit breaker pattern implementation

#### Event Listeners (4 tests)
- Circuit open event listener
- Circuit half-open event listener
- Circuit close event listener
- Circuit failure event listener

#### Metrics (2 tests)
- Prometheus metrics existence
- Service label in metrics

#### Behavior (3 tests)
- Circuit breaker creation
- Opens after threshold failures (5)
- Prevents calls when open
- Allows successful calls

#### Integration (1 test)
- Middleware integration with FastAPI

---

### 2.4 CORS Tests (`test_cors.py`)
**13 tests** - Cross-Origin Resource Sharing

#### Headers (2 tests)
- Content-Type header allowed
- Authorization header allowed

#### Preflight Requests (4 tests)
- Basic OPTIONS request handling
- POST method preflight
- Custom header preflight
- Max-Age header presence

#### Methods & Origins (5 tests)
- GET method allowed
- POST method allowed
- DELETE method allowed
- localhost origin allowed
- No origin header works

#### Integration (2 tests)
- CORS with rate limiting
- Consistent CORS across requests

---

### 2.5 Database Demo Tests (`test_database_demo.py`)
**9 tests** (6 skipped - require infrastructure)

#### PostgreSQL (3 tests)
- Query success (SKIPPED - requires DB)
- Connection failure handling
- Vault credential failure

#### MySQL (3 tests)
- Query success (SKIPPED - requires DB)
- Connection failure handling
- Vault credential failure

#### MongoDB (3 tests)
- Query success (SKIPPED - requires DB)
- Connection failure handling
- Vault credential failure

---

### 2.6 Exception Handler Tests (`test_exception_handlers.py` + `test_exception_handlers_unit.py`)
**35 tests** - Exception handling and error responses

#### Exception Handlers (12 tests)
- 503 responses for Vault unavailability
- 404 responses for resource not found
- 422 responses for validation errors
- Retry suggestions in service unavailable responses
- Request ID tracking in error responses
- Error detail preservation in responses
- Error logging with context
- Debug mode behavior (show/hide stack traces)
- Prometheus error counter metrics
- Unhandled exception handling
- HTTP exception conversion

#### Unit Tests (23 tests)
- Custom exception handler registration
- BaseAPIException formatting
- ServiceUnavailableError handling
- ValidationError formatting
- ResourceNotFoundError handling
- Request validation error conversion
- Error response structure

---

### 2.7 Exception Hierarchy Tests (`test_exceptions.py`)
**20 tests** - Exception classes and inheritance

#### Exception Creation (9 tests)
- VaultUnavailableError with secret paths
- DatabaseConnectionError with connection details
- CacheConnectionError initialization
- ValidationError with field details
- ResourceNotFoundError with resource info
- AuthenticationError handling
- RateLimitError with retry-after headers
- CircuitBreakerError with service names
- TimeoutError with operation details

#### Exception Hierarchy (5 tests)
- All exceptions inherit from BaseAPIException
- Service exceptions inherit from ServiceUnavailableError
  - VaultUnavailableError
  - DatabaseConnectionError
  - CacheConnectionError
  - MessageQueueError
  - CircuitBreakerError
- TimeoutError uses 504 Gateway Timeout status

#### Exception Helpers (6 tests)
- Exception to_dict() serialization
- Service-specific error details
- HTTP error code mapping
- Error message formatting
- Status code validation
- Details dictionary handling

---

### 2.8 Health Router Tests (`test_health_routers.py`)
**18 tests** - Health check endpoints

#### Individual Service Health (6 tests - SKIPPED)
- Vault health check
- PostgreSQL health check
- MySQL health check
- MongoDB health check
- Redis health check
- RabbitMQ health check

#### Aggregated Health (12 tests)
- All services healthy response
- Individual service failure detection
- Overall status calculation (healthy/degraded)
- Response time tracking
- Health endpoint format
- Metrics generation
- Partial outage handling
- Complete outage handling
- Degraded service detection
- Cache health status
- Service dependency tracking
- Health check timeouts

---

### 2.9 Rate Limiting Tests (`test_rate_limiting.py`)
**8 tests** - Request rate limiting

- Rate limit enforcement
- 429 status code on limit exceeded
- Retry-After header presence
- Rate limit reset after time window
- Different endpoints separate limits
- Sliding window algorithm
- Prometheus rate limit metrics
- Rate limit headers in response (X-RateLimit-*)

---

### 2.10 Redis Cluster Tests (`test_redis_cluster.py`)
**15 tests** (10 skipped - require cluster)

#### Cluster Operations (10 tests - SKIPPED)
- Get cluster nodes
- Get cluster info
- Get cluster slot distribution
- Get individual node info
- Cluster failover testing
- Slot rebalancing
- Master-replica verification
- Cluster state validation
- Node health checks
- Cluster topology

#### Unit Tests (5 tests)
- Cluster node retrieval
- Connection failure handling
- Cluster info parsing
- Invalid node handling
- Error response formatting

---

### 2.11 Request Validation Tests (`test_request_validation.py`)
**15 tests** - Input validation and sanitization

#### Path Parameters (6 tests)
- Valid cache key format
- Invalid special characters rejection
- Valid service names
- Invalid service names
- Path traversal prevention
- Null byte injection prevention

#### Input Sanitization (4 tests)
- Service name lowercase conversion
- Whitespace trimming
- Special character removal
- Maximum length enforcement

#### Content Type (3 tests)
- JSON content type validation
- Invalid content type rejection
- Missing content type handling

#### Query Parameters (2 tests)
- Valid parameter ranges
- Invalid parameter values

---

### 2.12 Request Validators Tests (`test_request_validators.py`)
**Tests** - Pydantic model validation

- ServiceNameParam validation
- CacheKeyParam validation
- QueueNameParam validation
- SecretKeyParam validation
- Value size limits
- TTL range validation

---

### 2.13 Router Unit Tests (`test_routers_unit.py`)
**30+ tests** - Individual router unit tests

#### Cache Demo Routers (11 tests)
- Get existing value
- Get nonexistent value
- Set value without TTL
- Set value with TTL
- Delete existing key
- Delete nonexistent key
- Redis error handling
- Get Redis client
- Value expiration
- Cache statistics
- Pattern matching

#### Vault Demo Routers (2 tests - SKIPPED)
- Get vault secret
- Get vault secret with key

#### Database Routers (3 tests)
- PostgreSQL queries (1 SKIPPED)
- MySQL queries (1 SKIPPED)
- MongoDB queries (unit test)

#### Messaging Routers (3 tests - 2 SKIPPED)
- Publish message
- Publish failure handling
- Consume messages (SKIPPED)

#### Redis Cluster Routers (4 tests)
- Get cluster nodes
- Connection failure handling
- Cluster info parsing
- Invalid node errors

---

### 2.14 Vault Service Tests (`test_vault_service.py`)
**17 tests** - Vault client implementation

#### Secret Retrieval (9 tests)
- Successful secret retrieval
- Retrieve specific key from secret
- 404 handling (secret not found)
- 403 handling (permission denied)
- Key not found in secret
- Connection timeout handling
- Connection error handling
- HTTP error handling
- Unexpected error handling

#### Health Checks (5 tests)
- Healthy Vault status
- Sealed Vault detection
- Uninitialized Vault detection
- Standby node detection
- Connection error handling

#### Integration Flows (3 tests)
- Client initialization with settings
- End-to-end secret retrieval flow
- End-to-end error handling flow

---

## 3. Shared Test Suite (API Parity Tests)

**Location:** `reference-apps/shared/test-suite/`

**Total Test Runs:** 26 (16 test functions, parametrized to run against both APIs)

**Purpose:** Validate that the code-first and API-first implementations maintain 100% behavioral equivalence.

**Test Framework:** pytest with async support, parametrized fixtures, and deep comparison

---

### 3.1 Test Categories

#### Parity Tests (`@pytest.mark.parity`)
Tests that run against **both** implementations independently using parametrized fixtures.

**How it works:**
- Single test function decorated with `api_url` fixture
- Pytest automatically runs it twice: once for code-first (port 8000), once for API-first (port 8001)
- Validates each implementation independently

**Example:**
```python
async def test_health_check(self, api_url, http_client):
    # This test runs twice automatically
    response = await http_client.get(f"{api_url}/health/")
    assert response.status_code == 200
```

#### Comparison Tests (`@pytest.mark.comparison`)
Tests that directly compare responses from both APIs to ensure identical behavior.

**How it works:**
- Test receives both API URLs via `both_api_urls` fixture
- Makes requests to both implementations
- Compares responses for exact matches

**Example:**
```python
async def test_responses_match(self, both_api_urls, http_client):
    code_first = await http_client.get(f"{both_api_urls['code-first']}/health/")
    api_first = await http_client.get(f"{both_api_urls['api-first']}/health/")
    assert code_first.json() == api_first.json()
```

---

### 3.2 Health Check Tests (`test_health_checks.py`)

**7 test runs** (4 test functions)

#### Parity Tests (6 test runs from 3 functions)
1. **Simple health check** (`test_simple_health_check`)
   - Runs against both APIs (2 runs)
   - Validates `/health/` endpoint returns 200 with `{"status": "ok"}`

2. **Health response structure** (`test_health_response_structure`)
   - Runs against both APIs (2 runs)
   - Validates response is dict with string status field

3. **Vault health check** (`test_vault_health_check`)
   - Runs against both APIs (2 runs)
   - Validates `/health/vault` returns healthy/unhealthy status

#### Comparison Tests (1 test run)
4. **Health responses match** (`test_health_responses_match`)
   - Direct comparison between both APIs
   - Ensures identical health response structure and content

---

### 3.3 API Parity Tests (`test_api_parity.py`)

**19 test runs** (12 test functions)

#### Root Endpoint Tests (3 test runs)
- **Root endpoint returns info** - Parametrized (2 runs)
  - Validates presence of name, version, description
- **Root endpoint structure matches** - Comparison (1 run)
  - Ensures both APIs return identical top-level keys

#### OpenAPI Spec Tests (5 test runs)
- **OpenAPI endpoint accessible** - Parametrized (2 runs)
  - Validates `/openapi.json` returns valid OpenAPI spec
- **OpenAPI specs match** - Comparison (1 run)
  - Ensures both APIs expose identical paths
- **OpenAPI version format** - Parametrized (2 runs)
  - Validates OpenAPI 3.x.x version format

#### Vault Endpoints Tests (2 test runs)
- **Vault secret endpoint structure** - Parametrized (2 runs)
  - Validates `/examples/vault/secret/{path}` error handling

#### Cache Endpoints Tests (3 test runs)
- **Cache GET endpoint exists** - Parametrized (2 runs)
  - Validates `/examples/cache/{key}` endpoint
- **Cache endpoints have same behavior** - Comparison (1 run)
  - Ensures identical response structure for cache operations

#### Metrics Endpoint Tests (3 test runs)
- **Metrics endpoint accessible** - Parametrized (2 runs)
  - Validates `/metrics` returns Prometheus format
- **Metrics format matches** - Comparison (1 run)
  - Ensures both APIs return same Prometheus format

#### Error Handling Tests (3 test runs)
- **404 response format** - Parametrized (2 runs)
  - Validates consistent 404 error structure
- **404 responses match** - Comparison (1 run)
  - Ensures identical 404 error responses

---

### 3.4 Test Infrastructure

#### Fixtures (`conftest.py`)
```python
@pytest.fixture(params=[CODE_FIRST_URL, API_FIRST_URL])
def api_url(request):
    """Parametrized fixture - tests run twice, once per API"""
    return request.param

@pytest.fixture
async def both_api_urls():
    """Fixture providing both URLs for comparison tests"""
    return {
        "code-first": CODE_FIRST_URL,
        "api-first": API_FIRST_URL
    }

@pytest.fixture
async def http_client():
    """Async HTTP client for making API requests"""
    async with httpx.AsyncClient() as client:
        yield client
```

#### Configuration (`pytest.ini`)
```ini
[pytest]
markers =
    parity: Tests that run against both implementations
    comparison: Tests that compare both implementations
    health: Health check related tests
```

---

### 3.5 Coverage Areas

| Area | Parity Tests | Comparison Tests | Total Runs |
|------|--------------|------------------|------------|
| Root Endpoint | 1 × 2 | 1 | 3 |
| OpenAPI Spec | 2 × 2 | 1 | 5 |
| Health Checks | 3 × 2 | 1 | 7 |
| Vault Integration | 1 × 2 | 0 | 2 |
| Cache Operations | 1 × 2 | 1 | 3 |
| Metrics | 1 × 2 | 1 | 3 |
| Error Handling | 1 × 2 | 1 | 3 |
| **Total** | **10 × 2** | **6** | **26** |

---

### 3.6 Running Shared Test Suite

#### Prerequisites
Both APIs must be running:
```bash
# Start both implementations
docker compose up -d reference-api api-first

# Verify both are healthy
curl http://localhost:8000/health/
curl http://localhost:8001/health/
```

#### Run Tests
```bash
cd reference-apps/shared/test-suite
pip install -r requirements.txt
pytest -v
```

#### Expected Results
```
test_health_checks.py::TestHealthEndpoints::test_simple_health_check[code-first] PASSED
test_health_checks.py::TestHealthEndpoints::test_simple_health_check[api-first] PASSED
test_health_checks.py::TestHealthParity::test_health_responses_match PASSED
test_api_parity.py::TestRootEndpoint::test_root_endpoint_returns_info[code-first] PASSED
test_api_parity.py::TestRootEndpoint::test_root_endpoint_returns_info[api-first] PASSED
...

========================== 26 passed in 2.34s ===========================
```

#### Run Specific Categories
```bash
# Health checks only
pytest -v -m health

# Parity tests only
pytest -v -m parity

# Comparison tests only
pytest -v -m comparison
```

---

### 3.7 What Gets Validated

**Endpoint Consistency:**
- ✅ Identical endpoint paths
- ✅ Identical response structures
- ✅ Identical status codes
- ✅ Identical error handling

**API Contract:**
- ✅ OpenAPI specifications match
- ✅ Request/response formats identical
- ✅ Content-Type headers consistent
- ✅ Error response formats match

**Behavioral Equivalence:**
- ✅ Health checks return same information
- ✅ Cache operations behave identically
- ✅ Metrics format is consistent
- ✅ 404 errors formatted the same

**Integration Points:**
- ✅ Vault integration consistent
- ✅ Database access patterns match
- ✅ Cache behavior identical
- ✅ All service integrations work

---

### 3.8 Success Criteria

The shared test suite enforces:
- **100% pass rate** - All 26 tests must pass
- **No manual sync** - Automated validation prevents drift
- **CI/CD integration** - Tests run on every commit
- **Continuous parity** - Both implementations stay synchronized

**Current Status:** ✅ 26/26 tests passing (100% parity achieved)

---

### 3.9 Maintenance

When adding new endpoints to either implementation:

1. **Update OpenAPI spec** (`reference-apps/shared/openapi.yaml`)
2. **Implement in code-first** (`reference-apps/fastapi/`)
3. **Implement in API-first** (`reference-apps/fastapi-api-first/`)
4. **Add parity test** to validate endpoint on both implementations
5. **Add comparison test** if responses must be byte-for-byte identical
6. **Run shared test suite** - must achieve 100% pass rate
7. **Update documentation** (this file, README files)

---

## Running Tests

### Infrastructure Tests (Shell Scripts)

#### Run All Infrastructure Tests
```bash
./tests/run-all-tests.sh
```

This runs all test suites in sequence and provides a comprehensive summary.

#### Run Individual Test Suites
```bash
# Infrastructure
./tests/test-vault.sh

# Databases
./tests/test-postgres.sh
./tests/test-mysql.sh
./tests/test-mongodb.sh

# Cache & Messaging
./tests/test-redis-cluster.sh
./tests/test-rabbitmq.sh

# Application Container
./tests/test-fastapi.sh
```

---

### FastAPI Application Tests (Pytest)

#### Run All Tests
```bash
cd reference-apps/fastapi
pytest tests/ -v
```

#### Run with Coverage
```bash
pytest tests/ --cov=app --cov-report=html --cov-report=term
```

#### Run Specific Test File
```bash
pytest tests/test_vault_service.py -v
```

#### Run Specific Test
```bash
pytest tests/test_vault_service.py::TestVaultClientGetSecret::test_get_secret_success -v
```

#### Run Only Unit Tests
```bash
pytest tests/ -v -m unit
```

#### Run Only Integration Tests
```bash
pytest tests/ -v -m integration
```

---

## Test Dependencies

### System Tools (Infrastructure Tests)
- `curl` - HTTP client (usually pre-installed)
- `jq` - JSON processor
  ```bash
  # macOS
  brew install jq

  # Ubuntu/Debian
  apt-get install jq
  ```
- `docker` - Container runtime (via Colima)
- `docker-compose` - Container orchestration

### Python Dependencies (Application Tests)
```bash
cd reference-apps/fastapi
pip install -r requirements.txt
```

Includes:
- `pytest` - Test framework
- `pytest-asyncio` - Async test support
- `pytest-cov` - Coverage reporting
- `pytest-mock` - Mocking utilities
- `httpx` - HTTP client for testing
- `fastapi[all]` - FastAPI with all extras

---

## Test Results Format

### Infrastructure Tests Output
Each shell script test suite provides:
- Real-time test execution output
- Color-coded pass/fail indicators (green ✓ / red ✗)
- Summary with total tests, passed, and failed counts
- List of failed tests (if any)

Example output:
```
=========================================
  FastAPI Reference App Test Suite
=========================================

[TEST] Test 1: FastAPI container is running
[PASS] FastAPI container is running

[TEST] Test 5: Redis health check with cluster details
[PASS] Redis health shows cluster enabled with 3 nodes in ok state

[TEST] Test 7: Redis cluster slots API endpoint
[PASS] Redis cluster slots API shows 100% coverage (16384 slots)

=========================================
  Test Results
=========================================
Total tests: 14
Passed: 13

✓ All FastAPI tests passed!
```

### Pytest Output
```
============================= test session starts ==============================
collected 254 items

tests/test_caching.py::TestCacheKeyGeneration::test_generate_cache_key_basic PASSED [ 0%]
tests/test_caching.py::TestCacheKeyGeneration::test_generate_cache_key_with_query_params PASSED [ 1%]
...
tests/test_vault_service.py::TestVaultServiceIntegration::test_vault_error_handling_flow PASSED [100%]

---------- coverage: platform linux, python 3.11.14-final-0 ----------
Name                                   Stmts   Miss  Cover   Missing
--------------------------------------------------------------------
app/__init__.py                            0      0   100%
app/config.py                             22      0   100%
app/exceptions.py                         86      0   100%
...
--------------------------------------------------------------------
TOTAL                                    974    152    84%

Required test coverage of 80% reached. Total coverage: 84.39%
================= 178 passed, 76 skipped, 6 warnings in 1.76s ==================
```

---

## Coverage Summary

### Infrastructure Tests (Shell Scripts)
| Component | Test Suite | Tests | Coverage |
|-----------|-----------|-------|----------|
| Vault | test-vault.sh | 10 | PKI, secrets, certificates, auto-unseal |
| PostgreSQL | test-postgres.sh | ~5 | Container, credentials, connectivity |
| MySQL | test-mysql.sh | ~5 | Container, credentials, connectivity |
| MongoDB | test-mongodb.sh | ~5 | Container, credentials, connectivity |
| Redis Cluster | test-redis-cluster.sh | 12 | Cluster init, slots, sharding, failover |
| RabbitMQ | test-rabbitmq.sh | ~5 | Container, credentials, messaging |
| FastAPI Container | test-fastapi.sh | 14 | Container, APIs, health, cluster endpoints |

**Subtotal: ~56 infrastructure tests**

### Application Tests (Pytest)
| Category | Tests | Coverage |
|----------|-------|----------|
| Caching | 34 | Cache middleware, operations, keys, invalidation |
| Circuit Breakers | 10 | Pattern implementation, metrics, events |
| CORS | 13 | Headers, preflight, methods, origins |
| Databases | 9 | PostgreSQL, MySQL, MongoDB integration |
| Exception Handling | 55 | Handlers, hierarchy, formatting, errors |
| Health Checks | 18 | Service health, aggregation, metrics |
| Rate Limiting | 8 | IP-based limits, throttling, headers |
| Redis Cluster | 15 | Cluster ops, nodes, slots, info |
| Request Validation | 15+ | Input validation, sanitization, types |
| Routers | 30+ | Cache, vault, database, messaging routers |
| Vault Service | 17 | Secret retrieval, health checks, errors |

**Subtotal: 178 executed unit tests (76 integration tests skipped)**

**Code Coverage: 84.39%**

### Shared Test Suite (Pytest)
| Category | Test Runs | Coverage |
|----------|-----------|----------|
| Health Checks | 7 | Simple health, structure, Vault health, response matching |
| Root Endpoint | 3 | API info, structure consistency |
| OpenAPI Spec | 5 | Spec access, matching, version format |
| Vault Endpoints | 2 | Error handling, endpoint structure |
| Cache Endpoints | 3 | GET operations, behavior consistency |
| Metrics | 3 | Prometheus format, endpoint access |
| Error Handling | 3 | 404 format, response consistency |

**Subtotal: 26 parity test runs** (16 test functions, parametrized across both APIs)

---

## 4. Go Reference API

**Location:** `reference-apps/golang/`

**Implementation Status:** ✅ Complete and tested

**Purpose:** Demonstrate language-agnostic infrastructure integration patterns using Go and the Gin web framework.

---

### 4.1 Implementation Features

The Go reference API provides a production-ready implementation showcasing:

#### Core Capabilities
- **Vault Integration**: HashiCorp Vault client for secrets management
- **Database Connectivity**: PostgreSQL (pgx/v5), MySQL (go-sql-driver), MongoDB (mongo-driver)
- **Caching**: Redis cluster operations with go-redis/v9
- **Messaging**: RabbitMQ integration with amqp091-go
- **Health Checks**: Comprehensive service health monitoring
- **Redis Cluster Management**: Full cluster inspection and node monitoring

#### Go-Specific Features
- **Concurrency**: Goroutines for concurrent health checks
- **Context Propagation**: Proper context.Context usage throughout
- **Graceful Shutdown**: Signal handling (SIGINT/SIGTERM) with clean termination
- **Structured Logging**: Logrus with JSON formatting and request ID correlation
- **Type Safety**: Strong typing with explicit error handling
- **Prometheus Metrics**: Native Go Prometheus client integration

---

### 4.2 API Endpoints

**Container:** `golang-api` (dev-golang-api)
**Ports:** 8002 (HTTP), 8445 (HTTPS)
**Framework:** Gin v1.9.1
**Go Version:** 1.21

#### Available Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/` | GET | API information and endpoint discovery |
| `/health/` | GET | Simple health check (no dependencies) |
| `/health/all` | GET | Aggregate health (concurrent checks) |
| `/health/vault` | GET | Vault connectivity and status |
| `/health/postgres` | GET | PostgreSQL connection test |
| `/health/mysql` | GET | MySQL connection test |
| `/health/mongodb` | GET | MongoDB connection test |
| `/health/redis` | GET | Redis cluster health |
| `/health/rabbitmq` | GET | RabbitMQ connectivity |
| `/examples/vault/secret/:service_name` | GET | Retrieve service secrets |
| `/examples/vault/secret/:service_name/:key` | GET | Retrieve specific secret key |
| `/examples/database/postgres/query` | GET | PostgreSQL query example |
| `/examples/database/mysql/query` | GET | MySQL query example |
| `/examples/database/mongodb/query` | GET | MongoDB query example |
| `/examples/cache/:key` | GET | Get cache value |
| `/examples/cache/:key` | POST | Set cache value with TTL |
| `/examples/cache/:key` | DELETE | Delete cache key |
| `/redis/cluster/nodes` | GET | List all cluster nodes |
| `/redis/cluster/slots` | GET | Slot distribution |
| `/redis/cluster/info` | GET | Cluster information |
| `/redis/nodes/:node_name/info` | GET | Detailed node information |
| `/examples/messaging/publish/:queue` | POST | Publish message to queue |
| `/examples/messaging/queue/:queue_name/info` | GET | Queue information |
| `/metrics` | GET | Prometheus metrics |

---

### 4.3 Manual Testing Results

**Test Date:** 2025-10-27

#### ✅ Verified Working Endpoints

1. **Root Endpoint** (`/`)
   - Returns comprehensive API information
   - Lists all available endpoint categories
   - Includes security configuration details

2. **Simple Health Check** (`/health/`)
   - Returns `{"status": "ok"}`
   - No external dependencies
   - Fast response (<5ms)

3. **Vault Health Check** (`/health/vault`)
   - Successfully connects to Vault
   - Returns initialization status, seal status, version
   - Proper error handling

4. **Aggregate Health Check** (`/health/all`)
   - Uses goroutines for concurrent service checks
   - Returns health status for all available services
   - Fast execution with parallel checks

5. **Prometheus Metrics** (`/metrics`)
   - Exposes Go runtime metrics (goroutines, memory, GC)
   - Standard Prometheus format
   - HTTP request counters and histograms

#### Expected Behavior - Vault Secrets Not Bootstrapped

Database and cache endpoints properly return errors when Vault secrets are missing:
- `/health/postgres` - Returns "secret not found" error (correct behavior)
- `/health/redis` - Returns "secret not found" error (correct behavior)
- `/examples/cache/*` - Returns "secret not found" error (correct behavior)

This demonstrates the implementation correctly integrates with Vault and handles missing credentials appropriately.

---

### 4.4 Architecture Highlights

#### Project Structure
```
reference-apps/golang/
├── cmd/api/main.go              # Application entry point
├── internal/
│   ├── config/config.go         # Configuration management
│   ├── handlers/                # HTTP handlers
│   │   ├── health.go
│   │   ├── vault.go
│   │   ├── database.go
│   │   ├── cache.go
│   │   ├── redis_cluster.go
│   │   └── messaging.go
│   ├── middleware/logging.go    # Logging + CORS
│   └── services/vault.go        # Vault client
├── Dockerfile                   # Multi-stage build
├── init.sh                      # Vault integration + TLS
└── start.sh                     # Application startup
```

#### Key Design Patterns

**Dependency Injection:**
```go
healthHandler := handlers.NewHealthHandler(cfg, vaultClient)
```

**Context Propagation:**
```go
ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
defer cancel()
```

**Resource Cleanup:**
```go
defer conn.Close(ctx)
```

**Concurrent Operations:**
```go
var wg sync.WaitGroup
for _, service := range services {
    wg.Add(1)
    go checkService(service, &wg)
}
wg.Wait()
```

---

### 4.5 Comparison with Python Implementation

| Feature | Go (Gin) | Python (FastAPI) |
|---------|----------|------------------|
| **Concurrency Model** | Goroutines (native) | asyncio (event loop) |
| **Type System** | Static typing (compile-time) | Type hints (runtime optional) |
| **Performance** | Compiled, very fast | Interpreted, fast with async |
| **Memory Usage** | Low (~20-30MB) | Higher (~80-150MB) |
| **Startup Time** | Instant (<100ms) | Slower (~1-2s) |
| **Deployment** | Single binary | Python + dependencies |
| **Error Handling** | Explicit returns | Exceptions |
| **Context Management** | context.Context | async context |
| **Testing** | go test | pytest |

---

### 4.6 Testing Status

#### ✅ Completed
- [x] Docker image builds successfully
- [x] Container starts and initializes
- [x] All routes registered correctly
- [x] Vault connectivity verified
- [x] Health check endpoints functional
- [x] Prometheus metrics exposed
- [x] Error handling for missing Vault secrets
- [x] Graceful shutdown working
- [x] Logging middleware operational
- [x] CORS middleware configured

#### 🔄 Requires Infrastructure Bootstrap
The following features require Vault secrets to be bootstrapped:
- Database connectivity tests (PostgreSQL, MySQL, MongoDB)
- Redis cache operations
- RabbitMQ messaging operations
- Redis cluster management APIs

These endpoints correctly detect missing credentials and return appropriate error messages.

### 4.9 Automated Test Suite

**Test Status:** ✅ **35+ tests, 100% PASS RATE**

#### Test Files Created
- `internal/config/config_test.go` - Configuration testing
- `internal/services/vault_test.go` - Vault client testing
- `internal/middleware/logging_test.go` - Middleware testing

#### Test Coverage by Package

**Config Package** (12 tests)
- Default configuration values
- Custom HTTP/HTTPS ports
- Vault address and token configuration
- Debug mode enabled/disabled
- Environment settings (development/production)
- Database configuration (PostgreSQL, MySQL, MongoDB)
- Redis configuration
- RabbitMQ configuration
- Environment variable fallback handling
- Configuration completeness validation
- **Coverage: 91.7%**

**Vault Service** (9 test groups)
- VaultClient creation with various configurations
- GetSecret context handling (timeout, cancellation)
- GetSecretKey method validation
- HealthCheck functionality
- Client structure validation
- Concurrent access safety
- Error message formatting
- Method signature validation
- **Coverage: 62.5%**

**Middleware** (14 tests)
- Request ID generation and propagation
- Request logging with structured fields
- HTTP method logging (GET, POST, PUT, DELETE, PATCH)
- Status code logging (200, 201, 400, 404, 500)
- Request duration measurement
- CORS header configuration
- OPTIONS preflight request handling
- Credential allowance
- Max-Age cache control
- Standard header allowance
- Middleware integration
- **Coverage: 100.0%**

#### Test Execution

```bash
cd reference-apps/golang
go test ./... -v -cover
```

**Results:**
```
✓ Config:     12 tests PASS (91.7% coverage)
✓ Services:   9 tests PASS (62.5% coverage)
✓ Middleware: 14 tests PASS (100.0% coverage)
────────────────────────────────────────────
TOTAL:        35+ tests, 100% PASS RATE
```

#### Test Patterns Used

1. **Table-Driven Tests**: Structured test cases for multiple scenarios
2. **Subtests**: Organized test output with t.Run()
3. **Context Testing**: Timeout and cancellation handling
4. **HTTP Testing**: Using httptest.Recorder and httptest.NewRequest
5. **Concurrency Testing**: Goroutine safety validation
6. **Error Validation**: Comprehensive error message checking

#### 📝 Future Testing Enhancements
- [ ] Handler tests using httptest (database, cache, messaging handlers)
- [ ] Integration tests with mock Vault server
- [ ] Benchmark tests for performance validation
- [ ] E2E tests with full infrastructure stack

---

### 4.7 Running the Go API

#### Start Service
```bash
# Build and start
docker-compose up -d golang-api

# View logs
docker-compose logs -f golang-api

# Check health
curl http://localhost:8002/health/
```

#### Test Endpoints
```bash
# Root endpoint
curl http://localhost:8002/ | jq .

# Health checks
curl http://localhost:8002/health/all | jq .
curl http://localhost:8002/health/vault | jq .

# Metrics
curl http://localhost:8002/metrics

# Cache operations (requires Vault bootstrap)
curl -X POST "http://localhost:8002/examples/cache/test?value=hello&ttl=60"
curl http://localhost:8002/examples/cache/test

# Redis cluster info (requires Vault bootstrap)
curl http://localhost:8002/redis/cluster/nodes | jq .
```

---

### 4.8 Dependencies

**Main Dependencies:**
- `github.com/gin-gonic/gin` v1.9.1 - Web framework
- `github.com/hashicorp/vault/api` v1.10.0 - Vault client
- `github.com/jackc/pgx/v5` v5.5.0 - PostgreSQL driver
- `github.com/go-sql-driver/mysql` v1.7.1 - MySQL driver
- `go.mongodb.org/mongo-driver` v1.13.1 - MongoDB driver
- `github.com/redis/go-redis/v9` v9.3.0 - Redis client
- `github.com/rabbitmq/amqp091-go` v1.9.0 - RabbitMQ client
- `github.com/prometheus/client_golang` v1.17.0 - Prometheus metrics
- `github.com/sirupsen/logrus` v1.9.3 - Structured logging

**Total Dependencies:** 76 (including transitive)

---

## Total Test Coverage

**Infrastructure + Application + Parity: 330+ tests**

- **56 infrastructure integration tests** (shell scripts)
- **178 application unit tests** (pytest - executed)
- **76 application integration tests** (pytest - skipped in CI)
- **26 shared parity test runs** (pytest - validates API equivalence)

**Combined Coverage:**
- All Docker containers and services
- Vault PKI and secrets management
- Database connectivity and credentials
- Redis cluster operations
- RabbitMQ messaging
- FastAPI application endpoints
- Middleware (caching, circuit breakers, CORS, rate limiting)
- Exception handling
- Request validation
- Health checks
- Prometheus metrics
- **API parity validation** (code-first vs API-first equivalence)

---

## Continuous Testing

Run tests after:
- Initial infrastructure setup (`./devstack.sh start`)
- Service configuration changes
- Certificate regeneration
- Vault bootstrap
- Container restarts
- Application deployments
- Code changes (`pytest tests/`)
- Pull request reviews
- Pre-production deployment

This ensures all components remain properly configured, integrated, and functional.

---

## Test Quality Metrics

### Infrastructure Tests
- **Real environment testing**: Tests run against actual Docker containers
- **Integration validation**: Tests verify inter-service communication
- **Credential security**: Tests verify Vault integration throughout

### Application Tests
- **High unit test coverage**: 84.39% code coverage
- **100% pass rate**: All 178 executed tests passing
- **Comprehensive mocking**: External dependencies mocked for speed
- **Async support**: Full async/await testing with pytest-asyncio
- **Fast execution**: Unit tests complete in <2 seconds

---

## CI/CD Considerations

### Recommended CI Pipeline

```yaml
# Example GitHub Actions workflow
jobs:
  infrastructure-tests:
    runs-on: ubuntu-latest
    steps:
      - Install Docker/Colima
      - ./devstack.sh start
      - ./tests/run-all-tests.sh

  application-tests:
    runs-on: ubuntu-latest
    steps:
      - cd reference-apps/fastapi
      - pip install -r requirements.txt
      - pytest tests/ --cov=app --cov-fail-under=80
```

### Test Environments
- **Local Development**: All tests (infrastructure + application)
- **CI/CD**: Unit tests only (fast feedback)
- **Pre-Production**: Full integration tests
- **Production**: Smoke tests + health checks

---

## Future Test Improvements

Planned enhancements:
- Performance testing
- Load testing with Locust
- Security testing
- End-to-end user workflows
- Automated snapshot testing
- Chaos engineering tests

---

## Documentation

- **Main README**: [../README.md](../README.md)
- **FastAPI (Code-First) README**: [../reference-apps/fastapi/README.md](../reference-apps/fastapi/README.md)
- **FastAPI (API-First) README**: [../reference-apps/fastapi-api-first/README.md](../reference-apps/fastapi-api-first/README.md)
- **Go Reference API README**: [../reference-apps/golang/README.md](../reference-apps/golang/README.md)
- **API Patterns**: [.API-Patterns](.API-Patterns)
- **Reference Apps Overview**: [.Development-Workflow](.Development-Workflow)
