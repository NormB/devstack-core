#!/usr/bin/env bash
# ===========================================================================
# Vault PKI and Secrets Bootstrap Script
# ===========================================================================
#
# DESCRIPTION:
#   Bootstraps complete Vault PKI infrastructure and secrets management for
#   microservices. Establishes two-tier CA hierarchy (Root + Intermediate),
#   generates service-specific certificate roles, creates and stores secure
#   credentials, and exports CA certificates for client trust. Designed for
#   development environments with production-ready PKI architecture.
#
# GLOBALS:
#   VAULT_ADDR    - Vault server address (default: http://localhost:8200)
#   VAULT_TOKEN   - Vault authentication token (default: from ~/.config/vault/root-token)
#   EXPORT_DIR    - CA certificates export directory (default: ~/.config/vault/ca)
#   ROOT_CA_TTL   - Root CA certificate lifetime (default: 87600h / 10 years)
#   INT_CA_TTL    - Intermediate CA lifetime (default: 43800h / 5 years)
#   CERT_TTL      - Service certificate lifetime (default: 8760h / 1 year)
#   KEY_TYPE      - Certificate key type (default: rsa)
#   KEY_BITS      - RSA key size in bits (default: 2048)
#   SERVICES      - Array of service:ip pairs for certificate generation
#   RED, GREEN, YELLOW, BLUE, NC - Terminal color codes for output formatting
#
# USAGE:
#   ./vault-bootstrap.sh
#
# DEPENDENCIES:
#   - curl        - For HTTP requests to Vault API
#   - jq          - For JSON parsing and manipulation
#   - openssl     - For random password generation
#   - grep, cat   - For text processing
#   - HashiCorp Vault - Server must be initialized, unsealed, and accessible
#
# EXIT CODES:
#   0  - Success: Complete bootstrap finished
#   1  - Error: Vault not ready, token missing, or API operation failed
#
# NOTES:
#   - Creates hierarchical PKI: Root CA -> Intermediate CA -> Service Certs
#   - Enables KV v2 secrets engine at path 'secret/'
#   - Generates 25-character alphanumeric passwords for each service
#   - Creates Vault policies for service-level access control
#   - Exports CA chain to ~/.config/vault/ca/ for client configuration
#   - Script is idempotent: skips existing resources, safe to re-run
#   - Service credentials include tls_enabled flag for dynamic TLS control
#   - Redis cluster nodes share the same password
#
# SERVICES CONFIGURED:
#   - postgres (172.20.0.10)      - PostgreSQL with user credentials
#   - mysql (172.20.0.12)         - MySQL with root and user credentials
#   - redis-1/2/3 (172.20.0.13/16/17) - Redis cluster with shared password
#   - rabbitmq (172.20.0.14)      - RabbitMQ with vhost configuration
#   - mongodb (172.20.0.15)       - MongoDB with database credentials
#   - forgejo (172.20.0.20)       - Forgejo Git service
#   - reference-api (172.20.0.100) - API reference service
#
# EXAMPLES:
#   # Bootstrap with default configuration:
#   ./vault-bootstrap.sh
#
#   # Bootstrap with custom Vault address:
#   VAULT_ADDR=https://vault.example.com:8200 ./vault-bootstrap.sh
#
#   # Bootstrap with explicit token:
#   VAULT_TOKEN=hvs.CAESIJ... ./vault-bootstrap.sh
#
#   # Retrieve service credentials after bootstrap:
#   vault kv get -field=password secret/postgres
#   vault read -field=certificate pki_int/issue/postgres-role common_name=postgres
#
# ===========================================================================

set -e

# Colors for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-$(cat ~/.config/vault/root-token 2>/dev/null)}"
EXPORT_DIR="${HOME}/.config/vault/ca"

# Certificate configuration
ROOT_CA_TTL="87600h"     # 10 years
INT_CA_TTL="43800h"      # 5 years
CERT_TTL="8760h"         # 1 year
KEY_TYPE="rsa"
KEY_BITS="2048"

# Service configuration (service:ip pairs)
SERVICES=(
    "postgres:172.20.0.10"
    "mysql:172.20.0.12"
    "redis-1:172.20.0.13"
    "redis-2:172.20.0.16"
    "redis-3:172.20.0.17"
    "rabbitmq:172.20.0.14"
    "mongodb:172.20.0.15"
    "forgejo:172.20.0.20"
    "reference-api:172.20.0.100"
)

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
warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
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
# Generate cryptographically secure random password
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   None
# Outputs:
#   25-character alphanumeric password to stdout
# Notes:
#   - Uses OpenSSL for cryptographic randomness
#   - Removes special characters (=, +, /) for compatibility
#   - Fixed length of 25 characters
#######################################
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

#######################################
# Check if Vault is ready and accessible with valid token
# Globals:
#   VAULT_ADDR  - Vault server address to check
#   VAULT_TOKEN - Authentication token to validate
# Arguments:
#   None
# Returns:
#   0 - Vault is ready and token is valid
#   1 - Token missing or Vault not responding (via error function)
# Outputs:
#   Status messages to stdout
# Notes:
#   - Validates VAULT_TOKEN is set before attempting connection
#   - Polls health endpoint up to 30 times with 2-second intervals (60s total)
#   - Requires Vault to be unsealed and accessible
#   - Exits script if Vault doesn't respond within timeout
#######################################
check_vault() {
    info "Checking Vault status..."

    if [ -z "$VAULT_TOKEN" ]; then
        error "VAULT_TOKEN not set. Please set it or ensure ~/.config/vault/root-token exists"
    fi

    for i in {1..30}; do
        if curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
            success "Vault is ready"
            return 0
        fi
        sleep 2
    done

    error "Vault is not responding. Please ensure Vault is running and unsealed"
}

#######################################
# Enable a Vault secrets engine at specified mount path
# Globals:
#   VAULT_ADDR  - Vault server address
#   VAULT_TOKEN - Authentication token
# Arguments:
#   $1 - Engine type (e.g., "pki", "kv-v2")
#   $2 - Mount path for the engine (e.g., "pki", "secret")
# Returns:
#   0 - Engine enabled successfully or already exists
# Outputs:
#   Status messages to stdout
# Notes:
#   - Checks if engine already exists before attempting to enable
#   - Idempotent: safe to call multiple times
#   - Skips with warning if mount path already in use
#######################################
enable_secrets_engine() {
    local engine=$1
    local path=$2

    info "Enabling $engine at $path..."

    # Check if already enabled
    if curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/sys/mounts" | grep -q "\"$path/\""; then
        warn "$path already enabled, skipping"
        return 0
    fi

    # Enable the secrets engine
    curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{\"type\":\"$engine\"}" \
        "$VAULT_ADDR/v1/sys/mounts/$path" > /dev/null

    success "Enabled $engine at $path"
}

#######################################
# Setup and configure Vault Root Certificate Authority
# Globals:
#   VAULT_ADDR    - Vault server address
#   VAULT_TOKEN   - Authentication token
#   ROOT_CA_TTL   - Root CA certificate lifetime
#   KEY_TYPE      - Certificate key type
#   KEY_BITS      - RSA key size
# Arguments:
#   None
# Returns:
#   0 - Root CA configured successfully
# Outputs:
#   Status messages to stdout
# Notes:
#   - Enables PKI secrets engine at 'pki' mount point
#   - Sets maximum lease TTL to ROOT_CA_TTL (10 years)
#   - Generates internal root CA with common name "DevStack Core Root CA"
#   - Configures issuing certificate and CRL distribution URLs
#   - Idempotent: skips generation if root CA already exists
#   - Private key remains internal to Vault (not exported)
#######################################
setup_root_ca() {
    info "Setting up Root CA..."

    # Enable PKI secrets engine for root CA
    enable_secrets_engine "pki" "pki"

    # Tune the mount for longer TTL
    curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{\"max_lease_ttl\":\"$ROOT_CA_TTL\"}" \
        "$VAULT_ADDR/v1/sys/mounts/pki/tune" > /dev/null

    # Check if root CA already exists
    local ca_exists=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/pki/ca/pem" 2>/dev/null || true)

    if [ -z "$ca_exists" ]; then
        # Generate root CA certificate
        info "Generating Root CA certificate..."
        curl -sf -X POST \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            -d "{
                \"common_name\": \"DevStack Core Root CA\",
                \"issuer_name\": \"root-ca\",
                \"ttl\": \"$ROOT_CA_TTL\",
                \"key_type\": \"$KEY_TYPE\",
                \"key_bits\": $KEY_BITS
            }" \
            "$VAULT_ADDR/v1/pki/root/generate/internal" > /dev/null
    else
        warn "Root CA already exists, skipping generation"
    fi

    # Configure CA and CRL URLs
    curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{
            \"issuing_certificates\": [\"$VAULT_ADDR/v1/pki/ca\"],
            \"crl_distribution_points\": [\"$VAULT_ADDR/v1/pki/crl\"]
        }" \
        "$VAULT_ADDR/v1/pki/config/urls" > /dev/null

    success "Root CA configured"
}

#######################################
# Setup and configure Vault Intermediate Certificate Authority
# Globals:
#   VAULT_ADDR  - Vault server address
#   VAULT_TOKEN - Authentication token
#   INT_CA_TTL  - Intermediate CA certificate lifetime
#   KEY_TYPE    - Certificate key type
#   KEY_BITS    - RSA key size
# Arguments:
#   None
# Returns:
#   0 - Intermediate CA configured and signed successfully
# Outputs:
#   Status messages to stdout
# Notes:
#   - Enables PKI secrets engine at 'pki_int' mount point
#   - Sets maximum lease TTL to INT_CA_TTL (5 years)
#   - Generates CSR for intermediate CA
#   - Signs CSR with root CA to create trust chain
#   - Imports signed certificate back into Vault
#   - Configures issuing certificate and CRL distribution URLs
#   - Idempotent: skips generation if intermediate CA already exists
#   - Used for issuing all service certificates
#######################################
setup_intermediate_ca() {
    info "Setting up Intermediate CA..."

    # Enable PKI secrets engine for intermediate CA
    enable_secrets_engine "pki" "pki_int"

    # Tune the mount for intermediate CA TTL
    curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{\"max_lease_ttl\":\"$INT_CA_TTL\"}" \
        "$VAULT_ADDR/v1/sys/mounts/pki_int/tune" > /dev/null

    # Check if intermediate CA already exists
    local int_ca_exists=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/pki_int/ca/pem" 2>/dev/null || true)

    if [ -z "$int_ca_exists" ]; then
        # Generate intermediate CA CSR
        info "Generating Intermediate CA CSR..."
        CSR_RESPONSE=$(curl -sf -X POST \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            -d "{
                \"common_name\": \"DevStack Core Intermediate CA\",
                \"issuer_name\": \"intermediate-ca\",
                \"key_type\": \"$KEY_TYPE\",
                \"key_bits\": $KEY_BITS
            }" \
            "$VAULT_ADDR/v1/pki_int/intermediate/generate/internal")

        CSR=$(echo "$CSR_RESPONSE" | jq -r '.data.csr')

        # Sign intermediate CA with root CA
        info "Signing Intermediate CA with Root CA..."
        SIGNED_CERT_RESPONSE=$(curl -sf -X POST \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            -d "{
                \"csr\": \"$CSR\",
                \"format\": \"pem_bundle\",
                \"ttl\": \"$INT_CA_TTL\"
            }" \
            "$VAULT_ADDR/v1/pki/root/sign-intermediate")

        SIGNED_CERT=$(echo "$SIGNED_CERT_RESPONSE" | jq -r '.data.certificate')
        CA_CHAIN=$(echo "$SIGNED_CERT_RESPONSE" | jq -r '.data.ca_chain | join("\n")')

        # Set the signed certificate
        curl -sf -X POST \
            -H "X-Vault-Token: $VAULT_TOKEN" \
            -d "{\"certificate\": \"$SIGNED_CERT\"}" \
            "$VAULT_ADDR/v1/pki_int/intermediate/set-signed" > /dev/null
    else
        warn "Intermediate CA already exists, skipping generation"
    fi

    # Configure CA and CRL URLs for intermediate
    curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{
            \"issuing_certificates\": [\"$VAULT_ADDR/v1/pki_int/ca\"],
            \"crl_distribution_points\": [\"$VAULT_ADDR/v1/pki_int/crl\"]
        }" \
        "$VAULT_ADDR/v1/pki_int/config/urls" > /dev/null

    success "Intermediate CA configured and signed"
}

#######################################
# Create PKI certificate role for a service
# Globals:
#   VAULT_ADDR  - Vault server address
#   VAULT_TOKEN - Authentication token
#   KEY_TYPE    - Certificate key type
#   KEY_BITS    - RSA key size
#   CERT_TTL    - Certificate lifetime
# Arguments:
#   $1 - Service name (e.g., "postgres", "redis-1")
#   $2 - IP address for service (currently unused but reserved)
# Returns:
#   0 - Role created successfully
# Outputs:
#   Status messages to stdout
# Notes:
#   - Creates role named "${service}-role" in pki_int
#   - Allows domains: ${service}.dev-services.local, localhost
#   - Enables subdomains, bare domains, localhost, and IP SANs
#   - Certificates valid for both server and client authentication
#   - TTL set to CERT_TTL (1 year by default)
#   - Common name (CN) not required for flexibility
#######################################
create_cert_role() {
    local service=$1
    local ip_address=$2
    local role_name="${service}-role"

    info "Creating certificate role for $service..."

    # Build allowed domains and alt names
    local allowed_domains="$service.dev-services.local,localhost"
    local alt_names="$service,dev-$service,localhost"

    # Create the role
    curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{
            \"allowed_domains\": \"$allowed_domains\",
            \"allow_subdomains\": true,
            \"allow_bare_domains\": true,
            \"allow_localhost\": true,
            \"allow_ip_sans\": true,
            \"key_type\": \"$KEY_TYPE\",
            \"key_bits\": $KEY_BITS,
            \"max_ttl\": \"$CERT_TTL\",
            \"ttl\": \"$CERT_TTL\",
            \"require_cn\": false,
            \"server_flag\": true,
            \"client_flag\": true
        }" \
        "$VAULT_ADDR/v1/pki_int/roles/$role_name" > /dev/null

    success "Created role: $role_name"
}

#######################################
# Generate and store service-specific credentials in Vault KV
# Globals:
#   VAULT_ADDR  - Vault server address
#   VAULT_TOKEN - Authentication token
# Arguments:
#   $1 - Service name (e.g., "postgres", "mysql", "redis-1")
# Returns:
#   0 - Credentials stored successfully or already exist
# Outputs:
#   Status messages to stdout
# Notes:
#   - Stores credentials in KV v2 at path secret/${service}
#   - Idempotent: skips if credentials already exist
#   - Updates existing credentials to add tls_enabled flag if missing
#   - All credentials include tls_enabled=true by default
#   - Service-specific credential schemas:
#     * postgres: user, password, database, tls_enabled
#     * mysql: root_password, user, password, database, tls_enabled
#     * redis-*: password, tls_enabled (shared across cluster)
#     * rabbitmq: user, password, vhost, tls_enabled
#     * mongodb: user, password, database, tls_enabled
#     * forgejo: tls_enabled only (uses external PostgreSQL)
#   - Redis cluster (redis-1/2/3) shares same password for cluster auth
#######################################
store_service_credentials() {
    local service=$1

    # Check if credentials already exist
    local existing_creds=$(curl -sf \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/$service" 2>/dev/null)

    if [ -n "$existing_creds" ] && echo "$existing_creds" | jq -e '.data.data' > /dev/null 2>&1; then
        # Check if tls_enabled field exists
        local has_tls=$(echo "$existing_creds" | jq -r '.data.data.tls_enabled // "missing"')

        if [ "$has_tls" = "missing" ] || [ "$has_tls" = "null" ]; then
            info "Adding tls_enabled field to existing credentials for $service..."
            # Add tls_enabled to existing credentials
            local updated_creds=$(echo "$existing_creds" | jq '.data.data + {tls_enabled: true}')
            curl -sf -X POST \
                -H "X-Vault-Token: $VAULT_TOKEN" \
                -d "{\"data\": $updated_creds}" \
                "$VAULT_ADDR/v1/secret/data/$service" > /dev/null
            success "Added tls_enabled=true to $service"
        else
            warn "Credentials for $service already exist (tls_enabled=$has_tls), skipping"
        fi
        return 0
    fi

    info "Generating and storing credentials for $service..."

    # Generate passwords
    local password=$(generate_password)
    local root_password=$(generate_password)

    # Build credentials JSON based on service type
    # All services include tls_enabled flag (default: true)
    local creds_json=""
    case $service in
        postgres)
            creds_json=$(jq -n \
                --arg user "dev_admin" \
                --arg password "$password" \
                --arg database "dev_database" \
                --argjson tls_enabled true \
                '{user: $user, password: $password, database: $database, tls_enabled: $tls_enabled}')
            ;;
        mysql)
            creds_json=$(jq -n \
                --arg root_password "$root_password" \
                --arg user "dev_admin" \
                --arg password "$password" \
                --arg database "dev_database" \
                --argjson tls_enabled true \
                '{root_password: $root_password, user: $user, password: $password, database: $database, tls_enabled: $tls_enabled}')
            ;;
        redis-*)
            # All Redis nodes share the same password
            if [ "$service" = "redis-1" ]; then
                creds_json=$(jq -n \
                    --arg password "$password" \
                    --argjson tls_enabled true \
                    '{password: $password, tls_enabled: $tls_enabled}')
            else
                # Reuse redis-1 password for other nodes
                local redis_password=$(curl -sf \
                    -H "X-Vault-Token: $VAULT_TOKEN" \
                    "$VAULT_ADDR/v1/secret/data/redis-1" | jq -r '.data.data.password')
                creds_json=$(jq -n \
                    --arg password "$redis_password" \
                    --argjson tls_enabled true \
                    '{password: $password, tls_enabled: $tls_enabled}')
            fi
            ;;
        rabbitmq)
            creds_json=$(jq -n \
                --arg user "dev_admin" \
                --arg password "$password" \
                --arg vhost "dev_vhost" \
                --argjson tls_enabled true \
                '{user: $user, password: $password, vhost: $vhost, tls_enabled: $tls_enabled}')
            ;;
        mongodb)
            creds_json=$(jq -n \
                --arg user "dev_admin" \
                --arg password "$password" \
                --arg database "dev_database" \
                --argjson tls_enabled true \
                '{user: $user, password: $password, database: $database, tls_enabled: $tls_enabled}')
            ;;
        forgejo)
            # Forgejo admin credentials and PostgreSQL connection
            # Generate random admin password for initial setup
            creds_json=$(jq -n \
                --arg admin_user "devadmin" \
                --arg admin_password "$password" \
                --arg admin_email "admin@devstack.local" \
                --argjson tls_enabled true \
                '{admin_user: $admin_user, admin_password: $admin_password, admin_email: $admin_email, tls_enabled: $tls_enabled}')
            ;;
    esac

    # Store in Vault
    curl -sf -X POST \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{\"data\": $creds_json}" \
        "$VAULT_ADDR/v1/secret/data/$service" > /dev/null

    success "Stored credentials for $service"
}

#######################################
# Export CA certificate chain to local filesystem
# Globals:
#   VAULT_ADDR  - Vault server address
#   VAULT_TOKEN - Authentication token
#   EXPORT_DIR  - Directory to export certificates to
# Arguments:
#   None
# Returns:
#   0 - Certificates exported successfully
# Outputs:
#   Status messages and file paths to stdout
# Notes:
#   - Creates EXPORT_DIR if it doesn't exist
#   - Exports three certificate files:
#     * ca-chain.pem: Intermediate CA only (for service verification)
#     * root-ca.pem: Root CA only
#     * full-chain.pem: Complete chain (intermediate + root)
#   - Sets file permissions to 644 (world-readable)
#   - Use full-chain.pem for client trust store configuration
#######################################
export_ca_chain() {
    info "Exporting CA certificate chain..."

    mkdir -p "$EXPORT_DIR"

    # Get intermediate CA certificate chain
    curl -sf \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/pki_int/ca/pem" > "$EXPORT_DIR/ca-chain.pem"

    # Get root CA certificate
    curl -sf \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/pki/ca/pem" > "$EXPORT_DIR/root-ca.pem"

    # Create full chain (intermediate + root)
    cat "$EXPORT_DIR/ca-chain.pem" "$EXPORT_DIR/root-ca.pem" > "$EXPORT_DIR/full-chain.pem"

    chmod 644 "$EXPORT_DIR"/*.pem

    success "CA certificates exported to $EXPORT_DIR/"
    info "  - ca-chain.pem: Intermediate CA (use for service verification)"
    info "  - root-ca.pem: Root CA"
    info "  - full-chain.pem: Complete chain (intermediate + root)"
}

#######################################
# Create least-privilege Vault policy for service access
# Globals:
#   VAULT_ADDR  - Vault server address
#   VAULT_TOKEN - Authentication token
# Arguments:
#   $1 - Service name (e.g., "postgres", "mysql")
# Returns:
#   0 - Policy created successfully
# Outputs:
#   Status messages to stdout
# Notes:
#   - Creates policy named "${service}-policy"
#   - Grants read access to service credentials at secret/data/${service}
#   - Grants create/update access to issue certificates via pki_int/issue/${service}-role
#   - Grants read access to CA chain for certificate verification
#   - Policy follows principle of least privilege
#   - Use with Vault AppRole or other auth methods for service authentication
#######################################
create_service_policy() {
    local service=$1
    local policy_name="${service}-policy"

    info "Creating Vault policy for $service..."

    # Create policy HCL
    local policy_hcl=$(cat <<EOF
# Policy for $service service
# Read service credentials
path "secret/data/$service" {
  capabilities = ["read"]
}

# Issue certificates
path "pki_int/issue/${service}-role" {
  capabilities = ["create", "update"]
}

# Read CA chain
path "pki_int/cert/ca_chain" {
  capabilities = ["read"]
}

path "pki_int/ca/pem" {
  capabilities = ["read"]
}
EOF
)

    # Write policy to Vault
    curl -sf -X PUT \
        -H "X-Vault-Token: $VAULT_TOKEN" \
        -d "{\"policy\": $(echo "$policy_hcl" | jq -Rs .)}" \
        "$VAULT_ADDR/v1/sys/policy/$policy_name" > /dev/null

    success "Created policy: $policy_name"
}

#######################################
# Main execution function - orchestrates complete Vault bootstrap
# Globals:
#   VAULT_ADDR  - Vault server address
#   EXPORT_DIR  - CA certificates export directory
#   SERVICES    - Array of services to configure
# Arguments:
#   All arguments are ignored (accepts "$@" for compatibility)
# Returns:
#   0 - Bootstrap completed successfully
#   1 - Error during bootstrap (via error function in called functions)
# Outputs:
#   Formatted status messages and completion summary to stdout
# Notes:
#   - Executes bootstrap steps in strict order:
#     1. Verify Vault is ready and accessible
#     2. Enable KV v2 secrets engine
#     3. Setup Root CA
#     4. Setup Intermediate CA (signed by Root CA)
#     5. Create certificate roles for all services
#     6. Generate and store credentials for all services
#     7. Create access policies for all services
#     8. Export CA certificates to filesystem
#   - All operations are idempotent and safe to re-run
#   - Displays next steps and usage examples upon completion
#######################################
main() {
    echo ""
    echo "========================================="
    echo "  Vault PKI & Secrets Bootstrap"
    echo "========================================="
    echo ""

    # Check Vault is ready
    check_vault

    # Enable KV v2 secrets engine
    info "Setting up secrets storage..."
    enable_secrets_engine "kv-v2" "secret"

    # Setup PKI infrastructure
    info ""
    info "Setting up PKI infrastructure..."
    info ""
    setup_root_ca
    setup_intermediate_ca

    # Create certificate roles for each service
    info ""
    info "Creating certificate roles..."
    info ""
    for service_pair in "${SERVICES[@]}"; do
        service="${service_pair%%:*}"
        ip="${service_pair##*:}"
        create_cert_role "$service" "$ip"
    done

    # Store credentials for each service
    info ""
    info "Generating and storing service credentials..."
    info ""
    for service_pair in "${SERVICES[@]}"; do
        service="${service_pair%%:*}"
        store_service_credentials "$service"
    done

    # Create policies for each service
    info ""
    info "Creating Vault policies..."
    info ""
    for service_pair in "${SERVICES[@]}"; do
        service="${service_pair%%:*}"
        create_service_policy "$service"
    done

    # Export CA certificates
    info ""
    export_ca_chain

    echo ""
    echo "========================================="
    success "Vault bootstrap completed successfully!"
    echo "========================================="
    echo ""
    info "Next steps:"
    echo "  1. Review generated credentials in Vault UI: $VAULT_ADDR/ui"
    echo "  2. CA certificates available at: $EXPORT_DIR/"
    echo "  3. Start services with: docker compose up -d"
    echo ""

    # Display a sample credential retrieval
    info "Example: Retrieve PostgreSQL password:"
    echo "  vault kv get -field=password secret/postgres"
    echo ""
}

# Run main function
main "$@"
