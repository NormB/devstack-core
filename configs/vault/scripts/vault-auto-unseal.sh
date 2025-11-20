#!/bin/sh
# ===========================================================================
# Vault Auto-Unseal Script
# ===========================================================================
#
# DESCRIPTION:
#   Automatically unseals HashiCorp Vault when detected as sealed. Designed
#   to run as a sidecar container or background process that monitors Vault
#   seal status and applies unseal keys when needed. Particularly useful
#   after container restarts or Vault service interruptions.
#
# GLOBALS:
#   VAULT_ADDR      - Vault server address (default: http://127.0.0.1:8200)
#   VAULT_KEYS_FILE - Path to unseal keys JSON file (default: /vault-keys/keys.json)
#
# USAGE:
#   ./vault-auto-unseal.sh
#
# DEPENDENCIES:
#   - wget          - For HTTP requests to Vault API (BusyBox compatible)
#   - grep          - For JSON field extraction
#   - cut           - For text parsing
#   - sh            - POSIX shell (not bash - for Alpine/BusyBox compatibility)
#   - HashiCorp Vault - Server must be running and accessible
#
# EXIT CODES:
#   0  - Normal operation (infinite loop keeps process alive)
#   1  - Error: Vault not ready, keys file missing, or unsealing failed
#
# NOTES:
#   - Uses POSIX sh (not bash) for container compatibility
#   - Designed for minimal resource usage (Alpine Linux, BusyBox)
#   - Waits up to 30 seconds for Vault to become responsive
#   - Requires 3 out of 5 Shamir unseal keys (threshold)
#   - After unsealing, sleeps indefinitely to keep container alive
#   - Keys file must contain JSON with base64-encoded 44-character keys
#   - Does NOT initialize Vault, only unseals existing installation
#
# EXAMPLES:
#   # Run as container sidecar:
#   docker run -v /path/to/keys:/vault-keys vault-auto-unseal
#
#   # Run with custom Vault address:
#   VAULT_ADDR=http://vault:8200 ./vault-auto-unseal.sh
#
#   # Run with custom keys location:
#   VAULT_KEYS_FILE=/custom/path/keys.json ./vault-auto-unseal.sh
#
# ===========================================================================

set -eu

# Vault configuration
VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_KEYS_FILE="${VAULT_KEYS_FILE:-/vault-keys/keys.json}"

#######################################
# Wait for Vault server to become ready and responsive
# Globals:
#   VAULT_ADDR - Vault server address to check
# Arguments:
#   None
# Returns:
#   0 - Vault is ready and responding
#   1 - Vault did not become ready within timeout
# Outputs:
#   Error message to stdout on timeout
# Notes:
#   - Polls Vault health endpoint up to 30 times (30 seconds)
#   - Accepts both uninitialized (200) and sealed (200) as ready states
#   - Uses wget --spider for minimal overhead (BusyBox compatible)
#   - Silent operation except on timeout
#######################################
wait_for_vault() {
    max_attempts=30
    attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if wget --spider -q "${VAULT_ADDR}/v1/sys/health?uninitcode=200&sealedcode=200" 2>/dev/null; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done

    echo "ERROR: Vault did not become ready"
    return 1
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
#   - Queries /v1/sys/seal-status endpoint and parses sealed field
#   - Uses wget for BusyBox compatibility instead of curl
#######################################
is_sealed() {
    status=$(wget -qO- "${VAULT_ADDR}/v1/sys/seal-status" 2>/dev/null | grep -o '"sealed":[^,}]*' | cut -d':' -f2)
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
#   0 - Vault successfully unsealed
#   1 - Keys file not found or unsealing failed
# Outputs:
#   Status and error messages to stdout
# Notes:
#   - Checks for keys file existence before attempting unseal
#   - Extracts first 3 unseal keys from keys file (threshold requirement)
#   - Uses base64-encoded keys of exactly 44 characters
#   - Applies keys sequentially via POST to /v1/sys/unseal
#   - Waits 1 second after applying keys for unseal to complete
#   - Validates unsealing was successful before returning
#   - Returns error if Vault not initialized or keys invalid
#######################################
unseal_vault() {
    if [ ! -f "$VAULT_KEYS_FILE" ]; then
        echo "INFO: Unseal keys file not found: $VAULT_KEYS_FILE"
        echo "INFO: Vault needs to be initialized first"
        return 1
    fi

    echo "INFO: Unsealing Vault..."

    # Extract unseal keys (we need 3 out of 5)
    keys=$(cat "$VAULT_KEYS_FILE" | grep -o '"[^"]*"' | grep '^"[A-Za-z0-9+/=]\{44\}"$' | tr -d '"' | head -3)

    count=$(echo "$keys" | wc -l)
    if [ "$count" -lt 3 ]; then
        echo "ERROR: Could not extract enough unseal keys from $VAULT_KEYS_FILE"
        return 1
    fi

    # Unseal with first 3 keys
    echo "$keys" | while read -r key; do
        if [ -n "$key" ]; then
            wget -qO- --header='Content-Type: application/json' \
                --post-data="{\"key\": \"$key\"}" \
                "${VAULT_ADDR}/v1/sys/unseal" > /dev/null
        fi
    done

    # Wait a moment for unseal to complete
    sleep 1

    if is_sealed; then
        echo "ERROR: Failed to unseal Vault"
        return 1
    fi

    echo "SUCCESS: Vault unsealed successfully"
    return 0
}

#######################################
# Main execution function - monitors and unseals Vault
# Globals:
#   None (calls functions that use VAULT_ADDR and VAULT_KEYS_FILE)
# Arguments:
#   All arguments are ignored (accepts "$@" for compatibility)
# Returns:
#   0 - Normal operation (never returns due to infinite loop)
#   1 - Error during startup or unsealing
# Outputs:
#   Status messages to stdout
# Notes:
#   - Waits for Vault to become ready before proceeding
#   - Checks seal status and unseals if necessary
#   - Enters infinite sleep loop after successful unseal
#   - Sleeps for 3600 seconds (1 hour) per iteration for minimal CPU usage
#   - Designed to keep container alive after unsealing
#   - Does NOT continuously monitor - unseals once at startup only
#   - For continuous monitoring, use a proper init system or supervisor
#######################################
main() {
    echo "Starting Vault auto-unseal..."

    # Wait for Vault to be ready
    if ! wait_for_vault; then
        echo "ERROR: Vault not ready, exiting"
        exit 1
    fi

    echo "Vault is ready"

    # Check and unseal if needed
    if is_sealed; then
        echo "Vault is sealed, attempting to unseal..."
        unseal_vault || exit 1
    else
        echo "Vault is already unsealed"
    fi

    echo "Auto-unseal complete, keeping process alive..."

    # Keep process alive but do nothing (minimal CPU usage)
    # This prevents container from exiting
    while true; do
        sleep 3600
    done
}

main "$@"
