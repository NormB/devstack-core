#!/bin/bash
#
# Vault Backup Script
# ====================
#
# This script creates a comprehensive backup of HashiCorp Vault configuration,
# keys, tokens, certificates, and AppRole credentials.
#
# Usage:
#   ./scripts/vault-backup.sh [backup_dir]
#
# Arguments:
#   backup_dir - Optional. Directory to store backup (default: ./backups/vault-YYYYMMDD_HHMMSS)
#
# What Gets Backed Up:
#   - Vault unseal keys (~/.config/vault/keys.json)
#   - Vault root token (~/.config/vault/root-token)
#   - CA certificates (~/.config/vault/ca/)
#   - Service certificates (~/.config/vault/certs/)
#   - AppRole credentials (~/.config/vault/approles/)
#
# Output:
#   - Timestamped tar.gz archive in backup directory
#   - Verification report showing backed up files
#
# Exit Codes:
#   0 - Backup successful
#   1 - Backup failed
#
# Author: DevStack Core Team
# Version: 1.0
# Date: November 15, 2025

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
VAULT_CONFIG_DIR="${HOME}/.config/vault"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEFAULT_BACKUP_DIR="${PROJECT_ROOT}/backups/vault-${TIMESTAMP}"
BACKUP_DIR="${1:-$DEFAULT_BACKUP_DIR}"

# Logging functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Main backup function
main() {
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                         VAULT BACKUP"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""

    # Check if Vault config directory exists
    if [ ! -d "$VAULT_CONFIG_DIR" ]; then
        error "Vault config directory not found: $VAULT_CONFIG_DIR"
    fi

    # Create backup directory
    info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"

    # Backup unseal keys
    info "Backing up Vault unseal keys..."
    if [ -f "$VAULT_CONFIG_DIR/keys.json" ]; then
        cp "$VAULT_CONFIG_DIR/keys.json" "$BACKUP_DIR/"
        success "Unseal keys backed up"
    else
        warn "Unseal keys not found (keys.json)"
    fi

    # Backup root token
    info "Backing up Vault root token..."
    if [ -f "$VAULT_CONFIG_DIR/root-token" ]; then
        cp "$VAULT_CONFIG_DIR/root-token" "$BACKUP_DIR/"
        success "Root token backed up"
    else
        warn "Root token not found (root-token)"
    fi

    # Backup CA certificates
    info "Backing up CA certificates..."
    if [ -d "$VAULT_CONFIG_DIR/ca" ]; then
        cp -r "$VAULT_CONFIG_DIR/ca" "$BACKUP_DIR/"
        success "CA certificates backed up"
    else
        warn "CA directory not found"
    fi

    # Backup service certificates
    info "Backing up service certificates..."
    if [ -d "$VAULT_CONFIG_DIR/certs" ]; then
        cp -r "$VAULT_CONFIG_DIR/certs" "$BACKUP_DIR/"
        success "Service certificates backed up"
    else
        warn "Certs directory not found"
    fi

    # Backup AppRole credentials
    info "Backing up AppRole credentials..."
    if [ -d "$VAULT_CONFIG_DIR/approles" ]; then
        cp -r "$VAULT_CONFIG_DIR/approles" "$BACKUP_DIR/"
        success "AppRole credentials backed up"
    else
        warn "AppRoles directory not found"
    fi

    # Create compressed archive
    info "Creating compressed archive..."
    cd "$(dirname "$BACKUP_DIR")"
    tar -czf "$(basename "$BACKUP_DIR").tar.gz" "$(basename "$BACKUP_DIR")"
    success "Archive created: $(basename "$BACKUP_DIR").tar.gz"

    # Verify backup
    info "Verifying backup..."
    local backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    local archive_size=$(du -sh "$(basename "$BACKUP_DIR").tar.gz" | cut -f1)

    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                       BACKUP VERIFICATION"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "Backup directory: $BACKUP_DIR"
    echo "Archive file: $(dirname "$BACKUP_DIR")/$(basename "$BACKUP_DIR").tar.gz"
    echo "Backup size: $backup_size"
    echo "Archive size: $archive_size"
    echo ""
    echo "Backed up files:"
    ls -lh "$BACKUP_DIR"
    echo ""

    success "Vault backup completed successfully!"
    echo ""
    echo "To restore from this backup, run:"
    echo "  ./scripts/vault-restore.sh $(dirname "$BACKUP_DIR")/$(basename "$BACKUP_DIR").tar.gz"
    echo ""
}

# Run main function
main "$@"
