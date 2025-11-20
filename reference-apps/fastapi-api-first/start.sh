#!/bin/bash
#
#######################################
# FastAPI API-First Startup Script
#
# Description:
#   Starts the API-first FastAPI application with dual HTTP/HTTPS support.
#   Launches uvicorn servers for both protocols when TLS is enabled, or
#   HTTP-only mode when TLS is disabled or certificates are unavailable.
#   Manages both server processes with coordinated shutdown handling.
#
# Globals:
#   HTTP_PORT              - HTTP server port (default: 8001)
#   HTTPS_PORT             - HTTPS server port (default: 8444)
#   API_FIRST_ENABLE_TLS   - TLS enablement flag from init.sh
#   CERT_DIR               - Certificate directory path (default: /etc/ssl/certs/api-first)
#   HTTP_PID               - Modified: Process ID of HTTP server
#   HTTPS_PID              - Modified: Process ID of HTTPS server
#
# Usage:
#   ./start.sh
#   HTTP_PORT=9001 HTTPS_PORT=9444 ./start.sh
#   API_FIRST_ENABLE_TLS=true ./start.sh
#
# Dependencies:
#   - uvicorn: ASGI web server for Python
#   - app.main:app: FastAPI application module
#   - bash: Version 4.0 or higher for process management
#
# Exit Codes:
#   0 - Normal shutdown: All server processes terminated cleanly
#   1 - Abnormal shutdown: Server crash or startup failure
#
# Notes:
#   - HTTP server always starts regardless of TLS configuration
#   - HTTPS server only starts if TLS enabled AND certificates exist
#   - Both servers run with --reload for development hot-reloading
#   - Uses background processes with PID tracking for coordinated shutdown
#   - wait -n monitors for first process exit to trigger cleanup
#   - Graceful shutdown: kills remaining processes when one exits
#
# Examples:
#   # Start HTTP-only (default)
#   ./start.sh
#
#   # Start with custom ports
#   HTTP_PORT=9001 HTTPS_PORT=9444 ./start.sh
#
#   # Start with TLS (requires certificates)
#   API_FIRST_ENABLE_TLS=true CERT_DIR=/path/to/certs ./start.sh
#
#######################################

set -e

# Configuration
HTTP_PORT=${HTTP_PORT:-8001}
HTTPS_PORT=${HTTPS_PORT:-8444}
TLS_ENABLED=${API_FIRST_ENABLE_TLS:-false}
CERT_DIR=${CERT_DIR:-/etc/ssl/certs/api-first}

# Certificate paths
CERT_FILE="$CERT_DIR/server.crt"
KEY_FILE="$CERT_DIR/server.key"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#######################################
# Print informational message to stdout
# Globals:
#   BLUE, NC - Terminal color codes
# Arguments:
#   $1 - Message text to display
# Outputs:
#   Writes formatted info message to stdout
#######################################
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

#######################################
# Print success message to stdout
# Globals:
#   GREEN, NC - Terminal color codes
# Arguments:
#   $1 - Message text to display
# Outputs:
#   Writes formatted success message to stdout
#######################################
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

#######################################
# Print warning message to stdout
# Globals:
#   YELLOW, NC - Terminal color codes
# Arguments:
#   $1 - Message text to display
# Outputs:
#   Writes formatted warning message to stdout
#######################################
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

#######################################
# Check if TLS certificates are available and readable
# Verifies both certificate and key files exist at expected paths.
# Globals:
#   CERT_FILE - Path to TLS certificate file
#   KEY_FILE  - Path to TLS private key file
# Arguments:
#   None
# Returns:
#   0 - Both certificate and key files exist
#   1 - One or both files are missing
# Notes:
#   - Uses -f test for regular file existence check
#   - Does not validate certificate contents or format
#   - Does not check file permissions or ownership
#######################################
check_tls_certs() {
    if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        return 0
    else
        return 1
    fi
}

#######################################
# Start HTTP server using uvicorn
# Launches the FastAPI application on HTTP protocol with auto-reload enabled.
# Runs as background process for parallel operation with HTTPS server.
# Globals:
#   HTTP_PORT - Port number for HTTP server
#   HTTP_PID  - Modified: Set to background process ID
# Arguments:
#   None
# Returns:
#   0 - Server started successfully
# Outputs:
#   Status messages to stdout via info/success functions
#   Server logs to stdout from uvicorn
# Notes:
#   - Binds to 0.0.0.0 for all network interfaces
#   - Uses --reload for development (auto-restart on code changes)
#   - Runs in background (&) to allow HTTPS server startup
#   - PID stored in HTTP_PID for shutdown coordination
#######################################
start_http() {
    info "Starting HTTP server on port $HTTP_PORT..."
    uvicorn app.main:app \
        --host 0.0.0.0 \
        --port "$HTTP_PORT" \
        --reload &
    HTTP_PID=$!
    success "HTTP server started (PID: $HTTP_PID)"
}

#######################################
# Start HTTPS server using uvicorn with TLS
# Launches the FastAPI application on HTTPS protocol with TLS encryption.
# Requires valid certificate and key files at configured paths.
# Globals:
#   HTTPS_PORT - Port number for HTTPS server
#   CERT_FILE  - Path to TLS certificate file
#   KEY_FILE   - Path to TLS private key file
#   HTTPS_PID  - Modified: Set to background process ID
# Arguments:
#   None
# Returns:
#   0 - Server started successfully
# Outputs:
#   Status messages to stdout via info/success functions
#   Server logs to stdout from uvicorn
# Notes:
#   - Binds to 0.0.0.0 for all network interfaces
#   - Uses --reload for development (auto-restart on code changes)
#   - Runs in background (&) for parallel operation with HTTP server
#   - PID stored in HTTPS_PID for shutdown coordination
#   - Certificate files must exist and be readable by process
#######################################
start_https() {
    info "Starting HTTPS server on port $HTTPS_PORT..."
    uvicorn app.main:app \
        --host 0.0.0.0 \
        --port "$HTTPS_PORT" \
        --ssl-keyfile "$KEY_FILE" \
        --ssl-certfile "$CERT_FILE" \
        --reload &
    HTTPS_PID=$!
    success "HTTPS server started (PID: $HTTPS_PID)"
}

#######################################
# Main application startup orchestrator
# Coordinates the startup of HTTP and/or HTTPS servers based on configuration,
# monitors server processes, and handles graceful shutdown when servers exit.
# Globals:
#   HTTP_PORT    - HTTP server port number
#   HTTPS_PORT   - HTTPS server port number
#   TLS_ENABLED  - TLS enablement flag
#   CERT_DIR     - Certificate directory path
#   HTTP_PID     - Modified: Set by start_http(), used for shutdown
#   HTTPS_PID    - Modified: Set by start_https(), used for shutdown
# Arguments:
#   $@ - All command-line arguments (currently unused)
# Returns:
#   0 - Normal shutdown after all servers terminated
#   1 - Error during startup or abnormal termination
# Outputs:
#   Startup banner, configuration display, and status messages to stdout
#   Server logs from uvicorn processes to stdout
# Notes:
#   - Always starts HTTP server for baseline connectivity
#   - Conditionally starts HTTPS server based on TLS_ENABLED and cert availability
#   - Uses wait -n to monitor for first process exit
#   - Implements coordinated shutdown: kills all servers if one exits
#   - Final wait ensures clean process termination before exit
#   - Suppresses kill errors (2>/dev/null) for already-terminated processes
#######################################
main() {
    echo ""
    echo "========================================="
    echo "  FastAPI API-First Implementation"
    echo "========================================="
    echo ""

    info "Configuration:"
    echo "  HTTP Port: $HTTP_PORT"
    echo "  HTTPS Port: $HTTPS_PORT"
    echo "  TLS Enabled: $TLS_ENABLED"
    echo "  Certificate Directory: $CERT_DIR"
    echo ""

    # Always start HTTP server
    start_http

    # Start HTTPS server if enabled and certificates are available
    if [ "$TLS_ENABLED" = "true" ]; then
        if check_tls_certs; then
            start_https
            echo ""
            success "Both HTTP and HTTPS servers are running"
            info "  HTTP:  http://0.0.0.0:$HTTP_PORT"
            info "  HTTPS: https://0.0.0.0:$HTTPS_PORT"
        else
            warn "TLS is enabled but certificates not found at $CERT_DIR"
            warn "Only HTTP server is running"
            info "  HTTP:  http://0.0.0.0:$HTTP_PORT"
        fi
    else
        info "TLS is disabled, only HTTP server is running"
        info "  HTTP:  http://0.0.0.0:$HTTP_PORT"
    fi

    echo ""
    info "Application is ready!"
    echo ""

    # Wait for any process to exit
    wait -n

    # If one process exits, kill the other
    if [ -n "$HTTP_PID" ]; then
        kill $HTTP_PID 2>/dev/null || true
    fi
    if [ -n "$HTTPS_PID" ]; then
        kill $HTTPS_PID 2>/dev/null || true
    fi

    # Wait for all processes to finish
    wait
}

# Run main function
main "$@"
