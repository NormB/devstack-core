# TypeScript API-First Reference Implementation

## Table of Contents

- [Overview](#overview)
- [Status](#status)
- [Features](#features)
  - [Core Capabilities](#core-capabilities)
  - [TypeScript-Specific Features](#typescript-specific-features)
- [Quick Start](#quick-start)
- [API Endpoints](#api-endpoints)
  - [Root](#root)
  - [Health Checks (`/health`)](#health-checks-health)
  - [Vault Integration (`/examples/vault`)](#vault-integration-examplesvault)
  - [Database Operations (`/examples/database`)](#database-operations-examplesdatabase)
  - [Caching (`/examples/cache`)](#caching-examplescache)
  - [Messaging (`/examples/messaging`)](#messaging-examplesmessaging)
  - [Metrics](#metrics)
- [Architecture](#architecture)
- [API-First Development](#api-first-development)
  - [OpenAPI Specification](#openapi-specification)
  - [Code Generation](#code-generation)
  - [Synchronization](#synchronization)
- [Key Integration Patterns](#key-integration-patterns)
  - [Fetching Secrets from Vault](#fetching-secrets-from-vault)
  - [Database Connections with Vault](#database-connections-with-vault)
  - [Redis Caching](#redis-caching)
- [Environment Variables](#environment-variables)
- [Development](#development)
  - [Prerequisites](#prerequisites)
  - [Local Development](#local-development)
  - [Testing](#testing)
  - [Type Checking](#type-checking)
  - [Linting](#linting)
- [Comparison with Other Implementations](#comparison-with-other-implementations)
- [What This Demonstrates](#what-this-demonstrates)
- [What This Is NOT](#what-this-is-not)
- [Security Notes](#security-notes)
- [Documentation Links](#documentation-links)
- [Client Examples](#client-examples)
  - [cURL](#curl)
  - [TypeScript/JavaScript](#typescriptjavascript)
  - [Python](#python)
- [Roadmap](#roadmap)
- [Summary](#summary)

---

**⚠️ This is a reference implementation for learning and testing. Not intended for production use.**

**📝 Note:** This implementation follows the **API-First** development approach where the OpenAPI specification is the source of truth, and server code is generated from it.

A TypeScript/Express application demonstrating API-First development patterns with the DevStack Core infrastructure stack, featuring full type safety and code generation from OpenAPI specifications.

## Overview

This reference application demonstrates how to build a fully type-safe API using TypeScript with an **API-First** approach:
1. Define the API contract in OpenAPI 3.0 specification
2. Generate TypeScript server stubs from the spec
3. Implement business logic with full type safety
4. Validate requests/responses against the spec at runtime
5. Maintain synchronization between spec and implementation

## Status

**Current Status:** 🚧 **In Development / Experimental**

This implementation is actively being developed as a demonstration of API-First patterns in TypeScript. It is intended to complement the FastAPI API-First implementation and provide a Node.js/TypeScript perspective on contract-driven development.

**Completion Status:**
- ✅ Project structure defined
- ✅ OpenAPI specification scaffolding
- 🚧 Code generation pipeline (in progress)
- 🚧 Service implementations (in progress)
- 🚧 Tests (in progress)
- ⏳ Docker integration (planned)
- ⏳ Full infrastructure integration (planned)

## Features

### Core Capabilities
- **Vault Integration**: Secure credential fetching with typed responses
- **Database Connections**: PostgreSQL, MySQL, MongoDB with Vault credentials
- **Caching**: Redis cluster operations with type-safe keys/values
- **Messaging**: RabbitMQ message publishing with message schemas
- **Health Monitoring**: Comprehensive health checks for all services
- **Observability**: Prometheus metrics, structured logging
- **Security**: Helmet, CORS, request validation, TypeScript type safety

### TypeScript-Specific Features
- **Full Type Safety**: End-to-end type checking from API to database
- **OpenAPI Code Generation**: Auto-generate types and validators from spec
- **Interface-Based Design**: Clear separation of concerns
- **Compile-Time Validation**: Catch errors before runtime
- **IDE Integration**: Full autocomplete and type hints
- **Strict Mode**: Maximum TypeScript strictness enabled
- **API-First Workflow**: Specification-driven development

## Quick Start

```bash
# Start the TypeScript API-First reference API
docker compose up -d typescript-api

# Verify it's running
curl http://localhost:8005/

# Check infrastructure health
curl http://localhost:8005/health/all

# Test Vault integration
curl http://localhost:8005/examples/vault/secret/postgres
```

## API Endpoints

### Root
- `GET /` - API information and endpoint listing

### Health Checks (`/health`)
- `GET /health/` - Simple health check (no dependencies)
- `GET /health/all` - Aggregate health of all services
- `GET /health/vault` - Vault connectivity and status
- `GET /health/postgres` - PostgreSQL connection test
- `GET /health/mysql` - MySQL connection test
- `GET /health/mongodb` - MongoDB connection test
- `GET /health/redis` - Redis cluster health
- `GET /health/rabbitmq` - RabbitMQ connectivity

### Vault Integration (`/examples/vault`)
- `GET /examples/vault/secret/{serviceName}` - Fetch all secrets for a service
- `GET /examples/vault/secret/{serviceName}/{key}` - Fetch specific secret key

### Database Operations (`/examples/database`)
- `GET /examples/database/postgres/query` - PostgreSQL query example
- `GET /examples/database/mysql/query` - MySQL query example
- `GET /examples/database/mongodb/query` - MongoDB query example

### Caching (`/examples/cache`)
- `GET /examples/cache/{key}` - Get cached value
- `POST /examples/cache/{key}` - Set cached value (with optional TTL)
- `DELETE /examples/cache/{key}` - Delete cached value

### Messaging (`/examples/messaging`)
- `POST /examples/messaging/publish/{queue}` - Publish message to RabbitMQ queue

### Metrics
- `GET /metrics` - Prometheus metrics endpoint

## Architecture

```
reference-apps/typescript-api-first/
├── openapi/
│   └── spec.yaml              # OpenAPI 3.0 specification (source of truth)
├── src/
│   ├── generated/             # Auto-generated types and validators
│   │   ├── types.ts           # Request/response types
│   │   ├── validators.ts      # Runtime validators
│   │   └── routes.ts          # Route definitions
│   ├── services/              # Business logic implementations
│   │   ├── vault.service.ts   # Vault client wrapper
│   │   ├── postgres.service.ts
│   │   ├── mysql.service.ts
│   │   ├── mongodb.service.ts
│   │   ├── redis.service.ts
│   │   └── rabbitmq.service.ts
│   ├── controllers/           # Request handlers (thin layer)
│   │   ├── health.controller.ts
│   │   ├── vault.controller.ts
│   │   ├── database.controller.ts
│   │   ├── cache.controller.ts
│   │   └── messaging.controller.ts
│   ├── middleware/            # Express middleware
│   │   ├── logging.middleware.ts
│   │   ├── cors.middleware.ts
│   │   └── validation.middleware.ts
│   ├── config/
│   │   └── index.ts           # Environment configuration
│   ├── types/                 # Custom type definitions
│   │   └── index.ts
│   ├── utils/
│   │   └── logger.ts          # Winston logger setup
│   └── index.ts               # Application entry point
├── tests/                     # Test suite
│   ├── unit/
│   ├── integration/
│   └── api/
├── scripts/
│   └── generate.sh            # Run OpenAPI code generation
├── Dockerfile                 # Container build
├── tsconfig.json              # TypeScript configuration
├── package.json               # Dependencies
└── README.md                  # This file
```

## API-First Development

### OpenAPI Specification

The API contract is defined in `../shared/openapi.yaml`:

```yaml
openapi: 3.0.3
info:
  title: DevStack Core TypeScript API-First Reference
  version: 1.0.0
  description: API-First reference implementation with full type safety

paths:
  /health:
    get:
      summary: Simple health check
      responses:
        '200':
          description: Service is healthy
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/HealthResponse'
```

### Code Generation

Types and validators are auto-generated from the OpenAPI spec:

```bash
# Generate TypeScript types and validators
npm run generate

# Or manually
npx openapi-typescript ../shared/openapi.yaml -o src/generated/types.ts
```

Generated types provide full compile-time safety:

```typescript
import type { HealthResponse, VaultSecretResponse } from './generated/types';

// TypeScript knows the exact shape of responses
const health: HealthResponse = {
  status: 'healthy',
  timestamp: new Date().toISOString()
};
```

### Synchronization

The API-First approach ensures:
1. **Specification is source of truth** - All changes start with updating the OpenAPI spec
2. **Code generation** - Server types/validators regenerated from spec
3. **Automated validation** - Requests/responses validated at runtime
4. **Test synchronization** - Contract tests verify spec compliance
5. **Documentation sync** - API docs always match implementation

```bash
# Validate API implementation matches spec
npm run validate-api

# Run contract tests
npm run test:contract
```

## Key Integration Patterns

### Fetching Secrets from Vault

```typescript
import { VaultService } from './services/vault.service';

// Full type safety with generated types
const vaultService = new VaultService();

// Get all credentials for a service
const creds = await vaultService.getSecret('postgres');
const { user, password, database } = creds; // TypeScript knows these fields

// Get a specific key
const password = await vaultService.getSecretKey('postgres', 'password');
```

### Database Connections with Vault

```typescript
import { Client } from 'pg';
import { VaultService } from './services/vault.service';
import type { PostgresCredentials } from './generated/types';

// Fetch credentials from Vault (type-safe)
const vaultService = new VaultService();
const creds: PostgresCredentials = await vaultService.getSecret('postgres');

// Connect using Vault credentials
const client = new Client({
  host: 'postgres',
  port: 5432,
  user: creds.user,
  password: creds.password,
  database: creds.database
});

await client.connect();
const result = await client.query('SELECT NOW()');
await client.end();
```

### Redis Caching

```typescript
import { createClient, RedisClientType } from 'redis';
import { VaultService } from './services/vault.service';

// Get Redis credentials (type-safe)
const vaultService = new VaultService();
const creds = await vaultService.getSecret('redis-1');

// Connect to Redis
const client: RedisClientType = createClient({
  socket: { host: 'redis-1', port: 6379 },
  password: creds.password
});

await client.connect();

// Use cache (with type safety)
await client.setEx('key', 60, 'value'); // Set with 60s TTL
const value: string | null = await client.get('key');

await client.quit();
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HTTP_PORT` | `8005` | HTTP server port |
| `HTTPS_PORT` | `8448` | HTTPS server port (when TLS enabled) |
| `NODE_ENV` | `development` | Environment (development/production) |
| `DEBUG` | `true` | Enable debug logging |
| `VAULT_ADDR` | `http://vault:8200` | Vault server address |
| `VAULT_TOKEN` | - | Vault authentication token |
| `POSTGRES_HOST` | `postgres` | PostgreSQL hostname |
| `MYSQL_HOST` | `mysql` | MySQL hostname |
| `MONGODB_HOST` | `mongodb` | MongoDB hostname |
| `REDIS_HOST` | `redis-1` | Redis hostname |
| `RABBITMQ_HOST` | `rabbitmq` | RabbitMQ hostname |

## Development

### Prerequisites

- Node.js 18+ with TypeScript support
- npm or yarn
- OpenAPI Generator CLI (for code generation)

```bash
# Install OpenAPI Generator
npm install -g @openapitools/openapi-generator-cli
```

### Local Development

```bash
# Install dependencies
cd reference-apps/typescript-api-first
npm install

# Generate types from OpenAPI spec
npm run generate

# Type check
npm run typecheck

# Run locally (requires infrastructure running)
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
npm run dev

# Build for production
npm run build

# Run production build
npm start
```

### Testing

```bash
# Run all tests
npm test

# Unit tests
npm run test:unit

# Integration tests
npm run test:integration

# Contract tests (validate against OpenAPI spec)
npm run test:contract

# Test with coverage
npm run test:coverage

# Watch mode
npm run test:watch
```

### Type Checking

```bash
# Type check without building
npm run typecheck

# Watch mode
npm run typecheck:watch
```

### Linting

```bash
# Lint code
npm run lint

# Fix linting issues
npm run lint:fix
```

## Comparison with Other Implementations

| Feature | Python (FastAPI) | Go (Gin) | Node.js (Express) | TypeScript (Express) |
|---------|------------------|----------|-------------------|----------------------|
| **Port** | 8000/8001 | 8002 | 8003 | 8005 |
| **Approach** | Code-First / API-First | Code-First | Code-First | **API-First** |
| **Type Safety** | Runtime (Pydantic) | Compile-time | None | **Compile-time** |
| **Async Model** | async/await | goroutines | async/await | async/await |
| **Code Generation** | FastAPI auto-generates | Manual | Manual | **OpenAPI → TS** |
| **Validation** | Pydantic | Manual | Manual | **Auto-generated** |
| **Vault Client** | hvac | hashicorp/vault | node-vault | node-vault (typed) |
| **PostgreSQL** | asyncpg | pgx | pg | pg (typed) |
| **Redis** | redis-py | go-redis | redis | redis (typed) |
| **Logging** | Python logging | logrus | winston | winston (typed) |
| **Metrics** | prometheus_client | prometheus/client_golang | prom-client | prom-client (typed) |

## What This Demonstrates

✅ **API-First Development** - Specification-driven development workflow
✅ **Full Type Safety** - End-to-end compile-time type checking
✅ **Code Generation** - Auto-generate types/validators from OpenAPI spec
✅ **Secrets Management** - Vault integration for dynamic credentials
✅ **Database Integration** - PostgreSQL, MySQL, MongoDB with Vault
✅ **Caching Patterns** - Redis cluster operations
✅ **Message Queuing** - RabbitMQ publishing
✅ **Health Monitoring** - Comprehensive service health checks
✅ **Observability** - Structured logging and Prometheus metrics
✅ **TypeScript Best Practices** - Strict mode, interface-based design
✅ **Contract Testing** - Automated validation against OpenAPI spec

## What This Is NOT

❌ **Not production-ready** - Missing security hardening, rate limiting
❌ **Not feature-complete** - Focuses on integration patterns, not business logic
❌ **Not optimized** - Simple implementations for learning
❌ **Not secure** - Uses root Vault token for simplicity

## Security Notes

For learning only:
- ⚠️ Uses Vault root token (use AppRole in production)
- ⚠️ No authentication/authorization on endpoints
- ⚠️ Limited input validation (beyond OpenAPI schema)
- ⚠️ Debug mode enabled
- ⚠️ CORS wide open for development

For production, implement:
- ✅ Vault AppRole authentication
- ✅ JWT or OAuth2 for API authentication
- ✅ Request rate limiting
- ✅ Input sanitization
- ✅ Proper error handling without leaking internals
- ✅ Security headers (CSP, HSTS, etc.)

## Documentation Links

- **Main README**: [../../README.md](../../README.md)
- **Reference Apps Overview**: [../README.md](../README.md)
- **API Patterns**: [../API_PATTERNS.md](../API_PATTERNS.md)
- **API-First Comparison**: [../fastapi-api-first/README.md](../fastapi-api-first/README.md)
- **OpenAPI Specification**: [../shared/openapi.yaml](../shared/openapi.yaml)

## Client Examples

### cURL

```bash
# Health check
curl http://localhost:8005/health

# All services health
curl http://localhost:8005/health/all | jq '.'

# Fetch PostgreSQL credentials from Vault
curl http://localhost:8005/examples/vault/secret/postgres | jq '.data'

# Test PostgreSQL connection
curl http://localhost:8005/examples/database/postgres/query | jq '.'

# Cache operations
# Set a value with 60s TTL
curl -X POST http://localhost:8005/examples/cache/mykey \
  -H "Content-Type: application/json" \
  -d '{"value": "hello", "ttl": 60}'

# Get the value
curl http://localhost:8005/examples/cache/mykey | jq '.'

# Delete the value
curl -X DELETE http://localhost:8005/examples/cache/mykey

# Publish message to RabbitMQ
curl -X POST http://localhost:8005/examples/messaging/publish/test-queue \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from TypeScript!"}'
```

### TypeScript/JavaScript

```typescript
// Using fetch API (browser or Node.js 18+)
interface HealthResponse {
  status: string;
  timestamp: string;
}

const response = await fetch('http://localhost:8005/health');
const health: HealthResponse = await response.json();
console.log(health.status); // 'healthy'

// Using axios
import axios from 'axios';

const { data } = await axios.get<HealthResponse>('http://localhost:8005/health');
console.log(data.status);

// Vault secrets
interface VaultSecretResponse {
  data: Record<string, string>;
}

const vaultResponse = await fetch('http://localhost:8005/examples/vault/secret/postgres');
const secrets: VaultSecretResponse = await vaultResponse.json();
console.log(secrets.data.password);
```

### Python

```python
import requests

# Health check
response = requests.get('http://localhost:8005/health')
health = response.json()
print(health['status'])  # 'healthy'

# Fetch PostgreSQL credentials
response = requests.get('http://localhost:8005/examples/vault/secret/postgres')
secrets = response.json()
password = secrets['data']['password']

# Cache operations
# Set value
requests.post(
    'http://localhost:8005/examples/cache/mykey',
    json={'value': 'hello', 'ttl': 60}
)

# Get value
response = requests.get('http://localhost:8005/examples/cache/mykey')
cached = response.json()
```

## Roadmap

### Phase 1: Foundation (Current)
- [x] Project structure
- [x] OpenAPI specification scaffolding
- [ ] Basic service implementations
- [ ] Code generation pipeline
- [ ] Unit tests

### Phase 2: Infrastructure Integration
- [ ] Vault service implementation
- [ ] PostgreSQL integration
- [ ] MySQL integration
- [ ] MongoDB integration
- [ ] Redis cluster operations
- [ ] RabbitMQ messaging

### Phase 3: Advanced Features
- [ ] Full contract test suite
- [ ] API synchronization validation
- [ ] Docker integration
- [ ] TLS/HTTPS support
- [ ] Prometheus metrics
- [ ] Structured logging

### Phase 4: Documentation & Polish
- [ ] Comprehensive inline documentation
- [ ] API usage examples
- [ ] Troubleshooting guide
- [ ] Performance benchmarks

## Summary

This TypeScript API-First reference implementation demonstrates:
- 📝 **Specification-driven development** - OpenAPI spec as source of truth
- 🔒 **Full type safety** - Compile-time type checking throughout
- 🤖 **Code generation** - Auto-generate types and validators from spec
- 🧪 **Contract testing** - Automated validation against API specification
- 📚 **Modern TypeScript patterns** for infrastructure integration
- 🔍 How to integrate Express applications with Vault, databases, caching, and messaging
- ✅ Comprehensive health monitoring and observability

**Key Difference from Code-First:** In API-First development, the OpenAPI specification is designed first, and code is generated from it. This ensures the API contract is always respected and enables better collaboration between frontend and backend teams.

**Remember**: This is a learning resource and experimental implementation. Use these patterns to build your own production-ready applications with proper security, monitoring, and error handling.

---

**Status**: 🚧 In Active Development

**Contributions**: Feedback and contributions welcome to complete this reference implementation!
