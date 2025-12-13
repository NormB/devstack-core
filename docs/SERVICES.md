# Services

Detailed documentation for all DevStack Core services including infrastructure, observability, and reference applications.

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
| **PostgreSQL** | 18 | 5432 | Git storage + dev database | pg_isready |
| **PgBouncer** | latest | 6432 | Connection pooling | psql test |
| **MySQL** | 8.0.40 | 3306 | Legacy database support | mysqladmin ping |
| **Redis Cluster** | 7.4-alpine | 6379 (non-TLS), 6390 (TLS), 16379 (cluster bus) | Distributed cache (3 nodes) | redis-cli ping |
| **RabbitMQ** | 3.13-management-alpine | 5672, 15672 | Message queue + UI | rabbitmq-diagnostics |
| **MongoDB** | 7.0 | 27017 | NoSQL database | mongosh ping |
| **Forgejo** | 1.21 | 3000, 2222 | Self-hosted Git server | curl /api/healthz |
| **Vault** | 1.18 | 8200 | Secrets management | wget /sys/health |

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

**Purpose:** Connection pooling for PostgreSQL to reduce connection overhead and improve scalability.

**Configuration:**
- Pool mode: `transaction` (best for web applications)
- Max client connections: 100
- Default pool size: 10
- Reduces PostgreSQL connection overhead
- **Authentication:** Uses MD5 (PostgreSQL configured for MD5, not SCRAM-SHA-256)
- **Credentials:** Loaded from Vault via environment variables (`scripts/load-vault-env.sh`)

#### Connection Pool Modes

PgBouncer supports three pooling modes, each with different use cases:

**1. Transaction Pooling (Default)**
```ini
pool_mode = transaction
```
- **How it works:** Connection returned to pool when transaction completes
- **Best for:** Web applications, REST APIs, microservices
- **Pros:** Maximum connection reuse, highest efficiency
- **Cons:** Cannot use session-level features (temp tables, prepared statements, LISTEN/NOTIFY)
- **Use when:** Most common mode for stateless applications

**2. Session Pooling**
```ini
pool_mode = session
```
- **How it works:** Connection returned to pool when client disconnects
- **Best for:** Interactive applications, long-running sessions
- **Pros:** Full PostgreSQL feature support, no restrictions
- **Cons:** Lower connection reuse, less efficient
- **Use when:** Need session-level features (temp tables, advisory locks)

**3. Statement Pooling**
```ini
pool_mode = statement
```
- **How it works:** Connection returned after each SQL statement
- **Best for:** Simple read-only queries
- **Pros:** Highest connection reuse
- **Cons:** Multi-statement transactions not supported
- **Use when:** Simple query-only workloads (rare)

#### When to Use PgBouncer

**Ideal Scenarios:**

1. **High Connection Churn**
   - Web applications with many short-lived connections
   - Connection-per-request patterns
   - Serverless functions connecting to database

2. **Connection Limit Constraints**
   - PostgreSQL `max_connections=100` but need 500 clients
   - PgBouncer pools 500 clients → 10 actual PostgreSQL connections

3. **Microservices Architecture**
   - Multiple services sharing single database
   - Each service maintains connection pool
   - PgBouncer prevents PostgreSQL connection exhaustion

4. **Database Migration/Failover**
   - PgBouncer can redirect connections without client changes
   - Useful for blue-green deployments

**When NOT to Use PgBouncer:**

- Long-running analytical queries (use direct connection)
- Administrative tasks (backups, maintenance)
- Applications requiring LISTEN/NOTIFY or advisory locks
- Single-user development environments

#### Performance Tuning

**Pool Size Configuration:**

```bash
# In .env or docker-compose.yml environment
PGBOUNCER_DEFAULT_POOL_SIZE=10      # Connections per user/database
PGBOUNCER_MIN_POOL_SIZE=5           # Keep minimum connections warm
PGBOUNCER_RESERVE_POOL_SIZE=5       # Extra connections for bursts
PGBOUNCER_MAX_CLIENT_CONN=100       # Maximum client connections
PGBOUNCER_MAX_DB_CONNECTIONS=20     # Total connections to PostgreSQL
```

**Tuning Guidelines:**

| Scenario | Pool Size | Max Clients | Max DB Connections |
|----------|-----------|-------------|-------------------|
| **Development** | 5-10 | 25-50 | 10-20 |
| **Small Production** | 10-20 | 100-200 | 20-40 |
| **Medium Production** | 20-50 | 500-1000 | 50-100 |
| **Large Production** | 50-100 | 2000-5000 | 100-200 |

**Formula:** `max_db_connections = pool_size * (number of databases * number of users)`

**Connection Timeout Settings:**

```bash
PGBOUNCER_SERVER_IDLE_TIMEOUT=600   # Close idle server connections after 10min
PGBOUNCER_CLIENT_IDLE_TIMEOUT=300   # Disconnect idle clients after 5min
PGBOUNCER_QUERY_TIMEOUT=0           # No query timeout (0 = disabled)
PGBOUNCER_QUERY_WAIT_TIMEOUT=120    # Wait 2min for available connection
```

#### Monitoring

**Pool Utilization Metrics:**

```bash
# Connect to PgBouncer admin console
psql -h localhost -p 6432 -U pgbouncer pgbouncer

# Show pool statistics
SHOW POOLS;
# Output: database, user, cl_active, cl_waiting, sv_active, sv_idle, sv_used
#         dev_database, dev_admin, 5, 0, 3, 2, 8

# Show active clients
SHOW CLIENTS;

# Show server connections
SHOW SERVERS;

# Show configuration
SHOW CONFIG;

# Show statistics
SHOW STATS;
```

**Key Metrics to Monitor:**

1. **cl_waiting** - Clients waiting for connection (should be 0)
2. **sv_active** - Active server connections (should be < pool_size)
3. **sv_idle** - Idle server connections (pool of ready connections)
4. **total_xact_count** - Total transactions processed
5. **avg_xact_time** - Average transaction time

**Prometheus Metrics** (if using pgbouncer_exporter):
```bash
# Available at http://localhost:9127/metrics
pgbouncer_pools_server_active_connections
pgbouncer_pools_server_idle_connections
pgbouncer_pools_client_active_connections
pgbouncer_pools_client_waiting_connections
pgbouncer_stats_total_xact_count
pgbouncer_stats_avg_xact_time_microseconds
```

#### Troubleshooting

**Problem: Connection Pool Exhausted**

**Symptoms:**
```
ERROR: connection pool exhausted
FATAL: sorry, too many clients already
```

**Solutions:**
```bash
# 1. Increase pool size
PGBOUNCER_DEFAULT_POOL_SIZE=20  # Was: 10

# 2. Increase PostgreSQL max_connections
POSTGRES_MAX_CONNECTIONS=200    # Was: 100

# 3. Check for connection leaks
SHOW POOLS;  # Look for high cl_active without corresponding queries
SHOW CLIENTS;  # Identify misbehaving clients

# 4. Enable connection recycling
PGBOUNCER_SERVER_IDLE_TIMEOUT=300  # Close idle connections faster
```

**Problem: Slow Query Performance**

**Symptoms:**
- Queries slower through PgBouncer than direct connection

**Solutions:**
```bash
# 1. Check pool wait time
SHOW STATS;  # Look at avg_wait_time

# 2. Increase pool size if clients waiting
PGBOUNCER_DEFAULT_POOL_SIZE=20

# 3. Check for connection mode mismatch
# Ensure using transaction mode for web apps
PGBOUNCER_POOL_MODE=transaction

# 4. Monitor query timeouts
SHOW SERVERS;  # Look for long-running queries blocking pool
```

**Problem: Authentication Failures**

**Symptoms:**
```
FATAL: authentication failed for user "dev_admin"
FATAL: MD5 authentication failed
```

**Solutions:**
```bash
# 1. Verify PostgreSQL uses MD5 (not SCRAM-SHA-256)
docker exec dev-postgres grep "password_encryption" /var/lib/postgresql/data/postgresql.conf

# 2. Check userlist.txt has correct credentials
docker exec dev-pgbouncer cat /etc/pgbouncer/userlist.txt

# 3. Verify Vault credentials match
./devstack vault-show-password postgres

# 4. Restart PgBouncer after credential changes
docker compose restart pgbouncer
```

**Problem: PgBouncer Not Forwarding Queries**

**Symptoms:**
- Connections succeed but queries hang

**Solutions:**
```bash
# 1. Check PgBouncer logs
docker logs dev-pgbouncer

# 2. Verify PostgreSQL connectivity
docker exec dev-pgbouncer psql -h postgres -p 5432 -U dev_admin -d dev_database -c "SELECT 1;"

# 3. Check admin console
psql -h localhost -p 6432 -U pgbouncer pgbouncer -c "SHOW SERVERS;"

# 4. Restart PgBouncer
docker compose restart pgbouncer
```

#### Configuration Examples

**High-Throughput Web Application:**

```bash
# .env configuration
PGBOUNCER_POOL_MODE=transaction
PGBOUNCER_DEFAULT_POOL_SIZE=20
PGBOUNCER_MAX_CLIENT_CONN=500
PGBOUNCER_MAX_DB_CONNECTIONS=40
PGBOUNCER_SERVER_IDLE_TIMEOUT=300
PGBOUNCER_QUERY_WAIT_TIMEOUT=60
```

**Long-Running Session-Based Application:**

```bash
PGBOUNCER_POOL_MODE=session
PGBOUNCER_DEFAULT_POOL_SIZE=50
PGBOUNCER_MAX_CLIENT_CONN=100
PGBOUNCER_SERVER_IDLE_TIMEOUT=600
PGBOUNCER_CLIENT_IDLE_TIMEOUT=3600
```

**Microservices with Burst Traffic:**

```bash
PGBOUNCER_POOL_MODE=transaction
PGBOUNCER_DEFAULT_POOL_SIZE=10
PGBOUNCER_RESERVE_POOL_SIZE=10
PGBOUNCER_MAX_CLIENT_CONN=1000
PGBOUNCER_MAX_DB_CONNECTIONS=30
PGBOUNCER_QUERY_WAIT_TIMEOUT=30
```

#### Connection Examples

**Direct PostgreSQL Connection (Port 5432):**
```bash
# For long-lived connections, admin tasks
psql -h localhost -p 5432 -U $POSTGRES_USER -d $POSTGRES_DB

# Use cases:
# - Database migrations
# - Backups and restores
# - pg_dump/pg_restore
# - Administrative queries
# - Long-running analytical queries
```

**PgBouncer Connection (Port 6432):**
```bash
# For application connections, APIs
psql -h localhost -p 6432 -U $POSTGRES_USER -d $POSTGRES_DB

# Use cases:
# - Web application queries
# - REST API endpoints
# - Microservice database access
# - Connection pool management
# - High-frequency short transactions
```

**Application Configuration:**

```python
# Python (asyncpg example)
import asyncpg

# Use PgBouncer for application connections
pool = await asyncpg.create_pool(
    host='localhost',
    port=6432,  # PgBouncer port
    user='dev_admin',
    password='<from-vault>',
    database='dev_database',
    min_size=5,
    max_size=20,
    command_timeout=60
)
```

```javascript
// Node.js (pg example)
const { Pool } = require('pg');

// Use PgBouncer for connection pooling
const pool = new Pool({
  host: 'localhost',
  port: 6432,  // PgBouncer port
  user: 'dev_admin',
  password: '<from-vault>',
  database: 'dev_database',
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});
```

#### Performance Benchmarks

**Without PgBouncer:**
- Direct PostgreSQL connections
- Connection overhead: ~50-100ms per connection
- Max concurrent connections: 100 (PostgreSQL limit)
- Connection setup cost: High

**With PgBouncer:**
- Pooled connections
- Connection overhead: ~1-5ms (reusing existing connections)
- Max concurrent clients: 1000+ (configurable)
- Connection setup cost: Minimal (pool reuse)

**Throughput Improvement:**
- Simple queries: 50-100% improvement
- High-frequency requests: 200-300% improvement
- Connection-intensive workloads: 500% improvement

#### Related Documentation

- PostgreSQL connection management: [PostgreSQL](#postgresql)
- Performance tuning: `docs/PERFORMANCE_TUNING.md`
- Connection pooling best practices: `reference-apps/README.md`

### MySQL

**Purpose:** Legacy database support during migration period.

**Configuration:**
- Image: `mysql:8.0.40`
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
- Image: `mongo:7.0`
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

**Purpose:** Self-hosted Git server (Gitea fork) for private repositories with full Git forge capabilities.

**Configuration:**
- Image: `forgejo:1.21`
- Uses PostgreSQL for metadata storage
- Git data stored in Docker volume (`forgejo_data`)
- SSH port mapped to 2222 (to avoid conflict with Mac's SSH on 22)
- HTTP/HTTPS ports: 3000 (configurable)
- **Credentials:** Auto-configured from PostgreSQL Vault credentials

#### First-Time Setup

**Installation Wizard:**

1. **Navigate to Forgejo**
   ```bash
   open http://localhost:3000
   ```

2. **Complete Installation Wizard**
   - **Database Settings:**
     - Database type: PostgreSQL
     - Host: `postgres:5432` (internal Docker network)
     - Username: `dev_admin` (from Vault)
     - Password: (auto-filled from environment)
     - Database name: `forgejo`
     - SSL Mode: Disable (internal network)

   - **General Settings:**
     - Site title: "DevStack Git"
     - Repository root path: `/data/git/repositories`
     - Git LFS root path: `/data/git/lfs`
     - Run as username: `git`
     - SSH server domain: `localhost`
     - SSH port: `2222`
     - HTTP listen port: `3000`
     - Base URL: `http://localhost:3000/`

   - **Optional Settings:**
     - Email: Configure SMTP for notifications (optional)
     - Server and Third-Party Services: Enable/disable features

3. **Create Administrator Account**
   ```
   Username: admin
   Email: admin@localhost
   Password: <secure-password>
   ```

4. **Initial Configuration Complete**
   - You'll be automatically logged in
   - Start creating organizations and repositories

**Automated Setup** (scripted):

```bash
# Use management script for automated setup
./devstack forgejo-init

# Or manually via API
curl -X POST http://localhost:3000/api/v1/user/setup \
  -H "Content-Type: application/json" \
  -d '{
    "user_name": "admin",
    "email": "admin@localhost",
    "password": "<secure-password>",
    "admin": true
  }'
```

#### Git Operations

**HTTP Clone:**
```bash
# Public repository (read-only)
git clone http://localhost:3000/username/repo.git

# Private repository (requires authentication)
git clone http://admin:password@localhost:3000/username/private-repo.git

# Using credentials helper (recommended)
git config --global credential.helper store
git clone http://localhost:3000/username/repo.git
# Enter username/password once, stored for future use
```

**SSH Clone:**
```bash
# Standard SSH URL
git clone ssh://git@localhost:2222/username/repo.git

# Alternative syntax
git clone git@localhost:2222:username/repo.git
```

**SSH Configuration** (`~/.ssh/config`):
```bash
# Add entry for Forgejo
Host forgejo
  HostName localhost
  Port 2222
  User git
  IdentityFile ~/.ssh/id_rsa
  PreferredAuthentications publickey

# Usage
git clone forgejo:username/repo.git
git remote add origin forgejo:username/repo.git
```

**Common Git Workflows:**
```bash
# Create new repository on Forgejo first, then:
mkdir my-project && cd my-project
git init
git add README.md
git commit -m "Initial commit"
git remote add origin http://localhost:3000/admin/my-project.git
git push -u origin main

# Clone existing
git clone http://localhost:3000/admin/my-project.git
cd my-project
git checkout -b feature-branch
# Make changes
git add .
git commit -m "Add feature"
git push origin feature-branch
```

#### SSH and GPG Key Management

**Adding SSH Keys:**

1. **Generate SSH Key** (if needed)
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/forgejo_ed25519
   ```

2. **Add to Forgejo UI**
   - Navigate to Settings → SSH / GPG Keys
   - Click "Add Key"
   - Paste public key: `cat ~/.ssh/forgejo_ed25519.pub`
   - Give it a descriptive name
   - Click "Add Key"

3. **Test SSH Connection**
   ```bash
   ssh -T -p 2222 git@localhost
   # Output: Hi there, <username>! You've successfully authenticated...
   ```

4. **Use SSH for Git Operations**
   ```bash
   git clone ssh://git@localhost:2222/username/repo.git
   ```

**Adding GPG Keys for Signed Commits:**

1. **Generate GPG Key** (if needed)
   ```bash
   gpg --full-generate-key
   # Select: (1) RSA and RSA, 4096 bits, no expiration
   ```

2. **Get GPG Key ID**
   ```bash
   gpg --list-secret-keys --keyid-format=long
   # Note the key ID (e.g., 3AA5C34371567BD2)
   ```

3. **Export Public Key**
   ```bash
   gpg --armor --export 3AA5C34371567BD2
   ```

4. **Add to Forgejo UI**
   - Navigate to Settings → SSH / GPG Keys
   - Click "Add GPG Key"
   - Paste exported public key
   - Click "Add Key"

5. **Configure Git to Sign Commits**
   ```bash
   git config --global user.signingkey 3AA5C34371567BD2
   git config --global commit.gpgsign true
   ```

6. **Make Signed Commit**
   ```bash
   git commit -S -m "Signed commit message"
   git log --show-signature
   ```

For detailed SSH and GPG setup, see [CONTRIBUTING.md](../.github/CONTRIBUTING.md#setting-up-ssh-and-gpg-keys-for-forgejo).

#### User Management

**Creating Users (Admin):**

1. **Via Web UI:**
   - Navigate to Site Administration → User Accounts
   - Click "Create User Account"
   - Fill in details (username, email, password)
   - Set permissions and quotas
   - Click "Create User Account"

2. **Via API:**
   ```bash
   curl -X POST http://localhost:3000/api/v1/admin/users \
     -H "Authorization: token <admin-token>" \
     -H "Content-Type: application/json" \
     -d '{
       "username": "developer",
       "email": "dev@example.com",
       "password": "password123",
       "must_change_password": true
     }'
   ```

**User Permissions:**
- **Administrator:** Full system access
- **Regular User:** Can create repos, organizations
- **Restricted:** Limited permissions
- **Bot:** Automation accounts

**User Quotas:**
```bash
# Set via Site Administration → Users → Edit
- Max repositories: 10
- Max organizations: 3
- Repository size limit: 1GB
```

#### Repository Mirroring

**Mirror External Repository:**

1. **Via Web UI:**
   - Click "+" → "New Migration"
   - Select source (GitHub, GitLab, Gitea, etc.)
   - Enter repository URL
   - Configure mirror settings:
     - Mirror interval: 8 hours (default)
     - Mirror on push: Enable for two-way sync
   - Click "Migrate Repository"

2. **Via API:**
   ```bash
   curl -X POST http://localhost:3000/api/v1/repos/migrate \
     -H "Authorization: token <token>" \
     -H "Content-Type: application/json" \
     -d '{
       "clone_addr": "https://github.com/user/repo.git",
       "repo_name": "mirrored-repo",
       "mirror": true,
       "private": false,
       "uid": 1
     }'
   ```

**Mirror Types:**
- **Pull Mirror:** One-way sync from external source
- **Push Mirror:** One-way sync to external destination
- **Two-way Sync:** Bidirectional synchronization (advanced)

**Mirror Configuration:**
```bash
# Update mirror manually
curl -X POST http://localhost:3000/api/v1/repos/{owner}/{repo}/mirror-sync \
  -H "Authorization: token <token>"

# View mirror status
curl http://localhost:3000/api/v1/repos/{owner}/{repo} \
  -H "Authorization: token <token>" | jq '.mirror_interval'
```

#### Webhook Configuration

**CI/CD Integration:**

1. **Create Webhook:**
   - Navigate to Repository → Settings → Webhooks
   - Click "Add Webhook"
   - Select type (Gitea, Slack, Discord, Generic)

2. **Configure Webhook:**
   ```json
   {
     "type": "gitea",
     "config": {
       "url": "https://ci.example.com/webhooks/forgejo",
       "content_type": "json",
       "secret": "<webhook-secret>"
     },
     "events": [
       "push",
       "create",
       "delete",
       "pull_request"
     ],
     "active": true
   }
   ```

3. **Test Webhook:**
   - Click "Test Delivery"
   - Check response status
   - View delivery history

**Common Webhook Events:**
- `push` - Code pushed to repository
- `pull_request` - PR opened, closed, merged
- `issue` - Issue created, edited, closed
- `release` - Release published
- `repository` - Repository created, deleted

**Example CI/CD Webhook Handler:**
```python
from flask import Flask, request, jsonify
import hmac, hashlib

app = Flask(__name__)
WEBHOOK_SECRET = "your-secret-here"

@app.route('/webhooks/forgejo', methods=['POST'])
def handle_webhook():
    # Verify signature
    signature = request.headers.get('X-Gitea-Signature')
    payload = request.data
    expected = hmac.new(
        WEBHOOK_SECRET.encode(),
        payload,
        hashlib.sha256
    ).hexdigest()

    if not hmac.compare_digest(signature, expected):
        return jsonify({'error': 'Invalid signature'}), 403

    # Process webhook
    data = request.json
    if data['event'] == 'push':
        # Trigger build
        trigger_ci_build(data['repository']['full_name'])

    return jsonify({'status': 'success'}), 200
```

#### Backup and Restore

**Backup Forgejo Data:**

1. **Database Backup** (PostgreSQL):
   ```bash
   # Backup Forgejo database
   docker exec dev-postgres pg_dump -U dev_admin forgejo > forgejo-db-backup.sql

   # Or use management script
   ./devstack backup
   ```

2. **Git Repository Backup:**
   ```bash
   # Backup all repositories (Docker volume)
   docker run --rm \
     -v devstack-core_forgejo_data:/data \
     -v $(pwd):/backup \
     alpine tar czf /backup/forgejo-repos-backup.tar.gz /data
   ```

3. **Configuration Backup:**
   ```bash
   # Backup Forgejo config
   docker cp dev-forgejo:/data/gitea/conf/app.ini forgejo-app.ini.backup
   ```

**Automated Backup Script:**
```bash
#!/bin/bash
# backup-forgejo.sh

BACKUP_DIR="$HOME/backups/forgejo/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# 1. Backup database
docker exec dev-postgres pg_dump -U dev_admin forgejo > "$BACKUP_DIR/database.sql"

# 2. Backup repositories and data
docker run --rm \
  -v devstack-core_forgejo_data:/data \
  -v "$BACKUP_DIR":/backup \
  alpine tar czf /backup/repositories.tar.gz /data

# 3. Backup configuration
docker cp dev-forgejo:/data/gitea/conf/app.ini "$BACKUP_DIR/app.ini"

echo "Backup completed: $BACKUP_DIR"
```

**Restore Forgejo:**

1. **Stop Forgejo:**
   ```bash
   docker compose stop forgejo
   ```

2. **Restore Database:**
   ```bash
   docker exec -i dev-postgres psql -U dev_admin forgejo < forgejo-db-backup.sql
   ```

3. **Restore Repositories:**
   ```bash
   docker run --rm \
     -v devstack-core_forgejo_data:/data \
     -v $(pwd):/backup \
     alpine sh -c "cd / && tar xzf /backup/forgejo-repos-backup.tar.gz"
   ```

4. **Restore Configuration:**
   ```bash
   docker cp forgejo-app.ini.backup dev-forgejo:/data/gitea/conf/app.ini
   ```

5. **Restart Forgejo:**
   ```bash
   docker compose up -d forgejo
   ```

#### Performance Optimization

**Large Repository Handling:**

1. **Enable Git LFS:**
   ```bash
   # In app.ini (or via environment)
   [lfs]
   ENABLED = true
   PATH = /data/git/lfs

   # Client setup
   git lfs install
   git lfs track "*.psd"
   git lfs track "*.zip"
   ```

2. **Repository Size Limits:**
   ```bash
   # In app.ini
   [repository]
   MAX_SIZE = 100  # MB
   MAX_CREATION_LIMIT = -1  # Unlimited for admins
   ```

3. **Garbage Collection:**
   ```bash
   # Manual GC for specific repository
   docker exec dev-forgejo sh -c \
     "cd /data/git/repositories/username/repo.git && git gc --aggressive --prune=now"

   # Automatic GC (scheduled)
   # In app.ini:
   [cron.update_mirrors]
   ENABLED = true
   SCHEDULE = @every 8h
   ```

4. **Database Optimization:**
   ```bash
   # Vacuum PostgreSQL
   docker exec dev-postgres psql -U dev_admin forgejo -c "VACUUM ANALYZE;"

   # Reindex
   docker exec dev-postgres psql -U dev_admin forgejo -c "REINDEX DATABASE forgejo;"
   ```

**Caching Configuration:**
```bash
# In app.ini
[cache]
ENABLED = true
ADAPTER = redis
HOST = redis-1:6379
PASSWORD = <from-vault>

[session]
PROVIDER = redis
PROVIDER_CONFIG = redis-1:6379
```

**Resource Tuning:**
```yaml
# docker-compose.yml
forgejo:
  deploy:
    resources:
      limits:
        cpus: '2.0'
        memory: 2G
      reservations:
        cpus: '1.0'
        memory: 512M
```

#### Accessing from Network

**Local Network Access:**

1. **Set Forgejo Domain:**
   ```bash
   # In .env
   FORGEJO_DOMAIN=192.168.106.2  # Colima IP address

   # Or find Colima IP
   colima status | grep "IP Address"
   ```

2. **Update Base URL:**
   ```bash
   # In Forgejo app.ini
   [server]
   ROOT_URL = http://192.168.106.2:3000/
   ```

3. **Access from Other Machines:**
   ```bash
   # From libvirt VM or other computer on network
   git clone http://192.168.106.2:3000/admin/repo.git
   ```

**SSH Access from Network:**
```bash
# Configure SSH for network access
Host forgejo-network
  HostName 192.168.106.2
  Port 2222
  User git
  IdentityFile ~/.ssh/id_rsa

# Clone from network
git clone forgejo-network:username/repo.git
```

#### Troubleshooting

**Problem: Cannot Connect to Database**

**Symptoms:**
- Forgejo fails to start
- "Failed to connect to database" errors

**Solutions:**
```bash
# 1. Verify PostgreSQL is running
docker compose ps postgres

# 2. Test database connection
docker exec dev-postgres psql -U dev_admin -d forgejo -c "SELECT 1;"

# 3. Check Forgejo logs
docker logs dev-forgejo | grep -i database

# 4. Verify credentials
./devstack vault-show-password postgres

# 5. Restart Forgejo
docker compose restart forgejo
```

**Problem: SSH Push/Pull Not Working**

**Symptoms:**
- `Permission denied (publickey)` errors
- SSH authentication failures

**Solutions:**
```bash
# 1. Test SSH connection
ssh -vT -p 2222 git@localhost

# 2. Verify SSH key added to Forgejo
# Check Settings → SSH/GPG Keys in web UI

# 3. Check SSH key permissions
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# 4. Verify SSH config
cat ~/.ssh/config | grep -A 5 forgejo

# 5. Check Forgejo SSH logs
docker logs dev-forgejo | grep -i ssh
```

**Problem: Webhook Not Triggering**

**Symptoms:**
- CI/CD not triggering on push
- Webhook shows failed deliveries

**Solutions:**
```bash
# 1. Test webhook manually
curl -X POST https://ci.example.com/webhooks/forgejo \
  -H "Content-Type: application/json" \
  -d @webhook-payload.json

# 2. Check webhook deliveries
# Repository → Settings → Webhooks → Edit → Recent Deliveries

# 3. Verify webhook secret
# Check HMAC signature validation

# 4. Check network connectivity
docker exec dev-forgejo curl -I https://ci.example.com

# 5. Enable webhook debugging
# In app.ini: LOG_LEVEL = debug
```

**Problem: Large Repositories Slow Performance**

**Symptoms:**
- Slow clone/push operations
- High memory usage

**Solutions:**
```bash
# 1. Enable Git LFS for large files
git lfs migrate import --include="*.zip,*.tar.gz"

# 2. Run garbage collection
cd /data/git/repositories/username/repo.git
git gc --aggressive --prune=now

# 3. Increase resource limits
# Adjust docker-compose.yml resources

# 4. Enable caching (Redis)
# Configure [cache] in app.ini

# 5. Archive old repositories
# Site Administration → Repositories → Archive
```

#### Related Documentation

- SSH/GPG setup: [CONTRIBUTING.md](../.github/CONTRIBUTING.md)
- Backup procedures: [DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md)
- Performance tuning: [PERFORMANCE_TUNING.md](./PERFORMANCE_TUNING.md)
- PostgreSQL integration: [PostgreSQL](#postgresql)

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

