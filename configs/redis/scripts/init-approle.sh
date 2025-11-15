#!/bin/sh
################################################################################
# Redis Initialization Script with Vault AppRole Integration
################################################################################
# This script initializes a Redis instance by authenticating to Vault using
# AppRole, fetching credentials and TLS configuration, validating pre-generated
# certificates if TLS is enabled, and starting Redis with the appropriate
# configuration.
#
# DESCRIPTION:
#   Initializes Redis with credentials fetched from Vault using AppRole
#   authentication. The script authenticates via AppRole (role_id + secret_id),
#   obtains a temporary token, retrieves Redis password and TLS settings,
#   validates pre-generated certificates if TLS is enabled, and starts Redis
#   with appropriate security settings. Supports dynamic Redis cluster sizing
#   (1-3 nodes based on service profile).
#
# GLOBALS:
#   VAULT_ADDR      - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR - Directory containing AppRole credentials (default: /vault-approles/redis)
#   REDIS_NODE      - Name of the Redis service node (default: redis-1)
#   REDIS_IP        - IP address of the Redis instance (required)
#   REDIS_PORT      - Redis standard port (default: 6379)
#   REDIS_TLS_PORT  - Redis TLS port (default: 6380)
#   SERVICE_NAME    - Resolved service name from REDIS_NODE (always redis-1 for shared creds)
#   SERVICE_IP      - Resolved IP from REDIS_IP
#   PKI_ROLE        - Vault PKI role for certificate generation
#   CERT_DIR        - Directory containing TLS certificates
#   ENABLE_TLS      - Whether TLS is enabled (read from Vault)
#   REDIS_PASSWORD  - Redis password (fetched from Vault)
#   VAULT_TOKEN     - Temporary token obtained via AppRole auth
#   RED, GREEN, YELLOW, BLUE, NC - Color codes for terminal output
#
# USAGE:
#   init-approle.sh [redis-server-arguments]
#
#   Environment variables required:
#     REDIS_IP      - IP address for this Redis instance
#
#   Environment variables optional:
#     VAULT_ADDR    - Vault server URL (default: http://vault:8200)
#     VAULT_APPROLE_DIR - AppRole credentials directory (default: /vault-approles/redis)
#     REDIS_NODE    - Service name in Vault (default: redis-1)
#     REDIS_PORT    - Standard Redis port (default: 6379)
#     REDIS_TLS_PORT - TLS Redis port (default: 6380)
#
# DEPENDENCIES:
#   - wget          - For HTTP requests to Vault API
#   - jq            - For JSON parsing (auto-installed if missing)
#   - redis-server  - Redis server binary
#   - apk           - Alpine package manager (for jq installation)
#   - HashiCorp Vault: Must be accessible and unsealed
#   - AppRole credentials: role-id and secret-id files in VAULT_APPROLE_DIR
#
# EXIT CODES:
#   0 - Success (script replaces itself with redis-server via exec)
#   1 - Error (missing AppRole credentials, Vault unavailable, invalid
#       credentials, missing certificates, etc.)
#
# NOTES:
#   - This script uses 'exec' to replace itself with redis-server
#   - All Redis nodes (redis-1, redis-2, redis-3) share the same AppRole credentials
#   - All nodes fetch credentials from secret/redis-1 path in Vault
#   - AppRole credentials are read from mounted volume at VAULT_APPROLE_DIR
#   - Token obtained from AppRole is temporary (1h TTL by default)
#   - TLS certificates must be pre-generated using generate-certificates.sh
#   - The script supports dual-mode TLS: accepts both SSL and non-SSL connections
#   - Maximum wait time for Vault: 120 seconds (60 attempts × 2 seconds)
#   - Supports dynamic cluster sizing (1-3 nodes based on profile)
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
################################################################################

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/redis}"
REDIS_NODE_NAME="${REDIS_NODE:-redis-1}"  # For logging/identification only
SERVICE_NAME="redis-1"  # All nodes fetch credentials from secret/redis-1 (shared)
SERVICE_IP="${REDIS_IP}"
PKI_ROLE="redis-role"
CERT_DIR="/etc/redis/certs"
ENABLE_TLS=""  # Will be read from Vault
VAULT_TOKEN=""  # Will be obtained via AppRole auth

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print informational message to stdout
#######################################
info() { printf "${BLUE}[Redis Init]${NC} %s\n" "$1"; }

#######################################
# Print success message to stdout
#######################################
success() { printf "${GREEN}[Redis Init]${NC} %s\n" "$1"; }

#######################################
# Print warning message to stdout
#######################################
warn() { printf "${YELLOW}[Redis Init]${NC} %s\n" "$1"; }

#######################################
# Print error message and exit
#######################################
error() { printf "${RED}[Redis Init]${NC} %s\n" "$1"; exit 1; }

#######################################
# Install jq if not present
#######################################
install_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        info "Installing jq..."
        apk add --no-cache jq >/dev/null 2>&1
        success "jq installed"
    fi
}

#######################################
# Wait for Vault to become ready
#######################################
wait_for_vault() {
    info "Waiting for Vault to be ready..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if wget -q -O - "$VAULT_ADDR/v1/sys/health?standbyok=true" >/dev/null 2>&1; then
            success "Vault is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    error "Vault did not become ready in time"
}

#######################################
# Read AppRole credentials from mounted volume
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

    success "AppRole credentials loaded (role_id: ${ROLE_ID%%????????????????????????}...)"
}

#######################################
# Authenticate to Vault using AppRole and obtain a client token
# Returns:
#   0 - Authentication successful, token obtained
#   1 - Authentication failed or invalid response
# Outputs:
#   Sets VAULT_TOKEN environment variable with temporary client token
#######################################
authenticate_approle() {
    info "Authenticating to Vault with AppRole..."

    local auth_response
    auth_response=$(wget -q -O - \
        --header="Content-Type: application/json" \
        --post-data="{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
        "$VAULT_ADDR/v1/auth/approle/login" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$auth_response" ]; then
        error "Failed to authenticate with AppRole"
    fi

    VAULT_TOKEN=$(echo "$auth_response" | jq -r '.auth.client_token')

    if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" = "null" ]; then
        error "Failed to obtain token from AppRole authentication"
    fi

    success "AppRole authentication successful (token: ${VAULT_TOKEN%%????????????????????????}...)"
    export VAULT_TOKEN
}

#######################################
# Fetch credentials and TLS setting from Vault
# Uses the token obtained via AppRole authentication
#######################################
fetch_credentials() {
    info "Fetching credentials and TLS setting from Vault..."

    local response
    response=$(wget -q -O - \
        --header="X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/$SERVICE_NAME" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        error "Failed to fetch credentials from Vault"
    fi

    export REDIS_PASSWORD=$(echo "$response" | jq -r '.data.data.password')

    # Extract tls_enabled (default to false if not present)
    local tls_value=$(echo "$response" | jq -r '.data.data.tls_enabled // "false"')
    export ENABLE_TLS="$tls_value"

    if [ -z "$REDIS_PASSWORD" ] || [ "$REDIS_PASSWORD" = "null" ]; then
        error "Invalid credentials received from Vault"
    fi

    success "Credentials fetched successfully (tls_enabled=$ENABLE_TLS)"
}

#######################################
# Validate that required TLS certificates exist
#######################################
validate_certificates() {
    if [ "$ENABLE_TLS" != "true" ]; then
        info "TLS disabled (tls_enabled=false in Vault), skipping certificate validation"
        return 0
    fi

    info "Validating pre-generated TLS certificates..."

    # Check if certificates exist and are readable
    if [ ! -f "$CERT_DIR/redis.crt" ] || [ ! -r "$CERT_DIR/redis.crt" ]; then
        error "TLS enabled but redis.crt not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    if [ ! -f "$CERT_DIR/redis.key" ] || [ ! -r "$CERT_DIR/redis.key" ]; then
        error "TLS enabled but redis.key not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    if [ ! -f "$CERT_DIR/ca.crt" ] || [ ! -r "$CERT_DIR/ca.crt" ]; then
        error "TLS enabled but ca.crt not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    success "TLS certificates validated (pre-generated)"
}

#######################################
# Main initialization function
#######################################
main() {
    info "Starting Redis initialization with Vault AppRole integration..."
    info "Node: $REDIS_NODE_NAME, IP: $SERVICE_IP"
    info ""

    # Install jq if needed
    install_jq

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

    info ""
    success "Initialization complete, starting Redis..."
    info ""

    # Start Redis with password and TLS if enabled
    if [ "$ENABLE_TLS" = "true" ]; then
        info "TLS enabled, starting Redis with TLS configuration..."
        exec redis-server "$@" \
            --requirepass "$REDIS_PASSWORD" \
            --tls-port 6380 \
            --port 6379 \
            --tls-cert-file /etc/redis/certs/redis.crt \
            --tls-key-file /etc/redis/certs/redis.key \
            --tls-ca-cert-file /etc/redis/certs/ca.crt \
            --tls-auth-clients no
    else
        info "TLS disabled, starting Redis without TLS..."
        exec redis-server "$@" --requirepass "$REDIS_PASSWORD"
    fi
}

# Run main function
main "$@"
