#!/bin/bash
################################################################################
# Rollback Procedures Complete Validation Test (ALL FIXES APPLIED)
# Tests Phase 1 AppRole → Root Token rollback and re-migration
################################################################################
#
# This test validates rollback procedures for 6 core services with ALL fixes:
# - VAULT_TOKEN propagation via --env-file
# - Complete backup/restore including docker-compose.yml
# - Comprehensive diagnostic capture on failures
# - Correct restart commands (no --profile flag)
# - Environment variable validation
# - Full verification at each step
#
# FIXES APPLIED:
# - Fix #1: VAULT_TOKEN propagation via --env-file method
# - Fix #2: Removed invalid --profile flags from restart commands
# - Fix #3: Complete backup restoration including docker-compose.yml
# - Fix #4: Comprehensive diagnostic capture on all failures
# - Fix #5: Environment variable validation
# - Fix #6: docker-compose.yml state verification
#
# WARNING: This is a DESTRUCTIVE test that modifies the live environment.
################################################################################

set -u  # Exit on undefined variables
set -o pipefail  # Catch errors in pipes

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
BACKUP_DIR="/tmp/devstack-rollback-test-$(date +%Y%m%d_%H%M%S)"
VAULT_ENV_FILE="/tmp/vault-rollback-$(date +%Y%m%d_%H%M%S).env"

# Test configuration (core services only)
SERVICES=("postgres" "mysql" "mongodb" "redis" "rabbitmq" "forgejo")
CONTAINERS=("dev-postgres" "dev-mysql" "dev-mongodb" "dev-redis-1" "dev-rabbitmq" "dev-forgejo")

# Function to get service-specific entrypoints
get_service_entrypoint() {
    local service=$1
    case "$service" in
        postgres|mysql|mongodb|redis|rabbitmq)
            echo "docker-entrypoint.sh"
            ;;
        forgejo)
            echo "/usr/bin/entrypoint"
            ;;
        *)
            echo "Unknown service: $service" >&2
            return 1
            ;;
    esac
}

echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}  Rollback Procedures Complete Test (ALL FIXES APPLIED)${NC}"
echo -e "${MAGENTA}  Phase 1: AppRole → Root Token → AppRole${NC}"
echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
echo ""

################################################################################
# Helper Functions
################################################################################

log_phase() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

log_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

log_success() {
    echo -e "  ${GREEN}✓${NC} $1"
    ((PASS++))
}

log_fail() {
    echo -e "  ${RED}✗${NC} $1"
    ((FAIL++))
}

wait_for_services() {
    local max_wait=180
    local elapsed=0

    log_step "Waiting for services to be healthy (max ${max_wait}s)..."

    while [ $elapsed -lt $max_wait ]; do
        if../devstack health > /dev/null 2>&1; then
            log_success "All services healthy after ${elapsed}s"
            return 0
        fi
        sleep 5
        ((elapsed+=5))
        echo -n "."
    done

    echo ""
    log_fail "Services did not become healthy within ${max_wait}s"
    return 1
}

################################################################################
# FIX #4: Comprehensive Diagnostic Capture
################################################################################

capture_diagnostics() {
    local output_file="${BACKUP_DIR}/diagnostics.log"

    log_step "Capturing diagnostics to $output_file"

    {
        echo "=== Diagnostic Capture ==="
        echo "Timestamp: $(date)"
        echo ""

        echo "=== Container Status ==="
        docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}" 2>&1
        echo ""

        echo "=== Vault Health ==="
        curl -s http://localhost:8200/v1/sys/health 2>&1 || echo "Vault not accessible"
        echo ""

        echo "=== Container Environment Variables ==="
        for container in "${CONTAINERS[@]}"; do
            echo "--- $container ---"
            docker exec $container env 2>/dev/null | grep -E "(VAULT_|POSTGRES_|MYSQL_|MONGO_|REDIS_|RABBITMQ_)" || echo "Container not running or no matching vars"
            echo ""
        done

        echo "=== Container Logs (last 50 lines) ==="
        for container in "${CONTAINERS[@]}"; do
            echo "--- $container ---"
            docker logs $container 2>&1 | tail -50 || echo "No logs available"
            echo ""
        done

        echo "=== docker-compose.yml Entrypoints ==="
        grep -A2 "entrypoint:" docker-compose.yml 2>&1 | head -30
        echo ""

        echo "=== docker-compose.yml Volume Mounts (init scripts) ==="
        grep "init" docker-compose.yml 2>&1 | head -30
        echo ""

        echo "=== Init Script Files ==="
        ls -la configs/*/scripts/init*.sh 2>&1
        echo ""

        echo "=== Vault Token File ==="
        if [ -f "$VAULT_ENV_FILE" ]; then
            echo "File exists: $VAULT_ENV_FILE"
            cat "$VAULT_ENV_FILE" | sed 's/hvs\.[^=]*/hvs.REDACTED/g'
        else
            echo "File not found: $VAULT_ENV_FILE"
        fi
        echo ""

    } > "$output_file" 2>&1

    log_success "Diagnostics saved to $output_file"
}

################################################################################
# FIX #3: Complete Backup Creation and Restoration
################################################################################

create_backup() {
    log_step "Creating backup in $BACKUP_DIR"

    mkdir -p "$BACKUP_DIR"

    # Backup init scripts
    for service in "${SERVICES[@]}"; do
        if [ -f "configs/$service/scripts/init-approle.sh" ]; then
            cp "configs/$service/scripts/init-approle.sh" "$BACKUP_DIR/init-approle-$service.sh"
        fi
    done

    # Backup docker-compose.yml (CRITICAL)
    cp docker-compose.yml "$BACKUP_DIR/docker-compose.yml"

    # Backup .env
    cp .env "$BACKUP_DIR/.env"

    log_success "Backup created: $BACKUP_DIR"
}

restore_from_backup() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log_fail "Backup directory not found: $BACKUP_DIR"
        return 1
    fi

    log_step "Restoring from backup: $BACKUP_DIR"

    # Restore init scripts
    for service in "${SERVICES[@]}"; do
        if [ -f "$BACKUP_DIR/init-approle-$service.sh" ]; then
            cp "$BACKUP_DIR/init-approle-$service.sh" "configs/$service/scripts/init-approle.sh"
        fi
    done

    # FIX #3: Restore docker-compose.yml
    if [ -f "$BACKUP_DIR/docker-compose.yml" ]; then
        cp "$BACKUP_DIR/docker-compose.yml" docker-compose.yml
        log_success "docker-compose.yml restored"
    else
        log_fail "docker-compose.yml backup not found"
        return 1
    fi

    # Restore .env
    if [ -f "$BACKUP_DIR/.env" ]; then
        cp "$BACKUP_DIR/.env" .env
        log_success ".env restored"
    fi

    # FIX #3: Verify restoration
    if ! grep -q "/init/init-approle.sh" docker-compose.yml; then
        log_fail "docker-compose.yml not properly restored (still has /init/init.sh)"
        return 1
    fi
    log_success "Verified docker-compose.yml contains init-approle.sh"

    # Clean up .bak files
    rm -f docker-compose.yml.bak configs/*/scripts/*.bak

    log_success "Backup restored and verified"
}

cleanup_bak_files() {
    log_step "Cleaning up .bak files and temp files..."
    find . -name "*.bak" -type f -delete 2>/dev/null || true
    rm -f "$VAULT_ENV_FILE" 2>/dev/null || true
    log_success "Cleanup complete"
}

################################################################################
# Phase 1: Baseline Validation (Current AppRole State)
################################################################################

phase1_baseline_validation() {
    log_phase "PHASE 1: Baseline Validation (AppRole Authentication)"

    log_step "Checking all services are running with AppRole..."

    local baseline_pass=0
    local baseline_fail=0

    for i in "${!SERVICES[@]}"; do
        local service="${SERVICES[$i]}"
        local container="${CONTAINERS[$i]}"

        echo ""
        echo -e "${YELLOW}Checking: $service ($container)${NC}"

        # Check 1: AppRole credentials exist on host
        if [ -f "$HOME/.config/vault/approles/$service/role-id" ] && [ -f "$HOME/.config/vault/approles/$service/secret-id" ]; then
            log_success "AppRole credentials exist on host"
            ((baseline_pass++))
        else
            log_fail "AppRole credentials NOT found on host"
            ((baseline_fail++))
            continue
        fi

        # Check 2: Container is running
        if docker ps --filter "name=$container" --format "{{.Status}}" | grep -q "Up"; then
            log_success "Container is running"
            ((baseline_pass++))
        else
            log_fail "Container is NOT running"
            ((baseline_fail++))
            continue
        fi

        # Check 3: No VAULT_TOKEN environment variable
        if docker exec $container env 2>/dev/null | grep -q "^VAULT_TOKEN="; then
            log_fail "VAULT_TOKEN found in container (should not exist with AppRole)"
            ((baseline_fail++))
        else
            log_success "No VAULT_TOKEN in container (AppRole required)"
            ((baseline_pass++))
        fi

        # Check 4: AppRole credentials mounted
        if docker exec $container test -f "/vault-approles/$service/role-id" 2>/dev/null; then
            log_success "AppRole credentials mounted in container"
            ((baseline_pass++))
        else
            log_fail "AppRole credentials NOT mounted in container"
            ((baseline_fail++))
        fi
    done

    echo ""
    echo -e "${BLUE}Baseline Results: ${GREEN}$baseline_pass passed${NC}, ${RED}$baseline_fail failed${NC}"

    if [ $baseline_fail -gt 0 ]; then
        echo -e "${RED}BASELINE VALIDATION FAILED - Cannot proceed with rollback test${NC}"
        return 1
    fi

    log_success "Baseline validation complete - All services using AppRole"
    return 0
}

################################################################################
# Phase 2: Execute Rollback to Root Token (WITH ALL FIXES)
################################################################################

phase2_rollback_execution() {
    log_phase "PHASE 2: Rollback Execution (AppRole → Root Token) [ALL FIXES APPLIED]"

    # Create backup before rollback
    create_backup

    # Step 1: Stop all services
    log_step "Stopping all services..."
    if !../devstack stop; then
        log_fail "Failed to stop services"
        capture_diagnostics
        return 1
    fi
    log_success "Services stopped"

    # Step 2: Get Vault token
    export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
    export VAULT_ADDR=http://localhost:8200
    log_step "Vault token loaded: ${VAULT_TOKEN:0:10}..."

    # FIX #1: Create vault environment file
    cat > "$VAULT_ENV_FILE" << EOF
VAULT_TOKEN=$VAULT_TOKEN
VAULT_ADDR=$VAULT_ADDR
EOF
    log_success "Created vault environment file: $VAULT_ENV_FILE"

    # Step 3: Revert init scripts to root token pattern
    log_step "Reverting init scripts to root token authentication..."

    for service in "${SERVICES[@]}"; do
        local init_script="configs/$service/scripts/init.sh"
        local service_entrypoint=$(get_service_entrypoint "$service")

        cat > "$init_script" << EOFINIT
#!/bin/bash
# Root token authentication version (FIXED)
export VAULT_ADDR="\${VAULT_ADDR:-http://vault:8200}"

if [ -z "\$VAULT_TOKEN" ]; then
    echo "ERROR: VAULT_TOKEN environment variable is required"
    exit 1
fi

# Wait for Vault
echo "Waiting for Vault..."
for i in {1..30}; do
    if curl -s "\$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
        echo "Vault is ready"
        break
    fi
    sleep 2
done

# Fetch credentials from Vault
SERVICE_NAME="$service"
echo "Fetching credentials for \$SERVICE_NAME from Vault using root token..."

SECRET_DATA=\$(curl -s -H "X-Vault-Token: \$VAULT_TOKEN" "\$VAULT_ADDR/v1/secret/data/\$SERVICE_NAME")

if [ -z "\$SECRET_DATA" ]; then
    echo "ERROR: Failed to fetch credentials from Vault"
    exit 1
fi

# Extract password using simple grep/sed (works without jq)
PASSWORD=\$(echo "\$SECRET_DATA" | grep -o '"password":"[^"]*"' | sed 's/"password":"\(.*\)"/\1/')

if [ -z "\$PASSWORD" ]; then
    echo "ERROR: Failed to extract password from Vault response"
    exit 1
fi

# Export for service
case "\$SERVICE_NAME" in
    postgres)
        export POSTGRES_PASSWORD="\$PASSWORD"
        ;;
    mysql)
        export MYSQL_ROOT_PASSWORD="\$PASSWORD"
        ;;
    mongodb)
        export MONGO_INITDB_ROOT_PASSWORD="\$PASSWORD"
        ;;
    redis)
        export REDIS_PASSWORD="\$PASSWORD"
        ;;
    rabbitmq)
        export RABBITMQ_DEFAULT_PASS="\$PASSWORD"
        ;;
    forgejo)
        export FORGEJO_ADMIN_PASSWORD="\$PASSWORD"
        ;;
esac

echo "Credentials fetched successfully using root token"
echo "VAULT_TOKEN is set: \${VAULT_TOKEN:0:10}..."

# Execute original entrypoint and pass through command args from docker-compose.yml
# The "\$@" passes all arguments that Docker provides from the command: section
exec $service_entrypoint "\$@"
EOFINIT

        chmod +x "$init_script"
        log_success "Created root token init script for $service"
    done

    # Step 4: Update docker-compose.yml
    log_step "Updating docker-compose.yml for root token authentication..."

    # Replace init-approle.sh with init.sh in entrypoints
    sed -i.bak 's|/init/init-approle.sh|/init/init.sh|g' docker-compose.yml

    # Replace init-approle.sh with init.sh in volume mounts
    sed -i.bak 's|init-approle.sh:/init/init-approle.sh|init.sh:/init/init.sh|g' docker-compose.yml

    # Remove AppRole volume mounts
    sed -i.bak '/vault-approles.*:ro/d' docker-compose.yml

    # Remove VAULT_APPROLE_DIR environment variables
    sed -i.bak '/VAULT_APPROLE_DIR:/d' docker-compose.yml

    log_success "docker-compose.yml updated for root token"

    # FIX #6: Verify docker-compose.yml changes
    if ! grep -q "/init/init.sh" docker-compose.yml; then
        log_fail "docker-compose.yml not properly updated (still has init-approle.sh)"
        capture_diagnostics
        restore_from_backup
        return 1
    fi
    log_success "Verified docker-compose.yml contains /init/init.sh"

    # Step 5: Start services with root token (FIX #1: Use --env-file)
    log_step "Starting services with root token authentication (using --env-file)..."

    # Use --env-file to pass VAULT_TOKEN to docker-compose
    if ! docker compose --env-file "$VAULT_ENV_FILE" up -d; then
        log_fail "Failed to start services with root token"

        # FIX #4: Capture diagnostics before restoration
        capture_diagnostics

        echo -e "${YELLOW}Diagnostics saved. Restoring from backup...${NC}"
        restore_from_backup
        # FIX #2: Remove invalid --profile flag
       ../devstack restart
        cleanup_bak_files
        return 1
    fi
    log_success "Services started with root token"

    # FIX #5: Verify VAULT_TOKEN reached containers
    sleep 10  # Give containers time to start
    log_step "Verifying VAULT_TOKEN reached containers..."

    local token_verification_pass=0
    local token_verification_fail=0

    for container in "${CONTAINERS[@]}"; do
        if docker exec $container env 2>/dev/null | grep -q "^VAULT_TOKEN="; then
            log_success "$container has VAULT_TOKEN"
            ((token_verification_pass++))
        else
            log_fail "$container does NOT have VAULT_TOKEN"
            ((token_verification_fail++))
        fi
    done

    if [ $token_verification_fail -gt 0 ]; then
        log_fail "VAULT_TOKEN verification failed ($token_verification_fail/6)"
        capture_diagnostics
        restore_from_backup
       ../devstack restart
        cleanup_bak_files
        return 1
    fi
    log_success "VAULT_TOKEN verified in all containers ($token_verification_pass/6)"

    # Wait for services to be healthy
    if ! wait_for_services; then
        log_fail "Services failed to become healthy after rollback"

        # FIX #4: Capture diagnostics
        capture_diagnostics

        echo -e "${YELLOW}Diagnostics saved. Restoring from backup...${NC}"
        restore_from_backup
        # FIX #2: Remove invalid --profile flag
       ../devstack restart
        cleanup_bak_files
        return 1
    fi

    log_success "Rollback to root token authentication complete"
    return 0
}

################################################################################
# Phase 3: Validate Root Token Authentication
################################################################################

phase3_validate_root_token() {
    log_phase "PHASE 3: Validate Root Token Authentication"

    local validation_pass=0
    local validation_fail=0

    # Get passwords from Vault for authentication testing
    local VAULT_TOKEN=$(cat ~/.config/vault/root-token)
    local REDIS_PASS=$(docker exec -e VAULT_ADDR=http://vault:8200 -e VAULT_TOKEN="$VAULT_TOKEN" dev-vault \
        vault kv get -field=password secret/redis 2>/dev/null)

    for i in "${!CONTAINERS[@]}"; do
        local container="${CONTAINERS[$i]}"
        local service="${SERVICES[$i]}"

        echo ""
        echo -e "${YELLOW}Validating: $service ($container)${NC}"

        # Check 1: Container is running
        if docker ps --filter "name=$container" --format "{{.Status}}" | grep -q "Up"; then
            log_success "Container is running"
            ((validation_pass++))
        else
            log_fail "Container is NOT running"
            ((validation_fail++))
            continue
        fi

        # Check 2: Service is healthy (can connect)
        case "$service" in
            postgres)
                if docker exec $container pg_isready -U postgres > /dev/null 2>&1; then
                    log_success "PostgreSQL is accepting connections"
                    ((validation_pass++))
                else
                    log_fail "PostgreSQL is NOT accepting connections"
                    ((validation_fail++))
                fi
                ;;
            mysql)
                if docker exec $container mysqladmin ping -h localhost --silent 2>/dev/null; then
                    log_success "MySQL is accepting connections"
                    ((validation_pass++))
                else
                    log_fail "MySQL is NOT accepting connections"
                    ((validation_fail++))
                fi
                ;;
            mongodb)
                if docker exec $container mongosh --quiet --eval "db.adminCommand('ping').ok" 2>/dev/null | grep -q "1"; then
                    log_success "MongoDB is accepting connections"
                    ((validation_pass++))
                else
                    log_fail "MongoDB is NOT accepting connections"
                    ((validation_fail++))
                fi
                ;;
            redis)
                if docker exec $container redis-cli -a "$REDIS_PASS" --no-auth-warning ping 2>/dev/null | grep -q "PONG"; then
                    log_success "Redis is accepting connections"
                    ((validation_pass++))
                else
                    log_fail "Redis is NOT accepting connections"
                    ((validation_fail++))
                fi
                ;;
            rabbitmq)
                if docker exec $container rabbitmqctl status > /dev/null 2>&1; then
                    log_success "RabbitMQ is accepting connections"
                    ((validation_pass++))
                else
                    log_fail "RabbitMQ is NOT accepting connections"
                    ((validation_fail++))
                fi
                ;;
            forgejo)
                # Check if web interface responds
                if curl -s http://localhost:3000 > /dev/null 2>&1; then
                    log_success "Forgejo web interface is responding"
                    ((validation_pass++))
                else
                    log_fail "Forgejo web interface is NOT responding"
                    ((validation_fail++))
                fi
                ;;
        esac
    done

    echo ""
    echo -e "${BLUE}Root Token Validation Results: ${GREEN}$validation_pass passed${NC}, ${RED}$validation_fail failed${NC}"

    if [ $validation_fail -gt 0 ]; then
        echo -e "${RED}ROOT TOKEN VALIDATION FAILED${NC}"
        capture_diagnostics
        echo -e "${YELLOW}Restoring from backup...${NC}"
        restore_from_backup
        # FIX #2: Remove invalid --profile flag
       ../devstack restart
        cleanup_bak_files
        return 1
    fi

    log_success "Root token authentication validated"
    return 0
}

################################################################################
# Phase 4: Re-migrate to AppRole
################################################################################

phase4_remigrate_to_approle() {
    log_phase "PHASE 4: Re-migration to AppRole Authentication"

    log_step "Stopping services before re-migration..."
   ../devstack stop

    log_step "Restoring AppRole configuration from backup..."
    if ! restore_from_backup; then
        log_fail "Failed to restore from backup"
        return 1
    fi

    log_step "Starting services with AppRole..."
    # FIX #2: Remove invalid --profile flag
    if !../devstack start; then
        log_fail "Failed to start services"
        return 1
    fi

    if ! wait_for_services; then
        log_fail "Services failed to become healthy after re-migration"
        return 1
    fi

    log_success "Re-migration to AppRole complete"
    return 0
}

################################################################################
# Phase 5: Final Validation (Back to AppRole)
################################################################################

phase5_final_validation() {
    log_phase "PHASE 5: Final Validation (AppRole Authentication Restored)"

    local final_pass=0
    local final_fail=0

    for i in "${!SERVICES[@]}"; do
        local service="${SERVICES[$i]}"
        local container="${CONTAINERS[$i]}"

        echo ""
        echo -e "${YELLOW}Final Check: $service ($container)${NC}"

        # Check 1: AppRole credentials exist
        if [ -f "$HOME/.config/vault/approles/$service/role-id" ]; then
            log_success "AppRole credentials exist"
            ((final_pass++))
        else
            log_fail "AppRole credentials NOT found"
            ((final_fail++))
        fi

        # Check 2: No VAULT_TOKEN
        if docker exec $container env 2>/dev/null | grep -q "^VAULT_TOKEN="; then
            log_fail "VAULT_TOKEN found (should not exist)"
            ((final_fail++))
        else
            log_success "No VAULT_TOKEN (AppRole required)"
            ((final_pass++))
        fi

        # Check 3: AppRole credentials mounted
        if docker exec $container test -f "/vault-approles/$service/role-id" 2>/dev/null; then
            log_success "AppRole credentials mounted"
            ((final_pass++))
        else
            log_fail "AppRole credentials NOT mounted"
            ((final_fail++))
        fi
    done

    echo ""
    echo -e "${BLUE}Final Validation Results: ${GREEN}$final_pass passed${NC}, ${RED}$final_fail failed${NC}"

    if [ $final_fail -gt 0 ]; then
        echo -e "${RED}FINAL VALIDATION FAILED - Environment may be in inconsistent state${NC}"
        return 1
    fi

    # Clean up .bak files and temp files
    cleanup_bak_files

    log_success "Final validation complete - Back to AppRole authentication"
    return 0
}

################################################################################
# Main Test Execution
################################################################################

main() {
    local overall_result=0

    # Safety check
    echo -e "${YELLOW}WARNING: This is a DESTRUCTIVE test${NC}"
    echo -e "${YELLOW}It will modify your environment and restart services multiple times${NC}"
    echo ""
    echo -e "${CYAN}This version includes ALL fixes:${NC}"
    echo -e "  ${GREEN}✓${NC} Fix #1: VAULT_TOKEN propagation via --env-file"
    echo -e "  ${GREEN}✓${NC} Fix #2: Removed invalid --profile flags"
    echo -e "  ${GREEN}✓${NC} Fix #3: Complete backup/restore"
    echo -e "  ${GREEN}✓${NC} Fix #4: Comprehensive diagnostics"
    echo -e "  ${GREEN}✓${NC} Fix #5: Environment variable validation"
    echo -e "  ${GREEN}✓${NC} Fix #6: docker-compose.yml verification"
    echo ""
    echo -e "Press ${GREEN}ENTER${NC} to continue or ${RED}Ctrl+C${NC} to abort..."
    read

    # Execute test phases
    if ! phase1_baseline_validation; then
        echo -e "${RED}Phase 1 FAILED - Aborting test${NC}"
        exit 1
    fi

    if ! phase2_rollback_execution; then
        echo -e "${RED}Phase 2 FAILED - Attempting recovery${NC}"
        restore_from_backup
       ../devstack restart
        cleanup_bak_files
        exit 1
    fi

    if ! phase3_validate_root_token; then
        echo -e "${RED}Phase 3 FAILED - Attempting recovery${NC}"
        restore_from_backup
       ../devstack restart
        cleanup_bak_files
        exit 1
    fi

    if ! phase4_remigrate_to_approle; then
        echo -e "${RED}Phase 4 FAILED - Environment may be in inconsistent state${NC}"
        cleanup_bak_files
        exit 1
    fi

    if ! phase5_final_validation; then
        echo -e "${RED}Phase 5 FAILED - Environment may be in inconsistent state${NC}"
        cleanup_bak_files
        exit 1
    fi

    # Final summary
    echo ""
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}  Test Summary${NC}"
    echo -e "${MAGENTA}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}✓ Phase 1: Baseline Validation - PASSED${NC}"
    echo -e "${GREEN}✓ Phase 2: Rollback Execution - PASSED${NC}"
    echo -e "${GREEN}✓ Phase 3: Root Token Validation - PASSED${NC}"
    echo -e "${GREEN}✓ Phase 4: Re-migration - PASSED${NC}"
    echo -e "${GREEN}✓ Phase 5: Final Validation - PASSED${NC}"
    echo ""
    echo -e "${GREEN}✓✓✓ ROLLBACK PROCEDURES VALIDATED SUCCESSFULLY ✓✓✓${NC}"
    echo -e "${GREEN}✓ Rollback to root token: WORKS${NC}"
    echo -e "${GREEN}✓ Re-migration to AppRole: WORKS${NC}"
    echo -e "${GREEN}✓ Environment restored successfully${NC}"
    echo -e "${GREEN}✓ ALL FIXES CONFIRMED WORKING${NC}"
    echo ""
    echo -e "${BLUE}Backup location: $BACKUP_DIR${NC}"
    echo -e "${YELLOW}You can safely delete the backup: rm -rf $BACKUP_DIR${NC}"
    echo ""
}

# Run main function
main
