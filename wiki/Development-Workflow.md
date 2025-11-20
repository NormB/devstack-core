# Reference Applications

## Table of Contents

- [⚠️ Important: Not Production Code](#⚠️-important-not-production-code)
- [What Are Reference Apps?](#what-are-reference-apps)
- [Current Reference Apps](#current-reference-apps)
  - [1. FastAPI Code-First (Python)](#1-fastapi-code-first-python)
  - [2. FastAPI API-First (Python)](#2-fastapi-api-first-python)
  - [Comparing the Two Approaches](#comparing-the-two-approaches)
  - [Validation: Shared Test Suite](#validation-shared-test-suite)
  - [Release Notes](#release-notes)
- [How to Use Reference Apps](#how-to-use-reference-apps)
  - [As a Learning Tool](#as-a-learning-tool)
  - [As a Testing Tool](#as-a-testing-tool)
  - [As a Development Reference](#as-a-development-reference)
- [Key Integration Patterns](#key-integration-patterns)
  - [Fetching Secrets from Vault](#fetching-secrets-from-vault)
  - [Database Connections](#database-connections)
  - [Redis Cluster Operations](#redis-cluster-operations)
- [What Reference Apps Are NOT](#what-reference-apps-are-not)
- [What Reference Apps ARE](#what-reference-apps-are)
- [API Documentation](#api-documentation)
  - [3. Go Reference API](#3-go-reference-api)
  - [4. Node.js Reference API](#4-nodejs-reference-api)
  - [5. Rust Reference API (Partial Implementation)](#5-rust-reference-api-partial-implementation)
- [Future Reference Apps](#future-reference-apps)
- [Common Use Cases](#common-use-cases)
  - [1. Testing Infrastructure Setup](#1-testing-infrastructure-setup)
  - [2. Debugging Connection Issues](#2-debugging-connection-issues)
  - [3. Learning Integration Patterns](#3-learning-integration-patterns)
  - [4. Building Your Own App](#4-building-your-own-app)
- [Architecture](#architecture)
- [Testing](#testing)
- [Security Notes](#security-notes)
- [Getting Help](#getting-help)
- [Summary](#summary)

---

**Purpose:** Educational example applications demonstrating how to integrate with the DevStack Core infrastructure.

## ⚠️ Important: Not Production Code

These are **reference implementations** for learning and testing. They demonstrate best practices and integration patterns, but are **not intended for production use**.

## What Are Reference Apps?

Reference applications are **working code examples** that show you how to:

1. **Integrate with infrastructure services** - Vault, databases, Redis, RabbitMQ
2. **Follow best practices** - Async operations, error handling, configuration management
3. **Test infrastructure** - Health checks and inspection APIs
4. **Get started quickly** - Copy patterns into your own applications

## Current Reference Apps

We provide **two FastAPI implementations** demonstrating different API development patterns:

### 1. FastAPI Code-First (Python)

**Location:** `reference-apps/fastapi/`
**Port:** 8000 (HTTP), 8443 (HTTPS)
**Pattern:** Implementation drives documentation

**What it demonstrates:**
- ✅ Vault integration (fetching secrets securely)
- ✅ Database connectivity (PostgreSQL, MySQL, MongoDB)
- ✅ Redis caching and cluster operations
- ✅ RabbitMQ messaging patterns
- ✅ Health monitoring for all services
- ✅ HTTP/HTTPS dual-mode with Vault certificates
- ✅ Async/await patterns throughout
- ✅ Code-first development workflow

**Quick Start:**
```bash
# Start the code-first reference app
docker compose up -d reference-api

# View interactive API documentation
open http://localhost:8000/docs

# Check infrastructure health
curl http://localhost:8000/health/all

# Inspect Redis cluster
curl http://localhost:8000/redis/cluster/info
```

**Full Documentation:** See [fastapi/README.md](fastapi/README.md)

---

### 2. FastAPI API-First (Python)

**Location:** `reference-apps/fastapi-api-first/`
**Port:** 8001 (HTTP), 8444 (HTTPS)
**Pattern:** OpenAPI specification drives implementation

**What it demonstrates:**
- ✅ **Same infrastructure integrations** as code-first
- ✅ **Contract-first development** - OpenAPI spec defines the API
- ✅ **Generated models** from specification
- ✅ **100% behavioral parity** with code-first (validated by shared test suite)
- ✅ **API-first workflow** - design contract before implementation

**Quick Start:**
```bash
# Start the API-first reference app
docker compose up -d api-first

# View interactive API documentation
open http://localhost:8001/docs

# Check infrastructure health
curl http://localhost:8001/health/all

# Inspect Redis cluster
curl http://localhost:8001/redis/cluster/info
```

**Full Documentation:** See [fastapi-api-first/README.md](fastapi-api-first/README.md)

---

### Comparing the Two Approaches

Both implementations provide **identical functionality** but follow different development workflows:

| Aspect | Code-First (Port 8000) | API-First (Port 8001) |
|--------|------------------------|----------------------|
| **Starting Point** | Write Python code | Design OpenAPI spec |
| **Documentation** | Generated from code | Drives implementation |
| **Best For** | Rapid prototyping, internal APIs | External APIs, team coordination |
| **Changes Start In** | Python files | OpenAPI specification |
| **Development Speed** | Faster initial development | Slower start, faster collaboration |
| **Use Case** | MVP development, agile iterations | API contracts, microservices |

**Key Insight:** Both approaches are valid! The shared test suite validates that both implementations behave identically, proving you can achieve the same result with different workflows.

### Validation: Shared Test Suite

A comprehensive test suite validates **100% parity** between both implementations:

```bash
# Run parity tests (26 tests ensuring identical behavior)
cd reference-apps/shared/test-suite
pip install -r requirements.txt
pytest -v

# Expected: 26/26 tests passing
```

See [shared/test-suite/README.md](shared/test-suite/README.md) for details.

**What Gets Validated:**
- ✅ Identical endpoint paths
- ✅ Identical response structures
- ✅ Identical error handling
- ✅ Identical status codes
- ✅ Consistent OpenAPI specifications

### Release Notes

For details on both implementations, see [CHANGELOG.md](CHANGELOG.md) in this directory

## How to Use Reference Apps

### As a Learning Tool

```bash
# 1. Browse the code to see integration patterns
cat reference-apps/fastapi/app/services/vault.py
cat reference-apps/fastapi/app/routers/database_demo.py
cat reference-apps/fastapi/app/routers/redis_cluster.py

# 2. See working examples in the interactive docs
open http://localhost:8000/docs

# 3. Copy patterns into your own applications
# The code shows:
#   - How to fetch secrets from Vault
#   - How to connect to databases with Vault credentials
#   - How to handle errors gracefully
#   - How to structure async operations
```

### As a Testing Tool

```bash
# Check all infrastructure services are working
curl http://localhost:8000/health/all

# Verify Redis cluster is properly configured
curl http://localhost:8000/redis/cluster/info

# Test database connectivity
curl http://localhost:8000/examples/database/postgres/query

# Inspect cluster topology
curl http://localhost:8000/redis/cluster/nodes | jq '.nodes[].role'
```

### As a Development Reference

**Problem:** You need to add Redis caching to your application.

**Without reference app:**
- ❌ Read Redis docs
- ❌ Figure out authentication
- ❌ Debug connection issues
- ❌ Implement patterns from scratch

**With reference app:**
```bash
# 1. Verify Redis is working
curl http://localhost:8000/health/redis

# 2. See working example
cat reference-apps/fastapi/app/routers/cache_demo.py

# 3. Copy the pattern - it already shows:
#    - How to connect with Vault password
#    - How to handle errors
#    - How to set TTL
#    - Async/await patterns

# 4. Test it works
curl -X POST "http://localhost:8000/examples/cache/test?value=hello"
curl http://localhost:8000/examples/cache/test
```

## Key Integration Patterns

### Fetching Secrets from Vault

All reference apps demonstrate:

```python
from app.services.vault import vault_client

# Get all credentials for a service
creds = await vault_client.get_secret("postgres")
user = creds.get("user")
password = creds.get("password")
```

**Why this matters:**
- ✅ No hardcoded passwords
- ✅ Centralized secret management
- ✅ Credentials can be rotated without code changes

### Database Connections

```python
import asyncpg
from app.services.vault import vault_client

# Fetch credentials from Vault
creds = await vault_client.get_secret("postgres")

# Connect using Vault credentials
conn = await asyncpg.connect(
    host="postgres",
    user=creds.get("user"),
    password=creds.get("password"),
    database=creds.get("database")
)

# Execute query
result = await conn.fetch("SELECT * FROM users")
await conn.close()
```

**What you learn:**
- ✅ How to integrate Vault with databases
- ✅ Async database operations
- ✅ Connection management
- ✅ Error handling

### Redis Cluster Operations

```python
import redis.asyncio as redis
from app.services.vault import vault_client

# Get Redis credentials
creds = await vault_client.get_secret("redis-1")

# Connect to cluster
client = redis.Redis(
    host="redis-1",
    port=6379,
    password=creds.get("password"),
    decode_responses=True
)

# Use cache
await client.setex("key", 60, "value")  # Set with 60s TTL
value = await client.get("key")
await client.close()
```

**What you learn:**
- ✅ Redis cluster authentication
- ✅ Setting TTL for cache entries
- ✅ Async Redis operations

## What Reference Apps Are NOT

- ❌ **Not production-ready** - Missing security hardening, monitoring, scaling
- ❌ **Not feature-complete** - Focus on integration patterns, not business logic
- ❌ **Not performant at scale** - Simple implementations for learning
- ❌ **Not security-hardened** - Uses root Vault token for simplicity

## What Reference Apps ARE

- ✅ **Educational code** showing how to integrate services
- ✅ **Working examples** you can test immediately
- ✅ **Integration patterns** you can copy
- ✅ **Testing tools** to verify infrastructure
- ✅ **Starting points** for your own applications

## API Documentation

Each reference app provides interactive API documentation:

**Code-First (Port 8000):**
- **Swagger UI:** http://localhost:8000/docs
- **ReDoc:** http://localhost:8000/redoc
- **OpenAPI JSON:** http://localhost:8000/openapi.json

**API-First (Port 8001):**
- **Swagger UI:** http://localhost:8001/docs
- **ReDoc:** http://localhost:8001/redoc
- **OpenAPI JSON:** http://localhost:8001/openapi.json

Both implementations expose identical API endpoints with identical behavior.

### 3. Go Reference API

**Location:** `reference-apps/golang/`
**Port:** 8002 (HTTP), 8445 (HTTPS)
**Pattern:** Production-grade Go patterns with Gin framework

**What it demonstrates:**
- ✅ **Same infrastructure integrations** as Python implementations
- ✅ **Concurrency** - Goroutines for async operations
- ✅ **Context propagation** - Proper context.Context usage
- ✅ **Type safety** - Strong typing with comprehensive error handling
- ✅ **Graceful shutdown** - Signal handling for clean termination
- ✅ **Structured logging** - Logrus with request ID correlation

**Quick Start:**
```bash
# Start the Go reference API
docker compose up -d golang-api

# View API information
curl http://localhost:8002/

# Check infrastructure health
curl http://localhost:8002/health/all
```

**Full Documentation:** See [golang/README.md](golang/README.md)

---

### 4. Node.js Reference API

**Location:** `reference-apps/nodejs/`
**Port:** 8003 (HTTP), 8446 (HTTPS)
**Pattern:** Modern async/await patterns with Express

**What it demonstrates:**
- ✅ **Same infrastructure integrations** as other implementations
- ✅ **Async/await** - Modern JavaScript asynchronous patterns
- ✅ **Promise.allSettled** - Concurrent operations
- ✅ **Express middleware** - Modular request processing
- ✅ **Winston logging** - Structured logging with correlation IDs
- ✅ **Graceful shutdown** - Clean signal handling

**Quick Start:**
```bash
# Start the Node.js reference API
docker compose up -d nodejs-api

# View API information
curl http://localhost:8003/

# Check infrastructure health
curl http://localhost:8003/health/all
```

**Full Documentation:** See [nodejs/README.md](nodejs/README.md)

---

### 5. Rust Reference API (Partial Implementation)

**Location:** `reference-apps/rust/`
**Port:** 8004 (HTTP), 8447 (HTTPS)
**Pattern:** High-performance async with Actix-web (~40% complete)

**What it demonstrates:**
- ✅ **Actix-web framework** - Fast, async web framework with 4 endpoints
- ✅ **Type safety** - Rust's compile-time guarantees preventing runtime errors
- ✅ **Zero-cost abstractions** - Performance without overhead
- ✅ **Health checks** - Simple monitoring endpoints with Vault connectivity
- ✅ **Vault integration** - Service health checks and connectivity tests
- ✅ **CORS middleware** - Properly configured cross-origin resource sharing
- ✅ **Comprehensive testing** - 5 unit tests + 11 integration tests
- ✅ **Async/await patterns** - Modern Rust async programming with Tokio
- ✅ **CI/CD integration** - Automated linting (clippy) and formatting (rustfmt)

**Quick Start:**
```bash
# Start the Rust reference API
docker compose up -d rust-api

# View API information
curl http://localhost:8004/

# Check health
curl http://localhost:8004/health/
```

**Full Documentation:** See [rust/README.md](rust/README.md)

**Note:** This is a partial implementation (~40% complete) with comprehensive testing demonstrating core Rust/Actix-web patterns. While it doesn't include database/cache/messaging integrations, it provides a solid, production-ready foundation that can be extended following patterns from the Python, Go, or Node.js implementations.

---

## Future Reference Apps

The structure supports additional language/framework implementations:

```
reference-apps/
├── fastapi/          ✅ Python async patterns
├── fastapi-api-first/✅ Python API-first
├── golang/           ✅ Go with goroutines
├── nodejs/           ✅ Node.js with Express
├── rust/             ✅ Rust partial (Actix-web, ~40% complete)
├── typescript/       🔜 TypeScript API-first
└── spring-boot/      🔜 Java/Spring patterns
```

Each demonstrates the same integrations but in different languages.

## Common Use Cases

### 1. Testing Infrastructure Setup

```bash
# After setting up infrastructure
curl http://localhost:8000/health/all | jq '.'

# Verify all services are healthy
# {
#   "status": "healthy",
#   "services": {
#     "vault": {"status": "healthy"},
#     "postgres": {"status": "healthy"},
#     "redis": {"status": "healthy", "cluster_state": "ok"}
#   }
# }
```

### 2. Debugging Connection Issues

```bash
# Check which service is failing
curl http://localhost:8000/health/all | jq '.services[] | select(.status != "healthy")'

# Get detailed Redis cluster information
curl http://localhost:8000/redis/cluster/nodes

# Verify database connectivity
curl http://localhost:8000/examples/database/postgres/query
```

### 3. Learning Integration Patterns

```bash
# Browse the code
cd reference-apps/fastapi/app

# See Vault integration
cat services/vault.py

# See database patterns
cat routers/database_demo.py

# See Redis cluster inspection
cat routers/redis_cluster.py

# See health check implementation
cat routers/health.py
```

### 4. Building Your Own App

```bash
# 1. Copy the patterns
cp reference-apps/fastapi/app/services/vault.py your-app/

# 2. Adapt to your needs
# 3. Use the same integration approach
# 4. Test against the same infrastructure
```

## Architecture

Each reference app follows similar structure:

```
reference-apps/{language}/
├── app/
│   ├── main.py              # Application entry point
│   ├── config.py            # Environment configuration
│   ├── routers/             # API endpoints
│   │   ├── health.py        # Health checks
│   │   ├── {service}_demo.py # Integration examples
│   └── services/            # Reusable clients
│       └── vault.py         # Vault integration
├── tests/                   # Integration tests
├── Dockerfile              # Container build
├── requirements.txt        # Dependencies
└── README.md              # Detailed docs
```

## Testing

Each reference app includes test suites:

```bash
# Test FastAPI reference app
./tests/test-fastapi.sh

# Expected output:
# ✓ Container running
# ✓ HTTP/HTTPS endpoints accessible
# ✓ Redis Cluster APIs working
# ✓ Health checks functioning
# ✓ Service integrations operational
```

See [../tests/README.md](../tests/README.md) for comprehensive test documentation.

## Security Notes

Reference apps demonstrate integration patterns but **not production security**:

- ⚠️ Uses Vault root token (simplified for learning)
- ⚠️ No authentication/authorization on endpoints
- ⚠️ No rate limiting
- ⚠️ No input validation/sanitization
- ⚠️ Debug mode enabled

**For production:** Implement proper auth, use AppRole/JWT for Vault, add validation, monitoring, etc.

## Getting Help

**Documentation:**
- Main README: [../README.md](../README.md)
- Code-First README: [fastapi/README.md](fastapi/README.md)
- API-First README: [fastapi-api-first/README.md](fastapi-api-first/README.md)
- Shared Test Suite: [shared/test-suite/README.md](shared/test-suite/README.md)
- Release Notes: [CHANGELOG.md](CHANGELOG.md)
- Test Documentation: [../tests/README.md](../tests/README.md)

**Quick Links (Code-First):**
- Interactive API: http://localhost:8000/docs
- Health Checks: http://localhost:8000/health/all
- Redis Cluster: http://localhost:8000/redis/cluster/info

**Quick Links (API-First):**
- Interactive API: http://localhost:8001/docs
- Health Checks: http://localhost:8001/health/all
- Redis Cluster: http://localhost:8001/redis/cluster/info

## Summary

Reference apps are **educational tools** that:
- 📚 Show you how to integrate with infrastructure
- 🔍 Help you test and debug
- 🚀 Provide starting points for your applications
- ✅ Demonstrate best practices

**Remember:** These are learning resources, not production code. Use them to understand patterns, then build your own production-ready applications with proper security, monitoring, and error handling.
