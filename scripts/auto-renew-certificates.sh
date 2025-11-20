#!/usr/bin/env bash
#######################################
# Certificate Auto-Renewal Script
#
# This script automatically renews TLS certificates that are within 30 days of expiration.
# It should be run via cron to ensure certificates are renewed before they expire.
#
# Globals:
#   VAULT_ADDR          - Vault server address (default: http://localhost:8200)
#   VAULT_TOKEN         - Vault authentication token (required)
#   CERT_BASE_DIR       - Base directory for certificate storage (default: ~/.config/vault/certs)
#   RENEWAL_THRESHOLD   - Days before expiration to renew (default: 30)
#   LOG_FILE            - Log file for renewal operations (default: ~/.config/vault/cert-renewal.log)
#
# Arguments:
#   --dry-run     - Show what would be renewed without actually renewing
#   --force       - Force renewal of all certificates regardless of expiration
#   --service     - Renew only specific service (e.g., --service postgres)
#   --quiet       - Suppress output (useful for cron)
#
# Usage:
#   ./auto-renew-certificates.sh                    # Normal renewal
#   ./auto-renew-certificates.sh --dry-run          # Preview what would be renewed
#   ./auto-renew-certificates.sh --force            # Force all renewals
#   ./auto-renew-certificates.sh --service postgres # Renew only postgres
#   ./auto-renew-certificates.sh --quiet            # Silent mode for cron
#
# Cron Setup:
#   # Run daily at 2 AM
#   0 2 * * * /path/to/auto-renew-certificates.sh --quiet
#
#   # Run weekly on Sunday at 3 AM
#   0 3 * * 0 /path/to/auto-renew-certificates.sh
#
# Dependencies:
#   - bash (version 4.0+)
#   - openssl
#   - generate-certificates.sh (in same directory)
#   - Vault server must be running and accessible
#
# Exit Codes:
#   0 - Success: no renewals needed or all renewals successful
#   1 - Error: missing dependencies or renewal failed
#   2 - Warning: some certificates renewed, some failed
#
# Notifications:
#   - Logs all operations to ~/.config/vault/cert-renewal.log
#   - Exits with non-zero code if any renewal fails
#   - Can be integrated with monitoring/alerting systems
#
#######################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-$(cat ~/.config/vault/root-token 2>/dev/null)}"
CERT_BASE_DIR="${HOME}/.config/vault/certs"
RENEWAL_THRESHOLD=${RENEWAL_THRESHOLD:-30}  # Days before expiration
LOG_FILE="${HOME}/.config/vault/cert-renewal.log"

# Parse arguments
DRY_RUN=false
FORCE=false
SPECIFIC_SERVICE=""
QUIET=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --service)
            SPECIFIC_SERVICE="$2"
            shift 2
            ;;
        --quiet)
            QUIET=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--force] [--service SERVICE] [--quiet]"
            exit 1
            ;;
    esac
done

# Logging function
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
    if [[ "$QUIET" == "false" ]]; then
        echo -e "$message"
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()

    for cmd in openssl; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -ne 0 ]; then
        log "${RED}✗ Missing required dependencies: ${missing[*]}${NC}"
        exit 1
    fi

    if [ ! -f "$SCRIPT_DIR/generate-certificates.sh" ]; then
        log "${RED}✗ generate-certificates.sh not found in $SCRIPT_DIR${NC}"
        exit 1
    fi

    if [ -z "$VAULT_TOKEN" ]; then
        log "${RED}✗ VAULT_TOKEN not set and ~/.config/vault/root-token not found${NC}"
        exit 1
    fi
}

# Get certificate expiration date in seconds since epoch
get_cert_expiration() {
    local cert_file="$1"

    if [ ! -f "$cert_file" ]; then
        echo "0"
        return
    fi

    local expiration=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [ -z "$expiration" ]; then
        echo "0"
        return
    fi

    # Convert to epoch seconds
    date -j -f "%b %d %T %Y %Z" "$expiration" "+%s" 2>/dev/null || echo "0"
}

# Get days until expiration
get_days_until_expiration() {
    local cert_file="$1"
    local expiration_epoch=$(get_cert_expiration "$cert_file")

    if [ "$expiration_epoch" -eq 0 ]; then
        echo "-1"
        return
    fi

    local now_epoch=$(date +%s)
    local seconds_until_expiration=$((expiration_epoch - now_epoch))
    local days_until_expiration=$((seconds_until_expiration / 86400))

    echo "$days_until_expiration"
}

# Check if certificate needs renewal
needs_renewal() {
    local service="$1"
    local cert_file="$CERT_BASE_DIR/$service/server.crt"

    if [ ! -f "$cert_file" ]; then
        log "${YELLOW}  ⚠ Certificate not found for $service${NC}"
        return 0  # Needs generation
    fi

    local days_remaining=$(get_days_until_expiration "$cert_file")

    if [ "$days_remaining" -eq -1 ]; then
        log "${YELLOW}  ⚠ Cannot parse expiration for $service${NC}"
        return 0  # Needs renewal
    fi

    if [ "$days_remaining" -lt "$RENEWAL_THRESHOLD" ]; then
        log "${YELLOW}  ⚠ Certificate for $service expires in $days_remaining days (threshold: $RENEWAL_THRESHOLD)${NC}"
        return 0  # Needs renewal
    fi

    log "${GREEN}  ✓ Certificate for $service valid for $days_remaining more days${NC}"
    return 1  # No renewal needed
}

# Renew certificate for a service
renew_certificate() {
    local service="$1"

    log "${BLUE}  → Renewing certificate for $service${NC}"

    if [ "$DRY_RUN" == "true" ]; then
        log "${CYAN}  [DRY RUN] Would renew certificate for $service${NC}"
        return 0
    fi

    # Remove old certificate
    if [ -d "$CERT_BASE_DIR/$service" ]; then
        rm -rf "$CERT_BASE_DIR/$service"
        log "${BLUE}    Removed old certificate directory${NC}"
    fi

    # Run certificate generation script for this service
    export VAULT_ADDR
    export VAULT_TOKEN

    # Generate new certificate (the script handles individual services)
    if "$SCRIPT_DIR/generate-certificates.sh" 2>&1 | grep -q "$service"; then
        log "${GREEN}  ✓ Certificate renewed for $service${NC}"
        return 0
    else
        log "${RED}  ✗ Failed to renew certificate for $service${NC}"
        return 1
    fi
}

# Get list of services
get_services() {
    if [ -n "$SPECIFIC_SERVICE" ]; then
        echo "$SPECIFIC_SERVICE"
        return
    fi

    if [ ! -d "$CERT_BASE_DIR" ]; then
        log "${YELLOW}⚠ Certificate directory not found: $CERT_BASE_DIR${NC}"
        return
    fi

    # List all service directories
    find "$CERT_BASE_DIR" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
}

# Main execution
main() {
    log "${BLUE}═══════════════════════════════════════════════════════${NC}"
    log "${BLUE}  Certificate Auto-Renewal${NC}"
    log "${BLUE}  Threshold: $RENEWAL_THRESHOLD days${NC}"
    if [ "$DRY_RUN" == "true" ]; then
        log "${CYAN}  Mode: DRY RUN${NC}"
    fi
    if [ "$FORCE" == "true" ]; then
        log "${YELLOW}  Mode: FORCE RENEWAL${NC}"
    fi
    log "${BLUE}═══════════════════════════════════════════════════════${NC}"

    # Check dependencies
    check_dependencies

    # Get services to check
    local services=$(get_services)

    if [ -z "$services" ]; then
        log "${YELLOW}⚠ No services found${NC}"
        exit 0
    fi

    local renewal_count=0
    local failure_count=0
    local skip_count=0

    # Check each service
    for service in $services; do
        log ""
        log "${BLUE}Checking $service...${NC}"

        if [ "$FORCE" == "true" ]; then
            log "${YELLOW}  [FORCE] Forcing renewal${NC}"
            if renew_certificate "$service"; then
                ((renewal_count++))
            else
                ((failure_count++))
            fi
        else
            if needs_renewal "$service"; then
                if renew_certificate "$service"; then
                    ((renewal_count++))
                else
                    ((failure_count++))
                fi
            else
                ((skip_count++))
            fi
        fi
    done

    # Summary
    log ""
    log "${BLUE}═══════════════════════════════════════════════════════${NC}"
    log "${BLUE}  Renewal Summary${NC}"
    log "${BLUE}═══════════════════════════════════════════════════════${NC}"
    log "  Renewed: $renewal_count"
    log "  Skipped: $skip_count"
    log "  Failed:  $failure_count"
    log ""

    if [ $failure_count -gt 0 ]; then
        log "${RED}✗ Some certificate renewals failed${NC}"
        exit 2
    elif [ $renewal_count -gt 0 ]; then
        log "${GREEN}✓ Certificate renewal completed successfully${NC}"
        log "${YELLOW}⚠ Remember to restart affected services to use new certificates${NC}"
        exit 0
    else
        log "${GREEN}✓ No certificates needed renewal${NC}"
        exit 0
    fi
}

# Run main function
main
