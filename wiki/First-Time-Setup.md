# First Time Setup

Complete the initial configuration after installation - initialize Vault, bootstrap credentials, and access your services.

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Step 1: Initialize Vault](#step-1-initialize-vault)
- [Step 2: Bootstrap Vault](#step-2-bootstrap-vault)
- [Step 3: Verify Configuration](#step-3-verify-configuration)
- [Step 4: Access Services](#step-4-access-services)
- [Step 5: Test Integrations](#step-5-test-integrations)
- [Backup Critical Files](#backup-critical-files)
- [Troubleshooting](#troubleshooting)
- [Next Steps](#next-steps)

## Overview

After installation, you need to complete **one-time setup** to:
1. Initialize HashiCorp Vault for secrets management
2. Generate credentials for all services
3. Set up PKI (Public Key Infrastructure) for TLS certificates
4. Verify everything is working correctly

**Time required:** 5-10 minutes

**⚠️ Important:** These steps should be done **once** per installation. If you reset the environment, you'll need to repeat them.

## Prerequisites

Before starting this guide:

✅ Completed [Installation](Installation)
✅ All services are running (`./devstack.sh status`)
✅ Vault is unsealed (check with `./devstack.sh vault-status`)

**Verify services are running:**
```bash
cd ~/devstack-core
./devstack.sh status

# All services should show STATE: running
```

## Step 1: Initialize Vault

Vault initialization creates the master keys needed to unseal Vault and access secrets.

### Run Vault Initialization

```bash
./devstack.sh vault-init
```

### Expected Output

```
============================================
  Initializing HashiCorp Vault
============================================

[*] Checking if Vault is already initialized...
[*] Vault is not initialized. Proceeding with initialization...

[*] Initializing Vault with 5 key shares and threshold of 3...

Unseal Key 1: abc123...
Unseal Key 2: def456...
Unseal Key 3: ghi789...
Unseal Key 4: jkl012...
Unseal Key 5: mno345...

Initial Root Token: hvs.1234567890abcdef

[✓] Vault initialized successfully!

[*] Saving unseal keys to ~/.config/vault/keys.json
[*] Saving root token to ~/.config/vault/root-token

[*] Auto-unsealing Vault...
Key                    Value
---                    -----
Seal Type              shamir
Initialized            true
Sealed                 false
Total Shares           5
Threshold              3
Unseal Progress        3/3
Unseal Nonce           n/a
Version                1.18.0

[✓] Vault is now unsealed and ready to use!

⚠️  CRITICAL: Backup ~/.config/vault/ directory!
    Without these files, Vault data cannot be recovered.
```

### What Just Happened?

1. **Vault was initialized** with Shamir secret sharing
   - 5 unseal keys generated
   - 3 keys required to unseal (threshold)

2. **Files created:**
   - `~/.config/vault/keys.json` - Contains all 5 unseal keys
   - `~/.config/vault/root-token` - Contains the root token

3. **Vault automatically unsealed** using stored keys

### Verify Vault Status

```bash
./devstack.sh vault-status
```

**Expected output:**
```
Vault Status:
  Initialized: true
  Sealed: false
  Seal Type: shamir
  Threshold: 3
  Total Shares: 5
  Version: 1.18.0
```

**✓ Success indicators:**
- `Initialized: true`
- `Sealed: false`

### Troubleshooting Step 1

**Already initialized:**
```
[✓] Vault is already initialized
```
This is normal if re-running the command. Skip to Step 2.

**Vault connection failed:**
```bash
# Check Vault is running
docker compose ps vault

# Restart Vault
docker compose restart vault
sleep 30

# Try again
./devstack.sh vault-init
```

## Step 2: Bootstrap Vault

Bootstrapping sets up PKI infrastructure and generates all service credentials.

### Run Vault Bootstrap

```bash
./devstack.sh vault-bootstrap
```

### Expected Output

```
============================================
  Bootstrapping Vault Configuration
============================================

[*] Loading Vault token...
[✓] Vault token loaded from ~/.config/vault/root-token

[*] Enabling secrets engine at 'secret/'...
[✓] KV secrets engine enabled

[*] Setting up PKI (Public Key Infrastructure)...

Step 1/6: Enabling PKI secrets engine at 'pki/'...
[✓] Root CA PKI engine enabled

Step 2/6: Generating Root CA certificate...
[✓] Root CA generated (10-year validity)
    Common Name: DevStack Core Root CA
    Validity: 87600h (10 years)

Step 3/6: Enabling Intermediate CA at 'pki_int/'...
[✓] Intermediate CA PKI engine enabled

Step 4/6: Generating Intermediate CA...
[✓] Intermediate CA generated (5-year validity)
    Common Name: DevStack Core Intermediate CA
    Validity: 43800h (5 years)

Step 5/6: Setting up certificate roles...
[✓] Created role: postgres-role
[✓] Created role: mysql-role
[✓] Created role: mongodb-role
[✓] Created role: redis-role
[✓] Created role: rabbitmq-role
[✓] Created role: forgejo-role

Step 6/6: Exporting CA certificates...
[✓] Root CA exported to ~/.config/vault/ca/ca.pem
[✓] CA chain exported to ~/.config/vault/ca/ca-chain.pem

[*] Generating service credentials...

[✓] PostgreSQL credentials stored at secret/postgres
    Username: dev_admin
    Database: dev_database
    Password: [generated]

[✓] MySQL credentials stored at secret/mysql
    Username: dev_admin
    Database: dev_database
    Root Password: [generated]
    User Password: [generated]

[✓] MongoDB credentials stored at secret/mongodb
    Username: dev_admin
    Database: dev_database
    Password: [generated]

[✓] Redis credentials stored at secret/redis-1
    Password: [generated]
    (Shared across all Redis cluster nodes)

[✓] RabbitMQ credentials stored at secret/rabbitmq
    Username: dev_admin
    VHost: dev_vhost
    Password: [generated]

[*] Generating TLS certificates for services...
[✓] PostgreSQL certificate generated
[✓] MySQL certificate generated
[✓] MongoDB certificate generated
[✓] Redis certificates generated (3 nodes)
[✓] RabbitMQ certificate generated

[✓] All certificates exported to ~/.config/vault/certs/

============================================
  Bootstrap Complete!
============================================

Services are now configured with:
  ✓ Auto-generated strong passwords
  ✓ TLS certificates from internal CA
  ✓ Secure credential storage in Vault

To retrieve service passwords:
  ./devstack.sh vault-show-password <service>

Example:
  ./devstack.sh vault-show-password postgres
```

### What Just Happened?

1. **PKI Infrastructure Created:**
   - Root CA (10-year validity)
   - Intermediate CA (5-year validity)
   - Certificate roles for each service

2. **Service Credentials Generated:**
   - PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ
   - Strong random passwords (32+ characters)
   - Stored securely in Vault

3. **TLS Certificates Issued:**
   - One certificate per service
   - Signed by Intermediate CA
   - 1-year validity (renewable)

4. **Files Created:**
   - `~/.config/vault/ca/ca.pem` - Root CA certificate
   - `~/.config/vault/ca/ca-chain.pem` - Full certificate chain
   - `~/.config/vault/certs/<service>/` - Per-service certificates

### Verify Bootstrap Success

```bash
# Check if secrets were created
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# List all secrets
vault kv list secret/

# Expected output:
# Keys
# ----
# mongodb
# mysql
# postgres
# rabbitmq
# redis-1
```

### Troubleshooting Step 2

**Permission denied:**
```bash
# Ensure token is set
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Verify token is valid
vault token lookup

# Try bootstrap again
./devstack.sh vault-bootstrap
```

**PKI already exists:**
```
Error: path is already in use at pki/
```
This is normal if re-running bootstrap. The command is idempotent for secrets but PKI engines persist. If you need a complete reset, see [Common Issues](Common-Issues#vault-bootstrap-fails).

## Step 3: Verify Configuration

### Check All Services Are Healthy

```bash
./devstack.sh health
```

**Expected output:**
```
Health Check Results:
====================================

✓ Vault: healthy
  - Initialized: true
  - Sealed: false
  - Version: 1.18.0

✓ PostgreSQL: healthy
  - Accepting connections
  - Database: dev_database

✓ MySQL: healthy
  - Server version: 8.0.40

✓ MongoDB: healthy
  - Server version: 7.0.x

✓ Redis Cluster: healthy
  - Node 1: master (5461 slots)
  - Node 2: master (5461 slots)
  - Node 3: master (5462 slots)
  - Cluster state: ok

✓ RabbitMQ: healthy
  - Node status: running
  - Virtual hosts: 1

✓ Forgejo: healthy
  - Version: 8.x.x

✓ Reference API: healthy
  - FastAPI application

====================================
✓ All services healthy!
```

### Restart Services to Pick Up Credentials

Some services may need restarting to fetch credentials from Vault:

```bash
./devstack.sh restart
```

**Wait for services to become healthy:**
```bash
# Check status every 10 seconds
watch -n 10 './devstack.sh status'

# Press Ctrl+C when all services show "healthy"
```

## Step 4: Access Services

### Web UIs

Open these URLs in your browser:

| Service | URL | Credentials |
|---------|-----|-------------|
| **Vault UI** | http://localhost:8200/ui | Token: `cat ~/.config/vault/root-token` |
| **Forgejo (Git)** | http://localhost:3000 | Setup wizard on first visit |
| **RabbitMQ Management** | http://localhost:15672 | Get from Vault: `vault-show-password rabbitmq` |
| **Grafana** | http://localhost:3001 | admin / admin (change on first login) |
| **Prometheus** | http://localhost:9090 | No authentication |
| **FastAPI Docs** | http://localhost:8000/docs | No authentication |

### Database Connections

**PostgreSQL:**
```bash
# Get password
./devstack.sh vault-show-password postgres

# Connect
psql postgresql://dev_admin@localhost:5432/dev_database
# When prompted, paste the password
```

**MySQL:**
```bash
# Get password
./devstack.sh vault-show-password mysql

# Connect
mysql -h 127.0.0.1 -u dev_admin -p dev_database
# When prompted, paste the password
```

**MongoDB:**
```bash
# Get password
./devstack.sh vault-show-password mongodb

# Build connection string
echo "mongodb://dev_admin:<password>@localhost:27017/dev_database"
# Replace <password> with actual password

# Connect
mongosh "mongodb://dev_admin:<password>@localhost:27017/dev_database"
```

**Redis:**
```bash
# Get password
REDIS_PASSWORD=$(vault kv get -field=password secret/redis-1)

# Connect
redis-cli -a "$REDIS_PASSWORD"

# Test
redis-1> PING
PONG
```

### Retrieve Any Service Password

```bash
# PostgreSQL
./devstack.sh vault-show-password postgres

# MySQL
./devstack.sh vault-show-password mysql

# MongoDB
./devstack.sh vault-show-password mongodb

# Redis
./devstack.sh vault-show-password redis

# RabbitMQ
./devstack.sh vault-show-password rabbitmq
```

## Step 5: Test Integrations

### Test Reference API

The reference API demonstrates integration with all services:

```bash
# Health check (all services)
curl http://localhost:8000/health/all | jq

# Test Vault integration
curl http://localhost:8000/vault/info | jq

# Test PostgreSQL
curl http://localhost:8000/database/postgres/test | jq

# Test Redis cluster
curl http://localhost:8000/redis/cluster/info | jq

# Test RabbitMQ
curl -X POST http://localhost:8000/messaging/publish \
  -H "Content-Type: application/json" \
  -d '{"queue": "test", "message": "Hello"}' | jq
```

**Expected:** All endpoints return success responses with status 200.

### Interactive API Documentation

Open http://localhost:8000/docs in your browser to:
- Browse all available endpoints
- Try API calls directly from browser
- See request/response schemas
- Test service integrations

## Backup Critical Files

**⚠️ CRITICAL:** Backup these files immediately. Without them, Vault data cannot be recovered:

```bash
# Create backup directory
mkdir -p ~/vault-backups

# Backup with timestamp
cp -r ~/.config/vault ~/vault-backups/vault-backup-$(date +%Y%m%d-%H%M%S)

# Verify backup
ls -la ~/vault-backups/

# Expected files in backup:
# - keys.json (unseal keys)
# - root-token (Vault root token)
# - ca/ (CA certificates)
# - certs/ (service certificates)
```

**Store backup securely:**
- External drive
- Encrypted cloud storage
- Password manager (for keys and token)

**Never:**
- Commit to Git
- Store in plain text in shared locations
- Email or message unencrypted

## Troubleshooting

### Services Can't Connect to Vault

**Symptom:** Services logs show "connection refused" to Vault

**Solution:**
```bash
# Verify Vault is unsealed
./devstack.sh vault-status

# If sealed, restart Vault (auto-unseals)
docker compose restart vault
sleep 30

# Restart dependent services
./devstack.sh restart
```

### Password Authentication Fails

**Symptom:** Database connection fails with "password authentication failed"

**Solution:**
```bash
# Verify secret exists in Vault
vault kv get secret/postgres

# Restart the database to re-fetch credentials
docker compose restart postgres

# Wait for healthy status
docker compose ps postgres
```

### Certificate Issues

**Symptom:** TLS connection errors

**Solution:**
```bash
# Verify certificates were generated
ls -la ~/.config/vault/certs/postgres/

# Expected files: cert.pem, key.pem, ca.pem

# Regenerate certificates if missing
./scripts/generate-certificates.sh

# Restart services to pick up new certificates
./devstack.sh restart
```

### Forgot to Backup Vault Keys

**⚠️ If Vault gets sealed and you don't have keys:**

Vault data is **permanently unrecoverable**. You must:
1. Reset everything: `./devstack.sh reset`
2. Start over from [Installation](Installation)

**Prevention:** Backup now!

## Next Steps

### What You've Accomplished

✅ Initialized Vault with master keys
✅ Created PKI infrastructure (Root CA + Intermediate CA)
✅ Generated credentials for all services
✅ Issued TLS certificates
✅ Verified all services are healthy
✅ Backed up critical Vault files

### Continue Learning

1. **[Quick Start Guide](Quick-Start-Guide)** - Learn daily operations
2. **[Management Commands](Management-Commands)** - Explore available commands
3. **[Reference Applications](Reference-Applications)** - Explore API examples
4. **[Vault Integration](Vault-Integration)** - Deep dive into Vault usage
5. **[Testing Guide](Testing-Guide)** - Run the test suites

### Daily Usage

Now that setup is complete, normal workflow is:

```bash
# Start everything (typically once per day)
./devstack.sh start

# Check status
./devstack.sh status

# View logs if needed
./devstack.sh logs <service>

# Stop everything (end of day)
./devstack.sh stop
```

**Services auto-start with credentials** - no need to re-run vault-init or vault-bootstrap unless you reset the environment.

## Getting Help

- **[Common Issues](Common-Issues)** - Troubleshooting guide
- **[Management Commands](Management-Commands)** - Command reference
- **[Architecture Overview](Architecture-Overview)** - How it all works
- **GitHub Issues** - [Report problems](https://github.com/NormB/devstack-core/issues)

---

**Congratulations!** 🎉 Your DevStack Core environment is fully configured and ready to use.
