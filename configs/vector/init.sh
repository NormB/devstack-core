#!/bin/bash
################################################################################
# Vector Initialization Script with Vault Integration
################################################################################
# This script initializes the Vector logging agent by fetching database
# credentials from HashiCorp Vault for PostgreSQL, MongoDB, and Redis services.
# The credentials are exported as environment variables for Vector to use in
# its configuration file.
#
# Vector is a high-performance observability data pipeline that collects,
# transforms, and routes logs and metrics. This script ensures it has the
# necessary credentials to connect to and monitor database services.
#
# The script performs the following operations:
# 1. Installs required packages (curl, redis-tools) if not present
# 2. Determines Vault token from environment or file
# 3. Fetches PostgreSQL credentials (user, password, database)
# 4. Fetches MongoDB credentials (user, password)
# 5. Fetches Redis credentials for all 3 Redis instances
# 6. Validates all credentials were successfully retrieved
# 7. Starts Vector with exported credentials
#
# GLOBALS:
#   VAULT_ADDR - Vault server address (default: http://vault:8200)
#   VAULT_TOKEN - Vault authentication token (from env or file)
#   POSTGRES_USER - PostgreSQL username (exported)
#   POSTGRES_PASSWORD - PostgreSQL password (exported)
#   POSTGRES_DB - PostgreSQL database name (exported)
#   MONGO_USER - MongoDB username (exported)
#   MONGO_PASSWORD - MongoDB password (exported)
#   REDIS_1_PASSWORD - Redis node 1 password (exported)
#   REDIS_2_PASSWORD - Redis node 2 password (exported)
#   REDIS_3_PASSWORD - Redis node 3 password (exported)
#   RED, GREEN, BLUE, NC - ANSI color codes for terminal output
#   HOME - User home directory for token file path
#
# USAGE:
#   init.sh [vector-arguments]
#
#   Environment variables optional:
#     VAULT_ADDR - Vault server URL (default: http://vault:8200)
#     VAULT_TOKEN - Vault authentication token
#
#   Token resolution order:
#     1. VAULT_TOKEN environment variable
#     2. ${HOME}/.config/vault/root-token file
#
# DEPENDENCIES:
#   - curl         - For HTTP requests to Vault API
#   - redis-tools  - Redis command-line tools (auto-installed if missing)
#   - grep, cut    - For JSON parsing without jq
#   - apt-get      - Debian package manager (for installing dependencies)
#   - vector       - Vector binary (in system PATH or /usr/bin/vector)
#
# EXIT CODES:
#   0 - Success (script replaces itself with vector via exec)
#   1 - Error (missing VAULT_TOKEN, failed to fetch credentials, invalid
#       credentials, vector binary not found)
#
# NOTES:
#   - Uses curl for Vault API requests (unlike Redis scripts that use wget)
#   - Parses JSON using grep/cut to avoid jq dependency
#   - Automatically installs curl and redis-tools if not present
#   - Fetches credentials from these Vault paths:
#     * secret/data/postgres
#     * secret/data/mongodb
#     * secret/data/redis-1, secret/data/redis-2, secret/data/redis-3
#   - All credentials are validated before starting Vector
#   - Vector binary location auto-detected via 'which' or defaults to /usr/bin/vector
#
# EXAMPLES:
#   # Using VAULT_TOKEN from environment
#   export VAULT_TOKEN=hvs.xxxxx
#   ./init.sh
#
#   # Using token from file (default location)
#   # Token at ${HOME}/.config/vault/root-token
#   ./init.sh
#
#   # With custom Vault address
#   export VAULT_ADDR=https://vault.example.com:8200
#   export VAULT_TOKEN=hvs.xxxxx
#   ./init.sh --config /etc/vector/vector.toml
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}[Vector Init]${NC} Initializing Vector with Vault credentials..."

################################################################################
# Packages (curl, redis-tools) are pre-installed via Dockerfile
# No runtime installation needed
################################################################################

# Vault configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"

################################################################################
# Resolve Vault token from environment or file
# Tries to get VAULT_TOKEN from environment variable first, then falls back
# to reading from ${HOME}/.config/vault/root-token file. Validates file
# permissions for security before reading. Exits if neither source provides
# a token or if file permissions are insecure.
################################################################################
if [ -n "$VAULT_TOKEN" ]; then
    echo -e "${BLUE}[Vector Init]${NC} Using VAULT_TOKEN from environment"
elif [ -f "${HOME}/.config/vault/root-token" ]; then
    # Validate token file permissions before reading
    token_file="${HOME}/.config/vault/root-token"
    perms=$(stat -f "%OLp" "$token_file" 2>/dev/null || stat -c "%a" "$token_file" 2>/dev/null)

    if [ -z "$perms" ]; then
        echo -e "${RED}[Vector Init]${NC} Failed to read token file permissions"
        exit 1
    fi

    if [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
        echo -e "${RED}[Vector Init]${NC} Token file has insecure permissions: $perms (expected 600 or 400)"
        echo -e "${YELLOW}[Vector Init]${NC} Fix with: chmod 600 $token_file"
        exit 1
    fi

    VAULT_TOKEN=$(cat "$token_file")
    echo -e "${BLUE}[Vector Init]${NC} Loaded VAULT_TOKEN from $token_file (permissions: $perms)"
else
    echo -e "${RED}[Vector Init]${NC} VAULT_TOKEN not set and token file not found"
    exit 1
fi

#######################################
# Fetch credentials from Vault KV store for a specific service
# Makes HTTP request to Vault API to retrieve credentials for the specified
# service name. Returns the raw JSON response on success.
# Globals:
#   VAULT_ADDR - Vault server address
#   VAULT_TOKEN - Vault authentication token
#   RED, BLUE, NC - ANSI color codes for output
# Arguments:
#   $1 - Service name (e.g., "postgres", "mongodb", "redis-1")
# Returns:
#   0 - Successfully fetched credentials
#   1 - Failed to fetch credentials from Vault
# Outputs:
#   Writes status messages to stdout
#   Writes JSON response to stdout on success
#   Writes error messages to stdout on failure
# Notes:
#   - Uses curl with -sf flags (silent, fail on error)
#   - Fetches from Vault path: /v1/secret/data/$service
#   - Captures both stdout and stderr from curl
#   - On failure, prints curl exit code and output for debugging
#######################################
fetch_credentials() {
    local service=$1
    local response
    local curl_exit

    echo -e "${BLUE}[Vector Init]${NC} Attempting to fetch $service credentials from $VAULT_ADDR..."

    response=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" \
        "$VAULT_ADDR/v1/secret/data/$service" 2>&1)
    curl_exit=$?

    if [ $curl_exit -ne 0 ]; then
        echo -e "${RED}[Vector Init]${NC} Failed to fetch credentials for $service (curl exit code: $curl_exit)"
        echo -e "${RED}[Vector Init]${NC} curl output: $response"
        return 1
    fi

    echo "$response"
}

################################################################################
# Fetch PostgreSQL credentials from Vault
# Retrieves user, password, and database name for PostgreSQL and exports them
# as environment variables for Vector configuration.
################################################################################
echo -e "${BLUE}[Vector Init]${NC} Fetching PostgreSQL credentials..."
POSTGRES_CREDS=$(fetch_credentials "postgres")
export POSTGRES_USER=$(echo "$POSTGRES_CREDS" | grep -o '"user":"[^"]*"' | cut -d'"' -f4)
export POSTGRES_PASSWORD=$(echo "$POSTGRES_CREDS" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)
export POSTGRES_DB=$(echo "$POSTGRES_CREDS" | grep -o '"database":"[^"]*"' | cut -d'"' -f4)

################################################################################
# Fetch MongoDB credentials from Vault
# Retrieves user and password for MongoDB and exports them as environment
# variables for Vector configuration.
################################################################################
echo -e "${BLUE}[Vector Init]${NC} Fetching MongoDB credentials..."
MONGO_CREDS=$(fetch_credentials "mongodb")
export MONGO_USER=$(echo "$MONGO_CREDS" | grep -o '"user":"[^"]*"' | cut -d'"' -f4)
export MONGO_PASSWORD=$(echo "$MONGO_CREDS" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)

################################################################################
# Fetch Redis credentials for all 3 Redis instances
# Retrieves passwords for redis-1, redis-2, and redis-3 from Vault and exports
# them as separate environment variables for Vector configuration.
################################################################################
echo -e "${BLUE}[Vector Init]${NC} Fetching Redis credentials..."
REDIS_1_CREDS=$(fetch_credentials "redis-1")
export REDIS_1_PASSWORD=$(echo "$REDIS_1_CREDS" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)

REDIS_2_CREDS=$(fetch_credentials "redis-2")
export REDIS_2_PASSWORD=$(echo "$REDIS_2_CREDS" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)

REDIS_3_CREDS=$(fetch_credentials "redis-3")
export REDIS_3_PASSWORD=$(echo "$REDIS_3_CREDS" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)

################################################################################
# Validate all credentials were successfully fetched and parsed
# Checks that all required environment variables are non-empty. Exits with
# error if any credential is missing or empty.
################################################################################
if [ -z "$POSTGRES_USER" ] || [ -z "$POSTGRES_PASSWORD" ] || [ -z "$POSTGRES_DB" ]; then
    echo -e "${RED}[Vector Init]${NC} Failed to parse PostgreSQL credentials"
    exit 1
fi

if [ -z "$MONGO_USER" ] || [ -z "$MONGO_PASSWORD" ]; then
    echo -e "${RED}[Vector Init]${NC} Failed to parse MongoDB credentials"
    exit 1
fi

if [ -z "$REDIS_1_PASSWORD" ] || [ -z "$REDIS_2_PASSWORD" ] || [ -z "$REDIS_3_PASSWORD" ]; then
    echo -e "${RED}[Vector Init]${NC} Failed to parse Redis credentials"
    exit 1
fi

echo -e "${GREEN}[Vector Init]${NC} Credentials loaded successfully"
echo -e "${BLUE}[Vector Init]${NC} Starting Vector..."

################################################################################
# Start Vector with exported credentials
# Locates Vector binary using 'which' command or defaults to /usr/bin/vector,
# then replaces the current process with Vector using exec.
################################################################################
VECTOR_BIN=$(which vector || echo "/usr/bin/vector")
echo -e "${BLUE}[Vector Init]${NC} Using Vector binary at: $VECTOR_BIN"
exec "$VECTOR_BIN" "$@"
