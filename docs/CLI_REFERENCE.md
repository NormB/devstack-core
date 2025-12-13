# CLI Reference

Complete reference for the `devstack` command-line interface.

---

## Quick Reference Card

```bash
# Lifecycle
./devstack start                    # Start all services
./devstack stop                     # Stop all services
./devstack restart                  # Restart services
./devstack reset                    # Delete everything

# Status
./devstack status                   # VM and container status
./devstack health                   # Health check all services

# Logs & Shell
./devstack logs [service]           # View logs
./devstack logs -f postgres         # Follow logs
./devstack shell mysql              # Shell into container

# Vault
./devstack vault-init               # Initialize Vault
./devstack vault-bootstrap          # Setup credentials
./devstack vault-status             # Vault status
./devstack vault-show-password pg   # Get password

# Data
./devstack backup                   # Backup databases
./devstack restore                  # List/restore backups

# Profiles
./devstack start --profile minimal  # Minimal services
./devstack start --profile full     # All services
./devstack profiles                 # List profiles
```

---

## Command Categories

| Category | Commands |
|----------|----------|
| **Lifecycle** | `start`, `stop`, `restart`, `reset` |
| **Status** | `status`, `health`, `ip` |
| **Logs & Shell** | `logs`, `shell` |
| **Vault** | `vault-init`, `vault-unseal`, `vault-status`, `vault-token`, `vault-bootstrap`, `vault-ca-cert`, `vault-show-password` |
| **Data** | `backup`, `restore`, `verify` |
| **Setup** | `forgejo-init`, `redis-cluster-init`, `profiles` |

---

## Lifecycle Commands

### start

Start Colima VM and Docker services.

```bash
./devstack start [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--profile` | Service profile to start | `standard` |
| `--no-vm` | Don't start Colima VM (use existing) | false |

**Examples:**
```bash
# Start with default profile (standard)
./devstack start

# Start minimal services only
./devstack start --profile minimal

# Start with monitoring
./devstack start --profile full

# Combine profiles
./devstack start --profile standard --profile reference

# Skip VM startup (already running)
./devstack start --no-vm
```

**What it does:**
1. Starts Colima VM (if not running)
2. Pulls Docker images (if needed)
3. Starts containers in dependency order
4. Waits for health checks

---

### stop

Stop Docker services and optionally Colima VM.

```bash
./devstack stop [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--vm` | Also stop Colima VM | false |

**Examples:**
```bash
# Stop containers only (VM keeps running)
./devstack stop

# Stop everything including VM
./devstack stop --vm
```

**What it does:**
1. Stops all Docker containers
2. Preserves data volumes
3. Optionally stops Colima VM

---

### restart

Restart all Docker services without restarting VM.

```bash
./devstack restart [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--profile` | Profile to restart with | current |

**Examples:**
```bash
# Restart all services
./devstack restart

# Restart with different profile
./devstack restart --profile minimal
```

---

### reset

Completely reset and delete Colima VM. **DESTRUCTIVE!**

```bash
./devstack reset [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--force` | Skip confirmation prompt | false |

**Examples:**
```bash
# Reset with confirmation
./devstack reset

# Reset without confirmation (scripts)
./devstack reset --force
```

**What it does:**
1. Stops all containers
2. Removes all containers
3. Removes all volumes (data deleted!)
4. Deletes Colima VM
5. Preserves Vault keys in `~/.config/vault/`

**Warning:** This deletes all database data. Back up first with `./devstack backup`.

---

## Status Commands

### status

Display Colima VM and service status.

```bash
./devstack status
```

**Output shows:**
- Colima VM state (running/stopped)
- CPU, memory, disk allocation
- Container status for each service

**Example output:**
```
═══ DevStack Core - Status ═══

Colima VM Status:
  Status: Running
  CPU: 4 cores
  Memory: 8 GB
  Disk: 60 GB

Container Status:
  dev-vault         running
  dev-postgres      running
  dev-mysql         running
  ...
```

---

### health

Check health status of all running services.

```bash
./devstack health
```

**Output shows:**
- Service name
- Running status
- Health check result (healthy/unhealthy/starting)

**Example output:**
```
        Service Health Status
╭───────────────┬─────────┬─────────╮
│ Service       │ Status  │ Health  │
├───────────────┼─────────┼─────────┤
│ vault         │ running │ healthy │
│ postgres      │ running │ healthy │
│ mysql         │ running │ healthy │
│ redis-1       │ running │ healthy │
╰───────────────┴─────────┴─────────╯
```

---

### ip

Display Colima VM IP address.

```bash
./devstack ip
```

**Example output:**
```
192.168.106.2
```

**Use case:** When you need to connect from another VM or container outside the Docker network.

---

## Logs & Shell Commands

### logs

View logs for all services or a specific service.

```bash
./devstack logs [SERVICE] [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `-f`, `--follow` | Follow log output | false |
| `-n`, `--tail` | Number of lines | 100 |
| `--since` | Show logs since timestamp | all |

**Examples:**
```bash
# View all service logs
./devstack logs

# View specific service logs
./devstack logs postgres

# Follow logs in real-time
./devstack logs -f postgres

# Last 50 lines only
./devstack logs -n 50 vault

# Logs from last hour
./devstack logs --since 1h redis-1
```

---

### shell

Open an interactive shell in a running container.

```bash
./devstack shell SERVICE [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--user` | User to run shell as | container default |

**Examples:**
```bash
# Shell into PostgreSQL container
./devstack shell postgres

# Shell into MySQL as root
./devstack shell mysql --user root

# Shell into Redis
./devstack shell redis-1
```

**Common use cases:**
```bash
# PostgreSQL psql
./devstack shell postgres
$ psql -U devuser devdb

# MySQL client
./devstack shell mysql
$ mysql -u devuser -p devdb

# Redis CLI
./devstack shell redis-1
$ redis-cli -a $REDIS_PASSWORD
```

---

## Vault Commands

### vault-init

Initialize and unseal Vault (first-time setup).

```bash
./devstack vault-init
```

**What it does:**
1. Initializes Vault with 5 key shares, 3 threshold
2. Saves unseal keys to `~/.config/vault/keys.json`
3. Saves root token to `~/.config/vault/root-token`
4. Automatically unseals Vault

**When to use:** First time after `./devstack reset` or fresh install.

---

### vault-unseal

Manually unseal Vault using stored keys.

```bash
./devstack vault-unseal
```

**What it does:**
1. Reads keys from `~/.config/vault/keys.json`
2. Submits unseal keys until threshold reached
3. Vault becomes operational

**When to use:** After Vault container restart if auto-unseal failed.

---

### vault-status

Display Vault seal status and token information.

```bash
./devstack vault-status
```

**Example output:**
```
═══ Vault Status ═══

Seal Status:
  Sealed: false
  Version: 1.18.5
  Cluster: vault-cluster-abc123

Root Token:
  Stored at: ~/.config/vault/root-token
  Token: hvs.CAESI... (truncated)
```

---

### vault-token

Print Vault root token to stdout.

```bash
./devstack vault-token
```

**Example output:**
```
hvs.CAESIxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Use case:** Piping to other commands:
```bash
export VAULT_TOKEN=$(./devstack vault-token)
vault kv list secret/
```

---

### vault-bootstrap

Bootstrap Vault with PKI and service credentials.

```bash
./devstack vault-bootstrap [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--regenerate` | Regenerate all credentials | false |

**What it does:**
1. Enables KV secrets engine
2. Sets up PKI (Root CA → Intermediate CA)
3. Creates certificate roles for each service
4. Generates and stores service passwords
5. Configures AppRole authentication
6. Exports CA certificates

**When to use:** After `vault-init` or when credentials need regeneration.

---

### vault-ca-cert

Export Vault CA certificate chain to stdout.

```bash
./devstack vault-ca-cert
```

**Output:** PEM-encoded certificate chain (Root CA + Intermediate CA)

**Use case:** Adding to trust store:
```bash
./devstack vault-ca-cert > ca-chain.pem
```

---

### vault-show-password

Retrieve and display service credentials from Vault.

```bash
./devstack vault-show-password SERVICE
```

**Available services:**
- `postgres` or `postgresql`
- `mysql`
- `mongodb` or `mongo`
- `redis`
- `rabbitmq`

**Examples:**
```bash
# Get PostgreSQL credentials
./devstack vault-show-password postgres

# Get MySQL credentials
./devstack vault-show-password mysql

# Get Redis password
./devstack vault-show-password redis
```

**Example output:**
```
═══ PostgreSQL Credentials ═══

Username: devuser
Password: Hx7kL9mNpQr2sTuVwXyZ12345
Database: devdb
Host: localhost
Port: 5432

Connection String:
  postgresql://devuser:Hx7kL9mNpQr2sTuVwXyZ12345@localhost:5432/devdb
```

---

## Data Commands

### backup

Backup all service data to timestamped directory.

```bash
./devstack backup [OPTIONS]
```

**Options:**
| Option | Description | Default |
|--------|-------------|---------|
| `--output` | Custom output directory | `./backups/YYYYMMDD_HHMMSS` |
| `--encrypt` | Encrypt backup with GPG | false |

**Examples:**
```bash
# Create backup with timestamp
./devstack backup

# Backup to specific directory
./devstack backup --output ./my-backup

# Create encrypted backup
./devstack backup --encrypt
```

**What gets backed up:**
- PostgreSQL: Full database dump
- MySQL: Full database dump
- MongoDB: Archive dump
- Redis: RDB snapshot
- Forgejo: Git repositories
- Configuration files

---

### restore

Restore service data from backup.

```bash
./devstack restore [BACKUP_ID]
```

**Examples:**
```bash
# List available backups
./devstack restore

# Restore specific backup
./devstack restore 20250113_143022
```

**List output:**
```
═══ Available Backups ═══

╭─────────────────────┬──────────────┬──────────╮
│ Backup ID           │ Date         │ Size     │
├─────────────────────┼──────────────┼──────────┤
│ 20250113_143022     │ Jan 13, 2025 │ 156 MB   │
│ 20250112_091500     │ Jan 12, 2025 │ 148 MB   │
╰─────────────────────┴──────────────┴──────────╯
```

---

### verify

Verify backup integrity using checksums.

```bash
./devstack verify BACKUP_ID
```

**Example:**
```bash
./devstack verify 20250113_143022
```

**Output:**
```
═══ Backup Verification ═══

Backup: 20250113_143022
Status: Valid

Files:
  ✓ postgres_all.sql (sha256 verified)
  ✓ mysql_all.sql (sha256 verified)
  ✓ mongodb_dump.archive (sha256 verified)
```

---

## Setup Commands

### forgejo-init

Initialize Forgejo via automated bootstrap.

```bash
./devstack forgejo-init
```

**What it does:**
1. Waits for Forgejo to be healthy
2. Creates initial admin user (if not exists)
3. Configures Forgejo settings

**When to use:** After first start to set up Forgejo.

---

### redis-cluster-init

Initialize Redis cluster for standard/full profiles.

```bash
./devstack redis-cluster-init
```

**What it does:**
1. Waits for all 3 Redis nodes
2. Creates cluster with `redis-cli --cluster create`
3. Assigns hash slots to each node

**When to use:** After starting with `--profile standard` or `--profile full`.

**Note:** Only needed once. Cluster configuration persists in volumes.

---

### profiles

List all available service profiles with details.

```bash
./devstack profiles
```

**Output:**
```
═══ Available Profiles ═══

╭───────────┬──────────┬─────────────────────────────────────╮
│ Profile   │ Services │ Description                         │
├───────────┼──────────┼─────────────────────────────────────┤
│ minimal   │ 5        │ Core services (Vault, PG, Redis)    │
│ standard  │ 10       │ Full dev stack + Redis cluster      │
│ full      │ 18       │ Standard + observability            │
│ reference │ 5        │ Example APIs (combinable)           │
╰───────────┴──────────┴─────────────────────────────────────╯
```

---

## Environment Variables

The CLI respects these environment variables:

| Variable | Description | Default |
|----------|-------------|---------|
| `COLIMA_PROFILE` | Colima profile name | `default` |
| `COLIMA_CPU` | VM CPU cores | `4` |
| `COLIMA_MEMORY` | VM memory (GB) | `8` |
| `COLIMA_DISK` | VM disk (GB) | `60` |
| `VAULT_ADDR` | Vault server address | `http://localhost:8200` |
| `VAULT_TOKEN` | Vault authentication token | (from file) |

**Example:**
```bash
# Start with more resources
COLIMA_CPU=8 COLIMA_MEMORY=16 ./devstack start
```

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Service not running |
| 4 | Vault error |
| 5 | Docker error |

---

## Getting Help

```bash
# General help
./devstack --help

# Command-specific help
./devstack start --help
./devstack vault-show-password --help

# Version
./devstack --version
```

---

## See Also

- [Getting Started](GETTING_STARTED.md) - Quick start guide
- [Quick Reference](QUICK_REFERENCE.md) - Cheat sheet
- [Troubleshooting](TROUBLESHOOTING.md) - Problem solving
- [Learning Paths](LEARNING_PATHS.md) - Guided learning
