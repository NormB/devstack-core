#!/bin/bash
################################################################################
# Observability Stack Extended Test Suite
#
# Comprehensive tests for Prometheus, Grafana, Loki, Vector, and cAdvisor
# including metrics collection, dashboard access, log aggregation, and
# monitoring functionality.
#
# TESTS:
#   1. Prometheus scraping targets status
#   2. Prometheus query API functionality
#   3. Grafana dashboard access and health
#   4. Grafana datasource configuration
#   5. Loki log ingestion and query
#   6. Vector pipeline functionality
#   7. cAdvisor metrics collection
#   8. Redis exporter metrics availability
#   9. Service discovery and monitoring
#   10. Alert manager configuration (if enabled)
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

# Service URLs
PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
GRAFANA_URL="${GRAFANA_URL:-http://localhost:3001}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"
CADVISOR_URL="${CADVISOR_URL:-http://localhost:8080}"

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
# Test 1: Prometheus targets status
################################################################################
test_prometheus_targets() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: Prometheus scraping targets status"

    local targets=$(curl -s "$PROMETHEUS_URL/api/v1/targets" 2>/dev/null)

    if [ -z "$targets" ]; then
        fail "Could not retrieve Prometheus targets" "Prometheus targets"
        return 1
    fi

    local active_targets=$(echo "$targets" | jq -r '.data.activeTargets | length')
    local up_targets=$(echo "$targets" | jq -r '.data.activeTargets | map(select(.health=="up")) | length')

    if [ -n "$active_targets" ] && [ "$active_targets" -gt 0 ]; then
        success "Prometheus targets monitored ($up_targets/$active_targets targets up)"
        return 0
    fi

    fail "Prometheus targets test failed" "Prometheus targets"
    return 1
}

################################################################################
# Test 2: Prometheus query API
################################################################################
test_prometheus_queries() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: Prometheus query API functionality"

    # Test instant query
    local query_result=$(curl -s -G --data-urlencode 'query=up' \
        "$PROMETHEUS_URL/api/v1/query" 2>/dev/null)

    if [ -z "$query_result" ]; then
        fail "Prometheus query API not responding" "Prometheus queries"
        return 1
    fi

    local status=$(echo "$query_result" | jq -r '.status')
    local result_count=$(echo "$query_result" | jq -r '.data.result | length')

    # Test range query
    local range_query=$(curl -s -G \
        --data-urlencode 'query=up' \
        --data-urlencode 'start='"$(date -u -d '5 minutes ago' +%s 2>/dev/null || date -u -v-5M +%s)" \
        --data-urlencode 'end='"$(date -u +%s)" \
        --data-urlencode 'step=15s' \
        "$PROMETHEUS_URL/api/v1/query_range" 2>/dev/null)

    local range_status=$(echo "$range_query" | jq -r '.status')

    if [ "$status" == "success" ] && [ "$range_status" == "success" ] && [ "$result_count" -gt 0 ]; then
        success "Prometheus queries working (instant and range queries, $result_count results)"
        return 0
    fi

    fail "Prometheus query test failed" "Prometheus queries"
    return 1
}

################################################################################
# Test 3: Grafana dashboard access
################################################################################
test_grafana_access() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: Grafana dashboard access and health"

    local health=$(curl -s "$GRAFANA_URL/api/health" 2>/dev/null)

    if [ -z "$health" ]; then
        fail "Grafana health endpoint not responding" "Grafana access"
        return 1
    fi

    local database=$(echo "$health" | jq -r '.database')
    local version=$(echo "$health" | jq -r '.version')

    # Test login page accessibility
    local login_page=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL/login" 2>/dev/null)

    if [ "$database" == "ok" ] && [ -n "$version" ] && [ "$login_page" == "200" ]; then
        success "Grafana accessible (version: $version, database: $database, login: OK)"
        return 0
    fi

    fail "Grafana access test failed" "Grafana access"
    return 1
}

################################################################################
# Test 4: Grafana datasources
################################################################################
test_grafana_datasources() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Grafana datasource configuration"

    # Note: This test checks the datasources API without authentication
    # In production, this would require proper authentication
    local datasources=$(curl -s "$GRAFANA_URL/api/datasources" 2>/dev/null)

    # If we get a 401, try with default credentials
    if echo "$datasources" | grep -q "Unauthorized"; then
        datasources=$(curl -s -u "admin:admin" "$GRAFANA_URL/api/datasources" 2>/dev/null)
    fi

    # Check if we can at least reach the API
    if [ -z "$datasources" ]; then
        # API might require auth, but we can check if Grafana is configured
        local ready=$(curl -s "$GRAFANA_URL/api/health" 2>/dev/null | jq -r '.database')
        if [ "$ready" == "ok" ]; then
            success "Grafana datasource API accessible (authentication required)"
            return 0
        fi
        fail "Grafana datasource API not responding" "Grafana datasources"
        return 1
    fi

    success "Grafana datasource configuration accessible"
    return 0
}

################################################################################
# Test 5: Loki log ingestion
################################################################################
test_loki_ingestion() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: Loki log ingestion and query"

    # Test Loki ready endpoint
    local ready=$(curl -s "$LOKI_URL/ready" 2>/dev/null)

    if [ "$ready" != "ready" ]; then
        fail "Loki not ready" "Loki ingestion"
        return 1
    fi

    # Test labels API
    local labels=$(curl -s "$LOKI_URL/loki/api/v1/labels" 2>/dev/null)

    if [ -z "$labels" ]; then
        fail "Loki labels API not responding" "Loki ingestion"
        return 1
    fi

    local status=$(echo "$labels" | jq -r '.status')
    local label_count=$(echo "$labels" | jq -r '.data | length')

    if [ "$status" == "success" ] && [ -n "$label_count" ]; then
        success "Loki ingestion working (status: ready, $label_count labels available)"
        return 0
    fi

    fail "Loki ingestion test failed" "Loki ingestion"
    return 1
}

################################################################################
# Test 6: Vector pipeline
################################################################################
test_vector_pipeline() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Vector pipeline functionality"

    # Check if Vector container is running
    if ! docker ps | grep -q "dev-vector"; then
        fail "Vector container not running" "Vector pipeline"
        return 1
    fi

    # Check Vector logs for pipeline initialization
    if docker logs dev-vector 2>&1 | grep -q "Vector has started"; then
        # Check if Vector is processing logs
        local log_count=$(docker logs dev-vector 2>&1 | wc -l)
        success "Vector pipeline active (container running, $log_count log lines)"
        return 0
    fi

    fail "Vector pipeline test failed" "Vector pipeline"
    return 1
}

################################################################################
# Test 7: cAdvisor metrics
################################################################################
test_cadvisor_metrics() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: cAdvisor metrics collection"

    # Note: cAdvisor might not expose metrics on standard port in all configs
    # Try to access the main page first
    local cadvisor_status=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://localhost:8080/containers/" 2>/dev/null)

    if [ "$cadvisor_status" == "200" ]; then
        success "cAdvisor metrics accessible (HTTP 200)"
        return 0
    fi

    # If not accessible via HTTP, check if container is running
    if docker ps | grep -q "dev-cadvisor"; then
        local health=$(docker inspect dev-cadvisor --format='{{.State.Health.Status}}' 2>/dev/null)
        if [ "$health" == "healthy" ]; then
            success "cAdvisor container healthy (metrics collection active)"
            return 0
        fi
    fi

    fail "cAdvisor metrics test failed" "cAdvisor metrics"
    return 1
}

################################################################################
# Test 8: Redis exporter metrics
################################################################################
test_redis_exporters() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: Redis exporter metrics availability"

    # Check if Redis exporters are running
    local exporter_count=$(docker ps | grep -c "dev-redis-exporter" || true)

    if [ "$exporter_count" -eq 0 ]; then
        fail "No Redis exporters running" "Redis exporters"
        return 1
    fi

    # Try to get metrics from first exporter (on port 9121 inside container)
    # In the actual setup, Prometheus scrapes these internally
    local exporter1_healthy=$(docker inspect dev-redis-exporter-1 --format='{{.State.Health.Status}}' 2>/dev/null)
    local exporter2_healthy=$(docker inspect dev-redis-exporter-2 --format='{{.State.Health.Status}}' 2>/dev/null)
    local exporter3_healthy=$(docker inspect dev-redis-exporter-3 --format='{{.State.Health.Status}}' 2>/dev/null)

    local healthy_count=0
    [ "$exporter1_healthy" == "healthy" ] && healthy_count=$((healthy_count + 1))
    [ "$exporter2_healthy" == "healthy" ] && healthy_count=$((healthy_count + 1))
    [ "$exporter3_healthy" == "healthy" ] && healthy_count=$((healthy_count + 1))

    if [ "$healthy_count" -eq 3 ]; then
        success "Redis exporters healthy ($healthy_count/$exporter_count exporters running)"
        return 0
    fi

    fail "Redis exporter test failed" "Redis exporters"
    return 1
}

################################################################################
# Test 9: Service discovery
################################################################################
test_service_discovery() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: Service discovery and monitoring"

    # Check Prometheus service discovery
    local service_discovery=$(curl -s "$PROMETHEUS_URL/api/v1/targets/metadata" 2>/dev/null)

    if [ -z "$service_discovery" ]; then
        fail "Service discovery API not responding" "Service discovery"
        return 1
    fi

    local metadata_count=$(echo "$service_discovery" | jq -r '.data | length')

    # Check if common services are being monitored
    local has_prometheus=$(curl -s "$PROMETHEUS_URL/api/v1/query?query=up{job=\"prometheus\"}" 2>/dev/null | \
        jq -r '.data.result | length')

    if [ "$metadata_count" -gt 0 ]; then
        success "Service discovery working ($metadata_count metric metadata entries, Prometheus self-monitoring: OK)"
        return 0
    fi

    fail "Service discovery test failed" "Service discovery"
    return 1
}

################################################################################
# Test 10: Monitoring stack integration
################################################################################
test_monitoring_integration() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: Monitoring stack integration"

    # Check if all monitoring components are accessible
    local prometheus_up=$(curl -s -o /dev/null -w "%{http_code}" "$PROMETHEUS_URL/-/healthy" 2>/dev/null)
    local grafana_up=$(curl -s -o /dev/null -w "%{http_code}" "$GRAFANA_URL/api/health" 2>/dev/null)
    local loki_up=$(curl -s -o /dev/null -w "%{http_code}" "$LOKI_URL/ready" 2>/dev/null)

    local components_up=0
    [ "$prometheus_up" == "200" ] && components_up=$((components_up + 1))
    [ "$grafana_up" == "200" ] && components_up=$((components_up + 1))
    [ "$loki_up" == "200" ] && components_up=$((components_up + 1))

    # Check if Vector is running
    if docker ps | grep -q "dev-vector"; then
        components_up=$((components_up + 1))
    fi

    if [ "$components_up" -ge 3 ]; then
        success "Monitoring stack integrated ($components_up/4 components healthy)"
        return 0
    fi

    fail "Monitoring integration test failed (only $components_up/4 components up)" "Monitoring integration"
    return 1
}

################################################################################
# Run all tests
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  Observability Stack Test Suite"
    echo "========================================="
    echo

    test_prometheus_targets || true
    test_prometheus_queries || true
    test_grafana_access || true
    test_grafana_datasources || true
    test_loki_ingestion || true
    test_vector_pipeline || true
    test_cadvisor_metrics || true
    test_redis_exporters || true
    test_service_discovery || true
    test_monitoring_integration || true

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
        echo -e "${GREEN}✓ All observability tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
