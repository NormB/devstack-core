# Upgrade Guide

**Version:** 1.3.0
**Last Updated:** 2025-01-18

Complete guide for upgrading DevStack Core versions, service versions, and migrating between profiles.

---

## Table of Contents

- [Version Upgrade Paths](#version-upgrade-paths)
- [Service Version Upgrades](#service-version-upgrades)
- [Profile Migration](#profile-migration)
- [Database Migration Procedures](#database-migration-procedures)
- [Backward Compatibility](#backward-compatibility)
- [Rollback Procedures](#rollback-procedures)
- [Post-Upgrade Validation](#post-upgrade-validation)
- [Troubleshooting Common Issues](#troubleshooting-common-issues)

---

## Version Upgrade Paths

### v1.2.x → v1.3.0 (Current)

**Major Changes:**
- Introduction of service profiles (minimal, standard, full, reference)
- Python management CLI (devstack.py)
- Enhanced TLS certificate management
- 4-tier network segmentation
- AppRole authentication for all services

**Upgrade Steps:**

1. **Backup Current Environment**
   ```bash
   # Backup databases and Vault configuration
   ./devstack backup

   # Backup Vault keys and tokens
   cp -r ~/.config/vault ~/vault-backup-$(date +%Y%m%d)
   ```

2. **Stop All Services**
   ```bash
   ./devstack stop
   ```

3. **Update Repository**
   ```bash
   cd ~/devstack-core
   git fetch origin
   git checkout v1.3.0
   ```

4. **Update Dependencies**
   ```bash
   # Update Python dependencies (if using Python CLI)
   cd ~/devstack-core
   uv venv
   uv pip install -r scripts/requirements.txt
   ```

5. **Review Configuration Changes**
   ```bash
   # Compare .env files
   diff .env .env.example

   # Key new variables in v1.3.0:
   # - Profile-specific settings (configs/profiles/*.env)
   # - Network segmentation variables
   # - Enhanced TLS settings
   ```

6. **Choose Service Profile**
   ```bash
   # v1.2.x equivalent = standard profile
   # All services from v1.2.x = full profile

   # Start with standard profile (recommended)
   ./devstack start --profile standard
   ```

7. **Re-initialize Vault**
   ```bash
   # Vault keys preserved from backup, just unseal
   ./devstack vault-init
   ./devstack vault-bootstrap
   ```

8. **Re-initialize Redis Cluster** (if using standard/full)
   ```bash
   ./devstack redis-cluster-init
   ```

9. **Restore Databases** (optional)
   ```bash
   # List available backups
   ./devstack restore

   # Restore specific backup
   ./devstack restore 20250118_143022
   ```

10. **Verify Upgrade**
    ```bash
    # Run health checks
    ./devstack health

    # Check all services running
    docker compose ps

    # Verify Vault integration
    ./devstack vault-status
    ```

**Breaking Changes:**
- Service profile system requires explicit `--profile` flag
- Redis cluster now requires initialization script
- Network IPs changed with 4-tier segmentation (update firewall rules if accessing from other machines)

**Migration Time:** 20-30 minutes

---

### v1.1.x → v1.2.x

**Major Changes:**
- AppRole authentication introduced
- Enhanced observability stack
- PgBouncer connection pooling

**Upgrade Steps:**

1. Backup environment (see v1.2→v1.3 steps 1-2)
2. Update repository to v1.2.x tag
3. Review `.env.example` for new variables
4. Start services with `./devstack start`
5. Run AppRole setup: `./scripts/vault-bootstrap.sh`
6. Verify AppRole authentication working

**Migration Time:** 15-20 minutes

---

### v1.0.x → v1.1.x

**Major Changes:**
- Initial Vault integration
- TLS certificate automation
- Docker Compose v2 required

**Upgrade Steps:**

1. Update Docker Compose to v2+
2. Backup databases
3. Update repository
4. Initialize Vault for first time
5. Migrate credentials from .env to Vault

**Migration Time:** 30-45 minutes

---

## Service Version Upgrades

### PostgreSQL Upgrades

#### PostgreSQL 16 → PostgreSQL 18 (v1.3.0)

**Changes:**
- New statistics views (`pg_stat_io`, `pg_stat_wal`)
- Removed `pg_stat_bgwriter` (replaced with compatibility view)
- Enhanced monitoring capabilities

**Upgrade Procedure:**

1. **Backup PostgreSQL Data**
   ```bash
   ./devstack backup

   # Or manually
   docker exec dev-postgres pg_dumpall -U dev_admin > backup-pg16.sql
   ```

2. **Stop PostgreSQL**
   ```bash
   docker compose stop postgres pgbouncer forgejo
   ```

3. **Update docker-compose.yml**
   ```yaml
   postgres:
     image: postgres:18  # Was: postgres:16
   ```

4. **Remove Old Volume** (if clean upgrade desired)
   ```bash
   # WARNING: This deletes all data! Backup first!
   docker volume rm devstack-core_postgres_data
   ```

5. **Start PostgreSQL 18**
   ```bash
   docker compose up -d postgres
   ```

6. **Restore Data**
   ```bash
   # If using clean volume
   docker exec -i dev-postgres psql -U dev_admin < backup-pg16.sql

   # Or use automated restore
   ./devstack restore 20250118_143022
   ```

7. **Verify Compatibility View**
   ```bash
   docker exec dev-postgres psql -U dev_admin -d dev_database \
     -c "SELECT * FROM compat.pg_stat_bgwriter LIMIT 1;"
   ```

8. **Restart Dependent Services**
   ```bash
   docker compose up -d pgbouncer forgejo
   ```

**In-Place Upgrade** (preserve data):

```bash
# 1. Stop services
docker compose stop postgres pgbouncer forgejo

# 2. Backup volume
docker run --rm -v devstack-core_postgres_data:/data \
  -v $(pwd):/backup alpine tar czf /backup/postgres-data-backup.tar.gz /data

# 3. Run pg_upgrade (advanced - requires careful planning)
# See: https://www.postgresql.org/docs/18/pgupgrade.html

# 4. Update image and restart
docker compose up -d postgres
```

**Rollback Procedure:**
```bash
# Restore from backup
docker compose down postgres
docker volume rm devstack-core_postgres_data
docker compose up -d postgres
docker exec -i dev-postgres psql -U dev_admin < backup-pg16.sql
```

**Time Estimate:** 10-15 minutes (dump/restore), 30-60 minutes (in-place upgrade)

---

#### PostgreSQL 18 → PostgreSQL 19 (future)

**Preparation Steps:**
1. Review PostgreSQL 19 release notes
2. Test migration in separate environment
3. Update compatibility views if needed
4. Follow same backup/restore procedure

---

### MySQL Upgrades

#### MySQL 8.0.38 → MySQL 8.0.40

**Changes:**
- Security updates
- Bug fixes
- Minor performance improvements

**Upgrade Procedure:**

1. **Backup MySQL Data**
   ```bash
   docker exec dev-mysql mysqldump -u root -p$(./devstack vault-show-password mysql) \
     --all-databases > backup-mysql-8.0.38.sql
   ```

2. **Stop MySQL**
   ```bash
   docker compose stop mysql
   ```

3. **Update Image**
   ```yaml
   mysql:
     image: mysql:8.0.40  # Was: mysql:8.0.38
   ```

4. **Start MySQL**
   ```bash
   docker compose up -d mysql
   ```

5. **Run mysql_upgrade** (automatic in 8.0+)
   ```bash
   docker exec dev-mysql mysql_upgrade -u root -p$(./devstack vault-show-password mysql)
   ```

6. **Verify Version**
   ```bash
   docker exec dev-mysql mysql -u root -p$(./devstack vault-show-password mysql) \
     -e "SELECT VERSION();"
   ```

**Rollback:**
```bash
docker compose down mysql
docker volume rm devstack-core_mysql_data
# Update to old version, restart, restore backup
```

**Time Estimate:** 5-10 minutes

---

### Redis Upgrades

#### Redis 7.2 → Redis 7.4

**Changes:**
- Cluster improvements
- Performance enhancements
- New commands and features

**Upgrade Procedure:**

1. **Backup Redis Data**
   ```bash
   # For each node
   for i in 1 2 3; do
     docker exec dev-redis-$i redis-cli -a $REDIS_PASSWORD --rdb /data/dump-backup.rdb
     docker cp dev-redis-$i:/data/dump-backup.rdb redis-$i-backup.rdb
   done
   ```

2. **Update Image** (rolling upgrade for zero downtime)
   ```bash
   # Node by node
   docker compose stop redis-1
   # Update docker-compose.yml: redis:7.4-alpine
   docker compose up -d redis-1

   # Wait for rejoin
   docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster info

   # Repeat for redis-2, redis-3
   ```

3. **Verify Cluster Health**
   ```bash
   docker exec dev-redis-1 redis-cli --cluster check 172.20.2.13:6379 -a $REDIS_PASSWORD
   ```

**Full Cluster Restart** (simpler but brief downtime):
```bash
docker compose stop redis-1 redis-2 redis-3
# Update all images
docker compose up -d redis-1 redis-2 redis-3
./devstack redis-cluster-init  # Re-initialize if needed
```

**Time Estimate:** 5-10 minutes (rolling), 2-3 minutes (full restart)

---

### MongoDB Upgrades

#### MongoDB 7.0 → MongoDB 7.2

**Upgrade Procedure:**

1. **Backup MongoDB**
   ```bash
   docker exec dev-mongodb mongodump --username dev_admin \
     --password $(./devstack vault-show-password mongodb) \
     --authenticationDatabase admin --out /backup

   docker cp dev-mongodb:/backup ./mongodb-backup
   ```

2. **Check Feature Compatibility Version**
   ```bash
   docker exec dev-mongodb mongosh --username dev_admin \
     --password $(./devstack vault-show-password mongodb) \
     --eval "db.adminCommand({getParameter: 1, featureCompatibilityVersion: 1})"
   ```

3. **Stop MongoDB**
   ```bash
   docker compose stop mongodb
   ```

4. **Update Image**
   ```yaml
   mongodb:
     image: mongo:7.2  # Was: mongo:7.0
   ```

5. **Start MongoDB**
   ```bash
   docker compose up -d mongodb
   ```

6. **Set Feature Compatibility Version**
   ```bash
   docker exec dev-mongodb mongosh --username dev_admin \
     --password $(./devstack vault-show-password mongodb) \
     --eval "db.adminCommand({setFeatureCompatibilityVersion: '7.2'})"
   ```

**Time Estimate:** 10-15 minutes

---

### RabbitMQ Upgrades

#### RabbitMQ 3.12 → RabbitMQ 3.13

**Upgrade Procedure:**

1. **Backup Definitions**
   ```bash
   curl -u dev_admin:$RABBITMQ_PASSWORD \
     http://localhost:15672/api/definitions > rabbitmq-definitions.json
   ```

2. **Stop RabbitMQ**
   ```bash
   docker compose stop rabbitmq
   ```

3. **Update Image**
   ```yaml
   rabbitmq:
     image: rabbitmq:3.13-management-alpine
   ```

4. **Start RabbitMQ**
   ```bash
   docker compose up -d rabbitmq
   ```

5. **Verify Version**
   ```bash
   docker exec dev-rabbitmq rabbitmqctl version
   ```

6. **Restore Definitions** (if needed)
   ```bash
   curl -u dev_admin:$RABBITMQ_PASSWORD -H "Content-Type: application/json" \
     -X POST -d @rabbitmq-definitions.json http://localhost:15672/api/definitions
   ```

**Time Estimate:** 5-10 minutes

---

## Profile Migration

### Migrating Between Profiles

#### From No Profile → Minimal Profile

**Scenario:** First-time v1.3.0 setup

```bash
# Start minimal services only
./devstack start --profile minimal

# Initialize Vault
./devstack vault-init
./devstack vault-bootstrap

# Initialize Forgejo
./devstack forgejo-init
```

**What's Included:** Vault, PostgreSQL, PgBouncer, Forgejo, Redis (standalone)

**What's Excluded:** MySQL, MongoDB, RabbitMQ, Redis cluster, Observability

---

#### Minimal → Standard Profile

**Scenario:** Need Redis cluster, MySQL, MongoDB, RabbitMQ

**Upgrade Steps:**

1. **Stop Current Services**
   ```bash
   docker compose down
   ```

2. **Start with Standard Profile**
   ```bash
   ./devstack start --profile standard
   ```

3. **Initialize Redis Cluster**
   ```bash
   ./devstack redis-cluster-init
   ```

4. **Verify New Services**
   ```bash
   docker compose ps | grep -E '(mysql|mongodb|rabbitmq|redis-[23])'
   ```

5. **Test Connectivity**
   ```bash
   # MySQL
   mysql -h 127.0.0.1 -u dev_admin -p

   # MongoDB
   mongosh --host localhost --port 27017 -u dev_admin

   # RabbitMQ
   curl http://localhost:15672

   # Redis cluster
   redis-cli -c -h localhost -p 6379 cluster nodes
   ```

**Data Preservation:** PostgreSQL and Forgejo data preserved (volumes persist)

**Time Estimate:** 5-10 minutes

---

#### Standard → Full Profile

**Scenario:** Add observability stack (Prometheus, Grafana, Loki)

**Upgrade Steps:**

1. **Start Full Profile** (keeps existing services running)
   ```bash
   docker compose --profile full up -d
   ```

2. **Verify Observability Services**
   ```bash
   docker compose ps | grep -E '(prometheus|grafana|loki|vector)'
   ```

3. **Access Dashboards**
   ```bash
   # Prometheus
   open http://localhost:9090

   # Grafana (admin/admin)
   open http://localhost:3001

   # Loki (via Grafana)
   # Add Loki data source in Grafana
   ```

4. **Import Grafana Dashboards**
   ```bash
   # Dashboards located in configs/grafana/dashboards/
   # Auto-imported on first start
   ```

**Additional Resources:** +2GB RAM, +2 CPU cores recommended

**Time Estimate:** 5-10 minutes

---

#### Full → Standard Profile (Downgrade)

**Scenario:** Reduce resource usage, remove observability

```bash
# Stop all services
docker compose down

# Remove observability volumes (optional)
docker volume rm devstack-core_prometheus_data
docker volume rm devstack-core_grafana_data
docker volume rm devstack-core_loki_data

# Start with standard profile
docker compose --profile standard up -d
```

**Data Preservation:** Metrics and logs deleted, core data preserved

**Time Estimate:** 3-5 minutes

---

#### Adding Reference Apps to Any Profile

**Scenario:** Learn API patterns alongside existing infrastructure

```bash
# Combine reference profile with standard
./devstack start --profile standard --profile reference

# Or with full
docker compose --profile full --profile reference up -d
```

**Additional Resources:** +1GB RAM, +1 CPU core

**Time Estimate:** 2-5 minutes

---

## Database Migration Procedures

### Migrating PostgreSQL Data Between Versions

**Scenario:** Moving data from old version to new version

**Method 1: pg_dump/pg_restore (Recommended)**

```bash
# 1. Dump from old version
docker exec dev-postgres pg_dump -U dev_admin -F c -f /tmp/backup.dump dev_database

# 2. Copy to host
docker cp dev-postgres:/tmp/backup.dump ./postgres-backup.dump

# 3. Stop services and update version
docker compose down postgres
# Update docker-compose.yml

# 4. Start new version
docker compose up -d postgres

# 5. Restore
docker cp ./postgres-backup.dump dev-postgres:/tmp/backup.dump
docker exec dev-postgres pg_restore -U dev_admin -d dev_database /tmp/backup.dump
```

**Method 2: Logical Replication (Advanced)**

For large databases, use PostgreSQL logical replication for minimal downtime.

---

### Migrating MySQL Data Between Versions

```bash
# Export
docker exec dev-mysql mysqldump -u root -p$MYSQL_ROOT_PASSWORD \
  --all-databases --single-transaction > mysql-backup.sql

# Import to new version
docker exec -i dev-mysql mysql -u root -p$MYSQL_ROOT_PASSWORD < mysql-backup.sql
```

---

### Migrating MongoDB Data Between Versions

```bash
# Export
docker exec dev-mongodb mongodump --username dev_admin \
  --password $MONGODB_PASSWORD --authenticationDatabase admin \
  --out /backup

docker cp dev-mongodb:/backup ./mongodb-backup

# Import to new version
docker cp ./mongodb-backup dev-mongodb:/backup
docker exec dev-mongodb mongorestore --username dev_admin \
  --password $MONGODB_PASSWORD --authenticationDatabase admin \
  /backup
```

---

### Migrating Redis Data Between Versions

**Method 1: RDB Snapshot**

```bash
# Save snapshot
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD SAVE

# Copy RDB file
docker cp dev-redis-1:/data/dump.rdb ./redis-backup.rdb

# Restore to new version
docker cp ./redis-backup.rdb dev-redis-1:/data/dump.rdb
docker compose restart redis-1
```

**Method 2: AOF (Append-Only File)**

Redis cluster uses AOF by default - data automatically persisted.

---

## Backward Compatibility

### API Compatibility

**v1.3.0 Compatibility:**
- ✅ Docker Compose v2+ required (not compatible with v1.x)
- ✅ Colima v0.5.0+ recommended
- ✅ macOS 12+ (Apple Silicon)
- ✅ Vault API v1 (stable)
- ❌ Not compatible with v1.1.x `.env` format (migration required)

### Configuration Compatibility

**Breaking Changes in v1.3.0:**
- Profile system requires `--profile` flag (no default profile)
- Network IP ranges changed (172.20.x.x scheme)
- Vault paths restructured (`secret/data/` → `secret/`)

**Maintaining Compatibility:**
```bash
# Old v1.2.x command
./devstack start

# New v1.3.0 command (requires profile)
./devstack start --profile standard
```

### Data Format Compatibility

**Database Schemas:** All versions maintain backward-compatible schemas

**Vault Secret Format:** Compatible across all v1.x versions

---

## Rollback Procedures

### Complete Version Rollback (v1.3 → v1.2)

**Scenario:** Upgrade failed, need to return to previous version

**Steps:**

1. **Stop All Services**
   ```bash
   docker compose down
   ```

2. **Restore Vault Backup**
   ```bash
   rm -rf ~/.config/vault
   cp -r ~/vault-backup-20250118 ~/.config/vault
   ```

3. **Revert Repository**
   ```bash
   cd ~/devstack-core
   git checkout v1.2.9  # Or your previous version
   ```

4. **Start Services (Old Method)**
   ```bash
   ./devstack start  # No profile flag in v1.2
   ```

5. **Restore Database Backups**
   ```bash
   ./devstack restore 20250118_120000  # Pre-upgrade backup
   ```

6. **Verify Services**
   ```bash
   ./devstack health
   docker compose ps
   ```

**Time Estimate:** 15-20 minutes

**Data Loss:** Any changes made after backup creation will be lost

---

### Service-Specific Rollback

**PostgreSQL Version Rollback:**

```bash
docker compose stop postgres pgbouncer forgejo
# Update docker-compose.yml to old version
docker compose up -d postgres
docker exec -i dev-postgres psql -U dev_admin < backup-pg16.sql
docker compose up -d pgbouncer forgejo
```

**Redis Cluster Rollback:**

```bash
docker compose stop redis-1 redis-2 redis-3
# Update to old version
docker compose up -d redis-1 redis-2 redis-3
./devstack redis-cluster-init
```

---

### Profile Rollback (Full → Standard → Minimal)

**No data loss** - simply stop services and restart with lower profile:

```bash
docker compose down
docker compose --profile minimal up -d
```

---

## Post-Upgrade Validation

### Validation Checklist

**1. Service Health**
```bash
# Overall health
./devstack health

# Individual service checks
docker compose ps
docker exec dev-postgres pg_isready
docker exec dev-mysql mysqladmin ping
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD ping
```

**2. Vault Integration**
```bash
# Vault status
./devstack vault-status

# Fetch secrets
./devstack vault-show-password postgres
./devstack vault-show-password mysql
./devstack vault-show-password mongodb
./devstack vault-show-password redis-1
./devstack vault-show-password rabbitmq
```

**3. Database Connectivity**
```bash
# PostgreSQL
psql -h localhost -p 5432 -U dev_admin -d dev_database -c "SELECT version();"

# MySQL
mysql -h 127.0.0.1 -u dev_admin -p -e "SELECT VERSION();"

# MongoDB
mongosh --host localhost --port 27017 -u dev_admin -e "db.version()"
```

**4. Redis Cluster**
```bash
# Cluster status
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster info

# Slot coverage
docker exec dev-redis-1 redis-cli --cluster check 172.20.2.13:6379 -a $REDIS_PASSWORD

# Test operations
redis-cli -c -a $REDIS_PASSWORD SET test:key "hello"
redis-cli -c -a $REDIS_PASSWORD GET test:key
```

**5. Network Connectivity**
```bash
# Service-to-service communication
docker exec dev-reference-api curl -s http://postgres:5432 || echo "Connection works"
docker exec dev-reference-api curl -s http://redis-1:6379 || echo "Connection works"
```

**6. Observability Stack** (if full profile)
```bash
# Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[].health'

# Grafana health
curl -s http://localhost:3001/api/health | jq .

# Loki ready
curl -s http://localhost:3100/ready
```

**7. Reference APIs** (if reference profile)
```bash
# Health checks
curl http://localhost:8000/health  # Python FastAPI
curl http://localhost:8001/health  # Python API-first
curl http://localhost:8002/health  # Go
curl http://localhost:8003/health  # Node.js
curl http://localhost:8004/health  # Rust
```

**8. TLS Certificates** (if TLS enabled)
```bash
# Check certificate validity
ls -la ~/.config/vault/certs/postgres/
openssl x509 -in ~/.config/vault/certs/postgres/postgres.crt -text -noout | grep "Not After"
```

---

### Automated Validation Script

```bash
#!/bin/bash
# post-upgrade-validation.sh

echo "Running post-upgrade validation..."

# 1. Service health
./devstack health || exit 1

# 2. Vault status
./devstack vault-status || exit 1

# 3. Database connectivity
psql -h localhost -p 5432 -U dev_admin -d dev_database -c "SELECT 1;" || exit 1
mysql -h 127.0.0.1 -u dev_admin -p$(./devstack vault-show-password mysql) -e "SELECT 1;" || exit 1

# 4. Redis cluster
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster info | grep "cluster_state:ok" || exit 1

# 5. Run test suite
cd ~/devstack-core/tests
./run-all-tests.sh || exit 1

echo "✅ All validation checks passed!"
```

---

## Troubleshooting Common Issues

### Issue: Services Won't Start After Upgrade

**Symptoms:**
- Docker containers exit immediately
- Health checks failing
- "Connection refused" errors

**Solutions:**

1. **Check Docker Compose Version**
   ```bash
   docker compose version
   # Must be v2.0+
   ```

2. **Clear Old Containers**
   ```bash
   docker compose down --remove-orphans
   docker system prune -f
   ```

3. **Reset Networks**
   ```bash
   docker network prune -f
   docker compose up -d
   ```

4. **Check Resource Limits**
   ```bash
   colima status
   # Ensure adequate CPU/memory allocated
   ```

---

### Issue: Vault Won't Unseal

**Symptoms:**
- Services waiting for Vault
- "Vault is sealed" errors

**Solutions:**

1. **Verify Unseal Keys**
   ```bash
   ls -la ~/.config/vault/keys.json
   cat ~/.config/vault/keys.json | jq '.unseal_keys_b64'
   ```

2. **Manual Unseal**
   ```bash
   export VAULT_ADDR=http://localhost:8200
   vault operator unseal <key1>
   vault operator unseal <key2>
   vault operator unseal <key3>
   ```

3. **Check Auto-Unseal Script**
   ```bash
   docker exec dev-vault ps aux | grep unseal
   docker logs dev-vault | grep -i unseal
   ```

---

### Issue: Redis Cluster Not Forming

**Symptoms:**
- Cluster state: fail
- CLUSTERDOWN errors

**Solutions:**

1. **Re-initialize Cluster**
   ```bash
   ./devstack redis-cluster-init
   ```

2. **Manual Cluster Creation**
   ```bash
   docker exec dev-redis-1 redis-cli --cluster create \
     172.20.2.13:6379 172.20.2.16:6379 172.20.2.17:6379 \
     --cluster-yes -a $REDIS_PASSWORD
   ```

3. **Check Node Connectivity**
   ```bash
   for i in 1 2 3; do
     docker exec dev-redis-$i redis-cli -a $REDIS_PASSWORD ping
   done
   ```

---

### Issue: Database Migration Failed

**Symptoms:**
- Data missing after upgrade
- Schema version mismatch errors

**Solutions:**

1. **Restore from Backup**
   ```bash
   ./devstack restore <timestamp>
   ```

2. **Check Backup Integrity**
   ```bash
   # PostgreSQL
   pg_restore --list backup.dump

   # MySQL
   head -50 backup.sql
   ```

3. **Manual Migration**
   ```bash
   # Review migration scripts
   ls configs/postgres/*.sql

   # Apply manually if needed
   psql -h localhost -U dev_admin -d dev_database -f migration.sql
   ```

---

### Issue: Profile Not Starting Correctly

**Symptoms:**
- Wrong services running
- Missing expected services

**Solutions:**

1. **Verify Profile Flag**
   ```bash
   docker compose --profile standard config
   # Shows expanded configuration
   ```

2. **Check Service Profiles**
   ```bash
   grep -A 1 "profiles:" docker-compose.yml | head -20
   ```

3. **Explicit Profile Start**
   ```bash
   docker compose down
   docker compose --profile standard up -d
   ```

---

### Issue: Performance Degradation After Upgrade

**Symptoms:**
- Slow queries
- High CPU usage
- Memory pressure

**Solutions:**

1. **Review Resource Allocation**
   ```bash
   docker stats
   colima status
   ```

2. **Adjust Profile**
   ```bash
   # Downgrade from full to standard if needed
   docker compose down
   docker compose --profile standard up -d
   ```

3. **Optimize Database Settings**
   ```bash
   # PostgreSQL
   docker exec dev-postgres psql -U dev_admin -c "VACUUM ANALYZE;"

   # MySQL
   docker exec dev-mysql mysql -u root -p -e "OPTIMIZE TABLE tablename;"
   ```

---

## Related Documentation

- [DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md) - Complete environment recovery
- [ROLLBACK_PROCEDURES.md](./ROLLBACK_PROCEDURES.md) - Detailed rollback steps
- [SERVICE_PROFILES.md](./SERVICE_PROFILES.md) - Profile system documentation
- [INSTALLATION.md](./INSTALLATION.md) - Fresh installation guide
- [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) - General troubleshooting

---

## Need Help?

- Check [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues
- Review [GitHub Issues](https://github.com/yourusername/devstack-core/issues)
- Consult service-specific documentation in `docs/`
