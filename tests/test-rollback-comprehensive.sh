#!/bin/bash
################################################################################
# Comprehensive Rollback Test - All Core Services
# Tests AppRole → Root Token → AppRole for postgres, mysql, mongodb
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

BACKUP_DIR="/tmp/rollback-comprehensive-$(date +%Y%m%d_%H%M%S)"
ENV_FILE="/tmp/vault-token-$(date +%Y%m%d_%H%M%S).env"

# Services to test (core databases only for safety)
SERVICES=("postgres" "mysql" "mongodb")

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Comprehensive Rollback Test - Core Services${NC}"
echo -e "${BLUE}  Testing: ${SERVICES[*]}${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    rm -f "$ENV_FILE" 2>/dev/null || true
    rm -f docker-compose.yml.bak 2>/dev/null || true
    for service in "${SERVICES[@]}"; do
        rm -f "configs/$service/scripts/init.sh.tmp" 2>/dev/null || true
    done
}

trap cleanup EXIT

##############################################################################
# Phase 1: Verify Current State (AppRole)
##############################################################################

echo -e "${CYAN}Phase 1: Verify Current State (AppRole)${NC}"
echo ""

for service in "${SERVICES[@]}"; do
    echo -e "${BLUE}Checking $service...${NC}"

    # Check AppRole credentials exist
    if [ ! -f "$HOME/.config/vault/approles/$service/role-id" ]; then
        echo -e "${RED}✗ AppRole credentials not found for $service${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ AppRole credentials exist for $service${NC}"

    # Check service is healthy
    container="dev-$service"
    if ! docker ps --filter "name=$container" --format "{{.Status}}" | grep -q "healthy"; then
        echo -e "${RED}✗ $service not healthy${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ $service is healthy${NC}"

    # Check no VAULT_TOKEN in container
    if docker exec "$container" env 2>/dev/null | grep -q "^VAULT_TOKEN="; then
        echo -e "${RED}✗ VAULT_TOKEN found in $service (should not exist with AppRole)${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ No VAULT_TOKEN in $service (AppRole mode confirmed)${NC}"
    echo ""
done

##############################################################################
# Phase 2: Create Backup
##############################################################################

echo -e "${CYAN}Phase 2: Create Backup${NC}"
echo ""

mkdir -p "$BACKUP_DIR"

# Backup docker-compose.yml
cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml"
echo -e "${GREEN}✓ Backed up docker-compose.yml${NC}"

# Backup init-approle scripts
for service in "${SERVICES[@]}"; do
    cp "configs/$service/scripts/init-approle.sh" "$BACKUP_DIR/init-approle-$service.sh"
    echo -e "${GREEN}✓ Backed up init-approle.sh for $service${NC}"
done

echo ""

##############################################################################
# Phase 3: Execute Rollback (AppRole → Root Token)
##############################################################################

echo -e "${CYAN}Phase 3: Execute Rollback (AppRole → Root Token)${NC}"
echo ""

# Stop all services
echo "Stopping services: ${SERVICES[*]}..."
docker compose stop "${SERVICES[@]}"
echo -e "${GREEN}✓ Services stopped${NC}"

# Create root token init scripts for each service
VAULT_TOKEN=$(cat ~/.config/vault/root-token)

for service in "${SERVICES[@]}"; do
    echo -e "${BLUE}Creating root token init script for $service...${NC}"

    cat > "configs/$service/scripts/init.sh" << 'EOFSCRIPT'
#!/bin/bash
set -e

SERVICE_NAME="SERVICE_PLACEHOLDER"

echo "[$SERVICE_NAME Init] Starting with ROOT TOKEN authentication"

# Install curl and jq if not available
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    echo "[$SERVICE_NAME Init] Installing curl and jq..."
    apt-get update > /dev/null 2>&1 && apt-get install -y curl jq > /dev/null 2>&1 || \
    yum install -y curl jq > /dev/null 2>&1 || \
    apk add curl jq > /dev/null 2>&1 || true
fi

# Check VAULT_TOKEN exists
if [ -z "$VAULT_TOKEN" ]; then
    echo "[$SERVICE_NAME Init] ERROR: VAULT_TOKEN not set"
    exit 1
fi

echo "[$SERVICE_NAME Init] VAULT_TOKEN is set: ${VAULT_TOKEN:0:10}..."

# Wait for Vault
echo "[$SERVICE_NAME Init] Waiting for Vault..."
for i in {1..30}; do
    if curl -sf "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
        echo "[$SERVICE_NAME Init] Vault is ready"
        break
    fi
    sleep 2
done

# Fetch credentials from Vault using root token
echo "[$SERVICE_NAME Init] Fetching credentials from Vault..."
SECRET_JSON=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/$SERVICE_NAME")

if [ -z "$SECRET_JSON" ]; then
    echo "[$SERVICE_NAME Init] ERROR: Failed to fetch credentials"
    exit 1
fi

# Extract credentials based on service type
echo "[$SERVICE_NAME Init] Extracting credentials..."

case "$SERVICE_NAME" in
    postgres)
        export POSTGRES_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.data.data.password')
        ;;
    mysql)
        export MYSQL_ROOT_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.data.data.root_password')
        export MYSQL_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.data.data.password')
        ;;
    mongodb)
        export MONGO_INITDB_ROOT_USERNAME=$(echo "$SECRET_JSON" | jq -r '.data.data.username')
        export MONGO_INITDB_ROOT_PASSWORD=$(echo "$SECRET_JSON" | jq -r '.data.data.password')
        ;;
esac

echo "[$SERVICE_NAME Init] Credentials loaded successfully"
echo "[$SERVICE_NAME Init] Starting $SERVICE_NAME..."

# Execute service entrypoint with all command args
exec docker-entrypoint.sh "$@"
EOFSCRIPT

    # Replace placeholder with actual service name
    sed -i.tmp "s/SERVICE_PLACEHOLDER/$service/g" "configs/$service/scripts/init.sh"
    rm -f "configs/$service/scripts/init.sh.tmp"

    chmod +x "configs/$service/scripts/init.sh"
    echo -e "${GREEN}✓ Created init.sh for $service${NC}"
done

# Modify docker-compose.yml for all services
echo "Modifying docker-compose.yml..."
cp docker-compose.yml docker-compose.yml.bak

for service in "${SERVICES[@]}"; do
    # Change entrypoint
    sed -i.tmp "/$service:/,/mysql:\\|mongodb:\\|redis-1:/ s|entrypoint: \[\"/init/init-approle.sh\"\]|entrypoint: [\"/init/init.sh\"]|" docker-compose.yml

    # Change volume mount for init script
    sed -i.tmp "/$service:/,/mysql:\\|mongodb:\\|redis-1:/ s|./configs/$service/scripts/init-approle.sh:/init/init-approle.sh:ro|./configs/$service/scripts/init.sh:/init/init.sh:ro|" docker-compose.yml

    # Remove AppRole volume mount
    sed -i.tmp "/$service:/,/mysql:\\|mongodb:\\|redis-1:/ s|.*vault/approles/$service:/vault-approles/$service:ro.*||" docker-compose.yml

    # Remove VAULT_APPROLE_DIR
    sed -i.tmp "/$service:/,/mysql:\\|mongodb:\\|redis-1:/ s|.*VAULT_APPROLE_DIR:.*||" docker-compose.yml
done

# Add VAULT_TOKEN to all services
for service in "${SERVICES[@]}"; do
    awk -v svc="$service" '
/^  / && $1 == svc":" { in_service=1 }
/^  [a-z]/ && $1 != svc":" { in_service=0 }
in_service && /VAULT_ADDR:/ && !vault_token_added {
    print
    print "      VAULT_TOKEN: ${VAULT_TOKEN}"
    vault_token_added=1
    next
}
{ print }
' docker-compose.yml > docker-compose.yml.new && mv docker-compose.yml.new docker-compose.yml
done

rm -f docker-compose.yml.tmp

echo -e "${GREEN}✓ Modified docker-compose.yml${NC}"

# Create env file with VAULT_TOKEN
cat > "$ENV_FILE" << EOF
VAULT_TOKEN=$VAULT_TOKEN
VAULT_ADDR=http://vault:8200
EOF
echo -e "${GREEN}✓ Created environment file with VAULT_TOKEN${NC}"

# Start services with root token
echo "Starting services with root token..."
if ! docker compose --env-file "$ENV_FILE" up -d "${SERVICES[@]}" 2>&1 | tee /tmp/docker-start.log; then
    echo -e "${RED}✗ Failed to start services${NC}"
    cat /tmp/docker-start.log
    echo "Restoring from backup..."
    cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
    for service in "${SERVICES[@]}"; do
        cp "$BACKUP_DIR/init-approle-$service.sh" "configs/$service/scripts/init-approle.sh"
    done
    docker compose up -d "${SERVICES[@]}"
    exit 1
fi

# Wait for services to become healthy
echo "Waiting for services to become healthy..."
for service in "${SERVICES[@]}"; do
    container="dev-$service"
    echo -n "Waiting for $service..."
    for i in {1..60}; do
        if docker ps --filter "name=$container" --format "{{.Status}}" | grep -q "healthy"; then
            echo -e " ${GREEN}✓ healthy after ${i}s${NC}"
            break
        fi
        sleep 1
        echo -n "."
    done

    # Verify it's actually healthy
    if ! docker ps --filter "name=$container" --format "{{.Status}}" | grep -q "healthy"; then
        echo -e "${RED}✗ $service did not become healthy${NC}"
        echo "Container logs:"
        docker logs "$container" 2>&1 | tail -50
        echo "Restoring from backup..."
        cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
        for svc in "${SERVICES[@]}"; do
            cp "$BACKUP_DIR/init-approle-$svc.sh" "configs/$svc/scripts/init-approle.sh"
        done
        docker compose up -d "${SERVICES[@]}"
        exit 1
    fi
done

echo ""

##############################################################################
# Phase 4: Validate Root Token Authentication
##############################################################################

echo -e "${CYAN}Phase 4: Validate Root Token Authentication${NC}"
echo ""

for service in "${SERVICES[@]}"; do
    container="dev-$service"
    echo -e "${BLUE}Validating $service...${NC}"

    # Check VAULT_TOKEN in container
    if ! docker exec "$container" env | grep -q "^VAULT_TOKEN="; then
        echo -e "${RED}✗ VAULT_TOKEN not found in $service${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ VAULT_TOKEN present in $service${NC}"

    # Service-specific validation
    case "$service" in
        postgres)
            if ! docker exec "$container" pg_isready -U devuser > /dev/null 2>&1; then
                echo -e "${RED}✗ PostgreSQL not accepting connections${NC}"
                exit 1
            fi
            echo -e "${GREEN}✓ PostgreSQL accepting connections${NC}"

            if ! docker exec "$container" psql -U devuser -d devdb -c "SELECT 1" > /dev/null 2>&1; then
                echo -e "${RED}✗ PostgreSQL query failed${NC}"
                exit 1
            fi
            echo -e "${GREEN}✓ PostgreSQL queries working${NC}"
            ;;
        mysql)
            if ! docker exec "$container" mysqladmin ping -u devuser -p"$(docker exec -e VAULT_ADDR=http://localhost:8200 -e VAULT_TOKEN=$VAULT_TOKEN dev-vault vault kv get -field=password secret/mysql)" > /dev/null 2>&1; then
                echo -e "${RED}✗ MySQL not accepting connections${NC}"
                exit 1
            fi
            echo -e "${GREEN}✓ MySQL accepting connections${NC}"
            ;;
        mongodb)
            if ! docker exec "$container" mongosh --quiet --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
                echo -e "${RED}✗ MongoDB not accepting connections${NC}"
                exit 1
            fi
            echo -e "${GREEN}✓ MongoDB accepting connections${NC}"
            ;;
    esac
    echo ""
done

##############################################################################
# Phase 5: Rollback to AppRole
##############################################################################

echo -e "${CYAN}Phase 5: Rollback to AppRole${NC}"
echo ""

# Stop services
echo "Stopping services..."
docker compose stop "${SERVICES[@]}"
echo -e "${GREEN}✓ Services stopped${NC}"

# Restore docker-compose.yml
cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
echo -e "${GREEN}✓ Restored docker-compose.yml${NC}"

# Restore init-approle scripts
for service in "${SERVICES[@]}"; do
    cp "$BACKUP_DIR/init-approle-$service.sh" "configs/$service/scripts/init-approle.sh"
    echo -e "${GREEN}✓ Restored init-approle.sh for $service${NC}"
done

# Start services with AppRole
echo "Starting services with AppRole..."
docker compose up -d "${SERVICES[@]}"

# Wait for services to become healthy
echo "Waiting for services to become healthy..."
for service in "${SERVICES[@]}"; do
    container="dev-$service"
    echo -n "Waiting for $service..."
    for i in {1..60}; do
        if docker ps --filter "name=$container" --format "{{.Status}}" | grep -q "healthy"; then
            echo -e " ${GREEN}✓ healthy after ${i}s${NC}"
            break
        fi
        sleep 1
        echo -n "."
    done

    if ! docker ps --filter "name=$container" --format "{{.Status}}" | grep -q "healthy"; then
        echo -e "${RED}✗ $service did not become healthy after AppRole restoration${NC}"
        docker logs "$container" 2>&1 | tail -50
        exit 1
    fi
done

echo ""

# Verify AppRole authentication
for service in "${SERVICES[@]}"; do
    container="dev-$service"
    echo -e "${BLUE}Validating AppRole for $service...${NC}"

    # Verify no VAULT_TOKEN
    if docker exec "$container" env 2>/dev/null | grep -q "^VAULT_TOKEN="; then
        echo -e "${RED}✗ VAULT_TOKEN still present in $service (should be removed)${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ No VAULT_TOKEN in $service (AppRole restored)${NC}"

    # Verify AppRole credentials mounted
    if ! docker exec "$container" test -f "/vault-approles/$service/role-id" 2>/dev/null; then
        echo -e "${RED}✗ AppRole credentials not mounted in $service${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ AppRole credentials mounted in $service${NC}"
    echo ""
done

##############################################################################
# Success
##############################################################################

echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓✓✓ COMPREHENSIVE ROLLBACK TEST SUCCESSFUL ✓✓✓${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "  ✓ Services tested: ${SERVICES[*]}"
echo "  ✓ AppRole → Root Token: SUCCESS"
echo "  ✓ Root Token Validation: SUCCESS"
echo "  ✓ Root Token → AppRole: SUCCESS"
echo "  ✓ AppRole Validation: SUCCESS"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
