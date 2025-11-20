#!/bin/bash
#######################################
# MySQL Initialization Script with Vault Integration
#
# This script orchestrates the secure initialization of MySQL by integrating
# with HashiCorp Vault for credential management and TLS certificate validation.
# It supports dual-mode TLS configuration (accepting both SSL and non-SSL connections).
#
# DESCRIPTION:
#   Initializes MySQL with credentials and configuration fetched from Vault.
#   The script waits for Vault availability, retrieves database credentials and
#   TLS settings, validates pre-generated certificates if TLS is enabled, configures
#   MySQL SSL parameters via configuration file, and starts the database server
#   with appropriate security settings.
#
# GLOBALS:
#   VAULT_ADDR - Vault server address (default: http://vault:8200)
#   VAULT_TOKEN - Authentication token for Vault API access (required)
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
#   VAULT_TOKEN=<token> ./init.sh [mysqld_args...]
#
#   Example:
#     VAULT_TOKEN=hvs.CAESIJ... ./init.sh mysqld
#     VAULT_TOKEN=hvs.CAESIJ... VAULT_ADDR=http://vault:8200 ./init.sh mysqld
#
# DEPENDENCIES:
#   - curl: For Vault health checks and API requests
#   - grep, sed, cut: For JSON parsing without jq dependency
#   - docker-entrypoint.sh: MySQL official entrypoint script
#   - HashiCorp Vault: Must be accessible and unsealed
#   - Pre-generated TLS certificates: Required when tls_enabled=true in Vault
#
# EXIT CODES:
#   0 - Successful initialization and MySQL startup
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
#   - MySQL config file created at /etc/my.cnf.d/tls.cnf when TLS enabled
#   - require_secure_transport is set to OFF for dual-mode operation
#   - Supported TLS versions: TLSv1.2, TLSv1.3
#   - Uses grep/sed for JSON parsing (no jq required)
#
# EXAMPLES:
#   # Basic usage with TLS disabled
#   VAULT_TOKEN=hvs.CAESIJ... ./init.sh mysqld
#
#   # Usage with TLS enabled (requires pre-generated certificates)
#   VAULT_TOKEN=hvs.CAESIJ... ./init.sh mysqld
#
#   # Custom Vault address
#   VAULT_TOKEN=hvs.CAESIJ... VAULT_ADDR=https://vault.example.com:8200 ./init.sh mysqld
#
#   # With custom MySQL IP
#   VAULT_TOKEN=hvs.CAESIJ... MYSQL_IP=192.168.1.12 ./init.sh mysqld
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
SERVICE_NAME="mysql"
SERVICE_IP="${MYSQL_IP:-172.20.0.12}"
CERT_DIR="/var/lib/mysql-certs"
ENABLE_TLS=""  # Will be read from Vault

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
info() { echo -e "${BLUE}[MySQL Init]${NC} $1"; }

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
success() { echo -e "${GREEN}[MySQL Init]${NC} $1"; }

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
warn() { echo -e "${YELLOW}[MySQL Init]${NC} $1"; }

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
error() { echo -e "${RED}[MySQL Init]${NC} $1"; exit 1; }

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
#   - Uses curl with silent and fail flags for health checks
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
# Retrieves MySQL credentials and TLS enablement flag from Vault's KV v2
# secrets engine and exports them as environment variables. Uses grep/sed for
# JSON parsing to avoid jq dependency.
# Globals:
#   VAULT_ADDR - Vault server URL
#   VAULT_TOKEN - Authentication token for Vault API
#   SERVICE_NAME - Service identifier (mysql) for secrets path
#   MYSQL_ROOT_PASSWORD - Exported root user password
#   MYSQL_USER - Exported application database username
#   MYSQL_PASSWORD - Exported application user password
#   MYSQL_DATABASE - Exported default database name
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
#   - Uses grep/cut/sed for JSON parsing (no jq required)
#   - Validates that root_password is not null or empty
#   - Defaults tls_enabled to false if not present in Vault
#######################################
fetch_credentials() {
    info "Fetching credentials and TLS setting from Vault..."

    local response=$(curl -sf \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/$SERVICE_NAME")

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
# Checks for the presence and accessibility of pre-generated SSL/TLS certificates
# required for MySQL secure connections. Skips validation if TLS is disabled.
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
#   - Required certificates: server-cert.pem, server-key.pem, ca.pem
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
# Creates MySQL configuration file for TLS when enabled. The configuration
# supports dual-mode operation accepting both SSL and non-SSL connections.
# Globals:
#   ENABLE_TLS - Flag indicating whether TLS is enabled
#   CERT_DIR - Directory path containing certificates
# Arguments:
#   None
# Returns:
#   0 - Always successful
# Outputs:
#   Status messages via info() and success() functions
#   Creates /etc/my.cnf.d/tls.cnf configuration file
# Notes:
#   - Only configures when ENABLE_TLS=true, otherwise returns immediately
#   - Sets require_secure_transport=OFF for dual-mode operation
#   - Supports TLS versions: TLSv1.2, TLSv1.3
#   - Configuration includes ssl-ca, ssl-cert, and ssl-key paths
#   - Accepts both encrypted and unencrypted connections
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
# Coordinates the complete MySQL initialization workflow including credential
# fetching, certificate validation, TLS configuration, and MySQL startup with
# appropriate security settings.
# Globals:
#   VAULT_TOKEN - Required authentication token (validated)
#   ENABLE_TLS - TLS enablement flag (set by fetch_credentials)
#   All globals used by called functions
# Arguments:
#   $@ - Command line arguments passed to MySQL (forwarded to docker-entrypoint.sh)
# Returns:
#   0 - Successful initialization (never returns as exec replaces process)
#   1 - Initialization failures (via error() calls in sub-functions)
# Outputs:
#   Initialization progress messages via info() and success() functions
# Notes:
#   - Validates VAULT_TOKEN environment variable is set
#   - Calls functions in sequence: wait_for_vault -> fetch_credentials ->
#     validate_certificates -> configure_tls
#   - Executes MySQL with exec (replaces current process)
#   - TLS configuration is file-based via /etc/my.cnf.d/tls.cnf
#   - Both TLS and non-TLS modes use same docker-entrypoint.sh execution path
#######################################
main() {
    info "Starting MySQL initialization with Vault integration..."
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
