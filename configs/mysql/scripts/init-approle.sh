#!/bin/bash
################################################################################
# MySQL Initialization Script with Vault AppRole Integration
################################################################################
# Initializes MySQL with credentials fetched from Vault using AppRole auth.
# Uses the shared service-init-common.sh library for common functionality.
#
# USAGE:
#   ./init-approle.sh [mysqld_args...]
#
# ENVIRONMENT:
#   VAULT_ADDR          - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR   - AppRole credentials directory (default: /vault-approles/mysql)
#   MYSQL_ENABLE_TLS    - Enable TLS mode (default: false, read from Vault)
#
# DEPENDENCIES:
#   - /scripts/lib/service-init-common.sh (mounted from host)
#   - curl, jq (auto-installed - fixes previous grep/sed JSON parsing)
#   - docker-entrypoint.sh (MySQL official entrypoint)
#
# VERSION: 3.0.0 (Refactored to use shared library with proper jq JSON parsing)
################################################################################

set -e

# Service configuration
SERVICE_NAME="mysql"
SERVICE_DISPLAY_NAME="MySQL"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/mysql}"
CERT_DIR="/var/lib/mysql-certs"

# Source common library
if [ -f "/scripts/lib/service-init-common.sh" ]; then
    source /scripts/lib/service-init-common.sh
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/../../../scripts/lib/service-init-common.sh" ]; then
        source "${SCRIPT_DIR}/../../../scripts/lib/service-init-common.sh"
    else
        echo "[MySQL Init] ERROR: Cannot find service-init-common.sh library"
        exit 1
    fi
fi

################################################################################
# MySQL-Specific Functions
################################################################################

#######################################
# Fetch MySQL credentials from Vault
# Exports: MYSQL_ROOT_PASSWORD, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE, ENABLE_TLS
#######################################
fetch_credentials() {
    log_info "Fetching credentials and TLS setting from Vault..."

    local response
    response=$(fetch_vault_secret "$SERVICE_NAME")

    # Now using jq for proper JSON parsing (fixed from grep/sed)
    export MYSQL_ROOT_PASSWORD=$(extract_vault_field "$response" "root_password")
    export MYSQL_USER=$(extract_vault_field "$response" "user")
    export MYSQL_PASSWORD=$(extract_vault_field "$response" "password")
    export MYSQL_DATABASE=$(extract_vault_field "$response" "database")
    export ENABLE_TLS=$(extract_vault_field "$response" "tls_enabled" "false")

    if [ -z "$MYSQL_ROOT_PASSWORD" ] || [ "$MYSQL_ROOT_PASSWORD" = "null" ]; then
        log_error "Invalid credentials received from Vault"
    fi

    log_success "Credentials fetched successfully (tls_enabled=$ENABLE_TLS)"
}

#######################################
# Validate MySQL TLS certificates
#######################################
validate_certificates() {
    if [ "$ENABLE_TLS" != "true" ]; then
        log_info "TLS disabled (tls_enabled=false in Vault), skipping certificate validation"
        return 0
    fi

    log_info "Validating pre-generated TLS certificates..."

    validate_cert_file "$CERT_DIR/server-cert.pem" "server-cert.pem"
    validate_cert_file "$CERT_DIR/server-key.pem" "server-key.pem"
    validate_cert_file "$CERT_DIR/ca.pem" "ca.pem"

    log_success "TLS certificates validated (pre-generated)"
}

#######################################
# Configure MySQL TLS via configuration file
#######################################
configure_tls() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return 0
    fi

    log_info "Configuring MySQL for TLS (dual-mode: accepts both SSL and non-SSL)..."

    # Create custom MySQL configuration for TLS
    mkdir -p /etc/my.cnf.d
    cat > /etc/my.cnf.d/tls.cnf <<EOF
[mysqld]
# SSL/TLS Configuration (Dual-Mode)
# Accepts both encrypted and unencrypted connections
ssl-ca=$CERT_DIR/ca.pem
ssl-cert=$CERT_DIR/server-cert.pem
ssl-key=$CERT_DIR/server-key.pem
require_secure_transport=OFF
tls_version=TLSv1.2,TLSv1.3
EOF

    log_success "TLS dual-mode configuration prepared (accepts both SSL and non-SSL connections)"
}

################################################################################
# Main
################################################################################

main() {
    # Run common Vault initialization
    vault_init_common

    # MySQL-specific initialization
    fetch_credentials
    validate_certificates
    configure_tls

    log_info ""
    log_success "Initialization complete, starting MySQL..."
    log_info ""

    # Start MySQL with the original docker-entrypoint
    exec docker-entrypoint.sh "$@"
}

main "$@"
