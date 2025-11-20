# Port Reference

## Table of Contents

- [Overview](#overview)
- [Complete Port Listing](#complete-port-listing)
- [Core Services](#core-services)
- [Database Services](#database-services)
- [Cache and Messaging](#cache-and-messaging)
- [Observability Stack](#observability-stack)
- [Application Services](#application-services)
- [Management UIs](#management-uis)
- [Internal Ports](#internal-ports)
- [Port Conflict Resolution](#port-conflict-resolution)
- [Related Pages](#related-pages)

## Overview

This page provides a complete reference of all ports used in the devstack-core environment, including HTTP, HTTPS, database, and internal cluster communication ports.

## Complete Port Listing

| Service | HTTP Port | HTTPS Port | Internal Port | Cluster Port | Purpose |
|---------|-----------|------------|---------------|--------------|---------|
| **Vault** | 8200 | - | - | - | Secrets management |
| **PostgreSQL** | 5432 | 5432* | - | - | Database (dual-mode TLS) |
| **MySQL** | 3306 | 3306* | - | - | Database (dual-mode TLS) |
| **MongoDB** | 27017 | 27017* | - | - | Database (dual-mode TLS) |
| **Redis-1** | 6379 | 6380 | - | 16379 | Cache/Store + cluster bus |
| **Redis-2** | 6379 | 6380 | - | 16379 | Cache/Store + cluster bus |
| **Redis-3** | 6379 | 6380 | - | 16379 | Cache/Store + cluster bus |
| **RabbitMQ** | 5672 | 5671 | - | - | Message broker (AMQP) |
| **RabbitMQ Mgmt** | 15672 | 15671 | - | - | Management UI |
| **Forgejo HTTP** | 3000 | - | - | - | Git hosting |
| **Forgejo SSH** | 2222 | - | - | - | Git SSH |
| **FastAPI (code-first)** | 8000 | 8443 | - | - | Reference API |
| **FastAPI (API-first)** | 8001 | 8444 | - | - | Reference API |
| **Go API** | 8002 | 8445 | - | - | Reference API |
| **Node.js API** | 8003 | 8446 | - | - | Reference API |
| **Rust API** | 8004 | 8447 | - | - | Reference API |
| **Prometheus** | 9090 | - | - | - | Metrics collection |
| **Grafana** | 3001 | - | - | - | Visualization |
| **Loki** | 3100 | - | - | - | Log aggregation |
| **cAdvisor** | 8080 | - | - | - | Container metrics |

*Dual-mode: Same port accepts both TLS and non-TLS connections

## Core Services

**Vault**
- Port: `8200`
- Protocol: HTTP (dev mode, no TLS)
- Access: `http://localhost:8200`
- UI: `http://localhost:8200/ui`
- API: `http://localhost:8200/v1/`

## Database Services

**PostgreSQL**
- Port: `5432`
- Protocol: PostgreSQL wire protocol (dual-mode TLS)
- Connection string: `postgresql://devuser:password@localhost:5432/devdb`
- With TLS: `postgresql://devuser:password@localhost:5432/devdb?sslmode=require`
- Static IP: `172.20.0.10`

**MySQL**
- Port: `3306`
- Protocol: MySQL wire protocol (dual-mode TLS)
- Connection string: `mysql://devuser:password@localhost:3306/devdb`
- With TLS: `mysql://devuser:password@localhost:3306/devdb?ssl-mode=REQUIRED`
- Static IP: `172.20.0.12`

**MongoDB**
- Port: `27017`
- Protocol: MongoDB wire protocol (dual-mode TLS)
- Connection string: `mongodb://devuser:password@localhost:27017/devdb`
- With TLS: `mongodb://devuser:password@localhost:27017/devdb?tls=true`
- Static IP: `172.20.0.15`

## Cache and Messaging

**Redis Cluster (3 nodes)**

Node 1 (172.20.0.13):
- Port: `6379` (non-TLS)
- TLS Port: `6380`
- Cluster Bus: `16379` (internal)
- Connection: `redis-cli -h localhost -p 6379 -c`

Node 2 (172.20.0.16):
- Port: `6379` (non-TLS)
- TLS Port: `6380`
- Cluster Bus: `16379` (internal)

Node 3 (172.20.0.17):
- Port: `6379` (non-TLS)
- TLS Port: `6380`
- Cluster Bus: `16379` (internal)

**RabbitMQ**
- AMQP Port: `5672` (non-TLS)
- AMQPS Port: `5671` (TLS)
- Management UI: `15672` (HTTP)
- Management UI: `15671` (HTTPS)
- Prometheus Metrics: `15692`
- Access UI: `http://localhost:15672`
- Static IP: `172.20.0.14`

## Observability Stack

**Prometheus**
- Port: `9090`
- Protocol: HTTP
- Access: `http://localhost:9090`
- Query UI: `http://localhost:9090/graph`
- API: `http://localhost:9090/api/v1/`
- Static IP: `172.20.0.101`

**Grafana**
- Port: `3001`
- Protocol: HTTP
- Access: `http://localhost:3001`
- Default credentials: `admin:admin`
- Static IP: `172.20.0.102`

**Loki**
- Port: `3100`
- Protocol: HTTP
- API: `http://localhost:3100`
- Health: `http://localhost:3100/ready`
- Static IP: `172.20.0.103`

**cAdvisor**
- Port: `8080`
- Protocol: HTTP
- Access: `http://localhost:8080`
- Metrics: `http://localhost:8080/metrics`

## Application Services

**FastAPI Reference (code-first)**
- HTTP Port: `8000`
- HTTPS Port: `8443`
- Health: `http://localhost:8000/health`
- Docs: `http://localhost:8000/docs`
- OpenAPI: `http://localhost:8000/openapi.json`
- Metrics: `http://localhost:8000/metrics`
- Static IP: `172.20.0.100`

**FastAPI Reference (API-first)**
- HTTP Port: `8001`
- HTTPS Port: `8444`
- Health: `http://localhost:8001/health`
- Docs: `http://localhost:8001/docs`
- Static IP: `172.20.0.107`

**Go API**
- HTTP Port: `8002`
- HTTPS Port: `8445`
- Health: `http://localhost:8002/health`
- Static IP: `172.20.0.104`

**Node.js API**
- HTTP Port: `8003`
- HTTPS Port: `8446`
- Health: `http://localhost:8003/health`
- Static IP: `172.20.0.105`

**Rust API**
- HTTP Port: `8004`
- HTTPS Port: `8447`
- Health: `http://localhost:8004/health`
- Static IP: `172.20.0.106`

## Management UIs

**Forgejo (Git Hosting)**
- HTTP Port: `3000`
- SSH Port: `2222`
- Access: `http://localhost:3000`
- Git clone: `http://localhost:3000/username/repo.git`
- SSH clone: `ssh://git@localhost:2222/username/repo.git`
- Static IP: `172.20.0.20`

**RabbitMQ Management**
- HTTP Port: `15672`
- HTTPS Port: `15671`
- Access: `http://localhost:15672`
- Default credentials: `devuser:password`

**Vault UI**
- Port: `8200`
- Access: `http://localhost:8200/ui`
- Login with root token

## Internal Ports

**Redis Cluster Bus**
- Port: `16379` (all nodes)
- Protocol: Redis cluster protocol
- Used for: Node-to-node communication, gossip, failover
- Not exposed to host

**Docker Internal DNS**
- Port: `53` (UDP)
- Service: Docker embedded DNS server
- Address: `127.0.0.11` (from inside containers)

**PostgreSQL Replication** (if configured)
- Port: `5432` (same as main port)
- Used for streaming replication

## Port Conflict Resolution

### Check Port Usage

```bash
# Check if port is in use
lsof -i :8200
lsof -i :5432
lsof -i :6379

# List all listening ports
lsof -i -P | grep LISTEN

# netstat alternative
netstat -an | grep LISTEN
```

### Common Conflicts

**Port 5432 (PostgreSQL)**
```bash
# Conflict with system PostgreSQL
lsof -i :5432
# Kill: brew services stop postgresql

# Use different port
# In .env:
POSTGRES_PORT=5433
```

**Port 3306 (MySQL)**
```bash
# Conflict with system MySQL
brew services stop mysql

# Or change port
MYSQL_PORT=3307
```

**Port 6379 (Redis)**
```bash
# Conflict with system Redis
brew services stop redis

# Or change ports
REDIS_1_PORT=6380
```

**Port 8000-8004 (Web Apps)**
```bash
# Common conflict with dev servers
# Change in .env:
REFERENCE_API_PORT=8100
```

### Change Ports

**Edit `.env` file:**
```bash
nano .env

# Change service ports
POSTGRES_PORT=5433
MYSQL_PORT=3307
REDIS_1_PORT=6380
REFERENCE_API_PORT=8100
```

**Restart services:**
```bash
docker compose down
docker compose up -d
```

### Port Ranges Used

- **1-1023**: System/privileged ports (not used)
- **2222**: Forgejo SSH
- **3000-3100**: Web UIs (Forgejo, Grafana, Loki)
- **5432**: PostgreSQL
- **5671-5672**: RabbitMQ AMQP
- **6379-6380**: Redis
- **8000-8004**: Reference applications
- **8080**: cAdvisor
- **8200**: Vault
- **8443-8447**: Reference apps HTTPS
- **9090**: Prometheus
- **15671-15672**: RabbitMQ Management
- **16379**: Redis cluster bus
- **27017**: MongoDB

## Quick Reference Commands

```bash
# List all container ports
docker ps --format "table {{.Names}}\t{{.Ports}}"

# Check specific service
docker port dev-postgres
docker port dev-vault

# Test connection
curl http://localhost:8200/v1/sys/health
pg_isready -h localhost -p 5432
redis-cli -h localhost -p 6379 PING

# Kill process on port
lsof -t -i :8200 | xargs kill -9
```

## Related Pages

- [Network-Issues](Network-Issues) - Port troubleshooting
- [Service-Configuration](Service-Configuration) - Port configuration
- [Environment-Variables](Environment-Variables) - Port variables
