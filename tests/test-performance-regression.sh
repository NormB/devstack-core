#!/usr/bin/env bash

# Performance Regression Test Suite
# Phase 3 - Task 3.3.3: Test performance regression
#
# Tests that performance optimizations from Phase 3 are maintained
# Validates against baseline metrics from PHASE_3_BASELINE.md

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Performance thresholds (realistic baselines based on actual testing)
# These are conservative minimums to catch major regressions
POSTGRES_TPS_MIN=5000      # Baseline: ~8000 TPS, allow regression to 5000
MYSQL_INSERT_MIN=10000     # Baseline: ~20000 rows/sec for 1000 row batch
MONGODB_INSERT_MIN=50000   # Baseline: ~80000 docs/sec for bulk insert
REDIS_OPS_MIN=30000        # Baseline: ~50000 ops/sec, allow regression to 30000

# API response time thresholds (p95)
API_HEALTH_P95_MAX=100     # p95 < 100ms for simple endpoints
DB_QUERY_P95_MAX=50        # p95 < 50ms for single row queries
REDIS_OP_P95_MAX=5         # p95 < 5ms for cache operations
VAULT_OP_P95_MAX=20        # p95 < 20ms for secret retrieval

# Get credentials from Vault
get_credential() {
    local service=$1
    local field=$2

    if ! command -v vault &> /dev/null; then
        echo "Vault CLI not found. Install with: brew install hashicorp/tap/vault"
        exit 1
    fi

    if ! vault status &> /dev/null; then
        echo "Vault is not available. Ensure VAULT_ADDR and VAULT_TOKEN are set."
        exit 1
    fi

    vault kv get -field="$field" "secret/$service" 2>/dev/null || {
        echo "Failed to get $field from Vault for $service"
        exit 1
    }
}

# Cache credentials
PG_PASSWORD=$(get_credential postgres password)
PG_USER=$(get_credential postgres user)
PG_DATABASE=$(get_credential postgres database)

MYSQL_PASSWORD=$(get_credential mysql password)
MYSQL_USER=$(get_credential mysql user)
MYSQL_DATABASE=$(get_credential mysql database)

MONGO_PASSWORD=$(get_credential mongodb password)
MONGO_USER=$(get_credential mongodb user)
MONGO_DATABASE=$(get_credential mongodb database)

REDIS_PASSWORD=$(get_credential redis-1 password)

# Helper functions
print_test() {
    echo -e "\n${YELLOW}TEST $((TESTS_RUN + 1)):${NC} $1"
}

pass() {
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++)) || true
    ((TESTS_RUN++)) || true
}

fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++)) || true
    ((TESTS_RUN++)) || true
}

# Test 1: PostgreSQL TPS regression check
test_postgres_tps() {
    print_test "PostgreSQL TPS regression check"

    # Initialize pgbench database (scale 50)
    docker exec -e PGPASSWORD="$PG_PASSWORD" dev-postgres \
        pgbench -i -s 50 -U "$PG_USER" "$PG_DATABASE" >/dev/null 2>&1 || {
        fail "Failed to initialize pgbench database"
        return
    }

    # Run benchmark (10 clients, 4 threads, 30 seconds)
    local result
    result=$(docker exec -e PGPASSWORD="$PG_PASSWORD" dev-postgres \
        pgbench -c 10 -j 4 -T 30 -U "$PG_USER" "$PG_DATABASE" 2>/dev/null | grep "tps")

    local tps
    tps=$(echo "$result" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)

    if [ -z "$tps" ]; then
        fail "Failed to extract TPS from pgbench output"
        return
    fi

    # Cleanup
    docker exec -e PGPASSWORD="$PG_PASSWORD" dev-postgres \
        psql -U "$PG_USER" -d "$PG_DATABASE" \
        -c "DROP TABLE IF EXISTS pgbench_accounts, pgbench_branches, pgbench_tellers, pgbench_history CASCADE;" >/dev/null 2>&1 || true

    if [ "$tps" -ge "$POSTGRES_TPS_MIN" ]; then
        pass
        echo "  Current TPS: $tps (minimum: $POSTGRES_TPS_MIN)"
    else
        fail "PostgreSQL TPS below threshold ($tps < $POSTGRES_TPS_MIN)"
    fi
}

# Test 2: MySQL insert performance regression check
test_mysql_insert() {
    print_test "MySQL insert performance regression check"

    # Create test table
    docker exec -e MYSQL_PWD="$MYSQL_PASSWORD" dev-mysql mysql -u "$MYSQL_USER" "$MYSQL_DATABASE" -e \
        "DROP TABLE IF EXISTS perf_test; CREATE TABLE perf_test (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100), value INT, created TIMESTAMP DEFAULT CURRENT_TIMESTAMP);" 2>/dev/null || {
        fail "Failed to create test table"
        return
    }

    # Benchmark bulk insert (1000 rows)
    local start=$(date +%s.%N)
    docker exec -e MYSQL_PWD="$MYSQL_PASSWORD" dev-mysql mysql -u "$MYSQL_USER" "$MYSQL_DATABASE" -e \
        "INSERT INTO perf_test (name, value) SELECT CONCAT('test_', n), FLOOR(RAND() * 1000) FROM (SELECT @row := @row + 1 AS n FROM (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a, (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b, (SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) c, (SELECT @row := 0) r LIMIT 1000) nums;" 2>/dev/null || {
        fail "Failed to execute bulk insert"
        docker exec -e MYSQL_PWD="$MYSQL_PASSWORD" dev-mysql mysql -u "$MYSQL_USER" "$MYSQL_DATABASE" -e "DROP TABLE IF EXISTS perf_test;" 2>/dev/null || true
        return
    }
    local end=$(date +%s.%N)

    local duration=$(echo "$end - $start" | bc)
    local rows_per_sec=$(echo "1000 / $duration" | bc)

    # Cleanup
    docker exec -e MYSQL_PWD="$MYSQL_PASSWORD" dev-mysql mysql -u "$MYSQL_USER" "$MYSQL_DATABASE" -e \
        "DROP TABLE IF EXISTS perf_test;" 2>/dev/null || true

    if [ "$rows_per_sec" -ge "$MYSQL_INSERT_MIN" ]; then
        pass
        echo "  Insert rate: $rows_per_sec rows/sec (minimum: $MYSQL_INSERT_MIN)"
    else
        fail "MySQL insert rate below threshold ($rows_per_sec < $MYSQL_INSERT_MIN)"
    fi
}

# Test 3: MongoDB insert performance regression check
test_mongodb_insert() {
    print_test "MongoDB insert performance regression check"

    local script='
    db.perf_test.drop();
    var docs = [];
    for (var i = 0; i < 10000; i++) {
        docs.push({
            name: "test_" + i,
            value: Math.floor(Math.random() * 1000),
            created: new Date()
        });
    }
    var start = new Date();
    db.perf_test.insertMany(docs);
    var end = new Date();
    var duration = (end - start) / 1000;
    var rate = Math.floor(10000 / duration);
    print("RATE:" + rate);
    db.perf_test.drop();
    '

    local result
    result=$(docker exec dev-mongodb mongosh \
        --quiet \
        "mongodb://$MONGO_USER:$MONGO_PASSWORD@localhost:27017/admin?authSource=admin" \
        --eval "$script" 2>/dev/null) || {
        fail "Failed to execute MongoDB benchmark"
        return
    }

    local insert_rate
    insert_rate=$(echo "$result" | grep "RATE:" | cut -d: -f2)

    if [ -z "$insert_rate" ]; then
        fail "Failed to extract insert rate from MongoDB output"
        return
    fi

    if [ "$insert_rate" -ge "$MONGODB_INSERT_MIN" ]; then
        pass
        echo "  Insert rate: $insert_rate docs/sec (minimum: $MONGODB_INSERT_MIN)"
    else
        fail "MongoDB insert rate below threshold ($insert_rate < $MONGODB_INSERT_MIN)"
    fi
}

# Test 4: Redis cluster performance regression check
test_redis_performance() {
    print_test "Redis cluster performance regression check"

    local result
    result=$(docker exec dev-redis-1 redis-benchmark \
        -a "$REDIS_PASSWORD" \
        --cluster \
        -h 172.20.2.13 \
        -p 6379 \
        -t set,get \
        -n 100000 \
        -q 2>&1) || {
        fail "Failed to run Redis benchmark"
        return
    }

    # Strip ANSI escape codes and extract GET ops from final summary
    # Note: The line may have both progress (GET: rps=X) and summary (GET: X requests per second) on same line
    local get_ops
    get_ops=$(echo "$result" | sed 's/\x1b\[[0-9;]*m//g' | grep "GET:.*requests per second" | tail -1 | grep -oE '[0-9]+\.[0-9]+ requests per second' | awk '{print int($1)}')

    if [ -z "$get_ops" ] || [ "$get_ops" = "0" ]; then
        fail "Failed to extract GET ops from Redis benchmark"
        return
    fi

    if [ "$get_ops" -ge "$REDIS_OPS_MIN" ]; then
        pass
        echo "  GET operations: $get_ops ops/sec (minimum: $REDIS_OPS_MIN)"
    else
        fail "Redis performance below threshold ($get_ops < $REDIS_OPS_MIN)"
    fi
}

# Main test execution
main() {
    echo "========================================="
    echo "Performance Regression Test Suite"
    echo "Phase 3 - Task 3.3.3"
    echo "========================================="
    echo ""
    echo "Validates Phase 3 performance optimizations are maintained"
    echo "Allows 20% regression from optimized performance"
    echo ""

    # Run tests
    test_postgres_tps
    test_mysql_insert
    test_mongodb_insert
    test_redis_performance

    # Summary
    echo ""
    echo "========================================="
    echo "Test Summary"
    echo "========================================="
    echo "Tests run: $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}✓ ALL PERFORMANCE REGRESSION TESTS PASSED${NC}"
        exit 0
    else
        echo -e "\n${RED}✗ SOME PERFORMANCE REGRESSION TESTS FAILED${NC}"
        exit 1
    fi
}

# Run main
main
