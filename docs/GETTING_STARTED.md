# Getting Started with DevStack Core

> **Time to complete:** 5-10 minutes
> **Prerequisites:** macOS with Apple Silicon, terminal access
> **Result:** A complete local development infrastructure with databases, caching, and secrets management

## What is DevStack Core?

DevStack Core is a **local development infrastructure** that gives you production-like services on your Mac. Instead of installing databases and services individually, you get a complete stack with one command.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            Your Development Mac                             │
│                                                                             │
│  ┌───────────────────────────────────────────────────────────────────────┐  │
│  │                      DevStack Core (Colima VM)                        │  │
│  │                                                                       │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐      │  │
│  │  │   Vault    │  │ PostgreSQL │  │   MySQL    │  │  MongoDB   │      │  │
│  │  │  Secrets   │  │     DB     │  │     DB     │  │     DB     │      │  │
│  │  └────────────┘  └────────────┘  └────────────┘  └────────────┘      │  │
│  │                                                                       │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐      │  │
│  │  │   Redis    │  │  RabbitMQ  │  │  Forgejo   │  │  Grafana   │      │  │
│  │  │  Cluster   │  │  Messages  │  │    Git     │  │  Monitor   │      │  │
│  │  └────────────┘  └────────────┘  └────────────┘  └────────────┘      │  │
│  │                                                                       │  │
│  └───────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  Your App ────────────────────────────────────────────────────────────────▶ │
│  connects to localhost ports (5432, 3306, 6379, etc.)                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### What You Get

| Service | Purpose | Access |
|---------|---------|--------|
| **Vault** | Secrets & certificates | http://localhost:8200 |
| **PostgreSQL** | Relational database | localhost:5432 |
| **MySQL** | Relational database | localhost:3306 |
| **MongoDB** | Document database | localhost:27017 |
| **Redis Cluster** | Caching (3 nodes) | localhost:6379-6381 |
| **RabbitMQ** | Message queue | localhost:5672, http://localhost:15672 |
| **Forgejo** | Git hosting | http://localhost:3000 |
| **Grafana** | Monitoring dashboards | http://localhost:3001 |

---

## Quick Start (5 Minutes)

### Step 1: Install Prerequisites

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install colima docker docker-compose uv
```

### Step 2: Clone and Setup

```bash
# Clone the repository
git clone https://github.com/NormB/devstack-core.git
cd devstack-core

# Create Python environment
uv venv && uv pip install -r scripts/requirements.txt

# Copy environment configuration
cp .env.example .env
```

### Step 3: Start DevStack

```bash
# Start all services (first time takes 2-3 minutes)
./devstack start
```

**What you should see:**
```
═══ DevStack Core - Start Services ═══

Starting with profile(s): standard
✓ Colima VM started

Starting Docker services...
 Container dev-vault Started
 Container dev-postgres Started
 Container dev-mysql Started
 Container dev-mongodb Started
 Container dev-redis-1 Started
 Container dev-redis-2 Started
 Container dev-redis-3 Started
 Container dev-rabbitmq Started
 Container dev-forgejo Started

✓ Services started successfully
```

### Step 4: Initialize Vault (First Time Only)

```bash
# Initialize Vault (creates encryption keys)
./devstack vault-init

# Bootstrap services with credentials
./devstack vault-bootstrap
```

**What you should see:**
```
═══ Vault Initialization ═══
✓ Vault initialized successfully
✓ Keys saved to ~/.config/vault/keys.json
✓ Root token saved to ~/.config/vault/root-token

═══ Vault Bootstrap ═══
✓ PKI engines configured
✓ Service credentials stored
✓ AppRole authentication configured
```

### Step 5: Verify Everything Works

```bash
# Check all services are healthy
./devstack health
```

**What you should see:**
```
        Service Health Status
╭───────────────┬─────────┬─────────╮
│ Service       │ Status  │ Health  │
├───────────────┼─────────┼─────────┤
│ vault         │ running │ healthy │
│ postgres      │ running │ healthy │
│ mysql         │ running │ healthy │
│ mongodb       │ running │ healthy │
│ redis-1       │ running │ healthy │
│ redis-2       │ running │ healthy │
│ redis-3       │ running │ healthy │
│ rabbitmq      │ running │ healthy │
│ forgejo       │ running │ healthy │
╰───────────────┴─────────┴─────────╯
```

---

## Connect Your Application

### Get Database Credentials

DevStack stores all passwords in Vault. Get them with:

```bash
# Get PostgreSQL password
./devstack vault-show-password postgres

# Get all credentials as environment variables
source scripts/load-vault-env.sh
echo $POSTGRES_PASSWORD  # Now available in your shell
```

### Connection Examples

**PostgreSQL (Python)**
```python
import psycopg2

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    database="devdb",
    user="devuser",
    password="<from vault-show-password>"
)
```

**MySQL (Node.js)**
```javascript
const mysql = require('mysql2');

const connection = mysql.createConnection({
    host: 'localhost',
    port: 3306,
    user: 'devuser',
    password: '<from vault-show-password>',
    database: 'devdb'
});
```

**Redis (Go)**
```go
import "github.com/redis/go-redis/v9"

rdb := redis.NewClient(&redis.Options{
    Addr:     "localhost:6379",
    Password: "<from vault-show-password>",
})
```

**MongoDB (Rust)**
```rust
use mongodb::Client;

let uri = "mongodb://devuser:<password>@localhost:27017/devdb";
let client = Client::with_uri_str(uri).await?;
```

---

## Daily Workflow

### Starting Your Day
```bash
cd ~/devstack-core
./devstack start          # Start all services
./devstack health         # Verify everything is healthy
```

### During Development
```bash
./devstack logs postgres  # View PostgreSQL logs
./devstack shell mysql    # Get shell inside MySQL container
./devstack status         # Quick status check
```

### End of Day
```bash
./devstack stop           # Stop all services (data preserved)
```

---

## Choosing a Profile

DevStack has different profiles for different needs:

| Profile | RAM | Services | Use Case |
|---------|-----|----------|----------|
| **minimal** | 2GB | Vault, PostgreSQL, Redis, Forgejo | Light development |
| **standard** | 4GB | + MySQL, MongoDB, RabbitMQ, Redis cluster | Full development |
| **full** | 6GB | + Prometheus, Grafana, Loki, Vector | With monitoring |
| **reference** | +1GB | + Example APIs (5 languages) | Learning/testing |

```bash
# Start with minimal profile
./devstack start --profile minimal

# Start with full monitoring
./devstack start --profile full

# Combine profiles
./devstack start --profile standard --profile reference
```

---

## Common Tasks

### View Logs
```bash
./devstack logs              # All services
./devstack logs postgres     # Specific service
./devstack logs -f redis-1   # Follow logs in real-time
```

### Restart a Service
```bash
./devstack restart postgres
```

### Reset Everything
```bash
./devstack reset             # Stops and removes all containers
./devstack start             # Fresh start
./devstack vault-init        # Re-initialize Vault
./devstack vault-bootstrap   # Re-create credentials
```

### Backup Data
```bash
./devstack backup            # Creates timestamped backup
./devstack restore           # Lists available backups
./devstack restore 20250113_143022  # Restore specific backup
```

---

## Web Interfaces

After starting DevStack, you can access these web UIs:

| Service | URL | Default Login |
|---------|-----|---------------|
| **Vault** | http://localhost:8200 | Token from `~/.config/vault/root-token` |
| **RabbitMQ** | http://localhost:15672 | `./devstack vault-show-password rabbitmq` |
| **Forgejo** | http://localhost:3000 | Create account on first visit |
| **Grafana** | http://localhost:3001 | admin / admin |
| **Prometheus** | http://localhost:9090 | No auth required |

---

## Troubleshooting

### Services Won't Start

```bash
# Check if Colima VM is running
colima status

# If not running, start it
./devstack start

# Check service logs for errors
./devstack logs vault
```

### Database Connection Refused

```bash
# Verify service is healthy
./devstack health

# Check the port is accessible
nc -zv localhost 5432

# Get the correct password
./devstack vault-show-password postgres
```

### Vault is Sealed

```bash
# Check Vault status
./devstack vault-status

# Unseal if needed
./devstack vault-unseal
```

### Need to Start Fresh

```bash
# Complete reset (preserves Vault keys)
./devstack reset
./devstack start
./devstack vault-bootstrap
```

---

## Next Steps

Now that DevStack is running:

1. **Learn the CLI** - See [CLI Reference](CLI_REFERENCE.md) for all commands
2. **Understand the architecture** - Read [Architecture](ARCHITECTURE.md)
3. **Connect your app** - See [Use Cases](USE_CASES.md) for examples
4. **Customize profiles** - See [Service Profiles](SERVICE_PROFILES.md)
5. **Set up monitoring** - Start with `--profile full` and open Grafana

---

## Getting Help

- **Quick reference:** `./devstack --help`
- **Service status:** `./devstack health`
- **Logs:** `./devstack logs <service>`
- **Documentation:** See [docs/README.md](README.md) for full documentation
- **Issues:** https://github.com/NormB/devstack-core/issues
