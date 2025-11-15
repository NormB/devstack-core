#!/bin/bash
#
# Vault AppRole Bootstrap Script
# ================================
#
# This script bootstraps HashiCorp Vault with AppRole authentication for all services.
# It replaces root token authentication with least-privilege AppRole access.
#
# Usage:
#   ./scripts/vault-approle-bootstrap.sh
#
# Prerequisites:
#   - Vault must be running and unsealed
#   - VAULT_ADDR must be set (default: http://localhost:8200)
#   - VAULT_TOKEN must be set (root token)
#
# What this script does:
#   1. Enables AppRole auth method
#   2. Loads policies from configs/vault/policies/*.hcl
#   3. Creates AppRole for each service (postgres, mysql, mongodb, redis, rabbitmq, forgejo, reference-api)
#   4. Generates role_id and secret_id for each AppRole
#   5. Stores credentials in ~/.config/vault/approles/
#   6. Validates AppRole authentication
#
# Security notes:
#   - role_id: Can be distributed openly (identifies the role)
#   - secret_id: Must be kept secret (proves authorization)
#   - secret_id has 30-day TTL with unlimited uses
#   - After 30 days, new secret_id must be generated
#
# Author: DevStack Core Team
# Version: 1.0
# Date: November 14, 2025

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
VAULT_CONFIG_DIR="${HOME}/.config/vault"
APPROLE_DIR="${VAULT_CONFIG_DIR}/approles"
POLICY_DIR="${PROJECT_ROOT}/configs/vault/policies"

# Services that need AppRole authentication
SERVICES=(
    "postgres"
    "mysql"
    "mongodb"
    "redis"
    "rabbitmq"
    "forgejo"
    "reference-api"
)

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if Vault token is set
    if [ -z "$VAULT_TOKEN" ]; then
        if [ -f "${VAULT_CONFIG_DIR}/root-token" ]; then
            VAULT_TOKEN=$(cat "${VAULT_CONFIG_DIR}/root-token")
            export VAULT_TOKEN
            log_info "Loaded Vault token from ${VAULT_CONFIG_DIR}/root-token"
        else
            error_exit "VAULT_TOKEN not set and root-token file not found"
        fi
    fi

    # Check if Vault is accessible
    if ! docker exec dev-vault vault status >/dev/null 2>&1; then
        error_exit "Vault is not accessible. Is it running and unsealed?"
    fi

    # Check if Vault is unsealed
    SEALED=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault status -format=json | docker exec -i dev-vault sh -c "grep -o '\"sealed\":[^,]*' | cut -d':' -f2")
    if [ "$SEALED" = "true" ]; then
        error_exit "Vault is sealed. Unseal it first with: ./manage-devstack vault-unseal"
    fi

    # Check if policy directory exists
    if [ ! -d "$POLICY_DIR" ]; then
        error_exit "Policy directory not found: $POLICY_DIR"
    fi

    # Check if policy files exist
    local missing_policies=0
    for service in "${SERVICES[@]}"; do
        if [ ! -f "${POLICY_DIR}/${service}-policy.hcl" ]; then
            log_error "Policy file not found: ${POLICY_DIR}/${service}-policy.hcl"
            missing_policies=1
        fi
    done

    if [ $missing_policies -eq 1 ]; then
        error_exit "Some policy files are missing. Cannot continue."
    fi

    log_success "All prerequisites met"
}

# Enable AppRole auth method
enable_approle() {
    log_info "Enabling AppRole auth method..."

    # Check if AppRole is already enabled
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault auth list | grep -q "approle"; then
        log_warning "AppRole auth method already enabled"
        return 0
    fi

    # Enable AppRole
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault auth enable approle; then
        log_success "AppRole auth method enabled"
    else
        error_exit "Failed to enable AppRole auth method"
    fi
}

# Load policy into Vault
load_policy() {
    local service=$1
    local policy_file="${POLICY_DIR}/${service}-policy.hcl"
    local policy_name="${service}-policy"

    log_info "Loading policy: ${policy_name}"

    # Copy policy file to Vault container
    docker cp "$policy_file" dev-vault:/tmp/${service}-policy.hcl

    # Write policy to Vault
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault policy write "$policy_name" /tmp/${service}-policy.hcl; then
        log_success "Policy loaded: ${policy_name}"
    else
        error_exit "Failed to load policy: ${policy_name}"
    fi

    # Clean up temporary file
    docker exec dev-vault rm /tmp/${service}-policy.hcl
}

# Load all policies
load_all_policies() {
    log_info "Loading all service policies..."

    for service in "${SERVICES[@]}"; do
        load_policy "$service"
    done

    log_success "All policies loaded successfully"
}

# Create AppRole for a service
create_approle() {
    local service=$1
    local role_name="${service}-role"
    local policy_name="${service}-policy"

    log_info "Creating AppRole: ${role_name}"

    # Create AppRole with policy attached
    # token_ttl: 1 hour (3600 seconds)
    # token_max_ttl: 24 hours (86400 seconds)
    # secret_id_ttl: 30 days (2592000 seconds)
    # secret_id_num_uses: 0 (unlimited)
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault write \
        "auth/approle/role/${role_name}" \
        token_policies="${policy_name}" \
        token_ttl=3600 \
        token_max_ttl=86400 \
        secret_id_ttl=2592000 \
        secret_id_num_uses=0 \
        bind_secret_id=true; then
        log_success "AppRole created: ${role_name}"
    else
        error_exit "Failed to create AppRole: ${role_name}"
    fi
}

# Create all AppRoles
create_all_approles() {
    log_info "Creating AppRoles for all services..."

    for service in "${SERVICES[@]}"; do
        create_approle "$service"
    done

    log_success "All AppRoles created successfully"
}

# Generate role_id for a service
generate_role_id() {
    local service=$1
    local role_name="${service}-role"

    log_info "Generating role_id for: ${role_name}" >&2

    # Get role_id
    local role_id
    role_id=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault read -field=role_id "auth/approle/role/${role_name}/role-id")

    if [ -z "$role_id" ]; then
        error_exit "Failed to generate role_id for: ${role_name}"
    fi

    echo "$role_id"
}

# Generate secret_id for a service
generate_secret_id() {
    local service=$1
    local role_name="${service}-role"

    log_info "Generating secret_id for: ${role_name}" >&2

    # Generate secret_id
    local secret_id
    secret_id=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault write -field=secret_id -f "auth/approle/role/${role_name}/secret-id")

    if [ -z "$secret_id" ]; then
        error_exit "Failed to generate secret_id for: ${role_name}"
    fi

    echo "$secret_id"
}

# Generate and store credentials for all services
generate_credentials() {
    log_info "Generating role_id and secret_id for all services..."

    # Create AppRole directory
    mkdir -p "$APPROLE_DIR"
    chmod 700 "$APPROLE_DIR"

    for service in "${SERVICES[@]}"; do
        local service_dir="${APPROLE_DIR}/${service}"
        mkdir -p "$service_dir"
        chmod 700 "$service_dir"

        log_info "Generating credentials for: ${service}"

        # Generate role_id
        local role_id
        role_id=$(generate_role_id "$service")
        echo "$role_id" > "${service_dir}/role-id"
        chmod 600 "${service_dir}/role-id"

        # Generate secret_id
        local secret_id
        secret_id=$(generate_secret_id "$service")
        echo "$secret_id" > "${service_dir}/secret-id"
        chmod 600 "${service_dir}/secret-id"

        log_success "Credentials generated for ${service}:"
        log_info "  role_id: ${role_id}"
        log_info "  secret_id: ${secret_id:0:20}... (truncated)"
        log_info "  Stored in: ${service_dir}/"
    done

    log_success "All credentials generated and stored"
}

# Test AppRole authentication for a service
test_approle_auth() {
    local service=$1
    local role_id=$2
    local secret_id=$3

    log_info "Testing AppRole authentication for: ${service}"

    # Login with AppRole and get token
    local client_token
    client_token=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" dev-vault vault write -field=token auth/approle/login \
        role_id="$role_id" \
        secret_id="$secret_id" 2>/dev/null)

    if [ -z "$client_token" ] || [ "$client_token" = "null" ]; then
        log_error "AppRole authentication failed for: ${service}"
        return 1
    fi

    # Test accessing service's secret with the token
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${client_token}" dev-vault vault kv get "secret/${service}" >/dev/null 2>&1; then
        log_success "AppRole authentication successful for: ${service}"
        return 0
    else
        log_error "AppRole authenticated but cannot access secret for: ${service}"
        return 1
    fi
}

# Test all AppRole authentications
test_all_approles() {
    log_info "Testing AppRole authentication for all services..."

    local failures=0

    for service in "${SERVICES[@]}"; do
        local role_id
        local secret_id

        role_id=$(cat "${APPROLE_DIR}/${service}/role-id")
        secret_id=$(cat "${APPROLE_DIR}/${service}/secret-id")

        if ! test_approle_auth "$service" "$role_id" "$secret_id"; then
            failures=$((failures + 1))
        fi
    done

    if [ $failures -eq 0 ]; then
        log_success "All AppRole authentications tested successfully"
        return 0
    else
        log_error "AppRole authentication failed for $failures service(s)"
        return 1
    fi
}

# Verify policy enforcement (ensure services can only access their own secrets)
verify_policy_enforcement() {
    log_info "Verifying policy enforcement (least-privilege access)..."

    # Test: postgres AppRole should NOT be able to access mysql secret
    log_info "Testing: postgres AppRole accessing mysql secret (should fail)"

    local postgres_role_id
    local postgres_secret_id
    postgres_role_id=$(cat "${APPROLE_DIR}/postgres/role-id")
    postgres_secret_id=$(cat "${APPROLE_DIR}/postgres/secret-id")

    # Login with postgres AppRole
    local postgres_token
    postgres_token=$(docker exec -e VAULT_ADDR="${VAULT_ADDR}" dev-vault vault write -field=token auth/approle/login \
        role_id="$postgres_role_id" \
        secret_id="$postgres_secret_id")

    # Try to access mysql secret (should fail)
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${postgres_token}" dev-vault vault kv get "secret/mysql" >/dev/null 2>&1; then
        log_error "Policy enforcement FAILED: postgres can access mysql secret"
        return 1
    else
        log_success "Policy enforcement PASSED: postgres cannot access mysql secret"
    fi

    log_success "Policy enforcement verified successfully"
}

# Rollback function (in case of failure)
rollback() {
    log_warning "Rolling back AppRole configuration..."

    # Disable AppRole auth method
    if docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault auth list | grep -q "approle"; then
        log_info "Disabling AppRole auth method..."
        docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault auth disable approle
    fi

    # Remove policies
    for service in "${SERVICES[@]}"; do
        log_info "Removing policy: ${service}-policy"
        docker exec -e VAULT_ADDR="${VAULT_ADDR}" -e VAULT_TOKEN="${VAULT_TOKEN}" dev-vault vault policy delete "${service}-policy" 2>/dev/null || true
    done

    # Remove stored credentials
    if [ -d "$APPROLE_DIR" ]; then
        log_info "Removing stored credentials: $APPROLE_DIR"
        rm -rf "$APPROLE_DIR"
    fi

    log_success "Rollback completed"
}

# Print summary
print_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                    VAULT APPROLE BOOTSTRAP COMPLETE"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "AppRole Status:"
    echo "  ✓ AppRole auth method enabled"
    echo "  ✓ $(echo ${#SERVICES[@]}) policies loaded"
    echo "  ✓ $(echo ${#SERVICES[@]}) AppRoles created"
    echo "  ✓ Credentials generated and stored"
    echo "  ✓ Authentication tested successfully"
    echo "  ✓ Policy enforcement verified"
    echo ""
    echo "Credentials stored in: ${APPROLE_DIR}/"
    echo ""
    echo "Service AppRoles:"
    for service in "${SERVICES[@]}"; do
        echo "  - ${service}-role"
        echo "    role_id: ${APPROLE_DIR}/${service}/role-id"
        echo "    secret_id: ${APPROLE_DIR}/${service}/secret-id"
    done
    echo ""
    echo "Next Steps:"
    echo "  1. Update service init scripts to use AppRole authentication"
    echo "  2. Test service startup with AppRole credentials"
    echo "  3. Remove root token from service configurations"
    echo ""
    echo "Security Notes:"
    echo "  - role_id can be distributed openly (identifies the role)"
    echo "  - secret_id MUST be kept secret (proves authorization)"
    echo "  - secret_id expires in 30 days - regenerate before expiry"
    echo "  - Token TTL: 1 hour, Max TTL: 24 hours"
    echo ""
    echo "To regenerate secret_id for a service:"
    echo "  docker exec -e VAULT_ADDR=http://localhost:8200 -e VAULT_TOKEN=\$VAULT_TOKEN \\"
    echo "    dev-vault vault write -field=secret_id -f auth/approle/role/<service>-role/secret-id"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
}

# Main execution
main() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                       VAULT APPROLE BOOTSTRAP"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""

    # Trap errors for rollback
    trap 'log_error "Bootstrap failed! Run with rollback: ./scripts/vault-approle-bootstrap.sh --rollback"; exit 1' ERR

    # Check for rollback flag
    if [ "${1:-}" = "--rollback" ]; then
        rollback
        exit 0
    fi

    # Execute bootstrap steps
    check_prerequisites
    enable_approle
    load_all_policies
    create_all_approles
    generate_credentials
    test_all_approles
    verify_policy_enforcement

    # Print summary
    print_summary

    log_success "Vault AppRole bootstrap completed successfully!"
    exit 0
}

# Run main function
main "$@"
