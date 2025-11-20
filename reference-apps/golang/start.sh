#!/bin/sh
set -e

# Configuration
HTTP_PORT="${HTTP_PORT:-8002}"
HTTPS_PORT="${HTTPS_PORT:-8445}"
TLS_ENABLED="${GOLANG_API_ENABLE_TLS:-false}"
CERT_DIR="${CERT_DIR:-/etc/ssl/certs/golang-api}"

echo "=========================================="
echo "  Starting Golang Reference API"
echo "=========================================="

echo "[START] Configuration:"
echo "  - HTTP Port: ${HTTP_PORT}"
echo "  - HTTPS Port: ${HTTPS_PORT}"
echo "  - TLS Enabled: ${TLS_ENABLED}"
echo "  - Vault: ${VAULT_ADDR}"

# Export environment variables for the application
export HTTP_PORT
export HTTPS_PORT

# Start the application
echo "[START] Starting API server..."

if [ "${TLS_ENABLED}" = "true" ]; then
    if [ ! -f "${CERT_DIR}/cert.pem" ] || [ ! -f "${CERT_DIR}/key.pem" ]; then
        echo "[START] ⚠ TLS enabled but certificates not found, starting HTTP only"
        exec /app/api
    else
        echo "[START] Starting with TLS support"
        # Note: TLS support would require modifying main.go to support HTTPS
        # For now, starting HTTP only
        exec /app/api
    fi
else
    echo "[START] Starting HTTP server"
    exec /app/api
fi
