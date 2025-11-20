#!/usr/bin/env bash
#######################################
# Certificate Renewal Cron Setup Script
#
# This script sets up automated certificate renewal via cron.
# It creates cron jobs to check and renew certificates automatically.
#
# Arguments:
#   --remove    - Remove cron jobs
#   --list      - List existing cron jobs
#
# Usage:
#   ./setup-cert-renewal-cron.sh          # Install cron jobs
#   ./setup-cert-renewal-cron.sh --list   # List cron jobs
#   ./setup-cert-renewal-cron.sh --remove # Remove cron jobs
#
#######################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRON_COMMENT="# DevStack Core - Certificate Auto-Renewal"

# Check if running on macOS or Linux
if [[ "$OSTYPE" == "darwin"* ]]; then
    IS_MACOS=true
else
    IS_MACOS=false
fi

# List existing cron jobs
list_cron_jobs() {
    echo -e "${BLUE}Current Certificate Renewal Cron Jobs:${NC}"
    echo ""

    if crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
        crontab -l | grep -A 2 "$CRON_COMMENT"
        echo ""
        echo -e "${GREEN}✓ Cron jobs are installed${NC}"
    else
        echo -e "${YELLOW}No certificate renewal cron jobs found${NC}"
    fi
}

# Remove cron jobs
remove_cron_jobs() {
    echo -e "${BLUE}Removing Certificate Renewal Cron Jobs...${NC}"

    if crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
        # Remove lines with the comment and the two lines after it
        crontab -l 2>/dev/null | grep -v "$CRON_COMMENT" | grep -v "auto-renew-certificates.sh" | grep -v "check-cert-expiration.sh" | crontab -
        echo -e "${GREEN}✓ Cron jobs removed${NC}"
    else
        echo -e "${YELLOW}No cron jobs to remove${NC}"
    fi
}

# Install cron jobs
install_cron_jobs() {
    echo -e "${BLUE}Installing Certificate Renewal Cron Jobs...${NC}"
    echo ""

    # Check if cron jobs already exist
    if crontab -l 2>/dev/null | grep -q "$CRON_COMMENT"; then
        echo -e "${YELLOW}⚠ Cron jobs already exist${NC}"
        echo -e "${YELLOW}  Run with --remove first to reinstall${NC}"
        return 1
    fi

    # Create temp file with existing crontab + new jobs
    local temp_cron=$(mktemp)

    # Get existing crontab (if any)
    crontab -l 2>/dev/null > "$temp_cron" || true

    # Add new cron jobs
    cat >> "$temp_cron" <<EOF

$CRON_COMMENT
# Daily certificate renewal check at 2:00 AM
0 2 * * * $SCRIPT_DIR/auto-renew-certificates.sh --quiet >> $HOME/.config/vault/cert-renewal.log 2>&1

# Weekly certificate expiration report (Sunday at 9:00 AM)
0 9 * * 0 $SCRIPT_DIR/check-cert-expiration.sh >> $HOME/.config/vault/cert-check.log 2>&1
EOF

    # Install new crontab
    crontab "$temp_cron"
    rm "$temp_cron"

    echo -e "${GREEN}✓ Cron jobs installed successfully${NC}"
    echo ""
    echo -e "${BLUE}Installed Jobs:${NC}"
    echo "  • Daily renewal check:   2:00 AM (auto-renew-certificates.sh)"
    echo "  • Weekly status report:  9:00 AM Sunday (check-cert-expiration.sh)"
    echo ""
    echo -e "${BLUE}Log Files:${NC}"
    echo "  • Renewal log:  ~/.config/vault/cert-renewal.log"
    echo "  • Check log:    ~/.config/vault/cert-check.log"
    echo ""
    echo -e "${YELLOW}Note: Ensure Vault is running when cron jobs execute${NC}"
    echo -e "${YELLOW}      Consider using devstack to start Vault on boot${NC}"
}

# Main execution
main() {
    if [[ $# -eq 0 ]]; then
        install_cron_jobs
    else
        case "$1" in
            --list)
                list_cron_jobs
                ;;
            --remove)
                remove_cron_jobs
                ;;
            *)
                echo "Usage: $0 [--list|--remove]"
                exit 1
                ;;
        esac
    fi
}

main "$@"
