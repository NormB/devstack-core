#!/bin/bash
#######################################
# PostgreSQL Initialization Script with Vault AppRole Integration
#
# This script orchestrates the secure initialization of PostgreSQL by integrating
# with HashiCorp Vault AppRole authentication for credential management and TLS
# certificate validation. It supports dual-mode TLS configuration.
#
# DESCRIPTION:
#   Initializes PostgreSQL with credentials fetched from Vault using AppRole
#   authentication. The script authenticates via AppRole (role_id + secret_id),
#   obtains a temporary token, retrieves database credentials and TLS settings,
#   validates pre-generated certificates if TLS is enabled, configures PostgreSQL
#   SSL parameters, and starts the database server with appropriate security settings.
#
# GLOBALS:
#   VAULT_ADDR - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR - Directory containing AppRole credentials (default: /vault-approles)
#   SERVICE_NAME - Service identifier for Vault secrets (set to "postgres")
#   SERVICE_IP - PostgreSQL service IP address (default: 172.20.0.10)
#   CERT_DIR - Directory containing TLS certificates (/var/lib/postgresql/certs)
#   ENABLE_TLS - TLS enablement flag (read from Vault)
#   TLS_CONFIG_DIR - Temporary directory for TLS configuration
#   POSTGRES_USER - Database username (exported from Vault)
#   POSTGRES_PASSWORD - Database password (exported from Vault)
#   POSTGRES_DB - Default database name (exported from Vault)
#   POSTGRES_SSL - SSL mode flag (exported when TLS enabled)
#   POSTGRES_SSL_CERT_FILE - Path to server certificate
#   POSTGRES_SSL_KEY_FILE - Path to server private key
#   POSTGRES_SSL_CA_FILE - Path to CA certificate
#   POSTGRES_SSL_MIN_PROTOCOL_VERSION - Minimum TLS version
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for output formatting
#
# USAGE:
#   ./init-approle.sh [postgres_args...]
#
#   Example:
#     ./init-approle.sh postgres
#     VAULT_ADDR=http://vault:8200 ./init-approle.sh postgres
#
# DEPENDENCIES:
#   - curl: For Vault health checks and API requests
#   - jq: For JSON parsing (auto-installed if missing)
#   - docker-entrypoint.sh: PostgreSQL official entrypoint script
#   - HashiCorp Vault: Must be accessible and unsealed
#   - AppRole credentials: role-id and secret-id files in VAULT_APPROLE_DIR
#   - Pre-generated TLS certificates: Required when tls_enabled=true in Vault
#
# EXIT CODES:
#   0 - Successful initialization and PostgreSQL startup
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
#   - PostgreSQL is started with ssl=on and ssl_prefer_server_ciphers=on when TLS enabled
#   - Minimum TLS version enforced: TLSv1.2
#   - The script delegates to docker-entrypoint.sh after initialization
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
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/postgres}"
SERVICE_NAME="postgres"
SERVICE_IP="${POSTGRES_IP:-172.20.0.10}"
CERT_DIR="/var/lib/postgresql/certs"
ENABLE_TLS=""  # Will be read from Vault
TLS_CONFIG_DIR="/tmp/postgres-tls"
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
info() { echo -e "${BLUE}[PostgreSQL Init]${NC} $1"; }

#######################################
# Prints success message to stdout
#######################################
success() { echo -e "${GREEN}[PostgreSQL Init]${NC} $1"; }

#######################################
# Prints warning message to stdout
#######################################
warn() { echo -e "${YELLOW}[PostgreSQL Init]${NC} $1"; }

#######################################
# Prints error message to stderr and exits with code 1
#######################################
error() { echo -e "${RED}[PostgreSQL Init]${NC} $1"; exit 1; }

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

    VAULT_TOKEN=$(echo "$auth_response" | jq -r '.auth.client_token')

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

    export POSTGRES_USER=$(echo "$response" | jq -r '.data.data.user')
    export POSTGRES_PASSWORD=$(echo "$response" | jq -r '.data.data.password')
    export POSTGRES_DB=$(echo "$response" | jq -r '.data.data.database')
    export ENABLE_TLS=$(echo "$response" | jq -r '.data.data.tls_enabled // "false"')

    if [ -z "$POSTGRES_USER" ] || [ "$POSTGRES_USER" = "null" ]; then
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
    if [ ! -f "$CERT_DIR/server.crt" ] || [ ! -r "$CERT_DIR/server.crt" ]; then
        error "TLS enabled but server.crt not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    if [ ! -f "$CERT_DIR/server.key" ] || [ ! -r "$CERT_DIR/server.key" ]; then
        error "TLS enabled but server.key not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    if [ ! -f "$CERT_DIR/ca.crt" ] || [ ! -r "$CERT_DIR/ca.crt" ]; then
        error "TLS enabled but ca.crt not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    success "TLS certificates validated (pre-generated)"
}

#######################################
# Configures PostgreSQL SSL/TLS environment variables
#######################################
configure_tls() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return 0
    fi

    info "Configuring PostgreSQL for TLS (dual-mode: accepts both SSL and non-SSL)..."

    # Set environment variables for TLS config
    export POSTGRES_SSL="on"
    export POSTGRES_SSL_CERT_FILE="$CERT_DIR/server.crt"
    export POSTGRES_SSL_KEY_FILE="$CERT_DIR/server.key"
    export POSTGRES_SSL_CA_FILE="$CERT_DIR/ca.crt"
    export POSTGRES_SSL_MIN_PROTOCOL_VERSION="TLSv1.2"

    success "TLS configuration environment variables set"
}

#######################################
# Main initialization orchestration function
#######################################
main() {
    info "Starting PostgreSQL initialization with Vault AppRole integration..."
    info ""

    # Install required tools if not present
    if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
        info "Installing curl and jq..."
        apt-get update > /dev/null 2>&1 && apt-get install -y curl jq > /dev/null 2>&1
    fi

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
    success "Initialization complete, starting PostgreSQL..."
    info ""

    # Start PostgreSQL with the original docker-entrypoint
    # Pass TLS configuration via command line if enabled
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

# Run main function
main "$@"
