#!/bin/bash
################################################################################
# Forgejo Initialization Script with Vault Integration
################################################################################
# This script initializes Forgejo by fetching PostgreSQL credentials from
# HashiCorp Vault and configuring the database connection via app.ini.
#
# GLOBALS:
#   VAULT_ADDR                - Vault server address (default: http://vault:8200)
#   VAULT_TOKEN               - Authentication token for Vault (required)
#   FORGEJO__database__DB_TYPE - Database type (default: postgres)
#   FORGEJO__database__HOST   - Database host (default: postgres:5432)
#   FORGEJO__database__NAME   - Database name (default: forgejo)
#   FORGEJO__server__DOMAIN   - Server domain (default: localhost)
#   FORGEJO__server__ROOT_URL - Server root URL
#
# EXIT CODES:
#   0 - Success (script replaces itself with Forgejo)
#   1 - Error (missing variables, Vault unavailable, etc.)
#
# EXAMPLES:
#   export VAULT_TOKEN=hvs.xxxxx
#   ./init.sh
################################################################################

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[Forgejo Init]${NC} $1"; }
success() { echo -e "${GREEN}[Forgejo Init]${NC} $1"; }
warn() { echo -e "${YELLOW}[Forgejo Init]${NC} $1"; }
error() { echo -e "${RED}[Forgejo Init]${NC} $1"; exit 1; }

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
# Fetch PostgreSQL credentials from Vault
#######################################
fetch_credentials() {
    info "Fetching PostgreSQL credentials from Vault..."

    local response
    response=$(wget -qO- \
        --header "X-Vault-Token: $VAULT_TOKEN" \
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
    info "Starting Forgejo initialization with Vault integration..."
    info ""

    # Check required environment variables and validate token format
    if [ -z "$VAULT_TOKEN" ]; then
        error "VAULT_TOKEN environment variable is required"
    fi

    if [ ${#VAULT_TOKEN} -lt 20 ]; then
        error "VAULT_TOKEN must be at least 20 characters (current: ${#VAULT_TOKEN} chars)"
    fi

    # Wait for Vault
    wait_for_vault

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
