#!/bin/bash
################################################################################
# Forgejo Initialization Script with Vault AppRole Integration
################################################################################
# This script initializes Forgejo by authenticating to Vault using AppRole,
# fetching PostgreSQL credentials, and configuring the database connection.
#
# DESCRIPTION:
#   Initializes Forgejo with credentials fetched from Vault using AppRole
#   authentication. The script authenticates via AppRole (role_id + secret_id),
#   obtains a temporary token, retrieves PostgreSQL credentials, and configures
#   Forgejo's database connection via environment variables.
#
# GLOBALS:
#   VAULT_ADDR                - Vault server address (default: http://vault:8200)
#   VAULT_APPROLE_DIR         - Directory containing AppRole credentials (default: /vault-approles/forgejo)
#   VAULT_TOKEN               - Temporary token (obtained via AppRole auth)
#   FORGEJO__database__DB_TYPE - Database type (default: postgres)
#   FORGEJO__database__HOST   - Database host (default: postgres:5432)
#   FORGEJO__database__NAME   - Database name (default: forgejo)
#   FORGEJO__server__DOMAIN   - Server domain (default: localhost)
#   FORGEJO__server__ROOT_URL - Server root URL
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for output formatting
#
# USAGE:
#   ./init-approle.sh [forgejo_args...]
#
#   Example:
#     ./init-approle.sh
#     VAULT_ADDR=http://vault:8200 ./init-approle.sh
#
# DEPENDENCIES:
#   - wget: For Vault health checks and API requests
#   - jq: For JSON parsing (auto-installed if missing via apk)
#   - /usr/bin/entrypoint: Forgejo original entrypoint
#   - HashiCorp Vault: Must be accessible and unsealed
#   - AppRole credentials: role-id and secret-id files in VAULT_APPROLE_DIR
#
# EXIT CODES:
#   0 - Success (script replaces itself with Forgejo)
#   1 - Error (missing AppRole credentials, Vault unavailable, etc.)
#
# NOTES:
#   - The script uses 'set -e' for fail-fast behavior
#   - Maximum Vault readiness wait time: 120 seconds (60 attempts x 2s)
#   - AppRole credentials are read from mounted volume at VAULT_APPROLE_DIR
#   - Token obtained from AppRole is temporary (1h TTL by default)
#   - Forgejo reads FORGEJO__database__USER and FORGEJO__database__PASSWD env vars
#   - Fetches PostgreSQL credentials from secret/postgres path in Vault
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
################################################################################

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/forgejo}"
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
info() { echo -e "${BLUE}[Forgejo Init]${NC} $1"; }

#######################################
# Prints success message to stdout
#######################################
success() { echo -e "${GREEN}[Forgejo Init]${NC} $1"; }

#######################################
# Prints warning message to stdout
#######################################
warn() { echo -e "${YELLOW}[Forgejo Init]${NC} $1"; }

#######################################
# Prints error message to stderr and exits with code 1
#######################################
error() { echo -e "${RED}[Forgejo Init]${NC} $1"; exit 1; }

#######################################
# Install jq if not present
#######################################
install_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        info "Installing jq..."
        apk add --no-cache jq >/dev/null 2>&1 || {
            error "Failed to install jq"
        }
        success "jq installed"
    fi
}

#######################################
# Wait for Vault service to become ready
#######################################
wait_for_vault() {
    info "Waiting for Vault to be ready..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if wget --spider -q "$VAULT_ADDR/v1/sys/health?standbyok=true" 2>/dev/null; then
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

    local auth_response
    auth_response=$(wget -qO- \
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

    success "AppRole authentication successful (token: ${VAULT_TOKEN:0:20}...)"
    export VAULT_TOKEN
}

#######################################
# Fetch PostgreSQL credentials from Vault
# Uses the token obtained via AppRole authentication
#######################################
fetch_credentials() {
    info "Fetching PostgreSQL credentials from Vault..."

    local response
    response=$(wget -qO- \
        --header="X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/postgres" 2>/dev/null) || {
        error "Failed to fetch credentials from Vault"
    }

    if [ -z "$response" ]; then
        error "Empty response from Vault"
    fi

    DB_USER=$(echo "$response" | jq -r '.data.data.user')
    DB_PASSWD=$(echo "$response" | jq -r '.data.data.password')

    if [ -z "$DB_USER" ] || [ "$DB_USER" = "null" ]; then
        error "Invalid username received from Vault"
    fi

    if [ -z "$DB_PASSWD" ] || [ "$DB_PASSWD" = "null" ]; then
        error "Invalid password received from Vault"
    fi

    success "Credentials fetched successfully"
}

#######################################
# Configure database credentials in app.ini
#######################################
configure_database() {
    info "Configuring database credentials..."

    # Forgejo reads environment variables and generates /data/gitea/conf/app.ini
    # We'll set environment variables for the original entrypoint to use
    export FORGEJO__database__USER="$DB_USER"
    export FORGEJO__database__PASSWD="$DB_PASSWD"

    success "Database configuration prepared"
}

#######################################
# Main execution function
#######################################
main() {
    info "Starting Forgejo initialization with Vault AppRole integration..."
    info ""

    # Install jq if needed
    install_jq

    # Wait for Vault
    wait_for_vault

    # Read AppRole credentials from mounted volume
    read_approle_credentials

    # Authenticate to Vault using AppRole
    authenticate_approle

    # Fetch credentials from Vault
    fetch_credentials

    # Configure database
    configure_database

    info ""
    success "Initialization complete, starting Forgejo..."
    info ""

    # Start Forgejo using original entrypoint
    # Pass through all original environment variables and command args
    exec /usr/bin/entrypoint "$@"
}

# Run main function
main "$@"
