#!/bin/bash
################################################################################
# PostgreSQL Extended Integration Test Suite
#
# Additional comprehensive tests for PostgreSQL integration including
# advanced queries, transaction handling, connection pooling, replication
# status, performance, and security features.
#
# TESTS:
#   1. Transaction isolation levels
#   2. Concurrent connection handling
#   3. Query performance and explain plans
#   4. Database encoding and collation
#   5. Extension availability and functionality
#   6. Table statistics and vacuum operations
#   7. Index creation and usage
#   8. JSON/JSONB operations
#   9. Full-text search capabilities
#   10. Connection limit enforcement
#
# VERSION: 1.0.0
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

# PostgreSQL configuration
POSTGRES_HOST="${POSTGRES_HOST:-localhost}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_DB="${POSTGRES_DB:-devdb}"

# Always get credentials from Vault (ignore environment variables)
if [ -f ~/.config/vault/root-token ]; then
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

    # Retrieve user, database, and password from Vault
    POSTGRES_USER=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        http://localhost:8200/v1/secret/data/postgres 2>/dev/null | jq -r '.data.data.user' 2>/dev/null)

    POSTGRES_DB=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        http://localhost:8200/v1/secret/data/postgres 2>/dev/null | jq -r '.data.data.database' 2>/dev/null)

    POSTGRES_PASSWORD=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
        http://localhost:8200/v1/secret/data/postgres 2>/dev/null | jq -r '.data.data.password' 2>/dev/null)
fi

# Set defaults if Vault retrieval failed
POSTGRES_USER="${POSTGRES_USER:-devuser}"
POSTGRES_DB="${POSTGRES_DB:-devdb}"

# Verify we got the password
if [ -z "$POSTGRES_PASSWORD" ] || [ "$POSTGRES_PASSWORD" == "null" ]; then
    echo "Warning: Could not retrieve PostgreSQL password from Vault"
else
    export PGPASSWORD="$POSTGRES_PASSWORD"
fi

info() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

success() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$2")
}

################################################################################
# Test 1: Transaction isolation levels
################################################################################
test_transaction_isolation() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: Transaction isolation levels"

    # Test READ COMMITTED (default)
    local result=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SHOW transaction_isolation;" 2>/dev/null | tr -d ' ')

    if [ -z "$result" ]; then
        fail "Could not query transaction isolation level" "Transaction isolation"
        return 1
    fi

    # Test setting different isolation levels
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE; COMMIT;" &>/dev/null

    if [ $? -eq 0 ]; then
        success "Transaction isolation levels working (current: $result, serializable: OK)"
        return 0
    fi

    fail "Transaction isolation level test failed" "Transaction isolation"
    return 1
}

################################################################################
# Test 2: Concurrent connections stress test
################################################################################
test_concurrent_connections() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: Concurrent connection handling"

    # Get current connection count
    local baseline_conns=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')

    if [ -z "$baseline_conns" ]; then
        fail "Could not query connection count" "Concurrent connections"
        return 1
    fi

    # Create 10 concurrent connections with longer-running queries
    for i in {1..10}; do
        psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT pg_sleep(1);" &>/dev/null &
    done

    # Give connections time to establish
    sleep 0.5

    # Check peak connection count
    local peak_conns=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')

    wait

    # Peak should be higher than baseline (at least baseline + some of the 10 new connections)
    if [ -n "$peak_conns" ] && [ "$peak_conns" -gt "$baseline_conns" ]; then
        local added_conns=$((peak_conns - baseline_conns))
        success "Concurrent connections handled (baseline: $baseline_conns, peak: $peak_conns, added: $added_conns)"
        return 0
    fi

    fail "Concurrent connection test failed" "Concurrent connections"
    return 1
}

################################################################################
# Test 3: Query performance and explain
################################################################################
test_query_performance() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: Query performance and explain plans"

    # Create a test table with data
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null <<EOF
DROP TABLE IF EXISTS perf_test;
CREATE TABLE perf_test (id SERIAL PRIMARY KEY, data TEXT, created_at TIMESTAMP DEFAULT NOW());
INSERT INTO perf_test (data) SELECT 'test_' || generate_series(1, 1000);
EOF

    if [ $? -ne 0 ]; then
        fail "Could not create performance test table" "Query performance"
        return 1
    fi

    # Test EXPLAIN output
    local explain_output=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "EXPLAIN SELECT * FROM perf_test WHERE id < 100;" 2>/dev/null)

    # Test EXPLAIN ANALYZE for timing information
    local analyze_output=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "EXPLAIN ANALYZE SELECT COUNT(*) FROM perf_test;" 2>/dev/null | grep -i "execution time")

    # Cleanup
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "DROP TABLE IF EXISTS perf_test;" &>/dev/null

    if [ -n "$explain_output" ] && [ -n "$analyze_output" ]; then
        success "Query performance analysis working (EXPLAIN and EXPLAIN ANALYZE functional)"
        return 0
    fi

    fail "Query performance test failed" "Query performance"
    return 1
}

################################################################################
# Test 4: Database encoding and collation
################################################################################
test_encoding_collation() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Database encoding and collation"

    local encoding=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SHOW server_encoding;" 2>/dev/null | tr -d ' ')

    # Query collation and ctype from pg_database (they're not runtime parameters)
    local collation=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT datcollate FROM pg_database WHERE datname = 'postgres';" 2>/dev/null | tr -d ' ')

    local ctype=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT datctype FROM pg_database WHERE datname = 'postgres';" 2>/dev/null | tr -d ' ')

    if [ -n "$encoding" ] && [ -n "$collation" ] && [ -n "$ctype" ]; then
        success "Database encoding configured (encoding: $encoding, collation: $collation, ctype: $ctype)"
        return 0
    fi

    fail "Encoding/collation test failed" "Encoding and collation"
    return 1
}

################################################################################
# Test 5: PostgreSQL extensions
################################################################################
test_extensions() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: Extension availability and functionality"

    # Check available extensions
    local available_exts=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT count(*) FROM pg_available_extensions;" 2>/dev/null | tr -d ' ')

    if [ -z "$available_exts" ] || [ "$available_exts" -eq 0 ]; then
        fail "No extensions available" "Extensions"
        return 1
    fi

    # Try to create and use pg_trgm extension for similarity searches
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null <<EOF
DROP EXTENSION IF EXISTS pg_trgm CASCADE;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
SELECT similarity('hello', 'helo');
EOF

    if [ $? -eq 0 ]; then
        success "Extensions working ($available_exts available, pg_trgm tested successfully)"
        return 0
    fi

    fail "Extension test failed" "Extensions"
    return 1
}

################################################################################
# Test 6: Table statistics and vacuum
################################################################################
test_statistics_vacuum() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Table statistics and vacuum operations"

    # Create test table
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null <<EOF
DROP TABLE IF EXISTS vacuum_test;
CREATE TABLE vacuum_test (id SERIAL PRIMARY KEY, data TEXT);
INSERT INTO vacuum_test (data) SELECT 'row_' || generate_series(1, 100);
EOF

    # Run ANALYZE to update statistics
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "ANALYZE vacuum_test;" &>/dev/null

    # Check statistics
    local stats=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT n_tup_ins FROM pg_stat_user_tables WHERE relname='vacuum_test';" 2>/dev/null | tr -d ' ')

    # Run VACUUM
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "VACUUM vacuum_test;" &>/dev/null

    local vacuum_result=$?

    # Cleanup
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "DROP TABLE IF EXISTS vacuum_test;" &>/dev/null

    if [ "$vacuum_result" -eq 0 ] && [ "$stats" == "100" ]; then
        success "Statistics and VACUUM working (inserted rows: $stats, vacuum: OK)"
        return 0
    fi

    fail "Statistics/VACUUM test failed" "Statistics and vacuum"
    return 1
}

################################################################################
# Test 7: Index creation and usage
################################################################################
test_indexes() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: Index creation and usage"

    # Create test table with index
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null <<EOF
DROP TABLE IF EXISTS index_test;
CREATE TABLE index_test (id SERIAL PRIMARY KEY, email TEXT, username TEXT);
INSERT INTO index_test (email, username)
    SELECT 'user' || i || '@example.com', 'user' || i
    FROM generate_series(1, 1000) AS i;
CREATE INDEX idx_email ON index_test(email);
CREATE INDEX idx_username ON index_test(username);
EOF

    if [ $? -ne 0 ]; then
        fail "Could not create test table with indexes" "Indexes"
        return 1
    fi

    # Verify indexes exist
    local index_count=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT count(*) FROM pg_indexes WHERE tablename='index_test';" 2>/dev/null | tr -d ' ')

    # Check if index is used in query plan
    local uses_index=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "EXPLAIN SELECT * FROM index_test WHERE email='user500@example.com';" 2>/dev/null | grep -c "idx_email")

    # Cleanup
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "DROP TABLE IF EXISTS index_test;" &>/dev/null

    if [ "$index_count" -ge 2 ] && [ "$uses_index" -gt 0 ]; then
        success "Indexes working ($index_count indexes created, query optimizer uses indexes)"
        return 0
    fi

    fail "Index test failed" "Indexes"
    return 1
}

################################################################################
# Test 8: JSON/JSONB operations
################################################################################
test_json_operations() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: JSON/JSONB operations"

    # Create table with JSONB column
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null <<EOF
DROP TABLE IF EXISTS json_test;
CREATE TABLE json_test (id SERIAL PRIMARY KEY, data JSONB);
INSERT INTO json_test (data) VALUES
    ('{"name": "John", "age": 30, "tags": ["developer", "postgresql"]}'),
    ('{"name": "Jane", "age": 25, "tags": ["manager", "devops"]}');
EOF

    # Test JSONB queries
    local json_query=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT data->>'name' FROM json_test WHERE data->>'age' = '30';" 2>/dev/null | tr -d ' ')

    # Test JSONB operators
    local jsonb_contains=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT count(*) FROM json_test WHERE data @> '{\"tags\": [\"developer\"]}';" 2>/dev/null | tr -d ' ')

    # Cleanup
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "DROP TABLE IF EXISTS json_test;" &>/dev/null

    if [ "$json_query" == "John" ] && [ "$jsonb_contains" == "1" ]; then
        success "JSON/JSONB operations working (queries and operators functional)"
        return 0
    fi

    fail "JSON/JSONB test failed" "JSON operations"
    return 1
}

################################################################################
# Test 9: Full-text search
################################################################################
test_fulltext_search() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: Full-text search capabilities"

    # Create table with text data
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" &>/dev/null <<EOF
DROP TABLE IF EXISTS fts_test;
CREATE TABLE fts_test (id SERIAL PRIMARY KEY, title TEXT, content TEXT, tsv tsvector);
INSERT INTO fts_test (title, content) VALUES
    ('PostgreSQL Tutorial', 'Learn about PostgreSQL database management'),
    ('Docker Guide', 'Container orchestration with Docker and Kubernetes'),
    ('Vault Security', 'HashiCorp Vault for secrets management');
UPDATE fts_test SET tsv = to_tsvector('english', title || ' ' || content);
CREATE INDEX idx_fts ON fts_test USING GIN(tsv);
EOF

    # Test full-text search
    local search_result=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT title FROM fts_test WHERE tsv @@ to_tsquery('english', 'PostgreSQL');" 2>/dev/null | grep -c "PostgreSQL")

    # Test ranked search
    local ranked_result=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT title, ts_rank(tsv, to_tsquery('english', 'database')) as rank
         FROM fts_test
         WHERE tsv @@ to_tsquery('english', 'database')
         ORDER BY rank DESC;" 2>/dev/null | grep -c "PostgreSQL")

    # Cleanup
    psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c \
        "DROP TABLE IF EXISTS fts_test;" &>/dev/null

    if [ "$search_result" -gt 0 ] && [ "$ranked_result" -gt 0 ]; then
        success "Full-text search working (search and ranking functional)"
        return 0
    fi

    fail "Full-text search test failed" "Full-text search"
    return 1
}

################################################################################
# Test 10: Connection pool and limits
################################################################################
test_connection_limits() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: Connection limit configuration"

    # Check max connections setting
    local max_conns=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SHOW max_connections;" 2>/dev/null | tr -d ' ')

    # Check current connections
    local current_conns=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT count(*) FROM pg_stat_activity;" 2>/dev/null | tr -d ' ')

    # Check connection statistics
    local stats=$(psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c \
        "SELECT numbackends, xact_commit, xact_rollback
         FROM pg_stat_database
         WHERE datname='postgres';" 2>/dev/null)

    if [ -n "$max_conns" ] && [ -n "$current_conns" ] && [ -n "$stats" ]; then
        local usage_pct=$((current_conns * 100 / max_conns))
        success "Connection limits configured (max: $max_conns, current: $current_conns, usage: ${usage_pct}%)"
        return 0
    fi

    fail "Connection limit test failed" "Connection limits"
    return 1
}

################################################################################
# Run all tests
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  PostgreSQL Extended Test Suite"
    echo "========================================="
    echo

    test_transaction_isolation || true
    test_concurrent_connections || true
    test_query_performance || true
    test_encoding_collation || true
    test_extensions || true
    test_statistics_vacuum || true
    test_indexes || true
    test_json_operations || true
    test_fulltext_search || true
    test_connection_limits || true

    echo
    echo "========================================="
    echo "  Test Results"
    echo "========================================="
    echo "Total tests: $TESTS_RUN"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    if [ $TESTS_FAILED -gt 0 ]; then
        echo -e "${RED}Failed: $TESTS_FAILED${NC}"
        echo
        echo "Failed tests:"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
    fi
    echo "========================================="
    echo

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}✓ All PostgreSQL extended tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
