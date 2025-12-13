# Service Catalog

Complete inventory of all 23 containerized services in DevStack Core, including ports, health checks, dependencies, and configuration details.

**Version:** 1.0 | **Last Updated:** November 19, 2025

---

## Table of Contents

1. [Overview](#overview)
2. [Service Summary](#service-summary)
3. [Core Data Services](#core-data-services)
4. [Git & Collaboration](#git--collaboration)
5. [Reference Applications](#reference-applications)
6. [Observability Stack](#observability-stack)
7. [Service Profiles](#service-profiles)
8. [Network Assignments](#network-assignments)
9. [Port Mappings](#port-mappings)

---

## Overview

This document serves as the **single source of truth** for all services in the DevStack Core infrastructure. All other documentation references this catalog for service information.

**Total Services:** 23 containerized services
**Service Profiles:** minimal (5), standard (12), full (18), reference (5)
**Networks:** 4-tier segmentation (vault, data, app, observability)

---

## Service Summary

| # | Service | Category | Profile | AppRole | TLS | Ports | Purpose |
|---|---------|----------|---------|---------|-----|-------|---------|
| 1 | vault | Core | all | N/A | Yes | 8200 | Secrets management, PKI |
| 2 | postgres | Core Data | all | ✅ | Dual | 5432 | Primary relational database |
| 3 | pgbouncer | Core Data | standard+ | ✅ | No | 6432 | PostgreSQL connection pooler |
| 4 | mysql | Core Data | all | ✅ | Dual | 3306 | Secondary relational database |
| 5 | mongodb | Core Data | all | ✅ | Dual | 27017 | Document database |
| 6 | redis-1 | Core Data | all | ✅ | Dual | 6379/6380 | Redis cluster node 1 |
| 7 | redis-2 | Core Data | standard+ | ✅ | Dual | 6379/6380 | Redis cluster node 2 |
| 8 | redis-3 | Core Data | standard+ | ✅ | Dual | 6379/6380 | Redis cluster node 3 |
| 9 | rabbitmq | Core Data | all | ✅ | Dual | 5672/15672 | Message broker |
| 10 | forgejo | Git/Collab | all | ✅ | No | 3000/22 | Git server & collaboration |
| 11 | reference-api | Reference | reference | ✅ | No | 8000/8443 | Python FastAPI (code-first) |
| 12 | api-first | Reference | reference | ✅ | No | 8001/8444 | Python FastAPI (API-first) |
| 13 | golang-api | Reference | reference | ✅ | No | 8002/8445 | Go Gin framework |
| 14 | nodejs-api | Reference | reference | ✅ | No | 8003/8446 | Node.js Express |
| 15 | rust-api | Reference | reference | ✅ | No | 8004/8447 | Rust Actix-web |
| 16 | prometheus | Observability | full | No | No | 9090 | Metrics collection |
| 17 | grafana | Observability | full | No | No | 3001 | Metrics visualization |
| 18 | loki | Observability | full | No | No | 3100 | Log aggregation |
| 19 | vector | Observability | full | ✅ | No | 8686 | Log routing & transformation |
| 20 | cadvisor | Observability | full | No | No | 8080 | Container metrics |
| 21 | redis-exporter-1 | Observability | full | ✅ | No | 9121 | Redis node 1 metrics |
| 22 | redis-exporter-2 | Observability | full | ✅ | No | 9122 | Redis node 2 metrics |
| 23 | redis-exporter-3 | Observability | full | ✅ | No | 9123 | Redis node 3 metrics |

**Legend:**
- **AppRole:** ✅ = Uses Vault AppRole authentication
- **TLS:** Dual = Accepts both TLS and non-TLS, Yes = TLS only, No = No TLS
- **Profile:** all = runs in all profiles, standard+ = standard and full, full = full only

---

## Core Data Services

### 1. Vault
- **Image:** `hashicorp/vault:1.18`
- **Purpose:** Centralized secrets management and PKI
- **Profile:** All (always runs - no profile required)
- **Network:** vault-network (172.20.1.10)
- **Ports:** 8200 (HTTP/HTTPS)
- **AppRole:** N/A (authenticates other services)
- **TLS:** Enabled
- **Health Check:** `http://localhost:8200/v1/sys/health`
- **Dependencies:** None
- **Data Volume:** `vault_data`

### 2. PostgreSQL
- **Image:** `postgres:18`
- **Purpose:** Primary relational database
- **Profile:** minimal, standard, full
- **Network:** data-network (172.20.2.10)
- **Ports:** 5432 (PostgreSQL)
- **AppRole:** ✅ Yes (`/vault-approles/postgres`)
- **TLS:** Dual-mode (ssl=on, accepts both)
- **Init Script:** `configs/postgres/scripts/init-approle.sh`
- **Health Check:** `pg_isready -U devuser -d devdb`
- **Dependencies:** Vault
- **Data Volume:** `postgres_data`
- **Credentials:** Stored in Vault at `secret/postgres`

### 3. PgBouncer
- **Image:** `edoburu/pgbouncer:1.21.0`
- **Purpose:** PostgreSQL connection pooling
- **Profile:** standard, full
- **Network:** data-network (172.20.2.11)
- **Ports:** 6432 (PgBouncer)
- **AppRole:** ✅ Yes (`/vault-approles/pgbouncer`)
- **TLS:** No
- **Init Script:** `configs/pgbouncer/scripts/init.sh`
- **Health Check:** `pg_isready -h localhost -p 6432`
- **Dependencies:** Vault, PostgreSQL
- **Credentials:** Fetches PostgreSQL creds from Vault at `secret/postgres`

### 4. MySQL
- **Image:** `mysql:8.0.40`
- **Purpose:** Secondary relational database
- **Profile:** minimal, standard, full
- **Network:** data-network (172.20.2.20)
- **Ports:** 3306 (MySQL)
- **AppRole:** ✅ Yes (`/vault-approles/mysql`)
- **TLS:** Dual-mode (ssl enabled, accepts both)
- **Init Script:** `configs/mysql/scripts/init-approle.sh`
- **Health Check:** `mysqladmin ping -h localhost`
- **Dependencies:** Vault
- **Data Volume:** `mysql_data`
- **Credentials:** Stored in Vault at `secret/mysql`

### 5. MongoDB
- **Image:** `mongo:7.0`
- **Purpose:** Document-oriented database
- **Profile:** minimal, standard, full
- **Network:** data-network (172.20.2.30)
- **Ports:** 27017 (MongoDB)
- **AppRole:** ✅ Yes (`/vault-approles/mongodb`)
- **TLS:** Dual-mode
- **Init Script:** `configs/mongodb/scripts/init-approle.sh`
- **Health Check:** `mongosh --eval "db.adminCommand('ping')"`
- **Dependencies:** Vault
- **Data Volume:** `mongodb_data`
- **Credentials:** Stored in Vault at `secret/mongodb`

### 6-8. Redis Cluster (redis-1, redis-2, redis-3)
- **Image:** `redis:7.4-alpine`
- **Purpose:** In-memory data structure store, cluster mode
- **Profile:** redis-1 (all), redis-2/3 (standard, full)
- **Network:** data-network (172.20.2.41, .42, .43)
- **Ports:** 6379 (non-TLS), 6380 (TLS), 16379 (cluster bus)
- **AppRole:** ✅ Yes (shared `/vault-approles/redis`)
- **TLS:** Dual-mode (accepts both ports)
- **Init Script:** `configs/redis/scripts/init-approle.sh`
- **Health Check:** `redis-cli ping`
- **Dependencies:** Vault
- **Data Volumes:** `redis_1_data`, `redis_2_data`, `redis_3_data`
- **Credentials:** Stored in Vault at `secret/redis-1`, `secret/redis-2`, `secret/redis-3`
- **Cluster:** Requires `./devstack redis-cluster-init` after startup

### 9. RabbitMQ
- **Image:** `rabbitmq:4.0-management`
- **Purpose:** Message broker / queue
- **Profile:** minimal, standard, full
- **Network:** data-network (172.20.2.50)
- **Ports:** 5672 (AMQP), 5671 (AMQPS), 15672 (Management UI)
- **AppRole:** ✅ Yes (`/vault-approles/rabbitmq`)
- **TLS:** Dual-mode
- **Init Script:** `configs/rabbitmq/scripts/init-approle.sh`
- **Health Check:** `rabbitmq-diagnostics ping`
- **Dependencies:** Vault
- **Data Volume:** `rabbitmq_data`
- **Credentials:** Stored in Vault at `secret/rabbitmq`

---

## Git & Collaboration

### 10. Forgejo
- **Image:** `codeberg.org/forgejo/forgejo:9.0`
- **Purpose:** Self-hosted Git service (Gitea fork)
- **Profile:** minimal, standard, full
- **Network:** app-network (172.20.3.10)
- **Ports:** 3000 (HTTP), 22 (SSH)
- **AppRole:** ✅ Yes (`/vault-approles/forgejo`)
- **TLS:** No
- **Init Script:** `configs/forgejo/scripts/init-approle.sh`
- **Health Check:** `wget --spider http://localhost:3000`
- **Dependencies:** Vault, PostgreSQL
- **Data Volume:** `forgejo_data`
- **Credentials:** Stored in Vault at `secret/forgejo`
- **Database:** Uses PostgreSQL for data storage

---

## Reference Applications

### 11. Reference API (Python FastAPI - Code-First)
- **Image:** Custom build from `reference-apps/fastapi/`
- **Purpose:** Python FastAPI reference implementation (code-first pattern)
- **Profile:** reference
- **Network:** app-network (172.20.3.20)
- **Ports:** 8000 (HTTP), 8443 (HTTPS)
- **AppRole:** ✅ Yes (built into application code)
- **TLS:** No
- **Environment:** `VAULT_APPROLE_DIR=/vault-approles/reference-api`
- **Health Check:** `curl http://localhost:8000/health`
- **Dependencies:** Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- **Features:** Full CRUD, caching, circuit breaker, rate limiting
- **Tests:** 254 pytest tests (84.39% coverage)

### 12. API-First (Python FastAPI - API-First)
- **Image:** Custom build from `reference-apps/fastapi/`
- **Purpose:** Python FastAPI reference implementation (API-first pattern)
- **Profile:** reference
- **Network:** app-network (172.20.3.21)
- **Ports:** 8001 (HTTP), 8444 (HTTPS)
- **AppRole:** ✅ Yes (built into application code)
- **TLS:** No
- **Environment:** `VAULT_APPROLE_DIR=/vault-approles/api-first`
- **Health Check:** `curl http://localhost:8001/health`
- **Dependencies:** Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- **Features:** OpenAPI spec-driven development, same features as reference-api
- **Tests:** Shares tests with reference-api, 26 parity tests

### 13. Golang API (Go Gin)
- **Image:** Custom build from `reference-apps/golang/`
- **Purpose:** Go reference implementation using Gin framework
- **Profile:** reference
- **Network:** app-network (172.20.3.22)
- **Ports:** 8002 (HTTP), 8445 (HTTPS)
- **AppRole:** ✅ Yes (built into application code)
- **TLS:** No
- **Environment:** `VAULT_APPROLE_DIR=/vault-approles/golang-api`
- **Health Check:** `curl http://localhost:8002/health`
- **Dependencies:** Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- **Features:** Health checks, Vault integration, database connectivity
- **Tests:** 35+ Go tests (62.5%-100% coverage)

### 14. Node.js API (Express)
- **Image:** Custom build from `reference-apps/nodejs/`
- **Purpose:** Node.js reference implementation using Express
- **Profile:** reference
- **Network:** app-network (172.20.3.23)
- **Ports:** 8003 (HTTP), 8446 (HTTPS)
- **AppRole:** ✅ Yes (built into application code)
- **TLS:** No
- **Environment:** `VAULT_APPROLE_DIR=/vault-approles/nodejs-api`
- **Health Check:** `curl http://localhost:8003/health`
- **Dependencies:** Vault, PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- **Features:** Health checks, Vault integration, database connectivity

### 15. Rust API (Actix-web)
- **Image:** Custom build from `reference-apps/rust/`
- **Purpose:** Rust reference implementation using Actix-web
- **Profile:** reference
- **Network:** app-network (172.20.3.24)
- **Ports:** 8004 (HTTP), 8447 (HTTPS)
- **AppRole:** ✅ Yes (built into application code, ~40% complete)
- **TLS:** No
- **Environment:** `VAULT_APPROLE_DIR=/vault-approles/rust-api`
- **Health Check:** `curl http://localhost:8004/health`
- **Dependencies:** Vault (partial), PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
- **Status:** Vault integration ~40% complete
- **Tests:** 5 Rust unit tests

---

## Observability Stack

### 16. Prometheus
- **Image:** `prom/prometheus:latest`
- **Purpose:** Metrics collection and storage
- **Profile:** full
- **Network:** observability-network (172.20.4.10)
- **Ports:** 9090 (HTTP UI/API)
- **AppRole:** No
- **TLS:** No
- **Health Check:** `curl http://localhost:9090/-/healthy`
- **Dependencies:** None
- **Data Volume:** `prometheus_data`
- **Config:** `configs/prometheus/prometheus.yml`
- **Scrape Targets:** All services with /metrics endpoints

### 17. Grafana
- **Image:** `grafana/grafana:latest`
- **Purpose:** Metrics visualization and dashboards
- **Profile:** full
- **Network:** observability-network (172.20.4.20)
- **Ports:** 3001 (HTTP UI)
- **AppRole:** No
- **TLS:** No
- **Health Check:** `curl http://localhost:3001/api/health`
- **Dependencies:** Prometheus
- **Data Volume:** `grafana_data`
- **Default Credentials:** admin/admin
- **Dashboards:** Pre-configured for DevStack services

### 18. Loki
- **Image:** `grafana/loki:latest`
- **Purpose:** Log aggregation and storage
- **Profile:** full
- **Network:** observability-network (172.20.4.30)
- **Ports:** 3100 (HTTP API)
- **AppRole:** No
- **TLS:** No
- **Health Check:** `curl http://localhost:3100/ready`
- **Dependencies:** None
- **Data Volume:** `loki_data`
- **Config:** `configs/loki/loki-config.yaml`

### 19. Vector
- **Image:** `timberio/vector:latest`
- **Purpose:** Log routing, transformation, and shipping
- **Profile:** full
- **Network:** observability-network (172.20.4.40), data-network
- **Ports:** 8686 (API)
- **AppRole:** ✅ Yes (`/vault-approles/vector`)
- **TLS:** No
- **Init Script:** `configs/vector/init.sh`
- **Health Check:** `curl http://localhost:8686/health`
- **Dependencies:** Vault, all data services (for log collection)
- **Config:** `configs/vector/vector.toml`
- **Credentials:** Fetches from Vault at `secret/postgres`, `secret/mongodb`, `secret/redis-*`

### 20. cAdvisor
- **Image:** `gcr.io/cadvisor/cadvisor:latest`
- **Purpose:** Container resource usage metrics
- **Profile:** full
- **Network:** observability-network (172.20.4.50)
- **Ports:** 8080 (HTTP UI/Metrics)
- **AppRole:** No
- **TLS:** No
- **Health Check:** `curl http://localhost:8080/healthz`
- **Dependencies:** None
- **Volumes:** Mounts Docker socket and system directories

### 21-23. Redis Exporters (redis-exporter-1/2/3)
- **Image:** `oliver006/redis_exporter:latest`
- **Purpose:** Export Redis metrics to Prometheus
- **Profile:** full
- **Network:** observability-network (172.20.4.61, .62, .63), data-network
- **Ports:** 9121, 9122, 9123 (Prometheus metrics)
- **AppRole:** ✅ Yes (shared `/vault-approles/redis-exporter`)
- **TLS:** No
- **Init Script:** `configs/exporters/redis/init.sh`
- **Health Check:** `curl http://localhost:9121/health` (etc.)
- **Dependencies:** Vault, Redis cluster nodes
- **Credentials:** Fetches from Vault at `secret/redis-1/2/3`
- **Environment:** `REDIS_NODE=redis-1/2/3`

---

## Service Profiles

### Profile: minimal (5 services, 2GB RAM)
**Use Case:** Basic development, Git workflows, single Redis node

**Services:**
1. vault
2. postgres
3. mysql
4. mongodb
5. redis-1
6. rabbitmq
7. forgejo

**Command:** `./devstack start --profile minimal`

### Profile: standard (12 services, 4GB RAM)
**Use Case:** Full development stack with Redis cluster

**Services:** All minimal services +
8. redis-2
9. redis-3
10. pgbouncer

**Additional:** Requires `./devstack redis-cluster-init` for cluster setup

**Command:** `./devstack start --profile standard`

### Profile: full (18 services, 6GB RAM)
**Use Case:** Complete infrastructure with observability

**Services:** All standard services +
11. prometheus
12. grafana
13. loki
14. vector
15. cadvisor
16. redis-exporter-1
17. redis-exporter-2
18. redis-exporter-3

**Command:** `./devstack start --profile full`

### Profile: reference (5 services, +1GB RAM)
**Use Case:** API development examples (combinable with other profiles)

**Services:**
1. reference-api
2. api-first
3. golang-api
4. nodejs-api
5. rust-api

**Command:** `./devstack start --profile standard --profile reference`

---

## Network Assignments

### 4-Tier Network Segmentation

#### 1. vault-network (172.20.1.0/24)
**Purpose:** Vault and AppRole authentication
- vault: 172.20.1.10

#### 2. data-network (172.20.2.0/24)
**Purpose:** Core data services
- postgres: 172.20.2.10
- pgbouncer: 172.20.2.11
- mysql: 172.20.2.20
- mongodb: 172.20.2.30
- redis-1: 172.20.2.41
- redis-2: 172.20.2.42
- redis-3: 172.20.2.43
- rabbitmq: 172.20.2.50

#### 3. app-network (172.20.3.0/24)
**Purpose:** Application services
- forgejo: 172.20.3.10
- reference-api: 172.20.3.20
- api-first: 172.20.3.21
- golang-api: 172.20.3.22
- nodejs-api: 172.20.3.23
- rust-api: 172.20.3.24

#### 4. observability-network (172.20.4.0/24)
**Purpose:** Monitoring and observability
- prometheus: 172.20.4.10
- grafana: 172.20.4.20
- loki: 172.20.4.30
- vector: 172.20.4.40
- cadvisor: 172.20.4.50
- redis-exporter-1: 172.20.4.61
- redis-exporter-2: 172.20.4.62
- redis-exporter-3: 172.20.4.63

**Note:** Some services are connected to multiple networks for cross-tier communication.

---

## Port Mappings

### Host Port Assignments

| Service | Host Port(s) | Container Port | Protocol | Purpose |
|---------|-------------|----------------|----------|---------|
| vault | 8200 | 8200 | HTTP/HTTPS | Vault API |
| postgres | 5432 | 5432 | PostgreSQL | Database |
| pgbouncer | 6432 | 6432 | PostgreSQL | Connection pooler |
| mysql | 3306 | 3306 | MySQL | Database |
| mongodb | 27017 | 27017 | MongoDB | Database |
| redis-1 | 6379, 6380 | 6379, 6380 | Redis | Cache (non-TLS, TLS) |
| redis-2 | 6379, 6380 | 6379, 6380 | Redis | Cache (non-TLS, TLS) |
| redis-3 | 6379, 6380 | 6379, 6380 | Redis | Cache (non-TLS, TLS) |
| rabbitmq | 5672, 5671, 15672 | 5672, 5671, 15672 | AMQP/HTTP | Messaging, Management |
| forgejo | 3000, 2222 | 3000, 22 | HTTP, SSH | Git UI, Git SSH |
| reference-api | 8000, 8443 | 8000, 8443 | HTTP, HTTPS | FastAPI code-first |
| api-first | 8001, 8444 | 8001, 8444 | HTTP, HTTPS | FastAPI API-first |
| golang-api | 8002, 8445 | 8002, 8445 | HTTP, HTTPS | Go Gin API |
| nodejs-api | 8003, 8446 | 8003, 8446 | HTTP, HTTPS | Node.js Express API |
| rust-api | 8004, 8447 | 8004, 8447 | HTTP, HTTPS | Rust Actix-web API |
| prometheus | 9090 | 9090 | HTTP | Prometheus UI/API |
| grafana | 3001 | 3000 | HTTP | Grafana UI |
| loki | 3100 | 3100 | HTTP | Loki API |
| vector | 8686 | 8686 | HTTP | Vector API |
| cadvisor | 8080 | 8080 | HTTP | cAdvisor metrics |
| redis-exporter-1 | 9121 | 9121 | HTTP | Redis metrics |
| redis-exporter-2 | 9122 | 9121 | HTTP | Redis metrics |
| redis-exporter-3 | 9123 | 9121 | HTTP | Redis metrics |

**Note:** Ports 6379-6380 (Redis) and 5672 (RabbitMQ) are not exposed to host by default for security.

---

## AppRole Adoption Status

**Total Services with AppRole:** 16/23 (69.6%)

**Services with AppRole ✅:**
1. postgres
2. pgbouncer
3. mysql
4. mongodb
5. redis (all 3 nodes share same AppRole)
6. rabbitmq
7. forgejo
8. reference-api
9. api-first
10. golang-api
11. nodejs-api
12. rust-api
13. vector
14. redis-exporter (all 3 instances share same AppRole)
15. management scripts

**Services without AppRole:**
- prometheus (no Vault integration needed)
- grafana (no Vault integration needed)
- loki (no Vault integration needed)
- cadvisor (no Vault integration needed)
- vault (authenticates others, doesn't use AppRole itself)

---

## References

**Related Documentation:**
- [Architecture Overview](./ARCHITECTURE.md) - System design and components
- [Service Profiles](./SERVICE_PROFILES.md) - Detailed profile documentation
- [Services Guide](./SERVICES.md) - Service configuration and usage
- [Network Segmentation](./NETWORK_SEGMENTATION.md) - Network architecture
- [Vault Integration](./VAULT.md) - AppRole configuration and usage

**Verification:**
```bash
# Count services
grep '^  [a-z]' docker-compose.yml | grep -v 'network$' | grep -v '_data$' | wc -l

# List all services
docker compose ps --all

# Check service profiles
grep 'profiles:' docker-compose.yml
```

---

**Document Version:** 1.0
**Last Updated:** November 19, 2025
**Maintainer:** DevStack Core Team
