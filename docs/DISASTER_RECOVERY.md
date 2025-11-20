# Disaster Recovery Runbook

## Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Recovery Time Objectives](#recovery-time-objectives)
- [Complete Environment Loss](#complete-environment-loss)
- [Vault Data Loss](#vault-data-loss)
- [Database Corruption](#database-corruption)
- [Network Issues](#network-issues)
- [Service-Specific Recovery](#service-specific-recovery)
- [Backup Procedures](#backup-procedures)
- [Testing DR Procedures](#testing-dr-procedures)
- [Post-Recovery Checklist](#post-recovery-checklist)

---

## Overview

This document provides comprehensive disaster recovery procedures for the DevStack Core infrastructure. It covers complete environment loss, partial failures, data corruption, and network issues.

**Recovery Objectives:**
- **RTO (Recovery Time Objective):** 30 minutes
- **RPO (Recovery Point Objective):** Last backup (typically 24 hours)

**Critical Data Locations:**
- Vault keys: `~/.config/vault/`
- Database backups: `backups/`
- Configuration: `.env`
- Service configs: `configs/*/`
- Certificates: `~/.config/vault/certs/`

---

## Prerequisites

Before disaster strikes, ensure you have:

- [ ] **Vault keys backed up** - `~/.config/vault/keys.json`
- [ ] **Vault root token backed up** - `~/.config/vault/root-token`
- [ ] **Database backups** - Run `./devstack.sh backup` regularly
- [ ] **Configuration files** - `.env`, `docker-compose.yml`
- [ ] **Service configs** - All files in `configs/*/`
- [ ] **Certificates** - `~/.config/vault/certs/` and `~/.config/vault/ca/`
- [ ] **This documentation** - Offline copy available

**Backup Checklist:**
```bash
# Create comprehensive backup
BACKUP_DIR=~/devstack-core-backup-$(date +%Y%m%d)
mkdir -p $BACKUP_DIR

# Vault data (CRITICAL)
cp -r ~/.config/vault $BACKUP_DIR/

# Databases
./devstack.sh backup
cp -r backups/ $BACKUP_DIR/

# Configuration
cp .env $BACKUP_DIR/
cp docker-compose.yml $BACKUP_DIR/
cp -r configs/ $BACKUP_DIR/

# Verify backup
ls -lh $BACKUP_DIR/
```

---

## Recovery Time Objectives

| Scenario | RTO | Impact | Priority |
|----------|-----|--------|----------|
| Complete environment loss | 30 min | Total outage | P0 |
| Vault data loss | 45 min | Cannot access secrets | P0 |
| Single database corruption | 15 min | Partial outage | P1 |
| Network issues | 10 min | Connectivity problems | P1 |
| Service crash | 5 min | Single service down | P2 |

---

## Complete Environment Loss

**Scenario:** Colima VM destroyed, all containers lost, data volumes missing

**Symptoms:**
- Colima not running
- All containers gone
- Docker volumes empty
- Services unreachable

### Recovery Steps

#### 1. Verify Backup Availability (1 minute)

```bash
# Check for backups
ls -lh ~/devstack-core-backup-*/

# Verify Vault keys exist
cat ~/devstack-core-backup-*/vault/keys.json
cat ~/devstack-core-backup-*/vault/root-token

# Verify database backups
ls -lh ~/devstack-core-backup-*/backups/
```

#### 2. Reinstall Colima (5 minutes)

```bash
# If Colima is completely gone
brew install colima docker docker-compose

# Start Colima with appropriate resources
colima start --cpu 4 --memory 8 --disk 60 --vm-type=vz --vz-rosetta

# Verify Colima is running
colima status
docker ps
```

#### 3. Restore Repository and Configuration (2 minutes)

```bash
# If repository is intact, just update configs
cd devstack-core

# Restore .env from backup
cp ~/devstack-core-backup-latest/.env .env

# Restore service configs if needed
cp -r ~/devstack-core-backup-latest/configs/* configs/

# Verify
cat .env | head -20
```

#### 4. Restore Vault Keys (2 minutes)

```bash
# Recreate Vault config directory
mkdir -p ~/.config/vault

# Restore Vault keys and token
cp ~/devstack-core-backup-latest/vault/keys.json ~/.config/vault/
cp ~/devstack-core-backup-latest/vault/root-token ~/.config/vault/

# Restore CA certificates
cp -r ~/devstack-core-backup-latest/vault/ca ~/.config/vault/

# Restore service certificates
cp -r ~/devstack-core-backup-latest/vault/certs ~/.config/vault/

# Verify
cat ~/.config/vault/root-token
ls ~/.config/vault/certs/
```

#### 5. Start Infrastructure (3 minutes)

```bash
# Start all services
./devstack.sh start

# This will:
# - Start Vault first
# - Auto-unseal Vault with restored keys
# - Start all dependent services
# - Services will fetch credentials from Vault

# Monitor startup
docker compose logs -f --tail=100
```

#### 6. Verify Vault (2 minutes)

```bash
# Set Vault environment
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
export VAULT_ADDR=http://localhost:8200

# Check Vault status
vault status
# Should show: Sealed: false

# Verify secrets are accessible
vault kv list secret/

# Test credential retrieval
vault kv get secret/postgres
```

#### 7. Restore Database Data (10 minutes)

**PostgreSQL:**
```bash
# Check if database is empty
docker exec postgres psql -U dev_admin -d dev_database -c "\dt"

# Restore from backup
docker exec -i postgres psql -U dev_admin -d dev_database < \
  ~/devstack-core-backup-latest/backups/postgres_backup_*.sql

# Verify restoration
docker exec postgres psql -U dev_admin -d dev_database -c "\dt"
docker exec postgres psql -U dev_admin -d dev_database -c "SELECT COUNT(*) FROM users;"
```

**MySQL:**
```bash
# Get MySQL password from Vault
MYSQL_PASS=$(vault kv get -field=password secret/mysql)

# Restore from backup
docker exec -i mysql mysql -u dev_admin -p$MYSQL_PASS dev_database < \
  ~/devstack-core-backup-latest/backups/mysql_backup_*.sql

# Verify
docker exec mysql mysql -u dev_admin -p$MYSQL_PASS dev_database -e "SHOW TABLES;"
```

**MongoDB:**
```bash
# Get MongoDB password
MONGO_PASS=$(vault kv get -field=password secret/mongodb)

# Copy backup into container
docker cp ~/devstack-core-backup-latest/backups/mongodb \
  mongodb:/tmp/mongodb_restore

# Restore
docker exec mongodb mongorestore \
  --host localhost --port 27017 \
  --username dev_admin --password $MONGO_PASS \
  --authenticationDatabase admin \
  /tmp/mongodb_restore

# Verify
docker exec mongodb mongosh \
  "mongodb://dev_admin:$MONGO_PASS@localhost:27017/dev_database" \
  --eval "db.getCollectionNames()"
```

#### 8. Verify All Services (5 minutes)

```bash
# Check service health
./devstack.sh health

# Expected output: All services should be "healthy"
# If any service is unhealthy, check logs:
docker compose logs <service>

# Test API endpoints
curl http://localhost:8000/health/all | jq '.'

# Test database connectivity
curl http://localhost:8000/examples/database/postgres/query | jq '.'

# Test Vault integration
curl http://localhost:8000/examples/vault/secret/postgres | jq '.'

# Test Redis cluster
curl http://localhost:8000/examples/cache/test -X POST \
  -H "Content-Type: application/json" \
  -d '{"value": "disaster recovery test", "ttl": 60}'

curl http://localhost:8000/examples/cache/test | jq '.'
```

#### 9. Verify Forgejo Git Server (Optional, 2 minutes)

```bash
# Access Forgejo
open http://localhost:3000

# Login with admin credentials
# Username: gitadmin
# Password: $(vault kv get -field=admin_password secret/forgejo)

# Verify repositories are accessible
# If repositories are missing, restore from Git backup
```

**Total Recovery Time:** ~30 minutes

---

## Vault Data Loss

**Scenario:** Vault sealed and cannot unseal, lost unseal keys, or corrupted Vault data

**CRITICAL:** If Vault keys are lost, Vault data **CANNOT BE RECOVERED**. All secrets and certificates will need to be regenerated.

### Prevention

```bash
# Immediately after initial setup, backup Vault keys
./devstack.sh vault-init

# Backup keys to multiple locations
cp -r ~/.config/vault ~/Dropbox/vault-backup-$(date +%Y%m%d)
cp -r ~/.config/vault /Volumes/ExternalDrive/vault-backup-$(date +%Y%m%d)

# Test backup integrity
cat ~/Dropbox/vault-backup-*/keys.json
cat ~/Dropbox/vault-backup-*/root-token
```

### Recovery If Keys Are Available

```bash
# 1. Stop Vault
docker compose stop vault

# 2. Remove corrupted data
docker volume rm devstack-core_vault-data

# 3. Recreate volume
docker volume create devstack-core_vault-data

# 4. Restore Vault keys
cp ~/vault-backup-*/keys.json ~/.config/vault/
cp ~/vault-backup-*/root-token ~/.config/vault/

# 5. Start Vault
docker compose start vault

# 6. Verify auto-unseal works
vault status

# 7. Re-bootstrap secrets
./devstack.sh vault-bootstrap

# 8. Restart all services to pick up new credentials
./devstack.sh restart
```

### Recovery If Keys Are LOST

**Impact:** All Vault data is permanently lost. Must re-initialize from scratch.

```bash
# 1. Stop everything
./devstack.sh stop

# 2. Remove Vault data
docker volume rm devstack-core_vault-data
rm -rf ~/.config/vault

# 3. Start infrastructure
./devstack.sh start

# 4. Initialize new Vault
./devstack.sh vault-init

# NEW keys and token will be generated

# 5. Bootstrap new secrets
./devstack.sh vault-bootstrap

# 6. Regenerate certificates
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
./scripts/generate-certificates.sh

# 7. Restart all services
./devstack.sh restart

# 8. MANUALLY UPDATE:
# - All applications using Vault credentials
# - All certificate references
# - Any external systems with Vault integration
```

---

## Database Corruption

### PostgreSQL Recovery

**Symptoms:**
- Connection errors
- Query failures
- Data inconsistency
- pg_dump fails

**Recovery:**

```bash
# 1. Stop PostgreSQL
docker compose stop postgres

# 2. Backup current state (even if corrupted)
docker run --rm -v devstack-core_postgres-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/postgres-corrupted-$(date +%Y%m%d-%H%M%S).tar.gz /data

# 3. Remove corrupted volume
docker volume rm devstack-core_postgres-data

# 4. Recreate volume
docker volume create devstack-core_postgres-data

# 5. Start PostgreSQL (will create fresh database)
docker compose start postgres

# Wait for PostgreSQL to be ready
sleep 10

# 6. Restore from backup
docker exec -i postgres psql -U dev_admin -d dev_database < \
  backups/postgres_backup_latest.sql

# 7. Verify data integrity
docker exec postgres psql -U dev_admin -d dev_database -c "\dt"
docker exec postgres psql -U dev_admin -d dev_database -c \
  "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables;"

# 8. Rebuild indexes
docker exec postgres psql -U dev_admin -d dev_database -c "REINDEX DATABASE dev_database;"

# 9. Vacuum and analyze
docker exec postgres psql -U dev_admin -d dev_database -c "VACUUM ANALYZE;"
```

### MySQL Recovery

```bash
# 1. Stop MySQL
docker compose stop mysql

# 2. Backup corrupted state
docker run --rm -v devstack-core_mysql-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/mysql-corrupted-$(date +%Y%m%d-%H%M%S).tar.gz /data

# 3. Remove volume
docker volume rm devstack-core_mysql-data

# 4. Start MySQL
docker compose start mysql
sleep 15

# 5. Restore
MYSQL_PASS=$(vault kv get -field=password secret/mysql)
docker exec -i mysql mysql -u dev_admin -p$MYSQL_PASS dev_database < \
  backups/mysql_backup_latest.sql

# 6. Verify
docker exec mysql mysql -u dev_admin -p$MYSQL_PASS dev_database -e \
  "CHECK TABLE users, sessions, logs;"
```

### MongoDB Recovery

```bash
# 1. Stop MongoDB
docker compose stop mongodb

# 2. Backup corrupted state
docker run --rm -v devstack-core_mongodb-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/mongodb-corrupted-$(date +%Y%m%d-%H%M%S).tar.gz /data

# 3. Remove volume
docker volume rm devstack-core_mongodb-data

# 4. Start MongoDB
docker compose start mongodb
sleep 10

# 5. Restore
MONGO_PASS=$(vault kv get -field=password secret/mongodb)
docker cp backups/mongodb_latest mongodb:/tmp/restore

docker exec mongodb mongorestore \
  --host localhost --port 27017 \
  --username dev_admin --password $MONGO_PASS \
  --authenticationDatabase admin \
  /tmp/restore

# 6. Verify
docker exec mongodb mongosh \
  "mongodb://dev_admin:$MONGO_PASS@localhost:27017/dev_database" \
  --eval "db.stats()"
```

---

## Network Issues

### Scenario 1: Docker Network Lost

```bash
# Symptoms: Services can't communicate
docker network ls | grep dev-services
# If missing:

# 1. Stop all services
./devstack.sh stop

# 2. Recreate network
docker network create --driver bridge --subnet 172.20.0.0/16 dev-services

# 3. Restart services
./devstack.sh start

# 4. Verify connectivity
docker exec reference-api ping -c 3 vault
docker exec reference-api ping -c 3 postgres
```

### Scenario 2: DNS Resolution Failing

```bash
# Test DNS
docker exec reference-api nslookup vault
docker exec reference-api nslookup postgres

# If failing, restart Docker DNS
docker compose restart

# Or restart Colima
colima restart
```

### Scenario 3: Port Conflicts

```bash
# Find conflicting processes
lsof -i :8200  # Vault
lsof -i :5432  # PostgreSQL
lsof -i :3306  # MySQL

# Kill conflicting process or change ports in .env
kill -9 <PID>

# Then restart
./devstack.sh restart
```

---

## Service-Specific Recovery

### Forgejo Git Server

```bash
# If Forgejo won't start
docker compose logs forgejo

# Common issues:
# 1. Database connection - verify PostgreSQL is healthy
# 2. Permission issues - check volume permissions
docker exec forgejo ls -la /data

# Restore Forgejo data
docker cp backups/forgejo/ forgejo:/data/
docker compose restart forgejo
```

### Redis Cluster

```bash
# If cluster is broken
docker exec redis-1 redis-cli -a $(vault kv get -field=password secret/redis-1) cluster info

# Reset cluster
docker compose stop redis-1 redis-2 redis-3
docker volume rm devstack-core_redis-1-data devstack-core_redis-2-data devstack-core_redis-3-data
docker compose up -d redis-1 redis-2 redis-3

# Reinitialize cluster
sleep 5
docker exec redis-1 redis-cli --cluster create \
  172.20.0.13:6379 172.20.0.16:6379 172.20.0.17:6379 \
  -a $(vault kv get -field=password secret/redis-1) \
  --cluster-replicas 0 --cluster-yes
```

### RabbitMQ

```bash
# If RabbitMQ won't start
docker compose logs rabbitmq

# Reset RabbitMQ
docker compose stop rabbitmq
docker volume rm devstack-core_rabbitmq-data
docker compose start rabbitmq

# Recreate vhost and user
RABBITMQ_PASS=$(vault kv get -field=password secret/rabbitmq)
docker exec rabbitmq rabbitmqctl add_vhost dev_vhost
docker exec rabbitmq rabbitmqctl set_permissions -p dev_vhost dev_admin ".*" ".*" ".*"
```

---

## Backup Procedures

### Automated Daily Backup

**Script:** `scripts/automated-backup.sh`

```bash
#!/bin/bash
# Automated backup script - run daily via cron

set -e

BACKUP_ROOT=~/devstack-core-backups
BACKUP_DIR=$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)

echo "Starting backup to $BACKUP_DIR"

mkdir -p $BACKUP_DIR

# 1. Vault keys (CRITICAL)
echo "Backing up Vault keys..."
cp -r ~/.config/vault $BACKUP_DIR/

# 2. Databases
echo "Backing up databases..."
cd ~/devstack-core
./devstack.sh backup
cp -r backups/ $BACKUP_DIR/

# 3. Configuration
echo "Backing up configuration..."
cp .env $BACKUP_DIR/
cp docker-compose.yml $BACKUP_DIR/
cp -r configs/ $BACKUP_DIR/

# 4. Create tarball
echo "Creating compressed archive..."
cd $BACKUP_ROOT
tar czf devstack-core-backup-$(date +%Y%m%d).tar.gz $(date +%Y%m%d-*)/

# 5. Retention: keep last 7 daily backups
echo "Cleaning old backups..."
find $BACKUP_ROOT -name "*.tar.gz" -mtime +7 -delete
find $BACKUP_ROOT -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

# 6. Verify backup
BACKUP_SIZE=$(du -sh $BACKUP_DIR | cut -f1)
echo "Backup complete: $BACKUP_SIZE"

# Optional: Copy to remote location
# rsync -avz $BACKUP_ROOT/ user@backup-server:/backups/devstack-core/
```

**Install cron job:**
```bash
# Make script executable
chmod +x scripts/automated-backup.sh

# Add to crontab (daily at 2 AM)
crontab -e
# Add line:
0 2 * * * /Users/gator/devstack-core/scripts/automated-backup.sh >> /Users/gator/colima-backup.log 2>&1
```

### Manual Backup

```bash
# Quick backup before making changes
./devstack.sh backup

# Full backup including configs
./scripts/automated-backup.sh
```

---

## Testing DR Procedures

**Test quarterly to ensure procedures work:**

```bash
# 1. Create test backup
./devstack.sh backup
cp -r ~/.config/vault ~/vault-test-backup

# 2. Stop environment
./devstack.sh stop

# 3. Simulate data loss
docker volume rm devstack-core_postgres-data

# 4. Follow recovery procedures
# (see "Database Corruption" section)

# 5. Verify recovery
./devstack.sh health
curl http://localhost:8000/health/all

# 6. Document any issues found
# Update this document with fixes
```

---

## Post-Recovery Checklist

After any disaster recovery, verify:

- [ ] Vault unsealed and accessible
- [ ] All services showing "healthy" status
- [ ] PostgreSQL accepting connections and data present
- [ ] MySQL accepting connections and data present
- [ ] MongoDB accepting connections and data present
- [ ] Redis cluster operational (all 3 nodes)
- [ ] RabbitMQ accepting connections
- [ ] Forgejo accessible and repositories present
- [ ] API endpoints responding correctly
- [ ] Vault secrets accessible
- [ ] Certificates valid and not expired
- [ ] Metrics collection working (Prometheus)
- [ ] Logs aggregating (Loki)
- [ ] Grafana dashboards displaying data
- [ ] No errors in service logs
- [ ] Performance within acceptable ranges

**Verification Script:**

```bash
#!/bin/bash
# Post-recovery verification

echo "=== Service Health ==="
./devstack.sh health

echo "\n=== API Health Check ==="
curl -s http://localhost:8000/health/all | jq '.services | to_entries[] | "\(.key): \(.value.status)"'

echo "\n=== Database Connectivity ==="
curl -s http://localhost:8000/examples/database/postgres/query | jq '.status'
curl -s http://localhost:8000/examples/database/mysql/query | jq '.status'
curl -s http://localhost:8000/examples/database/mongodb/query | jq '.status'

echo "\n=== Vault Integration ==="
curl -s http://localhost:8000/examples/vault/secret/postgres | jq '.status'

echo "\n=== Redis Cluster ==="
docker exec redis-1 redis-cli -a $(vault kv get -field=password secret/redis-1) cluster info | grep cluster_state

echo "\n=== Verification Complete ==="
```

---

## Emergency Contacts

| Role | Contact | Availability |
|------|---------|--------------|
| Infrastructure Owner | [Your Name/Email] | 24/7 |
| Backup System | ~/devstack-core-backups | Local |
| Off-site Backup | [Cloud storage location] | Always |
| Documentation | docs/DISASTER_RECOVERY.md | Always |

---

## Revision History

| Date | Version | Changes | Author |
|------|---------|---------|--------|
| 2025-10-29 | 1.0 | Initial disaster recovery runbook | System |

---

**Remember:** The best disaster recovery is prevention. Back up regularly, test procedures quarterly, and keep this document updated.
