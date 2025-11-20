# MongoDB Operations

Comprehensive guide to MongoDB database operations in the DevStack Core environment.

## Table of Contents

- [Overview](#overview)
- [Quick Reference](#quick-reference)
- [Connection Management](#connection-management)
  - [Connecting from Host](#connecting-from-host)
  - [Connecting from Containers](#connecting-from-containers)
  - [Connection Strings](#connection-strings)
  - [Connection Pooling](#connection-pooling)
  - [Connection Troubleshooting](#connection-troubleshooting)
- [User Management](#user-management)
  - [Creating Users](#creating-users)
  - [Granting Roles](#granting-roles)
  - [Revoking Roles](#revoking-roles)
  - [Viewing User Privileges](#viewing-user-privileges)
  - [Modifying Users](#modifying-users)
  - [Removing Users](#removing-users)
- [Database Management](#database-management)
  - [Creating Databases](#creating-databases)
  - [Listing Databases](#listing-databases)
  - [Switching Databases](#switching-databases)
  - [Dropping Databases](#dropping-databases)
  - [Database Statistics](#database-statistics)
- [Collection Operations](#collection-operations)
  - [Creating Collections](#creating-collections)
  - [Listing Collections](#listing-collections)
  - [Dropping Collections](#dropping-collections)
  - [Collection Statistics](#collection-statistics)
  - [Renaming Collections](#renaming-collections)
- [Query Optimization](#query-optimization)
  - [Using explain()](#using-explain)
  - [Query Planning](#query-planning)
  - [Index Usage Analysis](#index-usage-analysis)
  - [Profiler](#profiler)
  - [Query Patterns](#query-patterns)
- [Performance Monitoring](#performance-monitoring)
  - [Database Statistics](#database-statistics-1)
  - [Current Operations](#current-operations)
  - [Server Status](#server-status)
  - [Monitoring Collections](#monitoring-collections)
  - [Resource Usage](#resource-usage)
- [Index Management](#index-management)
  - [Index Types](#index-types)
  - [Creating Indexes](#creating-indexes)
  - [Index Maintenance](#index-maintenance)
  - [Index Optimization](#index-optimization)
  - [Index Statistics](#index-statistics)
- [Maintenance Operations](#maintenance-operations)
  - [Compact](#compact)
  - [Reindex](#reindex)
  - [Validation](#validation)
  - [Repair](#repair)
  - [Cleanup](#cleanup)
- [Backup Operations](#backup-operations)
  - [mongodump](#mongodump)
  - [mongorestore](#mongorestore)
  - [Filesystem Snapshots](#filesystem-snapshots)
  - [Backup Verification](#backup-verification)
- [Aggregation Pipelines](#aggregation-pipelines)
  - [Pipeline Stages](#pipeline-stages)
  - [Common Patterns](#common-patterns)
  - [Optimization](#optimization)
  - [Examples](#examples)
- [Troubleshooting](#troubleshooting)
  - [Connection Issues](#connection-issues)
  - [Slow Queries](#slow-queries)
  - [Disk Space Issues](#disk-space-issues)
  - [Replication Lag](#replication-lag)
  - [Authentication Issues](#authentication-issues)
- [Security Best Practices](#security-best-practices)
- [Related Documentation](#related-documentation)

## Overview

MongoDB is configured in the DevStack Core environment with:

- **Version**: MongoDB 7.0
- **Host Port**: 27017
- **Container IP**: 172.20.0.15
- **Container Name**: mongodb
- **Data Volume**: mongodb-data
- **Configuration**: `/configs/mongodb/mongod.conf`
- **Credentials**: Managed by Vault (`secret/mongodb`)

**⚠️ WARNING:** This is a development environment. Production deployments require replica sets, sharding, authentication, and backup strategies.

## Quick Reference

```bash
# Connect to MongoDB
mongosh "mongodb://localhost:27017" -u admin -p

# Connect from container
docker exec -it mongodb mongosh -u admin -p

# Show databases
mongosh -u admin -p --eval "show dbs"

# Create database (automatically created on first insert)
mongosh -u admin -p --eval "use myapp"

# Import JSON data
docker exec -i mongodb mongoimport --db=myapp --collection=users --file=/data/users.json

# Export database
docker exec mongodb mongodump --db=myapp --out=/backup

# Check MongoDB status
docker exec mongodb mongosh --eval "db.serverStatus()"

# View current operations
docker exec mongodb mongosh --eval "db.currentOp()"

# Check collection size
docker exec mongodb mongosh myapp --eval "db.users.stats().size"
```

## Connection Management

### Connecting from Host

Connect to MongoDB from your host machine:

```bash
# Get MongoDB credentials from Vault
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
MONGO_PASSWORD=$(vault kv get -field=password secret/mongodb)

# Connect using mongosh
mongosh "mongodb://admin:${MONGO_PASSWORD}@localhost:27017"

# Connect without storing password in history
mongosh "mongodb://localhost:27017" -u admin -p
# Enter password when prompted

# Connect to specific database
mongosh "mongodb://admin:${MONGO_PASSWORD}@localhost:27017/myapp"

# Execute single command
mongosh "mongodb://localhost:27017" -u admin -p --eval "show dbs"

# Execute JavaScript file
mongosh "mongodb://localhost:27017" -u admin -p script.js
```

### Connecting from Containers

Connect from other containers in the dev-services network:

```bash
# From another container using container name
mongosh "mongodb://admin:password@mongodb:27017"

# From another container using IP
mongosh "mongodb://admin:password@172.20.0.15:27017"

# Example: Connect from reference API
docker exec -it dev-reference-api mongosh "mongodb://mongodb:27017" -u admin -p

# Test connectivity
docker exec -it dev-reference-api ping mongodb
docker exec -it dev-reference-api nc -zv mongodb 27017
```

### Connection Strings

MongoDB connection string format:

```
mongodb://[username:password@]host[:port][/database][?options]
```

**Examples:**

```javascript
// Basic connection
mongodb://localhost:27017

// With authentication
mongodb://admin:password@localhost:27017

// Specific database
mongodb://admin:password@localhost:27017/myapp

// With options
mongodb://admin:password@localhost:27017/myapp?authSource=admin&retryWrites=true

// Replica set (not used in dev)
mongodb://admin:password@mongo1:27017,mongo2:27017,mongo3:27017/myapp?replicaSet=rs0

// With all options
mongodb://admin:password@localhost:27017/myapp?authSource=admin&retryWrites=true&w=majority&maxPoolSize=50
```

### Connection Pooling

Configure connection pooling in applications:

**Python (PyMongo):**

```python
from pymongo import MongoClient
from urllib.parse import quote_plus

# Create client with connection pooling
password = quote_plus("your_password")
client = MongoClient(
    f"mongodb://admin:{password}@mongodb:27017",
    maxPoolSize=50,           # Maximum connections in pool
    minPoolSize=10,           # Minimum connections in pool
    maxIdleTimeMS=60000,      # Max idle time before connection closed
    waitQueueTimeoutMS=5000,  # Timeout for getting connection from pool
    serverSelectionTimeoutMS=5000,
    connectTimeoutMS=10000,
    socketTimeoutMS=30000,
    retryWrites=True,
    w='majority'
)

# Test connection
db = client.admin
result = db.command("ping")
print(f"Connected: {result}")

# Get database
myapp_db = client.myapp
```

**Node.js (MongoDB Driver):**

```javascript
const { MongoClient } = require('mongodb');

// Connection URI with options
const uri = "mongodb://admin:password@mongodb:27017/myapp?authSource=admin";

// Create client with pool settings
const client = new MongoClient(uri, {
  maxPoolSize: 50,
  minPoolSize: 10,
  maxIdleTimeMS: 60000,
  waitQueueTimeoutMS: 5000,
  serverSelectionTimeoutMS: 5000,
  socketTimeoutMS: 30000,
  retryWrites: true,
  w: 'majority'
});

async function run() {
  try {
    await client.connect();
    await client.db("admin").command({ ping: 1 });
    console.log("Connected to MongoDB");

    const db = client.db("myapp");
    const users = db.collection("users");
  } catch (err) {
    console.error(err);
  }
}

run();
```

**Go (mongo-go-driver):**

```go
package main

import (
    "context"
    "time"
    "go.mongodb.org/mongo-driver/mongo"
    "go.mongodb.org/mongo-driver/mongo/options"
)

func createClient(password string) (*mongo.Client, error) {
    uri := fmt.Sprintf("mongodb://admin:%s@mongodb:27017", password)

    // Configure client options
    clientOpts := options.Client().
        ApplyURI(uri).
        SetMaxPoolSize(50).
        SetMinPoolSize(10).
        SetMaxConnIdleTime(60 * time.Second).
        SetServerSelectionTimeout(5 * time.Second).
        SetConnectTimeout(10 * time.Second).
        SetSocketTimeout(30 * time.Second).
        SetRetryWrites(true)

    // Connect to MongoDB
    ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
    defer cancel()

    client, err := mongo.Connect(ctx, clientOpts)
    if err != nil {
        return nil, err
    }

    // Ping to verify connection
    if err := client.Ping(ctx, nil); err != nil {
        return nil, err
    }

    return client, nil
}
```

### Connection Troubleshooting

**Issue: Connection Refused**

```bash
# Check if MongoDB is running
docker ps | grep mongodb

# Check MongoDB logs
docker logs mongodb --tail 50

# Check if port is accessible
nc -zv localhost 27017
telnet localhost 27017

# Check from within container network
docker exec -it dev-reference-api nc -zv mongodb 27017

# Verify MongoDB is listening
docker exec mongodb netstat -tlnp | grep 27017
```

**Issue: Authentication Failed**

```bash
# Verify credentials in Vault
vault kv get secret/mongodb

# Check user exists
docker exec mongodb mongosh -u admin -p --eval "use admin; db.getUsers()"

# Test authentication
docker exec mongodb mongosh -u admin -p --eval "db.adminCommand({connectionStatus: 1})"

# Check authentication database
mongosh "mongodb://admin:password@localhost:27017/?authSource=admin"
```

**Issue: Too Many Connections**

```bash
# Check current connections
docker exec mongodb mongosh --eval "db.serverStatus().connections"

# View active connections
docker exec mongodb mongosh --eval "db.currentOp({active: true})"

# Check max connections
docker exec mongodb mongosh --eval "db.serverStatus().connections.available"

# Kill specific operation
docker exec mongodb mongosh --eval "db.killOp(<opid>)"
```

## User Management

### Creating Users

```javascript
// Connect as admin
use admin

// Create user with password
db.createUser({
  user: "appuser",
  pwd: "SecurePass123!",
  roles: []
})

// Create user with roles
db.createUser({
  user: "appuser",
  pwd: "SecurePass123!",
  roles: [
    { role: "readWrite", db: "myapp" },
    { role: "read", db: "analytics" }
  ]
})

// Create admin user
db.createUser({
  user: "dbadmin",
  pwd: "AdminPass123!",
  roles: [
    { role: "userAdminAnyDatabase", db: "admin" },
    { role: "dbAdminAnyDatabase", db: "admin" },
    { role: "readWriteAnyDatabase", db: "admin" }
  ]
})

// Create user with custom role
db.createUser({
  user: "developer",
  pwd: "DevPass123!",
  roles: [
    { role: "readWrite", db: "myapp" },
    { role: "dbAdmin", db: "myapp" }
  ]
})
```

Execute from command line:

```bash
docker exec mongodb mongosh -u admin -p << 'EOF'
use admin
db.createUser({
  user: "appuser",
  pwd: "SecurePass123!",
  roles: [{ role: "readWrite", db: "myapp" }]
})
EOF
```

### Granting Roles

```javascript
// Grant single role
db.grantRolesToUser("appuser", [
  { role: "readWrite", db: "myapp" }
])

// Grant multiple roles
db.grantRolesToUser("appuser", [
  { role: "readWrite", db: "myapp" },
  { role: "read", db: "analytics" }
])

// Create custom role
use myapp
db.createRole({
  role: "appRole",
  privileges: [
    {
      resource: { db: "myapp", collection: "" },
      actions: ["find", "insert", "update", "remove"]
    }
  ],
  roles: []
})

// Grant custom role
db.grantRolesToUser("appuser", ["appRole"])
```

Common role combinations:

```bash
# Read-only user
docker exec mongodb mongosh -u admin -p << 'EOF'
use admin
db.createUser({
  user: "readonly",
  pwd: "ReadPass123!",
  roles: [{ role: "read", db: "myapp" }]
})
EOF

# Application user (CRUD operations)
docker exec mongodb mongosh -u admin -p << 'EOF'
use admin
db.createUser({
  user: "appuser",
  pwd: "AppPass123!",
  roles: [{ role: "readWrite", db: "myapp" }]
})
EOF

# Developer user (admin + CRUD)
docker exec mongodb mongosh -u admin -p << 'EOF'
use admin
db.createUser({
  user: "developer",
  pwd: "DevPass123!",
  roles: [
    { role: "readWrite", db: "myapp" },
    { role: "dbAdmin", db: "myapp" }
  ]
})
EOF
```

### Revoking Roles

```javascript
// Revoke specific role
db.revokeRolesFromUser("appuser", [
  { role: "readWrite", db: "myapp" }
])

// Revoke all roles
db.revokeRolesFromUser("appuser", db.getUser("appuser").roles)
```

### Viewing User Privileges

```javascript
// Show all users
use admin
db.getUsers()

// Show specific user
db.getUser("appuser")

// Show user roles
db.getUser("appuser").roles

// Show current user
db.runCommand({connectionStatus: 1})

// List all roles
db.getRoles()

// Show role privileges
db.getRole("readWrite", { showPrivileges: true })
```

### Modifying Users

```javascript
// Change password
db.changeUserPassword("appuser", "NewSecurePass123!")

// Update user (replace all settings)
db.updateUser("appuser", {
  pwd: "NewPass123!",
  roles: [
    { role: "readWrite", db: "myapp" },
    { role: "read", db: "analytics" }
  ]
})

// Add roles (without removing existing)
db.grantRolesToUser("appuser", [
  { role: "dbAdmin", db: "myapp" }
])
```

### Removing Users

```javascript
// Drop user
db.dropUser("appuser")

// Drop all users in database
db.dropAllUsers()
```

**⚠️ WARNING:** Dropping a user removes their authentication but doesn't affect their data.

## Database Management

### Creating Databases

```javascript
// Switch to database (creates if doesn't exist)
use myapp

// Database is created when first document is inserted
db.users.insertOne({ name: "John Doe" })

// Verify database exists
show dbs
```

**Note:** MongoDB creates databases lazily on first write operation.

### Listing Databases

```javascript
// Show all databases
show dbs

// Get database names
db.adminCommand({ listDatabases: 1 })

// Get detailed database info
db.adminCommand({ listDatabases: 1, nameOnly: false })

// Get current database
db.getName()
```

From command line:

```bash
# List databases
docker exec mongodb mongosh -u admin -p --eval "show dbs"

# Get database sizes
docker exec mongodb mongosh -u admin -p --eval "
db.adminCommand({ listDatabases: 1 }).databases.forEach(function(db) {
  print(db.name + ': ' + (db.sizeOnDisk / 1024 / 1024).toFixed(2) + ' MB');
})"
```

### Switching Databases

```javascript
// Switch to database
use myapp

// Verify current database
db.getName()
```

### Dropping Databases

```javascript
// Drop current database
use myapp
db.dropDatabase()

// Verify deletion
show dbs
```

**⚠️ WARNING:** Dropping a database permanently deletes all collections and data. Always backup first!

```bash
# Safe database drop procedure
# 1. Backup database first
docker exec mongodb mongodump --db=myapp --out=/backup/myapp_$(date +%Y%m%d_%H%M%S)

# 2. Verify backup
docker exec mongodb ls -lh /backup/

# 3. Drop database
docker exec mongodb mongosh -u admin -p --eval "use myapp; db.dropDatabase()"

# 4. Verify removal
docker exec mongodb mongosh -u admin -p --eval "show dbs"
```

### Database Statistics

```javascript
// Get database stats
db.stats()

// Get detailed stats
db.stats({ scale: 1024 * 1024 })  // Show sizes in MB

// Get all database stats
db.adminCommand({ listDatabases: 1 }).databases.forEach(function(database) {
  print("Database: " + database.name);
  var stats = db.getSiblingDB(database.name).stats(1024 * 1024);
  print("  Collections: " + stats.collections);
  print("  Data Size: " + stats.dataSize.toFixed(2) + " MB");
  print("  Storage Size: " + stats.storageSize.toFixed(2) + " MB");
  print("  Indexes: " + stats.indexes);
  print("  Index Size: " + stats.indexSize.toFixed(2) + " MB");
})
```

## Collection Operations

### Creating Collections

```javascript
// Implicit creation (on first insert)
db.users.insertOne({ name: "John Doe" })

// Explicit creation
db.createCollection("users")

// Create collection with options
db.createCollection("logs", {
  capped: true,           // Fixed-size collection
  size: 100000000,        // Max size in bytes (100MB)
  max: 5000               // Max documents
})

// Create collection with validation
db.createCollection("users", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["name", "email"],
      properties: {
        name: {
          bsonType: "string",
          description: "must be a string and is required"
        },
        email: {
          bsonType: "string",
          pattern: "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$",
          description: "must be a valid email address"
        },
        age: {
          bsonType: "int",
          minimum: 0,
          maximum: 150
        }
      }
    }
  }
})

// Create time series collection (MongoDB 5.0+)
db.createCollection("metrics", {
  timeseries: {
    timeField: "timestamp",
    metaField: "sensor_id",
    granularity: "seconds"
  }
})
```

### Listing Collections

```javascript
// Show all collections
show collections

// Get collection names
db.getCollectionNames()

// Get collection info
db.getCollectionInfos()

// Count collections
db.getCollectionNames().length
```

### Dropping Collections

```javascript
// Drop collection
db.users.drop()

// Verify deletion
show collections
```

### Collection Statistics

```javascript
// Get collection stats
db.users.stats()

// Get stats in MB
db.users.stats(1024 * 1024)

// Get detailed stats
db.users.stats({ indexDetails: true })

// Get count
db.users.countDocuments()
db.users.estimatedDocumentCount()  // Faster but less accurate

// Get storage size
db.users.totalSize()
db.users.storageSize()
db.users.totalIndexSize()

// Get all collection stats
db.getCollectionNames().forEach(function(collection) {
  var stats = db.getCollection(collection).stats(1024 * 1024);
  print("Collection: " + collection);
  print("  Count: " + stats.count);
  print("  Size: " + stats.size.toFixed(2) + " MB");
  print("  Storage: " + stats.storageSize.toFixed(2) + " MB");
  print("  Indexes: " + stats.nindexes);
  print("  Index Size: " + stats.totalIndexSize.toFixed(2) + " MB");
})
```

### Renaming Collections

```javascript
// Rename collection
db.users.renameCollection("app_users")

// Rename and drop target if exists
db.users.renameCollection("app_users", true)
```

## Query Optimization

### Using explain()

```javascript
// Basic explain
db.users.find({ email: "user@example.com" }).explain()

// Execution stats
db.users.find({ email: "user@example.com" }).explain("executionStats")

// All plans
db.users.find({ email: "user@example.com" }).explain("allPlansExecution")

// Explain for aggregation
db.users.aggregate([
  { $match: { status: "active" } },
  { $group: { _id: "$country", count: { $sum: 1 } } }
]).explain("executionStats")

// Analyze explain output
var explain = db.users.find({ email: "user@example.com" }).explain("executionStats")

// Check execution stats
print("Execution Time: " + explain.executionStats.executionTimeMillis + " ms")
print("Documents Examined: " + explain.executionStats.totalDocsExamined)
print("Documents Returned: " + explain.executionStats.nReturned)
print("Index Used: " + (explain.executionStats.executionStages.indexName || "COLLSCAN"))
```

Understanding explain output:

```javascript
// Key fields to examine:
// - stage: IXSCAN (index scan) is good, COLLSCAN (collection scan) is bad
// - executionTimeMillis: Query execution time
// - totalDocsExamined: Documents scanned (should be close to nReturned)
// - totalKeysExamined: Index entries scanned
// - nReturned: Documents returned
// - executionStats.indexName: Index used (undefined = collection scan)

// Example analysis:
var explain = db.users.find({ email: "user@example.com" }).explain("executionStats")
var stats = explain.executionStats

if (stats.totalDocsExamined > stats.nReturned * 10) {
  print("WARNING: Query is examining too many documents")
  print("Consider adding an index on: email")
}

if (stats.executionStages.stage === "COLLSCAN") {
  print("WARNING: Collection scan detected")
  print("Create index: db.users.createIndex({ email: 1 })")
}
```

### Query Planning

```javascript
// Force index usage
db.users.find({ email: "user@example.com" }).hint({ email: 1 })

// Hint natural order (no index)
db.users.find({}).hint({ $natural: 1 })

// Use projection to reduce data transfer
db.users.find(
  { status: "active" },
  { name: 1, email: 1, _id: 0 }  // Only return name and email
)

// Use limit to reduce results
db.users.find({ status: "active" }).limit(10)

// Optimize with sort + limit
db.users.find({ status: "active" }).sort({ created_at: -1 }).limit(10)

// Use covered queries (query + projection covered by index)
db.users.createIndex({ status: 1, name: 1 })
db.users.find(
  { status: "active" },
  { name: 1, _id: 0 }  // Both fields in index
)
```

### Index Usage Analysis

```javascript
// Get index stats
db.users.aggregate([
  { $indexStats: {} }
])

// Find unused indexes
db.users.aggregate([
  { $indexStats: {} },
  { $match: { "accesses.ops": { $eq: 0 } } }
])

// Index efficiency
db.users.aggregate([
  { $indexStats: {} },
  {
    $project: {
      name: 1,
      ops: "$accesses.ops",
      since: "$accesses.since"
    }
  },
  { $sort: { ops: -1 } }
])

// Check index selectivity
db.users.aggregate([
  {
    $group: {
      _id: null,
      total: { $sum: 1 },
      unique_emails: { $addToSet: "$email" }
    }
  },
  {
    $project: {
      total: 1,
      unique: { $size: "$unique_emails" },
      selectivity: {
        $divide: [{ $size: "$unique_emails" }, "$total"]
      }
    }
  }
])
// Selectivity close to 1.0 = highly selective (good for index)
```

### Profiler

Enable and use database profiler:

```javascript
// Enable profiler (level 2 = all operations)
db.setProfilingLevel(2)

// Enable profiler for slow queries only (> 100ms)
db.setProfilingLevel(1, { slowms: 100 })

// Check profiler status
db.getProfilingStatus()

// View profiler data
db.system.profile.find().limit(10).sort({ ts: -1 }).pretty()

// Find slow queries
db.system.profile.find({
  millis: { $gt: 100 }
}).sort({ millis: -1 }).limit(10)

// Analyze query patterns
db.system.profile.aggregate([
  { $group: {
      _id: "$op",
      count: { $sum: 1 },
      avgMs: { $avg: "$millis" },
      maxMs: { $max: "$millis" }
    }
  },
  { $sort: { count: -1 } }
])

// Disable profiler
db.setProfilingLevel(0)

// Clear profiler data
db.system.profile.drop()
```

### Query Patterns

```javascript
// Efficient queries

// 1. Use indexes for filtering
db.users.createIndex({ email: 1 })
db.users.find({ email: "user@example.com" })  // Uses index

// 2. Use compound indexes for multiple fields
db.users.createIndex({ status: 1, created_at: -1 })
db.users.find({ status: "active" }).sort({ created_at: -1 })  // Uses index

// 3. Use projection to limit fields
db.users.find(
  { status: "active" },
  { name: 1, email: 1 }  // Only fetch needed fields
)

// 4. Use limit for pagination
db.users.find({ status: "active" }).skip(0).limit(20)

// 5. Use $in for multiple values
db.users.find({ status: { $in: ["active", "pending"] } })

// 6. Avoid $where and JavaScript evaluation
// Bad:
db.users.find({ $where: "this.age > 18" })
// Good:
db.users.find({ age: { $gt: 18 } })

// 7. Use $exists sparingly
// Bad:
db.users.find({ email: { $exists: true } })  // Collection scan
// Good: Use compound index or different approach

// 8. Optimize text search
db.users.createIndex({ bio: "text" })
db.users.find({ $text: { $search: "developer" } })
```

## Performance Monitoring

### Database Statistics

```javascript
// Get server status
db.serverStatus()

// Get specific metrics
var status = db.serverStatus()
print("Uptime: " + status.uptime + " seconds")
print("Connections: " + status.connections.current + "/" + status.connections.available)
print("Network In: " + (status.network.bytesIn / 1024 / 1024).toFixed(2) + " MB")
print("Network Out: " + (status.network.bytesOut / 1024 / 1024).toFixed(2) + " MB")

// Get operation counters
var opcounters = db.serverStatus().opcounters
print("Inserts: " + opcounters.insert)
print("Queries: " + opcounters.query)
print("Updates: " + opcounters.update)
print("Deletes: " + opcounters.delete)

// Get database stats
db.stats(1024 * 1024)  // In MB
```

Monitor from command line:

```bash
# Watch server status
watch -n 1 'docker exec mongodb mongosh --quiet --eval "db.serverStatus().connections"'

# Monitor operations per second
docker exec mongodb mongostat --host=localhost

# Monitor top collections
docker exec mongodb mongotop --host=localhost

# Custom monitoring
docker exec mongodb mongosh --eval "
var prev = db.serverStatus().opcounters;
sleep(1000);
var curr = db.serverStatus().opcounters;
print('Ops/sec:');
print('  Insert: ' + (curr.insert - prev.insert));
print('  Query: ' + (curr.query - prev.query));
print('  Update: ' + (curr.update - prev.update));
print('  Delete: ' + (curr.delete - prev.delete));
"
```

### Current Operations

```javascript
// Show all current operations
db.currentOp()

// Show active operations
db.currentOp({ active: true })

// Show long-running operations (> 5 seconds)
db.currentOp({
  active: true,
  secs_running: { $gt: 5 }
})

// Show operations on specific database
db.currentOp({
  active: true,
  ns: /^myapp\./
})

// Get operation details
db.currentOp({ active: true }).inprog.forEach(function(op) {
  print("OpID: " + op.opid);
  print("  Op: " + op.op);
  print("  NS: " + op.ns);
  print("  Duration: " + op.secs_running + "s");
  print("  Query: " + JSON.stringify(op.query || op.command));
})

// Kill specific operation
db.killOp(<opid>)

// Kill all long-running queries
db.currentOp({ active: true, secs_running: { $gt: 10 } }).inprog.forEach(function(op) {
  db.killOp(op.opid);
})
```

### Server Status

```javascript
// Full server status
db.serverStatus()

// Memory usage
var mem = db.serverStatus().mem
print("Resident: " + mem.resident + " MB")
print("Virtual: " + mem.virtual + " MB")
print("Mapped: " + (mem.mapped || 0) + " MB")

// Connection stats
var conn = db.serverStatus().connections
print("Current: " + conn.current)
print("Available: " + conn.available)
print("Total Created: " + conn.totalCreated)

// Lock statistics
db.serverStatus().locks

// WiredTiger cache stats
var wt = db.serverStatus().wiredTiger.cache
print("Cache Size: " + (wt["bytes currently in the cache"] / 1024 / 1024).toFixed(2) + " MB")
print("Max Cache Size: " + (wt["maximum bytes configured"] / 1024 / 1024).toFixed(2) + " MB")
print("Dirty Bytes: " + (wt["tracked dirty bytes in the cache"] / 1024 / 1024).toFixed(2) + " MB")
```

### Monitoring Collections

```javascript
// Monitor collection growth
db.users.stats(1024 * 1024)

// Track index usage
db.users.aggregate([
  { $indexStats: {} }
]).forEach(function(index) {
  print("Index: " + index.name);
  print("  Operations: " + index.accesses.ops);
  print("  Since: " + index.accesses.since);
})

// Monitor query performance
db.setProfilingLevel(1, { slowms: 100 })
sleep(60000)  // Monitor for 1 minute
db.system.profile.aggregate([
  {
    $group: {
      _id: "$ns",
      count: { $sum: 1 },
      avgMs: { $avg: "$millis" },
      maxMs: { $max: "$millis" }
    }
  },
  { $sort: { avgMs: -1 } }
])
```

### Resource Usage

Monitor from Docker:

```bash
# Container resource usage
docker stats mongodb --no-stream

# Detailed container stats
docker exec mongodb ps aux

# Memory usage
docker exec mongodb free -h

# Disk usage
docker exec mongodb df -h

# MongoDB data directory size
docker exec mongodb du -sh /data/db

# Database sizes
docker exec mongodb mongosh --eval "
db.adminCommand({ listDatabases: 1 }).databases.forEach(function(db) {
  print(db.name + ': ' + (db.sizeOnDisk / 1024 / 1024).toFixed(2) + ' MB');
})"
```

## Index Management

### Index Types

MongoDB supports several index types:

1. **Single Field Index**: Index on single field
2. **Compound Index**: Index on multiple fields
3. **Multikey Index**: Index on array fields
4. **Text Index**: For text search
5. **Geospatial Index**: For geographic queries
6. **Hashed Index**: For hash-based sharding
7. **Wildcard Index**: For flexible schema (MongoDB 4.2+)

### Creating Indexes

```javascript
// Single field index (ascending)
db.users.createIndex({ email: 1 })

// Single field index (descending)
db.users.createIndex({ created_at: -1 })

// Compound index
db.users.createIndex({ status: 1, created_at: -1 })

// Unique index
db.users.createIndex({ email: 1 }, { unique: true })

// Sparse index (only documents with field)
db.users.createIndex({ phone: 1 }, { sparse: true })

// Partial index (filtered)
db.users.createIndex(
  { email: 1 },
  { partialFilterExpression: { status: "active" } }
)

// TTL index (auto-delete documents)
db.sessions.createIndex(
  { created_at: 1 },
  { expireAfterSeconds: 3600 }  // Delete after 1 hour
)

// Text index
db.posts.createIndex({ title: "text", content: "text" })

// Text index with weights
db.posts.createIndex(
  { title: "text", content: "text" },
  { weights: { title: 10, content: 1 } }
)

// Geospatial index (2dsphere)
db.places.createIndex({ location: "2dsphere" })

// Hashed index
db.users.createIndex({ _id: "hashed" })

// Wildcard index
db.products.createIndex({ "$**": 1 })

// Background index (non-blocking)
db.users.createIndex({ email: 1 }, { background: true })

// Case-insensitive index
db.users.createIndex(
  { email: 1 },
  { collation: { locale: "en", strength: 2 } }
)
```

Create indexes from command line:

```bash
# Create index
docker exec mongodb mongosh myapp --eval "db.users.createIndex({ email: 1 })"

# Create multiple indexes
docker exec mongodb mongosh myapp << 'EOF'
db.users.createIndex({ email: 1 });
db.users.createIndex({ status: 1, created_at: -1 });
db.users.createIndex({ username: 1 }, { unique: true });
EOF
```

### Index Maintenance

```javascript
// List all indexes on collection
db.users.getIndexes()

// Rebuild specific index
db.users.reIndex()  // Rebuilds all indexes

// Drop index by name
db.users.dropIndex("email_1")

// Drop index by specification
db.users.dropIndex({ email: 1 })

// Drop all indexes except _id
db.users.dropIndexes()

// Drop specific indexes
db.users.dropIndexes(["email_1", "status_1_created_at_-1"])

// Hide index (disable without dropping)
db.users.hideIndex("email_1")

// Unhide index
db.users.unhideIndex("email_1")

// Check if index is hidden
db.users.getIndexes().forEach(function(idx) {
  print(idx.name + ": " + (idx.hidden ? "hidden" : "visible"));
})
```

Maintenance from command line:

```bash
# Rebuild all indexes in database
docker exec mongodb mongosh myapp --eval "
db.getCollectionNames().forEach(function(col) {
  print('Reindexing: ' + col);
  db.getCollection(col).reIndex();
})"

# List all indexes in database
docker exec mongodb mongosh myapp --eval "
db.getCollectionNames().forEach(function(col) {
  print('Collection: ' + col);
  db.getCollection(col).getIndexes().forEach(function(idx) {
    print('  ' + idx.name);
  });
})"
```

### Index Optimization

```javascript
// Find unused indexes
db.users.aggregate([
  { $indexStats: {} },
  { $match: { "accesses.ops": { $eq: 0 } } },
  { $project: { name: 1 } }
])

// Find duplicate indexes
var indexes = db.users.getIndexes();
var keys = {};
indexes.forEach(function(idx) {
  var key = JSON.stringify(idx.key);
  if (keys[key]) {
    print("Duplicate index: " + idx.name + " matches " + keys[key]);
  } else {
    keys[key] = idx.name;
  }
})

// Check index size vs collection size
var stats = db.users.stats(1024 * 1024);
print("Data Size: " + stats.size.toFixed(2) + " MB");
print("Index Size: " + stats.totalIndexSize.toFixed(2) + " MB");
print("Index/Data Ratio: " + (stats.totalIndexSize / stats.size * 100).toFixed(2) + "%");

// Analyze index efficiency
db.users.find({ email: "user@example.com" }).explain("executionStats").executionStats
// Compare totalDocsExamined vs nReturned
// Ideal ratio: 1:1 (one document examined per document returned)
```

### Index Statistics

```javascript
// Index stats for collection
db.users.aggregate([
  { $indexStats: {} }
]).forEach(function(idx) {
  print("Index: " + idx.name);
  print("  Operations: " + idx.accesses.ops);
  print("  Since: " + idx.accesses.since);
})

// Index size per collection
db.getCollectionNames().forEach(function(col) {
  var stats = db.getCollection(col).stats(1024 * 1024);
  print("Collection: " + col);
  print("  Index Size: " + stats.totalIndexSize.toFixed(2) + " MB");
  print("  Indexes: " + stats.nindexes);
})

// Detailed index stats
db.users.stats().indexSizes
```

## Maintenance Operations

### Compact

Reclaim disk space and defragment data:

```javascript
// Compact collection
db.runCommand({ compact: "users" })

// Compact with options
db.runCommand({
  compact: "users",
  force: true  // Force compact even if collection is in use
})

// Compact all collections
db.getCollectionNames().forEach(function(col) {
  print("Compacting: " + col);
  db.runCommand({ compact: col });
})
```

**⚠️ WARNING:** Compact operation blocks writes to the collection. Use during maintenance windows.

From command line:

```bash
# Compact specific collection
docker exec mongodb mongosh myapp --eval "db.runCommand({ compact: 'users' })"

# Compact all collections
docker exec mongodb mongosh myapp --eval "
db.getCollectionNames().forEach(function(col) {
  print('Compacting: ' + col);
  db.runCommand({ compact: col });
})"
```

### Reindex

Rebuild all indexes on a collection:

```javascript
// Reindex collection
db.users.reIndex()

// Reindex all collections
db.getCollectionNames().forEach(function(col) {
  print("Reindexing: " + col);
  db.getCollection(col).reIndex();
})
```

**⚠️ WARNING:** Reindex operation blocks all operations on the collection.

### Validation

Validate collection data and indexes:

```javascript
// Basic validation
db.users.validate()

// Full validation (slower but thorough)
db.users.validate({ full: true })

// Validate all collections
db.getCollectionNames().forEach(function(col) {
  print("Validating: " + col);
  var result = db.getCollection(col).validate();
  if (!result.valid) {
    print("  ERROR: Collection is invalid!");
    print("  " + JSON.stringify(result.errors));
  } else {
    print("  OK");
  }
})
```

### Repair

Repair database (requires MongoDB restart):

```bash
# Stop MongoDB
docker compose stop mongodb

# Start MongoDB in repair mode
docker run --rm -v mongodb-data:/data/db mongo:7.0 mongod --repair

# Start MongoDB normally
docker compose start mongodb

# Verify
docker exec mongodb mongosh --eval "db.serverStatus()"
```

### Cleanup

```javascript
// Remove orphaned documents (if using sharding)
db.runCommand({ cleanupOrphaned: "myapp.users" })

// Clear profiler data
db.system.profile.drop()

// Drop empty collections
db.getCollectionNames().forEach(function(col) {
  if (db.getCollection(col).countDocuments() === 0) {
    print("Dropping empty collection: " + col);
    db.getCollection(col).drop();
  }
})
```

## Backup Operations

### mongodump

```bash
# Backup entire database
docker exec mongodb mongodump --db=myapp --out=/backup/myapp_$(date +%Y%m%d_%H%M%S)

# Backup specific collection
docker exec mongodb mongodump --db=myapp --collection=users --out=/backup/users_backup

# Backup with authentication
docker exec mongodb mongodump \
  --username=admin \
  --password="${MONGO_PASSWORD}" \
  --authenticationDatabase=admin \
  --db=myapp \
  --out=/backup/myapp_backup

# Backup all databases
docker exec mongodb mongodump --out=/backup/all_databases_$(date +%Y%m%d_%H%M%S)

# Backup with compression
docker exec mongodb mongodump --db=myapp --gzip --out=/backup/myapp_compressed

# Backup with query filter
docker exec mongodb mongodump \
  --db=myapp \
  --collection=users \
  --query='{"status":"active"}' \
  --out=/backup/active_users

# Backup excluding collections
docker exec mongodb mongodump \
  --db=myapp \
  --excludeCollection=logs \
  --excludeCollection=temp \
  --out=/backup/myapp_backup
```

Copy backup from container:

```bash
# Backup and copy to host
docker exec mongodb mongodump --db=myapp --out=/tmp/backup
docker cp mongodb:/tmp/backup ./backups/mongodb/myapp_$(date +%Y%m%d_%H%M%S)
docker exec mongodb rm -rf /tmp/backup
```

### mongorestore

```bash
# Restore entire database
docker exec mongodb mongorestore --db=myapp /backup/myapp_20240115_120000/myapp

# Restore specific collection
docker exec mongodb mongorestore \
  --db=myapp \
  --collection=users \
  /backup/myapp_backup/myapp/users.bson

# Restore with authentication
docker exec mongodb mongorestore \
  --username=admin \
  --password="${MONGO_PASSWORD}" \
  --authenticationDatabase=admin \
  --db=myapp \
  /backup/myapp_backup/myapp

# Restore all databases
docker exec mongodb mongorestore /backup/all_databases_20240115_120000

# Restore compressed backup
docker exec mongodb mongorestore --gzip /backup/myapp_compressed

# Restore and drop existing collections first
docker exec mongodb mongorestore --drop --db=myapp /backup/myapp_backup/myapp

# Restore to different database
docker exec mongodb mongorestore --nsFrom='myapp.*' --nsTo='myapp_restored.*' /backup/myapp_backup

# Restore from host
docker cp ./backups/mongodb/myapp_backup mongodb:/tmp/restore
docker exec mongodb mongorestore --db=myapp /tmp/restore/myapp
docker exec mongodb rm -rf /tmp/restore
```

### Filesystem Snapshots

Binary backup of MongoDB data directory:

```bash
# Stop MongoDB
docker compose stop mongodb

# Backup data volume
docker run --rm \
  -v mongodb-data:/data \
  -v $(pwd)/backups/mongodb:/backup \
  alpine tar czf /backup/mongodb-data-$(date +%Y%m%d_%H%M%S).tar.gz -C /data .

# Start MongoDB
docker compose start mongodb

# Verify backup
ls -lh backups/mongodb/mongodb-data-*.tar.gz
```

Restore filesystem backup:

```bash
# Stop MongoDB
docker compose stop mongodb

# Restore data volume
docker run --rm \
  -v mongodb-data:/data \
  -v $(pwd)/backups/mongodb:/backup \
  alpine sh -c "rm -rf /data/* && tar xzf /backup/mongodb-data-20240115_120000.tar.gz -C /data"

# Start MongoDB
docker compose start mongodb

# Verify
docker exec mongodb mongosh --eval "show dbs"
```

### Backup Verification

```bash
# Verify backup integrity
ls -lh /path/to/backup/

# Check backup size
docker exec mongodb du -sh /backup/myapp_backup

# Test restore to temporary database
docker exec mongodb mongorestore --db=myapp_test /backup/myapp_backup/myapp
docker exec mongodb mongosh --eval "use myapp_test; db.getCollectionNames()"
docker exec mongodb mongosh --eval "use myapp_test; db.dropDatabase()"

# Compare document counts
docker exec mongodb mongosh --eval "
use myapp;
db.getCollectionNames().forEach(function(col) {
  print(col + ': ' + db.getCollection(col).countDocuments());
})"
```

Complete backup script:

```bash
#!/bin/bash
# MongoDB backup script

BACKUP_DIR="/Users/gator/devstack-core/backups/mongodb"
DATE=$(date +%Y%m%d_%H%M%S)
MONGO_PASS=$(vault kv get -field=password secret/mongodb)

mkdir -p "${BACKUP_DIR}"

# Backup all databases
echo "Starting MongoDB backup..."
docker exec mongodb mongodump \
  --username=admin \
  --password="${MONGO_PASS}" \
  --authenticationDatabase=admin \
  --gzip \
  --out=/tmp/backup_${DATE}

# Copy from container
docker cp mongodb:/tmp/backup_${DATE} "${BACKUP_DIR}/backup_${DATE}"
docker exec mongodb rm -rf /tmp/backup_${DATE}

# Verify backup
if [ -d "${BACKUP_DIR}/backup_${DATE}" ]; then
  SIZE=$(du -sh "${BACKUP_DIR}/backup_${DATE}" | cut -f1)
  echo "Backup completed: ${BACKUP_DIR}/backup_${DATE} (${SIZE})"
else
  echo "Backup failed!"
  exit 1
fi

# Cleanup old backups (keep last 7 days)
find "${BACKUP_DIR}" -name "backup_*" -mtime +7 -exec rm -rf {} \;

echo "Backup retention: Removed backups older than 7 days"
```

## Aggregation Pipelines

### Pipeline Stages

Common aggregation stages:

```javascript
// $match - Filter documents
db.users.aggregate([
  { $match: { status: "active" } }
])

// $project - Select fields
db.users.aggregate([
  { $project: { name: 1, email: 1, _id: 0 } }
])

// $group - Group and aggregate
db.orders.aggregate([
  { $group: {
      _id: "$user_id",
      total_orders: { $sum: 1 },
      total_amount: { $sum: "$amount" }
    }
  }
])

// $sort - Sort results
db.users.aggregate([
  { $match: { status: "active" } },
  { $sort: { created_at: -1 } }
])

// $limit - Limit results
db.users.aggregate([
  { $limit: 10 }
])

// $skip - Skip documents
db.users.aggregate([
  { $skip: 20 },
  { $limit: 10 }
])

// $unwind - Deconstruct arrays
db.posts.aggregate([
  { $unwind: "$tags" }
])

// $lookup - Join collections
db.orders.aggregate([
  {
    $lookup: {
      from: "users",
      localField: "user_id",
      foreignField: "_id",
      as: "user"
    }
  }
])

// $addFields - Add computed fields
db.users.aggregate([
  {
    $addFields: {
      full_name: { $concat: ["$first_name", " ", "$last_name"] }
    }
  }
])

// $out - Write results to collection
db.users.aggregate([
  { $match: { status: "active" } },
  { $out: "active_users" }
])
```

### Common Patterns

```javascript
// Count by field
db.users.aggregate([
  { $group: {
      _id: "$country",
      count: { $sum: 1 }
    }
  },
  { $sort: { count: -1 } }
])

// Average, min, max
db.orders.aggregate([
  { $group: {
      _id: null,
      avg_amount: { $avg: "$amount" },
      min_amount: { $min: "$amount" },
      max_amount: { $max: "$amount" }
    }
  }
])

// Group by date (daily counts)
db.logs.aggregate([
  {
    $group: {
      _id: {
        $dateToString: { format: "%Y-%m-%d", date: "$created_at" }
      },
      count: { $sum: 1 }
    }
  },
  { $sort: { _id: -1 } }
])

// Top N with details
db.users.aggregate([
  { $match: { status: "active" } },
  { $sort: { score: -1 } },
  { $limit: 10 },
  { $project: { name: 1, email: 1, score: 1 } }
])

// Complex join with filtering
db.orders.aggregate([
  { $match: { status: "completed" } },
  {
    $lookup: {
      from: "users",
      localField: "user_id",
      foreignField: "_id",
      as: "user"
    }
  },
  { $unwind: "$user" },
  {
    $project: {
      order_id: "$_id",
      amount: 1,
      user_name: "$user.name",
      user_email: "$user.email"
    }
  }
])

// Bucket/histogram
db.users.aggregate([
  {
    $bucket: {
      groupBy: "$age",
      boundaries: [0, 18, 25, 35, 50, 100],
      default: "Other",
      output: {
        count: { $sum: 1 },
        users: { $push: "$name" }
      }
    }
  }
])
```

### Optimization

```javascript
// 1. Use $match early to reduce data
// Bad:
db.users.aggregate([
  { $sort: { created_at: -1 } },
  { $match: { status: "active" } }
])
// Good:
db.users.aggregate([
  { $match: { status: "active" } },
  { $sort: { created_at: -1 } }
])

// 2. Use indexes for $match and $sort
db.users.createIndex({ status: 1, created_at: -1 })
db.users.aggregate([
  { $match: { status: "active" } },
  { $sort: { created_at: -1 } }
])

// 3. Use $project to reduce field transfer
db.users.aggregate([
  { $match: { status: "active" } },
  { $project: { name: 1, email: 1 } },  // Reduce fields early
  { $sort: { name: 1 } }
])

// 4. Limit results early
db.users.aggregate([
  { $match: { status: "active" } },
  { $sort: { score: -1 } },
  { $limit: 10 }  // Limit before further processing
])

// 5. Use allowDiskUse for large datasets
db.users.aggregate(
  [
    { $match: { status: "active" } },
    { $sort: { created_at: -1 } }
  ],
  { allowDiskUse: true }  // Allow using disk if memory exceeded
)

// 6. Explain aggregation pipeline
db.users.aggregate([
  { $match: { status: "active" } },
  { $sort: { created_at: -1 } }
]).explain("executionStats")
```

### Examples

```javascript
// User analytics: Active users by country
db.users.aggregate([
  { $match: { status: "active" } },
  {
    $group: {
      _id: "$country",
      total_users: { $sum: 1 },
      avg_age: { $avg: "$age" }
    }
  },
  { $sort: { total_users: -1 } },
  { $limit: 10 }
])

// Sales report: Revenue by product category
db.orders.aggregate([
  { $match: { status: "completed" } },
  { $unwind: "$items" },
  {
    $lookup: {
      from: "products",
      localField: "items.product_id",
      foreignField: "_id",
      as: "product"
    }
  },
  { $unwind: "$product" },
  {
    $group: {
      _id: "$product.category",
      total_revenue: { $sum: { $multiply: ["$items.quantity", "$items.price"] } },
      total_orders: { $sum: 1 },
      avg_order_value: { $avg: { $multiply: ["$items.quantity", "$items.price"] } }
    }
  },
  { $sort: { total_revenue: -1 } }
])

// Time series: Daily active users
db.sessions.aggregate([
  {
    $match: {
      created_at: {
        $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)  // Last 30 days
      }
    }
  },
  {
    $group: {
      _id: {
        date: { $dateToString: { format: "%Y-%m-%d", date: "$created_at" } },
        user_id: "$user_id"
      }
    }
  },
  {
    $group: {
      _id: "$_id.date",
      unique_users: { $sum: 1 }
    }
  },
  { $sort: { _id: 1 } }
])

// Nested aggregation: User leaderboard with rank
db.users.aggregate([
  { $match: { status: "active" } },
  { $sort: { score: -1 } },
  {
    $group: {
      _id: null,
      users: {
        $push: {
          user_id: "$_id",
          name: "$name",
          score: "$score"
        }
      }
    }
  },
  { $unwind: { path: "$users", includeArrayIndex: "rank" } },
  {
    $project: {
      _id: 0,
      user_id: "$users.user_id",
      name: "$users.name",
      score: "$users.score",
      rank: { $add: ["$rank", 1] }  // Start rank at 1
    }
  },
  { $limit: 100 }
])
```

## Troubleshooting

### Connection Issues

**Symptom:** Cannot connect to MongoDB

```bash
# 1. Check if MongoDB is running
docker ps | grep mongodb

# 2. Check MongoDB logs
docker logs mongodb --tail 50

# 3. Test port accessibility
nc -zv localhost 27017
telnet localhost 27017

# 4. Check from container network
docker exec -it dev-reference-api nc -zv mongodb 27017

# 5. Verify MongoDB is listening
docker exec mongodb netstat -tlnp | grep 27017

# 6. Test authentication
docker exec mongodb mongosh --eval "db.adminCommand({connectionStatus: 1})"

# 7. Check bind IP
docker exec mongodb mongosh --eval "db.serverCmdLineOpts()" | grep bindIp

# 8. Verify credentials in Vault
vault kv get secret/mongodb
```

### Slow Queries

**Symptom:** Queries taking too long

```javascript
// 1. Enable profiler to find slow queries
db.setProfilingLevel(1, { slowms: 100 })

// 2. View slow queries
db.system.profile.find({ millis: { $gt: 100 } }).sort({ millis: -1 }).limit(10)

// 3. Analyze query with explain
db.users.find({ email: "user@example.com" }).explain("executionStats")

// 4. Check for collection scans
var explain = db.users.find({ email: "user@example.com" }).explain("executionStats")
if (explain.executionStats.executionStages.stage === "COLLSCAN") {
  print("Collection scan detected - needs index!");
}

// 5. Create appropriate index
db.users.createIndex({ email: 1 })

// 6. Check index usage
db.users.aggregate([
  { $indexStats: {} }
])

// 7. Analyze current operations
db.currentOp({ active: true, secs_running: { $gt: 5 } })

// 8. Kill slow operation
db.killOp(<opid>)
```

### Disk Space Issues

**Symptom:** Running out of disk space

```bash
# Check disk usage
docker exec mongodb df -h

# Check MongoDB data directory size
docker exec mongodb du -sh /data/db

# Check database sizes
docker exec mongodb mongosh --eval "
db.adminCommand({ listDatabases: 1 }).databases.forEach(function(db) {
  print(db.name + ': ' + (db.sizeOnDisk / 1024 / 1024).toFixed(2) + ' MB');
})"

# Check collection sizes
docker exec mongodb mongosh myapp --eval "
db.getCollectionNames().forEach(function(col) {
  var stats = db.getCollection(col).stats(1024 * 1024);
  print(col + ': ' + stats.size.toFixed(2) + ' MB');
})"

# Compact collections to reclaim space
docker exec mongodb mongosh myapp --eval "
db.getCollectionNames().forEach(function(col) {
  print('Compacting: ' + col);
  db.runCommand({ compact: col });
})"

# Drop unnecessary collections
docker exec mongodb mongosh myapp --eval "db.logs.drop()"

# Clear profiler data
docker exec mongodb mongosh --eval "db.system.profile.drop()"
```

### Replication Lag

**Symptom:** Replica set lag (if using replication)

```javascript
// Check replication status
rs.status()

// Check replication lag
rs.printReplicationInfo()
rs.printSlaveReplicationInfo()

// View oplog details
use local
db.oplog.rs.stats()

// Check sync source
db.serverStatus().repl.syncSourceHost

// Find operations causing lag
db.currentOp({ active: true, op: "repl" })
```

**Note:** Replication is not configured in default dev environment.

### Authentication Issues

**Symptom:** Access denied errors

```bash
# Check authentication is enabled
docker exec mongodb mongosh --eval "db.serverCmdLineOpts()" | grep auth

# List users
docker exec mongodb mongosh -u admin -p --eval "use admin; db.getUsers()"

# Check user roles
docker exec mongodb mongosh -u admin -p --eval "use admin; db.getUser('appuser')"

# Test user authentication
docker exec mongodb mongosh -u appuser -p --eval "db.runCommand({connectionStatus: 1})"

# Reset user password
docker exec mongodb mongosh -u admin -p --eval "
use admin;
db.changeUserPassword('appuser', 'NewPassword123!');
"

# Verify credentials in Vault
vault kv get secret/mongodb
```

## Security Best Practices

**Development Environment Considerations:**

```javascript
// 1. Use strong passwords
db.changeUserPassword("admin", "VeryStrongPassword123!")

// 2. Limit user privileges
db.createUser({
  user: "appuser",
  pwd: "SecurePass123!",
  roles: [{ role: "readWrite", db: "myapp" }]  // Only necessary permissions
})

// 3. Enable authentication (in mongod.conf)
// security:
//   authorization: enabled

// 4. Use specific database for authentication
db.createUser({
  user: "appuser",
  pwd: "SecurePass123!",
  roles: [{ role: "readWrite", db: "myapp" }]
},
{ authenticationDatabase: "admin" })

// 5. Regular password rotation
db.changeUserPassword("appuser", "NewPassword123!")

// 6. Audit user activity (enterprise feature)
// auditLog:
//   destination: file
//   format: JSON
//   path: /var/log/mongodb/audit.log

// 7. Remove unnecessary users
db.dropUser("testuser")

// 8. Use role-based access control
db.createRole({
  role: "appRole",
  privileges: [
    {
      resource: { db: "myapp", collection: "users" },
      actions: ["find", "insert", "update"]
    }
  ],
  roles: []
})

// 9. Limit network exposure (in mongod.conf)
// net:
//   bindIp: 127.0.0.1,172.20.0.15

// 10. Monitor failed login attempts
db.adminCommand({ getLog: "global" })
```

**⚠️ WARNING:** This is a development environment. Production requires:
- TLS/SSL encryption
- Network firewalls
- Replica sets for high availability
- Regular security audits
- Encrypted backups
- IP whitelisting

## Related Documentation

- [Service Configuration](Service-Configuration) - MongoDB service configuration
- [PostgreSQL Operations](PostgreSQL-Operations) - Similar SQL operations
- [MySQL Operations](MySQL-Operations) - Similar SQL operations
- [Backup and Restore](Backup-and-Restore) - Complete backup strategies
- [Container Management](Container-Management) - Docker operations
- [Health Monitoring](Health-Monitoring) - MongoDB health checks
- [Performance Tuning](Performance-Tuning) - MongoDB optimization

---

**Quick Reference Card:**

```bash
# Connection
mongosh "mongodb://localhost:27017" -u admin -p

# Database Operations
use myapp
show dbs
db.dropDatabase()

# Collection Operations
db.createCollection("users")
show collections
db.users.drop()

# CRUD Operations
db.users.insertOne({ name: "John" })
db.users.find({ status: "active" })
db.users.updateOne({ _id: 1 }, { $set: { status: "inactive" } })
db.users.deleteOne({ _id: 1 })

# Indexes
db.users.createIndex({ email: 1 })
db.users.getIndexes()
db.users.dropIndex("email_1")

# Backup/Restore
mongodump --db=myapp --out=/backup
mongorestore --db=myapp /backup/myapp

# Maintenance
db.users.reIndex()
db.runCommand({ compact: "users" })
db.users.validate()

# Monitoring
db.serverStatus()
db.currentOp()
db.stats()
```
