#!/bin/bash
################################################################################
# Simple Rollback Test - Focus on Making It Work
# Tests AppRole → Root Token → AppRole for postgres only first
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BACKUP_DIR="/tmp/rollback-backup-$(date +%Y%m%d_%H%M%S)"
ENV_FILE="/tmp/vault-token-$(date +%Y%m%d_%H%M%S).env"

echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Simple Rollback Test - PostgreSQL Only${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
echo ""

cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    rm -f "$ENV_FILE" 2>/dev/null || true
    rm -f docker-compose.yml.bak 2>/dev/null || true
    rm -f configs/postgres/scripts/init.sh.tmp 2>/dev/null || true
}

trap cleanup EXIT

#
##############################################################################
# Phase 1: Verify Current State (AppRole)
##############################################################################

echo -e "${BLUE}Phase 1: Verify Current State (AppRole)${NC}"

# Check AppRole credentials exist
if [ ! -f "$HOME/.config/vault/approles/postgres/role-id" ]; then
    echo -e "${RED}✗ AppRole credentials not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AppRole credentials exist${NC}"

# Check postgres is healthy
if ! docker ps --filter "name=dev-postgres" --format "{{.Status}}" | grep -q "healthy"; then
    echo -e "${RED}✗ PostgreSQL not healthy${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PostgreSQL is healthy${NC}"

# Check no VAULT_TOKEN in container
if docker exec dev-postgres env 2>/dev/null | grep -q "^VAULT_TOKEN="; then
    echo -e "${RED}✗ VAULT_TOKEN found (should not exist with AppRole)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ No VAULT_TOKEN in container (AppRole mode confirmed)${NC}"

echo ""

##############################################################################
# Phase 2: Create Backup
##############################################################################

echo -e "${BLUE}Phase 2: Create Backup${NC}"

mkdir -p "$BACKUP_DIR"

# Backup docker-compose.yml
cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml"
echo -e "${GREEN}✓ Backed up docker-compose.yml${NC}"

# Backup init-approle.sh
cp configs/postgres/scripts/init-approle.sh "$BACKUP_DIR/init-approle-postgres.sh"
echo -e "${GREEN}✓ Backed up init-approle.sh${NC}"

echo ""

##############################################################################
# Phase 3: Execute Rollback
##############################################################################

echo -e "${BLUE}Phase 3: Execute Rollback (AppRole → Root Token)${NC}"

# Stop postgres
echo "Stopping PostgreSQL..."
docker compose stop postgres
echo -e "${GREEN}✓ PostgreSQL stopped${NC}"

# Create root token init script
echo "Creating root token init script..."
cat > configs/postgres/scripts/init.sh << 'EOF'
#!/bin/bash
set -e

echo "[PostgreSQL Init] Starting with ROOT TOKEN authentication"

# Install curl and jq if not available
if ! command -v curl &> /dev/null || ! command -v jq &> /dev/null; then
    echo "[PostgreSQL Init] Installing curl and jq..."
    apt-get update > /dev/null 2>&1 && apt-get install -y curl jq > /dev/null 2>&1
fi

# Check VAULT_TOKEN exists
if [ -z "$VAULT_TOKEN" ]; then
    echo "[PostgreSQL Init] ERROR: VAULT_TOKEN not set"
    exit 1
fi

echo "[PostgreSQL Init] VAULT_TOKEN is set: ${VAULT_TOKEN:0:10}..."

# Wait for Vault
echo "[PostgreSQL Init] Waiting for Vault..."
for i in {1..30}; do
    if curl -sf "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
        echo "[PostgreSQL Init] Vault is ready"
        break
    fi
    sleep 2
done

# Fetch credentials from Vault using root token
echo "[PostgreSQL Init] Fetching credentials from Vault..."
SECRET_JSON=$(curl -sf -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/secret/data/postgres")

if [ -z "$SECRET_JSON" ]; then
    echo "[PostgreSQL Init] ERROR: Failed to fetch credentials"
    exit 1
fi

# Extract password using jq
PASSWORD=$(echo "$SECRET_JSON" | jq -r '.data.data.password')

if [ -z "$PASSWORD" ] || [ "$PASSWORD" = "null" ]; then
    echo "[PostgreSQL Init] ERROR: Failed to extract password"
    exit 1
fi

# Export for PostgreSQL
export POSTGRES_PASSWORD="$PASSWORD"

echo "[PostgreSQL Init] Credentials loaded successfully"
echo "[PostgreSQL Init] Starting PostgreSQL..."

# Execute PostgreSQL entrypoint with all command args from docker-compose.yml
exec docker-entrypoint.sh "$@"
EOF

chmod +x configs/postgres/scripts/init.sh
echo -e "${GREEN}✓ Created init.sh with root token authentication${NC}"

# Modify docker-compose.yml for postgres only
echo "Modifying docker-compose.yml..."

# Create a backup before modification
cp docker-compose.yml docker-compose.yml.bak

# Change entrypoint
sed -i.tmp '/postgres:/,/mysql:/ s|entrypoint: \["/init/init-approle.sh"\]|entrypoint: ["/init/init.sh"]|' docker-compose.yml

# Change volume mount for init script
sed -i.tmp '/postgres:/,/mysql:/ s|./configs/postgres/scripts/init-approle.sh:/init/init-approle.sh:ro|./configs/postgres/scripts/init.sh:/init/init.sh:ro|' docker-compose.yml

# Remove AppRole volume mount for postgres
sed -i.tmp '/postgres:/,/mysql:/ s|.*vault/approles/postgres:/vault-approles/postgres:ro.*||' docker-compose.yml

# Remove VAULT_APPROLE_DIR for postgres
sed -i.tmp '/postgres:/,/mysql:/ s|.*VAULT_APPROLE_DIR:.*||' docker-compose.yml

# Add VAULT_TOKEN to postgres environment section
# Use awk for more precise insertion
awk '
/^  postgres:/ { in_postgres=1 }
/^  mysql:/ { in_postgres=0 }
in_postgres && /VAULT_ADDR:/ && !vault_token_added {
    print
    print "      VAULT_TOKEN: ${VAULT_TOKEN}"
    vault_token_added=1
    next
}
{ print }
' docker-compose.yml > docker-compose.yml.new && mv docker-compose.yml.new docker-compose.yml

rm -f docker-compose.yml.tmp

echo -e "${GREEN}✓ Modified docker-compose.yml${NC}"

# Verify the changes
if ! grep -A 30 "postgres:" docker-compose.yml | grep -q 'entrypoint: \["/init/init.sh"\]'; then
    echo -e "${RED}✗ Entrypoint not changed correctly${NC}"
    cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
    exit 1
fi
echo -e "${GREEN}✓ Verified entrypoint changed to /init/init.sh${NC}"

# Create env file with VAULT_TOKEN
VAULT_TOKEN=$(cat ~/.config/vault/root-token)
cat > "$ENV_FILE" << EOF
VAULT_TOKEN=$VAULT_TOKEN
VAULT_ADDR=http://vault:8200
EOF
echo -e "${GREEN}✓ Created environment file with VAULT_TOKEN${NC}"

# Start postgres with root token
echo "Starting PostgreSQL with root token..."
if ! docker compose --env-file "$ENV_FILE" up -d postgres 2>&1 | tee /tmp/docker-start.log; then
    echo -e "${RED}✗ Failed to start PostgreSQL${NC}"
    cat /tmp/docker-start.log
    echo "Restoring from backup..."
    cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
    cp "$BACKUP_DIR/init-approle-postgres.sh" configs/postgres/scripts/init-approle.sh
    docker compose up -d postgres
    exit 1
fi

# Wait for healthy
echo "Waiting for PostgreSQL to become healthy..."
for i in {1..60}; do
    if docker ps --filter "name=dev-postgres" --format "{{.Status}}" | grep -q "healthy"; then
        echo -e "${GREEN}✓ PostgreSQL is healthy after ${i} seconds${NC}"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

# Verify it's actually healthy
if ! docker ps --filter "name=dev-postgres" --format "{{.Status}}" | grep -q "healthy"; then
    echo -e "${RED}✗ PostgreSQL did not become healthy${NC}"
    echo "Container logs:"
    docker logs dev-postgres 2>&1 | tail -50
    echo "Restoring from backup..."
    cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
    cp "$BACKUP_DIR/init-approle-postgres.sh" configs/postgres/scripts/init-approle.sh
    docker compose up -d postgres
    exit 1
fi

echo ""

##############################################################################
# Phase 4: Validate Root Token Authentication
##############################################################################

echo -e "${BLUE}Phase 4: Validate Root Token Authentication${NC}"

# Check VAULT_TOKEN in container
if ! docker exec dev-postgres env | grep -q "^VAULT_TOKEN="; then
    echo -e "${RED}✗ VAULT_TOKEN not found in container${NC}"
    exit 1
fi
echo -e "${GREEN}✓ VAULT_TOKEN present in container${NC}"

# Check PostgreSQL is accepting connections
if ! docker exec dev-postgres pg_isready -U devuser > /dev/null 2>&1; then
    echo -e "${RED}✗ PostgreSQL not accepting connections${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PostgreSQL accepting connections${NC}"

# Try to connect and query
if ! docker exec dev-postgres psql -U devuser -d devdb -c "SELECT 1" > /dev/null 2>&1; then
    echo -e "${RED}✗ PostgreSQL query failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ PostgreSQL queries working${NC}"

echo ""

##############################################################################
# Phase 5: Rollback to AppRole
##############################################################################

echo -e "${BLUE}Phase 5: Rollback to AppRole${NC}"

# Stop postgres
docker compose stop postgres
echo -e "${GREEN}✓ PostgreSQL stopped${NC}"

# Restore docker-compose.yml
cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
echo -e "${GREEN}✓ Restored docker-compose.yml${NC}"

# Restore init-approle.sh (it's still there, but make sure)
if [ ! -f configs/postgres/scripts/init-approle.sh ]; then
    cp "$BACKUP_DIR/init-approle-postgres.sh" configs/postgres/scripts/init-approle.sh
fi
echo -e "${GREEN}✓ Restored init-approle.sh${NC}"

# Start postgres with AppRole
echo "Starting PostgreSQL with AppRole..."
docker compose up -d postgres

# Wait for healthy
echo "Waiting for PostgreSQL to become healthy..."
for i in {1..60}; do
    if docker ps --filter "name=dev-postgres" --format "{{.Status}}" | grep -q "healthy"; then
        echo -e "${GREEN}✓ PostgreSQL is healthy after ${i} seconds${NC}"
        break
    fi
    sleep 1
    echo -n "."
done
echo ""

if ! docker ps --filter "name=dev-postgres" --format "{{.Status}}" | grep -q "healthy"; then
    echo -e "${RED}✗ PostgreSQL did not become healthy after AppRole restoration${NC}"
    docker logs dev-postgres 2>&1 | tail -50
    exit 1
fi

# Verify no VAULT_TOKEN
if docker exec dev-postgres env 2>/dev/null | grep -q "^VAULT_TOKEN="; then
    echo -e "${RED}✗ VAULT_TOKEN still present (should be removed)${NC}"
    exit 1
fi
echo -e "${GREEN}✓ No VAULT_TOKEN in container (AppRole restored)${NC}"

# Verify AppRole credentials mounted
if ! docker exec dev-postgres test -f /vault-approles/postgres/role-id 2>/dev/null; then
    echo -e "${RED}✗ AppRole credentials not mounted${NC}"
    exit 1
fi
echo -e "${GREEN}✓ AppRole credentials mounted${NC}"

echo ""

##############################################################################
# Success
##############################################################################

echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✓✓✓ ROLLBACK TEST SUCCESSFUL ✓✓✓${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo "Summary:"
echo "  ✓ AppRole → Root Token: SUCCESS"
echo "  ✓ Root Token Validation: SUCCESS"
echo "  ✓ Root Token → AppRole: SUCCESS"
echo "  ✓ AppRole Validation: SUCCESS"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
