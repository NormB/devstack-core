#!/bin/bash
#
#######################################
# FastAPI Initialization Script with Vault Integration
#
# Description:
#   Initializes the FastAPI reference application with Vault-managed configuration
#   and TLS certificate provisioning. Performs startup sequence including Vault
#   health checks, configuration retrieval, and certificate setup before launching
#   the application. Supports both TLS-enabled and plain HTTP deployments.
#
# Globals:
#   VAULT_ADDR         - Vault server address (default: http://vault:8200)
#   VAULT_TOKEN        - Vault authentication token (required)
#   REFERENCE_API_IP   - Service IP address (default: 172.20.0.30)
#   SERVICE_NAME       - Internal service identifier (fixed: reference-api)
#   CERT_DIR           - Certificate storage path (fixed: /etc/ssl/certs/reference-api)
#   VAULT_CERT_DIR     - Vault certificate source (default: ~/.config/vault/certs)
#   ENABLE_TLS         - TLS enablement flag (fetched from Vault)
#   REFERENCE_API_ENABLE_TLS - Exported TLS state for application
#
# Usage:
#   ./init.sh
#   VAULT_ADDR=https://vault.example.com:8200 VAULT_TOKEN=s.xyz ./init.sh
#
# Dependencies:
#   - wget: HTTP client for Vault API calls and health checks
#   - jq: JSON processor for parsing Vault responses
#   - bash: Version 4.0 or higher recommended
#   - start.sh: Application startup script (must be present at /app/start.sh)
#
# Exit Codes:
#   0 - Success: Initialization complete, application started
#   1 - Failure: Vault unreachable, missing dependencies, or startup error
#
# Notes:
#   - Waits up to 120 seconds (60 attempts * 2s) for Vault readiness
#   - Gracefully degrades to non-TLS mode if Vault config fetch fails
#   - Pre-generated certificates must exist in VAULT_CERT_DIR for TLS mode
#   - Uses exec to replace init process with start.sh (PID inheritance)
#   - All Vault API calls use standbyok=true for high availability
#
# Examples:
#   # Standard Docker container startup
#   ./init.sh
#
#   # Custom Vault configuration
#   VAULT_ADDR=http://vault-prod:8200 VAULT_TOKEN=s.abc123 ./init.sh
#
#   # Force-disable TLS (via Vault configuration)
#   # Set secret/reference-api: {"tls_enabled": "false"} in Vault
#
#######################################

set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_TOKEN="${VAULT_TOKEN}"
SERVICE_NAME="reference-api"
SERVICE_IP="${REFERENCE_API_IP:-172.20.0.30}"
CERT_DIR="/app/certs"
VAULT_CERT_DIR="/app/vault-certs"
ENABLE_TLS=""  # Will be read from Vault

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print informational message to stdout
# Globals:
#   BLUE, NC - Terminal color codes
# Arguments:
#   $1 - Message text to display
# Outputs:
#   Writes formatted info message to stdout
#######################################
info() { echo -e "${BLUE}[FastAPI Init]${NC} $1"; }

#######################################
# Print success message to stdout
# Globals:
#   GREEN, NC - Terminal color codes
# Arguments:
#   $1 - Message text to display
# Outputs:
#   Writes formatted success message to stdout
#######################################
success() { echo -e "${GREEN}[FastAPI Init]${NC} $1"; }

#######################################
# Print warning message to stdout
# Globals:
#   YELLOW, NC - Terminal color codes
# Arguments:
#   $1 - Message text to display
# Outputs:
#   Writes formatted warning message to stdout
#######################################
warn() { echo -e "${YELLOW}[FastAPI Init]${NC} $1"; }

#######################################
# Print error message and exit with code 1
# Globals:
#   RED, NC - Terminal color codes
# Arguments:
#   $1 - Error message text to display
# Returns:
#   1 - Always exits with error code
# Outputs:
#   Writes formatted error message to stdout before exit
#######################################
error() { echo -e "${RED}[FastAPI Init]${NC} $1"; exit 1; }

#######################################
# Wait for Vault service to become ready
# Polls Vault health endpoint with exponential backoff until service is available
# or timeout is reached.
# Globals:
#   VAULT_ADDR - Vault server address
# Arguments:
#   None
# Returns:
#   0 - Vault is ready and responsive
#   1 - Vault did not become ready within timeout (exits via error())
# Outputs:
#   Progress messages to stdout via info/success/error functions
# Notes:
#   - Maximum wait time: 120 seconds (60 attempts * 2s interval)
#   - Uses standbyok=true to accept Vault standby nodes
#   - Silent mode (-q) suppresses wget output noise
#######################################
wait_for_vault() {
    info "Waiting for Vault to be ready..."

    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if wget --spider -q --no-check-certificate "$VAULT_ADDR/v1/sys/health?standbyok=true" 2>/dev/null; then
            success "Vault is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    error "Vault did not become ready in time"
}

#######################################
# Fetch TLS configuration from Vault KV store
# Retrieves service configuration including TLS enablement flag from Vault
# secret store. Gracefully handles failures by defaulting to disabled TLS.
# Globals:
#   VAULT_ADDR   - Vault server address
#   VAULT_TOKEN  - Authentication token for Vault API
#   SERVICE_NAME - Service identifier for secret path (reference-api)
#   ENABLE_TLS   - Modified: Set to fetched value or "false" on failure
# Arguments:
#   None
# Returns:
#   0 - Always returns success (graceful degradation)
# Outputs:
#   Status messages to stdout via info/warn/success functions
# Notes:
#   - Fetches from path: /v1/secret/data/$SERVICE_NAME
#   - Uses jq with fallback operator (//) for safe JSON parsing
#   - Defaults to TLS disabled if Vault is unavailable or secret not found
#   - Exports ENABLE_TLS for use by subsequent functions
#######################################
fetch_tls_config() {
    info "Fetching TLS configuration from Vault..."

    local response=$(wget -qO- --no-check-certificate \
        --header "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/$SERVICE_NAME" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        warn "Failed to fetch configuration from Vault, using defaults"
        export ENABLE_TLS="false"
        return 0
    fi

    export ENABLE_TLS=$(echo "$response" | jq -r '.data.data.tls_enabled // "false"')

    success "Configuration fetched: tls_enabled=$ENABLE_TLS"
}

#######################################
# Setup TLS certificates from Vault-managed certificate store
# Copies pre-generated TLS certificates from Vault's certificate directory
# to the application's certificate directory with proper permissions.
# Globals:
#   ENABLE_TLS       - TLS enablement flag from Vault config
#   CERT_DIR         - Destination certificate directory
#   VAULT_CERT_DIR   - Source certificate directory from Vault
#   SERVICE_NAME     - Service identifier for certificate filenames
#   REFERENCE_API_ENABLE_TLS - Modified: Exported TLS state for application
# Arguments:
#   None
# Returns:
#   0 - Always returns success (graceful degradation)
# Outputs:
#   Status messages to stdout via info/warn/success functions
# Notes:
#   - Creates CERT_DIR if it doesn't exist
#   - Expects certificate files: ${SERVICE_NAME}.crt and ${SERVICE_NAME}.key
#   - Sets certificate permissions: 644 (crt) and 600 (key) for security
#   - Falls back to disabled TLS if certificates not found
#   - Exports REFERENCE_API_ENABLE_TLS for consumption by start.sh
#######################################
setup_tls_certificates() {
    if [ "$ENABLE_TLS" != "true" ]; then
        info "TLS is disabled"
        export REFERENCE_API_ENABLE_TLS="false"
        return 0
    fi

    info "Setting up TLS certificates..."

    # Create certificate directory
    mkdir -p "$CERT_DIR"

    # Check if pre-generated certificates exist in Vault cert directory
    local vault_cert="${VAULT_CERT_DIR}/${SERVICE_NAME}.crt"
    local vault_key="${VAULT_CERT_DIR}/${SERVICE_NAME}.key"

    if [ -f "$vault_cert" ] && [ -f "$vault_key" ]; then
        info "Copying pre-generated certificates from Vault..."
        cp "$vault_cert" "$CERT_DIR/server.crt"
        cp "$vault_key" "$CERT_DIR/server.key"
        chmod 644 "$CERT_DIR/server.crt"
        chmod 600 "$CERT_DIR/server.key"
        success "Certificates copied successfully"
        export REFERENCE_API_ENABLE_TLS="true"
    else
        warn "Pre-generated certificates not found at $VAULT_CERT_DIR"
        warn "TLS will be disabled"
        export REFERENCE_API_ENABLE_TLS="false"
    fi
}

#######################################
# Main initialization orchestrator
# Coordinates the complete initialization sequence for the FastAPI application
# including Vault connectivity, configuration retrieval, and certificate setup.
# Globals:
#   All globals from called functions (wait_for_vault, fetch_tls_config, setup_tls_certificates)
# Arguments:
#   $@ - All command-line arguments (passed through to start.sh)
# Returns:
#   Does not return - uses exec to replace process with start.sh
# Outputs:
#   Formatted startup banner and status messages to stdout
# Notes:
#   - Executes functions in strict order: vault → config → certificates → start
#   - Uses exec to replace current process with start.sh (maintains PID)
#   - Ensures proper signal handling by becoming the application process
#   - All configuration is exported via environment variables
#######################################
main() {
    echo ""
    echo "========================================="
    echo "  FastAPI Initialization"
    echo "========================================="
    echo ""

    wait_for_vault
    fetch_tls_config
    setup_tls_certificates

    echo ""
    success "Initialization complete, starting FastAPI..."
    echo ""

    # Start the FastAPI application
    exec /app/start.sh
}

# Run main function
main "$@"
