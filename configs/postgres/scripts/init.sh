#!/bin/bash
#######################################
# PostgreSQL Initialization Script with Vault Integration
#
# This script orchestrates the secure initialization of PostgreSQL by integrating
# with HashiCorp Vault for credential management and TLS certificate validation.
# It supports dual-mode TLS configuration (accepting both SSL and non-SSL connections).
#
# DESCRIPTION:
#   Initializes PostgreSQL with credentials and configuration fetched from Vault.
#   The script waits for Vault availability, retrieves database credentials and
#   TLS settings, validates pre-generated certificates if TLS is enabled, configures
#   PostgreSQL SSL parameters, and starts the database server with appropriate
#   security settings.
#
# GLOBALS:
#   VAULT_ADDR - Vault server address (default: http://vault:8200)
#   VAULT_TOKEN - Authentication token for Vault API access (required)
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
#   VAULT_TOKEN=<token> ./init.sh [postgres_args...]
#
#   Example:
#     VAULT_TOKEN=hvs.CAESIJ... ./init.sh postgres
#     VAULT_TOKEN=hvs.CAESIJ... VAULT_ADDR=http://vault:8200 ./init.sh postgres
#
# DEPENDENCIES:
#   - curl: For Vault health checks and API requests
#   - jq: For JSON parsing (auto-installed if missing)
#   - docker-entrypoint.sh: PostgreSQL official entrypoint script
#   - HashiCorp Vault: Must be accessible and unsealed
#   - Pre-generated TLS certificates: Required when tls_enabled=true in Vault
#
# EXIT CODES:
#   0 - Successful initialization and PostgreSQL startup
#   1 - Vault connection failure or timeout
#   1 - Missing required VAULT_TOKEN environment variable
#   1 - Invalid or missing credentials from Vault
#   1 - TLS certificate validation failure
#   1 - Configuration errors
#
# NOTES:
#   - The script uses 'set -e' for fail-fast behavior
#   - Maximum Vault readiness wait time: 120 seconds (60 attempts x 2s)
#   - TLS mode is "dual-mode": accepts both SSL and non-SSL connections
#   - Certificates must be pre-generated using scripts/generate-certificates.sh
#   - Certificate permissions are validated before use
#   - PostgreSQL is started with ssl=on and ssl_prefer_server_ciphers=on when TLS enabled
#   - Minimum TLS version enforced: TLSv1.2
#   - The script delegates to docker-entrypoint.sh after initialization
#
# EXAMPLES:
#   # Basic usage with TLS disabled
#   VAULT_TOKEN=hvs.CAESIJ... ./init.sh postgres
#
#   # Usage with TLS enabled (requires pre-generated certificates)
#   VAULT_TOKEN=hvs.CAESIJ... ./init.sh postgres
#
#   # Custom Vault address
#   VAULT_TOKEN=hvs.CAESIJ... VAULT_ADDR=https://vault.example.com:8200 ./init.sh postgres
#
#   # With custom PostgreSQL IP
#   VAULT_TOKEN=hvs.CAESIJ... POSTGRES_IP=192.168.1.10 ./init.sh postgres
#
# AUTHORS:
#   DevStack Core Team
#
# VERSION:
#   1.0.0
#
#######################################

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_TOKEN="${VAULT_TOKEN}"
SERVICE_NAME="postgres"
SERVICE_IP="${POSTGRES_IP:-172.20.0.10}"
CERT_DIR="/var/lib/postgresql/certs"
ENABLE_TLS=""  # Will be read from Vault
TLS_CONFIG_DIR="/tmp/postgres-tls"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Prints informational message to stdout
# Globals:
#   BLUE - ANSI color code for blue text
#   NC - ANSI color code to reset formatting
# Arguments:
#   $1 - Message string to display
# Returns:
#   None
# Outputs:
#   Writes formatted message to stdout
#######################################
info() { echo -e "${BLUE}[PostgreSQL Init]${NC} $1"; }

#######################################
# Prints success message to stdout
# Globals:
#   GREEN - ANSI color code for green text
#   NC - ANSI color code to reset formatting
# Arguments:
#   $1 - Message string to display
# Returns:
#   None
# Outputs:
#   Writes formatted success message to stdout
#######################################
success() { echo -e "${GREEN}[PostgreSQL Init]${NC} $1"; }

#######################################
# Prints warning message to stdout
# Globals:
#   YELLOW - ANSI color code for yellow text
#   NC - ANSI color code to reset formatting
# Arguments:
#   $1 - Message string to display
# Returns:
#   None
# Outputs:
#   Writes formatted warning message to stdout
#######################################
warn() { echo -e "${YELLOW}[PostgreSQL Init]${NC} $1"; }

#######################################
# Prints error message to stderr and exits with code 1
# Globals:
#   RED - ANSI color code for red text
#   NC - ANSI color code to reset formatting
# Arguments:
#   $1 - Error message string to display
# Returns:
#   1 - Always exits with code 1
# Outputs:
#   Writes formatted error message to stdout and terminates script
#######################################
error() { echo -e "${RED}[PostgreSQL Init]${NC} $1"; exit 1; }

#######################################
# Waits for Vault service to become available and ready
# Polls the Vault health endpoint until it responds successfully or timeout occurs.
# Uses standbyok=true to accept standby nodes as ready.
# Globals:
#   VAULT_ADDR - Vault server URL to check
# Arguments:
#   None
# Returns:
#   0 - Vault is ready and accessible
#   1 - Vault did not become ready within timeout period
# Outputs:
#   Status messages via info(), success(), and error() functions
# Notes:
#   - Maximum wait time: 120 seconds (60 attempts * 2 seconds)
#   - Checks Vault health endpoint: $VAULT_ADDR/v1/sys/health?standbyok=true
#   - Uses curl for lightweight health checks
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
# Fetches database credentials and TLS configuration from Vault
# Retrieves PostgreSQL credentials and TLS enablement flag from Vault's KV v2
# secrets engine and exports them as environment variables.
# Globals:
#   VAULT_ADDR - Vault server URL
#   VAULT_TOKEN - Authentication token for Vault API
#   SERVICE_NAME - Service identifier (postgres) for secrets path
#   POSTGRES_USER - Exported database username
#   POSTGRES_PASSWORD - Exported database password
#   POSTGRES_DB - Exported default database name
#   ENABLE_TLS - Exported TLS enablement flag (true/false)
# Arguments:
#   None
# Returns:
#   0 - Credentials fetched and exported successfully
#   1 - Failed to fetch credentials or received invalid data
# Outputs:
#   Status messages via info(), success(), and error() functions
# Notes:
#   - Accesses Vault path: /v1/secret/data/$SERVICE_NAME
#   - Uses jq for JSON parsing of Vault response
#   - Validates that username is not null or empty
#   - Defaults tls_enabled to false if not present in Vault
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
# Checks for the presence and accessibility of pre-generated SSL/TLS certificates
# required for PostgreSQL secure connections. Skips validation if TLS is disabled.
# Globals:
#   ENABLE_TLS - Flag indicating whether TLS is enabled
#   CERT_DIR - Directory path where certificates should be located
# Arguments:
#   None
# Returns:
#   0 - TLS disabled or all certificates validated successfully
#   1 - TLS enabled but required certificates missing or unreadable
# Outputs:
#   Status messages via info(), success(), and error() functions
# Notes:
#   - Required certificates: server.crt, server.key, ca.crt
#   - Certificates must be pre-generated using scripts/generate-certificates.sh
#   - Checks both file existence (-f) and read permissions (-r)
#   - Exits with error if TLS enabled but certificates unavailable
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
# Sets up environment variables for PostgreSQL TLS configuration when TLS is enabled.
# These variables control SSL certificate paths and protocol settings for dual-mode operation.
# Globals:
#   ENABLE_TLS - Flag indicating whether TLS is enabled
#   CERT_DIR - Directory path containing certificates
#   POSTGRES_SSL - Exported SSL mode flag (set to "on")
#   POSTGRES_SSL_CERT_FILE - Exported path to server certificate
#   POSTGRES_SSL_KEY_FILE - Exported path to server private key
#   POSTGRES_SSL_CA_FILE - Exported path to CA certificate
#   POSTGRES_SSL_MIN_PROTOCOL_VERSION - Exported minimum TLS version
# Arguments:
#   None
# Returns:
#   0 - Always successful
# Outputs:
#   Status messages via info() and success() functions
# Notes:
#   - Only configures when ENABLE_TLS=true, otherwise returns immediately
#   - Sets minimum TLS protocol version to TLSv1.2
#   - Environment variables are passed to PostgreSQL via command line options
#   - Dual-mode configuration accepts both SSL and non-SSL connections
#######################################
configure_tls() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return 0
    fi

    info "Configuring PostgreSQL for TLS (dual-mode: accepts both SSL and non-SSL)..."

    # Set environment variables for TLS config
    # These will be passed to postgres via command line options
    export POSTGRES_SSL="on"
    export POSTGRES_SSL_CERT_FILE="$CERT_DIR/server.crt"
    export POSTGRES_SSL_KEY_FILE="$CERT_DIR/server.key"
    export POSTGRES_SSL_CA_FILE="$CERT_DIR/ca.crt"
    export POSTGRES_SSL_MIN_PROTOCOL_VERSION="TLSv1.2"

    success "TLS configuration environment variables set"
}

#######################################
# Main initialization orchestration function
# Coordinates the complete PostgreSQL initialization workflow including dependency
# installation, credential fetching, certificate validation, TLS configuration,
# and PostgreSQL startup with appropriate security settings.
# Globals:
#   VAULT_TOKEN - Required authentication token (validated)
#   ENABLE_TLS - TLS enablement flag (set by fetch_credentials)
#   All globals used by called functions
# Arguments:
#   $@ - Command line arguments passed to PostgreSQL (forwarded to docker-entrypoint.sh)
# Returns:
#   0 - Successful initialization (never returns as exec replaces process)
#   1 - Initialization failures (via error() calls in sub-functions)
# Outputs:
#   Initialization progress messages via info() and success() functions
# Notes:
#   - Validates VAULT_TOKEN environment variable is set
#   - Auto-installs jq if not present (required for JSON parsing)
#   - Calls functions in sequence: wait_for_vault -> fetch_credentials ->
#     validate_certificates -> configure_tls
#   - Executes PostgreSQL with exec (replaces current process)
#   - TLS mode: Passes SSL configuration via command line when ENABLE_TLS=true
#   - Non-TLS mode: Starts PostgreSQL without SSL configuration
#   - SSL cipher suite: HIGH:MEDIUM:+3DES:!aNULL
#   - SSL server ciphers preferred when TLS enabled
#######################################
main() {
    info "Starting PostgreSQL initialization with Vault integration..."
    info ""

    # Install required tools if not present
    if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
        info "Installing curl and jq..."
        apt-get update > /dev/null 2>&1 && apt-get install -y curl jq > /dev/null 2>&1
    fi

    # Check required environment variables and validate token format
    if [ -z "$VAULT_TOKEN" ]; then
        error "VAULT_TOKEN environment variable is required"
    fi

    if [ ${#VAULT_TOKEN} -lt 20 ]; then
        error "VAULT_TOKEN must be at least 20 characters (current: ${#VAULT_TOKEN} chars)"
    fi

    # Wait for Vault
    wait_for_vault

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
