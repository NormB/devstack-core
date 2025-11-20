#!/bin/bash
################################################################################
# FastAPI Reference Application Test Suite
#
# DESCRIPTION:
#   Comprehensive test suite for validating the FastAPI reference application.
#   Tests HTTP/HTTPS endpoints, health checks, Redis cluster API integration,
#   database connectivity, RabbitMQ integration, and Vault integration. This
#   application serves as a reference implementation demonstrating service
#   integration patterns.
#
# GLOBALS:
#   SCRIPT_DIR         - Directory containing this script
#   PROJECT_ROOT       - Root directory of the project
#   HTTP_URL           - Base HTTP URL for API (http://localhost:8000)
#   HTTPS_URL          - Base HTTPS URL for API (https://localhost:8443)
#   RED, GREEN, YELLOW, BLUE, NC - Color codes for terminal output
#   TESTS_RUN          - Counter for total tests executed
#   TESTS_PASSED       - Counter for passed tests
#   TESTS_FAILED       - Counter for failed tests
#   FAILED_TESTS       - Array of failed test descriptions
#
# USAGE:
#   ./test-fastapi.sh
#
# DEPENDENCIES:
#   - Docker and Docker Compose for container management
#   - curl for HTTP/HTTPS API requests
#   - jq for JSON parsing and validation
#   - Vault server running on localhost:8200 with root token
#   - FastAPI container (dev-reference-api) running
#   - All backend services running (Redis, PostgreSQL, MySQL, MongoDB, RabbitMQ)
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# NOTES:
#   - Tests use curl to make actual HTTP/HTTPS requests to the API
#   - All responses are validated as proper JSON using jq
#   - HTTPS tests skip if TLS is not enabled in Vault
#   - Tests verify integration with all backend services
#   - Redis cluster tests validate 3-node cluster configuration
#   - Health checks confirm all database connections are operational
#   - Tests continue execution even if individual tests fail (|| true)
#   - Color output can be disabled by redirecting to file or pipe
#
# EXAMPLES:
#   # Run all FastAPI tests
#   ./test-fastapi.sh
#
#   # Run tests and save output to file
#   ./test-fastapi.sh > fastapi-test-results.txt 2>&1
#
#   # Test only HTTP endpoints (skip if HTTPS not configured)
#   ./test-fastapi.sh
#
# AUTHOR:
#   DevStack Core Project
#
# SEE ALSO:
#   - ../reference-api/app/ - FastAPI application source code
#   - test-redis.sh - Redis integration tests
#   - test-rabbitmq.sh - RabbitMQ integration tests
#   - test-postgres.sh - PostgreSQL integration tests
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

# Configuration
HTTP_URL="http://localhost:8000"
HTTPS_URL="https://localhost:8443"

################################################################################
# Test: Verifies FastAPI container is running
#
# DESCRIPTION:
#   Checks Docker to ensure the FastAPI reference application container
#   (dev-reference-api) is in running state.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - FastAPI container is running
#   1 - Container is not running
################################################################################
test_container_running() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: FastAPI container is running"

    if docker ps | grep -q dev-reference-api; then
        success "FastAPI container is running"
        return 0
    else
        fail "FastAPI container is not running"
        return 1
    fi
}

################################################################################
# Test: Verifies HTTP endpoint is accessible
#
# DESCRIPTION:
#   Makes HTTP GET request to root endpoint and validates JSON response.
#   Tests basic API accessibility on standard HTTP port (8000).
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - HTTP endpoint accessible and returns valid JSON
#   1 - HTTP endpoint not accessible or invalid response
#
# NOTES:
#   Uses jq to validate JSON structure
#   Looks for 'name' field in root endpoint response
################################################################################
test_http_endpoint() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: HTTP endpoint is accessible"

    local response=$(curl -sf "$HTTP_URL/" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ] && echo "$response" | jq -e '.name' &>/dev/null; then
        success "HTTP endpoint is accessible"
        return 0
    else
        fail "HTTP endpoint not accessible"
        return 1
    fi
}

################################################################################
# Retrieves TLS enabled status from Vault for a service
#
# DESCRIPTION:
#   Queries Vault secret store to determine if TLS is enabled for the
#   specified service. Uses root token from local config file.
#
# ARGUMENTS:
#   $1 - Service name (e.g., "reference-api", "rabbitmq", "postgres")
#
# OUTPUTS:
#   Prints "true" if TLS is enabled, "false" otherwise
#
# RETURNS:
#   0 - Successfully retrieved TLS status
#   1 - Failed to retrieve status (no token or connection error)
#
# EXAMPLE:
#   tls_status=$(get_tls_status_from_vault "reference-api")
################################################################################
get_tls_status_from_vault() {
    local service_name="$1"
    local vault_addr="http://localhost:8200"
    local vault_token=$(cat ~/.config/vault/root-token 2>/dev/null)

    if [ -z "$vault_token" ]; then
        echo "false"
        return 1
    fi

    local response=$(curl --max-time 5 -sf -H "X-Vault-Token: $vault_token" "$vault_addr/v1/secret/data/$service_name" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$response" | grep -o '"tls_enabled":"[^"]*"' | cut -d'"' -f4 | tr -d ' "'
    else
        echo "false"
    fi
}

################################################################################
# Test: Verifies HTTPS endpoint is accessible
#
# DESCRIPTION:
#   Makes HTTPS GET request to root endpoint and validates JSON response.
#   Only runs if TLS is enabled in Vault. Uses -k flag to skip certificate
#   verification for self-signed certificates.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() if TLS is disabled
#
# RETURNS:
#   0 - HTTPS endpoint accessible or test skipped (TLS disabled)
#   1 - HTTPS endpoint not accessible
#
# NOTES:
#   Conditionally runs based on Vault TLS configuration
#   Uses port 8443 for HTTPS
################################################################################
test_https_endpoint() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: HTTPS endpoint is accessible (when TLS enabled)"

    # Check if TLS is enabled from Vault
    local tls_enabled=$(get_tls_status_from_vault "reference-api")

    if [ "$tls_enabled" != "true" ]; then
        warn "TLS not enabled in Vault - skipping HTTPS test"
        success "HTTPS test skipped (TLS not enabled)"
        return 0
    fi

    local response=$(curl -sfk "$HTTPS_URL/" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ] && echo "$response" | jq -e '.name' &>/dev/null; then
        success "HTTPS endpoint is accessible"
        return 0
    else
        fail "HTTPS endpoint not accessible"
        return 1
    fi
}

################################################################################
# Test: Verifies aggregate health check endpoint
#
# DESCRIPTION:
#   Tests /health/all endpoint which aggregates health status of all backend
#   services. Accepts both "healthy" (all services up) and "degraded" (some
#   services down) as passing states.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Health endpoint returns healthy or degraded status
#   1 - Health endpoint failed or returned unexpected status
#
# NOTES:
#   Tests overall system health aggregation
#   Reports actual status in success message
################################################################################
test_health_all() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Health check endpoint (/health/all)"

    local response=$(curl -sf "$HTTP_URL/health/all" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ]; then
        local overall_status=$(echo "$response" | jq -r '.status // empty')

        if [ "$overall_status" = "healthy" ] || [ "$overall_status" = "degraded" ]; then
            success "Health check endpoint works (status: $overall_status)"
            return 0
        fi
    fi

    fail "Health check endpoint failed"
    return 1
}

################################################################################
# Test: Verifies Redis health check with cluster details
#
# DESCRIPTION:
#   Tests /health/redis endpoint which returns Redis cluster status including
#   cluster enabled flag, cluster state, and node count. Validates 3-node
#   cluster configuration with "ok" state.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() with cluster state details
#
# RETURNS:
#   0 - Redis health shows cluster enabled with 3 nodes in ok state
#   1 - Redis health check failed or cluster misconfigured
#
# NOTES:
#   Validates cluster mode is enabled
#   Checks for exactly 3 nodes
#   Verifies cluster state is "ok"
################################################################################
test_health_redis() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: Redis health check with cluster details"

    local response=$(curl -sf "$HTTP_URL/health/redis" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ]; then
        local cluster_enabled=$(echo "$response" | jq -r '.cluster_enabled')
        local cluster_state=$(echo "$response" | jq -r '.cluster_state')
        local total_nodes=$(echo "$response" | jq -r '.total_nodes')

        if [ "$cluster_enabled" = "true" ] && [ "$cluster_state" = "ok" ] && [ "$total_nodes" = "3" ]; then
            success "Redis health shows cluster enabled with 3 nodes in ok state"
            return 0
        else
            warn "Redis cluster state: enabled=$cluster_enabled, state=$cluster_state, nodes=$total_nodes"
            fail "Redis cluster not properly configured"
            return 1
        fi
    fi

    fail "Redis health check failed"
    return 1
}

################################################################################
# Test: Verifies Redis cluster nodes API endpoint
#
# DESCRIPTION:
#   Tests /redis/cluster/nodes endpoint which returns detailed information
#   about each cluster node including slot assignments. Validates all 3 nodes
#   are present and have slots assigned.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - API returns 3 nodes all with slot assignments
#   1 - API failed or nodes missing/misconfigured
#
# NOTES:
#   Validates JSON structure with jq
#   Checks both total_nodes count and actual nodes array length
#   Verifies each node has slots_count > 0
################################################################################
test_redis_cluster_nodes() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Redis cluster nodes API endpoint"

    local response=$(curl -sf "$HTTP_URL/redis/cluster/nodes" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ]; then
        local api_status=$(echo "$response" | jq -r '.status')
        local total_nodes=$(echo "$response" | jq -r '.total_nodes')
        local nodes_count=$(echo "$response" | jq '.nodes | length')

        if [ "$api_status" = "success" ] && [ "$total_nodes" = "3" ] && [ "$nodes_count" = "3" ]; then
            # Check that all nodes have slots assigned
            local nodes_with_slots=$(echo "$response" | jq '[.nodes[] | select(.slots_count > 0)] | length')

            if [ "$nodes_with_slots" = "3" ]; then
                success "Redis cluster nodes API returns 3 nodes with slot assignments"
                return 0
            fi
        fi
    fi

    fail "Redis cluster nodes API failed"
    return 1
}

################################################################################
# Test: Verifies Redis cluster slots API endpoint
#
# DESCRIPTION:
#   Tests /redis/cluster/slots endpoint which returns slot distribution
#   information. Validates all 16384 hash slots are assigned (100% coverage).
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() with coverage details
#
# RETURNS:
#   0 - API shows 16384 slots with 100% coverage
#   1 - API failed or slots incomplete
#
# NOTES:
#   Redis cluster uses 16384 hash slots total
#   Coverage must be exactly 100 or 100.0
#   Warns with actual coverage if incomplete
################################################################################
test_redis_cluster_slots() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: Redis cluster slots API endpoint"

    local response=$(curl -sf "$HTTP_URL/redis/cluster/slots" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ]; then
        local api_status=$(echo "$response" | jq -r '.status')
        local total_slots=$(echo "$response" | jq -r '.total_slots')
        local coverage=$(echo "$response" | jq -r '.coverage_percentage')

        # Coverage can be 100 or 100.0
        if [ "$api_status" = "success" ] && [ "$total_slots" = "16384" ] && \
           ([ "$coverage" = "100" ] || [ "$coverage" = "100.0" ]); then
            success "Redis cluster slots API shows 100% coverage (16384 slots)"
            return 0
        else
            warn "Slot coverage: $total_slots/$coverage%"
            fail "Redis cluster slots incomplete"
            return 1
        fi
    fi

    fail "Redis cluster slots API failed"
    return 1
}

################################################################################
# Test: Verifies Redis cluster info API endpoint
#
# DESCRIPTION:
#   Tests /redis/cluster/info endpoint which returns cluster information
#   including state and slot assignments. Validates cluster state is "ok"
#   and all 16384 slots are assigned.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() with state details
#
# RETURNS:
#   0 - Cluster info shows healthy state with all slots
#   1 - API failed or cluster unhealthy
#
# NOTES:
#   Tests cluster INFO command results via API
#   Validates critical cluster metrics
################################################################################
test_redis_cluster_info() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: Redis cluster info API endpoint"

    local response=$(curl -sf "$HTTP_URL/redis/cluster/info" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ]; then
        local api_status=$(echo "$response" | jq -r '.status')
        local cluster_state=$(echo "$response" | jq -r '.cluster_info.cluster_state')
        local slots_assigned=$(echo "$response" | jq -r '.cluster_info.cluster_slots_assigned')

        if [ "$api_status" = "success" ] && [ "$cluster_state" = "ok" ] && [ "$slots_assigned" = "16384" ]; then
            success "Redis cluster info shows healthy state with all slots assigned"
            return 0
        else
            warn "Cluster state: $cluster_state, slots: $slots_assigned"
            fail "Redis cluster info shows unhealthy state"
            return 1
        fi
    fi

    fail "Redis cluster info API failed"
    return 1
}

################################################################################
# Test: Verifies per-node Redis info API endpoint
#
# DESCRIPTION:
#   Tests /redis/nodes/{node}/info endpoint which returns detailed Redis INFO
#   command results for a specific node. Tests redis-1 and validates version,
#   cluster configuration, and node identity.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Node info API returns valid detailed information
#   1 - API failed or returned invalid data
#
# NOTES:
#   Tests node-specific API endpoint
#   Validates cluster_enabled flag is set
#   Confirms redis_version is present
################################################################################
test_redis_node_info() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: Redis per-node info API endpoint"

    local response=$(curl -sf "$HTTP_URL/redis/nodes/redis-1/info" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ]; then
        local api_status=$(echo "$response" | jq -r '.status')
        local node=$(echo "$response" | jq -r '.node')
        local redis_version=$(echo "$response" | jq -r '.info.redis_version // empty')
        local cluster_enabled=$(echo "$response" | jq -r '.info.cluster_enabled')

        if [ "$api_status" = "success" ] && [ "$node" = "redis-1" ] && [ -n "$redis_version" ] && [ "$cluster_enabled" = "1" ]; then
            success "Redis node info API returns detailed information for redis-1"
            return 0
        fi
    fi

    fail "Redis node info API failed"
    return 1
}

################################################################################
# Test: Verifies API documentation is accessible
#
# DESCRIPTION:
#   Tests /docs endpoint which serves Swagger UI for interactive API
#   documentation. Validates the documentation page loads correctly.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - API documentation page accessible
#   1 - Documentation not accessible
#
# NOTES:
#   FastAPI automatically generates Swagger UI
#   Checks for "Swagger UI" text in response
################################################################################
test_api_docs() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: API documentation is accessible"

    local response=$(curl -sf "$HTTP_URL/docs" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ] && echo "$response" | grep -q "Swagger UI"; then
        success "API documentation is accessible at /docs"
        return 0
    else
        fail "API documentation not accessible"
        return 1
    fi
}

################################################################################
# Test: Verifies OpenAPI schema is valid
#
# DESCRIPTION:
#   Tests /openapi.json endpoint which returns the OpenAPI specification
#   for the API. Validates JSON structure and checks API title matches
#   expected value.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - OpenAPI schema is valid with correct title
#   1 - Schema invalid or title mismatch
#
# NOTES:
#   OpenAPI schema enables code generation and validation
#   FastAPI automatically generates this from route definitions
################################################################################
test_openapi_schema() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 11: OpenAPI schema is valid"

    local response=$(curl -sf "$HTTP_URL/openapi.json" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ] && echo "$response" | jq -e '.openapi' &>/dev/null; then
        local title=$(echo "$response" | jq -r '.info.title')

        if [ "$title" = "DevStack Core - Reference API" ]; then
            success "OpenAPI schema is valid and accessible"
            return 0
        fi
    fi

    fail "OpenAPI schema failed validation"
    return 1
}

################################################################################
# Test: Verifies Vault integration works
#
# DESCRIPTION:
#   Tests /health/vault endpoint which checks Vault connectivity and
#   authentication status. Validates the API can communicate with Vault.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - Vault integration is healthy
#   1 - Vault integration failed
#
# NOTES:
#   Vault is used for secret management
#   Critical for retrieving database passwords
################################################################################
test_vault_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 12: Vault integration works"

    local response=$(curl -sf "$HTTP_URL/health/vault" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ]; then
        local vault_status=$(echo "$response" | jq -r '.status // empty')

        if [ "$vault_status" = "healthy" ]; then
            success "Vault integration is working"
            return 0
        fi
    fi

    fail "Vault integration failed"
    return 1
}

################################################################################
# Test: Verifies database connectivity for all databases
#
# DESCRIPTION:
#   Tests health endpoints for PostgreSQL, MySQL, and MongoDB. Validates
#   all three databases are accessible and healthy. Makes parallel requests
#   to individual health endpoints.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#   May call warn() with individual database statuses
#
# RETURNS:
#   0 - All three databases are healthy
#   1 - One or more databases are unhealthy
#
# NOTES:
#   Tests integration with all relational and NoSQL databases
#   Each database has separate health endpoint
################################################################################
test_database_connectivity() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 13: Database connectivity (all databases)"

    local postgres=$(curl -sf "$HTTP_URL/health/postgres" 2>/dev/null | jq -r '.status')
    local mysql=$(curl -sf "$HTTP_URL/health/mysql" 2>/dev/null | jq -r '.status')
    local mongodb=$(curl -sf "$HTTP_URL/health/mongodb" 2>/dev/null | jq -r '.status')

    if [ "$postgres" = "healthy" ] && [ "$mysql" = "healthy" ] && [ "$mongodb" = "healthy" ]; then
        success "All database connections are healthy"
        return 0
    else
        warn "Database status: postgres=$postgres, mysql=$mysql, mongodb=$mongodb"
        fail "Some databases are unhealthy"
        return 1
    fi
}

################################################################################
# Test: Verifies RabbitMQ integration
#
# DESCRIPTION:
#   Tests /health/rabbitmq endpoint which checks RabbitMQ connectivity and
#   broker status. Validates the API can communicate with message queue.
#
# SIDE EFFECTS:
#   Increments TESTS_RUN counter
#   Calls success() or fail() to update test results
#
# RETURNS:
#   0 - RabbitMQ integration is healthy
#   1 - RabbitMQ integration failed
#
# NOTES:
#   RabbitMQ is used for message queuing
#   Tests AMQP protocol connectivity
################################################################################
test_rabbitmq_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 14: RabbitMQ integration"

    local response=$(curl -sf "$HTTP_URL/health/rabbitmq" 2>/dev/null)
    local status=$?

    if [ $status -eq 0 ]; then
        local rabbitmq_status=$(echo "$response" | jq -r '.status')

        if [ "$rabbitmq_status" = "healthy" ]; then
            success "RabbitMQ integration is working"
            return 0
        fi
    fi

    fail "RabbitMQ integration failed"
    return 1
}

################################################################################
# Executes all FastAPI tests and reports results
#
# DESCRIPTION:
#   Orchestrates execution of all test functions in sequence. Each test
#   runs with || true to prevent early exit on failure, ensuring complete
#   test coverage. Displays formatted summary of results. Tests cover
#   HTTP/HTTPS endpoints, health checks, Redis cluster integration,
#   documentation, and all backend service integrations.
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
#   Tests validate complete service integration stack
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  FastAPI Reference App Test Suite"
    echo "========================================="
    echo

    test_container_running || true
    test_http_endpoint || true
    test_https_endpoint || true
    test_health_all || true
    test_health_redis || true
    test_redis_cluster_nodes || true
    test_redis_cluster_slots || true
    test_redis_cluster_info || true
    test_redis_node_info || true
    test_api_docs || true
    test_openapi_schema || true
    test_vault_integration || true
    test_database_connectivity || true
    test_rabbitmq_integration || true

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
        echo -e "${GREEN}✓ All FastAPI tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
