# PgBouncer Usage

Comprehensive guide to using PgBouncer connection pooler for PostgreSQL in the DevStack Core environment.

## Table of Contents

- [Overview](#overview)
- [What is PgBouncer](#what-is-pgbouncer)
  - [Benefits of Connection Pooling](#benefits-of-connection-pooling)
  - [When to Use PgBouncer](#when-to-use-pgbouncer)
  - [When to Use Direct Connections](#when-to-use-direct-connections)
- [Pool Modes](#pool-modes)
  - [Transaction Mode](#transaction-mode)
  - [Session Mode](#session-mode)
  - [Statement Mode](#statement-mode)
  - [Choosing the Right Mode](#choosing-the-right-mode)
- [Configuration](#configuration)
  - [PgBouncer Configuration File](#pgbouncer-configuration-file)
  - [Pool Size Tuning](#pool-size-tuning)
  - [Connection Limits](#connection-limits)
  - [Timeouts](#timeouts)
  - [Authentication](#authentication)
- [Connection Patterns](#connection-patterns)
  - [Connecting Through PgBouncer](#connecting-through-pgbouncer)
  - [Application Configuration](#application-configuration)
  - [Connection Strings](#connection-strings)
  - [Testing Connections](#testing-connections)
- [Performance Benefits](#performance-benefits)
  - [Reduced Connection Overhead](#reduced-connection-overhead)
  - [Better Resource Utilization](#better-resource-utilization)
  - [Connection Reuse](#connection-reuse)
  - [Performance Metrics](#performance-metrics)
- [Limitations](#limitations)
  - [Session-Level Features](#session-level-features)
  - [Prepared Statements](#prepared-statements)
  - [Temporary Tables](#temporary-tables)
  - [Advisory Locks](#advisory-locks)
- [Monitoring](#monitoring)
  - [PgBouncer Statistics](#pgbouncer-statistics)
  - [SHOW Commands](#show-commands)
  - [Connection Pool Status](#connection-pool-status)
  - [Performance Monitoring](#performance-monitoring)
- [Troubleshooting](#troubleshooting)
  - [Connection Refused](#connection-refused)
  - [Pool Exhaustion](#pool-exhaustion)
  - [Authentication Issues](#authentication-issues)
  - [Slow Queries](#slow-queries)
  - [Transaction Rollback Issues](#transaction-rollback-issues)
- [Migration](#migration)
  - [Moving from Direct PostgreSQL](#moving-from-direct-postgresql)
  - [Testing Migration](#testing-migration)
  - [Rollback Plan](#rollback-plan)
- [Advanced Configuration](#advanced-configuration)
  - [Multiple Database Pools](#multiple-database-pools)
  - [Per-Database Settings](#per-database-settings)
  - [Load Balancing](#load-balancing)
  - [SSL/TLS Configuration](#ssltls-configuration)
- [Best Practices](#best-practices)
- [Reference](#reference)

## Overview

PgBouncer is a lightweight connection pooler for PostgreSQL that significantly improves application performance and scalability by reusing database connections.

**Key Information:**
- **Container Name:** `dev-pgbouncer`
- **Host Port:** 6432
- **Network IP:** 172.20.0.11
- **Backend:** Connects to PostgreSQL at 172.20.0.10:5432
- **Configuration:** `/configs/pgbouncer/pgbouncer.ini`
- **Default Pool Mode:** Transaction (most efficient)
- **Credentials:** Same as PostgreSQL (stored in Vault at `secret/postgres`)

**Related Pages:**
- [PostgreSQL Operations](PostgreSQL-Operations) - PostgreSQL management
- [Service Configuration](Service-Configuration) - PgBouncer service details
- [Performance Tuning](Performance-Tuning) - Advanced optimization
- [Backup and Restore](Backup-and-Restore) - Backup strategies

## What is PgBouncer

PgBouncer is a connection pooler that sits between your application and PostgreSQL. It maintains a pool of connections to PostgreSQL and multiplexes client connections through this pool.

**Architecture:**

```
Application (port 6432) → PgBouncer → PostgreSQL (port 5432)
100 client connections    20 pooled   20 actual connections
```

### Benefits of Connection Pooling

1. **Reduced Connection Overhead:**
   - Creating PostgreSQL connections is expensive (fork process, allocate memory)
   - PgBouncer reuses connections, eliminating this overhead
   - Connection creation time: ~5-10ms → ~0.1ms with PgBouncer

2. **Better Resource Utilization:**
   - PostgreSQL has limited connections (default: 100, configurable)
   - Each PostgreSQL connection consumes ~10MB memory
   - PgBouncer allows 1000s of client connections with 10s of server connections

3. **Improved Scalability:**
   - Handle more concurrent clients without overwhelming PostgreSQL
   - Prevents "too many connections" errors
   - Smooth traffic spikes without database overload

4. **Lower Memory Usage:**
   - 100 direct connections: ~1GB memory (PostgreSQL)
   - 100 client connections → 20 pooled connections: ~200MB memory

### When to Use PgBouncer

**Recommended for:**
- Web applications with short-lived transactions
- Microservices with many concurrent connections
- Applications with connection spikes
- Environments with limited PostgreSQL connection capacity
- REST APIs with frequent requests
- Lambda/serverless functions

**Example Scenario:**
```
Web app with 500 concurrent users
├── Without PgBouncer: 500 PostgreSQL connections (unsustainable)
└── With PgBouncer: 500 client → 20 pooled → 20 PostgreSQL connections
```

### When to Use Direct Connections

**Direct connections preferred for:**
- Long-running analytical queries
- Database administration tasks
- Applications using prepared statements extensively
- Applications requiring advisory locks
- Applications using temporary tables across transactions
- LISTEN/NOTIFY subscriptions
- Database migrations (schema changes)

## Pool Modes

PgBouncer supports three pool modes. The mode determines when connections are returned to the pool.

### Transaction Mode

**Default mode. Connection returned after transaction completes.**

```ini
# pgbouncer.ini
pool_mode = transaction
```

**How it works:**
```sql
-- Client 1 starts
BEGIN;
SELECT * FROM users WHERE id = 1;
UPDATE users SET last_login = NOW() WHERE id = 1;
COMMIT;
-- Connection returned to pool immediately

-- Client 2 can now use the same connection
SELECT * FROM products;
```

**Characteristics:**
- Most efficient mode (best connection reuse)
- Connection released after `COMMIT` or `ROLLBACK`
- Cannot use session-level features (temp tables, prepared statements)
- **Recommended for:** Web applications, REST APIs, microservices

**Limitations:**
- No prepared statements across transactions
- No temporary tables across transactions
- No `SET` statements persisting across transactions
- No advisory locks

### Session Mode

**Connection returned when client disconnects.**

```ini
# pgbouncer.ini
pool_mode = session
```

**How it works:**
```sql
-- Client 1 connects
CREATE TEMP TABLE my_temp (id INT);
INSERT INTO my_temp VALUES (1);

SELECT * FROM my_temp;  -- Works
-- Connection held until client disconnects

-- Temp table persists for entire session
```

**Characteristics:**
- Connection held for entire client session
- All PostgreSQL features available
- Less efficient (lower connection reuse)
- **Recommended for:** Long-running connections, administrative tools

**Use cases:**
- Database administration (psql sessions)
- Applications using prepared statements
- Applications using temporary tables
- Applications requiring advisory locks

### Statement Mode

**Connection returned after each statement. Most aggressive pooling.**

```ini
# pgbouncer.ini
pool_mode = statement
```

**How it works:**
```sql
-- Each statement uses a different connection
SELECT * FROM users WHERE id = 1;  -- Connection A
SELECT * FROM orders WHERE user_id = 1;  -- Connection B (different!)
```

**Characteristics:**
- Highest connection reuse
- Cannot use transactions (multi-statement transactions break)
- Rarely used in practice
- **Recommended for:** Auto-commit only applications (rare)

**⚠️ WARNING:** Statement mode breaks transactions. Use transaction mode instead.

### Choosing the Right Mode

| Use Case | Recommended Mode | Reason |
|----------|------------------|--------|
| Web applications | Transaction | Best performance, handles transactions |
| REST APIs | Transaction | Short-lived requests, good reuse |
| Microservices | Transaction | Efficient pooling, stateless |
| Background jobs | Transaction | Good balance of features/performance |
| Admin tools (psql) | Session | Need full PostgreSQL features |
| ORMs (SQLAlchemy, Django) | Transaction | Works well with ORM patterns |
| Analytical queries | Session (or direct) | Long-running queries |
| Database migrations | Session (or direct) | Schema changes, DDL statements |

**Default recommendation: Transaction mode for 95% of applications.**

## Configuration

### PgBouncer Configuration File

PgBouncer configuration is at `/configs/pgbouncer/pgbouncer.ini` in the repository.

```bash
# View current configuration
docker exec dev-pgbouncer cat /etc/pgbouncer/pgbouncer.ini

# Edit configuration (requires restart)
nano /Users/gator/devstack-core/configs/pgbouncer/pgbouncer.ini
docker restart dev-pgbouncer
```

**Key Configuration Sections:**

```ini
[databases]
# Database definitions
* = host=postgres port=5432 dbname=postgres

[pgbouncer]
# Pool mode
pool_mode = transaction

# Connection limits
max_client_conn = 1000
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5
max_db_connections = 50

# Timeouts
server_idle_timeout = 600
query_timeout = 0
client_idle_timeout = 0

# Authentication
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Logging
admin_users = postgres
stats_users = postgres
```

### Pool Size Tuning

**default_pool_size:** Number of connections per database per user.

```ini
# Small pool (low traffic)
default_pool_size = 10

# Medium pool (moderate traffic)
default_pool_size = 20

# Large pool (high traffic)
default_pool_size = 50
```

**Formula for sizing:**

```
Recommended pool size = (Number of CPU cores) * 2-4
Example: 4 cores → 8-16 connections

Consider:
- Average query duration
- Concurrent request rate
- PostgreSQL max_connections limit
```

**Monitoring pool usage:**

```bash
# Check if pool is saturated
docker exec -it dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"

# Look for:
# - cl_waiting > 0: Clients waiting for connections (increase pool size)
# - sv_idle > 50%: Many idle connections (decrease pool size)
```

### Connection Limits

```ini
# Maximum client connections to PgBouncer
max_client_conn = 1000

# Maximum connections per database (across all pools)
max_db_connections = 100

# Maximum connections per user per database
max_user_connections = 50

# Minimum connections to keep open (performance)
min_pool_size = 5

# Reserved connections for superusers
reserve_pool_size = 5
reserve_pool_timeout = 5
```

**Example: Calculating limits**

```
Scenario:
- 3 databases (app, api, worker)
- default_pool_size = 20
- max_db_connections = 100

Maximum server connections needed:
3 databases * 20 pool size = 60 connections

PostgreSQL max_connections must be ≥ 60 + overhead (10)
Set PostgreSQL max_connections = 100
```

### Timeouts

```ini
# Server connection idle timeout (seconds)
# Connection returned to pool after this time
server_idle_timeout = 600

# Maximum query execution time (0 = disabled)
# Kill queries exceeding this time
query_timeout = 0

# Client idle timeout (0 = disabled)
# Disconnect idle clients
client_idle_timeout = 0

# Server connection lifetime (0 = disabled)
# Recycle connections after this time
server_lifetime = 3600

# Connection timeout (seconds)
# Time to wait for PostgreSQL connection
server_connect_timeout = 15
```

**Recommended timeout settings:**

```ini
# Web applications (short transactions)
server_idle_timeout = 300
query_timeout = 30
client_idle_timeout = 300

# Long-running applications
server_idle_timeout = 3600
query_timeout = 0
client_idle_timeout = 0
```

### Authentication

PgBouncer supports multiple authentication methods.

```ini
# Authentication type
auth_type = md5        # MD5 password authentication
# auth_type = plain    # Plain text (for local dev only)
# auth_type = trust    # No authentication (unsafe)
# auth_type = scram-sha-256  # SCRAM authentication (PostgreSQL 10+)

# Authentication file
auth_file = /etc/pgbouncer/userlist.txt

# Query to fetch auth data from PostgreSQL
# auth_query = SELECT usename, passwd FROM pg_shadow WHERE usename = $1
```

**userlist.txt format:**

```
# Format: "username" "md5_password"
"postgres" "md5abc123..."
"myapp_user" "md5def456..."
```

**Updating credentials:**

```bash
# Update userlist.txt
docker exec dev-pgbouncer nano /etc/pgbouncer/userlist.txt

# Reload configuration (no restart needed)
docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "RELOAD;"
```

## Connection Patterns

### Connecting Through PgBouncer

**From host machine:**

```bash
# Connect to PgBouncer (port 6432)
docker exec -it dev-postgres psql -h pgbouncer -p 6432 -U postgres

# Or from host
psql -h localhost -p 6432 -U postgres

# Connect to specific database
psql -h localhost -p 6432 -U postgres -d myapp
```

**From application container:**

```bash
# Using Docker network (preferred)
psql -h pgbouncer -p 6432 -U postgres

# Using IP address
psql -h 172.20.0.11 -p 6432 -U postgres
```

### Application Configuration

**Python (psycopg2):**

```python
import psycopg2

# Connect through PgBouncer
conn = psycopg2.connect(
    host="pgbouncer",       # Or "localhost" from host
    port=6432,              # PgBouncer port
    user="postgres",
    password="your_password",
    database="myapp"
)

# Or using connection string
conn = psycopg2.connect("postgresql://postgres:password@pgbouncer:6432/myapp")
```

**Python (SQLAlchemy):**

```python
from sqlalchemy import create_engine

# Connect through PgBouncer
engine = create_engine(
    "postgresql://postgres:password@pgbouncer:6432/myapp",
    pool_pre_ping=True,        # Verify connections before use
    pool_size=10,              # Application-level pool (optional)
    max_overflow=20
)

# Best practice: Disable application pooling (PgBouncer handles it)
engine = create_engine(
    "postgresql://postgres:password@pgbouncer:6432/myapp",
    poolclass=NullPool        # Disable SQLAlchemy pooling
)
```

**Node.js (pg):**

```javascript
const { Pool } = require('pg');

// Connect through PgBouncer
const pool = new Pool({
    host: 'pgbouncer',
    port: 6432,
    user: 'postgres',
    password: 'your_password',
    database: 'myapp',
    max: 20,                  // Application pool size
    idleTimeoutMillis: 30000
});

// Best practice: Use single connection (PgBouncer handles pooling)
const pool = new Pool({
    host: 'pgbouncer',
    port: 6432,
    user: 'postgres',
    password: 'your_password',
    database: 'myapp',
    max: 1                    // Let PgBouncer handle pooling
});
```

**Go (pgx):**

```go
package main

import (
    "context"
    "github.com/jackc/pgx/v5/pgxpool"
)

func main() {
    // Connect through PgBouncer
    connString := "postgresql://postgres:password@pgbouncer:6432/myapp"
    pool, err := pgxpool.New(context.Background(), connString)
    if err != nil {
        panic(err)
    }
    defer pool.Close()

    // Query example
    var result string
    err = pool.QueryRow(context.Background(), "SELECT 'Hello PgBouncer'").Scan(&result)
}
```

**Java (JDBC):**

```java
import java.sql.Connection;
import java.sql.DriverManager;

public class PgBouncerExample {
    public static void main(String[] args) throws Exception {
        // Connect through PgBouncer
        String url = "jdbc:postgresql://pgbouncer:6432/myapp";
        String user = "postgres";
        String password = "your_password";

        Connection conn = DriverManager.getConnection(url, user, password);
        // Use connection...
        conn.close();
    }
}
```

### Connection Strings

**Standard format:**

```
postgresql://[user[:password]@][host][:port][/dbname][?param1=value1&...]
```

**Examples:**

```bash
# Basic connection
postgresql://postgres:password@pgbouncer:6432/myapp

# With connection parameters
postgresql://postgres:password@pgbouncer:6432/myapp?connect_timeout=10&application_name=myapp

# SSL mode (if PgBouncer configured for SSL)
postgresql://postgres:password@pgbouncer:6432/myapp?sslmode=require

# From environment variable
export DATABASE_URL="postgresql://postgres:password@pgbouncer:6432/myapp"
```

### Testing Connections

```bash
# Test PgBouncer connectivity
docker exec dev-pgbouncer pg_isready -h localhost -p 6432 -U postgres

# Test query through PgBouncer
docker exec dev-postgres psql -h pgbouncer -p 6432 -U postgres -c "SELECT version();"

# Compare direct vs PgBouncer
echo "Direct PostgreSQL:"
docker exec dev-postgres psql -h postgres -p 5432 -U postgres -c "SELECT version();"

echo "Through PgBouncer:"
docker exec dev-postgres psql -h pgbouncer -p 6432 -U postgres -c "SELECT version();"
```

## Performance Benefits

### Reduced Connection Overhead

**Connection creation time comparison:**

```bash
# Benchmark: Direct PostgreSQL connection
time docker exec dev-postgres psql -h postgres -p 5432 -U postgres -c "SELECT 1;"
# Typical: 50-100ms (includes fork, auth, setup)

# Benchmark: Through PgBouncer
time docker exec dev-postgres psql -h pgbouncer -p 6432 -U postgres -c "SELECT 1;"
# Typical: 5-10ms (connection reuse)
```

**Connection establishment:**
- Direct PostgreSQL: Fork process (5ms) + Auth (2ms) + Setup (3ms) = ~10ms
- PgBouncer: Auth (1ms) + Reuse pooled connection (0.1ms) = ~1ms

### Better Resource Utilization

**Memory usage comparison:**

```
Scenario: 200 concurrent clients

Direct PostgreSQL:
├── 200 connections * 10MB = 2GB memory
└── 200 backend processes

With PgBouncer:
├── 200 client connections (lightweight)
├── 20 pooled connections * 10MB = 200MB memory
└── 20 backend processes

Savings: 1.8GB memory, 180 processes
```

### Connection Reuse

**Transaction throughput:**

```sql
-- Test transaction rate (100 transactions)
-- Direct PostgreSQL: ~200 TPS (connection overhead)
-- Through PgBouncer: ~2000 TPS (10x improvement)

-- Example benchmark
\timing on
BEGIN;
INSERT INTO test_table (id, data) VALUES (1, 'test');
COMMIT;
-- Repeat 100 times

-- Direct: ~500ms total (100 transactions)
-- PgBouncer: ~50ms total (100 transactions)
```

### Performance Metrics

**Monitoring performance improvements:**

```bash
# Check PgBouncer statistics
docker exec -it dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW STATS;"

# Key metrics:
# - total_xact_count: Total transactions (should be high)
# - total_query_count: Total queries
# - total_received: Bytes received
# - total_sent: Bytes sent
# - avg_xact_time: Average transaction time (should be low)
# - avg_query_time: Average query time (should be low)
```

**Comparing direct vs PgBouncer performance:**

```sql
-- Run load test
-- Direct PostgreSQL
ab -n 1000 -c 50 http://localhost:8000/api/direct_db

-- Through PgBouncer
ab -n 1000 -c 50 http://localhost:8000/api/pooled_db

-- Expected results:
-- PgBouncer: 2-10x faster for short transactions
-- Direct: Slightly faster for long analytical queries
```

## Limitations

### Session-Level Features

**Features NOT available in transaction mode:**

1. **Prepared statements:**
```sql
-- This FAILS in transaction mode
PREPARE get_user (int) AS SELECT * FROM users WHERE id = $1;
EXECUTE get_user(123);
-- ERROR: prepared statements not supported

-- Workaround: Use parameterized queries instead
SELECT * FROM users WHERE id = $1;  -- Pass 123 as parameter
```

2. **SET statements:**
```sql
-- This FAILS in transaction mode (doesn't persist)
SET timezone = 'America/New_York';
-- Setting lost after transaction

-- Workaround: Set per transaction
BEGIN;
SET LOCAL timezone = 'America/New_York';
SELECT NOW();
COMMIT;
```

3. **LISTEN/NOTIFY:**
```sql
-- This FAILS in transaction mode
LISTEN my_channel;
NOTIFY my_channel, 'message';
-- ERROR: LISTEN not supported

-- Workaround: Use session mode or direct connection
```

### Prepared Statements

**Problem:**
```python
# This pattern FAILS with PgBouncer (transaction mode)
import psycopg2

conn = psycopg2.connect("postgresql://postgres:password@pgbouncer:6432/myapp")
cursor = conn.cursor()

# Prepare statement
cursor.execute("PREPARE get_user (int) AS SELECT * FROM users WHERE id = $1")

# Execute (FAILS - prepared statement lost)
cursor.execute("EXECUTE get_user(123)")
```

**Solution: Use parameterized queries (no PREPARE):**

```python
# This works with PgBouncer
cursor.execute("SELECT * FROM users WHERE id = %s", (123,))
```

**SQLAlchemy consideration:**

```python
# SQLAlchemy uses prepared statements by default
# Disable for PgBouncer transaction mode
from sqlalchemy.pool import NullPool

engine = create_engine(
    "postgresql://postgres:password@pgbouncer:6432/myapp",
    poolclass=NullPool,
    connect_args={"prepared_statement_cache_size": 0}  # Disable prepared statements
)
```

### Temporary Tables

**Problem:**
```sql
-- Temporary tables don't persist across transactions
BEGIN;
CREATE TEMP TABLE my_temp (id INT);
INSERT INTO my_temp VALUES (1);
COMMIT;

-- Next transaction (FAILS - temp table gone)
SELECT * FROM my_temp;
-- ERROR: relation "my_temp" does not exist
```

**Solution: Use session mode or regular tables:**

```sql
-- Option 1: Use session mode (pgbouncer.ini)
pool_mode = session

-- Option 2: Use regular tables with unique names
CREATE TABLE my_temp_20241028_123456 (id INT);
-- Clean up when done
DROP TABLE my_temp_20241028_123456;

-- Option 3: Use CTEs (Common Table Expressions)
WITH my_temp AS (
    SELECT 1 as id
)
SELECT * FROM my_temp;
```

### Advisory Locks

**Problem:**
```sql
-- Advisory locks don't persist in transaction mode
BEGIN;
SELECT pg_advisory_lock(123);
-- Lock held
COMMIT;
-- Lock released immediately (not useful)

-- Next transaction (FAILS - lock not held)
SELECT pg_advisory_unlock(123);
-- ERROR: you don't own the lock
```

**Solution: Use session mode or application-level locking:**

```ini
# pgbouncer.ini - Use session mode for advisory locks
pool_mode = session
```

**Or use application-level locking:**

```python
import redis
import time

# Redis-based distributed lock
redis_client = redis.Redis(host='redis-1', port=6379)

def acquire_lock(key, timeout=10):
    return redis_client.set(key, 'locked', nx=True, ex=timeout)

def release_lock(key):
    redis_client.delete(key)

# Usage
if acquire_lock('my_resource'):
    # Critical section
    release_lock('my_resource')
```

## Monitoring

### PgBouncer Statistics

PgBouncer exposes statistics through a special `pgbouncer` database.

```bash
# Connect to PgBouncer admin console
docker exec -it dev-pgbouncer psql -p 6432 -U postgres pgbouncer
```

### SHOW Commands

#### SHOW STATS

```sql
-- Show database statistics
SHOW STATS;

-- Output columns:
-- database: Database name
-- total_xact_count: Total transactions
-- total_query_count: Total queries
-- total_received: Bytes received
-- total_sent: Bytes sent
-- total_xact_time: Total transaction time (microseconds)
-- total_query_time: Total query time (microseconds)
-- total_wait_time: Total wait time (microseconds)
-- avg_xact_count: Avg transactions per second
-- avg_query_count: Avg queries per second
-- avg_recv: Avg bytes received per second
-- avg_sent: Avg bytes sent per second
-- avg_xact_time: Avg transaction time (microseconds)
-- avg_query_time: Avg query time (microseconds)
-- avg_wait_time: Avg wait time (microseconds)
```

#### SHOW POOLS

```sql
-- Show connection pool status
SHOW POOLS;

-- Output columns:
-- database: Database name
-- user: Username
-- cl_active: Active client connections
-- cl_waiting: Clients waiting for connection
-- sv_active: Active server connections
-- sv_idle: Idle server connections
-- sv_used: Server connections in use
-- sv_tested: Server connections being tested
-- sv_login: Server connections logging in
-- maxwait: Max wait time (seconds)
-- maxwait_us: Max wait time (microseconds)
-- pool_mode: Pool mode (transaction/session/statement)

-- Key metrics to watch:
-- cl_waiting > 0: Pool exhaustion (increase pool size)
-- sv_idle high: Over-provisioned (decrease pool size)
-- maxwait > 0: Clients waiting (increase pool size)
```

#### SHOW DATABASES

```sql
-- Show configured databases
SHOW DATABASES;

-- Output columns:
-- name: Database name
-- host: PostgreSQL host
-- port: PostgreSQL port
-- database: Actual database name
-- force_user: Forced username
-- pool_size: Pool size for this database
-- reserve_pool: Reserve pool size
-- pool_mode: Pool mode
-- max_connections: Max connections
-- current_connections: Current connections
-- paused: Is database paused?
-- disabled: Is database disabled?
```

#### SHOW CLIENTS

```sql
-- Show connected clients
SHOW CLIENTS;

-- Output columns:
-- type: Client type (C = client, S = server)
-- user: Username
-- database: Database name
-- state: Connection state
-- addr: Client address
-- port: Client port
-- local_addr: Local address
-- local_port: Local port
-- connect_time: Connection time
-- request_time: Last request time
-- wait: Wait time
-- wait_us: Wait time (microseconds)
-- close_needed: Close needed?
-- ptr: Pointer (internal)
-- link: Linked server connection
-- remote_pid: PostgreSQL backend PID
-- tls: TLS cipher (if using SSL)
```

#### SHOW SERVERS

```sql
-- Show server connections
SHOW SERVERS;

-- Same columns as SHOW CLIENTS
-- Shows PgBouncer → PostgreSQL connections
```

#### Other SHOW Commands

```sql
-- Show configuration
SHOW CONFIG;

-- Show PgBouncer version
SHOW VERSION;

-- Show memory usage
SHOW MEM;

-- Show DNS cache
SHOW DNS_HOSTS;

-- Show active sockets
SHOW SOCKETS;

-- Show active lists
SHOW LISTS;

-- Show users
SHOW USERS;

-- Show databases with details
SHOW FDS;
```

### Connection Pool Status

**Checking pool health:**

```bash
# Quick pool check
docker exec -it dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW POOLS;" | grep -v "pgbouncer"

# Watch pool status in real-time
watch -n 1 'docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW POOLS;" | grep -v "pgbouncer"'

# Check for waiting clients
docker exec -it dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "
SELECT database, user, cl_waiting, sv_active, sv_idle
FROM pgbouncer.pools
WHERE cl_waiting > 0;
"
```

**Interpreting pool status:**

```
Example output:
 database |  user    | cl_active | cl_waiting | sv_active | sv_idle
----------+----------+-----------+------------+-----------+---------
 myapp    | postgres |        15 |          0 |        10 |       5

Analysis:
- 15 active clients
- 0 waiting clients (good - pool not saturated)
- 10 active server connections
- 5 idle server connections (ready for reuse)
- Pool healthy: cl_active ≈ sv_active + sv_idle
```

### Performance Monitoring

**Transaction rate:**

```sql
-- Monitor transaction rate
SHOW STATS;

-- Calculate TPS (transactions per second)
-- Run SHOW STATS twice, 10 seconds apart
-- TPS = (total_xact_count_2 - total_xact_count_1) / 10
```

**Query performance:**

```sql
-- Monitor average query time
SHOW STATS;

-- Look at:
-- avg_query_time: Average query time (microseconds)
-- avg_xact_time: Average transaction time (microseconds)
-- avg_wait_time: Average wait time (microseconds)

-- Good targets:
-- avg_query_time < 1000 (1ms)
-- avg_wait_time < 100 (0.1ms)
```

**Monitoring script:**

```bash
#!/bin/bash
# Save as: monitor-pgbouncer.sh

while true; do
    echo "=== PgBouncer Status $(date) ==="

    echo "Pool Status:"
    docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -t -c "
        SELECT database, cl_active, cl_waiting, sv_active, sv_idle
        FROM pgbouncer.pools
        WHERE database != 'pgbouncer'
        ORDER BY cl_active DESC;
    "

    echo "Top Databases by Transaction Count:"
    docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -t -c "
        SELECT database, total_xact_count, avg_xact_time
        FROM pgbouncer.stats
        WHERE database != 'pgbouncer'
        ORDER BY total_xact_count DESC
        LIMIT 5;
    "

    sleep 5
done
```

## Troubleshooting

### Connection Refused

**Problem:** Cannot connect to PgBouncer.

```bash
# Error: Connection refused
psql -h localhost -p 6432 -U postgres
# psql: error: connection to server at "localhost", port 6432 failed: Connection refused
```

**Solutions:**

```bash
# 1. Check if PgBouncer is running
docker ps | grep dev-pgbouncer

# 2. Check PgBouncer logs
docker logs dev-pgbouncer --tail 50

# 3. Check if port 6432 is listening
docker exec dev-pgbouncer netstat -tlnp | grep 6432

# 4. Test from inside container
docker exec -it dev-postgres psql -h pgbouncer -p 6432 -U postgres

# 5. Restart PgBouncer
docker restart dev-pgbouncer
```

### Pool Exhaustion

**Problem:** Clients waiting for connections (cl_waiting > 0).

```sql
-- Check pool status
SHOW POOLS;
-- cl_waiting > 0 indicates pool exhaustion
```

**Solutions:**

```bash
# 1. Increase pool size
nano /Users/gator/devstack-core/configs/pgbouncer/pgbouncer.ini
# Increase: default_pool_size = 30  (was 20)
docker restart dev-pgbouncer

# 2. Check for long-running queries (blocking connections)
docker exec -it dev-postgres psql -U postgres -c "
SELECT pid, state, query_start, NOW() - query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active' AND NOW() - query_start > INTERVAL '5 minutes';
"

# 3. Kill long-running queries
docker exec -it dev-postgres psql -U postgres -c "SELECT pg_terminate_backend(12345);"

# 4. Check for connection leaks in application
# Ensure connections are properly closed after use

# 5. Monitor pool over time
watch -n 2 'docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"'
```

### Authentication Issues

**Problem:** Authentication failed errors.

```bash
# Error: password authentication failed
psql -h localhost -p 6432 -U postgres
# psql: error: password authentication failed for user "postgres"
```

**Solutions:**

```bash
# 1. Check userlist.txt exists and has correct credentials
docker exec dev-pgbouncer cat /etc/pgbouncer/userlist.txt

# 2. Verify password format (MD5)
# Format: "username" "md5<md5hash>"
echo -n "passwordusername" | md5sum
# Result: abc123... → userlist.txt entry: "username" "md5abc123..."

# 3. Reload PgBouncer configuration
docker exec -it dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "RELOAD;"

# 4. Test direct PostgreSQL connection
docker exec -it dev-postgres psql -h postgres -p 5432 -U postgres
# If this works, problem is PgBouncer auth config

# 5. Use auth_query instead of userlist.txt
nano /Users/gator/devstack-core/configs/pgbouncer/pgbouncer.ini
# Add: auth_query = SELECT usename, passwd FROM pg_shadow WHERE usename = $1
docker restart dev-pgbouncer
```

### Slow Queries

**Problem:** Queries slower through PgBouncer than direct connection.

```bash
# Compare query times
time docker exec dev-postgres psql -h postgres -p 5432 -U postgres -c "SELECT pg_sleep(0.1);"
time docker exec dev-postgres psql -h pgbouncer -p 6432 -U postgres -c "SELECT pg_sleep(0.1);"
```

**Solutions:**

```sql
-- 1. Check for waiting clients (pool saturation)
SHOW POOLS;
-- If cl_waiting > 0, increase pool size

-- 2. Check average wait time
SHOW STATS;
-- If avg_wait_time > 1000 (1ms), pool too small

-- 3. Check query timeout setting
SHOW CONFIG;
-- Look at query_timeout

-- 4. Verify pool mode is transaction (not session)
SHOW CONFIG;
-- pool_mode should be "transaction" for best performance

-- 5. Check for network issues
-- Run from application container vs host
```

### Transaction Rollback Issues

**Problem:** Transactions not rolling back properly.

```sql
-- Symptom: Data persists despite ROLLBACK
BEGIN;
INSERT INTO test_table (id) VALUES (999);
ROLLBACK;
-- Later: SELECT * FROM test_table WHERE id = 999; returns row (shouldn't!)
```

**Solutions:**

```python
# 1. Ensure proper transaction handling in application
import psycopg2

conn = psycopg2.connect("postgresql://postgres:password@pgbouncer:6432/myapp")
try:
    cursor = conn.cursor()
    cursor.execute("INSERT INTO test_table (id) VALUES (999)")
    conn.commit()  # Explicit commit
except Exception as e:
    conn.rollback()  # Explicit rollback
finally:
    conn.close()  # Always close

# 2. Check autocommit setting
conn.autocommit = False  # Ensure transactions are used

# 3. Verify transaction mode
# Check pgbouncer.ini: pool_mode = transaction

# 4. Look for connection leaks
# Connections returned to pool without COMMIT/ROLLBACK remain in transaction
# Always use try/finally or context managers
```

## Migration

### Moving from Direct PostgreSQL

**Step-by-step migration:**

```bash
# 1. Document current setup
echo "Current PostgreSQL connections:"
docker exec dev-postgres psql -U postgres -c "SELECT count(*) FROM pg_stat_activity;"

echo "Current application connection strings:"
# Review application config files

# 2. Backup current configuration
cp application.conf application.conf.backup

# 3. Update application configuration (gradual rollout)
# Change: postgresql://postgres:password@postgres:5432/myapp
# To:     postgresql://postgres:password@pgbouncer:6432/myapp

# 4. Deploy to staging/test environment first
# 5. Run test suite
# 6. Monitor for issues (24-48 hours)
# 7. Deploy to production (canary/rolling deployment)
```

**Configuration changes checklist:**

- [ ] Update database host (postgres → pgbouncer)
- [ ] Update database port (5432 → 6432)
- [ ] Disable application-level connection pooling
- [ ] Test prepared statement usage (may need to refactor)
- [ ] Test temporary table usage (may need to refactor)
- [ ] Update monitoring/alerting (track PgBouncer metrics)
- [ ] Document rollback procedure

### Testing Migration

```bash
# 1. Test basic connectivity
docker exec dev-postgres psql -h pgbouncer -p 6432 -U postgres -c "SELECT version();"

# 2. Test transaction handling
docker exec dev-postgres psql -h pgbouncer -p 6432 -U postgres << 'EOF'
BEGIN;
CREATE TABLE test_migration (id INT);
INSERT INTO test_migration VALUES (1);
SELECT * FROM test_migration;
ROLLBACK;
SELECT count(*) FROM test_migration;  -- Should error (table shouldn't exist)
EOF

# 3. Load test (use reference API)
# Direct PostgreSQL
ab -n 1000 -c 50 http://localhost:8000/api/postgres/users/1

# Through PgBouncer (update app config)
ab -n 1000 -c 50 http://localhost:8000/api/postgres/users/1

# 4. Monitor pool usage during load test
watch -n 1 'docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"'

# 5. Check for errors in application logs
docker logs reference-api --tail 100 -f
```

### Rollback Plan

**If issues occur, rollback immediately:**

```bash
# 1. Update application config (revert changes)
# Change: postgresql://postgres:password@pgbouncer:6432/myapp
# To:     postgresql://postgres:password@postgres:5432/myapp

# 2. Restart application
docker restart reference-api

# 3. Verify connectivity
docker exec reference-api curl http://localhost:8000/health

# 4. Document issues for later analysis
echo "Rollback reason: <describe issue>" >> migration.log

# 5. Plan remediation before next attempt
```

## Advanced Configuration

### Multiple Database Pools

Configure different pool sizes for different databases.

```ini
# pgbouncer.ini
[databases]
myapp = host=postgres port=5432 dbname=myapp pool_size=30
analytics = host=postgres port=5432 dbname=analytics pool_size=10
logs = host=postgres port=5432 dbname=logs pool_size=5

# Wildcard for other databases (default)
* = host=postgres port=5432 dbname=postgres pool_size=20
```

### Per-Database Settings

```ini
# pgbouncer.ini
[databases]
# High-traffic database (large pool)
api = host=postgres port=5432 dbname=api pool_size=50 pool_mode=transaction

# Admin database (session mode for full features)
admin = host=postgres port=5432 dbname=admin pool_size=5 pool_mode=session

# Read-replica (separate host)
reporting = host=postgres-replica port=5432 dbname=reporting pool_size=20

# Different authentication
special = host=postgres port=5432 dbname=special auth_user=special_user
```

### Load Balancing

PgBouncer can distribute connections across multiple PostgreSQL servers.

```ini
# pgbouncer.ini
[databases]
# Round-robin across read replicas
myapp_read = host=postgres-replica1,postgres-replica2 port=5432 dbname=myapp

# Write to primary
myapp_write = host=postgres-primary port=5432 dbname=myapp
```

**Application usage:**

```python
# Write connection
write_conn = psycopg2.connect("postgresql://postgres:password@pgbouncer:6432/myapp_write")

# Read connection (load balanced)
read_conn = psycopg2.connect("postgresql://postgres:password@pgbouncer:6432/myapp_read")
```

### SSL/TLS Configuration

Enable SSL between PgBouncer and PostgreSQL.

```ini
# pgbouncer.ini
[pgbouncer]
# Client connections (application → PgBouncer)
client_tls_sslmode = prefer
client_tls_ca_file = /etc/pgbouncer/ca.pem
client_tls_cert_file = /etc/pgbouncer/server.crt
client_tls_key_file = /etc/pgbouncer/server.key

# Server connections (PgBouncer → PostgreSQL)
server_tls_sslmode = require
server_tls_ca_file = /etc/pgbouncer/ca.pem
server_tls_cert_file = /etc/pgbouncer/client.crt
server_tls_key_file = /etc/pgbouncer/client.key
```

## Best Practices

1. **Use transaction mode for most applications:**
   ```ini
   pool_mode = transaction  # Best performance
   ```

2. **Disable application-level pooling:**
   ```python
   # Let PgBouncer handle pooling
   engine = create_engine(url, poolclass=NullPool)
   ```

3. **Size pools appropriately:**
   ```
   Pool size = (CPU cores * 2-4)
   Monitor cl_waiting metric
   ```

4. **Use parameterized queries (not prepared statements):**
   ```python
   # Good
   cursor.execute("SELECT * FROM users WHERE id = %s", (user_id,))

   # Avoid (doesn't work in transaction mode)
   cursor.execute("PREPARE stmt AS SELECT * FROM users WHERE id = $1")
   ```

5. **Set appropriate timeouts:**
   ```ini
   server_idle_timeout = 600   # 10 minutes
   query_timeout = 30          # 30 seconds (prevent runaway queries)
   ```

6. **Monitor pool status regularly:**
   ```bash
   # Add to monitoring dashboard
   docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"
   ```

7. **Use session mode for admin tasks:**
   ```ini
   # Separate database for admin
   admin = host=postgres port=5432 pool_size=5 pool_mode=session
   ```

8. **Always close connections properly:**
   ```python
   # Use context managers
   with psycopg2.connect(dsn) as conn:
       with conn.cursor() as cursor:
           cursor.execute("SELECT 1")
   # Connection automatically returned to pool
   ```

9. **Test before production deployment:**
   ```bash
   # Run full test suite through PgBouncer
   ./tests/run-all-tests.sh
   ```

10. **Document pool mode limitations:**
    ```
    Known limitations:
    - No prepared statements in transaction mode
    - No temp tables across transactions
    - No advisory locks in transaction mode
    ```

## Reference

### Related Wiki Pages

- [PostgreSQL Operations](PostgreSQL-Operations) - PostgreSQL management guide
- [Service Configuration](Service-Configuration) - Service configuration details
- [Performance Tuning](Performance-Tuning) - Advanced optimization
- [Backup and Restore](Backup-and-Restore) - Backup strategies
- [Health Monitoring](Health-Monitoring) - Monitoring and alerting
- [Disaster Recovery](Disaster-Recovery) - Recovery procedures

### Useful Commands Quick Reference

```bash
# Connect to PgBouncer admin
docker exec -it dev-pgbouncer psql -p 6432 -U postgres pgbouncer

# Show pool status
docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW POOLS;"

# Show statistics
docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "SHOW STATS;"

# Reload configuration (no restart)
docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "RELOAD;"

# Pause database (stop accepting new connections)
docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "PAUSE myapp;"

# Resume database
docker exec dev-pgbouncer psql -p 6432 -U postgres pgbouncer -c "RESUME myapp;"

# Restart PgBouncer
docker restart dev-pgbouncer

# View PgBouncer logs
docker logs dev-pgbouncer --tail 100 -f
```

### PgBouncer Admin Commands

```sql
-- Configuration management
RELOAD;          -- Reload configuration
PAUSE [db];      -- Pause database (finish active transactions, no new ones)
RESUME [db];     -- Resume database
DISABLE [db];    -- Disable database (reject connections)
ENABLE [db];     -- Enable database
KILL [db];       -- Kill all connections
SUSPEND;         -- Suspend all activity
SHUTDOWN;        -- Shutdown PgBouncer (graceful)

-- Information
SHOW STATS;      -- Statistics
SHOW POOLS;      -- Pool status
SHOW DATABASES;  -- Configured databases
SHOW CLIENTS;    -- Connected clients
SHOW SERVERS;    -- Server connections
SHOW CONFIG;     -- Configuration
SHOW VERSION;    -- PgBouncer version
SHOW MEM;        -- Memory usage
```

### Configuration File Reference

```ini
# /configs/pgbouncer/pgbouncer.ini

[databases]
* = host=postgres port=5432

[pgbouncer]
# Pool settings
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5

# Timeouts
server_idle_timeout = 600
query_timeout = 0
client_idle_timeout = 0

# Authentication
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

# Logging
logfile = /var/log/pgbouncer/pgbouncer.log
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1

# Admin
admin_users = postgres
stats_users = postgres
```

### Additional Resources

- [Official PgBouncer Documentation](https://www.pgbouncer.org/usage.html)
- [PgBouncer GitHub](https://github.com/pgbouncer/pgbouncer)
- [PostgreSQL Connection Pooling](https://www.postgresql.org/docs/current/runtime-config-connection.html)
- [PgBouncer FAQ](https://www.pgbouncer.org/faq.html)
