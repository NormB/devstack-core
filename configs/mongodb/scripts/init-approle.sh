#!/bin/bash
################################################################################
# MongoDB Initialization Script with Vault AppRole Integration
################################################################################
# Initializes MongoDB with credentials fetched from Vault using AppRole auth.
# Uses the shared service-init-common.sh library for common functionality.
#
# USAGE:
#   ./init-approle.sh [mongod_args...]
#
# ENVIRONMENT:
#   VAULT_ADDR          - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR   - AppRole credentials directory (default: /vault-approles/mongodb)
#   MONGODB_ENABLE_TLS  - Enable TLS mode (default: false, read from Vault)
#
# DEPENDENCIES:
#   - /scripts/lib/service-init-common.sh (mounted from host)
#   - curl, jq (auto-installed - fixes previous grep/sed JSON parsing)
#   - docker-entrypoint.sh (MongoDB official entrypoint)
#
# VERSION: 3.0.0 (Refactored to use shared library with proper jq JSON parsing)
################################################################################

set -e

# Service configuration
SERVICE_NAME="mongodb"
SERVICE_DISPLAY_NAME="MongoDB"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/mongodb}"
CERT_DIR="/etc/mongodb/certs"

# Source common library
if [ -f "/scripts/lib/service-init-common.sh" ]; then
    source /scripts/lib/service-init-common.sh
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/../../../scripts/lib/service-init-common.sh" ]; then
        source "${SCRIPT_DIR}/../../../scripts/lib/service-init-common.sh"
    else
        echo "[MongoDB Init] ERROR: Cannot find service-init-common.sh library"
        exit 1
    fi
fi

################################################################################
# MongoDB-Specific Functions
################################################################################

#######################################
# Fetch MongoDB credentials from Vault
# Exports: MONGO_INITDB_ROOT_USERNAME, MONGO_INITDB_ROOT_PASSWORD,
#          MONGO_INITDB_DATABASE, ENABLE_TLS
#######################################
fetch_credentials() {
    log_info "Fetching credentials and TLS setting from Vault..."

    local response
    response=$(fetch_vault_secret "$SERVICE_NAME")

    # Now using jq for proper JSON parsing (fixed from grep/sed)
    export MONGO_INITDB_ROOT_USERNAME=$(extract_vault_field "$response" "user")
    export MONGO_INITDB_ROOT_PASSWORD=$(extract_vault_field "$response" "password")
    export MONGO_INITDB_DATABASE=$(extract_vault_field "$response" "database")
    export ENABLE_TLS=$(extract_vault_field "$response" "tls_enabled" "false")

    if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
        log_error "Invalid credentials received from Vault"
    fi

    log_success "Credentials fetched successfully (tls_enabled=$ENABLE_TLS)"
}

#######################################
# Validate MongoDB TLS certificates
#######################################
validate_certificates() {
    if [ "$ENABLE_TLS" != "true" ]; then
        log_info "TLS disabled (tls_enabled=false in Vault), skipping certificate validation"
        return 0
    fi

    log_info "Validating pre-generated TLS certificates..."

    # MongoDB requires combined cert+key file
    validate_cert_file "$CERT_DIR/mongodb.pem" "mongodb.pem"
    validate_cert_file "$CERT_DIR/ca.pem" "ca.pem"

    log_success "TLS certificates validated (pre-generated)"
}

#######################################
# Configure MongoDB TLS via configuration file
#######################################
configure_tls() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return 0
    fi

    log_info "Configuring MongoDB for TLS (dual-mode: accepts both SSL and non-SSL)..."

    # Create MongoDB SSL config directory and file
    mkdir -p /etc/mongod.conf.d
    cat > /etc/mongod.conf.d/ssl.conf <<EOF
# SSL/TLS Configuration (Dual-Mode)
# Accepts both encrypted and unencrypted connections
net:
  tls:
    mode: preferTLS
    certificateKeyFile: $CERT_DIR/mongodb.pem
    CAFile: $CERT_DIR/ca.pem
    allowConnectionsWithoutCertificates: true
EOF

    log_success "TLS dual-mode configuration prepared (accepts both SSL and non-SSL connections)"
}

################################################################################
# Main
################################################################################

main() {
    # Run common Vault initialization
    vault_init_common

    # MongoDB-specific initialization
    fetch_credentials
    validate_certificates
    configure_tls

    log_info ""
    log_success "Initialization complete, starting MongoDB..."
    log_info ""

    # Start MongoDB with TLS configuration if enabled
    if [ "$ENABLE_TLS" = "true" ]; then
        exec docker-entrypoint.sh "$@" \
            --tlsMode preferTLS \
            --tlsCertificateKeyFile "$CERT_DIR/mongodb.pem" \
            --tlsCAFile "$CERT_DIR/ca.pem" \
            --tlsAllowConnectionsWithoutCertificates
    else
        exec docker-entrypoint.sh "$@"
    fi
}

main "$@"
