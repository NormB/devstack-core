# Learning Paths

Choose a learning path based on your role or goal. Each path provides a structured reading order with the knowledge you'll gain at each step.

---

## Quick Reference

| Your Goal | Start Here | Time |
|-----------|------------|------|
| Get running ASAP | [Just Start Developing](#path-1-just-start-developing) | 15 min |
| Understand the system | [Understanding DevStack](#path-2-understanding-devstack) | 1 hour |
| Connect my app | [Application Developer](#path-3-application-developer) | 30 min |
| Learn Vault secrets | [Vault Deep Dive](#path-4-vault-deep-dive) | 45 min |
| Set up monitoring | [Observability](#path-5-observability) | 30 min |
| Debug issues | [Troubleshooting](#path-6-troubleshooting) | As needed |

---

## Path 1: Just Start Developing

**Goal:** Get DevStack running and connect your application as quickly as possible.

**Time:** 15 minutes

### Step 1: Install and Start (5 min)
📖 Read: [Getting Started](GETTING_STARTED.md)

**You'll learn:**
- How to install prerequisites
- How to start all services
- How to verify everything works

### Step 2: Get Credentials (2 min)
📖 Read: [Getting Started - Connect Your Application](GETTING_STARTED.md#connect-your-application)

**You'll learn:**
- How to get database passwords
- Connection strings for each database

### Step 3: Daily Commands (3 min)
📖 Read: [Quick Reference](QUICK_REFERENCE.md) (first page only)

**You'll learn:**
- Start/stop commands
- How to view logs
- Basic troubleshooting

### Step 4: Keep This Open
📖 Bookmark: [CLI Reference](CLI_REFERENCE.md)

**For quick command lookup while developing.**

---

## Path 2: Understanding DevStack

**Goal:** Understand how DevStack works before using it.

**Time:** 1 hour

### Step 1: What It Is (10 min)
📖 Read: [Getting Started](GETTING_STARTED.md)
📖 Read: [Glossary](GLOSSARY.md) - scan key terms

**You'll learn:**
- What DevStack provides
- Key terminology (Vault, AppRole, Colima)
- High-level architecture

### Step 2: How It's Built (15 min)
📖 Read: [Architecture - Visual Overview](ARCHITECTURE.md#visual-architecture-overview)
📖 Read: [Architecture - Network Architecture](ARCHITECTURE.md#network-architecture)

**You'll learn:**
- Service layout and dependencies
- Network segmentation (4 networks)
- How services communicate

### Step 3: How Secrets Work (15 min)
📖 Read: [Architecture - Security Architecture](ARCHITECTURE.md#security-architecture)
📖 Read: [Glossary - Vault Concepts](GLOSSARY.md#vault-concepts)

**You'll learn:**
- Why Vault instead of .env files
- How services get credentials
- Certificate management (PKI)

### Step 4: Service Profiles (10 min)
📖 Read: [Service Profiles](SERVICE_PROFILES.md)

**You'll learn:**
- Different profile options
- Resource requirements
- When to use each profile

### Step 5: Hands-On (10 min)
📖 Follow: [Getting Started - Quick Start](GETTING_STARTED.md#quick-start-5-minutes)

**You'll do:**
- Install and start DevStack
- Initialize Vault
- Verify services are healthy

---

## Path 3: Application Developer

**Goal:** Connect your application to DevStack services.

**Time:** 30 minutes

### Step 1: Get Running (10 min)
📖 Follow: [Getting Started - Quick Start](GETTING_STARTED.md#quick-start-5-minutes)

**You'll do:**
- Start DevStack
- Initialize Vault

### Step 2: Get Credentials (5 min)
📖 Read: [Getting Started - Get Database Credentials](GETTING_STARTED.md#get-database-credentials)

**You'll learn:**
- How to get passwords from Vault
- How to load credentials into environment

**Commands you'll use:**
```bash
./devstack vault-show-password postgres
source scripts/load-vault-env.sh
```

### Step 3: Connection Examples (10 min)
📖 Read: [Use Cases](USE_CASES.md)

**You'll learn:**
- Connection strings for each language
- Code examples for Python, Go, Node.js, Rust
- How to test connections

### Step 4: Reference Implementations (5 min)
📖 Explore: `reference-apps/` directory

**You'll see:**
- Working examples in 5 languages
- Best practices for Vault integration
- Health check implementations

**Explore in browser:**
- http://localhost:8000/docs (FastAPI docs)
- http://localhost:8000/health/all (Health check)

---

## Path 4: Vault Deep Dive

**Goal:** Understand how HashiCorp Vault manages secrets and certificates.

**Time:** 45 minutes

### Step 1: Vault Basics (10 min)
📖 Read: [Glossary - Vault Concepts](GLOSSARY.md#vault-concepts)

**You'll learn:**
- What Vault is and why it's used
- Key concepts: unsealing, tokens, secrets engines
- AppRole authentication

### Step 2: Vault Architecture (15 min)
📖 Read: [Vault](VAULT.md)

**You'll learn:**
- PKI hierarchy (Root CA → Intermediate CA → Certs)
- Secrets engine structure
- How credentials are stored

### Step 3: AppRole Deep Dive (10 min)
📖 Read: [Architecture - AppRole Authentication Flow](ARCHITECTURE.md#approle-authentication-flow)

**You'll learn:**
- How services authenticate
- Role and secret IDs
- Token lifecycle

### Step 4: Hands-On Exploration (10 min)
📖 Follow: These commands

```bash
# View Vault status
./devstack vault-status

# Get a password
./devstack vault-show-password postgres

# Access Vault UI
open http://localhost:8200
# Token: cat ~/.config/vault/root-token

# List secrets
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
vault kv list secret/
```

### Step 5: Security Best Practices (Optional)
📖 Read: [Vault Security](VAULT_SECURITY.md)

**You'll learn:**
- Production hardening recommendations
- Policy management
- Audit logging

---

## Path 5: Observability

**Goal:** Set up and use monitoring with Prometheus and Grafana.

**Time:** 30 minutes

### Step 1: Start with Full Profile (5 min)
📖 Follow: These commands

```bash
# Start with observability services
./devstack start --profile full

# Verify observability services are healthy
./devstack health | grep -E "(prometheus|grafana|loki)"
```

### Step 2: Explore Grafana (10 min)
📖 Open: http://localhost:3001

**Login:** admin / admin

**Explore:**
1. **Dashboards** → Browse pre-configured dashboards
2. **Explore** → Query metrics with PromQL
3. **Explore** → Switch to Loki for logs

### Step 3: Understand the Stack (10 min)
📖 Read: [Architecture - Observability Architecture](ARCHITECTURE.md#observability-architecture)

**You'll learn:**
- Metrics flow (services → Prometheus → Grafana)
- Logs flow (containers → Promtail → Loki → Grafana)
- What metrics are available

### Step 4: Query Examples (5 min)
📖 Try in Grafana: These PromQL queries

```promql
# CPU usage by container
rate(container_cpu_usage_seconds_total[5m])

# Memory usage
container_memory_usage_bytes

# HTTP request rate (FastAPI)
rate(http_requests_total[5m])

# Redis operations
rate(redis_commands_total[5m])
```

### Step 5: Log Exploration
📖 Try in Grafana: Explore → Loki

```logql
# All PostgreSQL logs
{container="dev-postgres"}

# Errors only
{container="dev-reference-api"} |= "error"

# JSON log parsing
{container="dev-reference-api"} | json | level="ERROR"
```

---

## Path 6: Troubleshooting

**Goal:** Diagnose and fix common problems.

**Time:** As needed

### Quick Diagnostic Commands

```bash
# Overall status
./devstack health

# Service logs
./devstack logs <service>

# Vault status
./devstack vault-status

# Container status
docker ps -a
```

### Problem-Specific Guides

| Problem | Go To |
|---------|-------|
| Services won't start | [Troubleshooting - Services](TROUBLESHOOTING.md#services-wont-start) |
| Database connection failed | [Troubleshooting - Databases](TROUBLESHOOTING.md#database-issues) |
| Vault is sealed | [Troubleshooting - Vault](TROUBLESHOOTING.md#vault-issues) |
| Container keeps restarting | [Troubleshooting - Containers](TROUBLESHOOTING.md#container-issues) |
| Out of disk space | [Troubleshooting - Resources](TROUBLESHOOTING.md#resource-issues) |

### Visual Troubleshooting Flow

```
Start Here
    │
    ▼
┌─────────────────────────────────┐
│ Run: ./devstack health          │
└─────────────────────────────────┘
    │
    ├─── All healthy? ───▶ Problem is elsewhere
    │
    ▼
┌─────────────────────────────────┐
│ Which service is unhealthy?     │
└─────────────────────────────────┘
    │
    ├─── Vault ───▶ ./devstack vault-status
    │                └─── Sealed? ───▶ ./devstack vault-unseal
    │
    ├─── Database ───▶ ./devstack logs <db>
    │                  └─── Check credentials
    │
    └─── Other ───▶ ./devstack logs <service>
                    └─── Check dependencies
```

---

## Path 7: DevOps / Operations

**Goal:** Manage DevStack in a team environment.

**Time:** 1 hour

### Step 1: Complete Setup Understanding (20 min)
📖 Follow: [Path 2: Understanding DevStack](#path-2-understanding-devstack)

### Step 2: Backup and Recovery (15 min)
📖 Read: [Disaster Recovery](DISASTER_RECOVERY.md)

**You'll learn:**
- Backup procedures
- Restore procedures
- RTO and RPO targets

**Commands:**
```bash
# Backup all databases
./devstack backup

# List backups
./devstack restore

# Restore specific backup
./devstack restore 20250113_143022
```

### Step 3: Certificate Management (10 min)
📖 Read: [TLS Certificate Management](TLS_CERTIFICATE_MANAGEMENT.md)

**You'll learn:**
- Certificate lifecycle
- Renewal procedures
- Monitoring expiration

### Step 4: Performance Tuning (10 min)
📖 Read: [Performance Tuning](PERFORMANCE_TUNING.md)

**You'll learn:**
- Resource allocation
- Colima VM sizing
- Optimization strategies

### Step 5: Upgrade Procedures (5 min)
📖 Read: [Upgrade Guide](UPGRADE_GUIDE.md)

**You'll learn:**
- Version migration steps
- Breaking changes
- Rollback procedures

---

## Path 8: Contributing

**Goal:** Contribute to DevStack Core development.

**Time:** 30 minutes

### Step 1: Development Setup
📖 Follow: [Path 1: Just Start Developing](#path-1-just-start-developing)

### Step 2: Contribution Guidelines
📖 Read: [Contributing](../CONTRIBUTING.md)

**You'll learn:**
- Code style requirements
- PR process
- Testing requirements

### Step 3: Architecture Understanding
📖 Read: [Architecture](ARCHITECTURE.md) (full document)

### Step 4: Testing
📖 Read: [Testing Approach](TESTING_APPROACH.md)

**Commands:**
```bash
# Run all tests
./tests/run-all-tests.sh

# Run specific test
./tests/test-vault.sh

# Run with parallel execution
./tests/run-all-tests.sh --parallel
```

---

## Documentation Index

For complete documentation, see [docs/README.md](README.md).

### By Topic

| Topic | Documents |
|-------|-----------|
| **Getting Started** | [Getting Started](GETTING_STARTED.md), [Installation](INSTALLATION.md) |
| **CLI** | [CLI Reference](CLI_REFERENCE.md), [Quick Reference](QUICK_REFERENCE.md) |
| **Architecture** | [Architecture](ARCHITECTURE.md), [Network Segmentation](NETWORK_SEGMENTATION.md) |
| **Vault** | [Vault](VAULT.md), [Vault Security](VAULT_SECURITY.md) |
| **Databases** | [Services](SERVICES.md), [Redis](REDIS.md) |
| **Monitoring** | [Observability](OBSERVABILITY.md) |
| **Operations** | [Management](MANAGEMENT.md), [Disaster Recovery](DISASTER_RECOVERY.md) |
| **Troubleshooting** | [Troubleshooting](TROUBLESHOOTING.md), [FAQ](FAQ.md) |
| **Reference** | [Glossary](GLOSSARY.md), [Environment Variables](ENVIRONMENT_VARIABLES.md) |

---

## Next Steps After Any Path

1. **Bookmark frequently used docs:**
   - [CLI Reference](CLI_REFERENCE.md)
   - [Quick Reference](QUICK_REFERENCE.md)
   - [Troubleshooting](TROUBLESHOOTING.md)

2. **Join the community:**
   - GitHub Issues for questions
   - PRs for contributions

3. **Keep learning:**
   - Explore reference apps in `reference-apps/`
   - Try different profiles
   - Set up monitoring with full profile
