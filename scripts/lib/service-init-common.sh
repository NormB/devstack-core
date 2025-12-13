#!/bin/bash
################################################################################
# Common Service Initialization Library for Vault AppRole Integration
################################################################################
# This library provides shared functions for all service init scripts that
# integrate with HashiCorp Vault AppRole authentication.
#
# DESCRIPTION:
#   Centralizes common initialization logic used across PostgreSQL, MySQL,
#   Redis, MongoDB, RabbitMQ, and other services. Reduces code duplication
#   and ensures consistent behavior across all services.
#
# REQUIRED VARIABLES (must be set before sourcing):
#   SERVICE_NAME         - Service identifier (e.g., "postgres", "mysql")
#   SERVICE_DISPLAY_NAME - Human-readable name for logging (e.g., "PostgreSQL")
#   VAULT_APPROLE_DIR    - Directory containing AppRole credentials
#
# OPTIONAL VARIABLES:
#   VAULT_ADDR           - Vault server address (default: http://vault:8200)
#   VAULT_MAX_ATTEMPTS   - Max attempts to wait for Vault (default: 60)
#   VAULT_RETRY_DELAY    - Seconds between retry attempts (default: 2)
#
# EXPORTED VARIABLES (set by this library):
#   VAULT_TOKEN          - Temporary client token from AppRole auth
#   ROLE_ID              - AppRole role identifier
#   SECRET_ID            - AppRole secret identifier
#
# FUNCTIONS PROVIDED:
#   log_info()           - Print informational message
#   log_success()        - Print success message
#   log_warn()           - Print warning message
#   log_error()          - Print error and exit
#   ensure_jq()          - Install jq if not present (supports apt/apk)
#   ensure_curl()        - Install curl if not present (supports apt/apk)
#   wait_for_vault()     - Wait for Vault to become ready
#   read_approle_credentials() - Read role-id and secret-id from files
#   authenticate_approle()     - Authenticate to Vault and get token
#   fetch_vault_secret()       - Fetch a secret from Vault KV store
#   vault_init_common()        - Run all common init steps
#
# USAGE:
#   # In your service init script:
#   SERVICE_NAME="postgres"
#   SERVICE_DISPLAY_NAME="PostgreSQL"
#   VAULT_APPROLE_DIR="${VAULT_APPROLE_DIR:-/vault-approles/postgres}"
#   source /scripts/lib/service-init-common.sh
#
#   # Then call:
#   vault_init_common
#   # Now VAULT_TOKEN is set and you can fetch service-specific secrets
#
# NOTES:
#   - All functions use 'set -e' behavior from parent script
#   - Color output is automatically disabled if stdout is not a terminal
#   - Supports both Alpine (apk) and Debian (apt-get) package managers
#
# VERSION:
#   1.0.0
################################################################################

# Default configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_MAX_ATTEMPTS="${VAULT_MAX_ATTEMPTS:-60}"
VAULT_RETRY_DELAY="${VAULT_RETRY_DELAY:-2}"

# Runtime variables (set by functions)
VAULT_TOKEN=""
ROLE_ID=""
SECRET_ID=""

# Colors (can be disabled by setting NO_COLOR=1)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

################################################################################
# Logging Functions
################################################################################

#######################################
# Print informational message to stdout
# Arguments:
#   $1 - Message to print
#######################################
log_info() {
    echo -e "${BLUE}[${SERVICE_DISPLAY_NAME:-Service} Init]${NC} $1"
}

#######################################
# Print success message to stdout
# Arguments:
#   $1 - Message to print
#######################################
log_success() {
    echo -e "${GREEN}[${SERVICE_DISPLAY_NAME:-Service} Init]${NC} $1"
}

#######################################
# Print warning message to stdout
# Arguments:
#   $1 - Message to print
#######################################
log_warn() {
    echo -e "${YELLOW}[${SERVICE_DISPLAY_NAME:-Service} Init]${NC} $1"
}

#######################################
# Print error message to stderr and exit
# Arguments:
#   $1 - Error message
#   $2 - Exit code (default: 1)
#######################################
log_error() {
    echo -e "${RED}[${SERVICE_DISPLAY_NAME:-Service} Init]${NC} $1" >&2
    exit "${2:-1}"
}

################################################################################
# Dependency Management
################################################################################

#######################################
# Detect package manager type
# Outputs:
#   Writes "apt", "apk", "microdnf", or "yum" to stdout
# Returns:
#   0 - Package manager detected
#   1 - No supported package manager found
#######################################
_detect_package_manager() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v apk &>/dev/null; then
        echo "apk"
    elif command -v microdnf &>/dev/null; then
        echo "microdnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    else
        return 1
    fi
}

#######################################
# Install a package using the appropriate package manager
# Arguments:
#   $@ - Package names to install
# Returns:
#   0 - Installation successful
#   1 - Installation failed
#######################################
_install_package() {
    local pkg_mgr
    pkg_mgr=$(_detect_package_manager) || {
        log_warn "No supported package manager found"
        return 1
    }

    case "$pkg_mgr" in
        apt)
            apt-get update -qq >/dev/null 2>&1
            apt-get install -y -qq "$@" >/dev/null 2>&1
            ;;
        apk)
            apk add --no-cache "$@" >/dev/null 2>&1
            ;;
        microdnf)
            microdnf install -y "$@" >/dev/null 2>&1
            ;;
        yum)
            yum install -y "$@" >/dev/null 2>&1
            ;;
    esac
}

#######################################
# Ensure jq is installed
# Returns:
#   0 - jq is available
#   1 - Failed to install jq
#######################################
ensure_jq() {
    if command -v jq &>/dev/null; then
        return 0
    fi
    log_info "Installing jq..."
    if _install_package jq; then
        log_success "jq installed"
    else
        log_error "Failed to install jq"
    fi
}

#######################################
# Ensure curl is installed
# Returns:
#   0 - curl is available
#   1 - Failed to install curl
#######################################
ensure_curl() {
    if command -v curl &>/dev/null; then
        return 0
    fi
    log_info "Installing curl..."
    if _install_package curl; then
        log_success "curl installed"
    else
        log_error "Failed to install curl"
    fi
}

#######################################
# Ensure both curl and jq are installed
#######################################
ensure_dependencies() {
    ensure_curl
    ensure_jq
}

################################################################################
# Vault Functions
################################################################################

#######################################
# Wait for Vault service to become ready
# Globals:
#   VAULT_ADDR - Vault server address
#   VAULT_MAX_ATTEMPTS - Maximum retry attempts
#   VAULT_RETRY_DELAY - Delay between retries
# Returns:
#   0 - Vault is ready
#   1 - Vault did not become ready in time
#######################################
wait_for_vault() {
    log_info "Waiting for Vault to be ready..."

    local attempt=0
    local health_url="${VAULT_ADDR}/v1/sys/health?standbyok=true"

    while [ $attempt -lt "$VAULT_MAX_ATTEMPTS" ]; do
        # Try curl first, fall back to wget
        if command -v curl &>/dev/null; then
            if curl -sf "$health_url" >/dev/null 2>&1; then
                log_success "Vault is ready"
                return 0
            fi
        elif command -v wget &>/dev/null; then
            if wget -q -O - "$health_url" >/dev/null 2>&1; then
                log_success "Vault is ready"
                return 0
            fi
        else
            log_error "Neither curl nor wget available for health check"
        fi

        attempt=$((attempt + 1))
        sleep "$VAULT_RETRY_DELAY"
    done

    log_error "Vault did not become ready in time (waited $((VAULT_MAX_ATTEMPTS * VAULT_RETRY_DELAY)) seconds)"
}

#######################################
# Read AppRole credentials from mounted volume
# Globals:
#   VAULT_APPROLE_DIR - Directory containing credentials
# Outputs:
#   Sets ROLE_ID and SECRET_ID global variables
# Returns:
#   0 - Credentials read successfully
#   1 - Credentials not found or empty
#######################################
read_approle_credentials() {
    log_info "Reading AppRole credentials from $VAULT_APPROLE_DIR..."

    local role_id_file="${VAULT_APPROLE_DIR}/role-id"
    local secret_id_file="${VAULT_APPROLE_DIR}/secret-id"

    if [ ! -f "$role_id_file" ]; then
        log_error "AppRole role-id file not found: $role_id_file"
    fi

    if [ ! -f "$secret_id_file" ]; then
        log_error "AppRole secret-id file not found: $secret_id_file"
    fi

    ROLE_ID=$(cat "$role_id_file")
    SECRET_ID=$(cat "$secret_id_file")

    if [ -z "$ROLE_ID" ] || [ -z "$SECRET_ID" ]; then
        log_error "AppRole credentials are empty"
    fi

    # Show truncated role_id for debugging (first 20 chars)
    local truncated_role_id="${ROLE_ID:0:20}"
    log_success "AppRole credentials loaded (role_id: ${truncated_role_id}...)"
}

#######################################
# Authenticate to Vault using AppRole
# Globals:
#   VAULT_ADDR - Vault server address
#   ROLE_ID - AppRole role identifier
#   SECRET_ID - AppRole secret identifier
# Outputs:
#   Sets VAULT_TOKEN global variable
#   Exports VAULT_TOKEN environment variable
# Returns:
#   0 - Authentication successful
#   1 - Authentication failed
#######################################
authenticate_approle() {
    log_info "Authenticating to Vault with AppRole..."

    local auth_response
    local login_url="${VAULT_ADDR}/v1/auth/approle/login"
    local payload="{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}"

    # Use curl for authentication
    auth_response=$(curl -sf \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "$login_url" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$auth_response" ]; then
        log_error "Failed to authenticate with AppRole"
    fi

    VAULT_TOKEN=$(echo "$auth_response" | jq -r '.auth.client_token')

    if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" = "null" ]; then
        log_error "Failed to obtain token from AppRole authentication"
    fi

    export VAULT_TOKEN

    # Show truncated token for debugging
    local truncated_token="${VAULT_TOKEN:0:20}"
    log_success "AppRole authentication successful (token: ${truncated_token}...)"
}

#######################################
# Fetch a secret from Vault KV v2 store
# Arguments:
#   $1 - Secret path (e.g., "postgres", "mysql")
# Globals:
#   VAULT_ADDR - Vault server address
#   VAULT_TOKEN - Authentication token
# Outputs:
#   Writes JSON response to stdout
# Returns:
#   0 - Secret fetched successfully
#   1 - Failed to fetch secret
#######################################
fetch_vault_secret() {
    local secret_path="$1"
    local secret_url="${VAULT_ADDR}/v1/secret/data/${secret_path}"

    local response
    response=$(curl -sf \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$secret_url" 2>/dev/null)

    if [ $? -ne 0 ] || [ -z "$response" ]; then
        log_error "Failed to fetch credentials from Vault path: $secret_path"
    fi

    echo "$response"
}

#######################################
# Extract a field from Vault KV v2 JSON response
# Arguments:
#   $1 - JSON response from fetch_vault_secret
#   $2 - Field name to extract
#   $3 - Default value if field not found (optional)
# Outputs:
#   Writes field value to stdout
#######################################
extract_vault_field() {
    local json="$1"
    local field="$2"
    local default="${3:-}"

    local value
    value=$(echo "$json" | jq -r ".data.data.${field} // \"${default}\"")

    echo "$value"
}

################################################################################
# Certificate Validation
################################################################################

#######################################
# Validate that a certificate file exists and is readable
# Arguments:
#   $1 - Certificate file path
#   $2 - Certificate description for error message
# Returns:
#   0 - Certificate is valid
#   1 - Certificate not found or not readable
#######################################
validate_cert_file() {
    local cert_file="$1"
    local description="$2"

    if [ ! -f "$cert_file" ]; then
        log_error "TLS enabled but $description not found: $cert_file. Run scripts/generate-certificates.sh first."
    fi

    if [ ! -r "$cert_file" ]; then
        log_error "TLS enabled but $description is not readable: $cert_file. Check file permissions."
    fi
}

################################################################################
# Main Initialization Helper
################################################################################

#######################################
# Run common Vault initialization steps
# This function:
#   1. Ensures curl and jq are installed
#   2. Waits for Vault to be ready
#   3. Reads AppRole credentials
#   4. Authenticates to Vault
#
# After calling this, VAULT_TOKEN will be set and exported.
# Globals:
#   All globals mentioned above
#######################################
vault_init_common() {
    log_info "Starting ${SERVICE_DISPLAY_NAME:-service} initialization with Vault AppRole integration..."
    log_info ""

    # Ensure dependencies
    ensure_dependencies

    # Wait for Vault
    wait_for_vault

    # Read AppRole credentials
    read_approle_credentials

    # Authenticate to Vault
    authenticate_approle
}
