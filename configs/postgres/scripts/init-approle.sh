#!/bin/bash
################################################################################
# PostgreSQL Initialization Script with Vault AppRole Integration
################################################################################
# Initializes PostgreSQL with credentials fetched from Vault using AppRole auth.
# Uses the shared service-init-common.sh library for common functionality.
#
# USAGE:
#   ./init-approle.sh [postgres_args...]
#
# ENVIRONMENT:
#   VAULT_ADDR          - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR   - AppRole credentials directory (default: /vault-approles/postgres)
#   POSTGRES_ENABLE_TLS - Enable TLS mode (default: false, read from Vault)
#
# DEPENDENCIES:
#   - /scripts/lib/service-init-common.sh (mounted from host)
#   - curl, jq (auto-installed)
#   - docker-entrypoint.sh (PostgreSQL official entrypoint)
#
# VERSION: 3.0.0 (Refactored to use shared library)
################################################################################

set -e

# Service configuration
SERVICE_NAME="postgres"
SERVICE_DISPLAY_NAME="PostgreSQL"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/postgres}"
CERT_DIR="/var/lib/postgresql/certs"

# Source common library
# The library is mounted from the host at container runtime
if [ -f "/scripts/lib/service-init-common.sh" ]; then
    source /scripts/lib/service-init-common.sh
else
    # Fallback: try to source from relative path (for local testing)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/../../../scripts/lib/service-init-common.sh" ]; then
        source "${SCRIPT_DIR}/../../../scripts/lib/service-init-common.sh"
    else
        echo "[PostgreSQL Init] ERROR: Cannot find service-init-common.sh library"
        exit 1
    fi
fi

################################################################################
# PostgreSQL-Specific Functions
################################################################################

#######################################
# Fetch PostgreSQL credentials from Vault
# Exports: POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, ENABLE_TLS
#######################################
fetch_credentials() {
    log_info "Fetching credentials and TLS setting from Vault..."

    local response
    response=$(fetch_vault_secret "$SERVICE_NAME")

    export POSTGRES_USER=$(extract_vault_field "$response" "user")
    export POSTGRES_PASSWORD=$(extract_vault_field "$response" "password")
    export POSTGRES_DB=$(extract_vault_field "$response" "database")
    export ENABLE_TLS=$(extract_vault_field "$response" "tls_enabled" "false")

    if [ -z "$POSTGRES_USER" ] || [ "$POSTGRES_USER" = "null" ]; then
        log_error "Invalid credentials received from Vault"
    fi

    log_success "Credentials fetched successfully (tls_enabled=$ENABLE_TLS)"
}

#######################################
# Validate PostgreSQL TLS certificates
#######################################
validate_certificates() {
    if [ "$ENABLE_TLS" != "true" ]; then
        log_info "TLS disabled (tls_enabled=false in Vault), skipping certificate validation"
        return 0
    fi

    log_info "Validating pre-generated TLS certificates..."

    validate_cert_file "$CERT_DIR/server.crt" "server.crt"
    validate_cert_file "$CERT_DIR/server.key" "server.key"
    validate_cert_file "$CERT_DIR/ca.crt" "ca.crt"

    log_success "TLS certificates validated (pre-generated)"
}

#######################################
# Configure PostgreSQL TLS environment
#######################################
configure_tls() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return 0
    fi

    log_info "Configuring PostgreSQL for TLS (dual-mode: accepts both SSL and non-SSL)..."

    export POSTGRES_SSL="on"
    export POSTGRES_SSL_CERT_FILE="$CERT_DIR/server.crt"
    export POSTGRES_SSL_KEY_FILE="$CERT_DIR/server.key"
    export POSTGRES_SSL_CA_FILE="$CERT_DIR/ca.crt"
    export POSTGRES_SSL_MIN_PROTOCOL_VERSION="TLSv1.2"

    log_success "TLS configuration environment variables set"
}

################################################################################
# Main
################################################################################

main() {
    # Run common Vault initialization
    vault_init_common

    # PostgreSQL-specific initialization
    fetch_credentials
    validate_certificates
    configure_tls

    log_info ""
    log_success "Initialization complete, starting PostgreSQL..."
    log_info ""

    # Start PostgreSQL with TLS configuration if enabled
    if [ "$ENABLE_TLS" = "true" ]; then
        exec docker-entrypoint.sh "$@" \
            -c ssl=on \
            -c ssl_cert_file="$CERT_DIR/server.crt" \
            -c ssl_key_file="$CERT_DIR/server.key" \
            -c ssl_ca_file="$CERT_DIR/ca.crt" \
            -c ssl_min_protocol_version=TLSv1.2 \
            -c ssl_prefer_server_ciphers=on \
            -c "ssl_ciphers=HIGH:MEDIUM:+3DES:!aNULL"
    else
        exec docker-entrypoint.sh "$@"
    fi
}

main "$@"
