#!/bin/bash
#######################################
# MySQL Initialization Script with Vault AppRole Integration
#
# This script orchestrates the secure initialization of MySQL by integrating
# with HashiCorp Vault AppRole authentication for credential management and TLS
# certificate validation. It supports dual-mode TLS configuration.
#
# DESCRIPTION:
#   Initializes MySQL with credentials fetched from Vault using AppRole
#   authentication. The script authenticates via AppRole (role_id + secret_id),
#   obtains a temporary token, retrieves database credentials and TLS settings,
#   validates pre-generated certificates if TLS is enabled, configures MySQL
#   SSL parameters, and starts the database server with appropriate security settings.
#
# GLOBALS:
#   VAULT_ADDR - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR - Directory containing AppRole credentials (default: /vault-approles/mysql)
#   SERVICE_NAME - Service identifier for Vault secrets (set to "mysql")
#   SERVICE_IP - MySQL service IP address (default: 172.20.0.12)
#   CERT_DIR - Directory containing TLS certificates (/var/lib/mysql-certs)
#   ENABLE_TLS - TLS enablement flag (read from Vault)
#   MYSQL_ROOT_PASSWORD - Root user password (exported from Vault)
#   MYSQL_USER - Application database username (exported from Vault)
#   MYSQL_PASSWORD - Application user password (exported from Vault)
#   MYSQL_DATABASE - Default database name (exported from Vault)
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for output formatting
#
# USAGE:
#   ./init-approle.sh [mysqld_args...]
#
#   Example:
#     ./init-approle.sh mysqld
#     VAULT_ADDR=http://vault:8200 ./init-approle.sh mysqld
#
# DEPENDENCIES:
#   - curl: For Vault health checks and API requests
#   - grep, sed, cut: For JSON parsing without jq dependency
#   - docker-entrypoint.sh: MySQL official entrypoint script
#   - HashiCorp Vault: Must be accessible and unsealed
#   - AppRole credentials: role-id and secret-id files in VAULT_APPROLE_DIR
#   - Pre-generated TLS certificates: Required when tls_enabled=true in Vault
#
# EXIT CODES:
#   0 - Successful initialization and MySQL startup
#   1 - Vault connection failure or timeout
#   1 - Missing AppRole credentials (role-id or secret-id)
#   1 - AppRole authentication failure
#   1 - Invalid or missing credentials from Vault
#   1 - TLS certificate validation failure
#   1 - Configuration errors
#
# NOTES:
#   - The script uses 'set -e' for fail-fast behavior
#   - Maximum Vault readiness wait time: 120 seconds (60 attempts x 2s)
#   - AppRole credentials are read from mounted volume at VAULT_APPROLE_DIR
#   - Token obtained from AppRole is temporary (1h TTL by default)
#   - TLS mode is "dual-mode": accepts both SSL and non-SSL connections
#   - Certificates must be pre-generated using scripts/generate-certificates.sh
#   - Certificate permissions are validated before use
#   - MySQL config file created at /etc/my.cnf.d/tls.cnf when TLS enabled
#   - require_secure_transport is set to OFF for dual-mode operation
#   - Supported TLS versions: TLSv1.2, TLSv1.3
#   - Uses grep/sed for JSON parsing (no jq required)
#
# SECURITY:
#   - No hardcoded credentials or tokens
#   - Uses least-privilege AppRole authentication
#   - Token expires after 1 hour (renewable)
#   - AppRole credentials mounted read-only from host
#
# AUTHORS:
#   DevStack Core Team
#
# VERSION:
#   2.0.0 (AppRole)
#
#######################################

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/mysql}"
SERVICE_NAME="mysql"
SERVICE_IP="${MYSQL_IP:-172.20.0.12}"
CERT_DIR="/var/lib/mysql-certs"
ENABLE_TLS=""  # Will be read from Vault
VAULT_TOKEN=""  # Will be obtained via AppRole auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Prints informational message to stdout
#######################################
info() { echo -e "${BLUE}[MySQL Init]${NC} $1"; }

#######################################
# Prints success message to stdout
#######################################
success() { echo -e "${GREEN}[MySQL Init]${NC} $1"; }

#######################################
# Prints warning message to stdout
#######################################
warn() { echo -e "${YELLOW}[MySQL Init]${NC} $1"; }

#######################################
# Prints error message to stderr and exits with code 1
#######################################
error() { echo -e "${RED}[MySQL Init]${NC} $1"; exit 1; }

#######################################
# Waits for Vault service to become available and ready
#######################################
wait_for_vault() {
    info "Waiting for Vault to be ready..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "$VAULT_ADDR/v1/sys/health?standbyok=true" > /dev/null 2>&1; then
            success "Vault is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    error "Vault did not become ready in time"
}

#######################################
# Reads AppRole credentials from mounted volume
# Globals:
#   VAULT_APPROLE_DIR - Directory containing role-id and secret-id files
# Returns:
#   0 - Credentials read successfully
#   1 - Missing or unreadable credential files
# Outputs:
#   ROLE_ID - AppRole role identifier
#   SECRET_ID - AppRole secret identifier
#######################################
read_approle_credentials() {
    info "Reading AppRole credentials from $VAULT_APPROLE_DIR..."

    if [ ! -f "$VAULT_APPROLE_DIR/role-id" ]; then
        error "AppRole role-id file not found: $VAULT_APPROLE_DIR/role-id"
    fi

    if [ ! -f "$VAULT_APPROLE_DIR/secret-id" ]; then
        error "AppRole secret-id file not found: $VAULT_APPROLE_DIR/secret-id"
    fi

    ROLE_ID=$(cat "$VAULT_APPROLE_DIR/role-id")
    SECRET_ID=$(cat "$VAULT_APPROLE_DIR/secret-id")

    if [ -z "$ROLE_ID" ] || [ -z "$SECRET_ID" ]; then
        error "AppRole credentials are empty"
    fi

    success "AppRole credentials loaded (role_id: ${ROLE_ID:0:20}...)"
}

#######################################
# Authenticates to Vault using AppRole and obtains a client token
# Globals:
#   VAULT_ADDR - Vault server URL
#   ROLE_ID - AppRole role identifier
#   SECRET_ID - AppRole secret identifier
#   VAULT_TOKEN - Exported client token obtained from authentication
# Returns:
#   0 - Authentication successful, token obtained
#   1 - Authentication failed or invalid response
# Outputs:
#   Sets VAULT_TOKEN environment variable with temporary client token
#######################################
authenticate_approle() {
    info "Authenticating to Vault with AppRole..."

    local auth_response=$(curl -sf \
        -X POST \
        -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
        "$VAULT_ADDR/v1/auth/approle/login" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$auth_response" ]; then
        error "Failed to authenticate with AppRole"
    fi

    # Parse JSON using grep/sed (no jq required)
    VAULT_TOKEN=$(echo "$auth_response" | grep -o '"client_token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" = "null" ]; then
        error "Failed to obtain token from AppRole authentication"
    fi

    success "AppRole authentication successful (token: ${VAULT_TOKEN:0:20}...)"
    export VAULT_TOKEN
}

#######################################
# Fetches database credentials and TLS configuration from Vault
# Uses the token obtained via AppRole authentication
#######################################
fetch_credentials() {
    info "Fetching credentials and TLS setting from Vault..."

    local response=$(curl -sf \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/$SERVICE_NAME" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        error "Failed to fetch credentials from Vault"
    fi

    # Parse JSON using grep/sed (no jq required)
    export MYSQL_ROOT_PASSWORD=$(echo "$response" | grep -o '"root_password":"[^"]*"' | cut -d'"' -f4)
    export MYSQL_USER=$(echo "$response" | grep -o '"user":"[^"]*"' | cut -d'"' -f4)
    export MYSQL_PASSWORD=$(echo "$response" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)
    export MYSQL_DATABASE=$(echo "$response" | grep -o '"database":"[^"]*"' | cut -d'"' -f4)

    # Extract tls_enabled (default to false if not present)
    local tls_value=$(echo "$response" | grep -o '"tls_enabled":[^,}]*' | cut -d':' -f2 | tr -d ' "')
    export ENABLE_TLS="${tls_value:-false}"

    if [ -z "$MYSQL_ROOT_PASSWORD" ] || [ "$MYSQL_ROOT_PASSWORD" = "null" ]; then
        error "Invalid credentials received from Vault"
    fi

    success "Credentials fetched successfully (tls_enabled=$ENABLE_TLS)"
}

#######################################
# Validates that required TLS certificates exist and are readable
#######################################
validate_certificates() {
    if [ "$ENABLE_TLS" != "true" ]; then
        info "TLS disabled (tls_enabled=false in Vault), skipping certificate validation"
        return 0
    fi

    info "Validating pre-generated TLS certificates..."

    # Check if certificates exist and are readable
    if [ ! -f "$CERT_DIR/server-cert.pem" ] || [ ! -r "$CERT_DIR/server-cert.pem" ]; then
        error "TLS enabled but server-cert.pem not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    if [ ! -f "$CERT_DIR/server-key.pem" ] || [ ! -r "$CERT_DIR/server-key.pem" ]; then
        error "TLS enabled but server-key.pem not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    if [ ! -f "$CERT_DIR/ca.pem" ] || [ ! -r "$CERT_DIR/ca.pem" ]; then
        error "TLS enabled but ca.pem not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    success "TLS certificates validated (pre-generated)"
}

#######################################
# Configures MySQL SSL/TLS via configuration file
#######################################
configure_tls() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return 0
    fi

    info "Configuring MySQL for TLS (dual-mode: accepts both SSL and non-SSL)..."

    # Create custom MySQL configuration for TLS
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

    success "TLS dual-mode configuration prepared (accepts both SSL and non-SSL connections)"
}

#######################################
# Main initialization orchestration function
#######################################
main() {
    info "Starting MySQL initialization with Vault AppRole integration..."
    info ""

    # Wait for Vault
    wait_for_vault

    # Read AppRole credentials from mounted volume
    read_approle_credentials

    # Authenticate to Vault using AppRole
    authenticate_approle

    # Fetch credentials and TLS setting from Vault
    fetch_credentials

    # Validate pre-generated certificates if TLS is enabled
    validate_certificates

    # Configure TLS if enabled
    configure_tls

    info ""
    success "Initialization complete, starting MySQL..."
    info ""

    # Start MySQL with the original docker-entrypoint
    exec docker-entrypoint.sh "$@"
}

# Run main function
main "$@"
