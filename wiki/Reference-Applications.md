# Reference Applications

Complete guide to the six reference API implementations demonstrating infrastructure integration patterns across multiple programming languages.

## Table of Contents

- [Overview](#overview)
- [Available Implementations](#available-implementations)
- [Common Features](#common-features)
- [API Endpoints](#api-endpoints)
- [Getting Started](#getting-started)
- [Code Examples](#code-examples)
- [Testing](#testing)
- [API Patterns](#api-patterns)

## Overview

The reference applications are **production-ready examples** demonstrating how to integrate with all DevStack Core infrastructure components. They showcase:

- Language-agnostic patterns
- Best practices for each ecosystem
- Identical API contracts across implementations
- Comprehensive testing strategies

### Why Multiple Languages?

1. **Learn patterns** - See same concepts across different ecosystems
2. **Compare approaches** - Different languages, same problems
3. **Choose your stack** - Find what works for your team
4. **Validate consistency** - Parity tests ensure identical behavior

## Available Implementations

### 1. Python - FastAPI (Code-First)

**Port:** 8000 (HTTP), 8443 (HTTPS)
**Container:** `dev-reference-api` (172.20.0.100)
**Directory:** `reference-apps/fastapi/`

**Features:**
- OpenAPI spec auto-generated from code
- Type hints and Pydantic validation
- Async/await patterns
- Comprehensive test suite (254 tests)
- 84% code coverage

**Access:**
- Interactive docs: http://localhost:8000/docs
- OpenAPI spec: http://localhost:8000/openapi.json
- Health check: http://localhost:8000/health/all

**Quick start:**
```bash
docker compose up -d reference-api
curl http://localhost:8000/health/all
```

### 2. Python - FastAPI (API-First)

**Port:** 8001 (HTTP), 8444 (HTTPS)
**Container:** `dev-api-first` (172.20.0.104)
**Directory:** `reference-apps/fastapi-api-first/`

**Features:**
- OpenAPI spec is source of truth
- Code generated from specification
- Guaranteed API contract compliance
- Parity tests with code-first (64 tests)

**Access:**
- Interactive docs: http://localhost:8001/docs
- OpenAPI spec: http://localhost:8001/openapi.json
- Health check: http://localhost:8001/health/all

**Quick start:**
```bash
docker compose up -d api-first
curl http://localhost:8001/health/all
```

### 3. Go - Gin Framework

**Port:** 8002 (HTTP), 8445 (HTTPS)
**Container:** `dev-golang-api` (172.20.0.105)
**Directory:** `reference-apps/golang/`

**Features:**
- High-performance HTTP routing
- Concurrent request handling
- Structured logging
- Graceful shutdown

**Access:**
- Health check: http://localhost:8002/health/
- Vault info: http://localhost:8002/vault/info

**Quick start:**
```bash
docker compose up -d golang-api
curl http://localhost:8002/health/
```

### 4. Node.js - Express Framework

**Port:** 8003 (HTTP), 8446 (HTTPS)
**Container:** `dev-nodejs-api` (172.20.0.106)
**Directory:** `reference-apps/nodejs/`

**Features:**
- Modern async/await patterns
- Express middleware architecture
- Promise-based database clients
- Comprehensive error handling

**Access:**
- Health check: http://localhost:8003/health/
- Vault info: http://localhost:8003/vault/info

**Quick start:**
```bash
docker compose up -d nodejs-api
curl http://localhost:8003/health/
```

### 5. Rust - Actix-web Framework

**Port:** 8004 (HTTP), 8447 (HTTPS)
**Container:** `dev-rust-api` (172.20.0.107)
**Directory:** `reference-apps/rust/`

**Features:**
- High-performance async runtime
- Type-safe request handling
- Zero-cost abstractions
- Minimal resource footprint

**Access:**
- Health check: http://localhost:8004/health/
- Vault info: http://localhost:8004/vault/info

**Quick start:**
```bash
docker compose up -d rust-api
curl http://localhost:8004/health/
```

### 6. TypeScript - API-First (Scaffolding)

**Status:** Scaffolding only
**Directory:** `reference-apps/typescript-api-first/`

**Planned features:**
- TypeScript with strict typing
- OpenAPI code generation
- Similar to Python API-First approach

## Common Features

All reference applications demonstrate:

### Vault Integration
- Retrieving secrets from Vault KV store
- Dynamic credential fetching
- TLS certificate usage
- Health check integration

### Database Connections
- **PostgreSQL** - Relational data with connection pooling
- **MySQL** - Legacy database support
- **MongoDB** - Document storage patterns

### Caching
- **Redis Cluster** - Distributed caching
- Connection pooling
- Cluster-aware operations
- SET/GET/DELETE operations

### Messaging
- **RabbitMQ** - Queue management
- Publishing messages
- Queue inspection
- Connection management

### Observability
- Prometheus metrics export
- Structured logging
- Health check endpoints
- Request tracing

### Security
- TLS/HTTPS support
- Vault-managed certificates
- Secure credential handling
- CORS configuration

## API Endpoints

### Health Checks

All implementations provide:

```bash
GET /health/                    # Basic health
GET /health/all                 # All services (Python only)
GET /health/vault               # Vault status
GET /health/postgres            # PostgreSQL status
GET /health/mysql               # MySQL status
GET /health/mongodb             # MongoDB status
GET /health/redis               # Redis cluster status
GET /health/rabbitmq            # RabbitMQ status
```

### Vault Operations

```bash
GET  /vault/info                # Vault connection info
GET  /vault/status              # Vault seal status
POST /vault/secret              # Store secret
GET  /vault/secret/{key}        # Retrieve secret
```

### Database Demo

```bash
GET  /database/postgres/test    # Test PostgreSQL connection
GET  /database/mysql/test       # Test MySQL connection
GET  /database/mongodb/test     # Test MongoDB connection
```

### Redis Cluster

```bash
GET    /redis/cluster/info      # Cluster information
GET    /redis/cluster/nodes     # Node status
POST   /redis/cache             # Store value
GET    /redis/cache/{key}       # Retrieve value
DELETE /redis/cache/{key}       # Delete value
```

### Messaging

```bash
POST /messaging/publish         # Publish to queue
GET  /messaging/queue/{name}    # Queue information
```

### Cache Demo

```bash
POST   /cache/set               # Cache a value
GET    /cache/get/{key}         # Retrieve cached value
DELETE /cache/delete/{key}      # Delete cached value
GET    /cache/keys              # List all keys
```

## Getting Started

### Start All Reference Apps

```bash
# Start all at once
docker compose up -d reference-api api-first golang-api nodejs-api rust-api

# Or individually
docker compose up -d reference-api
docker compose up -d golang-api
```

### Test Connectivity

```bash
# Test all APIs
for port in 8000 8001 8002 8003 8004; do
  echo "Testing port $port..."
  curl -s http://localhost:$port/health/ | jq .
done
```

### View Interactive Documentation

**Python implementations only:**

- Code-First: http://localhost:8000/docs
- API-First: http://localhost:8001/docs

Provides:
- Try-it-now interface
- Request/response examples
- Schema definitions
- Authentication testing

## Code Examples

### Vault Integration

**Python (FastAPI):**
```python
from app.services.vault import VaultService

vault = VaultService()
secret = await vault.get_secret("postgres")
password = secret["password"]
```

**Go:**
```go
import "github.com/hashicorp/vault/api"

client, _ := api.NewClient(&api.Config{
    Address: os.Getenv("VAULT_ADDR"),
})
secret, _ := client.Logical().Read("secret/data/postgres")
password := secret.Data["data"].(map[string]interface{})["password"]
```

**Node.js:**
```javascript
const vault = require('node-vault')({
  endpoint: process.env.VAULT_ADDR,
  token: process.env.VAULT_TOKEN
});
const secret = await vault.read('secret/data/postgres');
const password = secret.data.data.password;
```

### Database Connection

**Python (FastAPI):**
```python
from app.db.postgres import get_db_connection

conn = get_db_connection()
cursor = conn.cursor()
cursor.execute("SELECT version()")
version = cursor.fetchone()
```

**Go:**
```go
import "database/sql"
import _ "github.com/lib/pq"

db, _ := sql.Open("postgres", connString)
var version string
db.QueryRow("SELECT version()").Scan(&version)
```

**Node.js:**
```javascript
const { Pool } = require('pg');
const pool = new Pool({ connectionString });
const result = await pool.query('SELECT version()');
const version = result.rows[0].version;
```

### Redis Cluster

**Python (FastAPI):**
```python
from redis.cluster import RedisCluster

rc = RedisCluster(
    host='redis-1',
    port=6379,
    password=redis_password
)
rc.set('key', 'value')
value = rc.get('key')
```

**Go:**
```go
import "github.com/redis/go-redis/v9"

rdb := redis.NewClusterClient(&redis.ClusterOptions{
    Addrs: []string{"redis-1:6379", "redis-2:6379", "redis-3:6379"},
    Password: redisPassword,
})
rdb.Set(ctx, "key", "value", 0)
```

## Testing

### Unit Tests

**Python FastAPI:**
```bash
# Run inside container
docker exec dev-reference-api pytest tests/ -v

# 254 tests, 84% coverage
```

### Parity Tests

Validate that both Python implementations have identical APIs:

```bash
# From host (requires uv)
cd reference-apps/shared/test-suite
uv run pytest -v

# 64 tests validating consistency
```

### Integration Tests

```bash
# Test all infrastructure
./tests/run-all-tests.sh

# Test specific API
./tests/test-fastapi.sh
```

## API Patterns

### Code-First vs API-First

**Code-First (FastAPI):**
- Write Python code with type hints
- OpenAPI spec auto-generated
- Fast development iteration
- Natural Python patterns

**API-First (FastAPI):**
- Design OpenAPI spec first
- Code generated from spec
- Contract-first development
- Guaranteed API compliance

**Both approaches:**
- Result in identical APIs
- Pass same parity tests
- Support same features
- Use same infrastructure

See [API Patterns](API-Patterns) wiki page for detailed comparison.

### Best Practices Demonstrated

1. **Configuration Management**
   - Environment variables for config
   - Vault for secrets
   - Separate dev/prod settings

2. **Error Handling**
   - Structured exceptions
   - Consistent error responses
   - Proper status codes

3. **Connection Management**
   - Connection pooling
   - Graceful shutdown
   - Retry logic

4. **Observability**
   - Health checks
   - Structured logging
   - Metrics export

5. **Security**
   - No hardcoded credentials
   - TLS support
   - Input validation

## Performance Comparison

Run benchmark suite:

```bash
./tests/performance-benchmark.sh
```

**Typical results (requests/second):**
- Rust: ~15,000 req/s
- Go: ~12,000 req/s
- Python FastAPI: ~5,000 req/s
- Node.js: ~8,000 req/s

**Note:** Numbers vary based on endpoint complexity and hardware.

## Next Steps

1. **Explore the code** - Browse `reference-apps/<language>/`
2. **Try the APIs** - Use interactive docs at http://localhost:8000/docs
3. **Run the tests** - See [Testing Guide](Testing-Guide)
4. **Build your own** - Use as templates for your applications
5. **Compare patterns** - See same problems solved differently

## See Also

- [Quick Start Guide](Quick-Start-Guide) - Get APIs running
- [API Patterns](API-Patterns) - Code-first vs API-first
- [Testing Guide](Testing-Guide) - Running and writing tests
- [Vault Integration](Vault-Integration) - Using Vault in your apps
