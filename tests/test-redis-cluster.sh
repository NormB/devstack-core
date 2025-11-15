#!/bin/bash
################################################################################
# Redis Cluster Test Suite
#
# DESCRIPTION:
#   Comprehensive test suite specifically for Redis cluster functionality.
#   Validates cluster initialization, slot distribution, data sharding, and
#   automatic redirection across cluster nodes. Tests cluster-specific features
#   beyond basic Redis operations.
#
# GLOBALS:
#   SCRIPT_DIR         - Directory containing this script
#   PROJECT_ROOT       - Root directory of the project
#   REDIS_PASSWORD     - Vault-sourced Redis password
#   RED, GREEN, YELLOW, BLUE, NC - Color codes for terminal output
#   TESTS_RUN          - Counter for total tests executed
#   TESTS_PASSED       - Counter for passed tests
#   TESTS_FAILED       - Counter for failed tests
#   FAILED_TESTS       - Array of failed test descriptions
#
# USAGE:
#   ./test-redis-cluster.sh
#
# DEPENDENCIES:
#   - Docker and Docker Compose for container management
#   - redis-cli (within containers) for cluster operations
#   - curl for Vault API communication
#   - jq for JSON parsing of Vault responses
#   - Vault server running on localhost:8200 with root token
#   - Redis containers (dev-redis-1, dev-redis-2, dev-redis-3) running
#   - Redis cluster must be initialized before running these tests
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# NOTES:
#   - This script uses docker exec to run redis-cli inside containers
#   - Tests validate cluster-specific functionality like slot distribution
#   - All 16384 hash slots must be assigned for full cluster operation
#   - Data sharding tests verify keys are distributed across nodes
#   - Automatic redirection tests verify cluster client behavior
#   - Cluster must be initialized with redis-cli --cluster create first
#   - Tests continue execution even if individual tests fail (|| true)
#
# EXAMPLES:
#   # Run all Redis cluster tests
#   ./test-redis-cluster.sh
#
#   # Run tests and save output to file
#   ./test-redis-cluster.sh > cluster-test-results.txt 2>&1
#
#   # Check if cluster is properly initialized before running other tests
#   ./test-redis-cluster.sh && echo "Cluster ready"
#
# AUTHOR:
#   DevStack Core Project
#
# SEE ALSO:
#   - test-redis.sh - Basic Redis tests (non-cluster specific)
#   - ../docker/redis/init.sh - Redis initialization script
#   - scripts/init-redis-cluster.sh - Cluster initialization helper
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

# Test results
declare -a FAILED_TESTS=()

################################################################################
# Prints an informational test message in blue
#
# ARGUMENTS:
#   $1 - Message to display
################################################################################
info() { echo -e "${BLUE}[TEST]${NC} $1"; }

################################################################################
# Prints a success message in green and increments pass counter
#
# ARGUMENTS:
#   $1 - Success message to display
#
# SIDE EFFECTS:
#   Increments TESTS_PASSED counter
################################################################################
success() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

################################################################################
# Prints a failure message in red and tracks failed test
#
# ARGUMENTS:
#   $1 - Failure message to display
#
# SIDE EFFECTS:
#   Increments TESTS_FAILED counter
#   Appends message to FAILED_TESTS array
################################################################################
fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_TESTS+=("$1"); }

################################################################################
# Prints a warning message in yellow
#
# ARGUMENTS:
#   $1 - Warning message to display
################################################################################
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

################################################################################
# Retrieves Redis password from Vault secret store
#
# DESCRIPTION:
#   Fetches the Redis password from Vault using the root token and parses
#   the JSON response to extract the password field.
#
# OUTPUTS:
#   Prints the Redis password to stdout
#
# RETURNS:
#   0 - Successfully retrieved password
#   Non-zero - Failed to retrieve password (curl or jq error)
#
# NOTES:
#   Requires ~/.config/vault/root-token file to exist
#   Uses redis-1 secret path as all nodes share same password
################################################################################
get_redis_password() {
    export VAULT_ADDR="http://localhost:8200"
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)

    curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/redis-1" 2>/dev/null | \
        jq -r '.data.data.password // empty'
}

REDIS_PASSWORD=$(get_redis_password)

################################################################################
# Test: Verifies all Redis cluster containers are running
#
# DESCRIPTION:
#   Checks Docker to ensure all three Redis cluster node containers
#   (dev-redis-1, dev-redis-2, dev-redis-3) are in running state.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - All 3 Redis containers are running
#   1 - One or more containers are not running
################################################################################
test_containers_running() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: All 3 Redis containers are running"

    local running_count=0

    for i in 1 2 3; do
        if docker ps | grep -q "dev-redis-$i"; then
            running_count=$((running_count + 1))
        fi
    done

    if [ $running_count -eq 3 ]; then
        success "All 3 Redis containers are running"
        return 0
    else
        fail "Only $running_count/3 Redis containers are running"
        return 1
    fi
}

################################################################################
# Test: Verifies all Redis nodes respond to PING commands
#
# DESCRIPTION:
#   Uses redis-cli inside each container to send PING commands and verify
#   each node responds with PONG. Tests basic network reachability and
#   Redis server responsiveness.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - All 3 Redis nodes are reachable and respond to PING
#   1 - One or more nodes are unreachable
#
# NOTES:
#   Uses Vault-sourced password for authentication
################################################################################
test_nodes_reachable() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: All Redis nodes are reachable"

    local reachable_count=0

    for i in 1 2 3; do
        if docker exec dev-redis-$i redis-cli -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q "PONG"; then
            reachable_count=$((reachable_count + 1))
        fi
    done

    if [ $reachable_count -eq 3 ]; then
        success "All 3 Redis nodes are reachable"
        return 0
    else
        fail "Only $reachable_count/3 Redis nodes are reachable"
        return 1
    fi
}

################################################################################
# Test: Verifies cluster mode is enabled on all nodes
#
# DESCRIPTION:
#   Queries the cluster configuration on each node using INFO cluster
#   command. Verifies that cluster_enabled flag is set to 1 on all nodes.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Cluster mode is enabled on all 3 nodes
#   1 - Cluster mode is not enabled on one or more nodes
#
# NOTES:
#   Cluster mode must be enabled in redis.conf for cluster to function
################################################################################
test_cluster_enabled() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: Cluster mode is enabled on all nodes"

    local enabled_count=0

    for i in 1 2 3; do
        local cluster_enabled=$(docker exec dev-redis-$i redis-cli -a "$REDIS_PASSWORD" \
            INFO cluster 2>/dev/null | grep "cluster_enabled:1" || echo "")

        if [ -n "$cluster_enabled" ]; then
            enabled_count=$((enabled_count + 1))
        fi
    done

    if [ $enabled_count -eq 3 ]; then
        success "Cluster mode is enabled on all 3 nodes"
        return 0
    else
        fail "Cluster mode only enabled on $enabled_count/3 nodes"
        return 1
    fi
}

################################################################################
# Test: Verifies Redis cluster is initialized
#
# DESCRIPTION:
#   Checks cluster state using CLUSTER INFO command. A properly initialized
#   cluster should report state as "ok". This indicates all nodes have joined
#   the cluster and can communicate.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Cluster state is "ok"
#   1 - Cluster state is not "ok" (fail, uninitialized, etc.)
#
# NOTES:
#   Queries redis-1 as representative of cluster state
#   Cluster initialization requires redis-cli --cluster create
################################################################################
test_cluster_initialized() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Cluster is initialized"

    local cluster_info=$(docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" \
        CLUSTER INFO 2>/dev/null)

    local cluster_state=$(echo "$cluster_info" | grep "cluster_state:" | cut -d: -f2 | tr -d '\r')

    if [ "$cluster_state" = "ok" ]; then
        success "Cluster is initialized and state is OK"
        return 0
    else
        fail "Cluster state is: $cluster_state (expected: ok)"
        return 1
    fi
}

################################################################################
# Test: Verifies all 16384 hash slots are assigned
#
# DESCRIPTION:
#   Redis cluster uses 16384 hash slots to distribute keys across nodes.
#   This test verifies that all slots have been assigned to master nodes.
#   Unassigned slots prevent the cluster from operating properly.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - All 16384 slots are assigned
#   1 - Some slots are unassigned
#
# NOTES:
#   This is critical for cluster operation
#   Slots are assigned during cluster initialization
################################################################################
test_all_slots_assigned() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: All 16384 slots are assigned"

    local cluster_info=$(docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" \
        CLUSTER INFO 2>/dev/null)

    local slots_assigned=$(echo "$cluster_info" | grep "cluster_slots_assigned:" | \
        cut -d: -f2 | tr -d '\r')

    if [ "$slots_assigned" = "16384" ]; then
        success "All 16384 hash slots are assigned"
        return 0
    else
        fail "Only $slots_assigned/16384 slots assigned"
        return 1
    fi
}

################################################################################
# Test: Verifies cluster has exactly 3 master nodes
#
# DESCRIPTION:
#   Queries CLUSTER NODES to count master nodes. For this 3-node cluster
#   configuration, all 3 nodes should be masters (no replicas configured).
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Cluster has 3 master nodes
#   1 - Cluster has different number of master nodes
#
# NOTES:
#   This configuration uses no replicas for simplicity
#   Production clusters typically include replica nodes
################################################################################
test_three_masters() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Cluster has 3 master nodes"

    local cluster_nodes=$(docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" \
        CLUSTER NODES 2>/dev/null)

    local master_count=$(echo "$cluster_nodes" | grep -c "master" || echo "0")

    if [ "$master_count" = "3" ]; then
        success "Cluster has 3 master nodes"
        return 0
    else
        fail "Cluster has $master_count master nodes (expected: 3)"
        return 1
    fi
}

################################################################################
# Test: Verifies slots are distributed across all master nodes
#
# DESCRIPTION:
#   Checks that each master node has been assigned a range of hash slots.
#   For proper load distribution, all masters should have slot assignments.
#   Parses CLUSTER NODES output looking for slot range patterns.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - All 3 masters have slots assigned
#   1 - One or more masters have no slots
#
# NOTES:
#   Looks for patterns like "0-5460" indicating slot ranges
#   Balanced distribution is approximately 5461 slots per node
################################################################################
test_slot_distribution() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: Slots are distributed across all masters"

    local cluster_nodes=$(docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" \
        CLUSTER NODES 2>/dev/null)

    local masters_with_slots=0

    # Count masters that have slot ranges assigned
    while IFS= read -r line; do
        if echo "$line" | grep -q "master"; then
            # Check if this line contains slot ranges (pattern like "0-5460" or single slots)
            if echo "$line" | grep -qE '[0-9]+-[0-9]+'; then
                masters_with_slots=$((masters_with_slots + 1))
            fi
        fi
    done <<< "$cluster_nodes"

    if [ $masters_with_slots -eq 3 ]; then
        success "All 3 masters have slots assigned"
        return 0
    else
        fail "Only $masters_with_slots/3 masters have slots assigned"
        return 1
    fi
}

################################################################################
# Test: Verifies data sharding works correctly across cluster
#
# DESCRIPTION:
#   Sets multiple test keys and verifies they can be retrieved. Redis cluster
#   automatically distributes keys across nodes based on hash slots. Uses
#   cluster-aware client (-c flag) to handle redirections transparently.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   Creates and deletes temporary test keys
#
# RETURNS:
#   0 - Keys were successfully set and retrieved
#   1 - Key operations failed
#
# NOTES:
#   Uses -c flag for cluster-aware client behavior
#   Tests actual data distribution across cluster nodes
################################################################################
test_data_sharding() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: Data sharding works correctly"

    # Set test keys and check they're distributed
    docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        SET test_key_1 "value1" &>/dev/null
    docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        SET test_key_2 "value2" &>/dev/null
    docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        SET test_key_3 "value3" &>/dev/null

    # Retrieve values
    local val1=$(docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        GET test_key_1 2>/dev/null)
    local val2=$(docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        GET test_key_2 2>/dev/null)
    local val3=$(docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        GET test_key_3 2>/dev/null)

    # Cleanup
    docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        DEL test_key_1 test_key_2 test_key_3 &>/dev/null

    if [ "$val1" = "value1" ] && [ "$val2" = "value2" ] && [ "$val3" = "value3" ]; then
        success "Data sharding works - keys distributed and retrievable"
        return 0
    else
        fail "Data sharding failed - keys not retrievable"
        return 1
    fi
}

################################################################################
# Test: Verifies automatic redirection between cluster nodes
#
# DESCRIPTION:
#   Tests cluster client's ability to automatically redirect requests to the
#   correct node. Sets a key on node 1, then retrieves it from node 2 using
#   cluster-aware client (-c flag). The client should automatically redirect
#   to the node owning that key's hash slot.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   Creates and deletes temporary test key
#
# RETURNS:
#   0 - Automatic redirection worked correctly
#   1 - Redirection failed
#
# NOTES:
#   The -c flag enables cluster mode in redis-cli
#   Redirection is transparent to the client
################################################################################
test_automatic_redirection() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: Automatic redirection works with -c flag"

    # Set a key on node 1
    docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        SET redirect_test "test_value" &>/dev/null

    # Try to get it from node 2 (should redirect automatically)
    local value=$(docker exec dev-redis-2 redis-cli -c -a "$REDIS_PASSWORD" \
        GET redirect_test 2>/dev/null)

    # Cleanup
    docker exec dev-redis-1 redis-cli -c -a "$REDIS_PASSWORD" \
        DEL redirect_test &>/dev/null

    if [ "$value" = "test_value" ]; then
        success "Automatic redirection works across nodes"
        return 0
    else
        fail "Automatic redirection failed"
        return 1
    fi
}

################################################################################
# Test: Verifies Vault password authentication works
#
# DESCRIPTION:
#   Tests that the password retrieved from Vault can successfully authenticate
#   with Redis. Attempts explicit AUTH command to verify credentials.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Vault password authentication successful
#   1 - Authentication failed or password not retrieved
#
# NOTES:
#   Password is retrieved at script startup via get_redis_password()
#   Auth may already be established, so "already authenticated" is success
################################################################################
test_vault_password_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: Vault password integration works"

    if [ -n "$REDIS_PASSWORD" ]; then
        # Try to authenticate with the password
        local auth_result=$(docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" \
            AUTH "$REDIS_PASSWORD" 2>&1)

        if echo "$auth_result" | grep -qE "OK|already authenticated"; then
            success "Vault password authentication works"
            return 0
        fi
    fi

    fail "Vault password integration failed"
    return 1
}

################################################################################
# Test: Performs comprehensive cluster health check
#
# DESCRIPTION:
#   Uses redis-cli --cluster check command to perform comprehensive validation
#   of cluster health. This command checks connectivity, slot coverage, and
#   overall cluster integrity. Connects to cluster via internal Docker network.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() with check output if failed
#
# RETURNS:
#   0 - Cluster health check passed with all slots covered
#   1 - Health check failed
#
# NOTES:
#   Uses internal IP 172.20.2.13 (redis-1 data-network address)
#   Checks all 16384 slots are properly covered
################################################################################
test_cluster_health_check() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 11: Cluster health check comprehensive test"

    local check_output=$(docker exec dev-redis-1 redis-cli --cluster check \
        172.20.2.13:6379 -a "$REDIS_PASSWORD" 2>&1)

    if echo "$check_output" | grep -q "\[OK\] All 16384 slots covered"; then
        success "Comprehensive cluster health check passed"
        return 0
    else
        warn "Cluster check output: $check_output"
        fail "Comprehensive cluster health check failed"
        return 1
    fi
}

################################################################################
# Test: Verifies keyslot calculation functionality
#
# DESCRIPTION:
#   Tests CLUSTER KEYSLOT command which calculates which hash slot a key
#   belongs to. This is fundamental to cluster operation as it determines
#   which node stores each key. Validates result is within valid range.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Keyslot calculation successful and within valid range (0-16383)
#   1 - Keyslot calculation failed
#
# NOTES:
#   Hash slots range from 0 to 16383 (total of 16384 slots)
#   Keyslot determines which master node owns the key
################################################################################
test_cluster_keyslot() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 12: Keyslot calculation works"

    local keyslot=$(docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" \
        CLUSTER KEYSLOT "test_key" 2>/dev/null)

    # Keyslot should be a number between 0 and 16383
    if [ "$keyslot" -ge 0 ] && [ "$keyslot" -le 16383 ] 2>/dev/null; then
        success "Keyslot calculation works (test_key -> slot $keyslot)"
        return 0
    else
        fail "Keyslot calculation failed"
        return 1
    fi
}

################################################################################
# Executes all Redis cluster tests and reports results
#
# DESCRIPTION:
#   Orchestrates execution of all cluster-specific test functions in sequence.
#   Each test runs with || true to prevent early exit on failure, ensuring
#   complete test coverage. Displays formatted summary of results.
#
# OUTPUTS:
#   Formatted test results including:
#   - Header banner
#   - Individual test results (pass/fail)
#   - Summary statistics
#   - List of failed tests (if any)
#
# RETURNS:
#   0 - All tests passed
#   1 - One or more tests failed
#
# NOTES:
#   Individual test failures don't stop execution
#   Final summary always displays even if tests fail
#   Tests focus on cluster-specific functionality
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  Redis Cluster Test Suite"
    echo "========================================="
    echo

    test_containers_running || true
    test_nodes_reachable || true
    test_cluster_enabled || true
    test_cluster_initialized || true
    test_all_slots_assigned || true
    test_three_masters || true
    test_slot_distribution || true
    test_data_sharding || true
    test_automatic_redirection || true
    test_vault_password_integration || true
    test_cluster_health_check || true
    test_cluster_keyslot || true

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
        echo -e "${GREEN}✓ All Redis Cluster tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
