# API-First FastAPI Implementation

## ✅ **FEATURE-COMPLETE IMPLEMENTATION** ✅

**Production-ready Python implementation with 100% feature parity** - API-first development approach.

**Production-Ready Reference Implementation Following API-First Development Pattern**

This implementation demonstrates the **API-first development approach** where the OpenAPI specification drives the implementation, in contrast to the code-first approach where implementation drives the documentation.

### Implementation Highlights

- **100% behavioral parity** - Validated by 26/26 shared parity tests
- **OpenAPI-driven development** - Specification is the source of truth
- **Complete infrastructure integration** - All services: Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- **Advanced features** - Circuit breakers, rate limiting, response caching
- **Comprehensive testing** - Unit tests, integration tests, parity validation
- **Dual-mode TLS** - HTTP (8001) and HTTPS (8444) support
- **Real Prometheus metrics** - HTTP requests, cache ops, circuit breakers
- **Interactive API docs** - Auto-generated from OpenAPI specification

## Table of Contents
- [Overview](#overview)
- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [API Endpoints](#api-endpoints)
- [Security Features](#security-features)
- [Configuration](#configuration)
- [Running the Application](#running-the-application)
- [Testing](#testing)
- [Parity with Code-First](#parity-with-code-first)
- [Development Workflow](#development-workflow)

## Overview

### Purpose
This API-first implementation serves as a reference for:
- Contract-first API development using OpenAPI specifications
- Containerized FastAPI applications with full infrastructure integration
- Implementing identical functionality through different development patterns
- Demonstrating API synchronization and parity validation

### Key Features
- ✅ **Full Parity**: 100% behavioral equivalence with code-first implementation (26/26 tests passing)
- ✅ **Containerized**: Complete Docker support with Vault integration
- ✅ **TLS/HTTPS**: Support for secure connections on port 8444
- ✅ **Infrastructure Integration**: Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- ✅ **Production Patterns**: Rate limiting, circuit breakers, CORS, metrics, health checks
- ✅ **Comprehensive Testing**: Unit tests, integration tests, shared parity test suite

### Service Details
- **HTTP Port**: 8001
- **HTTPS Port**: 8444 (when TLS enabled)
- **Network IP**: 172.20.0.104 (dev-services network)
- **Container Name**: dev-api-first
- **Health Check**: http://localhost:8001/health

## Quick Start

### Using Docker Compose (Recommended)

```bash
# Start the API-first implementation
docker compose up -d api-first

# Verify it's running
curl http://localhost:8001/health/

# View logs
docker compose logs -f api-first

# Access interactive API documentation
open http://localhost:8001/docs
```

### Local Development

```bash
# Install dependencies
cd reference-apps/fastapi-api-first
pip install -r requirements.txt

# Set environment variables
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=your-token

# Run the application
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload

# Access the API
open http://localhost:8001/docs
```

## Architecture

### API-First Development Pattern

```
┌─────────────────────────────────────────┐
│   OpenAPI Specification (Contract)      │
│   shared/openapi.yaml                   │
└───────────────┬─────────────────────────┘
                │
                │ Drives Implementation
                ▼
┌─────────────────────────────────────────┐
│   Generated Models & Stubs              │
│   (datamodel-code-generator)            │
└───────────────┬─────────────────────────┘
                │
                │ Enhanced With
                ▼
┌─────────────────────────────────────────┐
│   Business Logic & Integrations         │
│   - Vault secrets management            │
│   - Database connections                │
│   - Cache operations                    │
│   - Message queue integration           │
└───────────────┬─────────────────────────┘
                │
                │ Validated By
                ▼
┌─────────────────────────────────────────┐
│   Shared Test Suite (26 tests)         │
│   Ensures parity with code-first        │
└─────────────────────────────────────────┘
```

### Application Structure

```
fastapi-api-first/
├── app/
│   ├── main.py              # Application entry point
│   ├── config.py            # Configuration management
│   ├── routers/             # API endpoint routers (6 modules)
│   │   ├── health_checks.py
│   │   ├── vault_examples.py
│   │   ├── database_examples.py
│   │   ├── cache_examples.py
│   │   ├── messaging_examples.py
│   │   └── redis_cluster.py
│   ├── middleware/          # Custom middleware
│   │   ├── cache.py
│   │   └── exception_handlers.py
│   ├── models/              # Pydantic models
│   └── exceptions.py        # Custom exceptions
├── tests/                   # Unit and integration tests
├── Dockerfile               # Container build definition
├── init.sh                  # Vault integration and TLS setup
├── start.sh                 # Application startup script
├── requirements.txt         # Python dependencies
└── pytest.ini              # Test configuration
```

### Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| **Framework** | FastAPI | 0.104.1 |
| **ASGI Server** | Uvicorn | 0.24.0 |
| **Python** | Python | 3.11 |
| **Validation** | Pydantic | 2.x |
| **Database Clients** | asyncpg, aiomysql, motor | Latest |
| **Cache** | redis[hiredis] | 4.6.0 |
| **Messaging** | aio-pika | 9.x |
| **Secrets** | hvac (Vault client) | 2.x |
| **Metrics** | prometheus-client | 0.x |
| **Rate Limiting** | slowapi | 0.1.9 |

## API Endpoints

### Root Endpoint
```
GET /
```
Returns API information, security configuration, and available endpoints.

### Health Checks
```
GET /health/              # Simple health check
GET /health/all           # All services health
GET /health/vault         # Vault-specific health
GET /health/database      # Database health
GET /health/cache         # Cache health
GET /health/messaging     # Messaging health
```

### Vault Integration Examples
```
GET  /examples/vault/health                    # Vault health status
GET  /examples/vault/secret/{path}             # Read secret from Vault
POST /examples/vault/secret/{path}             # Write secret to Vault
GET  /examples/vault/secret/versioned/{path}   # Get versioned secret
GET  /examples/vault/transit/encrypt/{plaintext}  # Encrypt with Transit
GET  /examples/vault/transit/decrypt/{ciphertext} # Decrypt with Transit
```

### Database Examples
```
GET  /examples/database/postgres               # PostgreSQL operations
POST /examples/database/postgres               # Insert data
GET  /examples/database/mysql                  # MySQL operations
POST /examples/database/mysql                  # Insert data
GET  /examples/database/mongodb                # MongoDB operations
POST /examples/database/mongodb                # Insert data
```

### Cache Examples
```
GET    /examples/cache/{key}                   # Get cached value
POST   /examples/cache/{key}                   # Set cache value
DELETE /examples/cache/{key}                   # Delete cached value
GET    /examples/cache/pattern/{pattern}       # Search by pattern
```

### Messaging Examples
```
POST /examples/messaging/publish/{queue}       # Publish message
GET  /examples/messaging/consume/{queue}       # Consume message
GET  /examples/messaging/queues                # List queues
```

### Redis Cluster Management
```
GET /redis/cluster/nodes                       # Cluster node info
GET /redis/cluster/slots                       # Slot distribution
GET /redis/cluster/info                        # Cluster status
GET /redis/nodes/{node_name}/info              # Specific node info
```

### Observability
```
GET /metrics                                   # Prometheus metrics
GET /docs                                      # Interactive API docs (Swagger UI)
GET /redoc                                     # Alternative API docs (ReDoc)
GET /openapi.json                              # OpenAPI specification
```

## Security Features

### CORS Configuration
- **Allowed Origins**: localhost:3000, localhost:8000, localhost:8001
- **Allowed Methods**: GET, POST, PUT, DELETE, PATCH, OPTIONS
- **Credentials**: Enabled (not in debug mode)
- **Max Age**: 600 seconds

### Rate Limiting
- **General Endpoints**: 100 requests/minute per IP
- **Health Checks**: 200 requests/minute per IP
- **Metrics**: 1000 requests/minute per IP
- Headers: `X-RateLimit-Limit`, `X-RateLimit-Remaining`

### Circuit Breakers
- **Enabled Services**: Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- **Failure Threshold**: 5 consecutive failures
- **Reset Timeout**: 60 seconds

### Request Validation
- **Max Request Size**: 10MB
- **Allowed Content Types**: application/json, application/x-www-form-urlencoded, multipart/form-data, text/plain
- **Request ID Tracking**: `X-Request-ID` header on all responses

### TLS/HTTPS Support
Vault-managed certificates for secure connections:
- Certificates fetched from Vault PKI backend
- Automatic renewal before expiration
- Configurable via `API_FIRST_ENABLE_TLS` environment variable

## Configuration

### Environment Variables

#### Required
```bash
VAULT_ADDR=http://vault:8200           # Vault server address
VAULT_TOKEN=your-vault-token           # Vault authentication token
```

#### Database Configuration
```bash
# PostgreSQL
POSTGRES_HOST=postgres
POSTGRES_PORT=5432
POSTGRES_USER=appuser
POSTGRES_PASSWORD=from-vault
POSTGRES_DB=appdb

# MySQL
MYSQL_HOST=mysql
MYSQL_PORT=3306
MYSQL_USER=appuser
MYSQL_PASSWORD=from-vault
MYSQL_DATABASE=appdb

# MongoDB
MONGODB_HOST=mongodb
MONGODB_PORT=27017
MONGODB_USER=appuser
MONGODB_PASSWORD=from-vault
MONGODB_DATABASE=appdb
```

#### Cache Configuration
```bash
REDIS_HOST=redis-1                     # Redis host
REDIS_PORT=6379                        # Redis port
REDIS_PASSWORD=from-vault              # Redis password
```

#### Messaging Configuration
```bash
RABBITMQ_HOST=rabbitmq
RABBITMQ_PORT=5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=from-vault
```

#### TLS Configuration
```bash
API_FIRST_ENABLE_TLS=false             # Enable HTTPS
API_FIRST_HTTP_PORT=8001               # HTTP port
API_FIRST_HTTPS_PORT=8444              # HTTPS port
```

#### Application Settings
```bash
DEBUG=false                            # Debug mode
LOG_LEVEL=INFO                         # Logging level
WORKERS=4                              # Uvicorn workers
```

### Docker Compose Configuration

The service is defined in `docker-compose.yml`:

```yaml
api-first:
  build: ./reference-apps/fastapi-api-first
  container_name: dev-api-first
  ports:
    - "8001:8001"
    - "8444:8444"
  networks:
    dev-services:
      ipv4_address: 172.20.0.104
  depends_on:
    - vault
    - postgres
    - mysql
    - mongodb
    - redis-1
    - rabbitmq
  healthcheck:
    test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8001/health')"]
    interval: 30s
    timeout: 10s
    retries: 3
```

## Running the Application

### Docker Compose (Production-Like)

```bash
# Start all infrastructure services + API-first
docker compose up -d api-first

# View startup logs
docker compose logs -f api-first

# Check health
curl http://localhost:8001/health/

# Stop the service
docker compose stop api-first

# Rebuild after code changes
docker compose up -d --build api-first
```

### Docker Run (Standalone)

```bash
# Build the image
docker build -t api-first:latest ./reference-apps/fastapi-api-first

# Run the container
docker run -d \
  --name dev-api-first \
  -p 8001:8001 \
  -p 8444:8444 \
  -e VAULT_ADDR=http://vault:8200 \
  -e VAULT_TOKEN=your-token \
  api-first:latest

# View logs
docker logs -f dev-api-first
```

### Local Development (Hot Reload)

```bash
# Install dependencies
cd reference-apps/fastapi-api-first
pip install -r requirements.txt

# Set environment variables
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=your-token
export POSTGRES_HOST=localhost
export REDIS_HOST=localhost
# ... other variables

# Run with auto-reload
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload

# Or use the start script
./start.sh
```

### Accessing the Application

- **API Documentation**: http://localhost:8001/docs
- **Alternative Docs**: http://localhost:8001/redoc
- **OpenAPI Spec**: http://localhost:8001/openapi.json
- **Health Check**: http://localhost:8001/health/
- **Metrics**: http://localhost:8001/metrics

## Testing

### Unit Tests

```bash
# Run all unit tests
pytest tests/unit/ -v

# Run with coverage
pytest tests/unit/ --cov=app --cov-report=html

# Run specific test file
pytest tests/unit/test_routers.py -v
```

### Integration Tests

```bash
# Run integration tests (requires infrastructure)
pytest tests/integration/ -v

# Skip integration tests
pytest -m "not integration"
```

### Shared Test Suite (Parity Validation)

The shared test suite validates that this API-first implementation behaves identically to the code-first implementation:

```bash
# Run shared test suite
cd reference-apps/shared/test-suite
pip install -r requirements.txt

# Ensure both APIs are running
docker compose up -d reference-api api-first

# Run parity tests
pytest -v

# Results: 26/26 tests passing (100% parity)
```

**Test Categories:**
- **Parity Tests**: Run against both implementations independently (parametrized)
- **Comparison Tests**: Direct response comparison between implementations

**Coverage Areas:**
- Root endpoint structure and content
- OpenAPI specification matching
- Health check endpoints (simple and vault-specific)
- Cache endpoint behavior
- Metrics endpoint format
- Error handling (404 responses)

See `reference-apps/shared/test-suite/README.md` for complete testing documentation.

### Test Statistics

- **Unit Tests**: Comprehensive mocking of all dependencies
- **Integration Tests**: Real infrastructure validation
- **Shared Parity Tests**: 26 tests, 100% passing
- **Total Coverage**: Matches code-first implementation

## Parity with Code-First

### What is API Parity?

This API-first implementation maintains **100% behavioral equivalence** with the code-first implementation at `reference-apps/fastapi/`. Both implementations:

- Expose identical endpoints
- Accept the same request formats
- Return identical response structures
- Handle errors consistently
- Provide the same security features
- Integrate with infrastructure identically

### How Parity is Maintained

1. **Shared OpenAPI Specification**
   - Single source of truth: `reference-apps/shared/openapi.yaml`
   - Both implementations reference the same contract
   - Pre-commit hooks validate synchronization

2. **Shared Test Suite**
   - 26 automated tests run against both implementations
   - Parametrized fixtures test both APIs simultaneously
   - Comparison tests verify identical responses
   - CI/CD enforces 100% test pass rate

3. **Automated Validation**
   - Pre-commit hooks check API synchronization
   - Make targets for validation: `make validate-apis`
   - Continuous monitoring of parity

### Verification

```bash
# Run parity validation
cd reference-apps/shared/test-suite
pytest -v

# Expected output: 26/26 tests passing
# ===== 26 passed in X.XXs =====
```

### Key Differences

While behavior is identical, the development workflows differ:

| Aspect | Code-First | API-First |
|--------|-----------|-----------|
| **Starting Point** | Python code | OpenAPI spec |
| **Documentation** | Generated from code | Drives implementation |
| **Typical Use** | Rapid prototyping | Contract-first design |
| **Changes Start** | In Python files | In OpenAPI spec |
| **Best For** | Internal APIs, MVPs | External APIs, teams |

## Development Workflow

### Making Changes to the API

#### 1. Update OpenAPI Specification
```bash
# Edit the shared OpenAPI spec
vim reference-apps/shared/openapi.yaml
```

#### 2. Regenerate Models (Optional)
```bash
# Regenerate Pydantic models from spec
./scripts/generate-api-first.sh
```

#### 3. Implement Business Logic
```bash
# Update router implementations
vim reference-apps/fastapi-api-first/app/routers/your_router.py
```

#### 4. Run Tests
```bash
# Test your changes
pytest tests/ -v

# Validate parity
cd reference-apps/shared/test-suite && pytest -v
```

#### 5. Rebuild and Deploy
```bash
# Rebuild Docker image
docker compose up -d --build api-first

# Verify deployment
curl http://localhost:8001/health/
```

### Pre-commit Hooks

Pre-commit hooks automatically validate API synchronization:

```bash
# Install pre-commit hooks
pre-commit install

# Hooks will check:
# - OpenAPI spec is valid
# - Both implementations sync with spec
# - Code formatting and linting
# - No secrets in commits
```

### Synchronization Targets

```bash
# Validate API synchronization
make validate-apis

# Check for drift between implementations
make check-parity

# Update OpenAPI spec from code-first
make update-openapi-from-code

# Update API-first from OpenAPI spec
make update-api-from-openapi
```

## Troubleshooting

### Container Won't Start

```bash
# Check logs
docker compose logs api-first

# Common issues:
# - Vault not ready: Wait for vault healthy
# - Port conflict: Change API_FIRST_HTTP_PORT
# - Network issue: Check dev-services network
```

### Vault Connection Errors

```bash
# Verify Vault is accessible
docker compose exec api-first curl http://vault:8200/v1/sys/health

# Check Vault token
docker compose exec api-first env | grep VAULT_TOKEN

# Manual Vault initialization
docker compose exec api-first /app/init.sh
```

### Database Connection Issues

```bash
# Check database health
docker compose ps postgres mysql mongodb

# Test connection from container
docker compose exec api-first python -c "import asyncpg; print('OK')"

# Verify credentials in Vault
vault kv get secret/reference-api/postgres
```

### Tests Failing

```bash
# Run with verbose output
pytest -vv --tb=short

# Check test dependencies
pip install -r requirements.txt

# Ensure services are running
docker compose up -d vault postgres mysql mongodb redis-1 rabbitmq

# Run only fast tests
pytest -m "not integration"
```

## Performance Considerations

### Async/Await Pattern
All I/O operations use async/await for maximum concurrency:
- Database queries: asyncpg, aiomysql, motor
- Cache operations: redis[asyncio]
- Message queue: aio-pika
- HTTP requests: httpx

### Connection Pooling
- PostgreSQL: Connection pool (min=5, max=20)
- MySQL: Connection pool (min=5, max=20)
- MongoDB: Connection pool configured
- Redis: Connection pool with hiredis parser

### Caching Strategy
- Application-level caching via middleware
- Redis cluster for distributed caching
- Cache key patterns for invalidation

### Resource Limits
Docker container limits:
- Memory: Configured in docker-compose.yml
- CPU: Configured in docker-compose.yml
- Connections: Per service limits

## Security Considerations

### Secrets Management
- All secrets stored in Vault
- No hardcoded credentials
- Automatic secret rotation support
- TLS certificates from Vault PKI

### Network Security
- Internal service network (172.20.0.0/16)
- No direct external access to infrastructure
- HTTPS support with valid certificates
- CORS properly configured

### Input Validation
- Pydantic models for request validation
- Type checking on all endpoints
- SQL injection prevention (parameterized queries)
- XSS prevention (proper escaping)

### Monitoring & Auditing
- Prometheus metrics for all operations
- Structured JSON logging
- Request ID tracking
- Error logging and alerting

## Additional Resources

- **Shared Test Suite**: `reference-apps/shared/test-suite/README.md`
- **API Patterns Guide**: `reference-apps/API_PATTERNS.md`
- **OpenAPI Specification**: `reference-apps/shared/openapi.yaml`
- **Code-First Implementation**: `reference-apps/fastapi/README.md`
- **Release Notes**: `reference-apps/CHANGELOG.md`
- **Main Documentation**: `README.md`

## Contributing

See our [Contributing Guide](../../.github/CONTRIBUTING.md) for detailed instructions on how to contribute to DevStack Core.

### Adding New Endpoints

1. Update `reference-apps/shared/openapi.yaml`
2. Regenerate models if needed
3. Implement router in `app/routers/`
4. Add tests in `tests/`
5. Add parity tests in `shared/test-suite/`
6. Run full test suite
7. Update this README

### Code Style

- Follow PEP 8 style guide
- Use type hints for all functions
- Add docstrings to all public functions
- Keep functions small and focused
- Use async/await for I/O operations

### Testing Requirements

- Unit tests for all new code
- Integration tests for infrastructure interactions
- Parity tests to verify code-first equivalence
- Minimum 80% code coverage

## License

This is a reference implementation for development and education purposes.

## Support

For issues or questions:
- Check troubleshooting section above
- Review logs: `docker compose logs api-first`
- Inspect health: `curl http://localhost:8001/health/all`
- Check test suite: `cd reference-apps/shared/test-suite && pytest -v`
