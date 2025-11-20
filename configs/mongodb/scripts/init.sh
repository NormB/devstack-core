#!/bin/bash
#######################################
# MongoDB Initialization Script with Vault Integration
#
# This script orchestrates the secure initialization of MongoDB by integrating
# with HashiCorp Vault for credential management and TLS certificate validation.
# It supports dual-mode TLS configuration (accepting both SSL and non-SSL connections).
#
# DESCRIPTION:
#   Initializes MongoDB with credentials and configuration fetched from Vault.
#   The script waits for Vault availability, retrieves database credentials and
#   TLS settings, validates pre-generated certificates if TLS is enabled, configures
#   MongoDB TLS parameters via configuration file and command-line options, and
#   starts the database server with appropriate security settings.
#
# GLOBALS:
#   VAULT_ADDR - Vault server address (default: http://vault:8200)
#   VAULT_TOKEN - Authentication token for Vault API access (required)
#   SERVICE_NAME - Service identifier for Vault secrets (set to "mongodb")
#   SERVICE_IP - MongoDB service IP address (default: 172.20.0.15)
#   PKI_ROLE - Vault PKI role name for certificate generation (mongodb-role)
#   CERT_DIR - Directory containing TLS certificates (/etc/mongodb/certs)
#   ENABLE_TLS - TLS enablement flag (read from Vault)
#   MONGO_INITDB_ROOT_USERNAME - Root username (exported from Vault)
#   MONGO_INITDB_ROOT_PASSWORD - Root password (exported from Vault)
#   MONGO_INITDB_DATABASE - Default database name (exported from Vault)
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for output formatting
#
# USAGE:
#   VAULT_TOKEN=<token> ./init.sh [mongod_args...]
#
#   Example:
#     VAULT_TOKEN=hvs.CAESIJ... ./init.sh mongod
#     VAULT_TOKEN=hvs.CAESIJ... VAULT_ADDR=http://vault:8200 ./init.sh mongod
#
# DEPENDENCIES:
#   - curl: For Vault health checks and API requests (auto-installed if missing)
#   - apt-get: For installing curl on Debian-based systems
#   - grep, sed, cut: For JSON parsing without jq dependency
#   - docker-entrypoint.sh: MongoDB official entrypoint script
#   - HashiCorp Vault: Must be accessible and unsealed
#   - Pre-generated TLS certificates: Required when tls_enabled=true in Vault
#
# EXIT CODES:
#   0 - Successful initialization and MongoDB startup
#   1 - Vault connection failure or timeout
#   1 - Missing required VAULT_TOKEN environment variable
#   1 - Invalid or missing credentials from Vault
#   1 - TLS certificate validation failure
#   1 - Configuration errors
#
# NOTES:
#   - The script uses 'set -e' for fail-fast behavior
#   - Maximum Vault readiness wait time: 120 seconds (60 attempts x 2s)
#   - TLS mode is "preferTLS": accepts both SSL and non-SSL connections
#   - Certificates must be pre-generated using scripts/generate-certificates.sh
#   - Certificate permissions are validated before use
#   - MongoDB config file created at /etc/mongod.conf.d/ssl.conf when TLS enabled
#   - MongoDB requires combined certificate+key file (mongodb.pem)
#   - Uses grep/sed for JSON parsing (no jq required)
#   - Auto-installs curl if not present in container
#
# EXAMPLES:
#   # Basic usage with TLS disabled
#   VAULT_TOKEN=hvs.CAESIJ... ./init.sh mongod
#
#   # Usage with TLS enabled (requires pre-generated certificates)
#   VAULT_TOKEN=hvs.CAESIJ... ./init.sh mongod
#
#   # Custom Vault address
#   VAULT_TOKEN=hvs.CAESIJ... VAULT_ADDR=https://vault.example.com:8200 ./init.sh mongod
#
#   # With custom MongoDB IP
#   VAULT_TOKEN=hvs.CAESIJ... MONGODB_IP=192.168.1.15 ./init.sh mongod
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
SERVICE_NAME="mongodb"
SERVICE_IP="${MONGODB_IP:-172.20.0.15}"
PKI_ROLE="mongodb-role"
CERT_DIR="/etc/mongodb/certs"
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
info() { echo -e "${BLUE}[MongoDB Init]${NC} $1"; }

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
success() { echo -e "${GREEN}[MongoDB Init]${NC} $1"; }

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
warn() { echo -e "${YELLOW}[MongoDB Init]${NC} $1"; }

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
error() { echo -e "${RED}[MongoDB Init]${NC} $1"; exit 1; }

#######################################
# Installs curl if not already available in the system
# Checks for curl command and installs it using apt-get if missing.
# Suppresses verbose output for cleaner initialization logs.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 - curl already installed or successfully installed
# Outputs:
#   Status messages via info() and success() functions
# Notes:
#   - Uses apt-get for Debian/Ubuntu-based MongoDB containers
#   - Updates package index before installation
#   - Suppresses apt-get output for cleaner logs
#######################################
install_curl() {
    if ! command -v curl &> /dev/null; then
        info "Installing curl..."
        apt-get update -qq > /dev/null 2>&1
        apt-get install -y -qq curl > /dev/null 2>&1
        success "curl installed"
    fi
}

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
# Retrieves MongoDB credentials and TLS enablement flag from Vault's KV v2
# secrets engine and exports them as environment variables. Uses grep/sed for
# JSON parsing to avoid jq dependency.
# Globals:
#   VAULT_ADDR - Vault server URL
#   VAULT_TOKEN - Authentication token for Vault API
#   SERVICE_NAME - Service identifier (mongodb) for secrets path
#   MONGO_INITDB_ROOT_USERNAME - Exported root username
#   MONGO_INITDB_ROOT_PASSWORD - Exported root password
#   MONGO_INITDB_DATABASE - Exported default database name
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
#   - Validates that username and password are not empty
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

    # Parse JSON using grep/sed (no jq required)
    export MONGO_INITDB_ROOT_USERNAME=$(echo "$response" | grep -o '"user":"[^"]*"' | cut -d'"' -f4)
    export MONGO_INITDB_ROOT_PASSWORD=$(echo "$response" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)
    export MONGO_INITDB_DATABASE=$(echo "$response" | grep -o '"database":"[^"]*"' | cut -d'"' -f4)

    # Extract tls_enabled (default to false if not present)
    local tls_value=$(echo "$response" | grep -o '"tls_enabled":[^,}]*' | cut -d':' -f2 | tr -d ' "')
    export ENABLE_TLS="${tls_value:-false}"

    if [ -z "$MONGO_INITDB_ROOT_USERNAME" ] || [ -z "$MONGO_INITDB_ROOT_PASSWORD" ]; then
        error "Invalid credentials received from Vault"
    fi

    success "Credentials fetched successfully (tls_enabled=$ENABLE_TLS)"
}

#######################################
# Validates that required TLS certificates exist and are readable
# Checks for the presence and accessibility of pre-generated SSL/TLS certificates
# required for MongoDB secure connections. Skips validation if TLS is disabled.
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
#   - Required certificates: mongodb.pem (combined cert+key), ca.pem
#   - MongoDB requires certificate and key in a single PEM file
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
    # MongoDB requires the combined cert+key file
    if [ ! -f "$CERT_DIR/mongodb.pem" ] || [ ! -r "$CERT_DIR/mongodb.pem" ]; then
        error "TLS enabled but mongodb.pem not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    if [ ! -f "$CERT_DIR/ca.pem" ] || [ ! -r "$CERT_DIR/ca.pem" ]; then
        error "TLS enabled but ca.pem not found or not readable in $CERT_DIR/. Run scripts/generate-certificates.sh first."
    fi

    success "TLS certificates validated (pre-generated)"
}

#######################################
# Configures MongoDB SSL/TLS via configuration file
# Creates MongoDB YAML configuration file for TLS when enabled. The configuration
# supports dual-mode operation using preferTLS mode.
# Globals:
#   ENABLE_TLS - Flag indicating whether TLS is enabled
#   CERT_DIR - Directory path containing certificates
# Arguments:
#   None
# Returns:
#   0 - Always successful
# Outputs:
#   Status messages via info() and success() functions
#   Creates /etc/mongod.conf.d/ssl.conf configuration file
# Notes:
#   - Only configures when ENABLE_TLS=true, otherwise returns immediately
#   - Uses preferTLS mode for dual-mode operation (accepts both SSL and non-SSL)
#   - allowConnectionsWithoutCertificates set to true for client flexibility
#   - Configuration requires mongodb.pem (combined cert+key) and ca.pem
#   - Creates configuration directory if it doesn't exist
#######################################
configure_tls() {
    if [ "$ENABLE_TLS" != "true" ]; then
        return 0
    fi

    info "Configuring MongoDB for TLS (dual-mode: accepts both SSL and non-SSL)..."

    # Create MongoDB SSL config directory and file
    mkdir -p /etc/mongod.conf.d
    cat > /etc/mongod.conf.d/ssl.conf <<EOF
# SSL/TLS Configuration (Dual-Mode)
# Accepts both encrypted and unencrypted connections
net:
  tls:
    mode: preferTLS
    certificateKeyFile: $CERT_DIR/mongodb.pem
    CAFile: $CERT_DIR/ca.pem
    allowConnectionsWithoutCertificates: true
EOF

    success "TLS dual-mode configuration prepared (accepts both SSL and non-SSL connections)"
}

#######################################
# Main initialization orchestration function
# Coordinates the complete MongoDB initialization workflow including curl installation,
# credential fetching, certificate validation, TLS configuration, and MongoDB startup
# with appropriate security settings.
# Globals:
#   VAULT_TOKEN - Required authentication token (validated)
#   ENABLE_TLS - TLS enablement flag (set by fetch_credentials)
#   CERT_DIR - Certificate directory path
#   All globals used by called functions
# Arguments:
#   $@ - Command line arguments passed to MongoDB (forwarded to docker-entrypoint.sh)
# Returns:
#   0 - Successful initialization (never returns as exec replaces process)
#   1 - Initialization failures (via error() calls in sub-functions)
# Outputs:
#   Initialization progress messages via info() and success() functions
# Notes:
#   - Validates VAULT_TOKEN environment variable is set
#   - Auto-installs curl if not present
#   - Calls functions in sequence: install_curl -> wait_for_vault -> fetch_credentials ->
#     validate_certificates -> configure_tls
#   - Executes MongoDB with exec (replaces current process)
#   - TLS mode: Passes TLS configuration via both config file and command-line options
#   - Non-TLS mode: Starts MongoDB without TLS configuration
#   - Command-line TLS options: --tlsMode preferTLS, --tlsCertificateKeyFile,
#     --tlsCAFile, --tlsAllowConnectionsWithoutCertificates
#######################################
main() {
    info "Starting MongoDB initialization with Vault integration..."
    info ""

    # Check required environment variables and validate token format
    if [ -z "$VAULT_TOKEN" ]; then
        error "VAULT_TOKEN environment variable is required"
    fi

    if [ ${#VAULT_TOKEN} -lt 20 ]; then
        error "VAULT_TOKEN must be at least 20 characters (current: ${#VAULT_TOKEN} chars)"
    fi

    # Install curl if needed
    install_curl

    # Wait for Vault
    wait_for_vault

    # Fetch credentials and TLS setting from Vault
    fetch_credentials

    # Validate pre-generated certificates if TLS is enabled
    validate_certificates

    # Configure TLS if enabled
    configure_tls

    info ""
    success "Initialization complete, starting MongoDB..."
    info ""

    # Start MongoDB with the original docker-entrypoint
    # Pass TLS configuration via command line if enabled
    if [ "$ENABLE_TLS" = "true" ]; then
        exec docker-entrypoint.sh "$@" \
            --tlsMode preferTLS \
            --tlsCertificateKeyFile "$CERT_DIR/mongodb.pem" \
            --tlsCAFile "$CERT_DIR/ca.pem" \
            --tlsAllowConnectionsWithoutCertificates
    else
        exec docker-entrypoint.sh "$@"
    fi
}

# Run main function
main "$@"
