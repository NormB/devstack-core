#!/bin/bash
################################################################################
# RabbitMQ Initialization Script with Vault AppRole Integration
################################################################################
# Initializes RabbitMQ with credentials fetched from Vault using AppRole auth.
# Uses the shared service-init-common.sh library for common functionality.
#
# USAGE:
#   ./init-approle.sh [rabbitmq_args...]
#
# ENVIRONMENT:
#   VAULT_ADDR          - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR   - AppRole credentials directory (default: /vault-approles/rabbitmq)
#   RABBITMQ_ENABLE_TLS - Enable TLS mode (default: false, read from Vault)
#
# DEPENDENCIES:
#   - /scripts/lib/service-init-common.sh (mounted from host)
#   - wget, jq (auto-installed - fixes previous grep/sed JSON parsing)
#   - docker-entrypoint.sh (RabbitMQ official entrypoint)
#
# VERSION: 3.0.0 (Refactored to use shared library with proper jq JSON parsing)
################################################################################

set -e

# Service configuration
SERVICE_NAME="rabbitmq"
SERVICE_DISPLAY_NAME="RabbitMQ"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/rabbitmq}"
CERT_DIR="/etc/rabbitmq/certs"

# Source common library
if [ -f "/scripts/lib/service-init-common.sh" ]; then
    source /scripts/lib/service-init-common.sh
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "${SCRIPT_DIR}/../../../scripts/lib/service-init-common.sh" ]; then
        source "${SCRIPT_DIR}/../../../scripts/lib/service-init-common.sh"
    else
        echo "[RabbitMQ Init] ERROR: Cannot find service-init-common.sh library"
        exit 1
    fi
fi

################################################################################
# RabbitMQ-Specific Functions
################################################################################

#######################################
# Fetch RabbitMQ credentials from Vault
# Exports: RABBITMQ_DEFAULT_USER, RABBITMQ_DEFAULT_PASS,
#          RABBITMQ_DEFAULT_VHOST, ENABLE_TLS
#######################################
fetch_credentials() {
    log_info "Fetching credentials and TLS setting from Vault..."

    local response
    response=$(fetch_vault_secret "$SERVICE_NAME")

    # Now using jq for proper JSON parsing (fixed from grep/sed)
    export RABBITMQ_DEFAULT_USER=$(extract_vault_field "$response" "user")
    export RABBITMQ_DEFAULT_PASS=$(extract_vault_field "$response" "password")
    export RABBITMQ_DEFAULT_VHOST=$(extract_vault_field "$response" "vhost")
    export ENABLE_TLS=$(extract_vault_field "$response" "tls_enabled" "false")

    if [ -z "$RABBITMQ_DEFAULT_USER" ] || [ -z "$RABBITMQ_DEFAULT_PASS" ]; then
        log_error "Invalid credentials received from Vault"
    fi

    log_success "Credentials fetched successfully (tls_enabled=$ENABLE_TLS)"
}

#######################################
# Validate RabbitMQ TLS certificates
#######################################
validate_certificates() {
    if [ "$ENABLE_TLS" != "true" ]; then
        log_info "TLS disabled (tls_enabled=false in Vault), skipping certificate validation"
        return 0
    fi

    log_info "Validating pre-generated TLS certificates..."

    validate_cert_file "$CERT_DIR/server.pem" "server.pem"
    validate_cert_file "$CERT_DIR/key.pem" "key.pem"
    validate_cert_file "$CERT_DIR/ca.pem" "ca.pem"

    log_success "TLS certificates validated (pre-generated)"
}

#######################################
# Configure RabbitMQ TLS via configuration file
#######################################
configure_tls() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return 0
    fi

    log_info "Configuring RabbitMQ for TLS (dual-mode: accepts both SSL and non-SSL)..."

    # Create RabbitMQ SSL config
    cat > /etc/rabbitmq/rabbitmq.conf <<EOF
# Dual-Mode TLS Configuration
# Accepts both encrypted (port 5671) and unencrypted (port 5672) connections
listeners.tcp.default = 5672
listeners.ssl.default = 5671

ssl_options.cacertfile = $CERT_DIR/ca.pem
ssl_options.certfile   = $CERT_DIR/server.pem
ssl_options.keyfile    = $CERT_DIR/key.pem
ssl_options.verify     = verify_peer
ssl_options.fail_if_no_peer_cert = false

# SSL versions
ssl_options.versions.1 = tlsv1.2
ssl_options.versions.2 = tlsv1.3
EOF

    log_success "TLS dual-mode configuration prepared (accepts both SSL on 5671 and non-SSL on 5672)"
}

################################################################################
# Main
################################################################################

main() {
    # Run common Vault initialization
    vault_init_common

    # RabbitMQ-specific initialization
    fetch_credentials
    validate_certificates
    configure_tls

    log_info ""
    log_success "Initialization complete, starting RabbitMQ..."
    log_info ""

    # Start RabbitMQ with the original docker-entrypoint
    exec docker-entrypoint.sh "$@"
}

main "$@"
