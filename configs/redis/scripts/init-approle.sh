#!/bin/sh
################################################################################
# Redis Initialization Script with Vault AppRole Integration
################################################################################
# Initializes Redis with credentials fetched from Vault using AppRole auth.
# Uses the shared service-init-common.sh library for common functionality.
#
# USAGE:
#   ./init-approle.sh [redis-server-arguments]
#
# ENVIRONMENT:
#   VAULT_ADDR          - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR   - AppRole credentials directory (default: /vault-approles/redis)
#   REDIS_NODE          - Node identifier (redis-1, redis-2, redis-3)
#   REDIS_IP            - IP address for this Redis instance
#
# NOTE: All Redis nodes share credentials from secret/redis-1 in Vault
#
# DEPENDENCIES:
#   - /scripts/lib/service-init-common.sh (mounted from host)
#   - wget, jq (auto-installed via apk on Alpine)
#   - redis-server
#
# VERSION: 3.0.0 (Refactored to use shared library)
################################################################################

set -e

# Service configuration
SERVICE_NAME="redis-1"  # All nodes fetch credentials from shared path
SERVICE_DISPLAY_NAME="Redis"
REDIS_NODE_NAME="${REDIS_NODE:-redis-1}"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/redis}"
CERT_DIR="/etc/redis/certs"
SERVICE_IP="${REDIS_IP}"

# Source common library
# Note: Using POSIX sh compatible sourcing
if [ -f "/scripts/lib/service-init-common.sh" ]; then
    . /scripts/lib/service-init-common.sh
else
    echo "[Redis Init] ERROR: Cannot find service-init-common.sh library"
    exit 1
fi

################################################################################
# Redis-Specific Functions
################################################################################

#######################################
# Fetch Redis credentials from Vault
# Exports: REDIS_PASSWORD, ENABLE_TLS
#######################################
fetch_credentials() {
    log_info "Fetching credentials and TLS setting from Vault..."

    local response
    response=$(fetch_vault_secret "$SERVICE_NAME")

    export REDIS_PASSWORD=$(extract_vault_field "$response" "password")
    export ENABLE_TLS=$(extract_vault_field "$response" "tls_enabled" "false")

    if [ -z "$REDIS_PASSWORD" ] || [ "$REDIS_PASSWORD" = "null" ]; then
        log_error "Invalid credentials received from Vault"
    fi

    log_success "Credentials fetched successfully (tls_enabled=$ENABLE_TLS)"
}

#######################################
# Validate Redis TLS certificates
#######################################
validate_certificates() {
    if [ "$ENABLE_TLS" != "true" ]; then
        log_info "TLS disabled (tls_enabled=false in Vault), skipping certificate validation"
        return 0
    fi

    log_info "Validating pre-generated TLS certificates..."

    validate_cert_file "$CERT_DIR/redis.crt" "redis.crt"
    validate_cert_file "$CERT_DIR/redis.key" "redis.key"
    validate_cert_file "$CERT_DIR/ca.crt" "ca.crt"

    log_success "TLS certificates validated (pre-generated)"
}

################################################################################
# Main
################################################################################

main() {
    log_info "Node: $REDIS_NODE_NAME, IP: $SERVICE_IP"

    # Run common Vault initialization
    vault_init_common

    # Redis-specific initialization
    fetch_credentials
    validate_certificates

    log_info ""
    log_success "Initialization complete, starting Redis..."
    log_info ""

    # Start Redis with password and TLS if enabled
    if [ "$ENABLE_TLS" = "true" ]; then
        log_info "TLS enabled, starting Redis with TLS configuration..."
        exec redis-server "$@" \
            --requirepass "$REDIS_PASSWORD" \
            --tls-port 6380 \
            --port 6379 \
            --tls-cert-file "$CERT_DIR/redis.crt" \
            --tls-key-file "$CERT_DIR/redis.key" \
            --tls-ca-cert-file "$CERT_DIR/ca.crt" \
            --tls-auth-clients no
    else
        log_info "TLS disabled, starting Redis without TLS..."
        exec redis-server "$@" --requirepass "$REDIS_PASSWORD"
    fi
}

main "$@"
