# API Endpoints

## Table of Contents

- [FastAPI Endpoints (Code-First)](#fastapi-endpoints-code-first)
- [FastAPI Endpoints (API-First)](#fastapi-endpoints-api-first)
- [Common Endpoints](#common-endpoints)
- [Database CRUD Endpoints](#database-crud-endpoints)
- [Redis Cluster Endpoints](#redis-cluster-endpoints)
- [RabbitMQ Messaging Endpoints](#rabbitmq-messaging-endpoints)

## FastAPI Endpoints (Code-First)

**Base URL:** `http://localhost:8000`

### Health and Docs
- `GET /health` - Health check
- `GET /metrics` - Prometheus metrics
- `GET /docs` - Swagger UI
- `GET /redoc` - ReDoc documentation
- `GET /openapi.json` - OpenAPI schema

### PostgreSQL Endpoints
- `POST /api/v1/postgres/users` - Create user
- `GET /api/v1/postgres/users` - List users
- `GET /api/v1/postgres/users/{id}` - Get user
- `PUT /api/v1/postgres/users/{id}` - Update user
- `DELETE /api/v1/postgres/users/{id}` - Delete user

### MySQL Endpoints
- `POST /api/v1/mysql/products` - Create product
- `GET /api/v1/mysql/products` - List products
- `GET /api/v1/mysql/products/{id}` - Get product
- `PUT /api/v1/mysql/products/{id}` - Update product
- `DELETE /api/v1/mysql/products/{id}` - Delete product

### MongoDB Endpoints
- `POST /api/v1/mongodb/documents` - Create document
- `GET /api/v1/mongodb/documents` - List documents
- `GET /api/v1/mongodb/documents/{id}` - Get document
- `PUT /api/v1/mongodb/documents/{id}` - Update document
- `DELETE /api/v1/mongodb/documents/{id}` - Delete document

### Redis Cluster Endpoints
- `POST /api/v1/redis/set` - Set key-value
- `GET /api/v1/redis/get/{key}` - Get value
- `DELETE /api/v1/redis/delete/{key}` - Delete key
- `GET /redis-cluster/info` - Cluster info
- `GET /redis-cluster/nodes` - Node status
- `GET /redis-cluster/slots` - Slot distribution

### RabbitMQ Endpoints
- `POST /api/v1/rabbitmq/publish` - Publish message
- `GET /api/v1/rabbitmq/consume` - Consume message
- `GET /api/v1/rabbitmq/queue-stats` - Queue statistics

## FastAPI Endpoints (API-First)

**Base URL:** `http://localhost:8001`

Same endpoints as code-first implementation, following OpenAPI spec defined in `openapi.yaml`.

## Common Endpoints

All reference applications implement:

```bash
# Health check
curl http://localhost:8000/health
# Response: {"status": "healthy", "version": "1.0.0"}

# Metrics (Prometheus format)
curl http://localhost:8000/metrics
# Response: Prometheus metrics

# API documentation
open http://localhost:8000/docs
```

## Database CRUD Endpoints

### Create User (PostgreSQL)
```bash
curl -X POST http://localhost:8000/api/v1/postgres/users \
  -H "Content-Type: application/json" \
  -d '{
    "username": "john_doe",
    "email": "john@example.com",
    "full_name": "John Doe"
  }'

# Response:
{
  "id": 1,
  "username": "john_doe",
  "email": "john@example.com",
  "full_name": "John Doe",
  "created_at": "2024-01-15T10:30:00Z"
}
```

### List Users
```bash
curl http://localhost:8000/api/v1/postgres/users

# Response:
{
  "users": [
    {
      "id": 1,
      "username": "john_doe",
      "email": "john@example.com"
    }
  ],
  "total": 1
}
```

### Get User
```bash
curl http://localhost:8000/api/v1/postgres/users/1

# Response:
{
  "id": 1,
  "username": "john_doe",
  "email": "john@example.com",
  "full_name": "John Doe",
  "created_at": "2024-01-15T10:30:00Z"
}
```

### Update User
```bash
curl -X PUT http://localhost:8000/api/v1/postgres/users/1 \
  -H "Content-Type: application/json" \
  -d '{
    "email": "john.doe@example.com",
    "full_name": "John A. Doe"
  }'
```

### Delete User
```bash
curl -X DELETE http://localhost:8000/api/v1/postgres/users/1

# Response:
{
  "message": "User deleted successfully"
}
```

## Redis Cluster Endpoints

### Set Value
```bash
curl -X POST http://localhost:8000/api/v1/redis/set \
  -H "Content-Type: application/json" \
  -d '{
    "key": "user:1000",
    "value": "John Doe",
    "ttl": 3600
  }'

# Response:
{
  "success": true,
  "key": "user:1000",
  "node": "172.20.0.16:6379"
}
```

### Get Value
```bash
curl http://localhost:8000/api/v1/redis/get/user:1000

# Response:
{
  "key": "user:1000",
  "value": "John Doe",
  "ttl": 3542
}
```

### Cluster Info
```bash
curl http://localhost:8000/redis-cluster/info

# Response:
{
  "cluster_state": "ok",
  "cluster_slots_assigned": 16384,
  "cluster_known_nodes": 3,
  "cluster_size": 3
}
```

### Node Status
```bash
curl http://localhost:8000/redis-cluster/nodes

# Response:
{
  "nodes": [
    {
      "id": "a1b2c3...",
      "ip": "172.20.0.13",
      "port": 6379,
      "role": "master",
      "slots": "0-5460",
      "slot_count": 5461
    },
    ...
  ]
}
```

## RabbitMQ Messaging Endpoints

### Publish Message
```bash
curl -X POST http://localhost:8000/api/v1/rabbitmq/publish \
  -H "Content-Type: application/json" \
  -d '{
    "queue": "tasks",
    "message": {
      "task": "process_order",
      "order_id": 12345
    }
  }'

# Response:
{
  "success": true,
  "queue": "tasks",
  "message_id": "abc123"
}
```

### Consume Message
```bash
curl http://localhost:8000/api/v1/rabbitmq/consume?queue=tasks

# Response:
{
  "message": {
    "task": "process_order",
    "order_id": 12345
  },
  "delivery_tag": 1
}
```

### Queue Stats
```bash
curl http://localhost:8000/api/v1/rabbitmq/queue-stats?queue=tasks

# Response:
{
  "queue": "tasks",
  "messages": 10,
  "consumers": 2,
  "message_rate": 5.2
}
```

## Related Pages

- [Service-Configuration](Service-Configuration) - API configuration
- [Health-Monitoring](Health-Monitoring) - Health endpoints
- [Redis-Cluster](Redis-Cluster) - Redis cluster details
