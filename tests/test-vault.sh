#!/bin/bash
################################################################################
# Vault Integration Test Suite
#
# Comprehensive test suite for validating HashiCorp Vault integration with the
# development services infrastructure. Tests Vault initialization, PKI setup,
# secrets management, and certificate issuance capabilities.
#
# GLOBALS:
#   SCRIPT_DIR - Directory containing this script
#   PROJECT_ROOT - Root directory of the project
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for output formatting
#   TESTS_RUN - Counter for total number of tests executed
#   TESTS_PASSED - Counter for successfully passed tests
#   TESTS_FAILED - Counter for failed tests
#   FAILED_TESTS - Array containing names of failed tests
#
# USAGE:
#   ./test-vault.sh
#
#   The script automatically runs all test functions in sequence and displays
#   a summary report at the end.
#
# DEPENDENCIES:
#   - Docker (for container inspection)
#   - curl (for Vault API calls)
#   - jq (for JSON parsing)
#   - openssl (for certificate validation)
#   - Vault container running (dev-vault)
#   - Vault keys file: ~/.config/vault/keys.json
#   - Vault token file: ~/.config/vault/root-token
#
# EXIT CODES:
#   0 - All tests passed successfully
#   1 - One or more tests failed
#
# TESTS:
#   1. Vault container is running
#   2. Vault is unsealed and operational
#   3. Vault keys and token files exist
#   4. PKI engines are enabled (Root CA, Intermediate CA)
#   5. Certificate roles exist for all services
#   6. Service credentials are stored in Vault
#   7. PostgreSQL credentials are valid
#   8. Can issue certificates for services
#   9. CA certificates are exported and valid
#   10. Management script Vault commands work
#
# NOTES:
#   - All tests continue execution even if individual tests fail
#   - Tests use 'set -e' for error handling but override with '|| true' in runner
#   - Requires Vault to be bootstrapped via vault-bootstrap command
#   - Tests verify both PKI infrastructure and secrets engine functionality
#
# EXAMPLES:
#   # Run all Vault tests
#   ./test-vault.sh
#
#   # Run tests after bootstrapping Vault
#   ../manage-devstack.sh vault-bootstrap
#   ./test-vault.sh
#
# AUTHORS:
#   Development Services Team
#
# VERSION:
#   1.0.0
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
# Prints an informational test message in blue.
#
# Globals:
#   BLUE - ANSI color code for blue text
#   NC - ANSI color code to reset color
#
# Arguments:
#   $1 - Message to display
#
# Outputs:
#   Writes formatted message to stdout
################################################################################
info() { echo -e "${BLUE}[TEST]${NC} $1"; }

################################################################################
# Prints a success message in green and increments the passed test counter.
#
# Globals:
#   GREEN - ANSI color code for green text
#   NC - ANSI color code to reset color
#   TESTS_PASSED - Counter incremented for each successful test
#
# Arguments:
#   $1 - Success message to display
#
# Outputs:
#   Writes formatted success message to stdout
################################################################################
success() { echo -e "${GREEN}[PASS]${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }

################################################################################
# Prints a failure message in red, increments failed counter, and records failure.
#
# Globals:
#   RED - ANSI color code for red text
#   NC - ANSI color code to reset color
#   TESTS_FAILED - Counter incremented for each failed test
#   FAILED_TESTS - Array to which failed test name is appended
#
# Arguments:
#   $1 - Failure message to display
#
# Outputs:
#   Writes formatted failure message to stdout
################################################################################
fail() { echo -e "${RED}[FAIL]${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); FAILED_TESTS+=("$1"); }

################################################################################
# Prints a warning message in yellow.
#
# Globals:
#   YELLOW - ANSI color code for yellow text
#   NC - ANSI color code to reset color
#
# Arguments:
#   $1 - Warning message to display
#
# Outputs:
#   Writes formatted warning message to stdout
################################################################################
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

################################################################################
# Tests if the Vault container is running.
#
# Verifies that the dev-vault Docker container is running by checking the
# output of 'docker ps'. This is the first test to ensure Vault is available
# for subsequent tests.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - Vault container is running
#   1 - Vault container is not running
#
# Outputs:
#   Test status message via info/success/fail functions
################################################################################
test_vault_running() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 1: Vault container is running"

    if docker ps | grep -q dev-vault; then
        success "Vault container is running"
        return 0
    else
        fail "Vault container is not running"
        return 1
    fi
}

################################################################################
# Tests if Vault is unsealed and ready to accept requests.
#
# Checks the Vault seal status by querying the Vault API via docker exec.
# An unsealed Vault is required for all PKI and secrets operations.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - Vault is unsealed (sealed=false)
#   1 - Vault is sealed or unreachable
#
# Outputs:
#   Test status message via info/success/fail functions
################################################################################
test_vault_unsealed() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 2: Vault is unsealed"

    local status=$(docker exec dev-vault vault status -format=json 2>/dev/null | jq -r '.sealed')

    if [ "$status" = "false" ]; then
        success "Vault is unsealed"
        return 0
    else
        fail "Vault is sealed or unreachable"
        return 1
    fi
}

################################################################################
# Tests if Vault keys and root token files exist on the host system.
#
# Verifies that the Vault initialization created the necessary key files:
# - keys.json: Contains unseal keys and root token
# - root-token: Contains the root authentication token
#
# These files are created during Vault initialization and are required for
# Vault operations and auto-unseal functionality.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - Both keys.json and root-token files exist
#   1 - One or both files are missing
#
# Outputs:
#   Test status message via info/success/fail functions
################################################################################
test_vault_keys_exist() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 3: Vault keys and token files exist"

    local keys_file="${HOME}/.config/vault/keys.json"
    local token_file="${HOME}/.config/vault/root-token"

    if [ -f "$keys_file" ] && [ -f "$token_file" ]; then
        success "Vault keys and token files exist"
        return 0
    else
        fail "Vault keys or token file missing"
        return 1
    fi
}

################################################################################
# Tests if Vault PKI engines are enabled and configured.
#
# Verifies that both the Root CA (pki) and Intermediate CA (pki_int) engines
# are mounted and accessible via the Vault API. These PKI engines are required
# for certificate issuance to database services.
#
# The test queries the /v1/sys/mounts endpoint to check for pki/ and pki_int/
# mount points created during the vault-bootstrap process.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - Both PKI engines are enabled
#   1 - One or both PKI engines are not enabled
#
# Outputs:
#   Test status message via info/success/fail functions
#   Suggests running vault-bootstrap if PKI engines are missing
################################################################################
test_vault_bootstrap_pki() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 4: Vault PKI is bootstrapped (Root CA, Intermediate CA)"

    export VAULT_ADDR="http://localhost:8200"
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)

    # Check if pki and pki_int are enabled
    local pki_enabled=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/sys/mounts" | jq -r '.["pki/"] // empty')

    local pki_int_enabled=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/sys/mounts" | jq -r '.["pki_int/"] // empty')

    if [ -n "$pki_enabled" ] && [ -n "$pki_int_enabled" ]; then
        success "PKI engines are enabled"
        return 0
    else
        fail "PKI engines not enabled - run vault-bootstrap"
        return 1
    fi
}

################################################################################
# Tests if certificate roles exist for all infrastructure services.
#
# Verifies that PKI roles are configured for each service that requires TLS
# certificates. Roles define the allowed domains, TTL, and other certificate
# parameters for each service.
#
# Checked roles:
# - postgres-role: For PostgreSQL database
# - mysql-role: For MySQL database
# - redis-1-role: For Redis cache
# - rabbitmq-role: For RabbitMQ message broker
# - mongodb-role: For MongoDB database
# - forgejo-role: For Forgejo Git service
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - All certificate roles exist
#   1 - One or more roles are missing
#
# Outputs:
#   Test status message via info/success/fail functions
#   Warning for each missing role
#   Suggests running vault-bootstrap if roles are missing
################################################################################
test_vault_certificate_roles() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 5: Certificate roles exist for all services"

    export VAULT_ADDR="http://localhost:8200"
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)

    local roles=("postgres-role" "mysql-role" "redis-1-role" "rabbitmq-role" "mongodb-role" "forgejo-role")
    local all_exist=true

    for role in "${roles[@]}"; do
        local role_exists=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/pki_int/roles/$role" 2>/dev/null | jq -r '.data // empty')

        if [ -z "$role_exists" ]; then
            warn "  Role missing: $role"
            all_exist=false
        fi
    done

    if [ "$all_exist" = true ]; then
        success "All certificate roles exist"
        return 0
    else
        fail "Some certificate roles missing - run vault-bootstrap"
        return 1
    fi
}

################################################################################
# Tests if service credentials are stored in Vault's KV secrets engine.
#
# Verifies that database passwords and credentials are securely stored in
# Vault at the expected secret paths. Each service has its credentials stored
# at /secret/data/{service-name} in the KV v2 secrets engine.
#
# Checked services:
# - postgres: PostgreSQL database credentials
# - mysql: MySQL database credentials
# - redis-1: Redis cache credentials
# - rabbitmq: RabbitMQ message broker credentials
# - mongodb: MongoDB database credentials
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - All service credentials are stored
#   1 - One or more services are missing credentials
#
# Outputs:
#   Test status message via info/success/fail functions
#   Warning for each service with missing credentials
#   Suggests running vault-bootstrap if credentials are missing
################################################################################
test_vault_secrets_stored() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 6: Service credentials stored in Vault"

    export VAULT_ADDR="http://localhost:8200"
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)

    local services=("postgres" "mysql" "redis-1" "rabbitmq" "mongodb")
    local all_exist=true

    for service in "${services[@]}"; do
        local secret=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
            "$VAULT_ADDR/v1/secret/data/$service" 2>/dev/null | jq -r '.data.data.password // empty')

        if [ -z "$secret" ]; then
            warn "  Credentials missing for: $service"
            all_exist=false
        fi
    done

    if [ "$all_exist" = true ]; then
        success "All service credentials stored"
        return 0
    else
        fail "Some service credentials missing - run vault-bootstrap"
        return 1
    fi
}

################################################################################
# Tests if PostgreSQL credentials in Vault are valid and complete.
#
# Verifies that the PostgreSQL secret contains all required fields with
# expected values:
# - user: Should be 'dev_admin'
# - password: Should be non-empty
# - database: Should be 'dev_database'
#
# This test validates the structure and content of stored credentials, ensuring
# they match the expected configuration for the PostgreSQL service.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - PostgreSQL credentials are valid and complete
#   1 - Credentials are incomplete or invalid
#
# Outputs:
#   Test status message via info/success/fail functions
#   Success message includes username and database name
################################################################################
test_vault_postgres_credentials() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 7: PostgreSQL credentials are valid"

    export VAULT_ADDR="http://localhost:8200"
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)

    local response=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/postgres" 2>/dev/null)

    local user=$(echo "$response" | jq -r '.data.data.user')
    local password=$(echo "$response" | jq -r '.data.data.password')
    local database=$(echo "$response" | jq -r '.data.data.database')

    if [ "$user" = "devuser" ] && [ -n "$password" ] && [ "$database" = "devdb" ]; then
        success "PostgreSQL credentials are valid (user=$user, db=$database)"
        return 0
    else
        fail "PostgreSQL credentials incomplete or invalid"
        return 1
    fi
}

################################################################################
# Tests if Vault can issue a certificate for PostgreSQL service.
#
# Performs a test certificate issuance request to verify that the PKI
# infrastructure is functioning correctly. Issues a certificate with:
# - Common Name: postgres.dev-services.local
# - TTL: 1 hour
# - Role: postgres-role
#
# This test validates that the intermediate CA can successfully sign
# certificates for service authentication and TLS encryption.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - Certificate issued successfully
#   1 - Failed to issue certificate
#
# Outputs:
#   Test status message via info/success/fail functions
################################################################################
test_vault_issue_certificate() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 8: Can issue certificate for PostgreSQL"

    export VAULT_ADDR="http://localhost:8200"
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)

    local cert_response=$(curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"common_name":"postgres.dev-services.local","ttl":"1h"}' \
        "$VAULT_ADDR/v1/pki_int/issue/postgres-role" 2>/dev/null)

    local certificate=$(echo "$cert_response" | jq -r '.data.certificate // empty')

    if [ -n "$certificate" ]; then
        success "Certificate issued successfully"
        return 0
    else
        fail "Failed to issue certificate"
        return 1
    fi
}

################################################################################
# Tests if CA certificates are exported to the local filesystem.
#
# Verifies that the Root CA and Intermediate CA certificates have been exported
# to the expected location (~/.config/vault/ca/) and are valid X.509 certificates.
#
# Checked files:
# - ca-chain.pem: Complete certificate chain (intermediate + root)
# - root-ca.pem: Root CA certificate
#
# The test also validates the certificate using OpenSSL to ensure the exported
# file is a properly formatted X.509 certificate.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#
# Returns:
#   0 - CA certificates exist and are valid
#   1 - Certificates missing or invalid
#
# Outputs:
#   Test status message via info/success/fail functions
#   Suggests running vault-bootstrap if certificates are missing
################################################################################
test_vault_ca_exported() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 9: CA certificates exported"

    local ca_dir="${HOME}/.config/vault/ca"

    if [ -f "$ca_dir/ca-chain.pem" ] && [ -f "$ca_dir/root-ca.pem" ]; then
        # Verify the certificate is valid
        if openssl x509 -in "$ca_dir/ca-chain.pem" -noout -text &>/dev/null; then
            success "CA certificates exported and valid"
            return 0
        else
            fail "CA certificate file exists but is invalid"
            return 1
        fi
    else
        fail "CA certificates not exported - run vault-bootstrap"
        return 1
    fi
}

################################################################################
# Tests if management script Vault commands function correctly.
#
# Verifies that the manage-devstack.sh script's Vault integration commands work
# as expected. Tests three key commands:
# - vault-status: Checks Vault health and seal status
# - vault-token: Retrieves the root token
# - vault-show-password: Retrieves service passwords from Vault
#
# This ensures that the management script provides a functional interface to
# Vault operations without requiring direct API calls.
#
# Globals:
#   TESTS_RUN - Incremented to track total tests
#   PROJECT_ROOT - Used to locate manage-devstack.sh script
#
# Returns:
#   0 - All management commands work correctly
#   1 - One or more commands failed
#
# Outputs:
#   Test status message via info/success/fail functions
################################################################################
test_management_commands() {
    TESTS_RUN=$((TESTS_RUN + 1))
    info "Test 10: Management script Vault commands work"

    # Test vault-status
    if "$PROJECT_ROOT/manage-devstack" vault-status &>/dev/null; then
        # Test vault-token
        local token=$("$PROJECT_ROOT/manage-devstack" vault-token 2>/dev/null)

        if [ -n "$token" ]; then
            # Test vault-show-password
            local password=$("$PROJECT_ROOT/manage-devstack" vault-show-password postgres 2>/dev/null)

            if [ -n "$password" ]; then
                success "Management commands work correctly"
                return 0
            fi
        fi
    fi

    fail "Some management commands failed"
    return 1
}

################################################################################
# Runs all Vault integration tests and displays results summary.
#
# Executes all test functions in sequence, allowing each to pass or fail
# independently. Displays a formatted summary of results including:
# - Total number of tests run
# - Number of tests passed
# - Number of tests failed
# - List of failed test names
#
# All tests are run with '|| true' to continue execution even if individual
# tests fail, ensuring a complete test report.
#
# Globals:
#   TESTS_RUN - Total count of executed tests
#   TESTS_PASSED - Count of successful tests
#   TESTS_FAILED - Count of failed tests
#   FAILED_TESTS - Array of failed test names
#   GREEN, RED, NC - Color codes for output formatting
#
# Returns:
#   0 - All tests passed
#   1 - One or more tests failed
#
# Outputs:
#   Test execution progress and final summary report to stdout
################################################################################
run_all_tests() {
    echo
    echo "========================================="
    echo "  Vault Integration Test Suite"
    echo "========================================="
    echo

    test_vault_running || true
    test_vault_unsealed || true
    test_vault_keys_exist || true
    test_vault_bootstrap_pki || true
    test_vault_certificate_roles || true
    test_vault_secrets_stored || true
    test_vault_postgres_credentials || true
    test_vault_issue_certificate || true
    test_vault_ca_exported || true
    test_management_commands || true

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
        echo -e "${GREEN}✓ All Vault tests passed!${NC}"
        return 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        return 1
    fi
}

# Main
run_all_tests
