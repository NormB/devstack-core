#!/bin/bash

# File: tests/test-rollback-complete.sh
# Purpose: Comprehensive test of all rollback procedures
# Covers: Failed updates, corrupted configs, database issues, network problems

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# ===============================================
# Helper Functions
# ===============================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

test_start() {
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    echo ""
    echo "==============================================="
    echo "TEST $TOTAL_TESTS: $1"
    echo "==============================================="
}

test_pass() {
    PASSED_TESTS=$((PASSED_TESTS + 1))
    log_info "✓ PASSED: $1"
}

test_fail() {
    FAILED_TESTS=$((FAILED_TESTS + 1))
    log_error "✗ FAILED: $1"
}

# ===============================================
# Setup Functions
# ===============================================

setup_test_environment() {
    log_info "Setting up test environment..."

    # Ensure services are running
    if ! docker compose ps | grep "vault" | grep -q "Up"; then
        log_error "Vault is not running. Please start the environment first."
        exit 1
    fi

    # Set Vault environment
    export VAULT_ADDR="http://localhost:8200"
    if [ -f ~/.config/vault/root-token ]; then
        export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
    else
        log_error "Vault root token not found"
        exit 1
    fi

    # Create test backup directory
    TEST_BACKUP_DIR="/tmp/rollback-test-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$TEST_BACKUP_DIR"
    log_info "Test backup directory: $TEST_BACKUP_DIR"
}

cleanup_test_environment() {
    log_info "Cleaning up test environment..."
    if [ -n "$TEST_BACKUP_DIR" ] && [ -d "$TEST_BACKUP_DIR" ]; then
        rm -rf "$TEST_BACKUP_DIR"
    fi
}

# ===============================================
# Test: Container State Management
# ===============================================

test_container_rollback() {
    test_start "Container State Rollback"

    # Get current postgres image
    local original_image=$(docker inspect dev-postgres --format='{{.Config.Image}}')
    log_info "Original image: $original_image"

    # Stop container
    log_info "Stopping postgres container..."
    docker compose stop postgres
    sleep 2

    # Verify container stopped
    if docker compose ps | grep postgres | grep -q "running"; then
        test_fail "Failed to stop postgres container"
        return 1
    fi
    test_pass "Container stopped successfully"

    # Rollback by restarting
    log_info "Rolling back by restarting container..."
    docker compose up -d postgres
    sleep 5

    # Verify container is running with same image
    if ! docker compose ps | grep postgres | grep -q "running"; then
        test_fail "Container failed to restart"
        return 1
    fi

    local current_image=$(docker inspect dev-postgres --format='{{.Config.Image}}')
    if [ "$original_image" != "$current_image" ]; then
        test_fail "Image mismatch after rollback"
        return 1
    fi

    test_pass "Container rolled back successfully"
}

# ===============================================
# Test: Configuration Rollback
# ===============================================

test_config_rollback() {
    test_start "Configuration File Rollback"

    local config_file="configs/postgres/postgresql.conf"

    # Backup original config
    cp "$config_file" "$TEST_BACKUP_DIR/postgresql.conf.backup"
    local original_hash=$(md5sum "$config_file" | awk '{print $1}')
    log_info "Original config hash: $original_hash"

    # Corrupt configuration
    log_info "Corrupting configuration..."
    echo "invalid_setting = corrupt_value" >> "$config_file"

    # Verify configuration changed
    local corrupted_hash=$(md5sum "$config_file" | awk '{print $1}')
    if [ "$original_hash" == "$corrupted_hash" ]; then
        test_fail "Configuration did not change"
        return 1
    fi
    test_pass "Configuration corruption simulated"

    # Rollback configuration
    log_info "Rolling back configuration..."
    cp "$TEST_BACKUP_DIR/postgresql.conf.backup" "$config_file"

    # Verify rollback
    local restored_hash=$(md5sum "$config_file" | awk '{print $1}')
    if [ "$original_hash" != "$restored_hash" ]; then
        test_fail "Configuration rollback failed"
        return 1
    fi
    test_pass "Configuration rolled back successfully"

    # Restart service to apply config
    docker compose restart postgres
    sleep 5

    if ! docker compose ps | grep postgres | grep -q "running"; then
        test_fail "Service failed to restart after config rollback"
        return 1
    fi
    test_pass "Service restarted successfully with rolled back config"
}

# ===============================================
# Test: Volume Rollback
# ===============================================

test_volume_rollback() {
    test_start "Volume Data Rollback"

    # Create test data in postgres
    log_info "Creating test data..."
    docker exec dev-postgres psql -U postgres -c "CREATE DATABASE rollback_test;" || true
    docker exec dev-postgres psql -U postgres -d rollback_test -c "CREATE TABLE test_data (id SERIAL PRIMARY KEY, value TEXT);"
    docker exec dev-postgres psql -U postgres -d rollback_test -c "INSERT INTO test_data (value) VALUES ('before rollback');"

    # Verify data exists
    local before_count=$(docker exec dev-postgres psql -U postgres -d rollback_test -t -c "SELECT COUNT(*) FROM test_data;" | xargs)
    if [ "$before_count" != "1" ]; then
        test_fail "Failed to create test data"
        return 1
    fi
    test_pass "Test data created successfully"

    # Backup volume (simulate snapshot)
    log_info "Creating volume backup..."
    docker exec dev-postgres pg_dump -U postgres rollback_test > "$TEST_BACKUP_DIR/rollback_test.sql"

    # Modify data (simulate corruption)
    log_info "Simulating data corruption..."
    docker exec dev-postgres psql -U postgres -d rollback_test -c "DELETE FROM test_data;"

    # Verify data deleted
    local after_count=$(docker exec dev-postgres psql -U postgres -d rollback_test -t -c "SELECT COUNT(*) FROM test_data;" | xargs)
    if [ "$after_count" != "0" ]; then
        test_fail "Data deletion failed"
        return 1
    fi
    test_pass "Data corruption simulated"

    # Rollback volume data
    log_info "Rolling back volume data..."
    docker exec -i dev-postgres psql -U postgres -d rollback_test < "$TEST_BACKUP_DIR/rollback_test.sql"

    # Verify rollback
    local restored_count=$(docker exec dev-postgres psql -U postgres -d rollback_test -t -c "SELECT COUNT(*) FROM test_data;" | xargs)
    if [ "$restored_count" != "1" ]; then
        test_fail "Volume rollback failed (expected 1 row, got $restored_count)"
        return 1
    fi

    local restored_value=$(docker exec dev-postgres psql -U postgres -d rollback_test -t -c "SELECT value FROM test_data LIMIT 1;" | xargs)
    if [ "$restored_value" != "before rollback" ]; then
        test_fail "Volume rollback data mismatch"
        return 1
    fi
    test_pass "Volume data rolled back successfully"

    # Cleanup test database
    docker exec dev-postgres psql -U postgres -c "DROP DATABASE rollback_test;" || true
}

# ===============================================
# Test: Network Rollback
# ===============================================

test_network_rollback() {
    test_start "Network Configuration Rollback"

    # Get current network configuration
    local network_name="devstack_data-network"
    local original_subnet=$(docker network inspect $network_name --format='{{range .IPAM.Config}}{{.Subnet}}{{end}}')
    log_info "Original subnet: $original_subnet"

    # Verify network exists
    if ! docker network inspect $network_name >/dev/null 2>&1; then
        test_fail "Network $network_name does not exist"
        return 1
    fi
    test_pass "Network exists and is accessible"

    # Test container network connectivity
    log_info "Testing network connectivity..."
    if ! docker exec dev-reference-api ping -c 1 postgres >/dev/null 2>&1; then
        test_fail "Network connectivity test failed (before rollback)"
        return 1
    fi
    test_pass "Network connectivity verified"

    # Simulate network issue by disconnecting/reconnecting
    log_info "Simulating network disruption..."
    docker network disconnect $network_name dev-reference-api 2>/dev/null || true
    sleep 2

    # Verify disconnection
    if docker exec dev-reference-api ping -c 1 postgres >/dev/null 2>&1; then
        log_warning "Container still has connectivity (expected during test)"
    fi

    # Rollback network by reconnecting
    log_info "Rolling back network connection..."
    docker network connect $network_name dev-reference-api --ip 172.20.2.100 2>/dev/null || true
    sleep 2

    # Verify rollback
    if ! docker exec dev-reference-api ping -c 1 postgres >/dev/null 2>&1; then
        test_fail "Network rollback failed - no connectivity"
        return 1
    fi
    test_pass "Network rolled back successfully"
}

# ===============================================
# Test: Vault Secret Rollback
# ===============================================

test_vault_secret_rollback() {
    test_start "Vault Secret Rollback"

    # Create test secret
    log_info "Creating test secret..."
    vault kv put secret/rollback_test password="original_password" > /dev/null

    # Verify secret created
    local original_password=$(vault kv get -field=password secret/rollback_test)
    if [ "$original_password" != "original_password" ]; then
        test_fail "Failed to create test secret"
        return 1
    fi
    test_pass "Test secret created"

    # Backup secret (get version)
    local original_version=$(vault kv metadata get secret/rollback_test | grep "Current Version:" | awk '{print $3}')
    log_info "Original version: $original_version"

    # Update secret (simulate change)
    log_info "Updating secret..."
    vault kv put secret/rollback_test password="corrupted_password" > /dev/null

    # Verify update
    local corrupted_password=$(vault kv get -field=password secret/rollback_test)
    if [ "$corrupted_password" != "corrupted_password" ]; then
        test_fail "Secret update failed"
        return 1
    fi
    test_pass "Secret updated successfully"

    # Rollback secret to previous version
    log_info "Rolling back secret..."
    vault kv rollback -version=$original_version secret/rollback_test > /dev/null

    # Verify rollback
    local restored_password=$(vault kv get -field=password secret/rollback_test)
    if [ "$restored_password" != "original_password" ]; then
        test_fail "Vault secret rollback failed"
        return 1
    fi
    test_pass "Vault secret rolled back successfully"

    # Cleanup test secret
    vault kv delete secret/rollback_test > /dev/null
    vault kv metadata delete secret/rollback_test > /dev/null
}

# ===============================================
# Test: Service Health Rollback
# ===============================================

test_service_health_rollback() {
    test_start "Service Health Rollback"

    local service="redis-1"

    # Verify service is healthy
    log_info "Checking initial service health..."
    if ! docker compose ps | grep $service | grep -q "healthy"; then
        log_warning "Service $service is not initially healthy, starting it..."
        docker compose up -d $service
        sleep 10
    fi

    if ! docker compose ps | grep $service | grep -q "healthy"; then
        test_fail "Service $service is not healthy before test"
        return 1
    fi
    test_pass "Service initially healthy"

    # Simulate failure by stopping service
    log_info "Simulating service failure..."
    docker compose stop $service
    sleep 2

    # Verify service stopped
    if docker compose ps | grep $service | grep -q "running"; then
        test_fail "Service failed to stop"
        return 1
    fi
    test_pass "Service failure simulated"

    # Rollback by restarting service
    log_info "Rolling back service health..."
    docker compose up -d $service
    sleep 10

    # Verify service healthy again
    if ! docker compose ps | grep $service | grep -q "healthy"; then
        test_fail "Service health rollback failed"
        return 1
    fi
    test_pass "Service health rolled back successfully"
}

# ===============================================
# Test: Full Environment Rollback
# ===============================================

test_full_environment_rollback() {
    test_start "Full Environment Rollback"

    log_info "Creating environment snapshot..."

    # Get current state
    local services=$(docker compose ps --services)
    local running_count=$(docker compose ps | grep -c "running" || echo "0")
    log_info "Currently running services: $running_count"

    # Create full backup
    log_info "Creating full backup..."
    mkdir -p "$TEST_BACKUP_DIR/full_backup"

    # Backup Vault data
    vault kv list secret/ > "$TEST_BACKUP_DIR/full_backup/vault_secrets.txt" 2>/dev/null || true

    # Backup database data
    docker exec dev-postgres pg_dumpall -U postgres > "$TEST_BACKUP_DIR/full_backup/postgres_all.sql" 2>/dev/null || true

    test_pass "Environment snapshot created"

    # Simulate catastrophic failure
    log_info "Simulating catastrophic failure..."
    docker compose stop
    sleep 5

    # Verify all services stopped
    local stopped_count=$(docker compose ps | grep -c "running" || echo "0")
    if [ "$stopped_count" != "0" ]; then
        test_fail "Not all services stopped"
        return 1
    fi
    test_pass "All services stopped"

    # Rollback full environment
    log_info "Rolling back full environment..."
    docker compose up -d

    # Wait for services to be ready (increased timeout)
    log_info "Waiting for services to become healthy..."
    local timeout=120
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local healthy_count=$(docker compose ps | grep -c "healthy" || echo "0")
        if [ $healthy_count -ge 3 ]; then  # At least core services healthy
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        log_info "Waiting for services... ($elapsed/$timeout seconds)"
    done

    # Verify critical services are running
    local final_running=$(docker compose ps | grep -c "running" || echo "0")
    if [ $final_running -lt 3 ]; then  # At least vault, postgres, redis-1
        test_fail "Environment rollback incomplete (only $final_running services running)"
        return 1
    fi
    test_pass "Environment rolled back successfully ($final_running services running)"
}

# ===============================================
# Test: Partial Rollback (Selective Services)
# ===============================================

test_partial_rollback() {
    test_start "Partial Service Rollback"

    local test_services=("redis-1" "postgres")

    # Record initial state
    log_info "Recording initial state..."
    declare -A initial_state
    for service in "${test_services[@]}"; do
        initial_state[$service]=$(docker compose ps $service --format json | jq -r '.[0].State' 2>/dev/null || echo "unknown")
        log_info "$service initial state: ${initial_state[$service]}"
    done

    # Stop specific services
    log_info "Stopping test services..."
    for service in "${test_services[@]}"; do
        docker compose stop $service
    done
    sleep 2

    # Verify services stopped
    for service in "${test_services[@]}"; do
        if docker compose ps $service | grep -q "running"; then
            test_fail "Service $service failed to stop"
            return 1
        fi
    done
    test_pass "Selected services stopped"

    # Rollback specific services
    log_info "Rolling back specific services..."
    for service in "${test_services[@]}"; do
        docker compose up -d $service
    done
    sleep 10

    # Verify rollback
    for service in "${test_services[@]}"; do
        if ! docker compose ps $service | grep -q "running"; then
            test_fail "Service $service rollback failed"
            return 1
        fi
    done
    test_pass "Partial rollback completed successfully"
}

# ===============================================
# Main Test Execution
# ===============================================

main() {
    echo "=================================================="
    echo "DevStack Core - Comprehensive Rollback Test Suite"
    echo "=================================================="
    echo ""

    setup_test_environment

    # Run all tests
    test_container_rollback
    test_config_rollback
    test_volume_rollback
    test_network_rollback
    test_vault_secret_rollback
    test_service_health_rollback
    test_partial_rollback
    test_full_environment_rollback

    # Cleanup
    cleanup_test_environment

    # Print summary
    echo ""
    echo "=================================================="
    echo "TEST SUMMARY"
    echo "=================================================="
    echo "Total Tests:  $TOTAL_TESTS"
    echo "Passed:       $PASSED_TESTS"
    echo "Failed:       $FAILED_TESTS"
    echo "=================================================="

    if [ $FAILED_TESTS -eq 0 ]; then
        log_info "All rollback tests passed! ✓"
        exit 0
    else
        log_error "Some rollback tests failed!"
        exit 1
    fi
}

# Run main function
main "$@"
