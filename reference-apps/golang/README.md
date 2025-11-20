# Go Reference API

**⚠️ This is a reference implementation for learning and testing. Not intended for production use.**

This Go application demonstrates production-grade best practices for integrating with the DevStack Core infrastructure using the Gin web framework. It showcases secure credential management, concurrent patterns, observability, and idiomatic Go code.

## Table of Contents

- [Features Overview](#features-overview)
- [API Endpoints](#api-endpoints)
  - [Root Endpoint](#root-endpoint)
  - [Health Checks](#health-checks-health)
  - [Vault Integration](#vault-integration-examplesvault)
  - [Database Operations](#database-operations-examplesdatabase)
  - [Caching](#caching-examplescache)
  - [Messaging](#messaging-examplesmessaging)
  - [Redis Cluster Management](#redis-cluster-management-redis)
  - [Metrics](#metrics-metrics)
- [Architecture](#architecture)
- [Go-Specific Features](#go-specific-features)
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
- **Database Connections**: PostgreSQL, MySQL, MongoDB with proper context handling
- **Caching**: Redis cluster integration with TTL support
- **Messaging**: RabbitMQ pub/sub patterns with queue management
- **Health Monitoring**: Comprehensive health checks for all services
- **Redis Cluster**: Full cluster management and node monitoring

### Go-Specific Features
- **Concurrency**: Goroutines for async operations and concurrent health checks
- **Context Propagation**: Proper context.Context usage throughout
- **Graceful Shutdown**: Signal handling for clean termination
- **Structured Logging**: Logrus with request ID correlation
- **Type Safety**: Strong typing with proper error handling
- **Prometheus Metrics**: Native Go Prometheus client integration

---

## API Endpoints

### Root Endpoint

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/` | API information and available endpoints |

**Response:**
```json
{
  "name": "DevStack Core Reference API",
  "version": "1.0.0",
  "language": "Go",
  "framework": "Gin",
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

### Health Checks (`/health`)

Comprehensive health monitoring for all infrastructure services using concurrent checks.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health/` | Simple health check (no dependencies) |
| GET | `/health/all` | Aggregate health of all services (concurrent) |
| GET | `/health/vault` | Vault connectivity and status |
| GET | `/health/postgres` | PostgreSQL connection test |
| GET | `/health/mysql` | MySQL connection test |
| GET | `/health/mongodb` | MongoDB connection test |
| GET | `/health/redis` | Redis cluster health |
| GET | `/health/rabbitmq` | RabbitMQ connectivity |

**Health Check Response Format:**
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

**Implementation Note:**
The `/health/all` endpoint uses goroutines to check all services concurrently, providing fast aggregate health status.

---

### Vault Integration (`/examples/vault`)

Secure credential management using HashiCorp Vault KV v2 secrets engine.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/examples/vault/secret/:service_name` | Retrieve all secrets for a service |
| GET | `/examples/vault/secret/:service_name/:key` | Retrieve specific secret key |

**Examples:**
```bash
# Get all PostgreSQL credentials
curl http://localhost:8002/examples/vault/secret/reference-api/postgres

# Get specific credential
curl http://localhost:8002/examples/vault/secret/reference-api/postgres/username
```

**Response:**
```json
{
  "service": "reference-api/postgres",
  "secrets": {
    "username": "postgres",
    "password": "dynamic_password_from_vault",
    "database": "reference_db"
  }
}
```

---

### Database Operations (`/examples/database`)

Demonstrates database connectivity with Vault-managed credentials.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/examples/database/postgres` | PostgreSQL query example |
| GET | `/examples/database/mysql` | MySQL query example |
| GET | `/examples/database/mongodb` | MongoDB query example |

**Implementation Pattern:**
1. Fetch credentials from Vault using context
2. Create database connection
3. Execute query with timeout
4. Clean up resources with defer

**Example Response:**
```json
{
  "database": "postgres",
  "status": "connected",
  "query_result": "PostgreSQL 16.6 on x86_64-pc-linux-musl",
  "timestamp": "2025-10-27T12:00:00Z"
}
```

---

### Caching (`/examples/cache`)

Redis cache operations with TTL support.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/examples/cache/:key` | Get value from cache |
| POST | `/examples/cache/:key?value=X&ttl=3600` | Set cache value with TTL |
| DELETE | `/examples/cache/:key` | Delete cache key |

**Examples:**
```bash
# Set cache value with 1 hour TTL
curl -X POST "http://localhost:8002/examples/cache/mykey?value=myvalue&ttl=3600"

# Get cache value
curl http://localhost:8002/examples/cache/mykey

# Delete cache key
curl -X DELETE http://localhost:8002/examples/cache/mykey
```

**Response Format:**
```json
{
  "key": "mykey",
  "value": "myvalue",
  "operation": "set",
  "ttl": 3600,
  "success": true
}
```

---

### Messaging (`/examples/messaging`)

RabbitMQ messaging operations with queue management.

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/examples/messaging/publish/:queue` | Publish message to queue |
| GET | `/examples/messaging/queue/:queue_name/info` | Get queue information |

**Examples:**
```bash
# Publish message to queue
curl -X POST http://localhost:8002/examples/messaging/publish/test-queue \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello from Go!", "timestamp": "2025-10-27T12:00:00Z"}'

# Get queue info
curl http://localhost:8002/examples/messaging/queue/test-queue/info
```

**Publish Response:**
```json
{
  "status": "published",
  "queue": "test-queue",
  "message_id": "abc123",
  "timestamp": "2025-10-27T12:00:00Z"
}
```

---

### Redis Cluster Management (`/redis`)

Advanced Redis cluster operations and node monitoring.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/redis/cluster/nodes` | List all cluster nodes |
| GET | `/redis/cluster/slots` | Show slot distribution |
| GET | `/redis/cluster/info` | Cluster information |
| GET | `/redis/nodes/:node_name/info` | Detailed node information |

**Examples:**
```bash
# Get all cluster nodes
curl http://localhost:8002/redis/cluster/nodes

# Get slot distribution
curl http://localhost:8002/redis/cluster/slots

# Get specific node info
curl http://localhost:8002/redis/nodes/redis-node-1/info
```

**Cluster Nodes Response:**
```json
{
  "cluster_enabled": true,
  "cluster_state": "ok",
  "cluster_size": 3,
  "nodes": [
    {
      "id": "abc123",
      "address": "172.20.0.21:6379",
      "role": "master",
      "slots": "0-5460",
      "flags": ["master"],
      "link_state": "connected"
    }
  ]
}
```

---

### Metrics (`/metrics`)

Prometheus metrics endpoint exposing application and runtime metrics.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/metrics` | Prometheus metrics |

**Available Metrics:**
- `http_requests_total` - Total HTTP requests by method, endpoint, status
- `http_request_duration_seconds` - Request latency histogram
- `go_goroutines` - Number of goroutines
- `go_memstats_*` - Go runtime memory statistics

---

## Architecture

### Project Structure

```
reference-apps/golang/
├── cmd/
│   └── api/
│       └── main.go              # Application entry point
├── internal/
│   ├── config/
│   │   └── config.go            # Configuration management
│   ├── handlers/
│   │   ├── health.go            # Health check handlers
│   │   ├── vault.go             # Vault integration handlers
│   │   ├── database.go          # Database handlers
│   │   ├── cache.go             # Redis cache handlers
│   │   ├── redis_cluster.go     # Redis cluster management
│   │   └── messaging.go         # RabbitMQ handlers
│   ├── middleware/
│   │   └── logging.go           # Logging and CORS middleware
│   └── services/
│       └── vault.go             # Vault client wrapper
├── go.mod                        # Go module definition
├── go.sum                        # Dependency checksums
├── Dockerfile                    # Multi-stage Docker build
├── init.sh                       # Initialization script
├── start.sh                      # Application startup script
└── README.md                     # This file
```

### Design Principles

1. **Clean Architecture**: Separation of concerns with clear package boundaries
2. **Dependency Injection**: Handlers receive dependencies via constructors
3. **Context Propagation**: `context.Context` used throughout for cancellation and timeouts
4. **Error Handling**: Explicit error checks with proper HTTP status codes
5. **Resource Cleanup**: `defer` statements for closing connections
6. **Concurrent Operations**: Goroutines for parallelizable operations

---

## Go-Specific Features

### Concurrency Patterns

**Concurrent Health Checks:**
```go
// All services checked in parallel using goroutines
var wg sync.WaitGroup
results := make(map[string]interface{})
mu := &sync.Mutex{}

for _, service := range services {
    wg.Add(1)
    go func(svc string) {
        defer wg.Done()
        result := checkService(ctx, svc)
        mu.Lock()
        results[svc] = result
        mu.Unlock()
    }(service)
}
wg.Wait()
```

### Context Handling

All operations use `context.Context` for:
- Request cancellation propagation
- Timeouts (5s for database operations, 30s for health checks)
- Distributed tracing correlation

**Example:**
```go
ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
defer cancel()

conn, err := pgx.Connect(ctx, connStr)
```

### Graceful Shutdown

```go
srv := &http.Server{Addr: fmt.Sprintf(":%s", cfg.HTTPPort), Handler: router}

// Start server in goroutine
go func() {
    if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
        logger.Fatalf("Server error: %s", err)
    }
}()

// Wait for interrupt signal
quit := make(chan os.Signal, 1)
signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
<-quit

// Graceful shutdown with timeout
ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
defer cancel()
srv.Shutdown(ctx)
```

---

## Middleware

### Logging Middleware

- Generates unique request ID (UUID)
- Adds `X-Request-ID` header to responses
- Logs all requests with structured fields:
  - request_id, method, path, status, duration
- Integration with logrus for JSON logging

### CORS Middleware

- Configurable allowed origins
- Supports credentials
- Standard headers: Content-Type, Authorization, X-Request-ID
- Methods: GET, POST, PUT, DELETE, OPTIONS

---

## Monitoring & Observability

### Structured Logging

Uses `logrus` for structured logging:
```go
logger.WithFields(logrus.Fields{
    "request_id": requestID,
    "method":     c.Request.Method,
    "path":       c.Request.URL.Path,
    "status":     c.Writer.Status(),
    "duration":   duration.Milliseconds(),
}).Info("HTTP request processed")
```

### Prometheus Metrics

- **HTTP Metrics**: Request counts and latency by endpoint
- **Go Runtime Metrics**: Goroutines, memory, GC stats
- **Custom Metrics**: Application-specific counters and gauges

---

## Quick Start

### Using Docker Compose

```bash
# Start the Go API service
docker-compose up -d golang-api

# View logs
docker-compose logs -f golang-api

# Test the API
curl http://localhost:8002/
curl http://localhost:8002/health/all
```

### Local Development

```bash
# Install dependencies
cd reference-apps/golang
go mod download

# Run locally (requires services)
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=your-token
go run ./cmd/api

# Build binary
go build -o api ./cmd/api
./api
```

---

## Development

### Building

```bash
# Development build
go build -o api ./cmd/api

# Production build (optimized)
CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o api ./cmd/api
```

### Docker Build

```bash
# Build Docker image
docker build -t golang-api:latest .

# Run container
docker run -p 8002:8002 \
  -e VAULT_ADDR=http://vault:8200 \
  -e VAULT_TOKEN=your-token \
  golang-api:latest
```

### Code Quality

```bash
# Format code
go fmt ./...

# Lint code
golangci-lint run

# Vet code
go vet ./...

# Run tests
go test ./...
```

---

## Testing

### Manual Testing

```bash
# Health checks
curl http://localhost:8002/health/
curl http://localhost:8002/health/all
curl http://localhost:8002/health/vault

# Vault integration
curl http://localhost:8002/examples/vault/secret/reference-api/postgres

# Database operations
curl http://localhost:8002/examples/database/postgres
curl http://localhost:8002/examples/database/mysql
curl http://localhost:8002/examples/database/mongodb

# Cache operations
curl -X POST "http://localhost:8002/examples/cache/test?value=hello&ttl=60"
curl http://localhost:8002/examples/cache/test
curl -X DELETE http://localhost:8002/examples/cache/test

# Redis cluster
curl http://localhost:8002/redis/cluster/nodes
curl http://localhost:8002/redis/cluster/info

# Messaging
curl -X POST http://localhost:8002/examples/messaging/publish/test-queue \
  -H "Content-Type: application/json" \
  -d '{"message": "test"}'

# Metrics
curl http://localhost:8002/metrics
```

### Integration Testing

Automated tests are planned using:
- Go's `testing` package
- `httptest` for HTTP handler testing
- Mock implementations for external services

---

## Environment Variables

### Required Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `VAULT_ADDR` | Vault server address | `http://vault:8200` |
| `VAULT_TOKEN` | Vault authentication token | Required |

### Service Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `HTTP_PORT` | HTTP server port | `8002` |
| `HTTPS_PORT` | HTTPS server port | `8445` |
| `GOLANG_API_ENABLE_TLS` | Enable TLS | `false` |

### Database Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTGRES_HOST` | PostgreSQL host | `postgres` |
| `POSTGRES_PORT` | PostgreSQL port | `5432` |
| `MYSQL_HOST` | MySQL host | `mysql` |
| `MYSQL_PORT` | MySQL port | `3306` |
| `MONGODB_HOST` | MongoDB host | `mongodb` |
| `MONGODB_PORT` | MongoDB port | `27017` |

### Cache & Messaging

| Variable | Description | Default |
|----------|-------------|---------|
| `REDIS_CLUSTER_NODES` | Redis cluster nodes | `redis-node-1:6379,...` |
| `RABBITMQ_HOST` | RabbitMQ host | `rabbitmq` |
| `RABBITMQ_PORT` | RabbitMQ port | `5672` |

### Application Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `ENVIRONMENT` | Environment name | `development` |
| `DEBUG` | Debug mode | `false` |
| `LOG_LEVEL` | Logging level | `info` |

---

## Comparison with Python Implementation

| Feature | Go Implementation | Python Implementation |
|---------|------------------|----------------------|
| **Web Framework** | Gin | FastAPI |
| **Concurrency** | Goroutines | asyncio |
| **Type System** | Static typing | Type hints (runtime optional) |
| **Performance** | Compiled, very fast | Interpreted, fast with async |
| **Resource Usage** | Lower memory, faster startup | Higher memory, slower startup |
| **Dependencies** | Compiled into binary | Requires runtime + packages |
| **Deployment** | Single binary | Python + dependencies |
| **Error Handling** | Explicit error returns | Exceptions |
| **Context** | context.Context | async context |

---

## Dependencies

Main Go dependencies:
- **github.com/gin-gonic/gin** - Web framework
- **github.com/hashicorp/vault/api** - Vault client
- **github.com/jackc/pgx/v5** - PostgreSQL driver
- **github.com/go-sql-driver/mysql** - MySQL driver
- **go.mongodb.org/mongo-driver** - MongoDB driver
- **github.com/redis/go-redis/v9** - Redis client
- **github.com/rabbitmq/amqp091-go** - RabbitMQ client
- **github.com/prometheus/client_golang** - Prometheus metrics
- **github.com/sirupsen/logrus** - Structured logging

---

## Additional Resources

- [Go Documentation](https://golang.org/doc/)
- [Gin Framework](https://gin-gonic.com/)
- [Main Project README](../../README.md)
- [API Patterns](../API_PATTERNS.md)
- [Vault Security Guide](../../docs/VAULT_SECURITY.md)

---

## License

This reference implementation is part of the DevStack Core project. See the main project README for license information.
