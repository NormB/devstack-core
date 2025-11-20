# QUICK REFERENCE

**Version:** 1.3.0
**Last Updated:** 2025-01-18

This is your go-to cheat sheet for DevStack Core. All commands, ports, credentials, and common operations on one page.

---

## 🚀 Essential Commands

### Quick Start (First Time)

```bash
# 1. Setup dependencies
cd ~/devstack-core && uv venv && uv pip install -r scripts/requirements.txt

# 2. Start environment
./devstack start --profile standard

# 3. Initialize (one-time only)
./devstack vault-init
./devstack vault-bootstrap
./devstack redis-cluster-init
./devstack forgejo-init

# 4. Verify
./devstack health
```

### Daily Operations

```bash
# Start
./devstack start --profile standard

# Check status
./devstack status
./devstack health

# View logs
./devstack logs [service]

# Stop
./devstack stop
```

---

## 📊 Service Profiles

| Profile | Services | RAM | Command |
|---------|----------|-----|---------|
| **minimal** | 5 | 2GB | `./devstack start --profile minimal` |
| **standard** | 10 | 4GB | `./devstack start --profile standard` |
| **full** | 18 | 6GB | `./devstack start --profile full` |
| **reference** | +5 | +1GB | `./devstack start --profile standard --profile reference` |

---

## 🌐 Service Ports & URLs

### Core Services

| Service | Port(s) | URL | Credentials |
|---------|---------|-----|-------------|
| **Vault** | 8200 | http://localhost:8200/ui | `cat ~/.config/vault/root-token` |
| **Forgejo** | 3000, 2222 | http://localhost:3000 | `./devstack vault-show-password forgejo` |
| **PostgreSQL** | 5432 | localhost:5432 | `./devstack vault-show-password postgres` |
| **PgBouncer** | 6432 | localhost:6432 | (uses PostgreSQL credentials) |
| **MySQL** | 3306 | localhost:3306 | `./devstack vault-show-password mysql` |
| **MongoDB** | 27017 | localhost:27017 | `./devstack vault-show-password mongodb` |
| **Redis-1** | 6379, 6390 | localhost:6379 | `./devstack vault-show-password redis-1` |
| **Redis-2** | 6380, 6391 | localhost:6380 | (same password as redis-1) |
| **Redis-3** | 6381, 6392 | localhost:6381 | (same password as redis-1) |
| **RabbitMQ** | 5672, 15672 | http://localhost:15672 | `./devstack vault-show-password rabbitmq` |

### Observability (Full Profile)

| Service | Port | URL | Credentials |
|---------|------|-----|-------------|
| **Prometheus** | 9090 | http://localhost:9090 | (no auth) |
| **Grafana** | 3001 | http://localhost:3001 | admin / admin |
| **Loki** | 3100 | http://localhost:3100 | (no auth) |

### Reference APIs (Reference Profile)

| API | Port(s) | URL | Docs |
|-----|---------|-----|------|
| **Python (code-first)** | 8000, 8443 | http://localhost:8000 | http://localhost:8000/docs |
| **Python (API-first)** | 8001, 8444 | http://localhost:8001 | http://localhost:8001/docs |
| **Go (Gin)** | 8002, 8445 | http://localhost:8002 | http://localhost:8002/swagger |
| **Node.js (Express)** | 8003, 8446 | http://localhost:8003 | http://localhost:8003/docs |
| **Rust (Actix)** | 8004, 8447 | http://localhost:8004 | http://localhost:8004/docs |

---

## 🔐 Getting Credentials

### Vault Root Token

```bash
# Display token
cat ~/.config/vault/root-token

# Export for Vault CLI
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
export VAULT_ADDR=http://localhost:8200
```

### Service Passwords

```bash
# PostgreSQL
./devstack vault-show-password postgres

# MySQL
./devstack vault-show-password mysql

# MongoDB
./devstack vault-show-password mongodb

# Redis (all nodes use same password)
./devstack vault-show-password redis-1

# RabbitMQ
./devstack vault-show-password rabbitmq

# Forgejo (includes username and email)
./devstack vault-show-password forgejo
```

### Using Vault CLI Directly

```bash
# Set environment
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Get passwords
vault kv get -field=password secret/postgres
vault kv get -field=password secret/mysql
vault kv get -field=password secret/redis-1
vault kv get -field=password secret/rabbitmq
vault kv get -field=password secret/mongodb

# Get all credentials for a service
vault kv get secret/postgres
vault kv get secret/forgejo
```

---

## 🔗 Connection Strings

### PostgreSQL

```bash
# psql (direct)
psql -h localhost -p 5432 -U dev_admin -d dev_database

# psql (via PgBouncer)
psql -h localhost -p 6432 -U dev_admin -d dev_database

# Connection string
postgresql://dev_admin:PASSWORD@localhost:5432/dev_database

# Environment variables
export PGHOST=localhost
export PGPORT=5432
export PGUSER=dev_admin
export PGDATABASE=dev_database
export PGPASSWORD=$(./devstack vault-show-password postgres | awk '/password/ {print $2}')
```

### MySQL

```bash
# mysql CLI
mysql -h localhost -P 3306 -u root -p

# Connection string
mysql://root:PASSWORD@localhost:3306/mysql

# Environment variable
export MYSQL_PWD=$(./devstack vault-show-password mysql | awk '/password/ {print $2}')
mysql -h localhost -u root
```

### MongoDB

```bash
# mongosh CLI
mongosh "mongodb://admin:PASSWORD@localhost:27017"

# Connection string
mongodb://admin:PASSWORD@localhost:27017/?authSource=admin
```

### Redis

```bash
# redis-cli (standalone or cluster)
redis-cli -h localhost -p 6379 -a PASSWORD

# Redis cluster (use -c flag)
redis-cli -c -h localhost -p 6379 -a PASSWORD

# Connection string
redis://:PASSWORD@localhost:6379

# TLS connection
redis-cli -h localhost -p 6390 --tls --insecure -a PASSWORD
```

### RabbitMQ

```bash
# Management UI
open http://localhost:15672
# Username: admin
# Password: (from vault-show-password rabbitmq)

# AMQP connection string
amqp://admin:PASSWORD@localhost:5672/dev_vhost

# AMQPS (TLS)
amqps://admin:PASSWORD@localhost:5671/dev_vhost
```

---

## 🛠️ Common Management Commands

### Environment Control

```bash
# Start with different profiles
./devstack start --profile minimal     # Lightweight (2GB)
./devstack start --profile standard    # Recommended (4GB)
./devstack start --profile full        # Everything (6GB)
./devstack start --profile standard --profile reference  # Standard + APIs

# Stop
./devstack stop                         # Stop everything
./devstack stop --profile reference     # Stop only reference apps

# Restart
./devstack restart                      # Restart all services

# Status & Health
./devstack status                       # VM and service status
./devstack health                       # Health checks
./devstack ip                           # Get Colima VM IP
```

### Logs & Debugging

```bash
# View logs
./devstack logs                         # All services
./devstack logs postgres                # Specific service
./devstack logs vault -f                # Follow logs
./devstack logs --tail 500 redis-1      # Last 500 lines

# Container shell
./devstack shell postgres               # Open shell in container
./devstack shell vault --shell bash     # Use bash instead of sh
```

### Vault Operations

```bash
# Initialize (first time only)
./devstack vault-init                   # Create keys & token
./devstack vault-bootstrap              # Setup PKI & credentials

# Status & Control
./devstack vault-status                 # Check seal status
./devstack vault-unseal                 # Unseal if sealed
./devstack vault-token                  # Display root token

# Certificates
./devstack vault-ca-cert > ca.pem       # Export CA cert

# Credentials
./devstack vault-show-password <service>
```

### Service Initialization

```bash
# Redis cluster (standard/full profiles only)
./devstack redis-cluster-init

# Forgejo Git server
./devstack forgejo-init
```

### Backup & Restore

```bash
# Backup everything
./devstack backup

# List backups
./devstack restore

# Restore from backup
./devstack restore 20250118_143022

# Restart after restore
./devstack restart
```

### Profiles

```bash
# List all available profiles
./devstack profiles
```

---

## 🗂️ Important File Locations

### Vault Data (CRITICAL - BACKUP THIS!)

```
~/.config/vault/
├── keys.json                    # Unseal keys (5 keys, need 3 to unseal)
├── root-token                   # Root token for Vault admin
├── ca/                          # CA certificates
│   ├── root-ca.pem             # Root CA (10-year)
│   └── intermediate-ca.pem     # Intermediate CA (5-year)
└── certs/                       # Service certificates
    ├── postgres/
    ├── mysql/
    ├── redis-{1,2,3}/
    ├── rabbitmq/
    └── mongodb/
```

### Project Files

```
~/devstack-core/
├── devstack              # Python CLI wrapper
├── manage_devstack.py           # Python CLI implementation
├── docker-compose.yml           # Service definitions
├── .env                         # Environment configuration
├── .venv/                       # Python virtual environment
├── configs/                     # Service configurations
│   ├── postgres/               # PostgreSQL init scripts
│   ├── mysql/                  # MySQL init scripts
│   ├── redis/                  # Redis configurations
│   ├── vault/                  # Vault policies
│   └── profiles/               # Profile environment files
│       ├── minimal.env
│       ├── standard.env
│       ├── full.env
│       └── reference.env
├── scripts/                     # Utility scripts
│   ├── vault-bootstrap.sh
│   ├── generate-certificates.sh
│   └── requirements.txt        # Python dependencies
├── backups/                     # Database backups
│   └── YYYYMMDD_HHMMSS/
├── docs/                        # Documentation (62,000+ lines)
├── tests/                       # Test suite (433+ tests)
└── reference-apps/              # API implementations
```

---

## 🔧 Troubleshooting Quick Fixes

### Vault is Sealed

```bash
# Check status
./devstack vault-status

# Unseal
./devstack vault-unseal

# Restart services that depend on Vault
./devstack restart
```

### Service Won't Start

```bash
# Check logs
./devstack logs <service>

# Check health
./devstack health

# Restart specific service
docker compose restart <service>

# Nuclear option: restart everything
./devstack restart
```

### Redis Cluster Not Working

```bash
# Check cluster status
redis-cli -h localhost -p 6379 cluster info
redis-cli -h localhost -p 6379 cluster nodes

# Reinitialize (WARNING: destroys data)
docker compose down
docker volume rm devstack-core_redis_{1,2,3}_data
./devstack start --profile standard
./devstack redis-cluster-init
```

### Can't Connect to Database

```bash
# Check service is running
docker ps | grep postgres

# Check credentials
./devstack vault-show-password postgres

# Test connection
./devstack shell postgres
# Inside container:
psql -U $POSTGRES_USER -d $POSTGRES_DB
```

### Colima VM Issues

```bash
# Check Colima status
colima status

# Get VM IP
./devstack ip

# Restart Colima
colima stop
colima start --cpu 4 --memory 8 --disk 60

# Nuclear option: reset VM (DESTRUCTIVE)
./devstack backup  # BACKUP FIRST!
./devstack reset
```

### Python Dependencies Missing

```bash
# Install dependencies
cd ~/devstack-core
uv venv
uv pip install -r scripts/requirements.txt

# Verify
./devstack --version
```

---

## 📡 Network Information

### Network Architecture (4-Tier)

| Network | Subnet | Gateway | Services |
|---------|--------|---------|----------|
| **vault-network** | 172.20.1.0/24 | 172.20.1.1 | Vault |
| **data-network** | 172.20.2.0/24 | 172.20.2.1 | PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ |
| **app-network** | 172.20.3.0/24 | 172.20.3.1 | Forgejo, Reference APIs |
| **observability-network** | 172.20.4.0/24 | 172.20.4.1 | Prometheus, Grafana, Loki, Vector |

### Static IP Assignments

| Service | IP Address | Network |
|---------|------------|---------|
| **vault** | 172.20.1.10 | vault-network |
| **postgres** | 172.20.2.10 | data-network |
| **pgbouncer** | 172.20.2.11 | data-network |
| **mysql** | 172.20.2.12 | data-network |
| **redis-1** | 172.20.2.13 | data-network |
| **redis-2** | 172.20.2.14 | data-network |
| **redis-3** | 172.20.2.15 | data-network |
| **rabbitmq** | 172.20.2.16 | data-network |
| **mongodb** | 172.20.2.17 | data-network |
| **forgejo** | 172.20.3.10 | app-network |
| **reference-api** | 172.20.3.20 | app-network |
| **prometheus** | 172.20.4.10 | observability-network |
| **grafana** | 172.20.4.11 | observability-network |

---

## 🧪 Testing

### Run All Tests

```bash
# Complete test suite (433+ tests)
./tests/run-all-tests.sh

# Individual test categories
./tests/test-vault.sh
./tests/test-postgres.sh
./tests/test-redis.sh
./tests/test-redis-cluster.sh
./tests/test-forgejo.sh

# Python unit tests (FastAPI)
docker exec dev-reference-api pytest tests/ -v

# Parity tests (across all APIs)
cd reference-apps/shared/test-suite && uv run pytest -v
```

### Validation

```bash
# Makefile validation
make validate          # All checks
make test              # Shared test suite
make sync-check        # API synchronization

# CI/CD validation
./scripts/validate-cicd.sh
```

---

## 📚 Documentation Links

### Quick Access

- **Full Docs:** `docs/README.md`
- **Installation:** `docs/INSTALLATION.md`
- **Services:** `docs/SERVICES.md`
- **Profiles:** `docs/SERVICE_PROFILES.md`
- **Python CLI:** `docs/PYTHON_CLI.md`
- **Vault:** `docs/VAULT.md`
- **Network:** `docs/NETWORK_SEGMENTATION.md`
- **Troubleshooting:** `docs/TROUBLESHOOTING.md`
- **Security:** `docs/SECURITY_ASSESSMENT.md`
- **Testing:** `docs/TESTING_APPROACH.md`

### Reference Apps

- **Overview:** `reference-apps/README.md`
- **OpenAPI Spec:** `reference-apps/shared/openapi.yaml`
- **API Patterns:** `reference-apps/API_PATTERNS.md`

---

## 💡 Pro Tips

### Speed Up Daily Start

```bash
# Use minimal profile for quick testing
./devstack start --profile minimal

# Only start what you need
./devstack start --profile standard
# Skip: --profile reference (if not needed)
```

### Monitor Resources

```bash
# Watch resource usage
docker stats

# Colima resource limits
colima status | grep -E "cpu|memory|disk"
```

### Backup Before Experiments

```bash
# Always backup before:
# - Upgrading versions
# - Testing new configurations
# - Making database schema changes

./devstack backup
```

### Use Shell Aliases

```bash
# Add to ~/.zshrc or ~/.bashrc
alias ds='./devstack'
alias dss='./devstack status'
alias dsh='./devstack health'
alias dsl='./devstack logs'

# Usage:
ds start --profile standard
dss
dsh
dsl postgres
```

### Environment Variables

```bash
# Load all Vault passwords into environment
source scripts/load-vault-env.sh

# Now use them directly
echo $POSTGRES_PASSWORD
echo $REDIS_PASSWORD
echo $MYSQL_PASSWORD
```

---

## 🆘 Emergency Recovery

### Complete Corruption

```bash
# 1. Backup what you can
./devstack backup

# 2. Reset environment
./devstack reset

# 3. Start fresh
./devstack start --profile standard
./devstack vault-init
./devstack vault-bootstrap
./devstack redis-cluster-init

# 4. Restore data (if you backed up)
./devstack restore 20250118_143022
./devstack restart
```

### Vault Data Loss

**⚠️ CRITICAL:** If you lose `~/.config/vault/keys.json` and `~/.config/vault/root-token`:
- You CANNOT unseal Vault
- You CANNOT access any stored secrets
- You MUST reset and start over
- This is why **BACKUP IS CRITICAL**

```bash
# Backup Vault data regularly
cp -r ~/.config/vault ~/vault-backup-$(date +%Y%m%d)
```

---

## 📋 Checklist: Daily Operations

### Morning Routine

- [ ] `./devstack start --profile standard`
- [ ] `./devstack health`
- [ ] Check Grafana dashboards (if using full profile)

### During Development

- [ ] `./devstack logs <service>` (as needed)
- [ ] `./devstack vault-show-password <service>` (for credentials)
- [ ] Monitor resource usage: `docker stats`

### End of Day

- [ ] `./devstack backup` (optional, before major changes)
- [ ] `./devstack stop`

### Weekly Maintenance

- [ ] Review logs for errors: `./devstack logs`
- [ ] Check disk space: `df -h`
- [ ] Backup critical data: `./devstack backup`
- [ ] Backup Vault data: `cp -r ~/.config/vault ~/vault-backup-$(date +%Y%m%d)`

---

## 🔗 Quick Links

- **GitHub:** https://github.com/NormB/devstack-core
- **Issues:** https://github.com/NormB/devstack-core/issues
- **Vault Docs:** https://www.vaultproject.io/docs
- **Docker Compose:** https://docs.docker.com/compose/
- **Colima:** https://github.com/abiosoft/colima

---

**Last Updated:** 2025-01-18
**Version:** 1.3.0

**Need More Help?** See `docs/README.md` for complete documentation index.
