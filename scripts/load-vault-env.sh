#!/bin/bash
#######################################
# Load environment variables from HashiCorp Vault
#
# This script reads secrets from Vault and exports them as environment variables
# for use by docker-compose. This eliminates the need for plaintext passwords in
# .env files, improving security and enabling centralized secret management.
#
# The script must be sourced (not executed) to export variables to the parent shell.
#
# Globals:
#   VAULT_ADDR - Vault server address (default: http://localhost:8200)
#   VAULT_TOKEN - Vault authentication token (auto-loaded from ~/.config/vault/root-token)
#   POSTGRES_PASSWORD - Exported PostgreSQL password from Vault
#
# Environment Variables Set:
#   VAULT_TOKEN - Vault authentication token
#   VAULT_ADDR - Vault server address
#   POSTGRES_PASSWORD - PostgreSQL admin password
#
# Usage:
#   source scripts/load-vault-env.sh
#   docker compose up -d
#
# Example:
#   $ source scripts/load-vault-env.sh
#   [Vault Env] Loading environment variables from Vault...
#   [Vault Env] Vault is accessible at http://localhost:8200
#   [Vault Env] PostgreSQL password loaded from Vault
#   $ docker compose up -d
#
# Dependencies:
#   - curl (for Vault API requests)
#   - jq (for JSON parsing)
#
# Exit Codes:
#   1 - Cannot connect to Vault or read secrets
#
# Notes:
#   - Script will exit with error if executed instead of sourced
#   - VAULT_TOKEN is auto-loaded from ~/.config/vault/root-token if not set
#   - Additional secrets can be added in main() function
#######################################

set -e

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print info message in blue
# Globals:
#   BLUE, NC
# Arguments:
#   Message to print
# Outputs:
#   Writes formatted message to stdout
#######################################
info() { echo -e "${BLUE}[Vault Env]${NC} $1"; }

#######################################
# Print success message in green
# Globals:
#   GREEN, NC
# Arguments:
#   Message to print
# Outputs:
#   Writes formatted message to stdout
#######################################
success() { echo -e "${GREEN}[Vault Env]${NC} $1"; }

#######################################
# Print warning message in yellow
# Globals:
#   YELLOW, NC
# Arguments:
#   Message to print
# Outputs:
#   Writes formatted message to stdout
#######################################
warn() { echo -e "${YELLOW}[Vault Env]${NC} $1"; }

#######################################
# Print error message in red
# Globals:
#   RED, NC
# Arguments:
#   Message to print
# Outputs:
#   Writes formatted message to stdout
#######################################
error() { echo -e "${RED}[Vault Env]${NC} $1"; }

#######################################
# Check if Vault is accessible and load token if needed
# Globals:
#   VAULT_ADDR - Vault server address
#   VAULT_TOKEN - Vault authentication token (exported if loaded from file)
# Arguments:
#   None
# Returns:
#   0 if Vault is accessible, 1 otherwise
# Outputs:
#   Status messages to stdout
# Notes:
#   - Attempts to load VAULT_TOKEN from ~/.config/vault/root-token if not set
#   - Uses curl to check Vault health endpoint
#######################################
check_vault() {
    local vault_addr="${VAULT_ADDR:-http://localhost:8200}"
    local vault_token="${VAULT_TOKEN:-}"

    if [ -z "$vault_token" ]; then
        # Try to read from file
        local token_file="$HOME/.config/vault/root-token"
        if [ -f "$token_file" ]; then
            vault_token=$(cat "$token_file")
            export VAULT_TOKEN="$vault_token"
            info "Loaded VAULT_TOKEN from $token_file"
        else
            error "VAULT_TOKEN not set and $token_file not found"
            return 1
        fi
    fi

    # Check if Vault is accessible
    if ! curl -sf -H "X-Vault-Token: $vault_token" "$vault_addr/v1/sys/health" > /dev/null 2>&1; then
        error "Vault is not accessible at $vault_addr"
        return 1
    fi

    success "Vault is accessible at $vault_addr"
}

#######################################
# Read a secret field from Vault using native curl + jq
# Globals:
#   VAULT_TOKEN - Vault authentication token
#   VAULT_ADDR - Vault server address
# Arguments:
#   $1 - Secret path in Vault (e.g., 'postgres')
#   $2 - Field name within secret (e.g., 'password')
# Returns:
#   0 on success, 1 on failure
# Outputs:
#   Secret value to stdout
# Notes:
#   - Uses Vault KV v2 API endpoint: /v1/secret/data/{path}
#   - Requires jq for JSON parsing
#######################################
read_vault_secret() {
    local path="$1"
    local field="$2"
    local vault_addr="${VAULT_ADDR:-http://localhost:8200}"
    local vault_token="${VAULT_TOKEN:-}"

    # Fetch secret from Vault and extract specific field
    local value=$(curl -sf -H "X-Vault-Token: $vault_token" \
        "$vault_addr/v1/secret/data/$path" | \
        jq -r ".data.data.${field}" 2>/dev/null)

    if [ "$value" == "null" ] || [ -z "$value" ]; then
        return 1
    fi

    echo "$value"
}

#######################################
# Main function - Load all required secrets from Vault
# Globals:
#   POSTGRES_PASSWORD - Exported PostgreSQL password
# Arguments:
#   None
# Returns:
#   0 on success, 1 if any secret fails to load
# Outputs:
#   Status messages to stdout
# Notes:
#   - Add additional secrets by calling read_vault_secret()
#   - Each secret should be validated before export
#   - All secrets are exported for use by docker-compose
#######################################
main() {
    info "Loading environment variables from Vault..."
    info ""

    # Check Vault accessibility
    if ! check_vault; then
        error "Failed to connect to Vault"
        return 1
    fi

    # Read PostgreSQL password from Vault
    info "Reading PostgreSQL credentials from Vault..."
    POSTGRES_PASSWORD=$(read_vault_secret postgres password)
    if [ -z "$POSTGRES_PASSWORD" ]; then
        error "Failed to read PostgreSQL password from Vault"
        return 1
    fi
    export POSTGRES_PASSWORD
    success "PostgreSQL password loaded from Vault"

    # Read MySQL password from Vault
    info "Reading MySQL credentials from Vault..."
    MYSQL_ROOT_PASSWORD=$(read_vault_secret mysql password)
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        error "Failed to read MySQL password from Vault"
        return 1
    fi
    export MYSQL_ROOT_PASSWORD
    success "MySQL password loaded from Vault"

    info ""
    success "All secrets loaded from Vault"
    info ""
    info "You can now run: docker compose up -d"
    info ""
}

# Only run main if script is sourced (not executed)
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    error "This script must be sourced, not executed"
    error "Usage: source $0"
    exit 1
fi

main
