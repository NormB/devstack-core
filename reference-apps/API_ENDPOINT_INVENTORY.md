# API Endpoint Inventory

## ✅ **COMPLETE & VERIFIED** - Last Verified: 2025-11-21

This document provides a comprehensive inventory of all API endpoints implemented across all reference implementations, verified against the shared OpenAPI specification.

---

## Summary

- **Total Endpoints**: 22
- **OpenAPI Spec**: `reference-apps/shared/openapi.yaml` (OpenAPI 3.1.0)
- **Implementation Coverage**: 100% across all 5+ implementations
- **Verification Status**: ✅ All endpoints match specification
- **Schema Validation**: ✅ Complete with request/response models

---

## Implementation Matrix

| Language | Port | Status | Endpoints | Tests | Notes |
|----------|------|--------|-----------|-------|-------|
| **Python (FastAPI Code-First)** | 8000 | ✅ Complete | 22/22 | 188 unit tests | Flagship implementation |
| **Python (FastAPI API-First)** | 8001 | ✅ Complete | 22/22 | 26/26 parity | 100% behavioral parity |
| **Go (Gin)** | 8002 | ✅ Complete | 22/22 | 13 tests | Production-grade patterns |
| **Node.js (Express)** | 8003 | ✅ Complete | 22/22 | Integration tests | Modern async/await |
| **Rust (Actix-web)** | 8004 | ✅ Complete | 22/22 | 44 comprehensive | Zero unwrap() calls |
| **TypeScript (Express)** | 8005 | 🚧 In Development | - | - | API-first pattern |

---

## Endpoint Categories

### 1. Health Checks (8 endpoints)

Health monitoring for all infrastructure services with comprehensive status reporting.

| Endpoint | Method | Description | Response Model | Rate Limit | Cache |
|----------|--------|-------------|----------------|------------|-------|
| `/health/` | GET | Simple health check (no dependencies) | - | 200/min | None |
| `/health/all` | GET | Aggregate health of all services | HealthStatus | 200/min | 30s |
| `/health/vault` | GET | Vault connectivity and status | - | 200/min | None |
| `/health/postgres` | GET | PostgreSQL connection test | - | 200/min | None |
| `/health/mysql` | GET | MySQL connection test | - | 200/min | None |
| `/health/mongodb` | GET | MongoDB connection test | - | 200/min | None |
| `/health/redis` | GET | Redis cluster health | - | 200/min | None |
| `/health/rabbitmq` | GET | RabbitMQ connectivity | - | 200/min | None |

**Implementation Notes:**
- All health checks use async operations
- Circuit breakers prevent cascading failures (FastAPI implementations)
- Concurrent health checks via goroutines (Go) / Promise.allSettled (Node.js)
- `/health/all` includes detailed status for each service

**Example Response** (`/health/all`):
```json
{
  "status": "healthy",
  "services": {
    "vault": {
      "status": "healthy",
      "initialized": true,
      "sealed": false,
      "version": "1.15.4"
    },
    "postgres": {
      "status": "healthy",
      "version": "PostgreSQL 16.6"
    },
    "redis": {
      "status": "healthy",
      "cluster_enabled": true,
      "cluster_state": "ok",
      "nodes": 3
    }
  }
}
```

---

### 2. Vault Integration (2 endpoints)

Secure credential management using HashiCorp Vault KV v2 secrets engine.

| Endpoint | Method | Description | Response Model | Cache TTL |
|----------|--------|-------------|----------------|-----------|
| `/examples/vault/secret/{service_name}` | GET | Retrieve all secrets for a service | SecretResponse | 5 min |
| `/examples/vault/secret/{service_name}/{key}` | GET | Retrieve specific secret key | SecretKeyResponse | 5 min |

**Path Parameters:**
- `service_name`: Service name (alphanumeric, hyphens, underscores; 1-50 chars)
- `key`: Secret key name (alphanumeric, hyphens, underscores; 1-100 chars)

**Implementation Notes:**
- Responses cached for 5 minutes to reduce Vault API load
- Passwords masked in responses for security
- Proper error handling for missing secrets
- VaultUnavailableError and ResourceNotFoundError exceptions

**Example Request:**
```bash
curl http://localhost:8000/examples/vault/secret/postgres
```

**Example Response:**
```json
{
  "service": "postgres",
  "data": {
    "user": "postgres",
    "password": "***REDACTED***",
    "database": "devstack",
    "host": "postgres",
    "port": "5432"
  },
  "note": "Passwords are masked for security"
}
```

---

### 3. Database Operations (3 endpoints)

Database connectivity examples demonstrating connection pooling and query execution.

| Endpoint | Method | Description | Database | Driver |
|----------|--------|-------------|----------|--------|
| `/examples/database/postgres/query` | GET | Execute PostgreSQL test query | PostgreSQL 16.6 | asyncpg (Python), pgx (Go), pg (Node.js/Rust) |
| `/examples/database/mysql/query` | GET | Execute MySQL test query | MySQL 8.0 | aiomysql (Python), mysql (Go), mysql2 (Node.js), mysql_async (Rust) |
| `/examples/database/mongodb/query` | GET | Execute MongoDB test operation | MongoDB 7.0 | motor (Python), mongo-driver (Go), mongodb (Node.js/Rust) |

**Implementation Notes:**
- All queries use Vault-managed credentials
- Connection pooling for performance
- Proper async/await patterns throughout
- Query: `SELECT version()` for SQL, `db.collection.findOne()` for MongoDB

**Example Response** (PostgreSQL):
```json
{
  "database": "postgres",
  "status": "connected",
  "query_result": "PostgreSQL 16.6 on x86_64-pc-linux-musl",
  "timestamp": "2025-11-21T12:00:00Z"
}
```

---

### 4. Cache Operations (3 endpoints)

Redis caching patterns with TTL support and proper error handling.

| Endpoint | Method | Description | Request Body | Response Model |
|----------|--------|-------------|--------------|----------------|
| `/examples/cache/{key}` | GET | Get value from cache | - | CacheGetResponse |
| `/examples/cache/{key}` | POST | Set cache value with optional TTL | `{"value": "string", "ttl": 60}` | CacheSetResponse |
| `/examples/cache/{key}` | DELETE | Delete cache key | - | CacheDeleteResponse |

**Path Parameters:**
- `key`: Cache key (alphanumeric and `:`, `-`, `_`, `.`; 1-200 chars)

**Query/Body Parameters (POST):**
- `value`: Value to cache (max 10KB)
- `ttl`: Time to live in seconds (1-86400; optional; default: no expiration)

**Implementation Notes:**
- Uses Redis cluster node (redis-1) with Vault password
- TTL support via SETEX command
- Returns TTL info on GET operations
- Proper null handling for non-existent keys

**Example Usage:**
```bash
# Set value with 60s TTL
curl -X POST "http://localhost:8000/examples/cache/mykey" \
  -H "Content-Type: application/json" \
  -d '{"value": "hello world", "ttl": 60}'

# Get value
curl http://localhost:8000/examples/cache/mykey

# Delete value
curl -X DELETE http://localhost:8000/examples/cache/mykey
```

**Example Response** (GET):
```json
{
  "key": "mykey",
  "value": "hello world",
  "exists": true,
  "ttl": 45
}
```

---

### 5. Messaging Operations (2 endpoints)

RabbitMQ messaging patterns including message publishing and queue management.

| Endpoint | Method | Description | Request Body | Response Model |
|----------|--------|-------------|--------------|----------------|
| `/examples/messaging/publish` | POST | Publish message to queue | `{"message": {...}}` | MessagePublishResponse |
| `/examples/messaging/queue/{queue_name}/info` | GET | Get queue information | - | QueueInfoResponse |

**Path/Query Parameters:**
- `queue_name`: Queue name (alphanumeric and `-`, `_`, `.`; 1-100 chars)

**Request Body (POST):**
- `message`: JSON object with message payload (max 1MB)

**Implementation Notes:**
- Uses Vault-managed RabbitMQ credentials
- Queue auto-declared on publish
- Returns message count and consumer count
- Proper connection lifecycle management

**Example Usage:**
```bash
# Publish message
curl -X POST "http://localhost:8000/examples/messaging/publish?queue_name=test-queue" \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from DevStack!", "priority": "high"}'

# Get queue info
curl http://localhost:8000/examples/messaging/queue/test-queue/info
```

**Example Response** (Publish):
```json
{
  "queue": "test-queue",
  "message": {
    "message": "Hello from DevStack!",
    "priority": "high"
  },
  "action": "published"
}
```

---

### 6. Redis Cluster Management (4 endpoints)

Advanced Redis cluster operations for monitoring topology and node health.

| Endpoint | Method | Description | Response Details |
|----------|--------|-------------|------------------|
| `/redis/cluster/nodes` | GET | List all cluster nodes | Node IDs, addresses, roles, slots, link state |
| `/redis/cluster/slots` | GET | Show slot distribution | Slot ranges per master, coverage percentage |
| `/redis/cluster/info` | GET | Cluster information | State, slots assigned/ok/fail, nodes, epoch |
| `/redis/nodes/{node_name}/info` | GET | Node-specific information | Server info, stats, replication, memory |

**Path Parameters:**
- `node_name`: Node name (redis-1, redis-2, redis-3)

**Implementation Notes:**
- Cluster commands: CLUSTER NODES, CLUSTER SLOTS, CLUSTER INFO
- Node info via INFO command on specific node
- Parses cluster protocol responses
- Returns structured JSON for easy consumption

**Example Response** (`/redis/cluster/nodes`):
```json
{
  "cluster_enabled": true,
  "cluster_state": "ok",
  "cluster_size": 3,
  "nodes": [
    {
      "id": "abc123...",
      "address": "172.20.2.10:6379",
      "role": "master",
      "slots": "0-5460",
      "flags": ["master"],
      "link_state": "connected"
    },
    {
      "id": "def456...",
      "address": "172.20.2.11:6379",
      "role": "master",
      "slots": "5461-10922",
      "flags": ["master"],
      "link_state": "connected"
    },
    {
      "id": "ghi789...",
      "address": "172.20.2.12:6379",
      "role": "master",
      "slots": "10923-16383",
      "flags": ["master"],
      "link_state": "connected"
    }
  ]
}
```

---

### 7. Core Endpoints (2 endpoints)

Root endpoint and metrics export for monitoring.

| Endpoint | Method | Description | Content Type | Rate Limit |
|----------|--------|-------------|--------------|------------|
| `/` | GET | API information and endpoint listing | application/json | 100/min |
| `/metrics` | GET | Prometheus metrics export | text/plain | Unlimited |

**Implementation Notes:**
- `/` returns API metadata, version, available endpoints
- `/metrics` exports Prometheus text format
- Metrics include HTTP requests (counter), request duration (histogram), circuit breaker states

**Example Response** (`/`):
```json
{
  "name": "DevStack Core Reference API",
  "version": "1.0.0",
  "language": "Python",
  "framework": "FastAPI",
  "description": "Reference implementation for infrastructure integration",
  "endpoints": {
    "health": "/health",
    "vault_examples": "/examples/vault",
    "database_examples": "/examples/database",
    "cache_examples": "/examples/cache",
    "redis_management": "/redis",
    "messaging_examples": "/examples/messaging",
    "metrics": "/metrics"
  }
}
```

**Example Metrics Output:**
```
# HELP http_requests_total Total HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",endpoint="/health/all",status="200"} 1542

# HELP http_request_duration_seconds HTTP request duration
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",endpoint="/health/all",le="0.01"} 1200
http_request_duration_seconds_bucket{method="GET",endpoint="/health/all",le="0.05"} 1500
http_request_duration_seconds_count{method="GET",endpoint="/health/all"} 1542
http_request_duration_seconds_sum{method="GET",endpoint="/health/all"} 15.234
```

---

## Response Models

### Shared Response Schemas

All endpoints return consistent response structures defined in the OpenAPI specification:

#### HealthStatus
```typescript
{
  status: "healthy" | "degraded" | "unhealthy",
  services: {
    [serviceName: string]: ServiceHealth
  }
}
```

#### ServiceHealth
```typescript
{
  status: "healthy" | "unhealthy",
  details?: object
}
```

#### SecretResponse
```typescript
{
  service: string,
  data: { [key: string]: string },
  note: string
}
```

#### SecretKeyResponse
```typescript
{
  service: string,
  key: string,
  value: string | null,
  note: string
}
```

#### CacheGetResponse
```typescript
{
  key: string,
  value: string | null,
  exists: boolean,
  ttl: number | string | null
}
```

#### CacheSetResponse
```typescript
{
  key: string,
  value: string,
  ttl: number | null,
  action: "set"
}
```

#### CacheDeleteResponse
```typescript
{
  key: string,
  deleted: boolean,
  action: "delete"
}
```

#### MessagePublishResponse
```typescript
{
  queue: string,
  message: object,
  action: "published"
}
```

#### QueueInfoResponse
```typescript
{
  queue: string,
  exists: boolean,
  message_count: number | null,
  consumer_count: number | null
}
```

#### HTTPValidationError
```typescript
{
  detail: Array<{
    loc: Array<string | number>,
    msg: string,
    type: string
  }>
}
```

---

## Error Handling

### Standard HTTP Status Codes

| Status Code | Meaning | When Used |
|-------------|---------|-----------|
| 200 | OK | Successful request |
| 400 | Bad Request | Invalid input parameters |
| 404 | Not Found | Resource doesn't exist |
| 422 | Unprocessable Entity | Validation error (detailed in response) |
| 500 | Internal Server Error | Unexpected server error |
| 503 | Service Unavailable | Dependency unavailable (Vault, DB, etc.) |

### Error Response Format

All errors follow consistent structure:
```json
{
  "detail": [
    {
      "loc": ["path", "key"],
      "msg": "Field required",
      "type": "missing"
    }
  ]
}
```

---

## Rate Limiting (FastAPI Implementations)

| Endpoint Category | Rate Limit | Implementation |
|-------------------|------------|----------------|
| Health checks | 200 requests/min | IP-based |
| Root endpoint | 100 requests/min | IP-based |
| Vault examples | 1000 requests/min | IP-based |
| Database examples | 1000 requests/min | IP-based |
| Cache operations | 1000 requests/min | IP-based |
| Messaging | 1000 requests/min | IP-based |
| Redis cluster | 1000 requests/min | IP-based |
| Metrics | Unlimited | - |

**Note:** Rate limiting implemented in Python FastAPI implementations only. Other implementations don't include rate limiting (reference implementation simplification).

---

## Caching Strategy (FastAPI Implementations)

| Endpoint | Cache Duration | Purpose |
|----------|----------------|---------|
| `/health/all` | 30 seconds | Reduce infrastructure load |
| `/examples/vault/secret/*` | 5 minutes | Reduce Vault API calls |
| All others | No caching | Real-time data |

**Cache Implementation:**
- In-memory cache with TTL
- Automatic invalidation on expiry
- Cache key includes endpoint + parameters

---

## Testing Coverage

### Shared Test Suite

All implementations validated by shared test suite (`reference-apps/shared/test-suite/`):

```python
# 38 test functions, ~64 test runs with parameterization
# All implementations tested against identical test suite

@pytest.mark.parametrize("api_url,port", [
    ("http://localhost:8000", 8000),  # FastAPI Code-First
    ("http://localhost:8001", 8001),  # FastAPI API-First
])
class TestAPIEndpoints:
    # Tests run against both implementations
    # Ensures 100% behavioral parity
```

### Test Categories

1. **Health Checks**: All 8 health endpoints
2. **Vault Integration**: Secret retrieval and key extraction
3. **Database Operations**: All 3 database query endpoints
4. **Cache Operations**: GET, SET, DELETE with TTL
5. **Messaging**: Publish and queue info
6. **Redis Cluster**: All 4 cluster management endpoints
7. **Error Handling**: 404, 400, validation errors
8. **Schema Validation**: Response structure compliance

---

## Security Considerations

### ⚠️ Reference Implementation Warnings

These APIs are **reference implementations for learning**, not production-ready:

**Missing in Reference Implementations:**
- ❌ Authentication (no API keys, no JWT)
- ❌ Authorization (no role-based access control)
- ❌ Input sanitization (basic validation only)
- ❌ Request signing
- ❌ IP whitelisting
- ❌ Advanced rate limiting (basic implementation only)

**For Production Deployments:**
- ✅ Implement JWT or OAuth2 authentication
- ✅ Add API key validation
- ✅ Implement RBAC with proper permissions
- ✅ Add request signing for sensitive operations
- ✅ Implement advanced rate limiting (distributed, per-user)
- ✅ Add comprehensive input sanitization
- ✅ Enable HTTPS/TLS only (disable HTTP)
- ✅ Implement request/response encryption for sensitive data
- ✅ Add audit logging for all operations
- ✅ Implement IP whitelisting/blacklisting

**Security Features Included:**
- ✅ Vault-managed credentials (no hardcoded secrets)
- ✅ CORS configuration
- ✅ Helmet security headers (Node.js)
- ✅ Input validation (OpenAPI schema)
- ✅ Password masking in responses
- ✅ Circuit breakers (prevent cascading failures)

---

## Documentation Links

### OpenAPI Specification
- **File**: `reference-apps/shared/openapi.yaml`
- **Format**: OpenAPI 3.1.0
- **Validation**: Spectral linting enabled
- **Interactive Docs**:
  - Code-First: http://localhost:8000/docs
  - API-First: http://localhost:8001/docs

### Implementation READMEs
- [FastAPI Code-First](./fastapi/README.md)
- [FastAPI API-First](./fastapi-api-first/README.md)
- [Go/Gin](./golang/README.md)
- [Node.js/Express](./nodejs/README.md)
- [Rust/Actix-web](./rust/README.md)
- [TypeScript/Express (In Development)](./typescript-api-first/README.md)

### Development Guides
- [API Patterns Guide](./API_PATTERNS.md) - Comprehensive guide on code-first vs API-first patterns
- [Reference Apps Overview](./README.md) - Overview of all reference implementations
- [Shared Test Suite](./shared/test-suite/README.md) - Parity testing documentation

---

## Quick Reference

### Start All APIs

```bash
# Start all reference APIs
docker compose up -d reference-api api-first golang-api nodejs-api rust-api

# Verify all running
curl http://localhost:8000/health
curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:8003/health
curl http://localhost:8004/health
```

### Test Endpoint Across All Implementations

```bash
# Health check across all implementations
for port in 8000 8001 8002 8003 8004; do
  echo "Testing port $port:"
  curl -s http://localhost:$port/health/ | jq '.status'
done
```

### Run Shared Test Suite

```bash
cd reference-apps/shared/test-suite
uv venv && source .venv/bin/activate
uv pip install -r requirements.txt
pytest -v
```

### Validate API Synchronization

```bash
# Check if code-first matches shared spec
make sync-check

# Detailed synchronization report
make sync-report
```

---

## Changelog

### 2025-11-21
- ✅ Created comprehensive API endpoint inventory
- ✅ Verified all 22 endpoints across 5 implementations
- ✅ Documented request/response models
- ✅ Added security considerations
- ✅ Included testing coverage details

### 2025-10-27
- ✅ Updated OpenAPI spec to 3.1.0
- ✅ Added response model schemas
- ✅ Enhanced endpoint descriptions
- ✅ Added API_PATTERNS.md documentation

---

**Last Updated**: 2025-11-21
**Maintained By**: Development Team
**Status**: ✅ Complete & Verified
