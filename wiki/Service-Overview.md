# Services


## Table of Contents

  - [Infrastructure Services](#infrastructure-services)
  - [Observability Stack](#observability-stack)
  - [Reference Applications](#reference-applications)
- [Service Configuration](#service-configuration)
  - [PostgreSQL](#postgresql)
  - [PgBouncer](#pgbouncer)
  - [MySQL](#mysql)
  - [Redis Cluster](#redis-cluster)
  - [RabbitMQ](#rabbitmq)
  - [MongoDB](#mongodb)
  - [Forgejo (Git Server)](#forgejo-git-server)
  - [HashiCorp Vault](#hashicorp-vault)

---

### Infrastructure Services

| Service | Version | Port(s) | Purpose | Health Check |
|---------|---------|---------|---------|--------------|
| **PostgreSQL** | 16-alpine | 5432 | Git storage + dev database | pg_isready |
| **PgBouncer** | latest | 6432 | Connection pooling | psql test |
| **MySQL** | 8.0 | 3306 | Legacy database support | mysqladmin ping |
| **Redis Cluster** | 7-alpine | 6379 (non-TLS), 6390 (TLS), 16379 (cluster bus) | Distributed cache (3 nodes) | redis-cli ping |
| **RabbitMQ** | 3-management-alpine | 5672, 15672 | Message queue + UI | rabbitmq-diagnostics |
| **MongoDB** | 7 | 27017 | NoSQL database | mongosh ping |
| **Forgejo** | 1.21 | 3000, 2222 | Self-hosted Git server | curl /api/healthz |
| **Vault** | latest | 8200 | Secrets management | wget /sys/health |

### Observability Stack

| Service | Version | Port(s) | Purpose | Health Check |
|---------|---------|---------|---------|--------------|
| **Prometheus** | 2.48.0 | 9090 | Metrics collection & time-series DB | wget /metrics |
| **Grafana** | 10.2.2 | 3001 | Visualization & dashboards | curl /-/health |
| **Loki** | 2.9.3 | 3100 | Log aggregation system | wget /ready |

### Reference Applications

| Service | Version | Port(s) | Purpose | Health Check |
|---------|---------|---------|---------|--------------|
| **FastAPI (Code-First)** | Python 3.11 | 8000 (HTTP), 8443 (HTTPS) | Comprehensive code-first API | curl /health |
| **FastAPI (API-First)** | Python 3.11 | 8001 (HTTP), 8444 (HTTPS) | OpenAPI-driven implementation | curl /health |
| **Go Reference API** | Go 1.23+ | 8002 (HTTP), 8445 (HTTPS) | Production-ready Go implementation | curl /health |
| **Node.js Reference API** | Node.js 18+ | 8003 (HTTP), 8446 (HTTPS) | Modern async/await patterns | curl /health |
| **Rust Reference API** | Rust 1.70+ | 8004 (HTTP), 8447 (HTTPS) | High-performance async API | curl /health |

**Implementation Patterns:**
- **FastAPI Code-First** (port 8000): Implementation drives documentation - typical rapid development approach
- **FastAPI API-First** (port 8001): OpenAPI specification drives implementation - contract-first approach
- **Go/Gin** (port 8002): Compiled binary with goroutines for concurrency
- **Node.js/Express** (port 8003): Event-driven with async/await patterns
- **Rust/Actix-web** (port 8004): Memory-safe, zero-cost abstractions, comprehensive testing (~40% complete)
- **Shared Test Suite**: Automated tests ensuring consistent behavior across all implementations
- **Performance Benchmarks**: Compare throughput, latency, and resource usage

All 5 implementations demonstrate identical core functionality with language-specific patterns. See `reference-apps/README.md` for architecture details and `tests/performance-benchmark.sh` for performance comparisons.

**Resource Allocation:**
- Total memory: ~4-5GB (with all services running)
- Colima VM: 8GB allocated (4 CPU cores)
- Each service has memory limits and health checks

## Service Configuration

### PostgreSQL

**Purpose:** Primary database for Forgejo (Git server) and local development.

**Configuration:**
- Image: `postgres:18` (Debian-based, ARM64 native)
- **Credentials:** Auto-fetched from Vault at startup via `configs/postgres/scripts/init.sh`
  - Stored in Vault at `secret/postgres`
  - Fields: `user`, `password`, `database`
  - Password retrieved using `scripts/read-vault-secret.py`
- **Authentication Mode:** MD5 (for PgBouncer compatibility, not SCRAM-SHA-256)
- Storage: File-based in `/var/lib/postgresql/data`
- Encoding: UTF8, Locale: C
- Max connections: 100 (reduced for dev/Git only)
- Shared buffers: 256MB
- Effective cache: 1GB
- **Optional TLS:** Configurable via `POSTGRES_ENABLE_TLS=true`
- **PostgreSQL 18 Compatibility Layer:** Includes `configs/postgres/01-pg18-compatibility.sql`
  - Creates `compat.pg_stat_bgwriter` view for backward compatibility with monitoring tools
  - Maps new PostgreSQL 18 statistics columns to pre-PG17 column names
  - Enables Vector metrics collection without modifications

**Key Settings** (`docker-compose.yml:68-78`):
```yaml
command:
  - "postgres"
  - "-c"
  - "max_connections=100"
  - "-c"
  - "shared_buffers=256MB"
  - "-c"
  - "effective_cache_size=1GB"
  - "-c"
  - "work_mem=8MB"
```

**Connection:**
```bash
# From Mac
psql -h localhost -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB

# From inside container
docker exec -it dev-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB

# Using management script
./devstack.sh shell postgres
# Then: psql -U $POSTGRES_USER -d $POSTGRES_DB
```

**Init Scripts:**
- Place `.sql` files in `configs/postgres/` to run on first start
- Executed in alphabetical order
- Useful for creating additional databases or users

**Health Check:**
```bash
# Automatic (runs every 60 seconds)
pg_isready -U $POSTGRES_USER

# Manual check
docker exec dev-postgres pg_isready -U $POSTGRES_USER
```

**Performance Tuning:**
- Tuned for Git server workload (many small transactions)
- Increased for dev workloads: adjust `max_connections`, `shared_buffers`
- Monitor: `./devstack.sh status` shows CPU/memory usage

### PgBouncer

**Purpose:** Connection pooling for PostgreSQL to reduce connection overhead.

**Configuration:**
- Pool mode: `transaction` (best for web applications)
- Max client connections: 100
- Default pool size: 10
- Reduces PostgreSQL connection overhead
- **Authentication:** Uses MD5 (PostgreSQL configured for MD5, not SCRAM-SHA-256)
- **Credentials:** Loaded from Vault via environment variables (`scripts/load-vault-env.sh`)

**When to Use:**
- High-frequency connections (web apps, APIs)
- Connection-per-request patterns
- Microservices connecting to shared database

**Connection:**
```bash
psql -h localhost -p 6432 -U $POSTGRES_USER -d $POSTGRES_DB
```

**Direct PostgreSQL vs PgBouncer:**
- Direct (5432): For long-lived connections, admin tasks
- PgBouncer (6432): For application connections, APIs

### MySQL

**Purpose:** Legacy database support during migration period.

**Configuration:**
- Image: `mysql:8.0`
- **Credentials:** Auto-fetched from Vault at startup via `configs/mysql/scripts/init.sh`
  - Stored in Vault at `secret/mysql`
  - Fields: `root_password`, `user`, `password`, `database`
- Character set: utf8mb4
- Collation: utf8mb4_unicode_ci
- Max connections: 100
- InnoDB buffer pool: 256MB
- **Optional TLS:** Configurable via `MYSQL_ENABLE_TLS=true`

**Connection:**
```bash
mysql -h 127.0.0.1 -u $MYSQL_USER -p$MYSQL_PASSWORD $MYSQL_DATABASE

# Or interactively
mysql -h 127.0.0.1 -u $MYSQL_USER -p
# Enter password when prompted
```

**Init Scripts:**
- Place `.sql` files in `configs/mysql/`
- Executed on first container start

### Redis Cluster

**Purpose:** Distributed caching with high availability and horizontal scaling.

**Architecture:**
- 3 master nodes (no replicas in dev mode)
- **Credentials:** All nodes share same password from Vault at `secret/redis-1`
  - Auto-fetched at startup via `configs/redis/scripts/init.sh`
  - Field: `password`
- 16,384 hash slots distributed across nodes
  - Node 1 (172.20.2.13): slots 0-5460
  - Node 2 (172.20.2.16): slots 5461-10922
  - Node 3 (172.20.2.17): slots 10923-16383
- Total memory: 768MB (256MB per node)
- Automatic slot allocation and data sharding
- **Optional TLS:** Configurable via `REDIS_ENABLE_TLS=true`

**Configuration Files:**
- `configs/redis/redis-cluster.conf` - Cluster-specific settings
- `configs/redis/redis.conf` - Standalone Redis config (reference)

**Key Settings:**
```conf
# Cluster mode enabled
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000
cluster-require-full-coverage no  # Dev mode: operate with partial coverage

# Persistence
appendonly yes  # AOF enabled for cluster reliability
save 900 1      # RDB snapshots

# Memory
maxmemory 256mb
maxmemory-policy allkeys-lru
```

**Ports:**
- **6379 (non-TLS):** Standard Redis port on all nodes
- **6390 (TLS):** TLS-encrypted port on all nodes (when TLS enabled)
- **16379:** Cluster bus port (internal communication)

**Connection:**
```bash
# Non-TLS connection (ALWAYS use -c flag for cluster mode!)
redis-cli -c -a $REDIS_PASSWORD -p 6379

# TLS-encrypted connection (requires certificates)
redis-cli -c -a $REDIS_PASSWORD -p 6390 \
  --tls --cert ~/.config/vault/certs/redis-1/redis.crt \
  --key ~/.config/vault/certs/redis-1/redis.key \
  --cacert ~/.config/vault/certs/redis-1/ca.crt
```

**First-Time Cluster Initialization:**
```bash
# After starting containers for the first time
./configs/redis/scripts/redis-cluster-init.sh

# Or manually
docker exec dev-redis-1 redis-cli --cluster create \
  172.20.2.13:6379 172.20.2.16:6379 172.20.2.17:6379 \
  --cluster-yes -a $REDIS_PASSWORD
```

**Cluster Operations:**
```bash
# Check cluster status
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster info

# List all nodes
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster nodes

# Check slot distribution
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster slots

# Find which node owns a key
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster keyslot <key-name>

# Comprehensive cluster check
docker exec dev-redis-1 redis-cli --cluster check 172.20.2.13:6379 -a $REDIS_PASSWORD
```

**FastAPI Cluster Inspection APIs:**

The reference application provides REST APIs for cluster inspection (see [Reference Applications](#reference-applications)):

```bash
# Get cluster nodes and slot assignments
curl http://localhost:8000/redis/cluster/nodes

# Get slot distribution with coverage percentage
curl http://localhost:8000/redis/cluster/slots

# Get cluster state and statistics
curl http://localhost:8000/redis/cluster/info

# Get detailed info for specific node
curl http://localhost:8000/redis/nodes/redis-1/info
```

**Data Distribution:**
- Keys are automatically sharded based on CRC16 hash
- Client redirects handled automatically with `-c` flag
- Example: `SET user:1000 "data"` → hashed → assigned to appropriate node

**Why Cluster vs Single Node?**
- **High Availability:** If one node fails, others continue serving
- **Horizontal Scaling:** Distribute data across nodes
- **Performance:** Parallel read/write operations
- **Production Parity:** Dev environment matches production architecture

### RabbitMQ

**Purpose:** Message queue for asynchronous communication between services.

**Configuration:**
- Image: `rabbitmq:3-management-alpine`
- **Credentials:** Auto-fetched from Vault at startup via `configs/rabbitmq/scripts/init.sh`
  - Stored in Vault at `secret/rabbitmq`
  - Fields: `user`, `password`, `vhost`
- Protocols: AMQP (5672), Management HTTP (15672)
- Virtual host: `dev_vhost`
- Plugins: Management UI enabled
- **Optional TLS:** Configurable via `RABBITMQ_ENABLE_TLS=true`

**Access:**
- **AMQP:** `amqp://dev_admin:password@localhost:5672/dev_vhost`
- **Management UI:** http://localhost:15672
  - Username: `$RABBITMQ_USER` (from .env)
  - Password: `$RABBITMQ_PASSWORD` (from .env)

**Common Operations:**
```bash
# View logs
./devstack.sh logs rabbitmq

# Shell access
docker exec -it dev-rabbitmq sh

# List queues
docker exec dev-rabbitmq rabbitmqctl list_queues

# List exchanges
docker exec dev-rabbitmq rabbitmqctl list_exchanges

# List connections
docker exec dev-rabbitmq rabbitmqctl list_connections
```

### MongoDB

**Purpose:** NoSQL document database for unstructured data.

**Configuration:**
- Image: `mongo:7`
- **Credentials:** Auto-fetched from Vault at startup via `configs/mongodb/scripts/init.sh`
  - Stored in Vault at `secret/mongodb`
  - Fields: `user`, `password`, `database`
- Authentication: SCRAM-SHA-256
- Storage engine: WiredTiger
- Default database: `dev_database`
- **Optional TLS:** Configurable via `MONGODB_ENABLE_TLS=true`

**Connection:**
```bash
# Using mongosh (MongoDB Shell)
mongosh --host localhost --port 27017 \
  --username $MONGODB_USER \
  --password $MONGODB_PASSWORD \
  --authenticationDatabase admin

# Connection string
mongodb://dev_admin:password@localhost:27017/dev_database?authSource=admin
```

**Init Scripts:**
- Place `.js` files in `configs/mongodb/`
- Executed in alphabetical order on first start

### Forgejo (Git Server)

**Purpose:** Self-hosted Git server (Gitea fork) for private repositories.

**Configuration:**
- Uses PostgreSQL for metadata storage
- Git data stored in Docker volume (`forgejo_data`)
- SSH port mapped to 2222 (to avoid conflict with Mac's SSH on 22)

**First-Time Setup:**
1. Navigate to http://localhost:3000
2. Complete installation wizard:
   - Database type: PostgreSQL
   - Host: `postgres:5432` (internal network)
   - Database: `forgejo`
   - Username/Password: Same as PostgreSQL (auto-configured via env vars)
3. Create admin account
4. Start creating repositories

**Git Operations:**
```bash
# Clone via HTTP
git clone http://localhost:3000/username/repo.git

# Clone via SSH
git clone ssh://git@localhost:2222/username/repo.git

# Configure SSH
# Add to ~/.ssh/config:
Host forgejo
  HostName localhost
  Port 2222
  User git
  IdentityFile ~/.ssh/id_rsa

# Then clone with:
git clone forgejo:username/repo.git
```

**SSH and GPG Keys:**
For setting up SSH keys (for authenticated push/pull) and GPG keys (for signed commits), see the detailed guide in [CONTRIBUTING.md](../Contributing-Guide#setting-up-ssh-and-gpg-keys-for-forgejo).

**Access from Network:**
- Set `FORGEJO_DOMAIN` to Colima IP in `.env`
- Access from libvirt VMs or other machines on network
- Example: http://192.168.106.2:3000

### HashiCorp Vault

**Purpose:** Centralized secrets management and encryption as a service.

**Configuration:**
- Storage backend: File (persistent across restarts)
- Seal type: Shamir (3 of 5 keys required to unseal)
- Auto-unseal: Enabled on container start (see [Vault Auto-Unseal](#vault-auto-unseal))
- UI: Enabled at http://localhost:8200/ui

**Key Features:**
- **Secrets Management:** Store API keys, passwords, certificates
- **Dynamic Secrets:** Generate database credentials on-demand
- **Encryption as a Service:** Encrypt/decrypt data via API
- **Audit Logging:** Track all secret access
- **Policy-Based Access:** Fine-grained permissions

**File Locations:**
```
~/.config/vault/keys.json        # 5 unseal keys
~/.config/vault/root-token       # Root token for admin access
```

**⚠️ CRITICAL:** Backup these files! Cannot be recovered if lost.

**Access Vault:**
```bash
# Set environment
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Check status
vault status

# List secrets
vault kv list secret/

# Store secret
vault kv put secret/myapp/config api_key=123456

# Retrieve secret
vault kv get secret/myapp/config

# Use management script
./devstack.sh vault-status
./devstack.sh vault-token
```

**Vault Workflow:**
1. Container starts → Vault server starts sealed
2. Auto-unseal script waits for Vault to be ready
3. Script reads `~/.config/vault/keys.json`
4. Script POSTs 3 of 5 unseal keys to `/v1/sys/unseal`
5. Vault unseals and becomes operational
6. Script sleeps indefinitely (zero CPU overhead)

See [Vault Auto-Unseal](#vault-auto-unseal) for detailed information.

