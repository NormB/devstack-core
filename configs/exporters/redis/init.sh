#!/bin/sh
################################################################################
# Redis Exporter Initialization Script with Vault Integration
################################################################################
# This script initializes the Redis Exporter by fetching Redis credentials from
# HashiCorp Vault and starting the exporter with the retrieved password. The
# exporter collects Redis metrics and exposes them in Prometheus format.
#
# The script performs the following operations:
# 1. Validates required environment variables (VAULT_TOKEN)
# 2. Waits for Vault service to become ready and responsive
# 3. Fetches Redis password from Vault KV store
# 4. Exports password as REDIS_PASSWORD environment variable
# 5. Starts redis_exporter with fetched credentials
#
# GLOBALS:
#   VAULT_ADDR     - Vault server address (default: http://vault:8200)
#   VAULT_TOKEN    - Authentication token for Vault (required)
#   REDIS_NODE     - Name of the Redis service node (default: redis-1)
#   REDIS_PASSWORD - Redis password fetched from Vault (exported)
#   RED, GREEN, BLUE, NC - ANSI color codes for terminal output
#
# USAGE:
#   init.sh [redis_exporter-arguments]
#
#   Environment variables required:
#     VAULT_TOKEN - Vault authentication token
#
#   Environment variables optional:
#     VAULT_ADDR - Vault server URL (default: http://vault:8200)
#     REDIS_NODE - Service name in Vault (default: redis-1)
#
# DEPENDENCIES:
#   - wget           - For HTTP requests to Vault API
#   - grep, cut      - For JSON parsing without jq
#   - redis_exporter - Redis exporter binary (at /redis_exporter)
#
# EXIT CODES:
#   0 - Success (script replaces itself with redis_exporter via exec)
#   1 - Error (missing VAULT_TOKEN, Vault unavailable, invalid credentials)
#
# NOTES:
#   - This script uses 'exec' to replace itself with redis_exporter, so it
#     never exits normally with code 0
#   - Parses JSON using grep/sed instead of jq to avoid additional dependencies
#   - Password is fetched from Vault path: secret/data/$REDIS_NODE
#   - Maximum wait time for Vault: 120 seconds (60 attempts × 2 seconds)
#   - REDIS_PASSWORD is exported for redis_exporter to use
#
# EXAMPLES:
#   # Basic usage for redis-1 exporter
#   export VAULT_TOKEN=hvs.xxxxx
#   ./init.sh
#
#   # For a different Redis node
#   export VAULT_TOKEN=hvs.xxxxx
#   export REDIS_NODE=redis-2
#   ./init.sh
#
#   # With custom Vault address
#   export VAULT_TOKEN=hvs.xxxxx
#   export VAULT_ADDR=https://vault.example.com:8200
#   export REDIS_NODE=redis-3
#   ./init.sh
################################################################################

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-}"
VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-}"
REDIS_NODE="${REDIS_NODE:-redis-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print informational message to stdout
# Globals:
#   BLUE - ANSI color code for blue text
#   NC - ANSI color code to reset colors
# Arguments:
#   $1 - Message to print
# Returns:
#   0 - Always successful
# Outputs:
#   Writes formatted info message to stdout
#######################################
info() { echo -e "${BLUE}[Redis Exporter]${NC} $1"; }

#######################################
# Print success message to stdout
# Globals:
#   GREEN - ANSI color code for green text
#   NC - ANSI color code to reset colors
# Arguments:
#   $1 - Message to print
# Returns:
#   0 - Always successful
# Outputs:
#   Writes formatted success message to stdout
#######################################
success() { echo -e "${GREEN}[Redis Exporter]${NC} $1"; }

#######################################
# Print error message and exit script
# Globals:
#   RED - ANSI color code for red text
#   NC - ANSI color code to reset colors
# Arguments:
#   $1 - Error message to print
# Returns:
#   Never returns (exits with code 1)
# Outputs:
#   Writes formatted error message to stdout, then exits
#######################################
error() { echo -e "${RED}[Redis Exporter]${NC} $1"; exit 1; }

#######################################
# Wait for Vault service to become ready and responsive
# Polls the Vault health endpoint until it responds successfully or timeout
# is reached. Maximum wait time is 120 seconds (60 attempts × 2 seconds).
# Globals:
#   VAULT_ADDR - Vault server address to check
# Arguments:
#   None
# Returns:
#   0 - Vault is ready and responding
#   1 - Vault did not become ready within timeout (via error function)
# Outputs:
#   Writes status messages to stdout during polling
# Notes:
#   - Uses wget --spider for non-invasive HTTP HEAD-like request
#   - Checks /v1/sys/health endpoint with standbyok=true parameter
#   - Sleep interval: 2 seconds between attempts
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
# Login to Vault with AppRole credentials
# Sets VAULT_TOKEN global variable
#######################################
login_with_approle() {
    info "Authenticating with Vault using AppRole..."

    if [ ! -d "$VAULT_APPROLE_DIR" ]; then
        error "AppRole directory not found: $VAULT_APPROLE_DIR"
    fi

    local role_id_file="$VAULT_APPROLE_DIR/role-id"
    local secret_id_file="$VAULT_APPROLE_DIR/secret-id"

    if [ ! -f "$role_id_file" ] || [ ! -f "$secret_id_file" ]; then
        error "AppRole credentials not found in $VAULT_APPROLE_DIR"
    fi

    local role_id secret_id
    role_id=$(cat "$role_id_file")
    secret_id=$(cat "$secret_id_file")

    if [ -z "$role_id" ] || [ -z "$secret_id" ]; then
        error "Empty AppRole credentials"
    fi

    # Login with AppRole
    local response
    response=$(wget -qO- \
        --header "Content-Type: application/json" \
        --post-data "{\"role_id\":\"$role_id\",\"secret_id\":\"$secret_id\"}" \
        "$VAULT_ADDR/v1/auth/approle/login" 2>/dev/null) || {
        error "AppRole login failed"
    }

    # Parse token from response using grep/cut (no jq dependency)
    VAULT_TOKEN=$(echo "$response" | grep -o '"client_token":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$VAULT_TOKEN" ]; then
        error "Failed to obtain token from AppRole login"
    fi

    success "Successfully authenticated with AppRole"
}

#######################################
# Fetch Redis password from Vault KV store
# Retrieves password from Vault and exports it as REDIS_PASSWORD environment
# variable for redis_exporter to use. Parses JSON response using grep/cut.
# Globals:
#   VAULT_ADDR - Vault server address
#   VAULT_TOKEN - Vault authentication token
#   REDIS_NODE - Service name used as Vault secret path
#   REDIS_PASSWORD - Set to password from Vault (modified, exported)
# Arguments:
#   None
# Returns:
#   0 - Password successfully fetched and validated
#   1 - Failed to fetch or parse password (via error function)
# Outputs:
#   Writes status messages to stdout
# Notes:
#   - Fetches from Vault path: /v1/secret/data/$REDIS_NODE
#   - Uses grep and cut for JSON parsing (no jq dependency)
#   - Expects JSON response with "password" field
#   - Validates password is non-empty and not null
#   - REDIS_PASSWORD is exported for redis_exporter to use
#######################################
fetch_credentials() {
    info "Fetching credentials from Vault (service: $REDIS_NODE)..."

    local response=$(wget -qO- \
        --header "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/$REDIS_NODE" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        error "Failed to fetch credentials from Vault"
    fi

    # Parse JSON using grep/sed (no jq required)
    export REDIS_PASSWORD=$(echo "$response" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)

    if [ -z "$REDIS_PASSWORD" ] || [ "$REDIS_PASSWORD" = "null" ]; then
        error "Invalid password received from Vault"
    fi

    success "Credentials fetched successfully"
}

#######################################
# Main execution function - orchestrates Redis Exporter initialization
# Validates environment variables, waits for Vault, fetches Redis credentials,
# and starts redis_exporter with the retrieved password.
# Globals:
#   VAULT_TOKEN - Vault authentication token (read, validated)
#   REDIS_PASSWORD - Redis password (read, set by fetch_credentials)
# Arguments:
#   $@ - Arguments passed to redis_exporter
# Returns:
#   Never returns - replaces process with redis_exporter via exec
#   1 - Error during initialization (via error function)
# Outputs:
#   Writes initialization status messages to stdout
# Notes:
#   - Uses 'exec' to replace shell process with redis_exporter
#   - REDIS_PASSWORD is exported by fetch_credentials for exporter to use
#   - redis_exporter binary expected at /redis_exporter
#   - Execution flow: validate env vars → wait for Vault → fetch credentials
#     → exec redis_exporter
#######################################
main() {
    info "Starting Redis Exporter initialization with Vault integration..."

    # Wait for Vault
    wait_for_vault

    # Authenticate with Vault (AppRole or token)
    if [ -n "$VAULT_APPROLE_DIR" ] && [ -d "$VAULT_APPROLE_DIR" ]; then
        login_with_approle
    elif [ -n "$VAULT_TOKEN" ]; then
        info "Using provided VAULT_TOKEN for authentication"
    else
        error "Either VAULT_APPROLE_DIR or VAULT_TOKEN must be provided"
    fi

    # Fetch password from Vault
    fetch_credentials

    success "Initialization complete, starting redis_exporter..."
    info ""

    # Start redis_exporter with the password from Vault
    exec /redis_exporter "$@"
}

# Run main function
main "$@"
