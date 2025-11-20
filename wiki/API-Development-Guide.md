# API Development Guide

Building new APIs following reference patterns in DevStack Core.

## Table of Contents

- [Overview](#overview)
- [Getting Started](#getting-started)
- [Reference Patterns](#reference-patterns)
- [Vault Integration](#vault-integration)
- [Database Integration](#database-integration)
- [Redis Integration](#redis-integration)
- [RabbitMQ Integration](#rabbitmq-integration)
- [Health Checks](#health-checks)
- [API Documentation](#api-documentation)
- [Testing](#testing)
- [Deployment](#deployment)
- [Related Documentation](#related-documentation)

## Overview

DevStack Core includes 5 reference API implementations demonstrating best practices for building services that integrate with the infrastructure.

**Reference APIs:**
- **FastAPI (Code-First)**: Port 8000/8443
- **FastAPI (API-First)**: Port 8001/8444
- **Go (Gin)**: Port 8002/8445
- **Node.js (Express)**: Port 8003/8446
- **Rust (Actix-web)**: Port 8004/8447

All demonstrate:
- Vault secret retrieval
- Database connections with Vault credentials
- Redis cluster operations
- RabbitMQ messaging
- Health checks for dependencies
- Dual HTTP/HTTPS with Vault-issued certificates

## Getting Started

### Choosing Framework

**Python FastAPI:**
- **Pros**: Modern, async, auto-generated OpenAPI docs, type hints
- **Cons**: Slower than compiled languages
- **Use**: APIs, microservices, data processing

**Go Gin:**
- **Pros**: Fast, compiled, low memory, good concurrency
- **Cons**: Verbose error handling, less flexible than Python
- **Use**: High-performance APIs, system tools

**Node.js Express:**
- **Pros**: JavaScript ecosystem, npm packages, async I/O
- **Cons**: Single-threaded, callback complexity
- **Use**: Real-time apps, JSON APIs, prototyping

**Rust Actix-web:**
- **Pros**: Extremely fast, memory-safe, zero-cost abstractions
- **Cons**: Steep learning curve, slower development
- **Use**: Performance-critical APIs, systems programming

### Project Structure

**Python FastAPI (Code-First):**

```
reference-apps/fastapi/
├── app/
│   ├── __init__.py
│   ├── main.py              # Application entry point
│   ├── config.py            # Configuration management
│   ├── dependencies.py      # Dependency injection
│   ├── routers/             # API route handlers
│   │   ├── __init__.py
│   │   ├── health.py        # Health check endpoints
│   │   ├── database.py      # Database operations
│   │   ├── cache.py         # Redis operations
│   │   └── messaging.py     # RabbitMQ operations
│   ├── services/            # Business logic
│   │   ├── __init__.py
│   │   ├── database.py
│   │   ├── cache.py
│   │   └── messaging.py
│   └── models/              # Data models
│       ├── __init__.py
│       └── schemas.py
├── tests/                   # Unit tests
├── Dockerfile
├── requirements.txt
└── pyproject.toml
```

**Go Gin:**

```
reference-apps/golang/
├── cmd/
│   └── api/
│       └── main.go          # Entry point
├── internal/
│   ├── config/              # Configuration
│   ├── handlers/            # HTTP handlers
│   ├── services/            # Business logic
│   ├── models/              # Data models
│   └── middleware/          # Middleware
├── pkg/
│   ├── vault/               # Vault client
│   ├── database/            # Database client
│   └── cache/               # Redis client
├── Dockerfile
├── go.mod
└── go.sum
```

### Create New API

```bash
# 1. Choose language/framework
mkdir -p reference-apps/myapi

# 2. Copy reference implementation
cp -r reference-apps/fastapi reference-apps/myapi

# 3. Update configuration
cd reference-apps/myapi

# 4. Update Dockerfile
# FROM python:3.11-slim
# WORKDIR /app
# COPY requirements.txt .
# RUN pip install -r requirements.txt
# COPY app/ ./app/
# CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# 5. Add to docker-compose.yml
services:
  myapi:
    build: ./reference-apps/myapi
    container_name: myapi
    ports:
      - "8005:8000"
    networks:
      dev-services:
        ipv4_address: 172.20.0.105
    depends_on:
      vault:
        condition: service_healthy
    environment:
      VAULT_ADDR: http://vault:8200
      VAULT_TOKEN: ${VAULT_TOKEN}

# 6. Build and run
docker compose up -d --build myapi
```

## Reference Patterns

### Basic Application Structure

**Python FastAPI:**

```python
# app/main.py
from fastapi import FastAPI, Depends
from app.config import get_settings
from app.routers import health, database, cache, messaging

app = FastAPI(title="My API", version="1.0.0")

# Include routers
app.include_router(health.router, prefix="/health", tags=["health"])
app.include_router(database.router, prefix="/api/database", tags=["database"])
app.include_router(cache.router, prefix="/api/cache", tags=["cache"])
app.include_router(messaging.router, prefix="/api/messaging", tags=["messaging"])

@app.on_event("startup")
async def startup_event():
    """Initialize connections on startup"""
    settings = get_settings()
    # Initialize database
    # Initialize cache
    # Initialize messaging

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup connections on shutdown"""
    # Close database
    # Close cache
    # Close messaging

@app.get("/")
async def root():
    return {"message": "Welcome to My API"}
```

### Configuration Management

```python
# app/config.py
from pydantic_settings import BaseSettings
from functools import lru_cache
import os

class Settings(BaseSettings):
    # Application
    app_name: str = "My API"
    app_version: str = "1.0.0"
    debug: bool = False
    
    # Vault
    vault_addr: str = os.getenv("VAULT_ADDR", "http://vault:8200")
    vault_token: str = os.getenv("VAULT_TOKEN", "")
    
    # Database
    db_host: str = "postgres"
    db_port: int = 5432
    db_name: str = "myapp"
    db_user: str = "postgres"
    db_password: str = ""  # Loaded from Vault
    
    # Redis
    redis_host: str = "redis-1"
    redis_port: int = 6379
    redis_password: str = ""  # Loaded from Vault
    
    # RabbitMQ
    rabbitmq_host: str = "rabbitmq"
    rabbitmq_port: int = 5672
    rabbitmq_user: str = "guest"
    rabbitmq_password: str = ""  # Loaded from Vault

    class Config:
        env_file = ".env"

@lru_cache()
def get_settings() -> Settings:
    return Settings()
```

## Vault Integration

### Fetching Secrets

**Python:**

```python
# app/vault.py
import hvac
import os

def get_vault_client():
    """Create Vault client"""
    client = hvac.Client(
        url=os.getenv("VAULT_ADDR", "http://vault:8200"),
        token=os.getenv("VAULT_TOKEN")
    )
    if not client.is_authenticated():
        raise Exception("Vault authentication failed")
    return client

def get_secret(path: str, key: str = None) -> dict:
    """Retrieve secret from Vault"""
    client = get_vault_client()
    
    # Read secret
    response = client.secrets.kv.v2.read_secret_version(
        path=path,
        mount_point="secret"
    )
    
    secret_data = response["data"]["data"]
    
    if key:
        return secret_data.get(key)
    return secret_data

# Usage
postgres_password = get_secret("postgres", "password")
redis_password = get_secret("redis-1", "password")
```

**Go:**

```go
// internal/vault/client.go
package vault

import (
    "os"
    vault "github.com/hashicorp/vault/api"
)

func GetClient() (*vault.Client, error) {
    config := vault.DefaultConfig()
    config.Address = os.Getenv("VAULT_ADDR")
    
    client, err := vault.NewClient(config)
    if err != nil {
        return nil, err
    }
    
    client.SetToken(os.Getenv("VAULT_TOKEN"))
    return client, nil
}

func GetSecret(path, key string) (string, error) {
    client, err := GetClient()
    if err != nil {
        return "", err
    }
    
    secret, err := client.Logical().Read("secret/data/" + path)
    if err != nil {
        return "", err
    }
    
    data := secret.Data["data"].(map[string]interface{})
    return data[key].(string), nil
}

// Usage
postgresPassword, _ := vault.GetSecret("postgres", "password")
```

**Node.js:**

```javascript
// src/vault.js
const vault = require('node-vault');

function getVaultClient() {
  const client = vault({
    apiVersion: 'v1',
    endpoint: process.env.VAULT_ADDR || 'http://vault:8200',
    token: process.env.VAULT_TOKEN
  });
  return client;
}

async function getSecret(path, key = null) {
  const client = getVaultClient();
  
  const response = await client.read(`secret/data/${path}`);
  const secretData = response.data.data;
  
  if (key) {
    return secretData[key];
  }
  return secretData;
}

// Usage
const postgresPassword = await getSecret('postgres', 'password');
```

## Database Integration

### Connection Pooling

**Python (SQLAlchemy):**

```python
# app/database.py
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from app.vault import get_secret

# Get credentials from Vault
POSTGRES_PASSWORD = get_secret("postgres", "password")

# Create database URL
DATABASE_URL = f"postgresql://postgres:{POSTGRES_PASSWORD}@postgres:5432/myapp"

# Create engine with pooling
engine = create_engine(
    DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_timeout=30,
    pool_recycle=3600,
    pool_pre_ping=True
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    """Dependency for database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# Usage in router
from fastapi import Depends
from sqlalchemy.orm import Session

@router.get("/users")
async def get_users(db: Session = Depends(get_db)):
    users = db.query(User).all()
    return users
```

**Go (pgx):**

```go
// internal/database/postgres.go
package database

import (
    "context"
    "fmt"
    "github.com/jackc/pgx/v5/pgxpool"
    "myapp/internal/vault"
)

func NewPostgresPool() (*pgxpool.Pool, error) {
    password, _ := vault.GetSecret("postgres", "password")
    
    dsn := fmt.Sprintf(
        "postgres://postgres:%s@postgres:5432/myapp?pool_max_conns=10",
        password,
    )
    
    config, err := pgxpool.ParseConfig(dsn)
    if err != nil {
        return nil, err
    }
    
    config.MaxConns = 10
    config.MinConns = 2
    
    pool, err := pgxpool.NewWithConfig(context.Background(), config)
    if err != nil {
        return nil, err
    }
    
    return pool, nil
}

// Usage
pool, _ := database.NewPostgresPool()
defer pool.Close()

rows, _ := pool.Query(context.Background(), "SELECT * FROM users")
```

### Query Patterns

**Python:**

```python
# app/services/database.py
from sqlalchemy.orm import Session
from sqlalchemy import text

class DatabaseService:
    def __init__(self, db: Session):
        self.db = db
    
    def get_user(self, user_id: int):
        """Get user by ID"""
        return self.db.query(User).filter(User.id == user_id).first()
    
    def create_user(self, name: str, email: str):
        """Create new user"""
        user = User(name=name, email=email)
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        return user
    
    def raw_query(self, query: str):
        """Execute raw SQL"""
        result = self.db.execute(text(query))
        return result.fetchall()
```

## Redis Integration

### Cache Operations

**Python:**

```python
# app/cache.py
import redis
from app.vault import get_secret
import json

# Get credentials
REDIS_PASSWORD = get_secret("redis-1", "password")

# Create Redis client (cluster mode)
redis_client = redis.RedisCluster(
    host='redis-1',
    port=6379,
    password=REDIS_PASSWORD,
    decode_responses=True
)

def cache_set(key: str, value: any, ttl: int = 300):
    """Set cache value with TTL"""
    redis_client.setex(key, ttl, json.dumps(value))

def cache_get(key: str):
    """Get cache value"""
    value = redis_client.get(key)
    if value:
        return json.loads(value)
    return None

def cache_delete(key: str):
    """Delete cache key"""
    redis_client.delete(key)

# Usage in router
@router.get("/users/{user_id}")
async def get_user(user_id: int, db: Session = Depends(get_db)):
    # Check cache first
    cache_key = f"user:{user_id}"
    cached_user = cache_get(cache_key)
    if cached_user:
        return cached_user
    
    # Query database
    user = db.query(User).filter(User.id == user_id).first()
    
    # Store in cache
    cache_set(cache_key, user.dict())
    
    return user
```

## RabbitMQ Integration

### Publishing Messages

**Python:**

```python
# app/messaging.py
import pika
from app.vault import get_secret

def get_rabbitmq_connection():
    """Create RabbitMQ connection"""
    password = get_secret("rabbitmq", "password")
    
    credentials = pika.PlainCredentials('guest', password)
    parameters = pika.ConnectionParameters(
        host='rabbitmq',
        port=5672,
        credentials=credentials
    )
    
    connection = pika.BlockingConnection(parameters)
    return connection

def publish_message(queue: str, message: dict):
    """Publish message to queue"""
    connection = get_rabbitmq_connection()
    channel = connection.channel()
    
    channel.queue_declare(queue=queue, durable=True)
    
    channel.basic_publish(
        exchange='',
        routing_key=queue,
        body=json.dumps(message),
        properties=pika.BasicProperties(
            delivery_mode=2  # Make message persistent
        )
    )
    
    connection.close()

# Usage
publish_message('user_events', {'event': 'user_created', 'user_id': 123})
```

## Health Checks

### Comprehensive Health Check

**Python:**

```python
# app/routers/health.py
from fastapi import APIRouter, status
from sqlalchemy import text
import redis

router = APIRouter()

@router.get("/")
async def health_check():
    """Basic health check"""
    return {"status": "healthy"}

@router.get("/ready")
async def readiness_check(db: Session = Depends(get_db)):
    """Check if application is ready"""
    checks = {
        "status": "healthy",
        "checks": {}
    }
    
    # Check database
    try:
        db.execute(text("SELECT 1"))
        checks["checks"]["database"] = "healthy"
    except Exception as e:
        checks["status"] = "unhealthy"
        checks["checks"]["database"] = f"unhealthy: {str(e)}"
    
    # Check Redis
    try:
        redis_client.ping()
        checks["checks"]["cache"] = "healthy"
    except Exception as e:
        checks["status"] = "unhealthy"
        checks["checks"]["cache"] = f"unhealthy: {str(e)}"
    
    # Check RabbitMQ
    try:
        connection = get_rabbitmq_connection()
        connection.close()
        checks["checks"]["messaging"] = "healthy"
    except Exception as e:
        checks["status"] = "unhealthy"
        checks["checks"]["messaging"] = f"unhealthy: {str(e)}"
    
    if checks["status"] == "unhealthy":
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content=checks
        )
    
    return checks
```

## API Documentation

### OpenAPI/Swagger

**Python FastAPI (automatic):**

```python
# app/main.py
app = FastAPI(
    title="My API",
    description="API for managing users and data",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json"
)

# Access docs at: http://localhost:8000/docs
```

**Manual OpenAPI spec:**

```yaml
# openapi.yaml
openapi: 3.0.0
info:
  title: My API
  version: 1.0.0
paths:
  /health:
    get:
      summary: Health check
      responses:
        '200':
          description: Service is healthy
  /api/users:
    get:
      summary: List users
      responses:
        '200':
          description: List of users
```

## Testing

### Unit Tests

**Python (pytest):**

```python
# tests/test_users.py
import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)

def test_health_check():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

def test_get_users():
    response = client.get("/api/users")
    assert response.status_code == 200
    assert isinstance(response.json(), list)

@pytest.fixture
def db_session():
    # Create test database session
    # Yield session
    # Cleanup
    pass
```

### Integration Tests

```bash
# Run integration tests
./tests/test-myapi.sh
```

## Deployment

### Docker Build

```dockerfile
# Dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app/ ./app/

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Multi-stage Build

```dockerfile
# Dockerfile (multi-stage)
FROM python:3.11-slim AS builder

WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11-slim

WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY app/ ./app/

ENV PATH=/root/.local/bin:$PATH

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

## Related Documentation

- [API Patterns](API-Patterns) - Common API patterns
- [Reference Applications](Reference-Applications) - Reference app details
- [API Endpoints](API-Endpoints) - Endpoint documentation
- [Testing Guide](Testing-Guide) - Testing strategies
- [Vault Integration](Vault-Integration) - Vault usage
- [Local Development Setup](Local-Development-Setup) - Development environment

---

**Quick Reference Card:**

```python
# Vault
from app.vault import get_secret
password = get_secret("postgres", "password")

# Database
from app.database import get_db
db = get_db()

# Cache
from app.cache import cache_get, cache_set
cache_set("key", {"data": "value"}, ttl=300)

# Messaging
from app.messaging import publish_message
publish_message("queue", {"event": "created"})

# Health Check
@router.get("/health")
async def health():
    return {"status": "healthy"}
```
