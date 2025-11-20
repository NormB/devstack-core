# MySQL Operations

Comprehensive guide to MySQL database operations in the DevStack Core environment.

## Table of Contents

- [Overview](#overview)
- [Quick Reference](#quick-reference)
- [Connection Management](#connection-management)
  - [Connecting from Host](#connecting-from-host)
  - [Connecting from Containers](#connecting-from-containers)
  - [Connection Pooling](#connection-pooling)
  - [Connection Troubleshooting](#connection-troubleshooting)
- [User Management](#user-management)
  - [Creating Users](#creating-users)
  - [Granting Privileges](#granting-privileges)
  - [Revoking Privileges](#revoking-privileges)
  - [Viewing User Privileges](#viewing-user-privileges)
  - [Modifying Users](#modifying-users)
  - [Removing Users](#removing-users)
- [Database Management](#database-management)
  - [Creating Databases](#creating-databases)
  - [Listing Databases](#listing-databases)
  - [Switching Databases](#switching-databases)
  - [Dropping Databases](#dropping-databases)
  - [Database Properties](#database-properties)
- [Schema Operations](#schema-operations)
  - [Creating Tables](#creating-tables)
  - [Altering Tables](#altering-tables)
  - [Viewing Table Structure](#viewing-table-structure)
  - [Dropping Tables](#dropping-tables)
  - [Table Statistics](#table-statistics)
- [Query Optimization](#query-optimization)
  - [Using EXPLAIN](#using-explain)
  - [Query Planning](#query-planning)
  - [Index Usage Analysis](#index-usage-analysis)
  - [Slow Query Log](#slow-query-log)
  - [Query Cache](#query-cache)
- [Performance Monitoring](#performance-monitoring)
  - [Server Status](#server-status)
  - [Process List](#process-list)
  - [Performance Schema](#performance-schema)
  - [Identifying Slow Queries](#identifying-slow-queries)
  - [Resource Usage](#resource-usage)
- [Index Management](#index-management)
  - [Index Types](#index-types)
  - [Creating Indexes](#creating-indexes)
  - [Index Maintenance](#index-maintenance)
  - [Index Optimization](#index-optimization)
  - [Index Statistics](#index-statistics)
- [Maintenance Operations](#maintenance-operations)
  - [Table Optimization](#table-optimization)
  - [Table Analysis](#table-analysis)
  - [Table Repair](#table-repair)
  - [InnoDB Maintenance](#innodb-maintenance)
  - [Checksum Operations](#checksum-operations)
- [Backup Operations](#backup-operations)
  - [Logical Backups with mysqldump](#logical-backups-with-mysqldump)
  - [Logical Backups with mysqlpump](#logical-backups-with-mysqlpump)
  - [Binary Backups](#binary-backups)
  - [Point-in-Time Recovery](#point-in-time-recovery)
  - [Backup Verification](#backup-verification)
- [Replication](#replication)
  - [Replication Overview](#replication-overview)
  - [Master-Slave Setup](#master-slave-setup)
  - [Monitoring Replication](#monitoring-replication)
  - [Replication Troubleshooting](#replication-troubleshooting)
- [Troubleshooting](#troubleshooting)
  - [Connection Issues](#connection-issues)
  - [Lock Contention](#lock-contention)
  - [Deadlocks](#deadlocks)
  - [Disk Space Issues](#disk-space-issues)
  - [Table Corruption](#table-corruption)
  - [Performance Issues](#performance-issues)
- [Security Best Practices](#security-best-practices)
- [Related Documentation](#related-documentation)

## Overview

MySQL is configured in the DevStack Core environment with:

- **Version**: MySQL 8.0
- **Host Port**: 3306
- **Container IP**: 172.20.0.12
- **Container Name**: mysql
- **Data Volume**: mysql-data
- **Configuration**: `/configs/mysql/my.cnf`
- **Credentials**: Managed by Vault (`secret/mysql`)

**⚠️ WARNING:** This is a development environment. Production deployments require additional security hardening, replication, and backup strategies.

## Quick Reference

```bash
# Connect to MySQL
mysql -h localhost -P 3306 -u root -p

# Connect from container
docker exec -it mysql mysql -u root -p

# Show databases
mysql -u root -p -e "SHOW DATABASES;"

# Create database
mysql -u root -p -e "CREATE DATABASE myapp;"

# Import SQL file
mysql -u root -p myapp < backup.sql

# Export database
mysqldump -u root -p myapp > backup.sql

# Check MySQL status
docker exec mysql mysqladmin -u root -p status

# View process list
docker exec mysql mysql -u root -p -e "SHOW PROCESSLIST;"

# Check table size
docker exec mysql mysql -u root -p -e "SELECT table_schema, table_name,
  ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb
  FROM information_schema.tables
  WHERE table_schema = 'myapp'
  ORDER BY size_mb DESC;"
```

## Connection Management

### Connecting from Host

Connect to MySQL from your host machine:

```bash
# Get MySQL credentials from Vault
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
MYSQL_PASSWORD=$(vault kv get -field=password secret/mysql)

# Connect using mysql client
mysql -h localhost -P 3306 -u root -p"${MYSQL_PASSWORD}"

# Connect without storing password in history
mysql -h localhost -P 3306 -u root -p
# Enter password when prompted

# Connect to specific database
mysql -h localhost -P 3306 -u root -p myapp

# Execute single command
mysql -h localhost -P 3306 -u root -p -e "SHOW DATABASES;"

# Execute SQL file
mysql -h localhost -P 3306 -u root -p myapp < script.sql
```

### Connecting from Containers

Connect from other containers in the dev-services network:

```bash
# From another container using container name
mysql -h mysql -P 3306 -u root -p

# From another container using IP
mysql -h 172.20.0.12 -P 3306 -u root -p

# Example: Connect from reference API
docker exec -it dev-reference-api mysql -h mysql -P 3306 -u root -p

# Test connectivity
docker exec -it dev-reference-api ping mysql
docker exec -it dev-reference-api nc -zv mysql 3306
```

### Connection Pooling

Configure connection pooling in applications:

**Python (SQLAlchemy):**

```python
from sqlalchemy import create_engine
from sqlalchemy.pool import QueuePool

# Create engine with connection pooling
engine = create_engine(
    f"mysql+pymysql://root:{password}@mysql:3306/myapp",
    poolclass=QueuePool,
    pool_size=10,          # Number of connections to maintain
    max_overflow=20,       # Max connections beyond pool_size
    pool_timeout=30,       # Timeout for getting connection
    pool_recycle=3600,     # Recycle connections after 1 hour
    pool_pre_ping=True,    # Verify connections before using
    echo_pool=True         # Log pool events
)

# Test connection
with engine.connect() as conn:
    result = conn.execute("SELECT 1")
    print(result.fetchone())
```

**Node.js (mysql2):**

```javascript
const mysql = require('mysql2/promise');

// Create connection pool
const pool = mysql.createPool({
  host: 'mysql',
  port: 3306,
  user: 'root',
  password: process.env.MYSQL_PASSWORD,
  database: 'myapp',
  waitForConnections: true,
  connectionLimit: 10,
  maxIdle: 10,
  idleTimeout: 60000,
  queueLimit: 0,
  enableKeepAlive: true,
  keepAliveInitialDelay: 0
});

// Test connection
async function testConnection() {
  const connection = await pool.getConnection();
  const [rows] = await connection.query('SELECT 1');
  connection.release();
  return rows;
}
```

**Go (go-sql-driver):**

```go
package main

import (
    "database/sql"
    "time"
    _ "github.com/go-sql-driver/mysql"
)

func createPool(password string) (*sql.DB, error) {
    dsn := fmt.Sprintf("root:%s@tcp(mysql:3306)/myapp", password)

    db, err := sql.Open("mysql", dsn)
    if err != nil {
        return nil, err
    }

    // Configure connection pool
    db.SetMaxOpenConns(10)
    db.SetMaxIdleConns(5)
    db.SetConnMaxLifetime(time.Hour)
    db.SetConnMaxIdleTime(10 * time.Minute)

    // Test connection
    if err := db.Ping(); err != nil {
        return nil, err
    }

    return db, nil
}
```

### Connection Troubleshooting

**Issue: Connection Refused**

```bash
# Check if MySQL is running
docker ps | grep mysql

# Check MySQL logs
docker logs mysql --tail 50

# Check if port is accessible
nc -zv localhost 3306

# Check from within container network
docker exec -it dev-reference-api nc -zv mysql 3306

# Verify MySQL is listening
docker exec mysql netstat -tlnp | grep 3306
```

**Issue: Access Denied**

```bash
# Verify credentials in Vault
vault kv get secret/mysql

# Check user exists and has privileges
docker exec mysql mysql -u root -p -e "SELECT user, host FROM mysql.user;"

# Check user privileges
docker exec mysql mysql -u root -p -e "SHOW GRANTS FOR 'root'@'%';"

# Reset root password if needed (⚠️ Vault will be out of sync)
docker exec mysql mysql -u root -e "ALTER USER 'root'@'%' IDENTIFIED BY 'newpassword';"
```

**Issue: Too Many Connections**

```bash
# Check current connections
docker exec mysql mysql -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"

# Check max connections
docker exec mysql mysql -u root -p -e "SHOW VARIABLES LIKE 'max_connections';"

# View active connections
docker exec mysql mysql -u root -p -e "SHOW PROCESSLIST;"

# Kill specific connection
docker exec mysql mysql -u root -p -e "KILL <connection_id>;"

# Increase max_connections (temporary)
docker exec mysql mysql -u root -p -e "SET GLOBAL max_connections = 200;"
```

## User Management

### Creating Users

```sql
-- Create user with password
CREATE USER 'appuser'@'%' IDENTIFIED BY 'SecurePass123!';

-- Create user with specific host
CREATE USER 'appuser'@'172.20.0.%' IDENTIFIED BY 'SecurePass123!';

-- Create user with authentication plugin
CREATE USER 'appuser'@'%' IDENTIFIED WITH caching_sha2_password BY 'SecurePass123!';

-- Create user with resource limits
CREATE USER 'limited'@'%' IDENTIFIED BY 'SecurePass123!'
  WITH MAX_QUERIES_PER_HOUR 1000
       MAX_CONNECTIONS_PER_HOUR 100
       MAX_USER_CONNECTIONS 5;
```

Execute from command line:

```bash
docker exec mysql mysql -u root -p -e "CREATE USER 'appuser'@'%' IDENTIFIED BY 'SecurePass123!';"
```

### Granting Privileges

```sql
-- Grant all privileges on database
GRANT ALL PRIVILEGES ON myapp.* TO 'appuser'@'%';

-- Grant specific privileges
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO 'appuser'@'%';

-- Grant privileges on specific table
GRANT SELECT, INSERT ON myapp.users TO 'appuser'@'%';

-- Grant privileges with grant option
GRANT SELECT, INSERT ON myapp.* TO 'appuser'@'%' WITH GRANT OPTION;

-- Grant admin privileges
GRANT ALL PRIVILEGES ON *.* TO 'admin'@'%' WITH GRANT OPTION;

-- Reload privileges
FLUSH PRIVILEGES;
```

Common privilege combinations:

```bash
# Read-only user
docker exec mysql mysql -u root -p -e "
CREATE USER 'readonly'@'%' IDENTIFIED BY 'ReadPass123!';
GRANT SELECT ON myapp.* TO 'readonly'@'%';
FLUSH PRIVILEGES;"

# Application user (CRUD operations)
docker exec mysql mysql -u root -p -e "
CREATE USER 'appuser'@'%' IDENTIFIED BY 'AppPass123!';
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.* TO 'appuser'@'%';
FLUSH PRIVILEGES;"

# Developer user (DDL + DML)
docker exec mysql mysql -u root -p -e "
CREATE USER 'developer'@'%' IDENTIFIED BY 'DevPass123!';
GRANT ALL PRIVILEGES ON myapp.* TO 'developer'@'%';
FLUSH PRIVILEGES;"
```

### Revoking Privileges

```sql
-- Revoke specific privileges
REVOKE INSERT, UPDATE ON myapp.* FROM 'appuser'@'%';

-- Revoke all privileges on database
REVOKE ALL PRIVILEGES ON myapp.* FROM 'appuser'@'%';

-- Revoke all privileges globally
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'appuser'@'%';

-- Reload privileges
FLUSH PRIVILEGES;
```

### Viewing User Privileges

```sql
-- Show all users
SELECT user, host, account_locked, password_expired
FROM mysql.user;

-- Show grants for specific user
SHOW GRANTS FOR 'appuser'@'%';

-- Show grants for current user
SHOW GRANTS;

-- View user privileges from information_schema
SELECT * FROM information_schema.user_privileges
WHERE grantee LIKE '%appuser%';

-- View database privileges
SELECT * FROM information_schema.schema_privileges
WHERE grantee LIKE '%appuser%';

-- View table privileges
SELECT * FROM information_schema.table_privileges
WHERE grantee LIKE '%appuser%';
```

### Modifying Users

```sql
-- Change password
ALTER USER 'appuser'@'%' IDENTIFIED BY 'NewSecurePass123!';

-- Change authentication plugin
ALTER USER 'appuser'@'%' IDENTIFIED WITH mysql_native_password BY 'NewPass123!';

-- Lock user account
ALTER USER 'appuser'@'%' ACCOUNT LOCK;

-- Unlock user account
ALTER USER 'appuser'@'%' ACCOUNT UNLOCK;

-- Expire password
ALTER USER 'appuser'@'%' PASSWORD EXPIRE;

-- Set password expiration policy
ALTER USER 'appuser'@'%' PASSWORD EXPIRE INTERVAL 90 DAY;

-- Modify resource limits
ALTER USER 'appuser'@'%'
  WITH MAX_QUERIES_PER_HOUR 2000
       MAX_CONNECTIONS_PER_HOUR 200;

-- Rename user
RENAME USER 'olduser'@'%' TO 'newuser'@'%';
```

### Removing Users

```sql
-- Drop user
DROP USER 'appuser'@'%';

-- Drop multiple users
DROP USER 'user1'@'%', 'user2'@'%', 'user3'@'%';

-- Drop user if exists
DROP USER IF EXISTS 'appuser'@'%';
```

**⚠️ WARNING:** Dropping a user does not drop their databases or tables. It only removes authentication.

```bash
# Safe user removal procedure
docker exec mysql mysql -u root -p << 'EOF'
-- 1. List user's privileges
SHOW GRANTS FOR 'appuser'@'%';

-- 2. Revoke all privileges
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'appuser'@'%';

-- 3. Drop user
DROP USER 'appuser'@'%';

-- 4. Verify removal
SELECT user, host FROM mysql.user WHERE user = 'appuser';
EOF
```

## Database Management

### Creating Databases

```sql
-- Create database with default settings
CREATE DATABASE myapp;

-- Create database with character set
CREATE DATABASE myapp CHARACTER SET utf8mb4;

-- Create database with collation
CREATE DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS myapp;
```

From command line:

```bash
# Create database
docker exec mysql mysql -u root -p -e "CREATE DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

# Create database from SQL file
docker exec -i mysql mysql -u root -p << EOF
CREATE DATABASE IF NOT EXISTS myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
EOF
```

### Listing Databases

```sql
-- Show all databases
SHOW DATABASES;

-- Show databases matching pattern
SHOW DATABASES LIKE 'myapp%';

-- Get database information
SELECT schema_name, default_character_set_name, default_collation_name
FROM information_schema.schemata;

-- Get database size
SELECT
  table_schema AS 'Database',
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
FROM information_schema.tables
GROUP BY table_schema
ORDER BY SUM(data_length + index_length) DESC;
```

### Switching Databases

```sql
-- Switch to database
USE myapp;

-- Verify current database
SELECT DATABASE();
```

### Dropping Databases

```sql
-- Drop database
DROP DATABASE myapp;

-- Drop database if exists
DROP DATABASE IF EXISTS myapp;
```

**⚠️ WARNING:** Dropping a database permanently deletes all tables and data. Always backup first!

```bash
# Safe database drop procedure
# 1. Backup database first
docker exec mysql mysqldump -u root -p myapp > myapp_backup_$(date +%Y%m%d_%H%M%S).sql

# 2. Verify backup
ls -lh myapp_backup_*.sql

# 3. Drop database
docker exec mysql mysql -u root -p -e "DROP DATABASE myapp;"

# 4. Verify removal
docker exec mysql mysql -u root -p -e "SHOW DATABASES LIKE 'myapp';"
```

### Database Properties

```sql
-- Show database creation statement
SHOW CREATE DATABASE myapp;

-- Get database metadata
SELECT * FROM information_schema.schemata WHERE schema_name = 'myapp';

-- Show database tables
SHOW TABLES FROM myapp;

-- Count tables in database
SELECT COUNT(*) AS table_count
FROM information_schema.tables
WHERE table_schema = 'myapp';

-- Get database statistics
SELECT
  table_schema,
  COUNT(*) AS tables,
  SUM(table_rows) AS total_rows,
  ROUND(SUM(data_length) / 1024 / 1024, 2) AS data_mb,
  ROUND(SUM(index_length) / 1024 / 1024, 2) AS index_mb,
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS total_mb
FROM information_schema.tables
WHERE table_schema = 'myapp'
GROUP BY table_schema;
```

## Schema Operations

### Creating Tables

```sql
-- Basic table creation
CREATE TABLE users (
  id INT PRIMARY KEY AUTO_INCREMENT,
  username VARCHAR(50) NOT NULL UNIQUE,
  email VARCHAR(100) NOT NULL UNIQUE,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Table with foreign key
CREATE TABLE posts (
  id INT PRIMARY KEY AUTO_INCREMENT,
  user_id INT NOT NULL,
  title VARCHAR(200) NOT NULL,
  content TEXT,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Table with indexes
CREATE TABLE products (
  id INT PRIMARY KEY AUTO_INCREMENT,
  sku VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  price DECIMAL(10, 2) NOT NULL,
  quantity INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_name (name),
  INDEX idx_price (price),
  FULLTEXT INDEX ft_description (description)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Table with composite key
CREATE TABLE user_roles (
  user_id INT NOT NULL,
  role_id INT NOT NULL,
  assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, role_id),
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
  FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE
);

-- Table with partitioning
CREATE TABLE logs (
  id INT NOT NULL AUTO_INCREMENT,
  log_date DATE NOT NULL,
  message TEXT,
  PRIMARY KEY (id, log_date)
)
PARTITION BY RANGE (YEAR(log_date)) (
  PARTITION p2023 VALUES LESS THAN (2024),
  PARTITION p2024 VALUES LESS THAN (2025),
  PARTITION p2025 VALUES LESS THAN (2026)
);
```

### Altering Tables

```sql
-- Add column
ALTER TABLE users ADD COLUMN phone VARCHAR(20);

-- Add column with position
ALTER TABLE users ADD COLUMN middle_name VARCHAR(50) AFTER first_name;

-- Modify column
ALTER TABLE users MODIFY COLUMN phone VARCHAR(30);

-- Change column name and type
ALTER TABLE users CHANGE COLUMN phone phone_number VARCHAR(30);

-- Drop column
ALTER TABLE users DROP COLUMN middle_name;

-- Add index
ALTER TABLE users ADD INDEX idx_email (email);

-- Add unique constraint
ALTER TABLE users ADD UNIQUE KEY uk_username (username);

-- Add foreign key
ALTER TABLE posts ADD CONSTRAINT fk_user
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

-- Drop foreign key
ALTER TABLE posts DROP FOREIGN KEY fk_user;

-- Drop index
ALTER TABLE users DROP INDEX idx_email;

-- Rename table
ALTER TABLE users RENAME TO app_users;

-- Change engine
ALTER TABLE users ENGINE=InnoDB;

-- Change character set
ALTER TABLE users CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Add auto_increment
ALTER TABLE users AUTO_INCREMENT = 1000;
```

### Viewing Table Structure

```sql
-- Describe table
DESCRIBE users;
DESC users;

-- Show table creation statement
SHOW CREATE TABLE users;

-- Show table columns
SHOW COLUMNS FROM users;

-- Show table indexes
SHOW INDEXES FROM users;

-- Show table status
SHOW TABLE STATUS LIKE 'users';

-- Get column information
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default,
  column_key
FROM information_schema.columns
WHERE table_schema = 'myapp' AND table_name = 'users';

-- Get foreign key information
SELECT
  constraint_name,
  table_name,
  column_name,
  referenced_table_name,
  referenced_column_name
FROM information_schema.key_column_usage
WHERE table_schema = 'myapp' AND referenced_table_name IS NOT NULL;
```

### Dropping Tables

```sql
-- Drop table
DROP TABLE users;

-- Drop table if exists
DROP TABLE IF EXISTS users;

-- Drop multiple tables
DROP TABLE IF EXISTS users, posts, comments;

-- Drop table with foreign key constraints (order matters)
DROP TABLE IF EXISTS posts, users;  -- Wrong order!
DROP TABLE IF EXISTS users, posts;  -- Correct order
```

**⚠️ WARNING:** Foreign key constraints prevent dropping referenced tables. Drop dependent tables first or use CASCADE.

### Table Statistics

```sql
-- Get table size
SELECT
  table_name,
  table_rows,
  ROUND(data_length / 1024 / 1024, 2) AS data_mb,
  ROUND(index_length / 1024 / 1024, 2) AS index_mb,
  ROUND((data_length + index_length) / 1024 / 1024, 2) AS total_mb
FROM information_schema.tables
WHERE table_schema = 'myapp'
ORDER BY (data_length + index_length) DESC;

-- Get table fragmentation
SELECT
  table_name,
  ROUND(data_length / 1024 / 1024, 2) AS data_mb,
  ROUND(data_free / 1024 / 1024, 2) AS free_mb,
  ROUND((data_free / data_length) * 100, 2) AS fragmentation_pct
FROM information_schema.tables
WHERE table_schema = 'myapp' AND data_length > 0
ORDER BY data_free DESC;

-- Get row count for all tables
SELECT
  table_name,
  table_rows,
  create_time,
  update_time
FROM information_schema.tables
WHERE table_schema = 'myapp'
ORDER BY table_rows DESC;
```

## Query Optimization

### Using EXPLAIN

```sql
-- Basic EXPLAIN
EXPLAIN SELECT * FROM users WHERE email = 'user@example.com';

-- EXPLAIN with format
EXPLAIN FORMAT=JSON SELECT * FROM users WHERE email = 'user@example.com';
EXPLAIN FORMAT=TREE SELECT * FROM users WHERE email = 'user@example.com';

-- EXPLAIN for complex query
EXPLAIN SELECT u.username, COUNT(p.id) as post_count
FROM users u
LEFT JOIN posts p ON u.id = p.user_id
WHERE u.created_at > '2024-01-01'
GROUP BY u.id
ORDER BY post_count DESC
LIMIT 10;

-- EXPLAIN ANALYZE (shows actual execution)
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user@example.com';
```

Understanding EXPLAIN output:

```sql
-- Example output interpretation:
-- id: Query identifier (1 = outermost query)
-- select_type: SIMPLE, PRIMARY, SUBQUERY, DERIVED, UNION
-- table: Table being accessed
-- type: Join type (system, const, eq_ref, ref, range, index, ALL)
--       Best to worst: const > eq_ref > ref > range > index > ALL
-- possible_keys: Indexes that could be used
-- key: Index actually used
-- key_len: Length of key used
-- ref: Columns compared to index
-- rows: Estimated rows examined
-- Extra: Additional information

-- Check for inefficiencies:
-- - type: ALL (full table scan) - needs index
-- - Extra: Using filesort - needs index for ORDER BY
-- - Extra: Using temporary - needs optimization
-- - rows: High number - inefficient query
```

### Query Planning

```sql
-- Force index usage
SELECT * FROM users FORCE INDEX (idx_email) WHERE email = 'user@example.com';

-- Ignore index
SELECT * FROM users IGNORE INDEX (idx_email) WHERE email = 'user@example.com';

-- Use specific index
SELECT * FROM users USE INDEX (idx_email) WHERE email = 'user@example.com';

-- Optimize query with proper joins
-- Bad: Cartesian product
SELECT * FROM users, posts WHERE users.id = posts.user_id;

-- Good: Explicit JOIN
SELECT * FROM users u
INNER JOIN posts p ON u.id = p.user_id;

-- Optimize subqueries with EXISTS
-- Bad: Subquery
SELECT * FROM users WHERE id IN (SELECT user_id FROM posts WHERE created_at > '2024-01-01');

-- Good: EXISTS
SELECT * FROM users u WHERE EXISTS (
  SELECT 1 FROM posts p WHERE p.user_id = u.id AND p.created_at > '2024-01-01'
);

-- Optimize with LIMIT
SELECT * FROM users ORDER BY created_at DESC LIMIT 10;

-- Use covering indexes
CREATE INDEX idx_user_posts ON posts(user_id, created_at, title);
SELECT user_id, created_at, title FROM posts WHERE user_id = 123;  -- Uses covering index
```

### Index Usage Analysis

```sql
-- Check index cardinality
SHOW INDEXES FROM users;

-- Analyze index usage
SELECT
  database_name,
  table_name,
  index_name,
  seq_in_index,
  column_name,
  cardinality
FROM information_schema.statistics
WHERE table_schema = 'myapp'
ORDER BY table_name, index_name, seq_in_index;

-- Find unused indexes
SELECT
  t.table_schema,
  t.table_name,
  s.index_name,
  s.column_name
FROM information_schema.tables t
INNER JOIN information_schema.statistics s ON t.table_schema = s.table_schema
  AND t.table_name = s.table_name
LEFT JOIN performance_schema.table_io_waits_summary_by_index_usage i
  ON i.object_schema = t.table_schema
  AND i.object_name = t.table_name
  AND i.index_name = s.index_name
WHERE t.table_schema = 'myapp'
  AND s.index_name != 'PRIMARY'
  AND i.index_name IS NULL;

-- Check index selectivity
SELECT
  COUNT(DISTINCT email) / COUNT(*) AS selectivity
FROM users;  -- Close to 1.0 = highly selective (good for index)
```

### Slow Query Log

Enable and analyze slow query log:

```sql
-- Enable slow query log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;  -- Log queries taking > 2 seconds
SET GLOBAL log_queries_not_using_indexes = 'ON';

-- Check slow query log settings
SHOW VARIABLES LIKE 'slow_query%';
SHOW VARIABLES LIKE 'long_query_time';

-- View slow query log location
SHOW VARIABLES LIKE 'slow_query_log_file';
```

Analyze slow query log:

```bash
# View slow query log
docker exec mysql tail -100 /var/lib/mysql/slow-query.log

# Use mysqldumpslow to analyze
docker exec mysql mysqldumpslow /var/lib/mysql/slow-query.log

# Show 10 slowest queries
docker exec mysql mysqldumpslow -s t -t 10 /var/lib/mysql/slow-query.log

# Show queries not using indexes
docker exec mysql mysqldumpslow -s t /var/lib/mysql/slow-query.log | grep "No index"

# Clear slow query log
docker exec mysql mysql -u root -p -e "SET GLOBAL slow_query_log = 'OFF';"
docker exec mysql bash -c "> /var/lib/mysql/slow-query.log"
docker exec mysql mysql -u root -p -e "SET GLOBAL slow_query_log = 'ON';"
```

### Query Cache

MySQL 8.0 removed query cache. Use application-level caching with Redis instead:

```python
import redis
import json
import hashlib

redis_client = redis.Redis(host='redis-1', port=6379)

def get_cached_query(query, params):
    # Generate cache key from query + params
    cache_key = hashlib.md5(f"{query}{json.dumps(params)}".encode()).hexdigest()

    # Try cache first
    cached = redis_client.get(f"query:{cache_key}")
    if cached:
        return json.loads(cached)

    # Execute query if not cached
    result = execute_query(query, params)

    # Cache result for 5 minutes
    redis_client.setex(f"query:{cache_key}", 300, json.dumps(result))

    return result
```

## Performance Monitoring

### Server Status

```sql
-- Show all status variables
SHOW STATUS;

-- Show specific status
SHOW STATUS LIKE 'Threads_connected';
SHOW STATUS LIKE 'Queries';
SHOW STATUS LIKE 'Uptime';

-- Show InnoDB status
SHOW ENGINE INNODB STATUS;

-- Key performance metrics
SHOW STATUS WHERE Variable_name IN (
  'Threads_connected',
  'Threads_running',
  'Queries',
  'Slow_queries',
  'Questions',
  'Uptime',
  'Open_tables',
  'Table_locks_waited',
  'Innodb_buffer_pool_read_requests',
  'Innodb_buffer_pool_reads'
);
```

Monitor from command line:

```bash
# Watch thread count
watch -n 1 'docker exec mysql mysql -u root -p -e "SHOW STATUS LIKE \"Threads_%\";"'

# Monitor queries per second
docker exec mysql mysqladmin -u root -p -i 1 extended-status | grep Questions

# Monitor connection usage
docker exec mysql mysql -u root -p -e "
SELECT
  (SELECT COUNT(*) FROM information_schema.processlist) AS current_connections,
  (SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME='max_connections') AS max_connections,
  ROUND((SELECT COUNT(*) FROM information_schema.processlist) /
        (SELECT VARIABLE_VALUE FROM performance_schema.global_variables WHERE VARIABLE_NAME='max_connections') * 100, 2) AS usage_pct;"
```

### Process List

```sql
-- Show all processes
SHOW PROCESSLIST;

-- Show full process list
SHOW FULL PROCESSLIST;

-- Get process information
SELECT * FROM information_schema.processlist;

-- Find long-running queries
SELECT
  id,
  user,
  host,
  db,
  command,
  time,
  state,
  LEFT(info, 100) AS query
FROM information_schema.processlist
WHERE time > 10 AND command != 'Sleep'
ORDER BY time DESC;

-- Count connections by user
SELECT
  user,
  COUNT(*) AS connections
FROM information_schema.processlist
GROUP BY user
ORDER BY connections DESC;

-- Kill specific process
KILL 12345;  -- Replace with actual process id
```

### Performance Schema

Enable and use Performance Schema:

```sql
-- Check if Performance Schema is enabled
SHOW VARIABLES LIKE 'performance_schema';

-- Enable specific instruments
UPDATE performance_schema.setup_instruments
SET enabled = 'YES', timed = 'YES'
WHERE name LIKE 'statement/%';

-- Top queries by execution time
SELECT
  digest_text,
  count_star,
  avg_timer_wait / 1000000000000 AS avg_seconds,
  sum_timer_wait / 1000000000000 AS total_seconds
FROM performance_schema.events_statements_summary_by_digest
ORDER BY sum_timer_wait DESC
LIMIT 10;

-- Table I/O statistics
SELECT
  object_schema,
  object_name,
  count_read,
  count_write,
  count_fetch,
  count_insert,
  count_update,
  count_delete
FROM performance_schema.table_io_waits_summary_by_table
WHERE object_schema = 'myapp'
ORDER BY (count_read + count_write) DESC;

-- Index usage statistics
SELECT
  object_schema,
  object_name,
  index_name,
  count_read,
  count_write,
  count_fetch,
  count_insert,
  count_update,
  count_delete
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = 'myapp'
ORDER BY (count_read + count_write) DESC;
```

### Identifying Slow Queries

```sql
-- Real-time monitoring of slow queries
SELECT
  processlist_id,
  processlist_user,
  processlist_host,
  processlist_db,
  processlist_command,
  processlist_time,
  processlist_state,
  LEFT(processlist_info, 200) AS query
FROM performance_schema.threads
WHERE processlist_time > 5
  AND processlist_command != 'Sleep'
ORDER BY processlist_time DESC;

-- Historical slow query analysis
SELECT
  SUBSTRING(digest_text, 1, 100) AS query,
  count_star AS exec_count,
  ROUND(avg_timer_wait / 1000000000000, 2) AS avg_sec,
  ROUND(max_timer_wait / 1000000000000, 2) AS max_sec,
  ROUND(sum_timer_wait / 1000000000000, 2) AS total_sec
FROM performance_schema.events_statements_summary_by_digest
WHERE schema_name = 'myapp'
ORDER BY sum_timer_wait DESC
LIMIT 20;
```

### Resource Usage

```sql
-- Buffer pool usage
SELECT
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_pages_total') AS total_pages,
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_pages_free') AS free_pages,
  (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_pages_data') AS data_pages,
  ROUND((SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_pages_data') /
        (SELECT VARIABLE_VALUE FROM performance_schema.global_status WHERE VARIABLE_NAME='Innodb_buffer_pool_pages_total') * 100, 2) AS usage_pct;

-- Memory usage by storage engine
SELECT
  engine,
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS total_mb
FROM information_schema.tables
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql', 'sys')
GROUP BY engine;

-- Temporary table usage
SHOW STATUS LIKE 'Created_tmp%';

-- Table lock wait statistics
SHOW STATUS LIKE 'Table_locks_waited';
```

Monitor from Docker:

```bash
# Container resource usage
docker stats mysql --no-stream

# Detailed container stats
docker exec mysql ps aux

# Memory usage
docker exec mysql free -h

# Disk usage
docker exec mysql df -h

# MySQL data directory size
docker exec mysql du -sh /var/lib/mysql
```

## Index Management

### Index Types

MySQL supports several index types:

1. **B-Tree Index** (default): Best for equality and range queries
2. **Hash Index**: Fast for exact lookups (MEMORY engine only)
3. **Full-Text Index**: For text searching
4. **Spatial Index**: For geographic data (requires SPATIAL column type)

### Creating Indexes

```sql
-- Single column index
CREATE INDEX idx_email ON users(email);

-- Multi-column (composite) index
CREATE INDEX idx_user_created ON posts(user_id, created_at);

-- Unique index
CREATE UNIQUE INDEX uk_username ON users(username);

-- Full-text index
CREATE FULLTEXT INDEX ft_content ON posts(title, content);

-- Index with length limit (for VARCHAR/TEXT)
CREATE INDEX idx_username_prefix ON users(username(10));

-- Index with sort order
CREATE INDEX idx_created_desc ON posts(created_at DESC);

-- Partial index (expression index)
CREATE INDEX idx_active_users ON users((CASE WHEN active = 1 THEN id END));

-- Using ALTER TABLE
ALTER TABLE users ADD INDEX idx_email (email);
ALTER TABLE users ADD UNIQUE KEY uk_username (username);
ALTER TABLE users ADD FULLTEXT INDEX ft_bio (bio);
```

Create indexes from command line:

```bash
# Create index
docker exec mysql mysql -u root -p myapp -e "CREATE INDEX idx_email ON users(email);"

# Create multiple indexes
docker exec mysql mysql -u root -p myapp << 'EOF'
CREATE INDEX idx_email ON users(email);
CREATE INDEX idx_created ON users(created_at);
CREATE INDEX idx_status ON users(status);
EOF
```

### Index Maintenance

```sql
-- Rebuild indexes (drops and recreates)
ALTER TABLE users DROP INDEX idx_email, ADD INDEX idx_email (email);

-- Analyze table (updates index statistics)
ANALYZE TABLE users;

-- Optimize table (defragments and rebuilds indexes)
OPTIMIZE TABLE users;

-- Check table integrity
CHECK TABLE users;

-- Repair table if corrupted
REPAIR TABLE users;
```

Maintenance from command line:

```bash
# Analyze all tables in database
docker exec mysql mysql -u root -p myapp -e "
SELECT CONCAT('ANALYZE TABLE ', table_schema, '.', table_name, ';')
FROM information_schema.tables
WHERE table_schema = 'myapp';" | docker exec -i mysql mysql -u root -p

# Optimize all tables
docker exec mysql mysqlcheck -u root -p --optimize myapp

# Analyze all tables
docker exec mysql mysqlcheck -u root -p --analyze myapp

# Check all tables
docker exec mysql mysqlcheck -u root -p --check myapp
```

### Index Optimization

```sql
-- Check index cardinality (selectivity)
SHOW INDEX FROM users;

-- Find duplicate indexes
SELECT
  t.table_schema,
  t.table_name,
  GROUP_CONCAT(s.index_name) AS duplicate_indexes,
  GROUP_CONCAT(s.column_name) AS columns
FROM information_schema.statistics s
INNER JOIN information_schema.tables t ON s.table_schema = t.table_schema
  AND s.table_name = t.table_name
WHERE t.table_schema = 'myapp'
GROUP BY t.table_schema, t.table_name, s.column_name
HAVING COUNT(DISTINCT s.index_name) > 1;

-- Find redundant indexes (covered by other indexes)
-- Example: If you have idx_user_created(user_id, created_at)
--          then idx_user(user_id) is redundant

-- Recommend indexes for query
EXPLAIN SELECT * FROM users WHERE email = 'user@example.com' AND status = 'active';
-- If type = ALL, consider: CREATE INDEX idx_email_status ON users(email, status);

-- Index prefix length optimization
SELECT
  COUNT(DISTINCT LEFT(email, 5)) / COUNT(*) AS prefix_5,
  COUNT(DISTINCT LEFT(email, 10)) / COUNT(*) AS prefix_10,
  COUNT(DISTINCT LEFT(email, 15)) / COUNT(*) AS prefix_15,
  COUNT(DISTINCT email) / COUNT(*) AS full_column
FROM users;
-- Use prefix length where selectivity is still high
```

### Index Statistics

```sql
-- Index size per table
SELECT
  table_schema,
  table_name,
  ROUND(index_length / 1024 / 1024, 2) AS index_mb
FROM information_schema.tables
WHERE table_schema = 'myapp'
ORDER BY index_length DESC;

-- Index details
SELECT
  table_schema,
  table_name,
  index_name,
  GROUP_CONCAT(column_name ORDER BY seq_in_index) AS columns,
  index_type,
  non_unique,
  cardinality
FROM information_schema.statistics
WHERE table_schema = 'myapp'
GROUP BY table_schema, table_name, index_name, index_type, non_unique, cardinality
ORDER BY table_name, index_name;

-- Index usage from Performance Schema
SELECT
  object_schema,
  object_name,
  index_name,
  count_read,
  count_write
FROM performance_schema.table_io_waits_summary_by_index_usage
WHERE object_schema = 'myapp'
ORDER BY (count_read + count_write) DESC;
```

## Maintenance Operations

### Table Optimization

```sql
-- Optimize single table (defragments, reclaims space, rebuilds indexes)
OPTIMIZE TABLE users;

-- Optimize multiple tables
OPTIMIZE TABLE users, posts, comments;

-- Optimize all tables in database
SELECT CONCAT('OPTIMIZE TABLE ', table_schema, '.', table_name, ';')
FROM information_schema.tables
WHERE table_schema = 'myapp';

-- Check if optimization is needed
SELECT
  table_name,
  ROUND(data_length / 1024 / 1024, 2) AS data_mb,
  ROUND(data_free / 1024 / 1024, 2) AS free_mb,
  ROUND((data_free / (data_length + data_free)) * 100, 2) AS fragmentation_pct
FROM information_schema.tables
WHERE table_schema = 'myapp'
  AND data_length > 0
  AND (data_free / (data_length + data_free)) > 0.1  -- More than 10% fragmentation
ORDER BY fragmentation_pct DESC;
```

**⚠️ WARNING:** OPTIMIZE TABLE locks the table during operation. Use during maintenance windows.

### Table Analysis

```sql
-- Analyze table (updates index statistics for query optimizer)
ANALYZE TABLE users;

-- Analyze all tables
ANALYZE TABLE users, posts, comments;

-- Check when tables were last analyzed
SELECT
  table_schema,
  table_name,
  update_time,
  check_time
FROM information_schema.tables
WHERE table_schema = 'myapp'
ORDER BY check_time;
```

Schedule regular analysis:

```bash
# Create maintenance script
cat > /tmp/mysql-maintenance.sh << 'EOF'
#!/bin/bash
docker exec mysql mysqlcheck -u root -p"${MYSQL_PASSWORD}" --analyze --all-databases
docker exec mysql mysqlcheck -u root -p"${MYSQL_PASSWORD}" --optimize --all-databases
EOF

chmod +x /tmp/mysql-maintenance.sh

# Run weekly via cron
# 0 2 * * 0 /tmp/mysql-maintenance.sh >> /var/log/mysql-maintenance.log 2>&1
```

### Table Repair

```sql
-- Check table for errors
CHECK TABLE users;

-- Extended check (slower but thorough)
CHECK TABLE users EXTENDED;

-- Quick check
CHECK TABLE users QUICK;

-- Repair table if corrupted
REPAIR TABLE users;

-- Extended repair
REPAIR TABLE users EXTENDED;

-- Quick repair
REPAIR TABLE users QUICK;
```

Repair from command line:

```bash
# Check all tables in database
docker exec mysql mysqlcheck -u root -p --check myapp

# Repair all tables
docker exec mysql mysqlcheck -u root -p --repair myapp

# Check and auto-repair
docker exec mysql mysqlcheck -u root -p --auto-repair myapp

# Extended check
docker exec mysql mysqlcheck -u root -p --check --extended myapp
```

### InnoDB Maintenance

```sql
-- View InnoDB status
SHOW ENGINE INNODB STATUS;

-- Purge InnoDB history
SET GLOBAL innodb_purge_batch_size = 300;
SET GLOBAL innodb_purge_threads = 4;

-- Monitor InnoDB buffer pool
SELECT
  SUBSTRING_INDEX(SUBSTRING_INDEX(name, '/', 2), '/', -1) AS database_name,
  SUBSTRING_INDEX(SUBSTRING_INDEX(name, '/', 3), '/', -1) AS table_name,
  COUNT(*) AS pages,
  ROUND(COUNT(*) * 16 / 1024, 2) AS mb
FROM information_schema.innodb_buffer_page
GROUP BY database_name, table_name
ORDER BY pages DESC
LIMIT 20;

-- Check InnoDB file per table
SHOW VARIABLES LIKE 'innodb_file_per_table';

-- Enable file per table (requires restart)
SET GLOBAL innodb_file_per_table = 1;

-- Reclaim space from InnoDB (requires rebuild)
ALTER TABLE users ENGINE=InnoDB;
```

### Checksum Operations

```sql
-- Calculate table checksum
CHECKSUM TABLE users;

-- Extended checksum (includes data)
CHECKSUM TABLE users EXTENDED;

-- Verify data integrity
SELECT
  table_schema,
  table_name,
  checksum
FROM information_schema.tables
WHERE table_schema = 'myapp' AND checksum IS NOT NULL;
```

## Backup Operations

### Logical Backups with mysqldump

```bash
# Backup single database
docker exec mysql mysqldump -u root -p myapp > myapp_backup_$(date +%Y%m%d_%H%M%S).sql

# Backup specific tables
docker exec mysql mysqldump -u root -p myapp users posts > tables_backup.sql

# Backup with compression
docker exec mysql mysqldump -u root -p myapp | gzip > myapp_backup.sql.gz

# Backup all databases
docker exec mysql mysqldump -u root -p --all-databases > all_databases_backup.sql

# Backup with routines and triggers
docker exec mysql mysqldump -u root -p --routines --triggers myapp > myapp_full_backup.sql

# Backup with single transaction (consistent snapshot)
docker exec mysql mysqldump -u root -p --single-transaction --routines --triggers myapp > myapp_backup.sql

# Backup excluding specific tables
docker exec mysql mysqldump -u root -p myapp --ignore-table=myapp.logs --ignore-table=myapp.temp > myapp_backup.sql

# Backup with extended inserts (faster restore)
docker exec mysql mysqldump -u root -p --extended-insert myapp > myapp_backup.sql

# Backup schema only (no data)
docker exec mysql mysqldump -u root -p --no-data myapp > myapp_schema.sql

# Backup data only (no schema)
docker exec mysql mysqldump -u root -p --no-create-info myapp > myapp_data.sql

# Backup with where clause
docker exec mysql mysqldump -u root -p myapp users --where="created_at > '2024-01-01'" > recent_users.sql
```

Restore from mysqldump:

```bash
# Restore database
docker exec -i mysql mysql -u root -p myapp < myapp_backup.sql

# Restore compressed backup
gunzip < myapp_backup.sql.gz | docker exec -i mysql mysql -u root -p myapp

# Restore all databases
docker exec -i mysql mysql -u root -p < all_databases_backup.sql

# Restore specific table
docker exec -i mysql mysql -u root -p myapp < tables_backup.sql

# Restore with progress
pv myapp_backup.sql | docker exec -i mysql mysql -u root -p myapp
```

### Logical Backups with mysqlpump

```bash
# Backup with mysqlpump (parallel, faster)
docker exec mysql mysqlpump -u root -p myapp > myapp_backup.sql

# Parallel backup (4 threads)
docker exec mysql mysqlpump -u root -p --default-parallelism=4 myapp > myapp_backup.sql

# Backup excluding databases
docker exec mysql mysqlpump -u root -p --exclude-databases=information_schema,performance_schema,sys > backup.sql

# Backup excluding tables
docker exec mysql mysqlpump -u root -p --exclude-tables=myapp.logs myapp > backup.sql

# Backup with compression
docker exec mysql mysqlpump -u root -p --compress-output=ZLIB myapp > myapp_backup.zlib
```

### Binary Backups

Copy MySQL data directory (requires stopped MySQL):

```bash
# Stop MySQL
docker compose stop mysql

# Backup data volume
docker run --rm -v mysql-data:/data -v $(pwd)/backups:/backup alpine tar czf /backup/mysql-data-$(date +%Y%m%d_%H%M%S).tar.gz -C /data .

# Start MySQL
docker compose start mysql

# Verify backup
ls -lh backups/mysql-data-*.tar.gz
```

Restore binary backup:

```bash
# Stop MySQL
docker compose stop mysql

# Restore data volume
docker run --rm -v mysql-data:/data -v $(pwd)/backups:/backup alpine sh -c "rm -rf /data/* && tar xzf /backup/mysql-data-20240115_120000.tar.gz -C /data"

# Start MySQL
docker compose start mysql

# Verify
docker exec mysql mysql -u root -p -e "SHOW DATABASES;"
```

### Point-in-Time Recovery

Enable binary logging:

```sql
-- Check if binary log is enabled
SHOW VARIABLES LIKE 'log_bin';

-- View binary logs
SHOW BINARY LOGS;

-- View binary log events
SHOW BINLOG EVENTS IN 'mysql-bin.000001';

-- Flush binary log (start new file)
FLUSH BINARY LOGS;

-- Purge old binary logs
PURGE BINARY LOGS BEFORE '2024-01-01 00:00:00';
PURGE BINARY LOGS TO 'mysql-bin.000010';
```

Perform point-in-time recovery:

```bash
# 1. Restore from last full backup
docker exec -i mysql mysql -u root -p < myapp_backup_20240115_000000.sql

# 2. Apply binary logs up to specific point
docker exec mysql mysqlbinlog /var/lib/mysql/mysql-bin.000001 | docker exec -i mysql mysql -u root -p myapp

# 3. Apply binary logs up to specific time
docker exec mysql mysqlbinlog --stop-datetime="2024-01-15 14:30:00" /var/lib/mysql/mysql-bin.000001 | docker exec -i mysql mysql -u root -p myapp

# 4. Apply binary logs from specific position
docker exec mysql mysqlbinlog --start-position=12345 /var/lib/mysql/mysql-bin.000001 | docker exec -i mysql mysql -u root -p myapp
```

### Backup Verification

```bash
# Verify backup file integrity
file myapp_backup.sql
head -20 myapp_backup.sql
tail -20 myapp_backup.sql

# Check backup size
ls -lh myapp_backup.sql

# Verify compressed backup
gunzip -t myapp_backup.sql.gz

# Test restore to temporary database
docker exec mysql mysql -u root -p -e "CREATE DATABASE myapp_test;"
docker exec -i mysql mysql -u root -p myapp_test < myapp_backup.sql
docker exec mysql mysql -u root -p -e "SHOW TABLES FROM myapp_test;"
docker exec mysql mysql -u root -p -e "DROP DATABASE myapp_test;"

# Compare row counts
docker exec mysql mysql -u root -p -e "
SELECT table_name, table_rows
FROM information_schema.tables
WHERE table_schema = 'myapp'
ORDER BY table_name;"
```

Complete backup script:

```bash
#!/bin/bash
# MySQL backup script

BACKUP_DIR="/Users/gator/devstack-core/backups/mysql"
DATE=$(date +%Y%m%d_%H%M%S)
MYSQL_USER="root"
MYSQL_PASS=$(vault kv get -field=password secret/mysql)

mkdir -p "${BACKUP_DIR}"

# Backup all databases
echo "Starting MySQL backup..."
docker exec mysql mysqldump -u ${MYSQL_USER} -p"${MYSQL_PASS}" \
  --single-transaction \
  --routines \
  --triggers \
  --all-databases | gzip > "${BACKUP_DIR}/all_databases_${DATE}.sql.gz"

# Verify backup
if [ -f "${BACKUP_DIR}/all_databases_${DATE}.sql.gz" ]; then
  SIZE=$(du -h "${BACKUP_DIR}/all_databases_${DATE}.sql.gz" | cut -f1)
  echo "Backup completed: ${BACKUP_DIR}/all_databases_${DATE}.sql.gz (${SIZE})"
else
  echo "Backup failed!"
  exit 1
fi

# Cleanup old backups (keep last 7 days)
find "${BACKUP_DIR}" -name "all_databases_*.sql.gz" -mtime +7 -delete

echo "Backup retention: Removed backups older than 7 days"
```

## Replication

### Replication Overview

MySQL replication types:
- **Asynchronous**: Master doesn't wait for slave acknowledgment (default)
- **Semi-synchronous**: Master waits for at least one slave acknowledgment
- **Group Replication**: Multi-master with conflict detection

**Note:** Replication is optional for development. The default DevStack Core setup is single-instance.

### Master-Slave Setup

Configure master:

```sql
-- On master: Enable binary logging
-- Edit my.cnf:
-- [mysqld]
-- server-id=1
-- log_bin=mysql-bin
-- binlog_do_db=myapp

-- Restart MySQL
-- docker compose restart mysql

-- Create replication user
CREATE USER 'repl'@'%' IDENTIFIED BY 'ReplPassword123!';
GRANT REPLICATION SLAVE ON *.* TO 'repl'@'%';
FLUSH PRIVILEGES;

-- Get master status
SHOW MASTER STATUS;
-- Note: File and Position values
```

Configure slave:

```sql
-- On slave: Configure server-id
-- Edit my.cnf:
-- [mysqld]
-- server-id=2

-- Restart MySQL

-- Configure replication
CHANGE MASTER TO
  MASTER_HOST='master-ip',
  MASTER_USER='repl',
  MASTER_PASSWORD='ReplPassword123!',
  MASTER_LOG_FILE='mysql-bin.000001',  -- From SHOW MASTER STATUS
  MASTER_LOG_POS=12345;                 -- From SHOW MASTER STATUS

-- Start replication
START SLAVE;

-- Check slave status
SHOW SLAVE STATUS\G
```

### Monitoring Replication

```sql
-- Check slave status
SHOW SLAVE STATUS\G

-- Key fields to monitor:
-- Slave_IO_Running: Yes (IO thread running)
-- Slave_SQL_Running: Yes (SQL thread running)
-- Seconds_Behind_Master: Replication lag in seconds
-- Last_Error: Any replication errors

-- Check master status
SHOW MASTER STATUS;

-- View binary log position
SHOW MASTER LOGS;

-- Check replication user
SELECT user, host FROM mysql.user WHERE Repl_slave_priv = 'Y';
```

### Replication Troubleshooting

```sql
-- Stop replication
STOP SLAVE;

-- Reset slave (clears replication state)
RESET SLAVE;

-- Skip replication error (dangerous!)
SET GLOBAL sql_slave_skip_counter = 1;
START SLAVE;

-- Re-synchronize slave
STOP SLAVE;
CHANGE MASTER TO MASTER_LOG_FILE='mysql-bin.000002', MASTER_LOG_POS=4;
START SLAVE;

-- Check replication errors
SHOW SLAVE STATUS\G
-- Look at: Last_IO_Error, Last_SQL_Error

-- Fix common issues:

-- 1. Slave lag
-- Check Seconds_Behind_Master
-- Increase slave resources
-- Use parallel replication

-- 2. Duplicate key error
-- Skip error or fix data inconsistency

-- 3. Connection issues
-- Verify network connectivity
-- Check replication user privileges
```

## Troubleshooting

### Connection Issues

**Symptom:** Cannot connect to MySQL

```bash
# 1. Check if MySQL is running
docker ps | grep mysql

# 2. Check MySQL logs
docker logs mysql --tail 50

# 3. Test port accessibility
nc -zv localhost 3306
telnet localhost 3306

# 4. Check from container network
docker exec -it dev-reference-api nc -zv mysql 3306

# 5. Verify MySQL is listening
docker exec mysql netstat -tlnp | grep 3306

# 6. Check user privileges
docker exec mysql mysql -u root -p -e "SELECT user, host FROM mysql.user;"

# 7. Test authentication
docker exec mysql mysql -u root -p -e "SELECT 1;"

# 8. Check bind address
docker exec mysql mysql -u root -p -e "SHOW VARIABLES LIKE 'bind_address';"
# Should be 0.0.0.0 or *

# 9. Verify credentials in Vault
vault kv get secret/mysql
```

### Lock Contention

**Symptom:** Queries waiting for locks

```sql
-- View locked tables
SHOW OPEN TABLES WHERE In_use > 0;

-- View processes waiting for locks
SELECT * FROM information_schema.processlist
WHERE state LIKE '%lock%';

-- View InnoDB lock waits
SELECT
  r.trx_id AS waiting_trx_id,
  r.trx_mysql_thread_id AS waiting_thread,
  r.trx_query AS waiting_query,
  b.trx_id AS blocking_trx_id,
  b.trx_mysql_thread_id AS blocking_thread,
  b.trx_query AS blocking_query
FROM information_schema.innodb_lock_waits w
INNER JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_trx_id
INNER JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_trx_id;

-- View lock statistics
SHOW STATUS LIKE 'Table_locks%';

-- Kill blocking query
KILL <thread_id>;
```

Prevent lock contention:

```sql
-- Use shorter transactions
START TRANSACTION;
-- Keep operations minimal
COMMIT;

-- Use proper indexes to reduce lock scope
CREATE INDEX idx_user ON posts(user_id);

-- Use lower isolation levels if appropriate
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- Use SELECT ... FOR UPDATE only when necessary
SELECT * FROM users WHERE id = 123 FOR UPDATE;
```

### Deadlocks

**Symptom:** ERROR 1213: Deadlock found when trying to get lock

```sql
-- View InnoDB status (includes deadlock information)
SHOW ENGINE INNODB STATUS;
-- Look for "LATEST DETECTED DEADLOCK" section

-- Enable deadlock logging
SET GLOBAL innodb_print_all_deadlocks = ON;

-- View deadlock log
-- docker exec mysql tail -100 /var/lib/mysql/error.log
```

Prevent deadlocks:

```sql
-- 1. Access tables in consistent order
-- Bad:
-- Transaction 1: UPDATE users, then posts
-- Transaction 2: UPDATE posts, then users (DEADLOCK!)

-- Good:
-- All transactions: UPDATE users, then posts

-- 2. Keep transactions short
START TRANSACTION;
UPDATE users SET status = 'active' WHERE id = 123;
COMMIT;  -- Don't keep transaction open

-- 3. Use appropriate indexes
-- Reduces lock scope

-- 4. Use lower isolation level if appropriate
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

-- 5. Retry deadlocked transactions
-- Application should catch deadlock error and retry
```

### Disk Space Issues

**Symptom:** ERROR 1114: The table is full

```bash
# Check disk usage
docker exec mysql df -h

# Check MySQL data directory size
docker exec mysql du -sh /var/lib/mysql

# Check database sizes
docker exec mysql mysql -u root -p -e "
SELECT
  table_schema,
  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS size_mb
FROM information_schema.tables
GROUP BY table_schema
ORDER BY size_mb DESC;"

# Check largest tables
docker exec mysql mysql -u root -p -e "
SELECT
  table_schema,
  table_name,
  ROUND((data_length + index_length) / 1024 / 1024, 2) AS size_mb
FROM information_schema.tables
ORDER BY (data_length + index_length) DESC
LIMIT 20;"

# Clean up binary logs
docker exec mysql mysql -u root -p -e "PURGE BINARY LOGS BEFORE NOW() - INTERVAL 7 DAY;"

# Optimize tables to reclaim space
docker exec mysql mysqlcheck -u root -p --optimize myapp
```

### Table Corruption

**Symptom:** Table is marked as crashed

```bash
# Check all tables
docker exec mysql mysqlcheck -u root -p --check --all-databases

# Check specific database
docker exec mysql mysqlcheck -u root -p --check myapp

# Repair corrupted tables
docker exec mysql mysqlcheck -u root -p --repair myapp

# Repair specific table
docker exec mysql mysql -u root -p myapp -e "REPAIR TABLE users;"

# If repair fails, restore from backup
docker exec -i mysql mysql -u root -p myapp < myapp_backup.sql
```

### Performance Issues

**Symptom:** Slow queries, high CPU/memory usage

```bash
# 1. Check resource usage
docker stats mysql --no-stream

# 2. Identify slow queries
docker exec mysql mysql -u root -p -e "
SELECT * FROM information_schema.processlist
WHERE time > 5 AND command != 'Sleep'
ORDER BY time DESC;"

# 3. Check query cache hit rate (if enabled)
docker exec mysql mysql -u root -p -e "
SHOW STATUS LIKE 'Qcache%';"

# 4. Check buffer pool efficiency
docker exec mysql mysql -u root -p -e "
SHOW STATUS WHERE Variable_name LIKE 'Innodb_buffer_pool%';"

# 5. Check for table locks
docker exec mysql mysql -u root -p -e "
SHOW STATUS LIKE 'Table_locks%';"

# 6. Analyze slow query log
docker exec mysql mysqldumpslow -s t -t 10 /var/lib/mysql/slow-query.log

# 7. Optimize poorly performing queries
docker exec mysql mysql -u root -p myapp -e "
EXPLAIN SELECT * FROM users WHERE email = 'user@example.com';"

# 8. Update statistics
docker exec mysql mysqlcheck -u root -p --analyze myapp

# 9. Optimize tables
docker exec mysql mysqlcheck -u root -p --optimize myapp
```

## Security Best Practices

**Development Environment Considerations:**

```sql
-- 1. Use strong passwords
ALTER USER 'root'@'%' IDENTIFIED BY 'VeryStrongPassword123!';

-- 2. Limit user privileges
GRANT SELECT, INSERT, UPDATE ON myapp.* TO 'appuser'@'%';
-- Don't use GRANT ALL unless necessary

-- 3. Use specific hosts instead of '%'
CREATE USER 'appuser'@'172.20.0.%' IDENTIFIED BY 'SecurePass123!';

-- 4. Remove anonymous users
DELETE FROM mysql.user WHERE user = '';

-- 5. Remove test database
DROP DATABASE IF EXISTS test;

-- 6. Disable remote root login
DELETE FROM mysql.user WHERE user = 'root' AND host NOT IN ('localhost', '127.0.0.1', '::1');

-- 7. Enable SSL/TLS (if configured)
SHOW VARIABLES LIKE 'have_ssl';

-- 8. Regular password rotation
ALTER USER 'appuser'@'%' IDENTIFIED BY 'NewPassword123!';

-- 9. Monitor failed login attempts
SELECT * FROM mysql.general_log WHERE command_type = 'Connect' AND argument LIKE '%Access denied%';

-- 10. Regular security audits
SELECT user, host, authentication_string, password_expired, account_locked
FROM mysql.user;
```

**⚠️ WARNING:** This is a development environment. Production requires additional hardening:
- Network firewalls
- TLS encryption for all connections
- Regular security patches
- Audit logging
- Backup encryption
- Principle of least privilege

## Related Documentation

- [Service Configuration](Service-Configuration) - MySQL service configuration details
- [PostgreSQL Operations](PostgreSQL-Operations) - Similar operations for PostgreSQL
- [Backup and Restore](Backup-and-Restore) - Complete backup strategies
- [Container Management](Container-Management) - Docker container operations
- [Health Monitoring](Health-Monitoring) - MySQL health checks and monitoring
- [Performance Tuning](Performance-Tuning) - MySQL performance optimization
- [Network Architecture](Network-Architecture) - Network configuration and connectivity

---

**Quick Reference Card:**

```bash
# Connection
mysql -h localhost -P 3306 -u root -p

# Database Operations
CREATE DATABASE myapp;
SHOW DATABASES;
USE myapp;
DROP DATABASE myapp;

# User Management
CREATE USER 'user'@'%' IDENTIFIED BY 'pass';
GRANT ALL PRIVILEGES ON myapp.* TO 'user'@'%';
SHOW GRANTS FOR 'user'@'%';
DROP USER 'user'@'%';

# Table Operations
CREATE TABLE users (id INT PRIMARY KEY AUTO_INCREMENT);
SHOW TABLES;
DESCRIBE users;
DROP TABLE users;

# Backup/Restore
mysqldump -u root -p myapp > backup.sql
mysql -u root -p myapp < backup.sql

# Maintenance
ANALYZE TABLE users;
OPTIMIZE TABLE users;
CHECK TABLE users;
REPAIR TABLE users;

# Monitoring
SHOW PROCESSLIST;
SHOW STATUS;
SHOW ENGINE INNODB STATUS;
```
