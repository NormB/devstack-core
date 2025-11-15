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
./manage-devstack stop

# 2. Checkout baseline commit
git checkout main
git reset --hard 9bef892

# 3. Restore Vault keys (CRITICAL - DO FIRST)
cp -r ~/vault-backup-20251114/* ~/.config/vault/

# 4. Restore .env configuration
cp backups/20251114_manual/env_backup .env

# 5. Start services
./manage-devstack start

# 6. Wait for services to stabilize (2-3 minutes)
sleep 180

# 7. Verify health
./manage-devstack health

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
./manage-devstack backup

# 2. Stop all services
./manage-devstack stop

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
./manage-devstack start

# 2. Wait for services to stabilize (3-5 minutes)
sleep 300

# 3. Check health status
./manage-devstack health
```

### Phase 8: Validation

```bash
# 1. Run full test suite
./tests/run-all-tests.sh

# 2. Check service logs for errors
./manage-devstack logs vault | tail -50
./manage-devstack logs postgres | tail -50
./manage-devstack logs mysql | tail -50
./manage-devstack logs mongodb | tail -50

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
./manage-devstack restart
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

#### Step 1: Revert to Root Token Authentication

```bash
# 1. Stop all services
./manage-devstack stop

# 2. Revert init scripts to root token
git checkout 80f7072 -- configs/*/scripts/init.sh

# 3. Disable TLS in .env
sed -i.bak 's/ENABLE_TLS=true/ENABLE_TLS=false/g' .env
sed -i.bak 's/POSTGRES_ENABLE_TLS=true/POSTGRES_ENABLE_TLS=false/g' .env
sed -i.bak 's/MYSQL_ENABLE_TLS=true/MYSQL_ENABLE_TLS=false/g' .env
sed -i.bak 's/MONGODB_ENABLE_TLS=true/MONGODB_ENABLE_TLS=false/g' .env
sed -i.bak 's/REDIS_ENABLE_TLS=true/REDIS_ENABLE_TLS=false/g' .env
sed -i.bak 's/RABBITMQ_ENABLE_TLS=true/RABBITMQ_ENABLE_TLS=false/g' .env

# 4. Revert network configuration
git checkout 80f7072 -- docker-compose.yml

# 5. Start services
./manage-devstack start

# 6. Verify health
./manage-devstack health
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
./manage-devstack health

# 2. Run test suite
./tests/run-all-tests.sh

# 3. Verify root token authentication
./manage-devstack vault-show-password postgres
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

# 5. Verify
docker compose exec mysql mysql -u devuser -p$(./manage-devstack vault-show-password mysql) -e "SELECT 1;"
```

### MongoDB Rollback

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
docker compose exec mongodb mongosh --username devuser --password $(./manage-devstack vault-show-password mongodb) --authenticationDatabase admin --eval "db.adminCommand('ping')"
```

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
REDIS_PASS=$(./manage-devstack vault-show-password redis-1)
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
./manage-devstack stop

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
./manage-devstack vault-status

# 8. Start all services
./manage-devstack start
```

---

## Rollback Testing

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
HEALTHY_COUNT=$(./manage-devstack health 2>&1 | /usr/bin/grep "healthy" | wc -l | tr -d ' ')
if [ "$HEALTHY_COUNT" -eq 23 ]; then
  echo "✓ Services: All 23 services healthy"
else
  echo "✗ Services: Only $HEALTHY_COUNT/23 healthy"
  exit 1
fi

# 3. Verify Vault
echo "3. Checking Vault..."
VAULT_STATUS=$(./manage-devstack vault-status 2>&1 | /usr/bin/grep "Sealed" | awk '{print $2}')
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

**Resolution:** Wait for all services to stabilize. Use `./manage-devstack health` to monitor.

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
./manage-devstack redis-cluster-init
```

### Issue 3: Vault Seal After Rollback

**Symptom:** Vault is sealed after rollback despite keys being restored.

**Cause:** Vault data volume not restored properly.

**Resolution:**
```bash
# 1. Check seal status
./manage-devstack vault-status

# 2. If sealed, manually unseal
./manage-devstack vault-unseal

# 3. If unseal fails, restore Vault volume
./manage-devstack stop
docker volume rm devstack-core_vault_data
docker volume create devstack-core_vault_data
docker run --rm -v devstack-core_vault_data:/data -v $(pwd)/backups/20251114_manual:/backup alpine sh -c "cd /data && tar xzf /backup/volume_devstack-core_vault_data.tar.gz"
./manage-devstack start
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
./manage-devstack restart

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

1. **Check GitHub Issues:** https://github.com/anthropics/devstack-core/issues
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
