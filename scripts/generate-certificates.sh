#!/usr/bin/env bash
#######################################
# Certificate Pre-Generation Script
#
# This script pre-generates TLS certificates for all services from Vault PKI.
# Certificates are stored in ~/.config/vault/certs/ and can be mounted into containers.
#
# Benefits:
# - Decouples certificate generation from service startup
# - Faster service initialization
# - Certificates can be validated before service deployment
# - Enables certificate rotation without service dependency on Vault PKI timing
#
# Globals:
#   VAULT_ADDR          - Vault server address (default: http://localhost:8200)
#   VAULT_TOKEN         - Vault authentication token (required)
#   CERT_BASE_DIR       - Base directory for certificate storage (default: ~/.config/vault/certs)
#   CERT_TTL            - Certificate time-to-live (default: 8760h / 1 year)
#   SERVICES            - Array of service:ip pairs for certificate generation
#   RED, GREEN, YELLOW, BLUE, NC - Terminal color codes for formatted output
#
# Arguments:
#   None
#
# Usage:
#   ./generate-certificates.sh
#
#   Or with custom Vault address and token:
#   VAULT_ADDR=http://vault:8200 VAULT_TOKEN=s.xxxxx ./generate-certificates.sh
#
# Dependencies:
#   - bash (version 4.0+)
#   - curl
#   - jq
#   - openssl
#   - vault (server must be running and unsealed)
#   - vault-bootstrap.sh must have been run to initialize PKI
#
# Exit Codes:
#   0 - Success: all certificates generated successfully
#   1 - Error: missing required dependencies, Vault not ready, PKI not initialized,
#       or certificate generation failed for one or more services
#
# Prerequisites:
#   - Vault must be running and unsealed
#   - vault-bootstrap.sh must have been run to initialize PKI and roles
#   - VAULT_ADDR and VAULT_TOKEN must be set (or token in ~/.config/vault/root-token)
#
# Notes:
#   - Existing valid certificates (>30 days remaining) are not regenerated
#   - Certificates are generated with 1 year TTL by default
#   - Service-specific certificate formats are handled automatically:
#     * PostgreSQL: server.crt, server.key, ca.crt
#     * MySQL: server-cert.pem, server-key.pem, ca.pem
#     * Redis: redis.crt, redis.key
#     * MongoDB: mongodb.pem (combined cert+key), ca.pem
#     * RabbitMQ: server.pem, key.pem, ca.pem
#     * Forgejo: server.crt, server.key, ca.crt
#     * reference-api: server.crt, server.key, ca.crt
#   - Private keys are stored with 600 permissions for security
#   - Certificates include:
#     * Common name: <service>.dev-services.local
#     * Alt names: localhost
#     * IP SANs: 127.0.0.1, <service-specific-ip>
#
# Examples:
#   # Basic usage (uses default VAULT_ADDR and token from ~/.config/vault/root-token)
#   ./generate-certificates.sh
#
#   # Regenerate all certificates (delete and re-run)
#   rm -rf ~/.config/vault/certs/
#   ./generate-certificates.sh
#
#   # Regenerate certificate for a specific service
#   rm -rf ~/.config/vault/certs/postgres/
#   ./generate-certificates.sh
#######################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-$(cat ~/.config/vault/root-token 2>/dev/null)}"
CERT_BASE_DIR="${HOME}/.config/vault/certs"
CERT_TTL="8760h"  # 1 year

# Service configuration (service:ip pairs)
SERVICES=(
    "postgres:172.20.2.10"
    "mysql:172.20.2.12"
    "redis-1:172.20.2.13"
    "redis-2:172.20.2.16"
    "redis-3:172.20.2.17"
    "rabbitmq:172.20.2.14"
    "mongodb:172.20.2.15"
    "forgejo:172.20.3.20"
    "reference-api:172.20.3.100"
)

# Helper functions
#######################################
# Print an informational message to stdout with blue formatting.
#
# Globals:
#   BLUE - ANSI color code for blue text
#   NC   - ANSI color code to reset text color
#
# Arguments:
#   $1 - The message to print
#
# Returns:
#   0 - Always succeeds
#
# Outputs:
#   Writes formatted message to stdout in format: [INFO] <message>
#
# Examples:
#   info "Starting certificate generation"
#   info "Vault address: $VAULT_ADDR"
#######################################
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

#######################################
# Print a success message to stdout with green formatting.
#
# Globals:
#   GREEN - ANSI color code for green text
#   NC    - ANSI color code to reset text color
#
# Arguments:
#   $1 - The success message to print
#
# Returns:
#   0 - Always succeeds
#
# Outputs:
#   Writes formatted message to stdout in format: [SUCCESS] <message>
#
# Examples:
#   success "Certificate generated successfully"
#   success "Vault is ready"
#######################################
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

#######################################
# Print a warning message to stdout with yellow formatting.
#
# Globals:
#   YELLOW - ANSI color code for yellow text
#   NC     - ANSI color code to reset text color
#
# Arguments:
#   $1 - The warning message to print
#
# Returns:
#   0 - Always succeeds
#
# Outputs:
#   Writes formatted message to stdout in format: [WARN] <message>
#
# Notes:
#   Unlike error(), this function does not terminate the script.
#   Use for non-fatal issues that should be brought to user's attention.
#
# Examples:
#   warn "Certificate expires in less than 30 days"
#   warn "Retrying certificate request after failure"
#######################################
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

#######################################
# Print an error message to stderr with red formatting and exit the script.
#
# Globals:
#   RED - ANSI color code for red text
#   NC  - ANSI color code to reset text color
#
# Arguments:
#   $1 - The error message to print
#
# Returns:
#   Never returns - always exits with code 1
#
# Outputs:
#   Writes formatted error message to stdout in format: [ERROR] <message>
#   Then terminates the script with exit code 1
#
# Notes:
#   This is a fatal error handler. Script execution stops immediately.
#   Use warn() instead for non-fatal issues.
#
# Examples:
#   error "VAULT_TOKEN environment variable is required"
#   error "Vault did not become ready in time"
#######################################
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

#######################################
# Wait for Vault server to become ready and responsive.
#
# Polls the Vault health endpoint until it responds successfully or timeout is reached.
# Uses a 2-second polling interval with a maximum of 60 attempts (120 seconds total).
#
# Globals:
#   VAULT_ADDR - Vault server address to check
#
# Arguments:
#   None
#
# Returns:
#   0 - Vault is ready and responsive
#   1 - Vault did not become ready within timeout (via error() call)
#
# Outputs:
#   Writes status messages to stdout via info(), success(), and error() functions
#
# Notes:
#   - Checks the /v1/sys/health endpoint with standbyok=true parameter
#   - standbyok=true allows standby nodes to be considered healthy
#   - Total timeout is 120 seconds (60 attempts * 2 seconds)
#   - Exits the script if Vault doesn't become ready (via error() function)
#   - Requires curl to be available on the system
#
# Examples:
#   wait_for_vault
#   # Script will wait up to 120 seconds for Vault to be ready
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
# Wait for Vault PKI to be fully ready and capable of issuing certificates.
#
# This function performs a three-stage readiness check:
# 1. Waits for the PKI CA endpoint to respond (up to 60 seconds)
# 2. Allows a 10-second grace period for issuance endpoints to stabilize
# 3. Tests actual certificate issuance capability (up to 10 attempts with 5s intervals)
#
# Globals:
#   VAULT_ADDR  - Vault server address
#   VAULT_TOKEN - Vault authentication token
#
# Arguments:
#   None
#
# Returns:
#   0 - PKI is ready and can successfully issue certificates
#   1 - PKI did not become ready within timeout (via error() call)
#
# Outputs:
#   Writes status messages to stdout via info(), success(), warn(), and error() functions
#
# Notes:
#   - Stage 1: Checks /v1/pki_int/ca/pem endpoint (30 attempts * 2s = 60s timeout)
#   - Stage 2: 10-second grace period for internal PKI initialization
#   - Stage 3: Tests actual certificate issuance using postgres-role (10 attempts * 5s = 50s timeout)
#   - Total maximum wait time: ~120 seconds
#   - Test certificate uses common_name "postgres.dev-services.local" with 1h TTL
#   - Verifies response contains "certificate" field to confirm successful issuance
#   - Exits the script if PKI doesn't become ready (via error() function)
#   - Requires curl and grep to be available on the system
#   - Assumes vault-bootstrap.sh has already created the postgres-role
#
# Examples:
#   wait_for_vault_pki
#   # Script will wait for PKI to be ready and test certificate issuance
#######################################
wait_for_vault_pki() {
    info "Waiting for Vault PKI to be fully ready..."

    local max_attempts=30
    local attempt=0

    # First, wait for PKI CA endpoint
    while [ $attempt -lt $max_attempts ]; do
        if curl -sf "$VAULT_ADDR/v1/pki_int/ca/pem" > /dev/null 2>&1; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    if [ $attempt -ge $max_attempts ]; then
        error "Vault PKI CA endpoint did not become ready"
    fi

    # Additional grace period for issuance endpoints to stabilize
    info "PKI CA ready, waiting for issuance endpoints to stabilize..."
    sleep 10

    # Test certificate issuance is actually working
    info "Testing certificate issuance capability..."
    local test_attempts=10
    local test_attempt=0

    while [ $test_attempt -lt $test_attempts ]; do
        local test_response=$(curl -sf --connect-timeout 5 --max-time 15 \
            -X POST \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"common_name":"postgres.dev-services.local","ttl":"1h"}' \
            "$VAULT_ADDR/v1/pki_int/issue/postgres-role" 2>&1)

        if echo "$test_response" | grep -q '"certificate"'; then
            success "Vault PKI issuance endpoint is ready"
            return 0
        fi

        test_attempt=$((test_attempt + 1))
        if [ $test_attempt -lt $test_attempts ]; then
            warn "Test certificate issuance attempt $test_attempt failed, retrying in 5 seconds..."
            sleep 5
        fi
    done

    error "Vault PKI issuance endpoint did not become ready after $test_attempts attempts"
}

#######################################
# Check if a certificate file exists and has more than 30 days until expiration.
#
# This function determines whether a certificate needs to be regenerated by checking:
# 1. Whether the certificate file exists
# 2. Whether the certificate can be parsed by OpenSSL
# 3. Whether the certificate has more than 30 days until expiration
#
# Globals:
#   None
#
# Arguments:
#   $1 - Path to the certificate file to validate (e.g., server.crt)
#
# Returns:
#   0 - Certificate exists, is valid, and has >30 days remaining
#   1 - Certificate doesn't exist, can't be parsed, or expires within 30 days
#
# Outputs:
#   None (silent operation, no output to stdout/stderr)
#
# Notes:
#   - Uses openssl x509 command to parse certificate expiration date
#   - Date parsing uses macOS/BSD date format with -j flag
#   - 30-day threshold provides buffer for certificate rotation
#   - Suppresses openssl errors to /dev/null for cleaner output
#   - Days remaining calculated as: (expiry_epoch - now_epoch) / 86400
#   - Return code can be used directly in if statements for flow control
#
# Examples:
#   if is_cert_valid "/path/to/server.crt"; then
#       echo "Certificate is still valid"
#   else
#       echo "Certificate needs renewal"
#   fi
#######################################
is_cert_valid() {
    local cert_file=$1

    if [ ! -f "$cert_file" ]; then
        return 1  # Certificate doesn't exist
    fi

    # Check if certificate expires in more than 30 days
    local expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -z "$expiry_date" ]; then
        return 1  # Can't parse certificate
    fi

    local expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
    local now_epoch=$(date +%s)
    local days_remaining=$(( ($expiry_epoch - $now_epoch) / 86400 ))

    if [ $days_remaining -gt 30 ]; then
        return 0  # Certificate is valid
    else
        return 1  # Certificate expiring soon
    fi
}

#######################################
# Generate or verify a TLS certificate for a specific service.
#
# This function:
# 1. Checks if an existing valid certificate exists (>30 days remaining)
# 2. If not, requests a new certificate from Vault PKI
# 3. Saves the certificate, private key, and CA chain to service-specific directory
# 4. Creates service-specific certificate formats as needed (MySQL, Redis, MongoDB, RabbitMQ)
# 5. Sets appropriate file permissions (600 for keys, 644 for certificates)
# 6. Displays certificate information (subject, expiry, location)
#
# Globals:
#   CERT_BASE_DIR - Base directory for certificate storage
#   VAULT_ADDR    - Vault server address
#   VAULT_TOKEN   - Vault authentication token
#   CERT_TTL      - Certificate time-to-live
#
# Arguments:
#   $1 - Service pair in format "service:ip" (e.g., "postgres:172.20.0.10")
#        The service name is extracted from the part before the colon
#        The IP address is extracted from the part after the colon
#
# Returns:
#   0 - Certificate already valid or successfully generated
#   1 - Certificate generation failed (via error() call)
#
# Outputs:
#   Writes status messages to stdout via info(), success(), warn(), and error() functions
#   Creates certificate files in $CERT_BASE_DIR/$service/ directory
#
# Side Effects:
#   Creates directories and files under $CERT_BASE_DIR/$service/
#   Standard files created for all services:
#     - server.crt: Server certificate
#     - server.key: Private key (permissions: 600)
#     - ca.crt: CA certificate chain
#
#   Additional service-specific files:
#     - MySQL: server-cert.pem, server-key.pem, ca.pem
#     - Redis: redis.crt, redis.key
#     - MongoDB: mongodb.pem (combined cert+key), ca.pem
#     - RabbitMQ: server.pem, key.pem, ca.pem
#
# Notes:
#   - Skips generation if existing certificate is valid (>30 days remaining)
#   - Certificate includes:
#     * Common Name: <service>.dev-services.local
#     * Alt Names: localhost
#     * IP SANs: 127.0.0.1, <service-specific-ip>
#   - Uses Vault PKI role: <service>-role
#   - Requires jq for JSON parsing of Vault response
#   - Requires openssl for certificate validation and info display
#   - curl timeout: 10 seconds connect, 30 seconds max
#   - Exits script on failure (via error() function)
#
# Examples:
#   generate_certificate "postgres:172.20.0.10"
#   generate_certificate "mysql:172.20.0.12"
#   generate_certificate "redis-1:172.20.0.13"
#######################################
generate_certificate() {
    local service_pair=$1
    local service="${service_pair%%:*}"
    local service_ip="${service_pair##*:}"

    info "Generating certificate for $service..."

    # Create service-specific directory
    local cert_dir="$CERT_BASE_DIR/$service"
    mkdir -p "$cert_dir"

    # Check if existing certificate is still valid
    if is_cert_valid "$cert_dir/server.crt"; then
        local expiry=$(openssl x509 -in "$cert_dir/server.crt" -noout -enddate | cut -d= -f2)
        success "Certificate for $service is still valid (expires: $expiry), skipping generation"
        return 0
    fi

    # Request certificate from Vault
    # Note: Only using allowed alt_names (localhost), roles don't allow bare service names
    local cert_response=$(curl -s --connect-timeout 10 --max-time 30 \
        -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"common_name\": \"$service.dev-services.local\",
            \"alt_names\": \"localhost\",
            \"ip_sans\": \"127.0.0.1,$service_ip\",
            \"ttl\": \"$CERT_TTL\"
        }" \
        "$VAULT_ADDR/v1/pki_int/issue/${service}-role" 2>&1)

    local curl_exit=$?

    if [ $curl_exit -ne 0 ] || ! echo "$cert_response" | grep -q '"certificate"'; then
        warn "Certificate request failed for $service (curl exit: $curl_exit)"
        warn "Response: $cert_response"
        error "Failed to generate certificate for $service"
    fi

    # Extract and save certificate components
    echo "$cert_response" | jq -r '.data.certificate' > "$cert_dir/server.crt"
    echo "$cert_response" | jq -r '.data.private_key' > "$cert_dir/server.key"
    echo "$cert_response" | jq -r '.data.ca_chain[]' > "$cert_dir/ca.crt"

    # Set permissions (restrictive for keys)
    chmod 600 "$cert_dir/server.key"
    chmod 644 "$cert_dir/server.crt" "$cert_dir/ca.crt"

    # Service-specific certificate formats
    case $service in
        mysql)
            # MySQL wants separate cert and key files
            cp "$cert_dir/server.crt" "$cert_dir/server-cert.pem"
            cp "$cert_dir/server.key" "$cert_dir/server-key.pem"
            cp "$cert_dir/ca.crt" "$cert_dir/ca.pem"
            chmod 600 "$cert_dir/server-key.pem"
            chmod 644 "$cert_dir/server-cert.pem" "$cert_dir/ca.pem"
            ;;
        redis-*)
            # Redis wants .crt and .key extensions
            cp "$cert_dir/server.crt" "$cert_dir/redis.crt"
            cp "$cert_dir/server.key" "$cert_dir/redis.key"
            chmod 600 "$cert_dir/redis.key"
            chmod 644 "$cert_dir/redis.crt"
            ;;
        mongodb)
            # MongoDB wants cert and key in the same file
            cat "$cert_dir/server.crt" "$cert_dir/server.key" > "$cert_dir/mongodb.pem"
            cp "$cert_dir/ca.crt" "$cert_dir/ca.pem"
            chmod 600 "$cert_dir/mongodb.pem"
            chmod 644 "$cert_dir/ca.pem"
            ;;
        rabbitmq)
            # RabbitMQ wants .pem extensions
            cp "$cert_dir/server.crt" "$cert_dir/server.pem"
            cp "$cert_dir/server.key" "$cert_dir/key.pem"
            cp "$cert_dir/ca.crt" "$cert_dir/ca.pem"
            chmod 600 "$cert_dir/key.pem"
            chmod 644 "$cert_dir/server.pem" "$cert_dir/ca.pem"
            ;;
    esac

    # Display certificate info
    local expiry=$(openssl x509 -in "$cert_dir/server.crt" -noout -enddate | cut -d= -f2)
    local subject=$(openssl x509 -in "$cert_dir/server.crt" -noout -subject | sed 's/subject=//')

    success "Generated certificate for $service"
    info "  Subject: $subject"
    info "  Expires: $expiry"
    info "  Location: $cert_dir/"
}

#######################################
# Main execution function - orchestrates certificate generation for all services.
#
# This function:
# 1. Validates required environment variables (VAULT_TOKEN)
# 2. Waits for Vault to be ready and responsive
# 3. Waits for Vault PKI to be fully initialized and capable of issuing certificates
# 4. Creates base certificate directory structure
# 5. Iterates through all services and generates/validates certificates
# 6. Displays completion summary and next steps
#
# Globals:
#   VAULT_TOKEN   - Vault authentication token (required)
#   CERT_BASE_DIR - Base directory for certificate storage
#   SERVICES      - Array of service:ip pairs to process
#
# Arguments:
#   $@ - Optional arguments (currently unused, reserved for future enhancements)
#
# Returns:
#   0 - All certificates processed successfully
#   1 - VAULT_TOKEN missing, Vault not ready, PKI not ready, or any certificate generation failed
#
# Outputs:
#   Writes formatted messages to stdout:
#     - Header banner with script title
#     - Progress messages for each stage
#     - Certificate generation status for each service
#     - Completion banner with next steps
#     - Instructions for certificate rotation
#
# Side Effects:
#   - Creates $CERT_BASE_DIR directory if it doesn't exist
#   - Calls wait_for_vault() to ensure Vault availability
#   - Calls wait_for_vault_pki() to ensure PKI readiness
#   - Calls generate_certificate() for each service in SERVICES array
#   - May create numerous certificate files and directories under $CERT_BASE_DIR
#
# Notes:
#   - Exits immediately if VAULT_TOKEN is not set (via error() function)
#   - Exits if Vault or PKI readiness checks fail (via error() function in called functions)
#   - Exits if any certificate generation fails (via error() function in generate_certificate())
#   - set -e is enabled at script level, so any unhandled error will terminate execution
#   - Processes services sequentially, not in parallel
#   - Existing valid certificates (>30 days) are skipped, not regenerated
#
# Services Processed:
#   - postgres (172.20.0.10)
#   - mysql (172.20.0.12)
#   - redis-1 (172.20.0.13)
#   - redis-2 (172.20.0.16)
#   - redis-3 (172.20.0.17)
#   - rabbitmq (172.20.0.14)
#   - mongodb (172.20.0.15)
#   - forgejo (172.20.0.20)
#   - reference-api (172.20.0.100)
#
# Examples:
#   main
#   # Processes all services and generates certificates as needed
#######################################
main() {
    echo ""
    echo "========================================="
    echo "  Certificate Pre-Generation"
    echo "========================================="
    echo ""

    # Check required environment variables
    if [ -z "$VAULT_TOKEN" ]; then
        error "VAULT_TOKEN environment variable is required"
    fi

    # Wait for Vault
    wait_for_vault

    # Wait for Vault PKI to be fully ready
    wait_for_vault_pki

    # Create base certificate directory
    mkdir -p "$CERT_BASE_DIR"

    # Generate certificates for all services
    info ""
    info "Generating certificates for all services..."
    info ""

    for service_pair in "${SERVICES[@]}"; do
        generate_certificate "$service_pair"
    done

    echo ""
    echo "========================================="
    success "Certificate generation completed!"
    echo "========================================="
    echo ""
    info "Next steps:"
    echo "  1. Certificates stored in: $CERT_BASE_DIR/"
    echo "  2. Restart services to use new certificates"
    echo "  3. Verify TLS connectivity for each service"
    echo ""
    info "To rotate certificates:"
    echo "  1. Delete old certificates: rm -rf $CERT_BASE_DIR/<service>/"
    echo "  2. Re-run this script"
    echo "  3. Restart affected services"
    echo ""
}

# Run main function
main "$@"
