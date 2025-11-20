#!/bin/bash
#######################################
# Docker Compose wrapper with Vault integration
#
# This wrapper ensures all docker-compose commands load passwords from Vault
# before executing. It provides a secure way to run docker-compose without
# storing plaintext credentials in .env files.
#
# This is the RECOMMENDED way to run docker-compose for services that require
# credentials from Vault.
#
# Globals:
#   VAULT_ADDR - Set to http://localhost:8200 for host access
#   VAULT_TOKEN - Loaded by load-vault-env.sh
#   POSTGRES_PASSWORD - Loaded by load-vault-env.sh
#
# Arguments:
#   All arguments are passed through to docker compose
#
# Usage:
#   ./scripts/docker-compose-vault.sh up -d
#   ./scripts/docker-compose-vault.sh down
#   ./scripts/docker-compose-vault.sh restart forgejo
#   ./scripts/docker-compose-vault.sh logs -f postgres
#
# Examples:
#   $ ./scripts/docker-compose-vault.sh up -d
#   [Vault Env] Loading environment variables from Vault...
#   [Vault Env] Vault is accessible at http://localhost:8200
#   [Vault Env] PostgreSQL password loaded from Vault
#   [+] Running 12/12
#    ✔ Container dev-postgres Started
#
# Dependencies:
#   - load-vault-env.sh (in same directory)
#   - docker compose
#   - Vault running at http://localhost:8200
#
# Exit Codes:
#   Exits with docker compose exit code
#
# Notes:
#   - Script changes to project root before running docker compose
#   - VAULT_ADDR is set for host access (containers use vault:8200)
#   - All environment variables from Vault are available to docker-compose
#######################################

set -e

# Determine script and project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Change to project root for docker-compose
cd "$PROJECT_ROOT"

# Export Vault address for host access (not container access)
export VAULT_ADDR=http://localhost:8200

# Source the Vault environment loader
source "$SCRIPT_DIR/load-vault-env.sh"

# Unset VAULT_ADDR so docker-compose uses value from .env file for containers
# The localhost address is only for the host scripts above
unset VAULT_ADDR

# Run docker-compose with all arguments passed through
docker compose "$@"
