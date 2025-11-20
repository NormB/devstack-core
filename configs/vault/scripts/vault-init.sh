#!/usr/bin/env bash
# ===========================================================================
# Vault Initialization and Unseal Script
# ===========================================================================
#
# DESCRIPTION:
#   Initializes HashiCorp Vault and unseals it for operation. This script
#   handles the complete initialization workflow including key generation,
#   secure storage of unseal keys and root token, and automatic unsealing.
#   Designed for development and testing environments.
#
# GLOBALS:
#   VAULT_ADDR              - Vault server address (default: http://localhost:8200)
#   VAULT_KEYS_FILE         - Path to store unseal keys (default: ~/.config/vault/keys.json)
#   VAULT_ROOT_TOKEN_FILE   - Path to store root token (default: ~/.config/vault/root-token)
#   RED, GREEN, YELLOW, BLUE, NC - Terminal color codes for output formatting
#
# USAGE:
#   ./vault-init.sh
#
# DEPENDENCIES:
#   - curl                  - For HTTP requests to Vault API
#   - grep                  - For parsing JSON responses
#   - python3 (optional)    - For pretty-printing JSON status output
#   - HashiCorp Vault       - Server must be running and accessible
#
# EXIT CODES:
#   0  - Success: Vault initialized and unsealed
#   1  - Error: Vault unreachable, initialization failed, or unsealing failed
#
# NOTES:
#   - Uses Shamir's Secret Sharing with 5 key shares and threshold of 3
#   - Unseal keys and root token are stored with 600 permissions
#   - Script is idempotent: safe to run multiple times
#   - Keys file location: ${HOME}/.config/vault/keys.json
#   - Root token location: ${HOME}/.config/vault/root-token
#   - WARNING: Store and backup unseal keys securely in production
#
# EXAMPLES:
#   # Initialize and unseal Vault with default settings:
#   ./vault-init.sh
#
#   # Initialize and unseal Vault on custom address:
#   VAULT_ADDR=http://vault.example.com:8200 ./vault-init.sh
#
#   # Use root token after initialization:
#   export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
#   vault status
#
# ===========================================================================

set -euo pipefail

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Vault configuration
export VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_KEYS_FILE="${HOME}/.config/vault/keys.json"
VAULT_ROOT_TOKEN_FILE="${HOME}/.config/vault/root-token"

#######################################
# Print informational message to stdout
# Globals:
#   BLUE, NC - Color codes for output formatting
# Arguments:
#   $1 - Message string to display
# Returns:
#   None
# Outputs:
#   Writes formatted info message to stdout
#######################################
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

#######################################
# Print success message to stdout
# Globals:
#   GREEN, NC - Color codes for output formatting
# Arguments:
#   $1 - Success message string to display
# Returns:
#   None
# Outputs:
#   Writes formatted success message to stdout
#######################################
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

#######################################
# Print warning message to stdout
# Globals:
#   YELLOW, NC - Color codes for output formatting
# Arguments:
#   $1 - Warning message string to display
# Returns:
#   None
# Outputs:
#   Writes formatted warning message to stdout
#######################################
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

#######################################
# Print error message and exit script
# Globals:
#   RED, NC - Color codes for output formatting
# Arguments:
#   $1 - Error message string to display
# Returns:
#   Does not return (exits with code 1)
# Outputs:
#   Writes formatted error message to stdout
# Notes:
#   Always exits with status code 1
#######################################
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

#######################################
# Wait for Vault server to become ready and responsive
# Globals:
#   VAULT_ADDR - Vault server address to check
# Arguments:
#   None
# Returns:
#   0 - Vault is ready and responding
#   1 - Vault did not become ready within timeout (via error function)
# Outputs:
#   Status messages to stdout
# Notes:
#   - Polls Vault health endpoint up to 60 times (60 seconds)
#   - Accepts both uninitialized (200) and sealed (200) as ready states
#   - Exits script if Vault doesn't respond within timeout
#######################################
wait_for_vault() {
    info "Waiting for Vault to be ready..."
    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "${VAULT_ADDR}/v1/sys/health?uninitcode=200&sealedcode=200" > /dev/null 2>&1; then
            success "Vault is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    error "Vault did not become ready in time"
}

#######################################
# Check if Vault is already initialized
# Globals:
#   VAULT_ADDR - Vault server address to query
# Arguments:
#   None
# Returns:
#   0 - Vault is initialized
#   1 - Vault is not initialized
# Outputs:
#   None
# Notes:
#   Queries /v1/sys/init endpoint and parses initialized field
#######################################
is_initialized() {
    local status=$(curl -sf "${VAULT_ADDR}/v1/sys/init" | grep -o '"initialized":[^,}]*' | cut -d':' -f2)
    [ "$status" = "true" ]
}

#######################################
# Initialize Vault with Shamir's Secret Sharing
# Globals:
#   VAULT_ADDR            - Vault server address to initialize
#   VAULT_KEYS_FILE       - File path to store unseal keys (modified)
#   VAULT_ROOT_TOKEN_FILE - File path to store root token (modified)
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   Status messages and file paths to stdout
# Notes:
#   - Generates 5 unseal key shares with threshold of 3
#   - Saves complete JSON response to VAULT_KEYS_FILE
#   - Extracts and saves root token to VAULT_ROOT_TOKEN_FILE
#   - Sets file permissions to 600 for security
#   - WARNING: These files contain sensitive cryptographic material
#######################################
initialize_vault() {
    info "Initializing Vault..."

    # Initialize with 5 key shares and 3 key threshold
    local init_output=$(curl -sf --request POST \
        --data '{"secret_shares": 5, "secret_threshold": 3}' \
        "${VAULT_ADDR}/v1/sys/init")

    # Save keys and root token
    echo "$init_output" > "$VAULT_KEYS_FILE"
    chmod 600 "$VAULT_KEYS_FILE"

    # Extract root token
    echo "$init_output" | grep -o '"root_token":"[^"]*"' | cut -d'"' -f4 > "$VAULT_ROOT_TOKEN_FILE"
    chmod 600 "$VAULT_ROOT_TOKEN_FILE"

    success "Vault initialized successfully"
    warning "Unseal keys and root token saved to:"
    echo "  Keys: $VAULT_KEYS_FILE"
    echo "  Root token: $VAULT_ROOT_TOKEN_FILE"
    warning "Keep these files secure and backed up!"
}

#######################################
# Check if Vault is currently in sealed state
# Globals:
#   VAULT_ADDR - Vault server address to query
# Arguments:
#   None
# Returns:
#   0 - Vault is sealed
#   1 - Vault is unsealed
# Outputs:
#   None
# Notes:
#   Queries /v1/sys/seal-status endpoint and parses sealed field
#######################################
is_sealed() {
    local status=$(curl -sf "${VAULT_ADDR}/v1/sys/seal-status" | grep -o '"sealed":[^,}]*' | cut -d':' -f2)
    [ "$status" = "true" ]
}

#######################################
# Unseal Vault using stored unseal keys
# Globals:
#   VAULT_ADDR      - Vault server address to unseal
#   VAULT_KEYS_FILE - File path containing unseal keys
# Arguments:
#   None
# Returns:
#   0 - Vault successfully unsealed or already unsealed
#   1 - Keys file not found or unsealing failed (via error function)
# Outputs:
#   Status messages to stdout
# Notes:
#   - Checks if Vault is already unsealed before attempting
#   - Extracts first 3 unseal keys from keys file (threshold requirement)
#   - Uses base64-encoded keys of exactly 44 characters
#   - Validates unsealing was successful after applying keys
#   - Exits on error if keys file missing or unsealing fails
#######################################
unseal_vault() {
    if ! is_sealed; then
        success "Vault is already unsealed"
        return 0
    fi

    info "Unsealing Vault..."

    if [ ! -f "$VAULT_KEYS_FILE" ]; then
        error "Unseal keys file not found: $VAULT_KEYS_FILE"
    fi

    # Extract unseal keys (we need 3 out of 5)
    local keys=($(cat "$VAULT_KEYS_FILE" | grep -o '"[^"]*"' | grep '^"[A-Za-z0-9+/=]\{44\}"$' | tr -d '"' | head -3))

    if [ ${#keys[@]} -lt 3 ]; then
        error "Could not extract enough unseal keys from $VAULT_KEYS_FILE"
    fi

    # Unseal with first 3 keys
    for key in "${keys[@]:0:3}"; do
        curl -sf --request POST \
            --data "{\"key\": \"$key\"}" \
            "${VAULT_ADDR}/v1/sys/unseal" > /dev/null
    done

    if is_sealed; then
        error "Failed to unseal Vault"
    fi

    success "Vault unsealed successfully"
}

#######################################
# Display current Vault status and authentication information
# Globals:
#   VAULT_ADDR            - Vault server address to query
#   VAULT_ROOT_TOKEN_FILE - File path containing root token
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   Vault seal status (JSON formatted if python3 available) and root token to stdout
# Notes:
#   - Retrieves and displays seal status from /v1/sys/seal-status
#   - Pretty-prints JSON using python3 if available, otherwise raw output
#   - Displays root token and export command if token file exists
#######################################
show_status() {
    info "Vault Status:"
    local status=$(curl -sf "${VAULT_ADDR}/v1/sys/seal-status")

    echo "$status" | python3 -m json.tool 2>/dev/null || echo "$status"

    if [ -f "$VAULT_ROOT_TOKEN_FILE" ]; then
        echo
        info "Root Token: $(cat $VAULT_ROOT_TOKEN_FILE)"
        warning "Use this token to authenticate: export VAULT_TOKEN=\$(cat $VAULT_ROOT_TOKEN_FILE)"
    fi
}

#######################################
# Main execution function - orchestrates Vault initialization and unsealing
# Globals:
#   VAULT_ADDR            - Vault server address
#   VAULT_ROOT_TOKEN_FILE - Root token file path for display
# Arguments:
#   All arguments are ignored (accepts "$@" for compatibility)
# Returns:
#   0 - Vault successfully initialized and unsealed
#   1 - Error during initialization or unsealing (via error function)
# Outputs:
#   Formatted status messages, Vault status, and access information to stdout
# Notes:
#   - Waits for Vault to be ready before proceeding
#   - Initializes Vault only if not already initialized
#   - Always attempts to unseal Vault (safe if already unsealed)
#   - Displays final status and access instructions
#######################################
main() {
    echo
    echo "===================================================================="
    echo "  Vault Initialization and Unseal"
    echo "===================================================================="
    echo

    # Wait for Vault to be ready
    wait_for_vault

    # Check if initialized
    if is_initialized; then
        info "Vault is already initialized"
    else
        initialize_vault
    fi

    # Unseal Vault
    unseal_vault

    echo
    show_status
    echo
    success "Vault is ready to use!"
    echo
    info "Access Vault UI: ${VAULT_ADDR}/ui"
    info "Use root token from: $VAULT_ROOT_TOKEN_FILE"
    echo
}

# Run main function
main "$@"
