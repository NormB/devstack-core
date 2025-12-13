# Glossary

A plain-language explanation of terms and concepts used in DevStack Core.

---

## Core Concepts

### DevStack Core
A local development infrastructure that provides production-like services (databases, caching, secrets management) on your Mac using Docker containers managed by Colima.

### Colima
A lightweight virtual machine (VM) manager for macOS that runs Docker containers. Think of it as a lightweight alternative to Docker Desktop that's optimized for Apple Silicon Macs.

**Why Colima instead of Docker Desktop?**
- Lower memory usage
- Better performance on Apple Silicon
- Open source with no licensing restrictions
- Command-line focused

### Container
A lightweight, isolated environment that runs a single application. Unlike virtual machines, containers share the host operating system kernel, making them faster to start and more efficient.

**Example:** The `dev-postgres` container runs PostgreSQL in isolation from other services.

### Docker Compose
A tool for defining and running multi-container applications. DevStack uses a `docker-compose.yml` file to define all services and their configurations.

### Profile
A named group of services to start together. Profiles let you run only what you need:

| Profile | What it includes |
|---------|------------------|
| minimal | Core services only (Vault, PostgreSQL, single Redis, Forgejo) |
| standard | All databases + Redis cluster + RabbitMQ |
| full | Standard + monitoring stack (Prometheus, Grafana, Loki) |
| reference | Example API applications in 5 languages |

---

## Vault Concepts

### HashiCorp Vault
A secrets management tool that securely stores and controls access to passwords, API keys, certificates, and other sensitive data. DevStack uses Vault instead of putting passwords in configuration files.

**Why use Vault?**
- Passwords are never stored in plain text files
- Credentials can be rotated without changing config files
- Access can be audited and controlled
- Certificates can be automatically generated

### Secrets Engine
A Vault component that stores or generates secrets. DevStack uses:

| Engine | Purpose |
|--------|---------|
| **KV (Key-Value)** | Stores database passwords and credentials |
| **PKI** | Generates TLS certificates |

### Unsealing
When Vault starts, it's in a "sealed" state and cannot read its data. Unsealing is the process of providing keys to decrypt Vault's storage.

**Analogy:** Think of Vault as a bank vault. Even if you have the door key (root token), you first need to unlock multiple safety deposit boxes (unseal keys) before the vault door will open.

```
Sealed Vault ──[Unseal Keys]──▶ Unsealed Vault ──[Token]──▶ Access Secrets
```

### Root Token
The most powerful authentication credential for Vault. Like a master key, it can access everything. DevStack stores this in `~/.config/vault/root-token`.

**Important:** The root token is for administrative tasks. Services use AppRole for day-to-day access.

### AppRole
A Vault authentication method designed for machines and applications. Each service gets its own AppRole identity with limited permissions.

**How it works:**
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Service   │────▶│  role_id +   │────▶│    Vault    │
│ (PostgreSQL)│     │  secret_id   │     │             │
└─────────────┘     └──────────────┘     └─────────────┘
                           │                    │
                           │                    ▼
                           │              ┌─────────────┐
                           └─────────────▶│ Temp Token  │
                                          │ (1hr TTL)   │
                                          └─────────────┘
```

**Why AppRole instead of Root Token?**
- Limited permissions (can only access specific secrets)
- Temporary tokens that expire
- Auditable access
- No long-lived credentials to steal

### PKI (Public Key Infrastructure)
A system for creating and managing digital certificates used for TLS/SSL encryption. DevStack uses a two-tier PKI:

```
┌─────────────────────────────────────────────────────┐
│                   Root CA (10 years)                │
│         Self-signed, stored securely                │
└────────────────────────┬────────────────────────────┘
                         │ signs
                         ▼
┌─────────────────────────────────────────────────────┐
│             Intermediate CA (5 years)               │
│         Used for issuing service certs              │
└────────────────────────┬────────────────────────────┘
                         │ signs
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│  PostgreSQL  │ │    MySQL     │ │    Redis     │
│  Cert (1yr)  │ │  Cert (1yr)  │ │  Cert (1yr)  │
└──────────────┘ └──────────────┘ └──────────────┘
```

---

## Database Concepts

### PostgreSQL
An advanced open-source relational database. Often called "Postgres." Used for structured data with relationships (users, orders, products).

**DevStack access:** `localhost:5432`

### MySQL
A popular open-source relational database. Often used for web applications and content management systems.

**DevStack access:** `localhost:3306`

### MongoDB
A document database that stores data in flexible, JSON-like documents. Good for unstructured or rapidly changing data.

**DevStack access:** `localhost:27017`

### PgBouncer
A connection pooler for PostgreSQL. It maintains a pool of database connections and shares them among clients, reducing the overhead of opening new connections.

**Why use PgBouncer?**
- Faster connection times
- Handles more concurrent connections
- Reduces database server load

**DevStack access:** `localhost:6432` (connects to PostgreSQL on your behalf)

---

## Redis Concepts

### Redis
An in-memory data store used for caching, session storage, and message queuing. Extremely fast because data is stored in RAM.

### Redis Cluster
Multiple Redis nodes working together to provide:
- **Sharding:** Data is automatically split across nodes
- **High availability:** If one node fails, others continue working
- **Scalability:** Add more nodes for more capacity

DevStack runs 3 Redis nodes:
```
┌─────────────────────────────────────────────────────┐
│                   Redis Cluster                     │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐       │
│  │  redis-1  │  │  redis-2  │  │  redis-3  │       │
│  │ :6379     │  │ :6380     │  │ :6381     │       │
│  │ slots     │  │ slots     │  │ slots     │       │
│  │ 0-5460    │  │ 5461-10922│  │10923-16383│       │
│  └───────────┘  └───────────┘  └───────────┘       │
└─────────────────────────────────────────────────────┘
```

### Hash Slots
Redis Cluster divides the keyspace into 16,384 hash slots. Each key belongs to a specific slot, and each node is responsible for a range of slots.

**Example:** When you store a key, Redis calculates which slot it belongs to:
```
key "user:1000" → slot 15495 → stored on redis-3
key "session:abc" → slot 8234 → stored on redis-2
```

---

## Messaging Concepts

### RabbitMQ
A message broker that enables applications to communicate asynchronously. One application sends a message to a queue, and another application processes it later.

**Use cases:**
- Background job processing
- Microservice communication
- Event-driven architectures

**DevStack access:**
- AMQP: `localhost:5672`
- Management UI: `localhost:15672`

### Queue
A buffer that holds messages until they're processed. Messages are typically processed in order (FIFO: First In, First Out).

### Exchange
A RabbitMQ component that receives messages and routes them to queues based on routing rules.

---

## Networking Concepts

### TLS (Transport Layer Security)
Encryption protocol that protects data in transit. Previously known as SSL. When you see "HTTPS" or a padlock in your browser, that's TLS.

DevStack can encrypt connections between services using TLS certificates generated by Vault.

### Dual-Mode TLS
DevStack services accept both encrypted (TLS) and unencrypted connections. This makes development easier while still supporting secure connections.

| Port | Type |
|------|------|
| 5432 | PostgreSQL (TLS optional) |
| 6379 | Redis (no TLS) |
| 6380 | Redis (TLS required) |

### Network Segmentation
DevStack divides services into separate networks for security:

```
┌─────────────────────────────────────────────────────────────────┐
│                        DevStack Networks                        │
├─────────────────────────────────────────────────────────────────┤
│  vault-network (172.20.1.0/24)                                  │
│  └── Vault server only                                          │
├─────────────────────────────────────────────────────────────────┤
│  data-network (172.20.2.0/24)                                   │
│  └── PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ                │
├─────────────────────────────────────────────────────────────────┤
│  app-network (172.20.3.0/24)                                    │
│  └── Forgejo, Reference APIs                                    │
├─────────────────────────────────────────────────────────────────┤
│  observability-network (172.20.4.0/24)                          │
│  └── Prometheus, Grafana, Loki, Vector                          │
└─────────────────────────────────────────────────────────────────┘
```

---

## Monitoring Concepts

### Prometheus
A monitoring system that collects metrics from services. It scrapes (pulls) metrics from HTTP endpoints and stores them in a time-series database.

**DevStack access:** `localhost:9090`

### Grafana
A visualization platform for creating dashboards from metrics data. Connects to Prometheus (and other data sources) to display charts, graphs, and alerts.

**DevStack access:** `localhost:3001`

### Loki
A log aggregation system (like Prometheus, but for logs). Collects logs from all services for centralized searching and analysis.

### Vector
A data pipeline tool that collects, transforms, and routes logs and metrics. In DevStack, Vector collects container logs and sends them to Loki.

### Metrics
Numerical measurements collected over time. Examples:
- CPU usage percentage
- Memory consumption
- Request count
- Response time

### cAdvisor
Container Advisor - a tool that monitors container resource usage and performance. Provides CPU, memory, and network statistics for each container.

---

## Git & Development Concepts

### Forgejo
A self-hosted Git server (like GitHub, but running locally). Fork of Gitea. Use it to store code repositories locally during development.

**DevStack access:** `localhost:3000`

### Reference Apps
Example API implementations in 5 programming languages (Python/FastAPI, Go, Node.js, Rust, TypeScript) that demonstrate how to integrate with DevStack services.

---

## DevStack CLI Commands

| Command | Description |
|---------|-------------|
| `./devstack start` | Start all services |
| `./devstack stop` | Stop all services |
| `./devstack restart` | Restart all services |
| `./devstack status` | Show VM and container status |
| `./devstack health` | Check service health |
| `./devstack logs <service>` | View service logs |
| `./devstack shell <service>` | Open shell in container |
| `./devstack vault-init` | Initialize Vault |
| `./devstack vault-bootstrap` | Configure Vault with credentials |
| `./devstack vault-show-password <service>` | Get service password |
| `./devstack backup` | Backup all databases |
| `./devstack restore` | Restore from backup |
| `./devstack reset` | Remove all containers |

---

## File Locations

| Path | Contents |
|------|----------|
| `~/.config/vault/` | Vault keys, tokens, certificates |
| `~/.config/vault/root-token` | Vault root token |
| `~/.config/vault/keys.json` | Vault unseal keys |
| `~/.config/vault/certs/` | Service TLS certificates |
| `~/devstack-core/.env` | Environment configuration |
| `~/devstack-core/configs/` | Service configuration files |
| `~/devstack-core/backups/` | Database backups |

---

## Common Abbreviations

| Abbreviation | Meaning |
|--------------|---------|
| **API** | Application Programming Interface |
| **CA** | Certificate Authority |
| **CLI** | Command Line Interface |
| **DB** | Database |
| **FQDN** | Fully Qualified Domain Name |
| **KV** | Key-Value (storage) |
| **PKI** | Public Key Infrastructure |
| **TLS** | Transport Layer Security |
| **TTL** | Time To Live |
| **UI** | User Interface |
| **VM** | Virtual Machine |

---

## See Also

- [Getting Started](GETTING_STARTED.md) - Quick start guide
- [Architecture](ARCHITECTURE.md) - System design
- [CLI Reference](CLI_REFERENCE.md) - All commands
- [Learning Paths](LEARNING_PATHS.md) - Guides by goal
