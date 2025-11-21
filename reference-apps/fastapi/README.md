# FastAPI Reference Application (Code-First)

## ✅ **FEATURE-COMPLETE IMPLEMENTATION** ✅

**Production-ready Python implementation with 100% feature completeness** - The flagship reference implementation.

**⚠️ This is a reference implementation for learning and testing. Not intended for production use.**

This FastAPI application demonstrates production-grade best practices for integrating with the DevStack Core infrastructure. It showcases secure credential management, circuit breakers, rate limiting, resilience patterns, response caching, observability, and comprehensive error handling with 188 unit tests.

### Implementation Highlights

- **Complete infrastructure integration** - All services: Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- **Advanced resilience patterns** - Circuit breakers prevent cascading failures
- **Rate limiting** - IP-based rate limiting (100-1000 req/min by endpoint)
- **Response caching** - Automatic caching with TTL configuration
- **188 comprehensive unit tests** - Extensive test coverage with pytest
- **Async/await throughout** - Modern Python async patterns with asyncio
- **Structured logging** - JSON-formatted logs for aggregation
- **Real Prometheus metrics** - HTTP requests, cache ops, circuit breakers
- **Request tracing** - Distributed request ID correlation
- **Interactive API docs** - Auto-generated Swagger UI and ReDoc

## Table of Contents

- [Features Overview](#features-overview)
- [API Endpoints](#api-endpoints)
  - [Health Checks](#health-checks-health)
  - [Vault Integration](#vault-integration-examplesvault)
  - [Database Operations](#database-operations-examplesdatabase)
  - [Caching](#caching-examplescache)
  - [Messaging](#messaging-examplesmessaging)
  - [Redis Cluster Management](#redis-cluster-management-redis)
  - [Metrics](#metrics-metrics)
- [Architecture](#architecture)
- [Security Features](#security-features)
- [Middleware](#middleware)
- [Monitoring & Observability](#monitoring--observability)
- [Quick Start](#quick-start)
- [Development](#development)
- [Testing](#testing)
- [Environment Variables](#environment-variables)

---

## Features Overview

### Core Capabilities
- **Vault Integration**: Secure credential fetching with HashiCorp Vault
- **Database Connections**: PostgreSQL, MySQL, MongoDB with connection pooling
- **Caching**: Redis cluster integration with response caching
- **Messaging**: RabbitMQ pub/sub patterns with queue management
- **Health Monitoring**: Comprehensive health checks for all services
- **Redis Cluster**: Full cluster management and slot distribution monitoring

### Advanced Features
- **Circuit Breakers**: Prevent cascading failures across all services
- **Rate Limiting**: IP-based rate limiting (100-1000 req/min depending on endpoint)
- **Request Validation**: Content-type and size validation
- **Response Caching**: Automatic response caching with TTL configuration
- **Structured Logging**: JSON-formatted logs for aggregation
- **Prometheus Metrics**: HTTP requests, cache operations, circuit breakers
- **CORS Security**: Environment-aware CORS configuration
- **Request Tracing**: Distributed request ID correlation

---

## API Endpoints

### Health Checks (`/health`)

Comprehensive health monitoring for all infrastructure services.

| Method | Endpoint | Description | Rate Limit | Cache TTL |
|--------|----------|-------------|------------|-----------|
| GET | `/health/` | Simple health check (no dependencies) | 200/min | None |
| GET | `/health/all` | Aggregate health of all services | 200/min | 30s |
| GET | `/health/vault` | Vault connectivity and status | 200/min | None |
| GET | `/health/postgres` | PostgreSQL connection test | 200/min | None |
| GET | `/health/mysql` | MySQL connection test | 200/min | None |
| GET | `/health/mongodb` | MongoDB connection test | 200/min | None |
| GET | `/health/redis` | Redis cluster health | 200/min | None |
| GET | `/health/rabbitmq` | RabbitMQ connectivity | 200/min | None |

**Health Check Response Format:**
```json
{
  "status": "healthy|degraded",
  "services": {
    "vault": {
      "status": "healthy|unhealthy",
      "details": {
        "initialized": true,
        "sealed": false,
        "standby": false
      }
    },
    "postgres": {
      "status": "healthy",
      "version": "PostgreSQL 16.6"
    },
    "redis": {
      "status": "healthy",
      "cluster_enabled": true,
      "cluster_state": "ok",
      "total_nodes": 3
    }
  }
}
```

---

### Vault Integration (`/examples/vault`)

Secure credential management using HashiCorp Vault KV v2 secrets engine.

| Method | Endpoint | Description | Cache TTL | Response |
|--------|----------|-------------|-----------|----------|
| GET | `/examples/vault/secret/{service_name}` | Fetch all credentials for a service | 5 min | All secret fields (passwords masked) |
| GET | `/examples/vault/secret/{service_name}/{key}` | Fetch specific credential field | 5 min | Single field value (masked if sensitive) |

**Parameters:**
- `service_name`: Service identifier (e.g., `postgres`, `mysql`, `redis-1`)
  - Pattern: `^[a-zA-Z0-9_-]+$`
  - Length: 1-50 characters
- `key`: Specific credential key (e.g., `user`, `password`, `database`)
  - Pattern: `^[a-zA-Z0-9_-]+$`
  - Length: 1-100 characters

**Example Response:**
```json
GET /examples/vault/secret/postgres

{
  "service": "postgres",
  "data": {
    "user": "dev_admin",
    "password": "***",
    "database": "dev_database",
    "host": "postgres",
    "port": "5432"
  },
  "note": "Passwords are masked in API responses for security"
}
```

**Security:**
- All passwords automatically masked in responses
- Credentials cached for 5 minutes
- Circuit breaker protection (5 failures = open circuit for 60s)
- All access logged with request ID

---

### Database Operations (`/examples/database`)

Demonstrates database connectivity with Vault-managed credentials.

| Method | Endpoint | Description | Database |
|--------|----------|-------------|----------|
| GET | `/examples/database/postgres/query` | Execute test query on PostgreSQL | PostgreSQL |
| GET | `/examples/database/mysql/query` | Execute test query on MySQL | MySQL |
| GET | `/examples/database/mongodb/query` | List collections on MongoDB | MongoDB |

**PostgreSQL Response:**
```json
{
  "database": "PostgreSQL",
  "query": "SELECT current_timestamp",
  "result": "2025-10-27 12:34:56.789123+00"
}
```

**MongoDB Response:**
```json
{
  "database": "MongoDB",
  "collections": ["users", "sessions", "logs"],
  "count": 3
}
```

**Features:**
- Credentials fetched from Vault at runtime
- Connection pooling (asyncpg for PostgreSQL, aiomysql for MySQL, Motor for MongoDB)
- Circuit breaker protection per database
- Comprehensive error handling with specific exception types

---

### Caching (`/examples/cache`)

Redis-based caching with TTL support and validation.

| Method | Endpoint | Description | Parameters |
|--------|----------|-------------|------------|
| GET | `/examples/cache/{key}` | Get value from cache | `key`: Cache key (1-200 chars) |
| POST | `/examples/cache/{key}` | Set value with optional TTL | `key`: Cache key<br>`value`: Value to cache (query, max 10KB)<br>`ttl`: Expiration in seconds (query, 1-86400s, optional) |
| DELETE | `/examples/cache/{key}` | Delete value from cache | `key`: Cache key |

**Cache Key Validation:**
- Pattern: `^[a-zA-Z0-9_:.-]+$` (alphanumeric, underscore, colon, hyphen, dot)
- Length: 1-200 characters
- Whitespace automatically stripped

**Value Constraints:**
- Maximum size: 10KB (10,000 characters)
- TTL range: 1 second to 24 hours (86,400 seconds)

**GET Response:**
```json
{
  "key": "user:123",
  "value": "{\"id\":123,\"name\":\"John\"}",
  "exists": true,
  "ttl": 3599  // seconds remaining, or "no expiration"
}
```

**POST Response:**
```json
{
  "key": "session:abc123",
  "value": "active",
  "ttl": 3600,
  "action": "set"
}
```

**DELETE Response:**
```json
{
  "key": "temp:data",
  "deleted": true,
  "action": "delete"
}
```

---

### Messaging (`/examples/messaging`)

RabbitMQ message publishing and queue management.

| Method | Endpoint | Description | Parameters |
|--------|----------|-------------|------------|
| POST | `/examples/messaging/publish` | Publish message to queue | `queue_name`: Queue name (query, 1-100 chars)<br>`message`: JSON message body (max 1MB) |
| GET | `/examples/messaging/queue/{queue_name}/info` | Get queue information | `queue_name`: Queue name (path) |

**Queue Name Validation:**
- Pattern: `^[a-zA-Z0-9_.-]+$`
- Length: 1-100 characters

**Message Constraints:**
- Format: JSON object
- Maximum size: 1MB
- Cannot be empty

**Publish Response:**
```json
{
  "queue": "notifications",
  "message": {"type": "email", "to": "user@example.com"},
  "action": "published"
}
```

**Queue Info Response:**
```json
{
  "queue": "notifications",
  "exists": true,
  "message_count": 42,
  "consumer_count": 2
}
```

**Features:**
- Durable queues (survive broker restart)
- Credentials from Vault
- Circuit breaker protection
- Configurable vhost (default: `dev_vhost`)

---

### Redis Cluster Management (`/redis`)

Full Redis cluster introspection and management capabilities.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/redis/cluster/nodes` | Get all cluster nodes with roles and slots |
| GET | `/redis/cluster/slots` | Get slot distribution across masters and replicas |
| GET | `/redis/cluster/info` | Get cluster state and statistics |
| GET | `/redis/nodes/{node_name}/info` | Get detailed info for specific node |

**Cluster Nodes Response:**
```json
{
  "status": "success",
  "total_nodes": 6,
  "nodes": [
    {
      "node_id": "abc123...",
      "host": "172.20.0.20",
      "port": 6379,
      "role": "master",
      "flags": ["master", "myself"],
      "master_id": null,
      "ping_sent": "0",
      "pong_recv": "1698765432",
      "config_epoch": 1,
      "link_state": "connected",
      "slots_count": 5461,
      "slot_ranges": [
        {"start": 0, "end": 5460}
      ]
    }
  ]
}
```

**Cluster Slots Response:**
```json
{
  "status": "success",
  "total_slots": 16384,
  "max_slots": 16384,
  "coverage_percentage": 100.0,
  "slot_distribution": [
    {
      "start_slot": 0,
      "end_slot": 5460,
      "slots_count": 5461,
      "master": {
        "host": "172.20.0.20",
        "port": 6379,
        "node_id": "abc123..."
      },
      "replicas": [
        {
          "host": "172.20.0.21",
          "port": 6379,
          "node_id": "def456..."
        }
      ]
    }
  ]
}
```

**Cluster Info Response:**
```json
{
  "status": "success",
  "cluster_info": {
    "cluster_state": "ok",
    "cluster_slots_assigned": 16384,
    "cluster_slots_ok": 16384,
    "cluster_slots_pfail": 0,
    "cluster_slots_fail": 0,
    "cluster_known_nodes": 6,
    "cluster_size": 3,
    "cluster_current_epoch": 6,
    "cluster_my_epoch": 1,
    "cluster_stats_messages_sent": 123456,
    "cluster_stats_messages_received": 123450
  }
}
```

**Node Info Response:**
```json
{
  "status": "success",
  "node": "redis-1",
  "info": {
    "redis_version": "7.4.0",
    "redis_mode": "cluster",
    "os": "Linux 6.1.0-26-cloud-amd64 aarch64",
    "arch_bits": 64,
    "multiplexing_api": "epoll",
    "uptime_in_seconds": 86400,
    "uptime_in_days": 1,
    "used_memory": "2048576",
    "used_memory_human": "2.00M",
    // ... many more fields
  }
}
```

**Supported Nodes:**
- `redis-1`: Typically master for slots 0-5460
- `redis-2`: Typically master for slots 5461-10922
- `redis-3`: Typically master for slots 10923-16383

---

### Metrics (`/metrics`)

Prometheus-formatted metrics for monitoring and alerting.

**Endpoint:** `GET /metrics`

**Rate Limit:** 1000 requests/minute

**Response Format:** Prometheus text exposition format

**Metrics Exposed:**

**HTTP Metrics:**
- `http_requests_total{method, endpoint, status}` - Total requests by endpoint and status
- `http_request_duration_seconds{method, endpoint}` - Request latency histogram
- `http_requests_in_progress{method, endpoint}` - Current in-flight requests
- `http_errors_total{error_type, status_code}` - Error count by type

**Cache Metrics:**
- `cache_hits_total{endpoint}` - Cache hit count
- `cache_misses_total{endpoint}` - Cache miss count
- `cache_invalidations_total{pattern}` - Cache invalidation count

**Circuit Breaker Metrics:**
- `circuit_breaker_opened_total{service}` - Times circuit opened
- `circuit_breaker_half_open_total{service}` - Times circuit entered half-open state
- `circuit_breaker_closed_total{service}` - Times circuit recovered
- `circuit_breaker_failures_total{service}` - Total failures per service

**Application Info:**
- `app_info{version, name}` - Application metadata

---

## Architecture

### Directory Structure

```
reference-apps/fastapi/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI application setup
│   ├── config.py                  # Settings management
│   ├── exceptions.py              # Custom exception hierarchy
│   ├── middleware/
│   │   ├── __init__.py
│   │   ├── cache.py               # Response caching middleware
│   │   ├── circuit_breaker.py    # Circuit breaker pattern
│   │   └── exception_handlers.py # Centralized error handling
│   ├── models/
│   │   ├── __init__.py
│   │   ├── requests.py            # Pydantic request models
│   │   └── responses.py           # Pydantic response models
│   ├── routers/
│   │   ├── __init__.py
│   │   ├── health.py              # Health check endpoints
│   │   ├── vault_demo.py          # Vault examples
│   │   ├── database_demo.py       # Database examples
│   │   ├── cache_demo.py          # Redis caching examples
│   │   ├── messaging_demo.py      # RabbitMQ examples
│   │   └── redis_cluster.py       # Redis cluster management
│   └── services/
│       ├── __init__.py
│       └── vault.py               # Vault client implementation
├── tests/
│   ├── conftest.py                # Pytest fixtures
│   ├── test_caching.py            # Cache tests
│   ├── test_circuit_breaker.py   # Circuit breaker tests
│   ├── test_cors.py               # CORS tests
│   ├── test_database_demo.py     # Database integration tests
│   ├── test_exception_handlers.py # Exception handler tests
│   ├── test_exceptions.py         # Exception hierarchy tests
│   ├── test_health_routers.py    # Health check tests
│   ├── test_rate_limiting.py     # Rate limiting tests
│   ├── test_redis_cluster.py     # Redis cluster tests
│   ├── test_request_validation.py # Input validation tests
│   ├── test_routers_unit.py      # Router unit tests
│   └── test_vault_service.py     # Vault service tests
├── Dockerfile
├── init.sh                        # Container initialization
├── pytest.ini                     # Pytest configuration
├── requirements.txt               # Python dependencies
├── start.sh                       # Application startup script
└── README.md                      # This file
```

### Exception Hierarchy

```
BaseAPIException
├── ServiceUnavailableError (503)
│   ├── VaultUnavailableError
│   ├── DatabaseConnectionError
│   ├── CacheConnectionError
│   ├── MessageQueueError
│   └── CircuitBreakerError
├── ConfigurationError (500)
├── ValidationError (422)
├── ResourceNotFoundError (404)
├── AuthenticationError (401)
├── RateLimitError (429)
└── TimeoutError (504)
```

---

## Security Features

### 1. Credential Management
- **Vault Integration**: All credentials fetched from HashiCorp Vault
- **AppRole Authentication**: Secure Vault authentication using AppRole method (recommended for production)
- **Fallback Authentication**: Automatic fallback to token-based authentication if AppRole is not configured
- **No Hardcoded Secrets**: No credentials stored in environment variables or configuration files
- **Password Masking**: Sensitive fields masked in API responses
- **Runtime Credentials**: Credentials loaded at request time, never cached long-term

#### AppRole Authentication

The reference API uses **HashiCorp Vault AppRole authentication** for secure credential management:

**How it Works:**
1. AppRole credentials (`role-id` and `secret-id`) are mounted into the container from `~/.config/vault/approles/reference-api/`
2. On startup, the application reads these credentials from `/vault-approles/reference-api/`
3. Exchanges `role-id` and `secret-id` for a Vault client token via `/v1/auth/approle/login`
4. Uses the obtained token (hvs. prefix) for all subsequent Vault operations
5. If AppRole authentication fails, falls back to `VAULT_TOKEN` environment variable

**Configuration:**
```python
# app/config.py
VAULT_APPROLE_DIR: str = os.getenv("VAULT_APPROLE_DIR", "/vault-approles/reference-api")
```

**Docker Compose Setup:**
```yaml
volumes:
  - ${HOME}/.config/vault/approles/reference-api:/vault-approles/reference-api:ro
environment:
  VAULT_ADDR: ${VAULT_ADDR:-http://vault:8200}
  # Note: No VAULT_TOKEN - forces AppRole authentication
```

**Fallback Mechanism:**
```python
# app/services/vault.py
def __init__(self):
    if settings.VAULT_APPROLE_DIR and os.path.exists(settings.VAULT_APPROLE_DIR):
        try:
            self.vault_token = self._login_with_approle()
            logger.info("Successfully authenticated to Vault using AppRole")
        except Exception as e:
            logger.warning(f"AppRole authentication failed: {e}, falling back to token-based auth")
            self.vault_token = settings.VAULT_TOKEN
    else:
        logger.info("Using token-based authentication (AppRole directory not found)")
        self.vault_token = settings.VAULT_TOKEN
```

**Benefits:**
- More secure than root tokens (limited permissions, renewable, revocable)
- Follows HashiCorp's recommended authentication method for applications
- No root token exposure in environment variables
- Automatic fallback ensures compatibility with development setups
- Token rotation without container restart (when using wrapped secret-id)

### 2. Rate Limiting
- **IP-based Limiting**: Using slowapi (Flask-Limiter port)
- **Configurable Rates**:
  - General endpoints: 100 requests/minute
  - Metrics endpoint: 1000 requests/minute
  - Health checks: 200 requests/minute
- **429 Responses**: Returns `Retry-After` header

### 3. Request Validation
- **Content-Type Validation**: POST/PUT/PATCH requests must have valid content type
- **Request Size Limits**: 10MB maximum request body
- **Input Sanitization**: Regex pattern validation on all inputs
- **Allowed Content Types**: `application/json`, `application/x-www-form-urlencoded`, `multipart/form-data`, `text/plain`

### 4. CORS Security
- **Environment-Aware**:
  - **Development** (`DEBUG=true`): Allow all origins (`*`)
  - **Production** (`DEBUG=false`): Explicit origin whitelist
- **Allowed Origins** (production):
  - `http://localhost:3000` (React/Next.js)
  - `http://localhost:8000` (self)
  - `http://localhost:8080` (common dev)
- **Credentials**: Only with explicit origins (not with `*`)
- **Preflight Caching**: 600 seconds (10 minutes)

### 5. Circuit Breakers
- **Service Protection**: All external services (Vault, databases, Redis, RabbitMQ)
- **Configuration**:
  - Failure threshold: 5 consecutive failures
  - Reset timeout: 60 seconds
  - States: CLOSED → OPEN → HALF_OPEN → CLOSED
- **Benefits**: Prevents cascading failures, improves system stability

### 6. Error Handling
- **Structured Responses**: Consistent error format across all endpoints
- **Request Correlation**: Every request has unique request ID
- **Debug Mode Control**: Stack traces only in DEBUG mode
- **Sensitive Data Protection**: No credentials in error responses

---

## Middleware

### 1. Metrics Middleware (`metrics_middleware`)
**Purpose:** Request tracking, timing, and Prometheus metrics

**Functionality:**
- Generates unique request ID (UUID4)
- Tracks in-progress requests (gauge metric)
- Measures request duration (histogram)
- Counts total requests by status (counter)
- Structured JSON logging of all requests
- Adds `X-Request-ID` header to responses

**Metrics:**
- `http_requests_total{method, endpoint, status}`
- `http_request_duration_seconds{method, endpoint}`
- `http_requests_in_progress{method, endpoint}`

---

### 2. Request Validation Middleware (`request_validation_middleware`)
**Purpose:** Validate request size and content type

**Validations:**
- **Request Size**: Maximum 10MB (returns 413 if exceeded)
- **Content-Type**: Required for POST/PUT/PATCH with body (returns 400 if missing)
- **Allowed Types**: JSON, form-urlencoded, multipart, text/plain (returns 415 if invalid)

**Exemptions:**
- GET, HEAD, OPTIONS requests
- `/metrics`, `/docs`, `/redoc`, `/openapi.json`
- `/health/*` endpoints

---

### 3. Cache Middleware (via `cache_manager`)
**Purpose:** Automatic response caching with Redis backend

**Features:**
- **Cache Key Generation**: Based on function, path params, and query params
- **Long Key Hashing**: MD5 hash for keys > 200 characters
- **TTL Configuration**: Configurable per endpoint (30s to 5min typical)
- **Pattern Invalidation**: Wildcard-based cache clearing
- **Metrics**: Tracks hits, misses, and invalidations

**Cache Strategy:**
- Vault endpoints: 5 minute TTL
- Health checks: 30 second TTL
- Other endpoints: No caching (unless explicitly configured)

---

### 4. Circuit Breaker Middleware (per-service)
**Purpose:** Prevent cascading failures across services

**Protected Services:**
- `vault_breaker` - Vault API calls
- `postgres_breaker` - PostgreSQL connections
- `mysql_breaker` - MySQL connections
- `mongodb_breaker` - MongoDB connections
- `redis_breaker` - Redis operations
- `rabbitmq_breaker` - RabbitMQ connections

**Behavior:**
- **CLOSED**: Normal operation, all requests pass through
- **OPEN**: After 5 failures, circuit opens, all requests fail immediately
- **HALF_OPEN**: After 60s timeout, allow limited requests to test recovery
- **Recovery**: On success in HALF_OPEN, circuit closes

**Metrics:**
- `circuit_breaker_opened_total{service}`
- `circuit_breaker_half_open_total{service}`
- `circuit_breaker_closed_total{service}`
- `circuit_breaker_failures_total{service}`

---

### 5. Exception Handlers (`register_exception_handlers`)
**Purpose:** Centralized error handling and formatting

**Handlers:**
- `BaseAPIException` - All custom exceptions
- `ServiceUnavailableError` - Service outages with retry suggestions
- `RequestValidationError` - Pydantic validation errors (422)
- `HTTPException` - FastAPI/Starlette HTTP exceptions
- `Exception` - Catch-all for unhandled errors (500)

**Response Format:**
```json
{
  "error": "VaultUnavailableError",
  "message": "Vault service is currently unavailable",
  "status_code": 503,
  "details": {
    "service": "vault",
    "secret_path": "postgres"
  },
  "request_id": "abc-123-def-456"
}
```

---

## Monitoring & Observability

### 1. Structured Logging
**Format:** JSON (python-json-logger)

**Log Fields:**
- `asctime`: Timestamp
- `name`: Logger name
- `levelname`: Log level (INFO, ERROR, etc.)
- `message`: Log message
- `request_id`: Request correlation ID
- `method`: HTTP method
- `path`: Request path
- `status_code`: Response status
- `duration_ms`: Request duration in milliseconds

**Example Log Entry:**
```json
{
  "asctime": "2025-10-27 12:34:56,789",
  "name": "__main__",
  "levelname": "INFO",
  "message": "HTTP request completed",
  "request_id": "abc-123-def-456",
  "method": "GET",
  "path": "/health/all",
  "status_code": 200,
  "duration_ms": 45.23
}
```

---

### 2. Prometheus Metrics
Exposed at `/metrics` in Prometheus text format.

**HTTP Metrics:**
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",endpoint="/health/all",status="200"} 42.0

# HELP http_request_duration_seconds HTTP request latency
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",endpoint="/health/all",le="0.005"} 10.0
http_request_duration_seconds_bucket{method="GET",endpoint="/health/all",le="0.01"} 20.0
http_request_duration_seconds_bucket{method="GET",endpoint="/health/all",le="0.025"} 30.0
http_request_duration_seconds_sum{method="GET",endpoint="/health/all"} 1.234
http_request_duration_seconds_count{method="GET",endpoint="/health/all"} 42.0

# HELP http_requests_in_progress HTTP requests in progress
# TYPE http_requests_in_progress gauge
http_requests_in_progress{method="GET",endpoint="/health/all"} 2.0
```

**Cache Metrics:**
```
cache_hits_total{endpoint="/examples/vault/secret/postgres"} 15.0
cache_misses_total{endpoint="/examples/vault/secret/postgres"} 3.0
cache_invalidations_total{pattern="cache:*"} 1.0
```

**Circuit Breaker Metrics:**
```
circuit_breaker_opened_total{service="vault"} 0.0
circuit_breaker_half_open_total{service="vault"} 0.0
circuit_breaker_closed_total{service="vault"} 0.0
circuit_breaker_failures_total{service="vault"} 0.0
```

---

### 3. Request Tracing
- **Request ID**: UUID4 generated per request
- **Propagation**: Stored in `request.state.request_id`
- **Response Header**: `X-Request-ID` added to all responses
- **Error Correlation**: Included in error responses and logs
- **Log Correlation**: All log entries tagged with request ID

---

## Quick Start

### Running in Docker (Recommended)

The application is included in the main `docker-compose.yml`:

```bash
# From repository root
./devstack.sh start

# Application available at:
# - HTTP:  http://localhost:8000
# - HTTPS: https://localhost:8443
# - Docs:  http://localhost:8000/docs
```

### Access the API

```bash
# Root endpoint (API info)
curl http://localhost:8000/

# Check all services health
curl http://localhost:8000/health/all

# Get credentials from Vault (passwords masked)
curl http://localhost:8000/examples/vault/secret/postgres

# Test PostgreSQL connection
curl http://localhost:8000/examples/database/postgres/query

# Use Redis cache
curl -X POST "http://localhost:8000/examples/cache/mykey?value=hello&ttl=60"
curl http://localhost:8000/examples/cache/mykey

# View Prometheus metrics
curl http://localhost:8000/metrics
```

---

## Development

### Local Development (Without Docker)

```bash
cd reference-apps/fastapi

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/vault-token.txt)
export DEBUG=true

# Run the application
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

**Development Features:**
- Hot reload on code changes
- DEBUG mode enables:
  - CORS `*` (allow all origins)
  - Stack traces in error responses
  - Detailed logging

---

## Testing

### Running Tests

```bash
# From FastAPI directory
cd reference-apps/fastapi

# Run all tests
pytest tests/ -v

# Run with coverage
pytest tests/ --cov=app --cov-report=html --cov-report=term

# Run specific test file
pytest tests/test_vault_service.py -v

# Run specific test
pytest tests/test_vault_service.py::TestVaultClientGetSecret::test_get_secret_success -v
```

### Test Suite

**Total: 254 tests** (178 executed unit tests, 76 skipped integration tests)

**Test Categories:**
- **Unit Tests (178)**: Mock external dependencies, fast execution
- **Integration Tests (76)**: Require running infrastructure, skipped in CI

**Coverage: 84.39%** (exceeds 80% requirement)

**Test Files:**
- `test_caching.py` - Cache middleware and operations (23 tests)
- `test_circuit_breaker.py` - Circuit breaker behavior (10 tests)
- `test_cors.py` - CORS configuration (13 tests)
- `test_database_demo.py` - Database integration (9 tests, 6 skipped)
- `test_exception_handlers.py` - Exception handling (35 tests)
- `test_exceptions.py` - Exception hierarchy (20 tests)
- `test_health_routers.py` - Health checks (18 tests)
- `test_rate_limiting.py` - Rate limiting (8 tests)
- `test_redis_cluster.py` - Redis cluster operations (15 tests, 10 skipped)
- `test_request_validation.py` - Input validation (15 tests)
- `test_routers_unit.py` - Router unit tests (30+ tests)
- `test_vault_service.py` - Vault client (17 tests)

**Test Markers:**
- `@pytest.mark.unit` - Unit tests
- `@pytest.mark.integration` - Integration tests (require infrastructure)
- `@pytest.mark.asyncio` - Async tests
- `@pytest.mark.cache` - Cache-related tests

---

## Environment Variables

### Required Variables

```bash
# Vault Configuration
VAULT_ADDR=http://vault:8200           # Vault API address
VAULT_APPROLE_DIR=/vault-approles/reference-api  # AppRole credentials directory (preferred)
# OR
VAULT_TOKEN=<your-token>               # Vault authentication token (fallback)

# Service Endpoints (Docker network names)
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
MYSQL_HOST=mysql
MYSQL_PORT=3306
MONGODB_HOST=mongodb
MONGODB_PORT=27017
REDIS_HOST=redis-1
REDIS_PORT=6379
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672

# Redis Cluster Nodes (comma-separated)
REDIS_NODES=redis-1:6379,redis-2:6379,redis-3:6379
```

**Note:** The application prefers AppRole authentication over token-based authentication. If `VAULT_APPROLE_DIR` exists and contains valid credentials, it will be used. Otherwise, it falls back to `VAULT_TOKEN`.

### Optional Variables

```bash
# Application Settings
DEBUG=false                            # Enable debug mode (default: false)
APP_NAME="DevStack Core Reference API"
```

### Docker Compose Configuration

When running in Docker Compose, these are set automatically via `docker-compose.yml`:

```yaml
environment:
  VAULT_ADDR: ${VAULT_ADDR:-http://vault:8200}
  VAULT_TOKEN: ${VAULT_TOKEN}
  POSTGRES_HOST: postgres
  POSTGRES_PORT: 5432
  MYSQL_HOST: mysql
  MYSQL_PORT: 3306
  MONGODB_HOST: mongodb
  MONGODB_PORT: 27017
  REDIS_HOST: redis-1
  REDIS_PORT: 6379
  RABBITMQ_HOST: rabbitmq
  RABBITMQ_PORT: 5672
```

---

## Integration Patterns

### 1. Fetching Secrets from Vault

```python
from app.services.vault import vault_client

# Get all credentials for a service
creds = await vault_client.get_secret("postgres")
user = creds.get("user")
password = creds.get("password")

# Get specific key
password = await vault_client.get_secret("postgres", key="password")
```

**Error Handling:**
```python
from app.exceptions import VaultUnavailableError, ResourceNotFoundError

try:
    creds = await vault_client.get_secret("postgres")
except ResourceNotFoundError:
    # Secret doesn't exist in Vault
    pass
except VaultUnavailableError as e:
    # Vault is down, sealed, or connection failed
    # Circuit breaker may be open
    pass
```

---

### 2. Database Connections with Circuit Breaker

```python
import asyncpg
from app.services.vault import vault_client
from app.middleware.circuit_breaker import postgres_breaker

@postgres_breaker
async def query_database():
    # Fetch credentials from Vault
    creds = await vault_client.get_secret("postgres")

    # Connect to PostgreSQL
    conn = await asyncpg.connect(
        host="postgres",
        port=5432,
        user=creds.get("user"),
        password=creds.get("password"),
        database=creds.get("database")
    )

    # Execute query
    result = await conn.fetch("SELECT * FROM users")
    await conn.close()

    return result
```

**Circuit Breaker Protection:**
- First 5 failures: Requests continue
- After 5 failures: Circuit opens, requests fail immediately with `CircuitBreakerError`
- After 60 seconds: Circuit enters HALF_OPEN, allows test request
- On success: Circuit closes, normal operation resumes

---

### 3. Redis Caching

```python
import redis.asyncio as redis
from app.services.vault import vault_client

async def get_redis_client() -> redis.Redis:
    """Create Redis client with Vault credentials"""
    creds = await vault_client.get_secret("redis-1")

    return redis.Redis(
        host="redis-1",
        port=6379,
        password=creds.get("password"),
        decode_responses=True,
        socket_timeout=5
    )

# Usage
client = await get_redis_client()
await client.setex("session:123", 3600, "user_data")  # 1 hour TTL
value = await client.get("session:123")
await client.close()
```

---

### 4. RabbitMQ Messaging

```python
import aio_pika
import json
from app.services.vault import vault_client
from app.middleware.circuit_breaker import rabbitmq_breaker

@rabbitmq_breaker
async def publish_message(queue_name: str, message: dict):
    """Publish message to RabbitMQ queue"""
    # Get credentials from Vault
    creds = await vault_client.get_secret("rabbitmq")

    # Build connection URL
    url = f"amqp://{creds.get('user')}:{creds.get('password')}@rabbitmq:5672/{creds.get('vhost', '')}"

    # Connect and publish
    connection = await aio_pika.connect_robust(url)
    channel = await connection.channel()

    # Declare durable queue
    await channel.declare_queue(queue_name, durable=True)

    # Publish message
    await channel.default_exchange.publish(
        aio_pika.Message(
            body=json.dumps(message).encode(),
            delivery_mode=aio_pika.DeliveryMode.PERSISTENT
        ),
        routing_key=queue_name
    )

    await connection.close()
```

---

### 5. Response Caching Decorator

```python
from fastapi_cache.decorator import cache

@router.get("/expensive-operation")
@cache(expire=300)  # Cache for 5 minutes
async def expensive_operation():
    # This operation result will be cached
    result = await perform_expensive_computation()
    return result
```

**Cache Key Generation:**
- Automatically includes: function name, path parameters, query parameters
- Keys > 200 chars are hashed (MD5)
- Supports custom namespace prefixes

---

## Technology Stack

### Core Framework
- **FastAPI** 0.104+ - Modern async Python web framework
- **Pydantic** 2.x - Data validation and serialization
- **Uvicorn** - ASGI server

### External Service Clients
- **asyncpg** - PostgreSQL async driver
- **aiomysql** - MySQL async driver
- **motor** - MongoDB async driver
- **redis[asyncio]** - Redis async client
- **aio-pika** - RabbitMQ async client
- **httpx** - Async HTTP client for Vault

### Middleware & Extensions
- **fastapi-cache2** - Response caching with Redis
- **slowapi** - Rate limiting (Flask-Limiter port)
- **pybreaker** - Circuit breaker pattern
- **prometheus-client** - Prometheus metrics
- **python-json-logger** - Structured JSON logging
- **starlette** - ASGI toolkit (FastAPI dependency)

### Testing
- **pytest** - Test framework
- **pytest-asyncio** - Async test support
- **pytest-cov** - Coverage reporting
- **pytest-mock** - Mocking utilities

---

## Notes

### Development vs Production

**This is a REFERENCE IMPLEMENTATION** designed for:
- Learning infrastructure integration patterns
- Testing service connectivity
- Demonstrating best practices
- Local development environment

**Not production-ready because:**
- No authentication/authorization beyond Vault token
- Limited error recovery strategies
- No request queuing or backpressure handling
- Simplified health checks
- Debug mode exposes stack traces
- No horizontal scaling considerations

### Production Recommendations

For production deployment, consider:
- **Authentication**: Add JWT/OAuth2 authentication
- **Authorization**: Implement role-based access control (RBAC)
- **API Gateway**: Use Kong, Traefik, or AWS API Gateway
- **Service Mesh**: Consider Istio or Linkerd for advanced traffic management
- **Observability**: Send logs to Loki/Elasticsearch, metrics to Prometheus
- **Secrets Rotation**: Implement automatic credential rotation
- **Connection Pooling**: Configure connection pool limits
- **Graceful Shutdown**: Handle SIGTERM for zero-downtime deployments
- **Health Checks**: Add readiness and liveness probes for Kubernetes
- **TLS Everywhere**: Enable TLS for all inter-service communication

---

## See Also

- **Main Infrastructure**: [../../README.md](../../README.md)
- **Vault Security**: [../../docs/VAULT_SECURITY.md](../../docs/VAULT_SECURITY.md)
- **Test Documentation**: [../../tests/README.md](../../tests/README.md)
- **Test Coverage Report**: [../../tests/TEST_COVERAGE.md](../../tests/TEST_COVERAGE.md)
- **Docker Compose Config**: [../../docker-compose.yml](../../docker-compose.yml)

---

## License

This reference application is part of the DevStack Core project. See the main repository for license information.

## Contributing

This is a reference implementation. For contributions, improvements, or issues, please refer to the [main DevStack Core repository](https://github.com/NormB/devstack-core) and see our [Contributing Guide](../../.github/CONTRIBUTING.md) for detailed instructions.
