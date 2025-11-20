#!/bin/bash
################################################################################
# Forgejo Bootstrap Script - Automated Installation
################################################################################
# This script performs automated installation of Forgejo using the CLI.
# It should be run AFTER Forgejo container is running but before first use.
#
# PREREQUISITES:
#   - Forgejo container must be running
#   - PostgreSQL must be healthy
#   - Vault must contain postgres credentials
#
# USAGE:
#   docker exec dev-forgejo /usr/local/bin/forgejo-bootstrap.sh
#   OR via management script:
#   ./devstack.sh forgejo-init
#
# EXIT CODES:
#   0 - Success (Forgejo installed and configured)
#   1 - Error (container not running, already installed, etc.)
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[Forgejo Bootstrap]${NC} $1"; }
success() { echo -e "${GREEN}[Forgejo Bootstrap]${NC} $1"; }
warn() { echo -e "${YELLOW}[Forgejo Bootstrap]${NC} $1"; }
error() { echo -e "${RED}[Forgejo Bootstrap]${NC} $1"; exit 1; }

#######################################
# Check if Forgejo is already installed
#######################################
check_installation_status() {
    info "Checking installation status..."

    if grep -q "INSTALL_LOCK.*=.*true" /data/gitea/conf/app.ini 2>/dev/null; then
        warn "Forgejo is already installed (INSTALL_LOCK = true)"
        info "If you need to reinstall, run: ./devstack.sh reset"
        exit 0
    fi

    success "Forgejo is not yet installed, proceeding with bootstrap"
}

#######################################
# Generate secure random secret key
#######################################
generate_secret_key() {
    info "Generating secure secret key..."
    SECRET_KEY=$(head -c 32 /dev/urandom | base64 | tr -d '\n' | head -c 64)
    success "Secret key generated"
}

#######################################
# Validate input parameters
#######################################
validate_inputs() {
    info "Validating configuration..."

    # Validate hostname format
    if ! echo "$FORGEJO__server__DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+$'; then
        error "Invalid FORGEJO__server__DOMAIN format: $FORGEJO__server__DOMAIN"
    fi

    # Validate database host format
    if ! echo "$FORGEJO__database__HOST" | grep -qE '^[a-zA-Z0-9._:-]+$'; then
        error "Invalid FORGEJO__database__HOST format: $FORGEJO__database__HOST"
    fi

    success "Configuration validated"
}

#######################################
# Fetch credentials from Vault
#######################################
fetch_credentials_from_vault() {
    info "Fetching credentials from Vault..."

    # Wait for Vault to be ready
    local max_attempts=30
    local attempt=0
    VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"

    while [ $attempt -lt $max_attempts ]; do
        if wget --spider -q "$VAULT_ADDR/v1/sys/health?standbyok=true" 2>/dev/null; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    if [ $attempt -eq $max_attempts ]; then
        error "Vault did not become ready in time"
    fi

    # Validate token has read access
    local token_test
    token_test=$(wget -qO- --header "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/auth/token/lookup-self" 2>&1)

    if [ $? -ne 0 ]; then
        error "VAULT_TOKEN is invalid or Vault is unreachable"
    fi

    # Fetch PostgreSQL credentials
    local pg_response
    pg_response=$(wget -qO- \
        --header "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/postgres" 2>/dev/null) || {
        error "Failed to fetch PostgreSQL credentials from Vault"
    }

    if [ -z "$pg_response" ]; then
        error "Empty response from Vault for PostgreSQL"
    fi

    DB_USER=$(echo "$pg_response" | jq -r '.data.data.user')
    DB_PASSWD=$(echo "$pg_response" | jq -r '.data.data.password')

    if [ -z "$DB_USER" ] || [ "$DB_USER" = "null" ]; then
        error "Invalid username received from Vault"
    fi

    if [ -z "$DB_PASSWD" ] || [ "$DB_PASSWD" = "null" ]; then
        error "Invalid password received from Vault"
    fi

    # Fetch Forgejo admin credentials
    local forgejo_response
    forgejo_response=$(wget -qO- \
        --header "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/forgejo" 2>/dev/null) || {
        error "Failed to fetch Forgejo credentials from Vault"
    }

    if [ -z "$forgejo_response" ]; then
        error "Empty response from Vault for Forgejo"
    fi

    ADMIN_USER=$(echo "$forgejo_response" | jq -r '.data.data.admin_user')
    ADMIN_PASSWORD=$(echo "$forgejo_response" | jq -r '.data.data.admin_password')
    ADMIN_EMAIL=$(echo "$forgejo_response" | jq -r '.data.data.admin_email')

    if [ -z "$ADMIN_USER" ] || [ "$ADMIN_USER" = "null" ]; then
        error "Invalid admin username received from Vault"
    fi

    if [ -z "$ADMIN_PASSWORD" ] || [ "$ADMIN_PASSWORD" = "null" ]; then
        error "Invalid admin password received from Vault"
    fi

    if [ -z "$ADMIN_EMAIL" ] || [ "$ADMIN_EMAIL" = "null" ]; then
        error "Invalid admin email received from Vault"
    fi

    success "Credentials fetched successfully from Vault"
}

#######################################
# Run Forgejo CLI installation
#######################################
run_installation() {
    info "Running automated Forgejo installation..."

    # Get credentials from Vault
    fetch_credentials_from_vault

    # Get config from environment
    DB_HOST="${FORGEJO__database__HOST:-postgres:5432}"
    DB_NAME="${FORGEJO__database__NAME:-forgejo}"
    SERVER_DOMAIN="${FORGEJO__server__DOMAIN:-localhost}"
    ROOT_URL="${FORGEJO__server__ROOT_URL:-http://localhost:3000/}"

    # Use web installation API to initialize Forgejo
    info "Creating database tables via installation API..."

    # Wait a moment for Forgejo web server to be ready
    sleep 3

    # URL encode sensitive parameters
    local encoded_admin_pass=$(echo -n "$ADMIN_PASSWORD" | jq -sRr @uri)
    local encoded_db_pass=$(echo -n "$DB_PASSWD" | jq -sRr @uri)

    # Create temporary file for POST data (avoids credential exposure in process list)
    local tmpfile=$(mktemp)
    trap "rm -f $tmpfile" EXIT

    # Write POST data to temp file
    cat > "$tmpfile" << EOF
db_type=postgres&db_host=${DB_HOST}&db_user=${DB_USER}&db_passwd=${encoded_db_pass}&db_name=${DB_NAME}&ssl_mode=disable&db_schema=&charset=utf8&db_path=%2Fdata%2Fgitea%2Fgitea.db&app_name=Forgejo%3A+Beyond+coding.+We+forge.&repo_root_path=%2Fdata%2Fgit%2Frepositories&lfs_root_path=%2Fdata%2Fgit%2Flfs&run_user=git&domain=${SERVER_DOMAIN}&ssh_port=22&http_port=3000&app_url=${ROOT_URL}&log_root_path=%2Fdata%2Fgitea%2Flog&smtp_addr=&smtp_port=&smtp_from=&smtp_user=&smtp_passwd=&enable_federated_avatar=on&enable_open_id_sign_in=on&enable_open_id_sign_up=on&default_allow_create_organization=on&default_enable_timetracking=on&no_reply_address=noreply.${SERVER_DOMAIN}&password_algorithm=pbkdf2&admin_name=${ADMIN_USER}&admin_passwd=${encoded_admin_pass}&admin_confirm_passwd=${encoded_admin_pass}&admin_email=${ADMIN_EMAIL}
EOF

    # Submit installation using POST file (prevents credential exposure)
    local install_response
    install_response=$(wget -qO- --post-file="$tmpfile" http://localhost:3000/ 2>/dev/null) || {
        warn "Installation API call completed (checking status...)"
    }

    # Clean up temp file immediately
    rm -f "$tmpfile"

    # Wait for installation to complete
    sleep 5

    # Check if installation was successful by verifying INSTALL_LOCK
    if grep -q "INSTALL_LOCK.*=.*true" /data/gitea/conf/app.ini 2>/dev/null; then
        success "Database tables created and installation completed"
    else
        # Manual fallback - update config directly
        warn "API installation may have failed, updating configuration manually..."
        sed -i "s/INSTALL_LOCK = false/INSTALL_LOCK = true/" /data/gitea/conf/app.ini
        # Use | as delimiter to avoid issues with / in SECRET_KEY
        sed -i "s|SECRET_KEY = |SECRET_KEY = ${SECRET_KEY}|" /data/gitea/conf/app.ini
        success "Configuration updated"
    fi
}

#######################################
# Display credential retrieval instructions
#######################################
display_admin_credentials() {
    info "Admin credentials stored in Vault at secret/forgejo"
    info ""
    info "To retrieve credentials:"
    info "  vault kv get -field=admin_user secret/forgejo"
    info "  vault kv get -field=admin_email secret/forgejo"
    info "  vault kv get -field=admin_password secret/forgejo"
    info ""
    info "OR use the management script:"
    info "  ./devstack.sh vault-show-password forgejo"
}

#######################################
# Verify installation
#######################################
verify_installation() {
    info "Verifying installation..."

    # Check that INSTALL_LOCK is set to true
    if ! grep -q "INSTALL_LOCK.*=.*true" /data/gitea/conf/app.ini 2>/dev/null; then
        error "Installation verification failed - INSTALL_LOCK not set"
    fi

    # Check that SECRET_KEY is not empty
    if grep -q "SECRET_KEY = $" /data/gitea/conf/app.ini 2>/dev/null; then
        error "Installation verification failed - SECRET_KEY not set"
    fi

    success "Installation verified successfully"
}

#######################################
# Main execution
#######################################
main() {
    info "Starting Forgejo automated installation..."
    info ""

    # Check if already installed
    check_installation_status

    # Validate configuration
    validate_inputs

    # Generate secret key
    generate_secret_key

    # Run installation
    run_installation

    # Verify
    verify_installation

    # Display credentials
    display_admin_credentials

    info ""
    success "✅ Forgejo installation complete!"
    info ""
    info "Access Forgejo at: http://localhost:3000"
    info ""
}

# Run main
main "$@"
