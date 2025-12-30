# Migration Guide

Step-by-step instructions for migrating from legacy configurations to DevStack Core v1.3.0+, including AppRole authentication and TLS encryption.

**Version:** 1.1 | **Last Updated:** 2025-12-30

> **Related Documentation:**
> - For version upgrades and service upgrades, see [UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)
> - For disaster recovery procedures, see [DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md)
> - For detailed rollback procedures, see [ROLLBACK_PROCEDURES.md](./ROLLBACK_PROCEDURES.md)

---

## Table of Contents

1. [Introduction](#introduction)
2. [Prerequisites](#prerequisites)
3. [Migration Timeline](#migration-timeline)
4. [Root Token → AppRole Migration](#root-token--approle-migration)
5. [HTTP → HTTPS (TLS) Migration](#http--https-tls-migration)
6. [Troubleshooting Guide](#troubleshooting-guide)
7. [Post-Migration Validation](#post-migration-validation)
8. [Rollback Procedures](#rollback-procedures)
9. [FAQ](#faq)

---

## Introduction

This guide provides step-by-step instructions for migrating existing DevStack Core installations to use:

1. **AppRole Authentication** - Replacing root token-based Vault access with role-based authentication
2. **TLS Encryption** - Enabling dual-mode TLS for all data services

### What's Changing?

**Security Enhancements (Phase 1):**
- Vault authentication: Root tokens → AppRole (role_id + secret_id)
- Network security: Plaintext → Dual-mode TLS (accepts both HTTP and HTTPS)
- Certificate management: Two-tier PKI (Root CA → Intermediate CA → Service Certs)
- Network segmentation: 4-tier isolation (vault/data/app/observability)

**Operational Improvements (Phase 2):**
- Startup: Manual → Health-check driven automatic startup
- Backup: Manual → Automated with validation
- Recovery: Undefined → 10-12 minute RTO with documented procedures
- Monitoring: Basic → Comprehensive alerting via Prometheus/Grafana

**Performance Optimizations (Phase 3):**
- PostgreSQL: +41% throughput improvement
- MySQL: +37% throughput improvement
- MongoDB: +19% throughput improvement
- Redis: 512MB memory limit, <3s failover time
- Testing: 50+ tests → 571+ comprehensive tests

**Phase 4 Completion:**
- ✅ 100% AppRole adoption (16/16 services)
- ✅ All infrastructure services migrated
- ✅ All reference applications migrated
- ✅ Comprehensive test coverage (32 AppRole tests, 24 TLS tests)

---

## Migration Scenarios

### Scenario 1: Fresh Install (Recommended)
**Who:** New users installing DevStack Core for the first time
**Path:** Follow standard installation guide - AppRole enabled by default
**Doc:** [INSTALLATION.md](./INSTALLATION.md)

### Scenario 2: Pre-Phase 1 → Current
**Who:** Users with DevStack Core installed before November 2025
**Path:** Migrate from root token to AppRole authentication
**Complexity:** Medium (2-3 hours)
**Downtime:** 10-15 minutes

### Scenario 3: Adding TLS to Existing Setup
**Who:** Users with current setup wanting to enable TLS
**Path:** Generate certificates and enable TLS dual-mode
**Complexity:** Low (30 minutes)
**Downtime:** 5 minutes

### Scenario 4: Migrating Custom Service to AppRole
**Who:** Developers adding new services
**Path:** Create AppRole, policy, and init script
**Complexity:** Medium (1-2 hours)
**Downtime:** None (new service)

---

## Pre-Phase 1 → Current (AppRole + TLS)

### Prerequisites

**Before starting:**
1. ✅ Backup your data: `./devstack backup`
2. ✅ Backup Vault configuration: `cp -r ~/.config/vault ~/vault-backup-$(date +%Y%m%d)`
3. ✅ Note current service versions
4. ✅ Have at least 1 hour for migration
5. ✅ Test rollback procedure (optional but recommended)

**System Requirements:**
- DevStack Core v1.2.0 or later
- Vault accessible and unsealed
- All services healthy before migration

### Step 1: Update Repository

```bash
cd ~/devstack-core
git fetch origin
git checkout main
git pull origin main

# Review changes
git log --oneline --since="2025-11-01"
```

**What changed:**
- AppRole authentication for 7 core services
- TLS certificate generation automation
- Service profiles (minimal/standard/full)
- Performance improvements (+41% PostgreSQL, +37% MySQL, +19% MongoDB)
- 571+ test suites

### Step 2: Stop All Services

```bash
# Graceful shutdown
./devstack stop

# Verify all stopped
docker ps
# Should show only Vault (or empty)
```

### Step 3: Update Configuration Files

**3.1: Update docker-compose.yml**
```bash
# Backup current config
cp docker-compose.yml docker-compose.yml.backup

# New version already includes AppRole entrypoints
# Verify PostgreSQL uses init-approle.sh:
grep "entrypoint.*init-approle" docker-compose.yml | head -1
# Should show: entrypoint: ["/init/init-approle.sh"]
```

**3.2: Verify .env file**
```bash
# Your .env should already have VAULT_TOKEN
cat .env | grep VAULT_TOKEN
# VAULT_TOKEN=hvs.xxxxx (or empty, will read from ~/.config/vault/root-token)
```

### Step 4: Enable AppRole in Vault

```bash
# Ensure Vault is running
docker compose up -d vault
sleep 10

# Check Vault health
curl http://localhost:8200/v1/sys/health

# Run vault-bootstrap (THIS IS THE KEY STEP)
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
./devstack vault-bootstrap
```

**Expected output:**
```
============================================
  Bootstrapping Vault with Service Credentials
============================================

[*] Enabling AppRole auth method...
[✓] AppRole enabled

[*] Creating policies for services...
[✓] Policy created: postgres-policy
[✓] Policy created: mysql-policy
[✓] Policy created: mongodb-policy
[✓] Policy created: redis-policy
[✓] Policy created: rabbitmq-policy
[✓] Policy created: forgejo-policy
[✓] Policy created: reference-api-policy

[*] Creating AppRole for each service...
[✓] AppRole created: postgres
[✓] AppRole created: mysql
[✓] AppRole created: mongodb
[✓] AppRole created: redis
[✓] AppRole created: rabbitmq
[✓] AppRole created: forgejo
[✓] AppRole created: reference-api

[*] Generating role-id and secret-id for each service...
[✓] Credentials saved: ~/.config/vault/approles/postgres/
[✓] Credentials saved: ~/.config/vault/approles/mysql/
... (etc)

[✓] Vault AppRole bootstrap complete!
```

### Step 5: Verify AppRole Credentials

```bash
# Check all AppRole directories created
ls -la ~/.config/vault/approles/
# Should show: postgres, mysql, mongodb, redis, rabbitmq, forgejo, reference-api, management

# Verify credentials for one service
cat ~/.config/vault/approles/postgres/role-id
# Should show: UUID like abc123-def456-...

# Test AppRole authentication
ROLE_ID=$(cat ~/.config/vault/approles/postgres/role-id)
SECRET_ID=$(cat ~/.config/vault/approles/postgres/secret-id)

curl -X POST http://localhost:8200/v1/auth/approle/login \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" | jq
# Should return: {"auth":{"client_token":"hvs.CAESIE..."}}
```

### Step 6: Restart Services with AppRole

```bash
# Start with standard profile (recommended)
./devstack start --profile standard

# Services will now authenticate via AppRole!
# Watch logs to see AppRole authentication:
docker compose logs postgres 2>&1 | grep -i approle
# Should show: "Successfully authenticated to Vault using AppRole"
```

### Step 7: Verify Migration Success

**7.1: Check all core services are using AppRole**
```bash
# These services should have NO "VAULT_TOKEN" in environment
docker inspect dev-postgres | grep -i VAULT_TOKEN
# Should return nothing (empty)

# Instead, they should have VAULT_APPROLE_DIR
docker inspect dev-postgres | grep VAULT_APPROLE_DIR
# Should show: /vault-approles/postgres
```

**7.2: Run AppRole security tests**
```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
./tests/test-approle-security.sh
```

**Expected results:**
```
============================================
  Testing AppRole Authentication and Security
============================================
PASS: Vault is accessible
PASS: AppRole auth method is enabled
PASS: Invalid role_id rejected
PASS: Invalid secret_id rejected
PASS: Valid credentials rejected without secret_id
PASS: Valid credentials rejected without role_id
PASS: PostgreSQL AppRole authentication successful
... (32 tests total)

============================================
  AppRole Security Tests: 32/32 passed (100%)
============================================
```

**7.3: Test database connectivity**
```bash
# PostgreSQL
docker exec dev-postgres psql -U devuser -d devdb -c "SELECT version();"
# Should show PostgreSQL version

# MySQL
docker exec dev-mysql mysql -u devuser -p$(./devstack vault-show-password mysql) -e "SELECT VERSION();"
# Should show MySQL version
```

### Step 8: Enable TLS (Optional)

```bash
# Generate TLS certificates via Vault PKI
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
./scripts/generate-certificates.sh

# Certificates saved to ~/.config/vault/certs/
ls -la ~/.config/vault/certs/
# Should show: postgres, mysql, mongodb, redis-1, redis-2, redis-3, rabbitmq, forgejo, reference-api

# Certificates are already mounted in docker-compose.yml
# Services will use them automatically

# Restart services to pick up certificates
docker compose restart postgres mysql mongodb redis-1 redis-2 redis-3 rabbitmq
```

**Verify TLS enabled:**
```bash
# PostgreSQL SSL check
export PGPASSWORD=$(./devstack vault-show-password postgres)
docker exec dev-postgres psql -U devuser -d devdb -c "SHOW ssl;"
# Should show: on

# MySQL SSL check
docker exec dev-mysql mysql -u root -p$(./devstack vault-show-password mysql | grep root_password) \
  -e "SHOW VARIABLES LIKE 'have_ssl';"
# Should show: YES
```

### Step 9: Update Backup Configuration

```bash
# New backup system includes AppRole credentials
./devstack backup

# Verify backup includes AppRole
tar -tzf ~/.config/vault/backups/vault-backup-*.tar.gz | grep approles
# Should show: approles/postgres/role-id, approles/postgres/secret-id, etc.
```

### Step 10: Clean Up Old Configuration

```bash
# Remove backup if everything works
rm docker-compose.yml.backup

# Optional: Remove old .env variables (if not needed)
# Keep VAULT_TOKEN for management operations
```

---

## Enabling AppRole for Your Service

**Use case:** Adding AppRole authentication to PGBouncer, reference apps, or custom services

### Prerequisites
- Service currently uses `VAULT_TOKEN` environment variable
- Service has init script that fetches credentials from Vault
- Vault is accessible from service container

### Step-by-Step Guide

**1. Create Vault Policy**

```bash
# Create policy file: configs/vault/policies/myservice-policy.hcl
cat > configs/vault/policies/myservice-policy.hcl <<'EOF'
# Policy for myservice
path "secret/data/myservice" {
  capabilities = ["read"]
}
EOF

# Write policy to Vault
vault policy write myservice-policy configs/vault/policies/myservice-policy.hcl
```

**2. Create AppRole**

```bash
# Create AppRole with policy
vault write auth/approle/role/myservice \
  token_ttl=1h \
  token_max_ttl=4h \
  policies=myservice-policy

# Generate role-id and secret-id
mkdir -p ~/.config/vault/approles/myservice

vault read -field=role_id auth/approle/role/myservice/role-id > \
  ~/.config/vault/approles/myservice/role-id

vault write -field=secret_id -f auth/approle/role/myservice/secret-id > \
  ~/.config/vault/approles/myservice/secret-id

# Set permissions
chmod 600 ~/.config/vault/approles/myservice/secret-id
chmod 644 ~/.config/vault/approles/myservice/role-id
```

**3. Create init-approle.sh Script**

```bash
# Copy template from existing service
cp configs/postgres/scripts/init-approle.sh configs/myservice/scripts/init-approle.sh

# Modify for your service (change SERVICE_NAME, paths, etc.)
nano configs/myservice/scripts/init-approle.sh

# Make executable
chmod +x configs/myservice/scripts/init-approle.sh
```

**4. Update docker-compose.yml**

```yaml
myservice:
  # Change entrypoint from init.sh to init-approle.sh
  entrypoint: ["/init/init-approle.sh"]

  environment:
    VAULT_ADDR: ${VAULT_ADDR:-http://vault:8200}
    VAULT_APPROLE_DIR: /vault-approles/myservice
    # Remove VAULT_TOKEN environment variable

  volumes:
    - ./configs/myservice/scripts/init-approle.sh:/init/init-approle.sh:ro
    - ${HOME}/.config/vault/approles/myservice:/vault-approles/myservice:ro

  networks:
    vault-network:  # Ensure service can reach Vault
    # ... other networks
```

**5. Test AppRole Authentication**

```bash
# Restart service
docker compose restart myservice

# Check logs for successful AppRole auth
docker compose logs myservice | grep -i approle
# Should show: "Successfully authenticated to Vault using AppRole"

# Verify service started correctly
docker compose ps myservice
# Should show: Up (healthy)
```

---

## Enabling TLS/SSL

### Quick Enable (Dual-Mode)

```bash
# 1. Generate certificates
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
./scripts/generate-certificates.sh

# 2. Certificates automatically mounted (already in docker-compose.yml)
# 3. Restart services
docker compose restart postgres mysql mongodb redis-1 redis-2 redis-3 rabbitmq

# 4. Verify TLS enabled
docker exec dev-postgres psql -U devuser -d devdb -c "SHOW ssl;"
# Should show: on
```

**Note:** Dual-mode means services accept BOTH TLS and non-TLS connections.

### TLS-Only Mode (Production)

To enforce TLS and reject non-TLS connections:

**PostgreSQL:**
```bash
# Update postgresql.conf
docker exec dev-postgres bash -c 'echo "ssl_ca_file = \"/var/lib/postgresql/certs/ca.crt\"" >> /var/lib/postgresql/data/postgresql.conf'
docker exec dev-postgres bash -c 'echo "hostssl all all 0.0.0.0/0 scram-sha-256" >> /var/lib/postgresql/data/pg_hba.conf'
docker compose restart postgres
```

**MySQL:**
```bash
# Update my.cnf
docker exec dev-mysql bash -c 'echo "require_secure_transport = ON" >> /etc/mysql/conf.d/tls.cnf'
docker compose restart mysql
```

---

## Rollback Procedures

### Rollback AppRole to Root Token

If AppRole causes issues, rollback to root token authentication:

**1. Update docker-compose.yml**
```bash
# Restore from backup
cp docker-compose.yml.backup docker-compose.yml

# Or manually change entrypoint:
# entrypoint: ["/init/init.sh"]  # instead of init-approle.sh

# And restore environment:
# VAULT_TOKEN: ${VAULT_TOKEN}
```

**2. Restart services**
```bash
docker compose restart postgres mysql mongodb redis-1 rabbitmq
```

**3. Verify services using root token**
```bash
docker inspect dev-postgres | grep VAULT_TOKEN
# Should show: VAULT_TOKEN=hvs.xxxxx
```

### Rollback TLS to Non-TLS

```bash
# 1. Remove SSL requirement from configurations
# (depends on service - see service documentation)

# 2. Restart without SSL
docker compose restart postgres mysql mongodb

# 3. Verify SSL disabled (or optional)
docker exec dev-postgres psql -U devuser -d devdb -c "SHOW ssl;"
# May show: on (but connections don't require it)
```

### Complete Rollback to Pre-Phase 1

```bash
# 1. Stop all services
./devstack stop

# 2. Restore from backup
tar -xzf ~/vault-backup-YYYYMMDD.tar.gz -C ~/.config/

# 3. Restore docker-compose.yml
cp docker-compose.yml.backup docker-compose.yml

# 4. Start services
./devstack start

# 5. Verify services healthy
./devstack health
```

---

## Troubleshooting Migration Issues

### Issue: Services Won't Start After AppRole Migration

**Check:**
```bash
# 1. Verify AppRole credentials exist
ls -la ~/.config/vault/approles/postgres/
# Should show: role-id and secret-id

# 2. Check service logs
docker compose logs postgres | grep -i error

# 3. Test AppRole login manually
ROLE_ID=$(cat ~/.config/vault/approles/postgres/role-id)
SECRET_ID=$(cat ~/.config/vault/approles/postgres/secret-id)
curl -X POST http://localhost:8200/v1/auth/approle/login \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}"
```

**Solution:** Re-run `./devstack vault-bootstrap`

### Issue: "permission denied" Errors

**Check policy:**
```bash
vault policy read postgres-policy
# Should show: path "secret/data/postgres" { capabilities = ["read"] }
```

**Solution:** Re-create policy via vault-bootstrap

### Issue: TLS Certificate Not Found

**Check:**
```bash
ls -la ~/.config/vault/certs/postgres/
# Should show: ca.crt, server.crt, server.key

docker exec dev-postgres ls -la /var/lib/postgresql/certs/
# Should show same files
```

**Solution:** Re-run `./scripts/generate-certificates.sh`

---

## FAQ

### Q: Do I need to migrate all services at once?
**A:** No. All services already use AppRole in DevStack Core v1.3.0+. Migration is only needed if you're upgrading from an older version.

### Q: Will migration cause data loss?
**A:** No. Migration only changes authentication method, not data storage. However, always backup before migration.

### Q: How long does migration take?
**A:** 10-15 minutes of downtime, 1-2 hours total including testing.

### Q: Can I use AppRole and root token simultaneously?
**A:** Yes. Core services use AppRole, infrastructure uses root token. Both work together.

### Q: Is TLS required?
**A:** No. TLS is optional. Services run in dual-mode (accept both TLS and non-TLS).

### Q: How do I check if AppRole is working?
**A:** Run `./tests/test-approle-security.sh` - all 32 tests should pass.

### Q: What happens when service token expires (1h TTL)?
**A:** Restart the service to get a new token: `docker compose restart postgres`

### Q: Can I change token TTL?
**A:** Yes. Update AppRole: `vault write auth/approle/role/postgres token_ttl=2h token_max_ttl=8h`

### Q: How do I backup AppRole credentials?
**A:** `tar -czf approles-backup.tar.gz ~/.config/vault/approles/`

### Q: Where are AppRole credentials stored?
**A:** `~/.config/vault/approles/<service>/role-id` and `secret-id`

---

## Support

**Documentation:**
- [VAULT.md](./VAULT.md) - Vault integration details
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - AppRole troubleshooting section
- [SECURITY_ASSESSMENT.md](./SECURITY_ASSESSMENT.md) - Security implementation details

**Testing:**
- Run `./tests/test-approle-security.sh` to validate AppRole
- Run `./tests/test-tls-connections.sh` to validate TLS

**Getting Help:**
- Check logs: `docker compose logs <service> | grep -i error`
- Run diagnostics: `./devstack health`
- Review: [UltraThink Analysis](./archive/ULTRATHINK_ANALYSIS_PHASE4.md)

---

**Last Updated:** November 19, 2025
**Phase Status:** Phase 4 Complete
**AppRole Adoption:** 100% (16/16 services) ✅
**Services:** postgres, mysql, mongodb, redis (3 nodes), rabbitmq, forgejo, reference-api, api-first, golang-api, nodejs-api, rust-api, pgbouncer, redis-exporter (3 instances), vector, management
