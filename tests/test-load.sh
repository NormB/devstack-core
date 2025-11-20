#!/usr/bin/env bash
#
# Load Testing Automation Suite
# Tests system behavior under various load conditions
# Validates resource usage, error handling, and performance under stress
#

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Load test parameters
SUSTAINED_USERS=100
SUSTAINED_DURATION=60

SPIKE_USERS=500
SPIKE_DURATION=10

RAMP_START=10
RAMP_END=200
RAMP_DURATION=120

DB_CONCURRENT_QUERIES=1000
CACHE_CONCURRENT_OPS=10000

# Performance thresholds
MAX_ERROR_RATE=1.0          # Maximum 1% error rate
MIN_SUCCESS_RATE=99.0       # Minimum 99% success rate
MAX_P95_LATENCY_MS=500      # Maximum p95 latency 500ms under load
MAX_P99_LATENCY_MS=1000     # Maximum p99 latency 1000ms under load

print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}"
}

print_test() {
    echo -e "${YELLOW}TEST: $1${NC}"
    ((TESTS_RUN++)) || true
}

print_pass() {
    echo -e "${GREEN}✓ PASS${NC}: $1"
    ((TESTS_PASSED++)) || true
}

print_fail() {
    echo -e "${RED}✗ FAIL${NC}: $1"
    ((TESTS_FAILED++)) || true
}

print_info() {
    echo -e "  ℹ $1"
}

# Get database password from Vault
get_db_password() {
    local service=$1
    export VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200}
    export VAULT_TOKEN=${VAULT_TOKEN:-$(cat ~/.config/vault/root-token 2>/dev/null || echo "")}

    if [ -z "$VAULT_TOKEN" ]; then
        echo "devpassword"  # Fallback
        return
    fi

    vault kv get -field=password "secret/$service" 2>/dev/null || echo "devpassword"
}

# Calculate percentile from sorted array
calculate_percentile() {
    local percentile=$1
    shift
    local values=("$@")
    local count=${#values[@]}
    local index=$(echo "($count * $percentile / 100) - 1" | bc)
    echo "${values[$index]}"
}

# Test sustained load on API
test_sustained_load() {
    print_test "Sustained load: $SUSTAINED_USERS concurrent users for ${SUSTAINED_DURATION}s"

    print_info "Running sustained load test..."
    local total_requests=0
    local successful_requests=0
    local failed_requests=0
    local response_times=()

    # Run concurrent requests
    local start_time=$(date +%s)
    local end_time=$((start_time + SUSTAINED_DURATION))

    while [ $(date +%s) -lt $end_time ]; do
        local pids=()

        # Launch concurrent requests
        for i in $(seq 1 $SUSTAINED_USERS); do
            (
                local req_start=$(date +%s.%N)
                if curl -s -f http://localhost:8000/health >/dev/null 2>&1; then
                    echo "SUCCESS"
                else
                    echo "FAIL"
                fi
                local req_end=$(date +%s.%N)
                local duration=$(echo "($req_end - $req_start) * 1000" | bc)
                echo "$duration"
            ) &
            pids+=($!)
        done

        # Wait for batch to complete
        for pid in "${pids[@]}"; do
            local result=$(wait $pid 2>/dev/null && cat /dev/fd/0 || echo "FAIL 0")
            ((total_requests++))

            if echo "$result" | grep -q "SUCCESS"; then
                ((successful_requests++))
            else
                ((failed_requests++))
            fi
        done

        sleep 0.1  # Brief pause between batches
    done

    local error_rate=$(echo "scale=2; ($failed_requests * 100) / $total_requests" | bc)
    local success_rate=$(echo "scale=2; ($successful_requests * 100) / $total_requests" | bc)

    print_info "Total requests: $total_requests"
    print_info "Successful: $successful_requests"
    print_info "Failed: $failed_requests"
    print_info "Error rate: ${error_rate}%"
    print_info "Success rate: ${success_rate}%"

    # Check if error rate is acceptable
    local error_check=$(echo "$error_rate <= $MAX_ERROR_RATE" | bc)
    if [ "$error_check" -eq 1 ]; then
        print_pass "Error rate under sustained load is acceptable (${error_rate}% <= ${MAX_ERROR_RATE}%)"
    else
        print_fail "Error rate under sustained load is too high (${error_rate}% > ${MAX_ERROR_RATE}%)"
    fi
}

# Test spike load on API
test_spike_load() {
    print_test "Spike load: $SPIKE_USERS concurrent users for ${SPIKE_DURATION}s"

    print_info "Running spike load test..."
    local total_requests=0
    local successful_requests=0
    local failed_requests=0

    local start_time=$(date +%s)
    local end_time=$((start_time + SPIKE_DURATION))

    while [ $(date +%s) -lt $end_time ]; do
        local pids=()

        # Launch spike of concurrent requests
        for i in $(seq 1 $SPIKE_USERS); do
            (
                if curl -s -f -m 5 http://localhost:8000/health >/dev/null 2>&1; then
                    echo "SUCCESS"
                else
                    echo "FAIL"
                fi
            ) &
            pids+=($!)
        done

        # Wait for batch to complete
        for pid in "${pids[@]}"; do
            local result=$(wait $pid 2>/dev/null && cat /dev/fd/0 || echo "FAIL")
            ((total_requests++))

            if echo "$result" | grep -q "SUCCESS"; then
                ((successful_requests++))
            else
                ((failed_requests++))
            fi
        done
    done

    local error_rate=$(echo "scale=2; ($failed_requests * 100) / $total_requests" | bc)
    local success_rate=$(echo "scale=2; ($successful_requests * 100) / $total_requests" | bc)

    print_info "Total requests: $total_requests"
    print_info "Successful: $successful_requests"
    print_info "Failed: $failed_requests"
    print_info "Error rate: ${error_rate}%"
    print_info "Success rate: ${success_rate}%"

    # Check if system handled spike
    local success_check=$(echo "$success_rate >= $MIN_SUCCESS_RATE" | bc)
    if [ "$success_check" -eq 1 ]; then
        print_pass "System handled spike load with acceptable success rate (${success_rate}% >= ${MIN_SUCCESS_RATE}%)"
    else
        print_fail "System struggled with spike load (${success_rate}% < ${MIN_SUCCESS_RATE}%)"
    fi
}

# Test gradual ramp load
test_gradual_ramp() {
    print_test "Gradual ramp: $RAMP_START → $RAMP_END users over ${RAMP_DURATION}s"

    print_info "Running gradual ramp test..."
    local total_requests=0
    local successful_requests=0
    local failed_requests=0

    local start_time=$(date +%s)
    local end_time=$((start_time + RAMP_DURATION))
    local step_duration=10  # Increase users every 10 seconds

    local current_users=$RAMP_START
    local user_increment=$(echo "($RAMP_END - $RAMP_START) / ($RAMP_DURATION / $step_duration)" | bc)

    while [ $(date +%s) -lt $end_time ]; do
        print_info "Current load: $current_users concurrent users"

        local pids=()

        # Launch concurrent requests
        for i in $(seq 1 $current_users); do
            (
                if curl -s -f http://localhost:8000/health >/dev/null 2>&1; then
                    echo "SUCCESS"
                else
                    echo "FAIL"
                fi
            ) &
            pids+=($!)
        done

        # Wait for batch to complete
        for pid in "${pids[@]}"; do
            local result=$(wait $pid 2>/dev/null && cat /dev/fd/0 || echo "FAIL")
            ((total_requests++))

            if echo "$result" | grep -q "SUCCESS"; then
                ((successful_requests++))
            else
                ((failed_requests++))
            fi
        done

        # Increment users for next iteration
        current_users=$((current_users + user_increment))
        sleep $step_duration
    done

    local error_rate=$(echo "scale=2; ($failed_requests * 100) / $total_requests" | bc)
    local success_rate=$(echo "scale=2; ($successful_requests * 100) / $total_requests" | bc)

    print_info "Total requests: $total_requests"
    print_info "Successful: $successful_requests"
    print_info "Failed: $failed_requests"
    print_info "Error rate: ${error_rate}%"
    print_info "Success rate: ${success_rate}%"

    # Check if system scaled well
    local error_check=$(echo "$error_rate <= $MAX_ERROR_RATE" | bc)
    if [ "$error_check" -eq 1 ]; then
        print_pass "System scaled well during gradual ramp (${error_rate}% <= ${MAX_ERROR_RATE}%)"
    else
        print_fail "System struggled during gradual ramp (${error_rate}% > ${MAX_ERROR_RATE}%)"
    fi
}

# Test concurrent database queries
test_database_load() {
    print_test "Database load: $DB_CONCURRENT_QUERIES concurrent queries"

    local password=$(get_db_password postgres)

    # Create test table
    print_info "Setting up test table..."
    docker exec -e PGPASSWORD="$password" dev-postgres \
        psql -U devuser -d devdb -c "DROP TABLE IF EXISTS load_test; CREATE TABLE load_test (id SERIAL PRIMARY KEY, data VARCHAR(100)); INSERT INTO load_test (data) SELECT md5(random()::text) FROM generate_series(1, 10000);" >/dev/null 2>&1

    print_info "Running $DB_CONCURRENT_QUERIES concurrent queries..."
    local successful=0
    local failed=0
    local pids=()

    for i in $(seq 1 $DB_CONCURRENT_QUERIES); do
        (
            if docker exec -e PGPASSWORD="$password" dev-postgres \
                psql -U devuser -d devdb -c "SELECT * FROM load_test WHERE id = $((RANDOM % 10000 + 1));" >/dev/null 2>&1; then
                echo "SUCCESS"
            else
                echo "FAIL"
            fi
        ) &
        pids+=($!)
    done

    # Wait for all queries to complete
    for pid in "${pids[@]}"; do
        local result=$(wait $pid 2>/dev/null && cat /dev/fd/0 || echo "FAIL")
        if echo "$result" | grep -q "SUCCESS"; then
            ((successful++))
        else
            ((failed++))
        fi
    done

    local success_rate=$(echo "scale=2; ($successful * 100) / $DB_CONCURRENT_QUERIES" | bc)

    print_info "Successful queries: $successful"
    print_info "Failed queries: $failed"
    print_info "Success rate: ${success_rate}%"

    # Cleanup
    docker exec -e PGPASSWORD="$password" dev-postgres \
        psql -U devuser -d devdb -c "DROP TABLE IF EXISTS load_test;" >/dev/null 2>&1

    # Check if database handled load
    local success_check=$(echo "$success_rate >= $MIN_SUCCESS_RATE" | bc)
    if [ "$success_check" -eq 1 ]; then
        print_pass "Database handled concurrent queries well (${success_rate}% >= ${MIN_SUCCESS_RATE}%)"
    else
        print_fail "Database struggled with concurrent queries (${success_rate}% < ${MIN_SUCCESS_RATE}%)"
    fi
}

# Test concurrent cache operations
test_cache_load() {
    print_test "Cache load: $CACHE_CONCURRENT_OPS concurrent operations"

    local password=$(get_db_password redis-1)

    print_info "Running $CACHE_CONCURRENT_OPS concurrent Redis operations..."
    local successful=0
    local failed=0
    local pids=()

    # Mix of SET and GET operations
    for i in $(seq 1 $CACHE_CONCURRENT_OPS); do
        (
            local key="load_test_key_$i"
            if [ $((i % 2)) -eq 0 ]; then
                # SET operation
                docker exec dev-redis-1 redis-cli -a "$password" SET "$key" "value_$i" >/dev/null 2>&1
            else
                # GET operation
                docker exec dev-redis-1 redis-cli -a "$password" GET "$key" >/dev/null 2>&1
            fi

            if [ $? -eq 0 ]; then
                echo "SUCCESS"
            else
                echo "FAIL"
            fi
        ) &
        pids+=($!)

        # Batch processing to avoid too many background processes
        if [ ${#pids[@]} -ge 100 ]; then
            for pid in "${pids[@]}"; do
                local result=$(wait $pid 2>/dev/null && cat /dev/fd/0 || echo "FAIL")
                if echo "$result" | grep -q "SUCCESS"; then
                    ((successful++))
                else
                    ((failed++))
                fi
            done
            pids=()
        fi
    done

    # Wait for remaining processes
    for pid in "${pids[@]}"; do
        local result=$(wait $pid 2>/dev/null && cat /dev/fd/0 || echo "FAIL")
        if echo "$result" | grep -q "SUCCESS"; then
            ((successful++))
        else
            ((failed++))
        fi
    done

    local success_rate=$(echo "scale=2; ($successful * 100) / $CACHE_CONCURRENT_OPS" | bc)

    print_info "Successful operations: $successful"
    print_info "Failed operations: $failed"
    print_info "Success rate: ${success_rate}%"

    # Cleanup test keys
    print_info "Cleaning up test keys..."
    for i in $(seq 1 $CACHE_CONCURRENT_OPS); do
        docker exec dev-redis-1 redis-cli -a "$password" DEL "load_test_key_$i" >/dev/null 2>&1 &
    done
    wait

    # Check if cache handled load
    local success_check=$(echo "$success_rate >= $MIN_SUCCESS_RATE" | bc)
    if [ "$success_check" -eq 1 ]; then
        print_pass "Cache handled concurrent operations well (${success_rate}% >= ${MIN_SUCCESS_RATE}%)"
    else
        print_fail "Cache struggled with concurrent operations (${success_rate}% < ${MIN_SUCCESS_RATE}%)"
    fi
}

# Test resource usage under load
test_resource_usage() {
    print_test "Resource usage monitoring during load"

    print_info "Collecting baseline resource usage..."
    local baseline_cpu=$(docker stats --no-stream --format "{{.CPUPerc}}" dev-reference-api | sed 's/%//')
    local baseline_mem=$(docker stats --no-stream --format "{{.MemUsage}}" dev-reference-api | cut -d/ -f1 | sed 's/MiB//')

    print_info "Baseline - CPU: ${baseline_cpu}%, Memory: ${baseline_mem}MiB"

    print_info "Applying load for 10 seconds..."

    # Apply load in background
    for i in {1..100}; do
        curl -s http://localhost:8000/health >/dev/null &
    done
    sleep 5

    # Measure under load
    local load_cpu=$(docker stats --no-stream --format "{{.CPUPerc}}" dev-reference-api | sed 's/%//')
    local load_mem=$(docker stats --no-stream --format "{{.MemUsage}}" dev-reference-api | cut -d/ -f1 | sed 's/MiB//')

    wait  # Wait for background requests to complete

    print_info "Under load - CPU: ${load_cpu}%, Memory: ${load_mem}MiB"

    # Check if resources are within acceptable limits (< 80% CPU, < 500MB memory)
    local cpu_check=$(echo "$load_cpu < 80" | bc)
    local mem_check=$(echo "$load_mem < 500" | bc)

    if [ "$cpu_check" -eq 1 ] && [ "$mem_check" -eq 1 ]; then
        print_pass "Resource usage under load is acceptable (CPU: ${load_cpu}%, Memory: ${load_mem}MiB)"
    else
        print_fail "Resource usage under load is high (CPU: ${load_cpu}%, Memory: ${load_mem}MiB)"
    fi
}

# Main test execution
main() {
    print_header "Load Testing Automation Suite"
    echo "Tests system behavior under various load conditions"
    echo ""

    # API load tests
    print_header "API Load Tests"
    echo "Note: These tests may take several minutes to complete"
    echo ""

    test_sustained_load
    test_spike_load
    test_gradual_ramp

    # Infrastructure load tests
    print_header "Infrastructure Load Tests"
    test_database_load
    test_cache_load

    # Resource monitoring
    print_header "Resource Monitoring"
    test_resource_usage

    # Summary
    print_header "Test Summary"
    echo "Tests run: $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}✓ ALL LOAD TESTS PASSED${NC}"
        exit 0
    else
        echo -e "\n${RED}✗ SOME LOAD TESTS FAILED${NC}"
        exit 1
    fi
}

# Run main function
main
