# Environment Variable Reference

Complete reference for all environment variables used by DevStack Core services, including Vault, databases, Redis, RabbitMQ, and observability components.

## Table of Contents

- [Overview](#overview)
- [Quick Reference](#quick-reference)
- [Core Services](#core-services)
  - [Vault](#vault)
  - [PostgreSQL](#postgresql)
  - [MySQL](#mysql)
  - [MongoDB](#mongodb)
  - [Redis Cluster](#redis-cluster)
  - [RabbitMQ](#rabbitmq)
- [Application Services](#application-services)
  - [Forgejo (Git Server)](#forgejo-git-server)
  - [Reference APIs](#reference-apis)
- [Observability Stack](#observability-stack)
  - [Prometheus](#prometheus)
  - [Grafana](#grafana)
  - [Loki](#loki)
  - [Vector](#vector)
- [Network Configuration](#network-configuration)
- [TLS/SSL Configuration](#tlsssl-configuration)
- [Performance Tuning](#performance-tuning)
- [Health Check Configuration](#health-check-configuration)
- [Examples](#examples)

---

## Overview

This document provides a comprehensive reference for all environment variables used in the DevStack Core infrastructure. Variables are organized by service and include:

- **Variable Name**: The environment variable name
- **Default Value**: Default if not set
- **Description**: What it controls
- **Required**: Whether it must be set
- **Source**: Where the value comes from (.env, Vault, computed)

**Important**: Most service passwords are managed by Vault and should NOT be set in `.env`. See the [Vault](#vault) section for details.

---

## Quick Reference

| Service | Key Variables | Vault Path | Ports |
|---------|---------------|------------|-------|
| **Vault** | `VAULT_ADDR`, `VAULT_TOKEN` | N/A | 8200 |
| **PostgreSQL** | `POSTGRES_USER`, `POSTGRES_DB` | `secret/postgres` | 5432 |
| **MySQL** | `MYSQL_USER`, `MYSQL_DATABASE` | `secret/mysql` | 3306 |
| **MongoDB** | `MONGO_INITDB_DATABASE` | `secret/mongodb` | 27017 |
| **Redis** | N/A | `secret/redis-1` | 6379-6381 (non-TLS), 6390-6392 (TLS) |
| **RabbitMQ** | `RABBITMQ_DEFAULT_VHOST` | `secret/rabbitmq` | 5672, 15672 |
| **Forgejo** | `FORGEJO_APP_NAME` | `secret/forgejo` | 3000, 222 |

---

## Core Services

### Vault

HashiCorp Vault manages all service credentials and TLS certificates.

| Variable | Default | Description | Required | Source |
|----------|---------|-------------|----------|--------|
| `VAULT_ADDR` | `http://vault:8200` | Vault server URL | ✅ Yes | .env |
| `VAULT_TOKEN` | (empty) | Root authentication token | ✅ Yes | ~/.config/vault/root-token |
| `VAULT_IP` | `172.20.0.21` | Static IP in Docker network | ✅ Yes | .env |

**Setup:**
```bash
# After initial start
./devstack.sh vault-init      # Creates token
./devstack.sh vault-bootstrap # Stores credentials

# Token location
cat ~/.config/vault/root-token
```

**Usage:**
```bash
# Set token for CLI use
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
export VAULT_ADDR=http://localhost:8200

# Retrieve service password
vault kv get -field=password secret/postgres
```

---

### PostgreSQL

PostgreSQL 18 with PgBouncer connection pooling.

#### Credentials (Vault-Managed)

**Vault Path:** `secret/postgres`

| Field | Description |
|-------|-------------|
| `user` | Database user (dev_admin) |
| `password` | Auto-generated password |
| `database` | Database name (dev_database) |

#### Environment Variables

| Variable | Default | Description | Required |
|----------|---------|-------------|----------|
| `POSTGRES_USER` | `dev_admin` | Database username | ✅ Yes |
| `POSTGRES_DB` | `dev_database` | Database name | ✅ Yes |
| `POSTGRES_PASSWORD` | (empty) | **Loaded from Vault** | ⚠️ Auto |
| `POSTGRES_IP` | `172.20.0.10` | Static IP address | ✅ Yes |
| `POSTGRES_HOST_PORT` | `5432` | Host port mapping | ✅ Yes |
| `POSTGRES_ENABLE_TLS` | `true` | Enable TLS support | No |
| `POSTGRES_MAX_CONNECTIONS` | `100` | Max simultaneous connections | No |
| `POSTGRES_SHARED_BUFFERS` | `256MB` | Shared memory buffer size | No |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | `1GB` | Query planner cache hint | No |
| `POSTGRES_WORK_MEM` | `8MB` | Per-operation memory | No |

#### PgBouncer Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PGBOUNCER_IP` | `172.20.0.11` | Static IP address |
| `PGBOUNCER_HOST_PORT` | `6432` | Host port mapping |

#### Health Check Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_HEALTH_INTERVAL` | `60s` | Time between health checks |
| `POSTGRES_HEALTH_TIMEOUT` | `5s` | Health check timeout |
| `POSTGRES_HEALTH_RETRIES` | `5` | Retries before unhealthy |
| `POSTGRES_HEALTH_START_PERIOD` | `30s` | Grace period on startup |

**Example Usage:**
```bash
# Connection string with Vault password
PGPASSWORD=$(vault kv get -field=password secret/postgres) \
  psql -h localhost -p 5432 -U dev_admin -d dev_database
```

---

### MySQL

MySQL 8.0.40 for legacy application support.

#### Credentials (Vault-Managed)

**Vault Path:** `secret/mysql`

| Field | Description |
|-------|-------------|
| `root_password` | Root user password |
| `user` | Database user (dev_admin) |
| `password` | User password |
| `database` | Database name (dev_database) |

#### Environment Variables

| Variable | Default | Description | Required |
|----------|---------|-------------|----------|
| `MYSQL_USER` | `dev_admin` | Database username | ✅ Yes |
| `MYSQL_DATABASE` | `dev_database` | Database name | ✅ Yes |
| `MYSQL_ROOT_PASSWORD` | (empty) | **Loaded from Vault** | ⚠️ Auto |
| `MYSQL_PASSWORD` | (empty) | **Loaded from Vault** | ⚠️ Auto |
| `MYSQL_IP` | `172.20.0.12` | Static IP address | ✅ Yes |
| `MYSQL_HOST_PORT` | `3306` | Host port mapping | ✅ Yes |
| `MYSQL_ENABLE_TLS` | `true` | Enable TLS support | No |
| `MYSQL_MAX_CONNECTIONS` | `100` | Max simultaneous connections | No |
| `MYSQL_INNODB_BUFFER_POOL` | `256M` | InnoDB buffer pool size | No |

#### Health Check Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MYSQL_HEALTH_INTERVAL` | `60s` | Time between health checks |
| `MYSQL_HEALTH_TIMEOUT` | `5s` | Health check timeout |
| `MYSQL_HEALTH_RETRIES` | `5` | Retries before unhealthy |

**Example Usage:**
```bash
# Connection with Vault password
mysql -h 127.0.0.1 -P 3306 -u dev_admin \
  -p$(vault kv get -field=password secret/mysql) \
  dev_database
```

---

### MongoDB

MongoDB 7 for NoSQL data storage.

#### Credentials (Vault-Managed)

**Vault Path:** `secret/mongodb`

| Field | Description |
|-------|-------------|
| `root_username` | Root username (admin) |
| `root_password` | Root password |
| `username` | Application username (dev_admin) |
| `password` | Application password |
| `database` | Database name (dev_database) |

#### Environment Variables

| Variable | Default | Description | Required |
|----------|---------|-------------|----------|
| `MONGO_INITDB_ROOT_USERNAME` | `admin` | Root username | ✅ Yes |
| `MONGO_INITDB_ROOT_PASSWORD` | (empty) | **Loaded from Vault** | ⚠️ Auto |
| `MONGO_INITDB_DATABASE` | `dev_database` | Initial database | ✅ Yes |
| `MONGODB_IP` | `172.20.0.15` | Static IP address | ✅ Yes |
| `MONGODB_HOST_PORT` | `27017` | Host port mapping | ✅ Yes |
| `MONGODB_ENABLE_TLS` | `true` | Enable TLS support | No |

#### Health Check Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `MONGODB_HEALTH_INTERVAL` | `60s` | Time between health checks |
| `MONGODB_HEALTH_TIMEOUT` | `5s` | Health check timeout |
| `MONGODB_HEALTH_RETRIES` | `5` | Retries before unhealthy |

**Example Usage:**
```bash
# Connection string
mongosh "mongodb://dev_admin:$(vault kv get -field=password secret/mongodb)@localhost:27017/dev_database"
```

---

### Redis Cluster

3-node Redis cluster for distributed caching.

#### Credentials (Vault-Managed)

**Vault Path:** `secret/redis-1` (shared across all nodes)

| Field | Description |
|-------|-------------|
| `password` | Shared cluster password |

#### Environment Variables

**Node 1:**
| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_1_IP` | `172.20.2.13` | Static IP address (data network) |
| `REDIS_1_HOST_PORT` | `6379` | Host → container port 6379 (non-TLS) |
| `REDIS_1_TLS_PORT` | `6390` | Host → container port 6380 (TLS) |
| `REDIS_1_CLUSTER_PORT` | `16379` | Cluster bus port (internal) |

**Node 2:**
| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_2_IP` | `172.20.2.16` | Static IP address (data network) |
| `REDIS_2_HOST_PORT` | `6380` | Host → container port 6379 (non-TLS) |
| `REDIS_2_TLS_PORT` | `6391` | Host → container port 6380 (TLS) |
| `REDIS_2_CLUSTER_PORT` | `16380` | Cluster bus port (internal) |

**Node 3:**
| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_3_IP` | `172.20.2.17` | Static IP address (data network) |
| `REDIS_3_HOST_PORT` | `6381` | Host → container port 6379 (non-TLS) |
| `REDIS_3_TLS_PORT` | `6392` | Host → container port 6380 (TLS) |
| `REDIS_3_CLUSTER_PORT` | `16381` | Cluster bus port (internal) |

**General:**
| Variable | Default | Description |
|----------|---------|-------------|
| `REDIS_ENABLE_TLS` | `true` | Enable TLS on all nodes |
| `REDIS_MAXMEMORY` | `256mb` | Max memory per node |
| `REDIS_HEALTH_INTERVAL` | `60s` | Health check interval |
| `REDIS_HEALTH_TIMEOUT` | `5s` | Health check timeout |
| `REDIS_HEALTH_RETRIES` | `5` | Retries before unhealthy |

**Example Usage:**
```bash
# Connect to cluster (non-TLS)
redis-cli -c -h localhost -p 6379 \
  -a $(vault kv get -field=password secret/redis-1)

# Connect with TLS
redis-cli -c -h localhost -p 6390 --tls \
  --cert ~/.config/vault/certs/redis-1/cert.pem \
  --key ~/.config/vault/certs/redis-1/key.pem \
  --cacert ~/.config/vault/certs/redis-1/ca.pem \
  -a $(vault kv get -field=password secret/redis-1)
```

---

### RabbitMQ

RabbitMQ for message queuing with management UI.

#### Credentials (Vault-Managed)

**Vault Path:** `secret/rabbitmq`

| Field | Description |
|-------|-------------|
| `user` | Username (dev_admin) |
| `password` | Password |
| `vhost` | Virtual host (dev_vhost) |

#### Environment Variables

| Variable | Default | Description | Required |
|----------|---------|-------------|----------|
| `RABBITMQ_DEFAULT_USER` | `dev_admin` | Admin username | ✅ Yes |
| `RABBITMQ_DEFAULT_PASS` | (empty) | **Loaded from Vault** | ⚠️ Auto |
| `RABBITMQ_DEFAULT_VHOST` | `dev_vhost` | Virtual host | ✅ Yes |
| `RABBITMQ_IP` | `172.20.0.14` | Static IP address | ✅ Yes |
| `RABBITMQ_AMQP_PORT` | `5672` | AMQP protocol port | ✅ Yes |
| `RABBITMQ_AMQPS_PORT` | `5671` | AMQPS (TLS) port | No |
| `RABBITMQ_MANAGEMENT_PORT` | `15672` | Management UI port | ✅ Yes |
| `RABBITMQ_ENABLE_TLS` | `true` | Enable TLS support | No |

#### Health Check Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RABBITMQ_HEALTH_INTERVAL` | `60s` | Health check interval |
| `RABBITMQ_HEALTH_TIMEOUT` | `5s` | Health check timeout |
| `RABBITMQ_HEALTH_RETRIES` | `5` | Retries before unhealthy |

**Example Usage:**
```bash
# Management UI
open http://localhost:15672
# Login: dev_admin / <password from Vault>

# Publish message with Python
import pika
credentials = pika.PlainCredentials('dev_admin', vault_password)
connection = pika.BlockingConnection(
    pika.ConnectionParameters('localhost', 5672, 'dev_vhost', credentials)
)
```

---

## Application Services

### Forgejo (Git Server)

Self-hosted Git service with PostgreSQL backend.

#### Credentials (Vault-Managed)

**Vault Path:** `secret/forgejo`

| Field | Description |
|-------|-------------|
| `admin_username` | Admin user (gitadmin) |
| `admin_password` | Admin password |
| `admin_email` | Admin email |

#### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FORGEJO_APP_NAME` | `Colima Git` | Application name |
| `FORGEJO_ADMIN_USER` | `gitadmin` | Admin username |
| `FORGEJO_ADMIN_PASSWORD` | (empty) | **Loaded from Vault** |
| `FORGEJO_ADMIN_EMAIL` | `git@example.com` | Admin email |
| `FORGEJO_IP` | `172.20.0.20` | Static IP address |
| `FORGEJO_HTTP_PORT` | `3000` | HTTP port |
| `FORGEJO_SSH_PORT` | `222` | SSH port |
| `FORGEJO_ENABLE_TLS` | `true` | Enable HTTPS |

**Example Usage:**
```bash
# Access web UI
open http://localhost:3000

# Clone repository
git clone http://localhost:3000/user/repo.git
```

---

### Reference APIs

Six language implementations on ports 8000-8005.

#### Python FastAPI (Code-First)
| Variable | Default | Description |
|----------|---------|-------------|
| `REFERENCE_API_IP` | `172.20.0.100` | Static IP |
| `HTTP_PORT` | `8000` | HTTP port |
| `HTTPS_PORT` | `8443` | HTTPS port (if TLS enabled) |

#### Python FastAPI (API-First)
| Variable | Default | Description |
|----------|---------|-------------|
| `API_FIRST_IP` | `172.20.0.104` | Static IP |
| `HTTP_PORT` | `8001` | HTTP port |
| `HTTPS_PORT` | `8444` | HTTPS port |

#### Go (Gin)
| Variable | Default | Description |
|----------|---------|-------------|
| `GOLANG_API_IP` | `172.20.0.105` | Static IP |
| `HTTP_PORT` | `8002` | HTTP port |
| `HTTPS_PORT` | `8445` | HTTPS port |

#### Node.js (Express)
| Variable | Default | Description |
|----------|---------|-------------|
| `NODEJS_API_IP` | `172.20.0.106` | Static IP |
| `HTTP_PORT` | `8003` | HTTP port |
| `HTTPS_PORT` | `8446` | HTTPS port |

#### Rust (Actix-web)
| Variable | Default | Description |
|----------|---------|-------------|
| `RUST_API_IP` | `172.20.0.107` | Static IP |
| `HTTP_PORT` | `8004` | HTTP port |
| `HTTPS_PORT` | `8447` | HTTPS port |

#### TypeScript (API-First)
| Variable | Default | Description |
|----------|---------|-------------|
| `TYPESCRIPT_API_IP` | `172.20.0.108` | Static IP |
| `HTTP_PORT` | `8005` | HTTP port |
| `HTTPS_PORT` | `8448` | HTTPS port |

---

## Observability Stack

### Prometheus

Metrics collection and monitoring.

| Variable | Default | Description |
|----------|---------|-------------|
| `PROMETHEUS_IP` | `172.20.0.101` | Static IP address |
| `PROMETHEUS_PORT` | `9090` | Web UI port |

**Example Usage:**
```bash
# Access Prometheus UI
open http://localhost:9090
```

---

### Grafana

Visualization and dashboards.

| Variable | Default | Description |
|----------|---------|-------------|
| `GRAFANA_IP` | `172.20.0.102` | Static IP address |
| `GRAFANA_PORT` | `3001` | Web UI port |
| `GF_SECURITY_ADMIN_USER` | `admin` | Admin username |
| `GF_SECURITY_ADMIN_PASSWORD` | `admin` | Admin password |

**Example Usage:**
```bash
# Access Grafana UI
open http://localhost:3001
# Login: admin / admin
```

---

### Loki

Log aggregation.

| Variable | Default | Description |
|----------|---------|-------------|
| `LOKI_IP` | `172.20.0.103` | Static IP address |
| `LOKI_PORT` | `3100` | HTTP port |

---

### Vector

Unified observability data pipeline.

| Variable | Default | Description |
|----------|---------|-------------|
| `VECTOR_IP` | `172.20.0.118` | Static IP address |
| `VECTOR_API_PORT` | `8686` | API port |

---

## Network Configuration

All services run in the `dev-services` Docker bridge network.

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK_SUBNET` | `172.20.0.0/16` | Network CIDR |
| `NETWORK_GATEWAY` | `172.20.0.1` | Gateway IP |

---

## TLS/SSL Configuration

### Global TLS Enablement

| Variable | Default | Description |
|----------|---------|-------------|
| `POSTGRES_ENABLE_TLS` | `true` | PostgreSQL TLS |
| `MYSQL_ENABLE_TLS` | `true` | MySQL TLS |
| `REDIS_ENABLE_TLS` | `true` | Redis TLS |
| `RABBITMQ_ENABLE_TLS` | `true` | RabbitMQ TLS |
| `MONGODB_ENABLE_TLS` | `true` | MongoDB TLS |
| `FORGEJO_ENABLE_TLS` | `true` | Forgejo TLS |

### Certificate Locations

Certificates generated by Vault PKI are stored at:
```
~/.config/vault/
├── ca/
│   ├── ca.pem           # Root CA
│   └── ca-chain.pem     # Full chain
└── certs/
    ├── postgres/
    │   ├── cert.pem
    │   ├── key.pem
    │   └── ca.pem
    ├── mysql/
    ├── redis-1/
    ├── redis-2/
    ├── redis-3/
    ├── rabbitmq/
    └── mongodb/
```

---

## Performance Tuning

### Memory Limits

| Service | Variable | Default | Description |
|---------|----------|---------|-------------|
| PostgreSQL | `POSTGRES_SHARED_BUFFERS` | `256MB` | Shared memory |
| PostgreSQL | `POSTGRES_EFFECTIVE_CACHE_SIZE` | `1GB` | Cache hint |
| MySQL | `MYSQL_INNODB_BUFFER_POOL` | `256M` | InnoDB buffer |
| Redis | `REDIS_MAXMEMORY` | `256mb` | Max memory per node |

### Connection Limits

| Service | Variable | Default |
|---------|----------|---------|
| PostgreSQL | `POSTGRES_MAX_CONNECTIONS` | `100` |
| MySQL | `MYSQL_MAX_CONNECTIONS` | `100` |

---

## Health Check Configuration

Standard health check variables across services:

| Variable Suffix | Description | Typical Default |
|----------------|-------------|-----------------|
| `_HEALTH_INTERVAL` | Time between checks | `60s` |
| `_HEALTH_TIMEOUT` | Timeout per check | `5s` |
| `_HEALTH_RETRIES` | Retries before unhealthy | `5` |
| `_HEALTH_START_PERIOD` | Initial grace period | `30s` |

---

## Examples

### Loading All Variables

```bash
# Source .env file
source .env

# Or use docker-compose
docker compose config
```

### Checking Current Values

```bash
# List all environment variables
./devstack.sh status

# Check specific service
docker compose exec postgres env | grep POSTGRES
```

### Updating Variables

```bash
# 1. Edit .env file
nano .env

# 2. Restart services to apply
./devstack.sh restart

# Or restart specific service
docker compose restart postgres
```

### Retrieving Vault-Managed Credentials

```bash
# Set Vault token
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
export VAULT_ADDR=http://localhost:8200

# Get all PostgreSQL credentials
vault kv get secret/postgres

# Get specific field
vault kv get -field=password secret/postgres

# Get all service passwords
for service in postgres mysql mongodb redis-1 rabbitmq forgejo; do
  echo "$service: $(vault kv get -field=password secret/$service)"
done
```

---

## See Also

- [Installation Guide](INSTALLATION.md)
- [Vault Documentation](VAULT.md)
- [Architecture Overview](ARCHITECTURE.md)
- [Troubleshooting](TROUBLESHOOTING.md)
