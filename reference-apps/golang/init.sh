#!/bin/sh
set -e

# Configuration
SERVICE_NAME="golang-api"
SERVICE_IP="${GOLANG_API_IP:-172.20.0.105}"
CERT_DIR="/etc/ssl/certs/golang-api"
VAULT_CERT_DIR="${HOME}/.config/vault/certs"
MAX_RETRIES=30
RETRY_DELAY=2

echo "=========================================="
echo "  ${SERVICE_NAME} Initialization"
echo "=========================================="

# Wait for Vault to be ready
wait_for_vault() {
    echo "[INIT] Waiting for Vault to be ready..."

    local retries=0
    while [ $retries -lt $MAX_RETRIES ]; do
        if wget -q --spider "${VAULT_ADDR}/v1/sys/health" 2>/dev/null; then
            echo "[INIT] ✓ Vault is ready"
            return 0
        fi

        retries=$((retries + 1))
        echo "[INIT] Waiting for Vault... (${retries}/${MAX_RETRIES})"
        sleep $RETRY_DELAY
    done

    echo "[INIT] ✗ Vault not available after ${MAX_RETRIES} attempts"
    return 1
}

# Fetch TLS configuration from Vault
fetch_tls_config() {
    if [ "${GOLANG_API_ENABLE_TLS}" != "true" ]; then
        echo "[INIT] TLS disabled, skipping certificate setup"
        return 0
    fi

    echo "[INIT] Fetching TLS certificates from Vault..."

    # Create certificate directory
    mkdir -p "${CERT_DIR}"

    # Fetch certificate
    if ! wget -q --header="X-Vault-Token: ${VAULT_TOKEN}" \
         "${VAULT_ADDR}/v1/pki_int/issue/reference-api" \
         --post-data="{\"common_name\":\"${SERVICE_NAME}\",\"ip_sans\":\"${SERVICE_IP}\",\"ttl\":\"720h\"}" \
         -O /tmp/cert_response.json; then
        echo "[INIT] ✗ Failed to fetch certificate from Vault"
        return 1
    fi

    # Extract and save certificate components
    jq -r '.data.certificate' /tmp/cert_response.json > "${CERT_DIR}/cert.pem"
    jq -r '.data.private_key' /tmp/cert_response.json > "${CERT_DIR}/key.pem"
    jq -r '.data.issuing_ca' /tmp/cert_response.json > "${CERT_DIR}/ca.pem"

    # Set permissions
    chmod 600 "${CERT_DIR}/key.pem"
    chmod 644 "${CERT_DIR}/cert.pem" "${CERT_DIR}/ca.pem"

    echo "[INIT] ✓ TLS certificates configured"
    rm /tmp/cert_response.json
    return 0
}

# Main initialization
main() {
    echo "[INIT] Starting initialization for ${SERVICE_NAME}"
    echo "[INIT] Service IP: ${SERVICE_IP}"
    echo "[INIT] Vault Address: ${VAULT_ADDR}"
    echo "[INIT] TLS Enabled: ${GOLANG_API_ENABLE_TLS:-false}"

    # Wait for Vault
    if ! wait_for_vault; then
        echo "[INIT] ✗ Initialization failed: Vault not available"
        exit 1
    fi

    # Fetch TLS configuration if enabled
    if ! fetch_tls_config; then
        echo "[INIT] ⚠ TLS setup failed, continuing without TLS"
    fi

    echo "[INIT] ✓ Initialization complete"
    echo "=========================================="

    # Start the application
    exec /app/start.sh
}

main "$@"
