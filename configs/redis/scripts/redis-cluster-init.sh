#!/usr/bin/env bash
################################################################################
# Redis Cluster Initialization Script
################################################################################
# Creates a Redis cluster from 3 standalone Redis nodes by configuring them
# as cluster masters and assigning hash slots. This script should be run ONCE
# after starting the Redis containers for the first time.
#
# The script performs the following operations:
# 1. Validates that REDIS_PASSWORD environment variable is set
# 2. Waits for all 3 Redis nodes to become ready and responsive
# 3. Checks if cluster is already initialized to avoid re-initialization
# 4. Creates cluster using redis-cli --cluster create command
# 5. Displays cluster information and connection details
#
# GLOBALS:
#   REDIS_PASSWORD - Password for Redis authentication (required)
#   RED, GREEN, YELLOW, BLUE, NC - ANSI color codes for terminal output
#
# USAGE:
#   ./redis-cluster-init.sh
#
#   Environment variables required:
#     REDIS_PASSWORD - Password for authenticating to Redis nodes
#
#   Prerequisites:
#     - 3 Redis containers must be running: dev-redis-1, dev-redis-2, dev-redis-3
#     - Redis nodes must be accessible at IPs: 172.20.2.13, 172.20.2.16, 172.20.2.17
#     - Docker must be available and accessible without sudo
#     - redis-cli must be available in the Redis containers
#
# DEPENDENCIES:
#   - docker          - For executing commands in Redis containers
#   - redis-cli       - Redis command-line client (inside containers)
#   - grep            - For parsing command output
#
# EXIT CODES:
#   0 - Success (cluster created or already exists)
#   1 - Error (missing REDIS_PASSWORD, nodes not ready, cluster creation failed)
#
# NOTES:
#   - Creates a 3-master cluster with no replicas
#   - Hash slots are automatically distributed across the 3 masters
#   - Uses --cluster-yes flag to auto-accept cluster configuration
#   - Maximum wait time per node: 30 seconds (30 attempts × 1 second)
#   - Node IP addresses are hardcoded: 172.20.2.13, 172.20.2.16, 172.20.2.17
#   - Container names are hardcoded: dev-redis-1, dev-redis-2, dev-redis-3
#   - Cluster communication ports must be accessible between nodes
#
# EXAMPLES:
#   # Basic usage after starting Redis containers
#   export REDIS_PASSWORD=mySecurePassword123
#   ./redis-cluster-init.sh
#
#   # Check cluster status after initialization
#   docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" cluster info
#   docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" cluster nodes
################################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

#######################################
# Print informational message to stdout
# Globals:
#   BLUE - ANSI color code for blue text
#   NC - ANSI color code to reset colors
# Arguments:
#   $1 - Message to print
# Returns:
#   0 - Always successful
# Outputs:
#   Writes formatted info message to stdout
#######################################
info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

#######################################
# Print success message to stdout
# Globals:
#   GREEN - ANSI color code for green text
#   NC - ANSI color code to reset colors
# Arguments:
#   $1 - Message to print
# Returns:
#   0 - Always successful
# Outputs:
#   Writes formatted success message to stdout
#######################################
success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

#######################################
# Print warning message to stdout
# Globals:
#   YELLOW - ANSI color code for yellow text
#   NC - ANSI color code to reset colors
# Arguments:
#   $1 - Message to print
# Returns:
#   0 - Always successful
# Outputs:
#   Writes formatted warning message to stdout
#######################################
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

#######################################
# Print error message and exit script
# Globals:
#   RED - ANSI color code for red text
#   NC - ANSI color code to reset colors
# Arguments:
#   $1 - Error message to print
# Returns:
#   Never returns (exits with code 1)
# Outputs:
#   Writes formatted error message to stdout, then exits
#######################################
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

################################################################################
# MAIN SCRIPT EXECUTION
################################################################################

# Check if password is set
if [ -z "${REDIS_PASSWORD:-}" ]; then
    error "REDIS_PASSWORD environment variable is not set"
fi

echo
echo "===================================================================="
echo "  Redis Cluster Initialization"
echo "===================================================================="
echo

################################################################################
# Wait for all Redis nodes to become ready and responsive
# Polls each node using PING command until it responds or timeout is reached.
# Node 1: 172.20.2.13:6379 (container: dev-redis-1)
# Node 2: 172.20.2.16:6379 (container: dev-redis-2)
# Node 3: 172.20.2.17:6379 (container: dev-redis-3)
################################################################################
info "Waiting for Redis nodes to be ready..."
max_attempts=30
attempt=0

# Wait for node 1 (172.20.2.13:6379)
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if docker exec dev-redis-1 redis-cli -h 172.20.2.13 -p 6379 -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
        success "Redis node 1 is ready"
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done

# Check if we exceeded max attempts
if [ $attempt -eq $max_attempts ]; then
    error "Redis node 1 did not become ready in time"
fi

# Wait for node 2 (172.20.2.16:6379)
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if docker exec dev-redis-2 redis-cli -h 172.20.2.16 -p 6379 -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
        success "Redis node 2 is ready"
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done

# Check if we exceeded max attempts
if [ $attempt -eq $max_attempts ]; then
    error "Redis node 2 did not become ready in time"
fi

# Wait for node 3 (172.20.2.17:6379)
attempt=0
while [ $attempt -lt $max_attempts ]; do
    if docker exec dev-redis-3 redis-cli -h 172.20.2.17 -p 6379 -a "$REDIS_PASSWORD" ping 2>/dev/null | grep -q PONG; then
        success "Redis node 3 is ready"
        break
    fi
    attempt=$((attempt + 1))
    sleep 1
done

# Check if we exceeded max attempts
if [ $attempt -eq $max_attempts ]; then
    error "Redis node 3 did not become ready in time"
fi

################################################################################
# Check if cluster is already initialized
# Queries cluster_state from the first node. If state is "ok", cluster is
# already operational and script exits successfully without re-initializing.
################################################################################
info "Checking if cluster is already initialized..."
if docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" cluster info 2>/dev/null | grep -q "cluster_state:ok"; then
    warning "Cluster is already initialized and running"
    docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" cluster info 2>/dev/null
    docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" cluster nodes 2>/dev/null
    echo
    success "Cluster is operational"
    exit 0
fi

################################################################################
# Create the Redis cluster
# Uses redis-cli --cluster create to configure 3 masters with automatic slot
# assignment. The --cluster-yes flag auto-accepts the proposed configuration.
# Hash slots (0-16383) are distributed evenly across the 3 master nodes.
################################################################################
info "Creating Redis cluster..."
info "This will assign slots to the 3 master nodes..."

# Use redis-cli --cluster create
docker exec dev-redis-1 redis-cli --cluster create \
    172.20.2.13:6379 \
    172.20.2.16:6379 \
    172.20.2.17:6379 \
    --cluster-yes \
    -a "$REDIS_PASSWORD"

if [ $? -eq 0 ]; then
    success "Redis cluster created successfully!"
else
    error "Failed to create Redis cluster"
fi

################################################################################
# Display cluster information and connection details
# Shows cluster state, node configuration, and instructions for connecting
# to the cluster using redis-cli.
################################################################################
echo
info "Cluster Information:"
docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" --no-auth-warning cluster info
echo
info "Cluster Nodes:"
docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" --no-auth-warning cluster nodes
echo

success "Redis cluster is ready to use!"
echo
info "Connection Info:"
echo "  - Node 1: localhost:6379"
echo "  - Node 2: localhost:6380"
echo "  - Node 3: localhost:6381"
echo
info "Connect using redis-cli:"
echo "  redis-cli -c -a \$REDIS_PASSWORD -p 6379"
echo
warning "Use the -c flag for cluster mode!"
echo
