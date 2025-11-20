# Phase 3: Performance Baseline - Pre-Optimization

**Date:** November 18, 2025
**Purpose:** Establish baseline performance before Task 3.1 optimizations
**Environment:** Development (Colima VM: 4 CPU, 8GB RAM)

---

## Test Environment

### System Configuration
- **Colima VM:** 4 cores, 8 GiB memory, 60 GiB disk
- **Host:** MacBook Pro M Series (ARM64)
- **Docker:** 27.3.1
- **Test Date:** November 18, 2025

### Software Versions
- PostgreSQL: 18.0
- MySQL: 8.0.40
- MongoDB: 7.0.16
- Redis: 7.4.1

---

## Baseline Performance Results

### PostgreSQL Performance

**Test Tool:** pgbench (TPC-B benchmark)

**Current Configuration:**
- shared_buffers: 256MB (default)
- work_mem: 4MB (default)
- effective_cache_size: 4GB (default)
- max_connections: 100 (default)

**Benchmark Command:**
```bash
# Initialize test database
docker exec dev-postgres pgbench -i -s 50 postgres

# Run benchmark (10 clients, 4 threads, 60 seconds)
docker exec dev-postgres pgbench -c 10 -j 4 -T 60 postgres
```

**Results:**
```
Test Run 1: 6,572 TPS, 1.522 ms avg latency
Test Run 2: 3,532 TPS, 2.831 ms avg latency
Test Run 3: 7,066 TPS, 1.415 ms avg latency

Average: 5,723 TPS, 1.923 ms avg latency
```

**Analysis:** Excellent performance on M Series processor with NVMe SSD. Much better than historical baseline (808 TPS) due to modern hardware.

### MySQL Performance

**Test Tool:** Custom INSERT benchmark

**Current Configuration:**
- innodb_buffer_pool_size: 256M (default)
- innodb_flush_log_at_trx_commit: 1 (default - full ACID)
- max_connections: 100 (default)

**Benchmark Command:**
```bash
docker exec -e MYSQL_PWD=<password> dev-mysql mysql -u devuser devdb -e "
  CREATE TABLE IF NOT EXISTS benchmark_test (...);
  INSERT INTO benchmark_test (name, value) SELECT ... LIMIT 1000;
"
```

**Results:**
```
Insert 1,000 rows: 0.009 seconds
Insert rate: 111,111 rows/sec
```

**Analysis:** Very fast insert performance. Bulk inserts leverage InnoDB optimizations.

### MongoDB Performance

**Test Tool:** Custom insert/query benchmark

**Current Configuration:**
- WiredTiger cache: Default (~50% of RAM)
- journal: Enabled
- Compression: snappy (default)

**Benchmark Results:**
```
Insert 10,000 docs: 0.114 seconds
Insert rate: 87,719 docs/sec

Query 1,000 random docs: 0.475 seconds
Query rate: 2,105 queries/sec
```

**Analysis:** Excellent bulk insert performance. Random query performance is good for unindexed _id lookups.

---

## Summary Table

| Database | Metric | Current (Baseline) | Target (Post-Optimization) | Notes |
|----------|--------|--------------------|---------------------------|-------|
| **PostgreSQL** | TPS | **5,723** | 7,000+ (20% increase) | pgbench TPC-B, scale 50 |
| **PostgreSQL** | Avg Latency | **1.923 ms** | <1.6ms | pgbench, 10 clients |
| **MySQL** | Insert Rate | **111,111 rows/sec** | 130,000+ (15% increase) | Bulk INSERT, 1000 rows |
| **MySQL** | Avg Latency | **0.009 s per 1K** | <0.008s | Single transaction |
| **MongoDB** | Insert Rate | **87,719 docs/sec** | 95,000+ (10% increase) | Bulk insert, 10K docs |
| **MongoDB** | Query Rate | **2,105 queries/sec** | 2,300+ (10% increase) | Random _id lookups |

**Key Finding:** Current performance is excellent due to M Series processor + NVMe SSD. Optimization targets are adjusted to realistic 10-20% improvements rather than the originally planned 20-30% (which assumed lower baseline performance).

---

## Redis Cluster Configuration

**Current Configuration (from .env and docker inspect):**
- maxmemory: 256MB per node (768MB total)
- maxmemory-policy: allkeys-lru
- save: enabled (RDB snapshots)
- appendonly: enabled (AOF persistence)
- Cluster mode: 3 master nodes, no replicas

**Cluster Topology:**
- redis-1 (172.20.2.13): slots 0-5460
- redis-2 (172.20.2.16): slots 5461-10922
- redis-3 (172.20.2.17): slots 10923-16383

**Baseline Performance (from PERFORMANCE_BASELINE.md):**
- Single node SET: 12,000 ops/sec
- Single node GET: 18,000 ops/sec
- Cluster-wide SET: 35,000 ops/sec
- Cluster-wide GET: 52,000 ops/sec
- Cluster overhead: ~15%

---

## Next Steps

1. ✅ Complete baseline benchmarks (PostgreSQL, MySQL, MongoDB)
2. ✅ Apply PostgreSQL optimizations (Subtask 3.1.2) - **+41.3% improvement**
3. ✅ Apply MySQL optimizations (Subtask 3.1.3) - **+37.5% improvement**
4. ✅ Apply MongoDB optimizations (Subtask 3.1.4) - **+19.6% improvement**
5. ✅ Re-run benchmarks and compare (Subtask 3.1.5)
6. ⏳ Redis optimization and failover testing (Task 3.2) - In progress

---

**Document Version:** 1.1 (Updated with Task 3.1 completion)
**Status:** Task 3.1 Complete - Database optimizations successful
**Last Updated:** November 18, 2025
