# Service Profile Testing Checklist

This document provides a comprehensive testing checklist for validating service profiles in DevStack Core.

## Table of Contents

- [Overview](#overview)
- [Pre-Testing Requirements](#pre-testing-requirements)
- [Profile Testing Checklist](#profile-testing-checklist)
  - [Minimal Profile Tests](#minimal-profile-tests)
  - [Standard Profile Tests](#standard-profile-tests)
  - [Full Profile Tests](#full-profile-tests)
  - [Reference Profile Tests](#reference-profile-tests)
- [Profile Combination Tests](#profile-combination-tests)
- [Environment Override Tests](#environment-override-tests)
- [Python Management Script Tests](#python-management-script-tests)
- [Regression Tests](#regression-tests)
- [Performance Tests](#performance-tests)
- [Documentation Validation](#documentation-validation)

## Overview

This checklist ensures that all service profiles function correctly in isolation and in combination. Each profile must:
- Start only the intended services
- Load correct environment overrides
- Pass health checks
- Support intended use cases

## Pre-Testing Requirements

Before starting profile tests, ensure:

```bash
# 1. Clean environment
docker compose down -v
colima stop

# 2. Update to latest code
git pull origin main

# 3. Verify docker-compose.yml has profile labels
grep -A 2 "profiles:" docker-compose.yml | head -20

# 4. Verify profile .env files exist
ls -la configs/profiles/*.env

# 5. Verify Python dependencies installed
pip3 list | grep -E "click|rich|PyYAML|python-dotenv|docker"

# 6. Verify scripts are executable
ls -l devstack.py devstack.sh
```

## Profile Testing Checklist

### Minimal Profile Tests

**Purpose:** Verify minimal profile starts only essential services.

**Expected Services:** vault, postgres, pgbouncer, forgejo, redis-1 (5 total)

#### Test 1: List Services

```bash
# Verify service list
docker compose --profile minimal config --services

# Expected output (5 services):
# forgejo
# pgbouncer
# postgres
# redis-1
# vault
```

- [ ] Outputs exactly 5 services
- [ ] Includes vault, postgres, pgbouncer, forgejo, redis-1
- [ ] Does NOT include redis-2, redis-3, mysql, mongodb, rabbitmq, observability services

#### Test 2: Start Minimal Profile

```bash
# Start minimal profile
./devstack.py start --profile minimal
```

- [ ] Colima starts successfully
- [ ] Only 5 containers start
- [ ] No errors in startup output
- [ ] Command completes in < 3 minutes

#### Test 3: Verify Running Containers

```bash
# Check running containers
docker ps --format "{{.Names}}"
```

- [ ] Shows exactly 5 containers:
  - dev-vault
  - dev-postgres
  - dev-pgbouncer
  - dev-forgejo
  - dev-redis-1
- [ ] Does NOT show redis-2, redis-3, mysql, mongodb, rabbitmq, prometheus, grafana, loki

#### Test 4: Health Checks

```bash
# Check health status
./devstack.py health
```

- [ ] All 5 services show "healthy" or "no healthcheck"
- [ ] No services show "unhealthy" or "starting" (after 3 minutes)
- [ ] Colored output works correctly (green for healthy)

#### Test 5: Environment Overrides

```bash
# Verify Redis standalone mode
docker exec dev-redis-1 redis-cli -a "$(./devstack.sh vault-show-password redis-1 | grep Password | awk '{print $2}')" INFO replication | grep role

# Expected: role:master (standalone, not cluster)
```

- [ ] Redis is in standalone mode (not cluster)
- [ ] No cluster-related errors in redis logs
- [ ] PostgreSQL max connections = 50 (check logs: `docker logs dev-postgres 2>&1 | grep max_connections`)

#### Test 6: Service Functionality

```bash
# Test PostgreSQL connectivity
docker exec dev-postgres pg_isready -U dev_admin

# Test Redis connectivity
docker exec dev-redis-1 redis-cli -a "$(./devstack.sh vault-show-password redis-1 | grep Password | awk '{print $2}')" PING

# Test Forgejo accessibility
curl -s http://localhost:3000 | grep -i forgejo
```

- [ ] PostgreSQL responds with "accepting connections"
- [ ] Redis responds with "PONG"
- [ ] Forgejo web UI accessible

#### Test 7: Stop Minimal Profile

```bash
# Stop services
./devstack.py stop
```

- [ ] All containers stop
- [ ] Colima stops
- [ ] No errors in stop output

---

### Standard Profile Tests

**Purpose:** Verify standard profile starts full development stack with Redis cluster.

**Expected Services:** vault, postgres, pgbouncer, mysql, mongodb, redis-1, redis-2, redis-3, rabbitmq, forgejo (10 total)

#### Test 1: List Services

```bash
# Verify service list
docker compose --profile standard config --services | wc -l

# Expected: 10 services
```

- [ ] Outputs exactly 10 services
- [ ] Includes all minimal services + mysql, mongodb, redis-2, redis-3, rabbitmq
- [ ] Does NOT include prometheus, grafana, loki, vector, cadvisor, exporters

#### Test 2: Start Standard Profile

```bash
# Start standard profile
./devstack.py start --profile standard
```

- [ ] Colima starts successfully
- [ ] Exactly 10 containers start
- [ ] No errors in startup output
- [ ] Command completes in < 4 minutes

#### Test 3: Verify Running Containers

```bash
# Check running containers
docker ps --format "{{.Names}}" | wc -l

# Expected: 10 containers
```

- [ ] Shows exactly 10 containers
- [ ] Includes dev-redis-1, dev-redis-2, dev-redis-3
- [ ] Includes dev-mysql, dev-mongodb, dev-rabbitmq
- [ ] Does NOT show observability services

#### Test 4: Redis Cluster Initialization

```bash
# Initialize Redis cluster
./devstack.py redis-cluster-init
```

- [ ] Cluster initialization succeeds
- [ ] All 3 Redis nodes join cluster
- [ ] 16384 slots distributed
- [ ] No errors in output

#### Test 5: Verify Redis Cluster

```bash
# Check cluster status
docker exec dev-redis-1 redis-cli -c -a "$(./devstack.sh vault-show-password redis-1 | grep Password | awk '{print $2}')" CLUSTER INFO | grep cluster_state

# Expected: cluster_state:ok
```

- [ ] cluster_state:ok
- [ ] cluster_slots_assigned:16384
- [ ] cluster_known_nodes:3
- [ ] All nodes show as master in CLUSTER NODES output

#### Test 6: Environment Overrides

```bash
# Verify Redis cluster mode
docker exec dev-redis-1 redis-cli -a "$(./devstack.sh vault-show-password redis-1 | grep Password | awk '{print $2}')" INFO cluster | grep cluster_enabled

# Expected: cluster_enabled:1
```

- [ ] Redis cluster enabled (cluster_enabled:1)
- [ ] PostgreSQL max connections = 100
- [ ] MySQL max connections = 100
- [ ] ENABLE_METRICS=false

#### Test 7: Database Connectivity

```bash
# Test all databases
docker exec dev-postgres pg_isready -U dev_admin
docker exec dev-mysql mysqladmin -u dev_admin -p"$(./devstack.sh vault-show-password mysql | grep Password | awk '{print $2}')" ping
docker exec dev-mongodb mongosh --eval "db.adminCommand('ping')" --quiet
```

- [ ] PostgreSQL accepting connections
- [ ] MySQL responding to ping
- [ ] MongoDB responding to ping

#### Test 8: RabbitMQ Functionality

```bash
# Test RabbitMQ
curl -s http://localhost:15672 | grep -i rabbitmq
```

- [ ] RabbitMQ management UI accessible
- [ ] Can login with Vault credentials

#### Test 9: Stop Standard Profile

```bash
# Stop services
./devstack.py stop
```

- [ ] All containers stop
- [ ] Colima stops
- [ ] No errors

---

### Full Profile Tests

**Purpose:** Verify full profile starts complete suite with observability.

**Expected Services:** All standard services + prometheus, grafana, loki, vector, cadvisor, redis-exporter-1/2/3 (18 total)

#### Test 1: List Services

```bash
# Verify service list
docker compose --profile full config --services | wc -l

# Expected: 18 services
```

- [ ] Outputs exactly 18 services
- [ ] Includes all standard services
- [ ] Includes prometheus, grafana, loki, vector, cadvisor
- [ ] Includes redis-exporter-1, redis-exporter-2, redis-exporter-3

#### Test 2: Start Full Profile

```bash
# Start full profile
./devstack.py start --profile full
```

- [ ] Colima starts successfully
- [ ] Exactly 18 containers start
- [ ] No errors in startup output
- [ ] Command completes in < 6 minutes

#### Test 3: Verify Observability Services

```bash
# Check observability containers
docker ps --format "{{.Names}}" | grep -E "prometheus|grafana|loki|vector|cadvisor|exporter"
```

- [ ] dev-prometheus running
- [ ] dev-grafana running
- [ ] dev-loki running
- [ ] dev-vector running
- [ ] dev-cadvisor running
- [ ] dev-redis-exporter-1/2/3 running

#### Test 4: Prometheus Metrics Collection

```bash
# Check Prometheus targets
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'
```

- [ ] All targets showing "up" status
- [ ] Redis exporters collecting metrics
- [ ] cAdvisor collecting container metrics

#### Test 5: Grafana Access

```bash
# Test Grafana
curl -s http://localhost:3001/api/health | jq .database

# Expected: "ok"
```

- [ ] Grafana UI accessible
- [ ] Can login with admin/admin
- [ ] Prometheus datasource configured

#### Test 6: Loki Log Aggregation

```bash
# Check Loki
curl -s http://localhost:3100/ready

# Expected: "ready"
```

- [ ] Loki service healthy
- [ ] Accepting log streams from Vector

#### Test 7: Environment Overrides

```bash
# Verify observability enabled
docker logs dev-prometheus 2>&1 | grep "Server is ready"
```

- [ ] ENABLE_METRICS=true
- [ ] ENABLE_LOGS=true
- [ ] Prometheus scrape interval = 15s
- [ ] Loki retention period = 744h (31 days)

#### Test 8: Stop Full Profile

```bash
# Stop services
./devstack.py stop
```

- [ ] All containers stop
- [ ] Colima stops
- [ ] No errors

---

### Reference Profile Tests

**Purpose:** Verify reference profile starts educational API examples.

**Expected Services:** reference-api, api-first, golang-api, nodejs-api, rust-api (5 services, must combine with standard/full)

#### Test 1: Reference Profile Requires Base Profile

```bash
# Try starting reference alone (should fail or warn)
docker compose --profile reference config --services

# Should show only reference services, not infrastructure
```

- [ ] Reference profile lists only 5 services
- [ ] Does NOT include vault, postgres, redis, etc.
- [ ] Documentation warns to combine with standard/full

#### Test 2: Start Standard + Reference

```bash
# Start combined profiles
./devstack.py start --profile standard --profile reference
```

- [ ] Colima starts successfully
- [ ] 15 containers start (10 standard + 5 reference)
- [ ] No errors in startup output

#### Test 3: Verify Reference Apps Running

```bash
# Check reference containers
docker ps --format "{{.Names}}" | grep -E "reference-api|api-first|golang-api|nodejs-api|rust-api"
```

- [ ] dev-reference-api running (Python FastAPI code-first)
- [ ] dev-api-first running (Python FastAPI API-first)
- [ ] dev-golang-api running (Go Gin)
- [ ] dev-nodejs-api running (Node.js Express)
- [ ] dev-rust-api running (Rust Actix-web)

#### Test 4: Reference API Health Checks

```bash
# Test all reference APIs
curl -s http://localhost:8000/health | jq .status  # Python code-first
curl -s http://localhost:8001/health | jq .status  # Python API-first
curl -s http://localhost:8002/health | jq .status  # Go
curl -s http://localhost:8003/health | jq .status  # Node.js
curl -s http://localhost:8004/health | jq .status  # Rust
```

- [ ] All APIs respond with "healthy" status
- [ ] All APIs return JSON responses
- [ ] Response times < 200ms

#### Test 5: Reference API Documentation

```bash
# Test OpenAPI documentation
curl -s http://localhost:8000/docs | grep -i "swagger"  # Python code-first
curl -s http://localhost:8001/docs | grep -i "swagger"  # Python API-first
```

- [ ] FastAPI docs accessible at /docs
- [ ] OpenAPI spec accessible at /openapi.json

#### Test 6: Stop Combined Profiles

```bash
# Stop only reference profile services
./devstack.py stop --profile reference
```

- [ ] Only reference containers stop
- [ ] Standard profile services continue running
- [ ] Can restart reference profile without affecting standard

---

## Profile Combination Tests

### Test 1: Minimal Cannot Combine with Standard

```bash
# This should use standard (last profile wins)
./devstack.py start --profile minimal --profile standard
```

- [ ] Standard profile services start (not minimal)
- [ ] All 10 standard services running
- [ ] Documentation explains profile precedence

### Test 2: Standard + Reference Combination

```bash
# Start standard + reference
./devstack.py start --profile standard --profile reference
```

- [ ] 15 containers running (10 + 5)
- [ ] All infrastructure services available to reference apps
- [ ] Reference apps can connect to databases

### Test 3: Full + Reference Combination

```bash
# Start full + reference
./devstack.py start --profile full --profile reference
```

- [ ] 23 containers running (18 + 5)
- [ ] Observability services collecting reference app metrics
- [ ] All services healthy

### Test 4: Profile Switching

```bash
# Start with minimal
./devstack.py start --profile minimal

# Switch to standard (requires restart)
docker compose down
./devstack.py start --profile standard
```

- [ ] Old containers stop cleanly
- [ ] New profile starts without issues
- [ ] Data volumes preserved (if any)

---

## Environment Override Tests

### Test 1: Profile .env Loading

```bash
# Start standard profile and verify environment
./devstack.py start --profile standard

# Check if Redis cluster is enabled
docker exec dev-redis-1 redis-cli -a "$(./devstack.sh vault-show-password redis-1 | grep Password | awk '{print $2}')" INFO cluster | grep cluster_enabled
```

- [ ] Profile .env file loaded automatically
- [ ] REDIS_CLUSTER_ENABLED=true for standard
- [ ] REDIS_CLUSTER_ENABLED=false for minimal

### Test 2: Environment Variable Priority

```bash
# Set shell variable (should override profile .env)
export POSTGRES_MAX_CONNECTIONS=200

# Start standard profile
./devstack.py start --profile standard

# Verify shell variable takes precedence
docker logs dev-postgres 2>&1 | grep "max_connections = 200"
```

- [ ] Shell environment takes highest priority
- [ ] Profile .env is second priority
- [ ] Root .env is third priority
- [ ] docker-compose.yml defaults are lowest priority

### Test 3: Manual Profile .env Loading

```bash
# Load profile .env manually
set -a
source configs/profiles/standard.env
set +a

# Verify variables loaded
echo $REDIS_CLUSTER_ENABLED  # Should be "true"
```

- [ ] Profile .env can be loaded manually
- [ ] Variables export correctly
- [ ] Can use with docker compose directly

---

## Python Management Script Tests

### Test 1: Start Command

```bash
# Test start with various options
./devstack.py start --profile standard
./devstack.py start --profile minimal --no-detach  # Foreground
./devstack.py start --profile full
```

- [ ] --profile flag works correctly
- [ ] Multiple --profile flags accepted
- [ ] --detach/--no-detach flag works
- [ ] Colored output displays properly

### Test 2: Status Command

```bash
# Test status display
./devstack.py status
```

- [ ] Shows Colima status
- [ ] Lists all running containers
- [ ] Displays resource usage
- [ ] Formatted table output

### Test 3: Health Command

```bash
# Test health check
./devstack.py health
```

- [ ] Shows all running services
- [ ] Color-coded health status (green/yellow/red)
- [ ] Table format with columns: Service, Status, Health
- [ ] Accurate health information

### Test 4: Logs Command

```bash
# Test log viewing
./devstack.py logs postgres
./devstack.py logs --follow redis-1
./devstack.py logs --tail 50 vault
```

- [ ] Can view specific service logs
- [ ] --follow flag works (streaming)
- [ ] --tail flag limits output
- [ ] Logs display correctly

### Test 5: Shell Command

```bash
# Test interactive shell
./devstack.py shell postgres
# Inside shell: psql -U $POSTGRES_USER
```

- [ ] Opens shell in container
- [ ] Default shell (sh) works
- [ ] --shell bash option works
- [ ] Environment variables available

### Test 6: Profiles Command

```bash
# Test profile listing
./devstack.py profiles
```

- [ ] Lists all 4 profiles
- [ ] Shows service count
- [ ] Shows RAM estimate
- [ ] Shows description
- [ ] Formatted table output

### Test 7: IP Command

```bash
# Test IP display
./devstack.py ip
```

- [ ] Shows Colima VM IP address
- [ ] Format: xxx.xxx.xxx.xxx
- [ ] Works when Colima is running
- [ ] Error message when Colima stopped

### Test 8: Redis Cluster Init Command

```bash
# Test Redis cluster initialization
./devstack.py start --profile standard
./devstack.py redis-cluster-init
```

- [ ] Creates 3-node cluster
- [ ] Distributes 16384 slots
- [ ] Verifies cluster health
- [ ] Success message displayed

### Test 9: Stop Command

```bash
# Test stop variants
./devstack.py stop                    # Stop all
./devstack.py stop --profile reference  # Stop specific profile
```

- [ ] Stop all works (containers + Colima)
- [ ] Stop profile stops only profile services
- [ ] No errors in output
- [ ] Confirmation messages displayed

---

## Regression Tests

### Test 1: Bash Script Still Works

```bash
# Verify bash script functionality
./devstack.sh start
./devstack.sh status
./devstack.sh health
./devstack.sh stop
```

- [ ] Bash script starts all services (no profile support)
- [ ] All bash commands still functional
- [ ] No breaking changes
- [ ] Backward compatible

### Test 2: Existing Tests Pass

```bash
# Run existing test suites
./tests/run-all-tests.sh
```

- [ ] All 370+ tests pass
- [ ] No regressions in Vault tests
- [ ] No regressions in database tests
- [ ] No regressions in Redis cluster tests
- [ ] No regressions in reference app tests

### Test 3: Vault Operations

```bash
# Verify Vault still works
./devstack.sh vault-init
./devstack.sh vault-bootstrap
./devstack.sh vault-show-password postgres
```

- [ ] Vault init works
- [ ] Vault bootstrap works
- [ ] Credentials retrievable
- [ ] No profile-related issues

### Test 4: Manual Docker Compose

```bash
# Verify manual docker compose commands work
docker compose --profile standard up -d
docker compose --profile full ps
docker compose --profile minimal down
```

- [ ] Manual profile selection works
- [ ] Profile labels applied correctly
- [ ] No service dependency errors

---

## Performance Tests

### Test 1: Startup Time

```bash
# Measure startup times
time ./devstack.py start --profile minimal
time ./devstack.py start --profile standard
time ./devstack.py start --profile full
```

- [ ] Minimal: < 3 minutes
- [ ] Standard: < 4 minutes
- [ ] Full: < 6 minutes
- [ ] Reference: < 5 minutes (combined with standard)

### Test 2: Resource Usage

```bash
# Check resource consumption
docker stats --no-stream
```

- [ ] Minimal: ~2GB RAM
- [ ] Standard: ~4GB RAM
- [ ] Full: ~6GB RAM
- [ ] Reference: +1GB RAM

### Test 3: Health Check Times

```bash
# Measure time to healthy
./devstack.py start --profile standard
time until ./devstack.py health | grep -q "healthy"; do sleep 5; done
```

- [ ] All services healthy within 3 minutes
- [ ] No services stuck in "starting" state
- [ ] Health checks not failing repeatedly

---

## Documentation Validation

### Test 1: README Examples

```bash
# Verify README examples work
# Test each command from README.md Service Profiles section
```

- [ ] All README examples execute successfully
- [ ] Example output matches documentation
- [ ] No typos or incorrect commands

### Test 2: INSTALLATION Guide

```bash
# Follow INSTALLATION.md step-by-step
# Test both Python and Bash script paths
```

- [ ] Step 4.5 instructions work
- [ ] Step 5 Option A (Python) works
- [ ] Step 5 Option B (Bash) works
- [ ] Step 7.5 (Redis cluster init) works

### Test 3: SERVICE_PROFILES.md

```bash
# Verify all examples in SERVICE_PROFILES.md
```

- [ ] All profile examples work
- [ ] Use case scenarios accurate
- [ ] Quick start commands work
- [ ] Profile comparison table accurate

### Test 4: PYTHON_MANAGEMENT_SCRIPT.md

```bash
# Verify all command examples
```

- [ ] All command examples work
- [ ] Installation instructions work
- [ ] Troubleshooting tips accurate
- [ ] Command reference complete

---

## Summary Checklist

After completing all tests:

- [ ] All 4 profiles start successfully
- [ ] Profile combinations work correctly
- [ ] Environment overrides apply properly
- [ ] Python management script fully functional
- [ ] Bash script backward compatible
- [ ] All existing tests pass (no regressions)
- [ ] Performance meets expectations
- [ ] Documentation accurate and complete

## Reporting Issues

If any test fails:

1. **Document the failure:**
   - Which test failed
   - Error messages
   - Steps to reproduce
   - Environment details

2. **Check logs:**
   ```bash
   docker compose logs <service>
   colima logs
   ```

3. **Check GitHub issues:**
   - Search for similar issues
   - Check closed issues for solutions

4. **Open new issue if needed:**
   - Include test failure details
   - Include logs and error messages
   - Tag with "profiles" label

## Test Automation

For CI/CD, run automated tests:

```bash
# Automated profile testing script
./scripts/test-profiles.sh

# Expected: All tests pass
```

This checklist ensures comprehensive validation of service profiles functionality.
