# Environment Variables

## Table of Contents

- [Overview](#overview)
- [Core Configuration](#core-configuration)
- [Vault Configuration](#vault-configuration)
- [Database Services](#database-services)
- [Redis Cluster](#redis-cluster)
- [RabbitMQ Configuration](#rabbitmq-configuration)
- [MongoDB Configuration](#mongodb-configuration)
- [Observability Stack](#observability-stack)
- [Reference Applications](#reference-applications)
- [Network Configuration](#network-configuration)
- [Performance Tuning](#performance-tuning)
- [TLS Configuration](#tls-configuration)
- [Default Values](#default-values)
- [Related Pages](#related-pages)

## Overview

All environment variables are stored in the `.env` file in the project root. Copy `.env.example` to `.env` to get started.

**Important:** Passwords are intentionally empty in the `.env` file - they are loaded from Vault at runtime.

## Core Configuration

```bash
# Project name (affects container names)
COMPOSE_PROJECT_NAME=devstack-core

# Environment (dev, staging, prod)
ENVIRONMENT=development

# Vault integration
VAULT_ADDR=http://vault:8200
VAULT_TOKEN=  # Loaded at runtime from ~/.config/vault/root-token
```

## Vault Configuration

```bash
# Network
VAULT_IP=172.20.0.21
VAULT_PORT=8200

# Storage
VAULT_STORAGE_TYPE=file
VAULT_STORAGE_PATH=/vault/data

# TLS (disabled in dev mode)
VAULT_TLS_DISABLE=1

# Unseal configuration
VAULT_KEYS_FILE=/vault-keys/keys.json
VAULT_AUTO_UNSEAL=true
```

## Database Services

### PostgreSQL

```bash
# Network
POSTGRES_IP=172.20.0.10
POSTGRES_PORT=5432

# Database and user
POSTGRES_DB=devdb
POSTGRES_USER=devuser
POSTGRES_PASSWORD=  # Loaded from Vault

# Performance tuning
POSTGRES_MAX_CONNECTIONS=200
POSTGRES_SHARED_BUFFERS=256MB
POSTGRES_EFFECTIVE_CACHE_SIZE=1GB
POSTGRES_WORK_MEM=4MB
POSTGRES_MAINTENANCE_WORK_MEM=64MB

# Logging
POSTGRES_LOG_STATEMENT=all
POSTGRES_LOG_CONNECTIONS=on

# TLS
POSTGRES_ENABLE_TLS=true
POSTGRES_TLS_PORT=5432
```

### MySQL

```bash
# Network
MYSQL_IP=172.20.0.12
MYSQL_PORT=3306

# Database and user
MYSQL_DATABASE=devdb
MYSQL_USER=devuser
MYSQL_PASSWORD=  # Loaded from Vault
MYSQL_ROOT_PASSWORD=  # Loaded from Vault

# Performance tuning
MYSQL_MAX_CONNECTIONS=200
MYSQL_INNODB_BUFFER_POOL_SIZE=256M
MYSQL_INNODB_LOG_FILE_SIZE=64M

# TLS
MYSQL_ENABLE_TLS=true
MYSQL_TLS_PORT=3306
```

## Redis Cluster

```bash
# Node 1
REDIS_1_IP=172.20.0.13
REDIS_1_PORT=6379
REDIS_1_TLS_PORT=6380
REDIS_1_CLUSTER_BUS_PORT=16379
REDIS_1_PASSWORD=  # Loaded from Vault

# Node 2
REDIS_2_IP=172.20.0.16
REDIS_2_PORT=6379
REDIS_2_TLS_PORT=6380
REDIS_2_CLUSTER_BUS_PORT=16379

# Node 3
REDIS_3_IP=172.20.0.17
REDIS_3_PORT=6379
REDIS_3_TLS_PORT=6380
REDIS_3_CLUSTER_BUS_PORT=16379

# Cluster configuration
REDIS_CLUSTER_ENABLED=yes
REDIS_CLUSTER_REPLICAS=0

# Performance
REDIS_MAXMEMORY=256mb
REDIS_MAXMEMORY_POLICY=allkeys-lru

# TLS
REDIS_ENABLE_TLS=true

# Persistence
REDIS_SAVE="900 1 300 10 60 10000"
REDIS_APPENDONLY=yes
REDIS_APPENDFSYNC=everysec
```

## RabbitMQ Configuration

```bash
# Network
RABBITMQ_IP=172.20.0.14
RABBITMQ_PORT=5672
RABBITMQ_TLS_PORT=5671
RABBITMQ_MANAGEMENT_PORT=15672
RABBITMQ_MANAGEMENT_TLS_PORT=15671

# User configuration
RABBITMQ_DEFAULT_USER=devuser
RABBITMQ_DEFAULT_PASS=  # Loaded from Vault
RABBITMQ_DEFAULT_VHOST=/

# TLS
RABBITMQ_ENABLE_TLS=true

# Memory
RABBITMQ_VM_MEMORY_HIGH_WATERMARK=0.6
```

## MongoDB Configuration

```bash
# Network
MONGODB_IP=172.20.0.15
MONGODB_PORT=27017

# Database and user
MONGODB_DATABASE=devdb
MONGODB_USER=devuser
MONGODB_PASSWORD=  # Loaded from Vault
MONGODB_ROOT_USER=root
MONGODB_ROOT_PASSWORD=  # Loaded from Vault

# TLS
MONGODB_ENABLE_TLS=true
MONGODB_TLS_PORT=27017

# Performance
MONGODB_CACHE_SIZE_GB=0.5
```

## Observability Stack

```bash
# Prometheus
PROMETHEUS_IP=172.20.0.101
PROMETHEUS_PORT=9090

# Grafana
GRAFANA_IP=172.20.0.102
GRAFANA_PORT=3001
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=admin

# Loki
LOKI_IP=172.20.0.103
LOKI_PORT=3100

# cAdvisor
CADVISOR_PORT=8080
```

## Reference Applications

```bash
# FastAPI (code-first)
REFERENCE_API_IP=172.20.0.100
REFERENCE_API_HTTP_PORT=8000
REFERENCE_API_HTTPS_PORT=8443

# FastAPI (API-first)
API_FIRST_IP=172.20.0.107
API_FIRST_HTTP_PORT=8001
API_FIRST_HTTPS_PORT=8444

# Go API
GO_API_IP=172.20.0.104
GO_API_HTTP_PORT=8002
GO_API_HTTPS_PORT=8445

# Node.js API
NODEJS_API_IP=172.20.0.105
NODEJS_API_HTTP_PORT=8003
NODEJS_API_HTTPS_PORT=8446

# Rust API
RUST_API_IP=172.20.0.106
RUST_API_HTTP_PORT=8004
RUST_API_HTTPS_PORT=8447
```

## Network Configuration

```bash
# Network name
NETWORK_NAME=dev-services

# Subnet
NETWORK_SUBNET=172.20.0.0/16
NETWORK_GATEWAY=172.20.0.1

# DNS
DNS_SERVERS=8.8.8.8,8.8.4.4
```

## Performance Tuning

```bash
# Colima VM resources (set before starting)
COLIMA_CPU=4
COLIMA_MEMORY=8
COLIMA_DISK=50

# Container resource limits
POSTGRES_MEM_LIMIT=2g
POSTGRES_MEM_RESERVATION=1g
POSTGRES_CPU_LIMIT=2.0

MYSQL_MEM_LIMIT=1g
REDIS_MEM_LIMIT=512m
RABBITMQ_MEM_LIMIT=512m
MONGODB_MEM_LIMIT=1g
```

## TLS Configuration

```bash
# Enable/disable TLS per service
POSTGRES_ENABLE_TLS=true
MYSQL_ENABLE_TLS=true
MONGODB_ENABLE_TLS=true
REDIS_ENABLE_TLS=true
RABBITMQ_ENABLE_TLS=true

# Certificate locations (on host)
VAULT_CERTS_DIR=/Users/${USER}/.config/vault/certs
```

## Default Values

**Complete `.env` file example:**

```bash
# Project Configuration
COMPOSE_PROJECT_NAME=devstack-core
ENVIRONMENT=development

# Vault
VAULT_ADDR=http://vault:8200
VAULT_IP=172.20.0.21
VAULT_PORT=8200
VAULT_TLS_DISABLE=1

# PostgreSQL
POSTGRES_IP=172.20.0.10
POSTGRES_PORT=5432
POSTGRES_DB=devdb
POSTGRES_USER=devuser
POSTGRES_PASSWORD=
POSTGRES_MAX_CONNECTIONS=200
POSTGRES_SHARED_BUFFERS=256MB
POSTGRES_EFFECTIVE_CACHE_SIZE=1GB
POSTGRES_ENABLE_TLS=true

# MySQL
MYSQL_IP=172.20.0.12
MYSQL_PORT=3306
MYSQL_DATABASE=devdb
MYSQL_USER=devuser
MYSQL_PASSWORD=
MYSQL_ROOT_PASSWORD=
MYSQL_MAX_CONNECTIONS=200
MYSQL_INNODB_BUFFER_POOL_SIZE=256M
MYSQL_ENABLE_TLS=true

# MongoDB
MONGODB_IP=172.20.0.15
MONGODB_PORT=27017
MONGODB_DATABASE=devdb
MONGODB_USER=devuser
MONGODB_PASSWORD=
MONGODB_ROOT_PASSWORD=
MONGODB_ENABLE_TLS=true

# Redis Cluster
REDIS_1_IP=172.20.0.13
REDIS_1_PORT=6379
REDIS_1_TLS_PORT=6380
REDIS_2_IP=172.20.0.16
REDIS_2_PORT=6379
REDIS_2_TLS_PORT=6380
REDIS_3_IP=172.20.0.17
REDIS_3_PORT=6379
REDIS_3_TLS_PORT=6380
REDIS_MAXMEMORY=256mb
REDIS_ENABLE_TLS=true

# RabbitMQ
RABBITMQ_IP=172.20.0.14
RABBITMQ_PORT=5672
RABBITMQ_TLS_PORT=5671
RABBITMQ_MANAGEMENT_PORT=15672
RABBITMQ_DEFAULT_USER=devuser
RABBITMQ_DEFAULT_PASS=
RABBITMQ_ENABLE_TLS=true

# Observability
PROMETHEUS_IP=172.20.0.101
PROMETHEUS_PORT=9090
GRAFANA_IP=172.20.0.102
GRAFANA_PORT=3001
LOKI_IP=172.20.0.103
LOKI_PORT=3100

# Reference Applications
REFERENCE_API_IP=172.20.0.100
REFERENCE_API_HTTP_PORT=8000
REFERENCE_API_HTTPS_PORT=8443
```

## Usage Examples

```bash
# Load environment variables
source .env

# Access in scripts
echo $POSTGRES_PORT
echo $VAULT_ADDR

# Use in docker-compose
services:
  postgres:
    ports:
      - "${POSTGRES_PORT}:5432"
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}

# Override variables
POSTGRES_PORT=5433 docker compose up -d postgres

# Set temporarily
export POSTGRES_MAX_CONNECTIONS=500
docker compose up -d postgres
```

## Related Pages

- [Service-Configuration](Service-Configuration) - Detailed service config
- [Performance-Tuning](Performance-Tuning) - Performance variables
- [TLS-Configuration](TLS-Configuration) - TLS settings
- [Network-Issues](Network-Issues) - Network variables
- [Port-Reference](Port-Reference) - Port mappings
