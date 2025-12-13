# DevStack Core Rollback Procedures

**Document Version:** 1.0
**Created:** November 14, 2025
**Baseline Commit:** 9bef892
**Feature Branch:** phase-0-4-improvements
**Improvement Commit:** 80f7072

---

## Table of Contents
1. [Overview](#overview)
2. [Quick Rollback (Emergency)](#quick-rollback-emergency)
3. [Complete Environment Rollback](#complete-environment-rollback)
4. [Partial Rollback (Per Phase)](#partial-rollback-per-phase)
5. [Service-Specific Rollback](#service-specific-rollback)
6. [Rollback Testing](#rollback-testing)
7. [Known Issues Post-Rollback](#known-issues-post-rollback)
8. [Rollback Validation Checklist](#rollback-validation-checklist)

---

## Overview

This document provides step-by-step procedures to roll back DevStack Core improvements implemented in Phases 0-4. Rollback procedures are organized by scope and urgency.

**🧪 Automated Testing:** Before performing manual rollback, consider running automated rollback tests:
- **Quick validation:** `./tests/test-rollback-simple.sh` (⭐ Recommended - 30 seconds)
- **Comprehensive:** `./tests/test-rollback-comprehensive.sh` (All databases - 2 minutes)
- **All test scripts:** See [Rollback Testing](#rollback-testing) section below
- **Test results:** [TEST_VALIDATION_REPORT.md](./TEST_VALIDATION_REPORT.md)

### When to Roll Back

Consider rollback when:
- Critical service failures occur after implementing changes
- Security vulnerabilities are introduced
- Performance degrades beyond acceptable thresholds (>20% memory, >10% CPU)
- Data integrity issues are detected
- More than 2 services fail health checks
- Test suite failures exceed 5%

### Rollback Decision Matrix

| Severity | Scope | Rollback Type | Estimated Time |
|----------|-------|---------------|----------------|
| **Critical** | All services failing | Full Environment | 15-20 minutes |
| **High** | Phase changes causing issues | Phase-Specific | 10-15 minutes |
| **Medium** | Single service issues | Service-Specific | 5-10 minutes |
| **Low** | Configuration tweaks | Configuration-Only | 2-5 minutes |

---

## Quick Rollback (Emergency)

**Use this for critical failures requiring immediate action.**

### Prerequisites
- Terminal access to DevStack Core host
- Backup files exist (verify before rollback):
  - `~/vault-backup-20251114/`
  - `backups/20251114_manual/`

### Steps

```bash
# 1. Stop all services immediately
./devstack stop

# 2. Checkout baseline commit
git checkout main
git reset --hard 9bef892

# 3. Restore Vault keys (CRITICAL - DO FIRST)
cp -r ~/vault-backup-20251114/* ~/.config/vault/

# 4. Restore .env configuration
cp backups/20251114_manual/env_backup .env

# 5. Start services
./devstack start

# 6. Wait for services to stabilize (2-3 minutes)
sleep 180

# 7. Verify health
./devstack health

# 8. Check test suite
./tests/run-all-tests.sh
```

### Expected Duration
**15-20 minutes** (including service startup and stabilization)

### Verification
- [ ] All 23 services show "healthy" status
- [ ] Vault unsealed and operational
- [ ] All databases accepting connections
- [ ] Test suite passes (370+ tests)
- [ ] No errors in service logs

---

## Complete Environment Rollback

**Use this for comprehensive rollback to baseline state.**

### Phase 1: Stop and Backup Current State

```bash
# 1. Create rollback snapshot of current state (optional)
mkdir -p rollback/$(date +%Y%m%d_%H%M%S)
cp -r ~/.config/vault rollback/$(date +%Y%m%d_%H%M%S)/
./devstack backup

# 2. Stop all services
./devstack stop

# 3. Verify all containers stopped
docker compose ps
```

**Expected Result:** All containers in "exited" state

### Phase 2: Restore Git Repository

```bash
# 1. Check current branch
git branch --show-current

# 2. Stash any uncommitted changes (if needed)
git stash save "rollback-stash-$(date +%Y%m%d_%H%M%S)"

# 3. Checkout main branch
git checkout main

# 4. Reset to baseline commit
git reset --hard 9bef892

# 5. Verify commit
git log --oneline -1
```

**Expected Output:**
```
9bef892 docs: add comprehensive Zero Cloud Dependencies section to README (#50)
```

### Phase 3: Restore Vault Configuration

```bash
# 1. Remove current Vault configuration
rm -rf ~/.config/vault/*

# 2. Restore from backup
cp -r ~/vault-backup-20251114/* ~/.config/vault/

# 3. Verify restoration
ls -la ~/.config/vault/
cat ~/.config/vault/root-token

# 4. Verify file integrity
ls ~/.config/vault/keys.json
ls ~/.config/vault/root-token
ls ~/.config/vault/ca/
ls ~/.config/vault/certs/
```

**Expected Files:**
- `keys.json` (651 bytes)
- `root-token` (29 bytes)
- `ca/` directory with CA certificates
- `certs/` directory with service certificates

### Phase 4: Restore Environment Configuration

```bash
# 1. Backup current .env (if different)
cp .env .env.rollback-$(date +%Y%m%d_%H%M%S) 2>/dev/null || true

# 2. Restore baseline .env
cp backups/20251114_manual/env_backup .env

# 3. Verify restoration
diff .env backups/20251114_manual/env_backup
```

**Expected Output:** No differences

### Phase 5: Restore Docker Volumes (if needed)

**WARNING:** This step is destructive. Only perform if data corruption is suspected.

```bash
# 1. Remove corrupted volumes
docker volume rm devstack-core_vault_data
docker volume rm devstack-core_postgres_data
docker volume rm devstack-core_mysql_data
docker volume rm devstack-core_mongodb_data
# ... (repeat for all volumes)

# 2. Recreate volumes and restore data
for vol in backups/20251114_manual/volume_*.tar.gz; do
  vol_name=$(basename "$vol" .tar.gz | sed 's/volume_//')
  docker volume create "$vol_name"
  docker run --rm -v "$vol_name":/data -v $(pwd)/backups/20251114_manual:/backup alpine sh -c "cd /data && tar xzf /backup/$(basename $vol)"
done
```

### Phase 6: Restore Database Data

```bash
# 1. Start only database services
docker compose up -d vault postgres mysql mongodb

# 2. Wait for services to be healthy
sleep 60

# 3. Restore PostgreSQL
docker compose exec -T postgres psql -U devuser -d devdb < backups/20251114_manual/postgres_all.sql

# 4. Restore MySQL
MYSQL_ROOT_PASS=$(docker exec -e VAULT_ADDR=http://localhost:8200 -e VAULT_TOKEN=$(cat ~/.config/vault/root-token) dev-vault vault kv get -field=root_password secret/mysql)
docker compose exec -T mysql sh -c "mysql -u root -p'${MYSQL_ROOT_PASS}' < /backup/mysql_all.sql"

# 5. Restore MongoDB
docker compose cp backups/20251114_manual/mongodb_dump.archive dev-mongodb:/tmp/
docker compose exec -T mongodb mongorestore --username=devuser --password=$(docker exec -e VAULT_ADDR=http://localhost:8200 -e VAULT_TOKEN=$(cat ~/.config/vault/root-token) dev-vault vault kv get -field=password secret/mongodb) --authenticationDatabase=admin --archive=/tmp/mongodb_dump.archive
```

### Phase 7: Start All Services

```bash
# 1. Start all services
./devstack start

# 2. Wait for services to stabilize (3-5 minutes)
sleep 300

# 3. Check health status
./devstack health
```

### Phase 8: Validation

```bash
# 1. Run full test suite
./tests/run-all-tests.sh

# 2. Check service logs for errors
./devstack logs vault | tail -50
./devstack logs postgres | tail -50
./devstack logs mysql | tail -50
./devstack logs mongodb | tail -50

# 3. Test API endpoints
curl -s http://localhost:8000/health | jq
curl -s http://localhost:8001/health | jq
curl -s http://localhost:8002/health | head -5
curl -s http://localhost:8003/health | jq
curl -s http://localhost:8004/health | jq

# 4. Verify resource usage
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
```

**Expected Results:**
- All 23 services healthy
- 370+ tests passing
- All API endpoints responding
- Memory usage: ~2.6 GiB
- CPU usage: <10%

---

## Partial Rollback (Per Phase)

### Phase 4 Rollback (Documentation & CI/CD)

**Impact:** Low - Only documentation and CI/CD affected

```bash
# 1. Revert documentation changes
git checkout 80f7072 -- docs/

# 2. Revert CI/CD changes
git checkout 80f7072 -- .github/workflows/

# 3. Restart (no service impact)
# No restart needed
```

### Phase 3 Rollback (Performance & Testing)

**Impact:** Low - Only test suite and performance configs affected

```bash
# 1. Revert test changes
git checkout 80f7072 -- tests/

# 2. Revert performance configs
git checkout 80f7072 -- configs/*/performance/

# 3. Restart services with reverted configs
./devstack restart
```

### Phase 2 Rollback (Operations & Reliability)

**Impact:** Medium - Backup/restore and monitoring affected

```bash
# 1. Revert backup scripts
git checkout 80f7072 -- scripts/backup-*.sh scripts/restore-*.sh

# 2. Revert monitoring configs
git checkout 80f7072 -- configs/prometheus/ configs/grafana/ configs/loki/

# 3. Restart observability services
docker compose restart prometheus grafana loki vector
```

### Phase 1 Rollback (Security Hardening)

**Impact:** High - AppRole, TLS, and network segmentation affected

**WARNING:** This rollback requires careful execution to avoid service disruption.

**CRITICAL NOTE:** When creating root token init scripts, the entrypoint must pass through Docker's command arguments. Services like PostgreSQL, MySQL, and MongoDB require additional configuration flags defined in docker-compose.yml's `command:` section.

**Correct Pattern:**
```bash
exec docker-entrypoint.sh "$@"
```

**Incorrect Pattern (will cause service failures):**
```bash
exec docker-entrypoint.sh postgres  # WRONG - loses command args
```

See `tests/test-rollback-core-services.sh` for the complete working implementation.

#### Step 1: Revert to Root Token Authentication

```bash
# 1. Stop all services
./devstack stop

# 2. Modify docker-compose.yml to use root token init scripts
sed -i.bak 's|/init/init-approle.sh|/init/init.sh|g' docker-compose.yml

# 3. Remove AppRole volume mounts from docker-compose.yml
sed -i.bak '/- .*vault-approles.*:ro/d' docker-compose.yml
sed -i.bak '/VAULT_APPROLE_DIR:/d' docker-compose.yml

# 4. Revert reference-api vault.py to root token authentication
cat > reference-apps/fastapi/app/services/vault.py << 'EOFVAULT'
"""Vault client for secrets management using root token authentication."""
import os
import logging
from typing import Optional, Dict, Any
import hvac
from hvac.exceptions import VaultError

logger = logging.getLogger(__name__)

class VaultClient:
    """HashiCorp Vault client for secret management."""

    def __init__(self):
        """Initialize Vault client with root token authentication."""
        self.vault_addr = os.getenv("VAULT_ADDR", "http://vault:8200")
        self.vault_token = os.getenv("VAULT_TOKEN")

        if not self.vault_token:
            raise ValueError("VAULT_TOKEN environment variable not set")

        self.client = hvac.Client(url=self.vault_addr, token=self.vault_token)

        if not self.client.is_authenticated():
            raise VaultError("Failed to authenticate with Vault using root token")

        logger.info("Vault client initialized successfully with root token")

    def get_secret(self, path: str, key: Optional[str] = None) -> Any:
        """Retrieve secret from Vault KV v2 store."""
        try:
            secret = self.client.secrets.kv.v2.read_secret_version(path=path)
            data = secret["data"]["data"]
            return data.get(key) if key else data
        except Exception as e:
            logger.error(f"Error retrieving secret from {path}: {e}")
            raise

vault_client = VaultClient()
EOFVAULT

# 5. Disable TLS in .env
sed -i.bak 's/ENABLE_TLS=true/ENABLE_TLS=false/g' .env
sed -i.bak 's/POSTGRES_ENABLE_TLS=true/POSTGRES_ENABLE_TLS=false/g' .env
sed -i.bak 's/MYSQL_ENABLE_TLS=true/MYSQL_ENABLE_TLS=false/g' .env
sed -i.bak 's/MONGODB_ENABLE_TLS=true/MONGODB_ENABLE_TLS=false/g' .env
sed -i.bak 's/REDIS_ENABLE_TLS=true/REDIS_ENABLE_TLS=false/g' .env
sed -i.bak 's/RABBITMQ_ENABLE_TLS=true/RABBITMQ_ENABLE_TLS=false/g' .env

# 6. Export VAULT_TOKEN for services to use
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# 7. Start services with VAULT_TOKEN environment variable
VAULT_TOKEN="$VAULT_TOKEN" ./devstack start

# 8. Verify services are using root token authentication
docker exec dev-postgres env | grep VAULT_TOKEN  # Should show token
docker exec dev-postgres ls /vault-approles 2>&1  # Should NOT exist (error expected)

# 9. Verify health
./devstack health
```

#### Step 2: Remove AppRole Configuration

```bash
# 1. Remove AppRole policies (optional - can keep for future use)
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
export VAULT_ADDR=http://localhost:8200

docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault auth disable approle
docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault policy delete postgres-policy
docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault policy delete mysql-policy
docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault policy delete mongodb-policy
docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault policy delete redis-policy
docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault policy delete rabbitmq-policy
docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault policy delete forgejo-policy
docker exec -e VAULT_ADDR=$VAULT_ADDR -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault policy delete reference-api-policy
```

#### Step 3: Validation

```bash
# 1. Verify all services healthy
./devstack health

# 2. Run test suite
./tests/run-all-tests.sh

# 3. Verify root token authentication
./devstack vault-show-password postgres
```

---

## Service-Specific Rollback

### PostgreSQL Rollback

```bash
# 1. Stop PostgreSQL
docker compose stop postgres pgbouncer

# 2. Revert init script
git checkout 80f7072 -- configs/postgres/scripts/init.sh

# 3. Disable TLS (if enabled)
# Edit .env: POSTGRES_ENABLE_TLS=false

# 4. Restart PostgreSQL
docker compose up -d postgres pgbouncer

# 5. Verify
docker compose exec postgres psql -U devuser -d devdb -c "SELECT 1;"
```

### MySQL Rollback

```bash
# 1. Stop MySQL
docker compose stop mysql

# 2. Revert init script
git checkout 80f7072 -- configs/mysql/scripts/init.sh

# 3. Disable TLS (if enabled)
# Edit .env: MYSQL_ENABLE_TLS=false

# 4. Restart MySQL
docker compose up -d mysql

# 5. Wait for MySQL to become healthy (expected: ~50-60 seconds)
# MySQL's InnoDB storage engine requires more initialization time than other databases
for i in {1..60}; do
    if docker ps --filter "name=dev-mysql" --format "{{.Status}}" | grep -q "healthy"; then
        echo "MySQL is healthy after ${i} seconds"
        break
    fi
    sleep 1
done

# 6. Verify
docker compose exec mysql mysql -u devuser -p$(./devstack vault-show-password mysql) -e "SELECT 1;"
```

**Performance Note:** MySQL typically takes 50-60 seconds to become healthy after restart, compared to:
- PostgreSQL: 6 seconds
- MongoDB: 1 second

This is expected behavior due to InnoDB's initialization requirements.

### MongoDB Rollback

**IMPORTANT:** MongoDB requires both `MONGO_INITDB_ROOT_USERNAME` and `MONGO_INITDB_ROOT_PASSWORD` environment variables for initial container setup. The root token init script (`configs/mongodb/scripts/init.sh`) includes both variables as of November 17, 2025.

```bash
# 1. Stop MongoDB
docker compose stop mongodb

# 2. Revert init script
git checkout 80f7072 -- configs/mongodb/scripts/init.sh

# 3. Disable TLS (if enabled)
# Edit .env: MONGODB_ENABLE_TLS=false

# 4. Restart MongoDB
docker compose up -d mongodb

# 5. Verify
docker compose exec mongodb mongosh --username devuser --password $(./devstack vault-show-password mongodb) --authenticationDatabase admin --eval "db.adminCommand('ping')"
```

**MongoDB Root Token Authentication Requirements:**
- When rolling back to root token authentication, ensure init script exports:
  - `MONGO_INITDB_ROOT_USERNAME` (from Vault secret/mongodb username field)
  - `MONGO_INITDB_ROOT_PASSWORD` (from Vault secret/mongodb password field)
- Missing either variable will cause MongoDB container startup failure
- Fixed in `configs/mongodb/scripts/init.sh` on November 17, 2025

### Redis Cluster Rollback

```bash
# 1. Stop all Redis nodes
docker compose stop redis-1 redis-2 redis-3

# 2. Revert init script
git checkout 80f7072 -- configs/redis/scripts/init.sh

# 3. Disable TLS (if enabled)
# Edit .env: REDIS_ENABLE_TLS=false

# 4. Restart Redis cluster
docker compose up -d redis-1 redis-2 redis-3

# 5. Wait for cluster to form
sleep 30

# 6. Verify
REDIS_PASS=$(./devstack vault-show-password redis-1)
docker compose exec redis-1 redis-cli -a "$REDIS_PASS" ping
```

### RabbitMQ Rollback

```bash
# 1. Stop RabbitMQ
docker compose stop rabbitmq

# 2. Revert init script
git checkout 80f7072 -- configs/rabbitmq/scripts/init.sh

# 3. Disable TLS (if enabled)
# Edit .env: RABBITMQ_ENABLE_TLS=false

# 4. Restart RabbitMQ
docker compose up -d rabbitmq

# 5. Verify
docker compose exec rabbitmq rabbitmqctl status
```

### Vault Rollback

**CRITICAL:** Only perform if Vault is corrupted beyond repair.

```bash
# 1. Stop all services (Vault dependencies)
./devstack stop

# 2. Remove Vault data
docker volume rm devstack-core_vault_data

# 3. Restore Vault keys
rm -rf ~/.config/vault/*
cp -r ~/vault-backup-20251114/* ~/.config/vault/

# 4. Restore Vault volume
docker volume create devstack-core_vault_data
docker run --rm -v devstack-core_vault_data:/data -v $(pwd)/backups/20251114_manual:/backup alpine sh -c "cd /data && tar xzf /backup/volume_devstack-core_vault_data.tar.gz"

# 5. Start Vault only
docker compose up -d vault

# 6. Wait for Vault to unseal
sleep 60

# 7. Verify Vault status
./devstack vault-status

# 8. Start all services
./devstack start
```

---

## Rollback Testing

DevStack Core includes **4 automated rollback test scripts** to validate rollback procedures. These tests ensure rollback procedures work correctly before you need them in production.

### Test Scripts Overview

| Test Script | Purpose | Duration | Scope | When to Use | Status |
|-------------|---------|----------|-------|-------------|--------|
| **`test-rollback-simple.sh`** ⭐ | Quick smoke test | ~30s | Single service validation | Development, quick checks | ✅ VALIDATED |
| **`test-rollback-core-services.sh`** | Comprehensive validation | ~15-20 min | All 6 core services | Pre-production validation | ✅ FIXED (Nov 17, 2025) |
| **`test-rollback-comprehensive.sh`** | Database rollback test | ~2-3 min | 3 databases | Database-specific validation | ✅ FIXED (Nov 17, 2025) |
| **`test-rollback-procedures-fixed.sh`** | Documentation validation | ~10-15 min | Procedures from this doc | After documentation updates | ⏳ PENDING |
| **`test-rollback-complete-fixed.sh`** | Full disaster recovery | ~20-30 min | Complete environment + VM | Pre-release validation only | ⏳ PENDING |

**Location:** `tests/test-rollback-*.sh`

**Recommended Test:** Use `test-rollback-simple.sh` for validation - it's proven to work and validates core rollback procedures (AppRole ↔ Root Token migration).

**Latest Test Results:** See [TEST_VALIDATION_REPORT.md](./TEST_VALIDATION_REPORT.md) for comprehensive testing analysis.

### Running Rollback Tests

```bash
# Recommended: Simple test (proven reliable, ~30 seconds)
./tests/test-rollback-simple.sh

# Comprehensive core services test (fixed November 17, 2025)
./tests/test-rollback-core-services.sh

# Database-specific test (fixed November 17, 2025)
./tests/test-rollback-comprehensive.sh

# Validate documentation accuracy
./tests/test-rollback-procedures-fixed.sh

# Full environment test (pre-release only, requires VM restart)
./tests/test-rollback-complete-fixed.sh
```

### Test Script Improvements Applied (November 17, 2025)

The following improvements have been implemented in test scripts:

1. ✅ **Fixed Command Syntax**: Changed `docker compose stop` to use service names instead of container names
2. ✅ **Fixed Restart Commands**: Replaced `./devstack restart` with `docker compose up -d` for targeted service restarts
3. ✅ **Added Redis Retry Logic**: Implemented 3-retry mechanism with 2-second delays for Redis connection tests
4. ✅ **MongoDB Init Script Fix**: Added `MONGO_INITDB_ROOT_USERNAME` environment variable for root token authentication
5. ✅ **Documented MySQL Restart Time**: Added performance note about MySQL's 50-60 second restart time

**Files Updated:**
- `configs/mongodb/scripts/init.sh` - Added MONGO_INITDB_ROOT_USERNAME export
- `tests/test-rollback-core-services.sh` - Fixed command syntax, added Redis retry logic, fixed restart commands
- `docs/ROLLBACK_PROCEDURES.md` - Added MySQL restart time documentation and performance notes

**Remaining Improvements:**
- Better error handling with diagnostic capture
- Prerequisites validation before test execution
- Automated cleanup on test failures

See [TEST_VALIDATION_REPORT.md](./TEST_VALIDATION_REPORT.md) for detailed test results and analysis.

### Pre-Rollback Test

**Run this before performing actual rollback to verify backup integrity:**

```bash
# 1. Verify backup files exist
test -d ~/vault-backup-20251114 && echo "✓ Vault backup exists" || echo "✗ Vault backup MISSING"
test -d backups/20251114_manual && echo "✓ Service backups exist" || echo "✗ Service backups MISSING"

# 2. Verify backup file sizes (should be non-zero)
du -sh ~/vault-backup-20251114
du -sh backups/20251114_manual

# 3. Verify backup file integrity
ls -lh ~/vault-backup-20251114/keys.json
ls -lh ~/vault-backup-20251114/root-token
ls -lh backups/20251114_manual/*.sql
ls -lh backups/20251114_manual/*.archive
ls -lh backups/20251114_manual/*.tar.gz

# 4. Verify git baseline commit exists
git log --oneline | /usr/bin/grep 9bef892 && echo "✓ Baseline commit exists" || echo "✗ Baseline commit MISSING"
```

### Post-Rollback Test

**Run this after rollback to verify success:**

```bash
#!/bin/bash
# File: scripts/test-rollback.sh

echo "=== DevStack Core Rollback Validation ==="
echo ""

# 1. Verify git state
echo "1. Checking git state..."
CURRENT_COMMIT=$(git log --oneline -1 | awk '{print $1}')
if [ "$CURRENT_COMMIT" = "9bef892" ]; then
  echo "✓ Git state: Baseline commit (9bef892)"
else
  echo "✗ Git state: NOT at baseline commit (current: $CURRENT_COMMIT)"
  exit 1
fi

# 2. Verify services
echo "2. Checking services..."
HEALTHY_COUNT=$(./devstack health 2>&1 | /usr/bin/grep "healthy" | wc -l | tr -d ' ')
if [ "$HEALTHY_COUNT" -eq 23 ]; then
  echo "✓ Services: All 23 services healthy"
else
  echo "✗ Services: Only $HEALTHY_COUNT/23 healthy"
  exit 1
fi

# 3. Verify Vault
echo "3. Checking Vault..."
VAULT_STATUS=$(./devstack vault-status 2>&1 | /usr/bin/grep "Sealed" | awk '{print $2}')
if [ "$VAULT_STATUS" = "false" ]; then
  echo "✓ Vault: Unsealed and operational"
else
  echo "✗ Vault: Sealed or not operational"
  exit 1
fi

# 4. Verify databases
echo "4. Checking databases..."
docker compose exec -T postgres psql -U devuser -d devdb -c "SELECT 1" >/dev/null 2>&1 && echo "✓ PostgreSQL: Connected" || echo "✗ PostgreSQL: Connection failed"
docker compose exec -T mysql sh -c "mysql -u devuser -p\$(cat /run/secrets/mysql_password 2>/dev/null || echo '') -e 'SELECT 1'" >/dev/null 2>&1 && echo "✓ MySQL: Connected" || echo "✗ MySQL: Connection failed"
docker compose exec -T mongodb mongosh --quiet --eval "db.adminCommand('ping')" >/dev/null 2>&1 && echo "✓ MongoDB: Connected" || echo "✗ MongoDB: Connection failed"

# 5. Verify APIs
echo "5. Checking APIs..."
curl -s http://localhost:8000/health | /usr/bin/grep -q "healthy" && echo "✓ Reference API: Responding" || echo "✗ Reference API: Not responding"
curl -s http://localhost:8001/health | /usr/bin/grep -q "healthy" && echo "✓ API-First: Responding" || echo "✗ API-First: Not responding"
curl -s http://localhost:8002/health >/dev/null 2>&1 && echo "✓ Golang API: Responding" || echo "✗ Golang API: Not responding"
curl -s http://localhost:8003/health | /usr/bin/grep -q "healthy" && echo "✓ Node.js API: Responding" || echo "✗ Node.js API: Not responding"
curl -s http://localhost:8004/health >/dev/null 2>&1 && echo "✓ Rust API: Responding" || echo "✗ Rust API: Not responding"

# 6. Run test suite
echo "6. Running test suite..."
./tests/run-all-tests.sh >/dev/null 2>&1
if [ $? -eq 0 ]; then
  echo "✓ Test suite: All tests passing"
else
  echo "✗ Test suite: Some tests failing"
  exit 1
fi

echo ""
echo "=== Rollback Validation: SUCCESS ==="
```

---

## Known Issues Post-Rollback

### Issue 1: Service Startup Delays

**Symptom:** Services take 3-5 minutes to become healthy after rollback.

**Cause:** Docker volume restoration and database initialization.

**Resolution:** Wait for all services to stabilize. Use `./devstack health` to monitor.

**Timeline:** 3-5 minutes

### Issue 2: Redis Cluster Split-Brain

**Symptom:** Redis cluster shows inconsistent state after rollback.

**Cause:** Cluster metadata not synchronized during volume restoration.

**Resolution:**
```bash
# 1. Stop Redis nodes
docker compose stop redis-1 redis-2 redis-3

# 2. Clear cluster metadata
docker volume rm devstack-core_redis_1_data
docker volume rm devstack-core_redis_2_data
docker volume rm devstack-core_redis_3_data

# 3. Restore volumes
docker volume create devstack-core_redis_1_data
docker volume create devstack-core_redis_2_data
docker volume create devstack-core_redis_3_data

# 4. Restore data
docker run --rm -v devstack-core_redis_1_data:/data -v $(pwd)/backups/20251114_manual:/backup alpine sh -c "cd /data && tar xzf /backup/volume_devstack-core_redis_1_data.tar.gz"
docker run --rm -v devstack-core_redis_2_data:/data -v $(pwd)/backups/20251114_manual:/backup alpine sh -c "cd /data && tar xzf /backup/volume_devstack-core_redis_2_data.tar.gz"
docker run --rm -v devstack-core_redis_3_data:/data -v $(pwd)/backups/20251114_manual:/backup alpine sh -c "cd /data && tar xzf /backup/volume_devstack-core_redis_3_data.tar.gz"

# 5. Start Redis and reinitialize cluster
docker compose up -d redis-1 redis-2 redis-3
sleep 30
./devstack redis-cluster-init
```

### Issue 3: Vault Seal After Rollback

**Symptom:** Vault is sealed after rollback despite keys being restored.

**Cause:** Vault data volume not restored properly.

**Resolution:**
```bash
# 1. Check seal status
./devstack vault-status

# 2. If sealed, manually unseal
./devstack vault-unseal

# 3. If unseal fails, restore Vault volume
./devstack stop
docker volume rm devstack-core_vault_data
docker volume create devstack-core_vault_data
docker run --rm -v devstack-core_vault_data:/data -v $(pwd)/backups/20251114_manual:/backup alpine sh -c "cd /data && tar xzf /backup/volume_devstack-core_vault_data.tar.gz"
./devstack start
```

### Issue 4: Forgejo Git Repository Corruption

**Symptom:** Forgejo fails to start or repositories are inaccessible.

**Cause:** Forgejo data volume corruption during rollback.

**Resolution:**
```bash
# 1. Stop Forgejo
docker compose stop forgejo

# 2. Restore Forgejo volume
docker volume rm devstack-core_forgejo_data
docker volume create devstack-core_forgejo_data
docker run --rm -v devstack-core_forgejo_data:/data -v $(pwd)/backups/20251114_manual:/backup alpine sh -c "cd /data && tar xzf /backup/volume_devstack-core_forgejo_data.tar.gz"

# 3. Start Forgejo
docker compose up -d forgejo

# 4. Verify
curl -s http://localhost:3000 | /usr/bin/grep -q "Forgejo" && echo "✓ Forgejo operational"
```

### Issue 5: Test Suite Intermittent Failures

**Symptom:** Some tests fail intermittently after rollback.

**Cause:** Services not fully stabilized.

**Resolution:**
```bash
# 1. Wait for all services to stabilize
sleep 300

# 2. Restart services
./devstack restart

# 3. Re-run test suite
./tests/run-all-tests.sh
```

---

## Rollback Validation Checklist

Use this checklist to verify successful rollback:

### Git State
- [ ] Branch: `main`
- [ ] Commit: `9bef892`
- [ ] No uncommitted changes
- [ ] No untracked files (except backups/)

### Services
- [ ] All 23 services running
- [ ] All 23 services healthy
- [ ] Vault unsealed (Sealed: false)
- [ ] PostgreSQL accepting connections
- [ ] MySQL accepting connections
- [ ] MongoDB accepting connections
- [ ] Redis cluster operational
- [ ] RabbitMQ accepting connections
- [ ] Forgejo accessible (http://localhost:3000)

### APIs
- [ ] Reference API (port 8000) responding
- [ ] API-First (port 8001) responding
- [ ] Golang API (port 8002) responding
- [ ] Node.js API (port 8003) responding
- [ ] Rust API (port 8004) responding

### Data Integrity
- [ ] PostgreSQL databases present and queryable
- [ ] MySQL databases present and queryable
- [ ] MongoDB databases present and queryable
- [ ] Redis cluster data accessible
- [ ] Forgejo repositories accessible

### Configuration
- [ ] `.env` matches baseline (backups/20251114_manual/env_backup)
- [ ] Vault keys restored (~/vault-backup-20251114/)
- [ ] No TLS enabled (all services HTTP only)
- [ ] Root token authentication (no AppRole)
- [ ] Single network (dev-services)

### Testing
- [ ] Test suite runs without errors
- [ ] All 370+ tests pass
- [ ] No test failures
- [ ] No test timeouts

### Performance
- [ ] Memory usage: ~2.6 GiB (±10%)
- [ ] CPU usage: <10%
- [ ] Response times normal (baseline)
- [ ] No performance degradation

### Logs
- [ ] No critical errors in Vault logs
- [ ] No critical errors in PostgreSQL logs
- [ ] No critical errors in MySQL logs
- [ ] No critical errors in MongoDB logs
- [ ] No critical errors in Redis logs
- [ ] No critical errors in API logs

---

## Emergency Contacts

In case of rollback failure:

1. **Check GitHub Issues:** https://github.com/NormB/devstack-core/issues
2. **Review Documentation:** `docs/DISASTER_RECOVERY.md`
3. **Consult Team:** (add team contact information)

---

## Rollback Success Criteria

Rollback is considered **successful** when:

✅ All services healthy (23/23)
✅ Git state at baseline commit (9bef892)
✅ Vault unsealed and operational
✅ All databases accessible
✅ All APIs responding
✅ Test suite passes (370+ tests)
✅ Performance within baseline (±10%)
✅ No critical errors in logs
✅ Data integrity verified
✅ Backup restoration tested

---

## Post-Rollback Actions

After successful rollback:

1. **Document Issue:** Create post-mortem document explaining:
   - What went wrong
   - Why rollback was necessary
   - What was learned
   - How to prevent in future

2. **Update Improvement Plan:** Revise `docs/IMPROVEMENT_TASK_LIST.md` with:
   - Root cause analysis
   - Adjusted task estimates
   - Additional risk mitigations
   - Updated dependencies

3. **Notify Stakeholders:** Inform team of:
   - Rollback completion
   - Current system state
   - Next steps
   - Timeline adjustments

4. **Plan Forward:** Determine:
   - Whether to retry improvements
   - What changes to make to approach
   - What additional testing needed
   - When to attempt again

---

**Document Version:** 1.0
**Last Updated:** November 14, 2025 08:50 EST
**Next Review:** After Phase 1 completion
**Owner:** DevStack Core Team
