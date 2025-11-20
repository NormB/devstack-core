#!/bin/bash
#
# Vault Restore Script
# =====================
#
# This script restores HashiCorp Vault configuration from a backup archive.
#
# Usage:
#   ./scripts/vault-restore.sh <backup_archive>
#
# Arguments:
#   backup_archive - Path to backup tar.gz file
#
# Author: DevStack Core Team
# Version: 1.0

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VAULT_CONFIG_DIR="${HOME}/.config/vault"

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

main() {
    local archive="$1"

    if [ -z "$archive" ]; then
        error "Usage: $0 <backup_archive.tar.gz>"
    fi

    if [ ! -f "$archive" ]; then
        error "Backup archive not found: $archive"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "                        VAULT RESTORE"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""

    # Create temp directory for extraction
    local temp_dir=$(mktemp -d)
    info "Extracting backup archive to: $temp_dir"
    tar -xzf "$archive" -C "$temp_dir"

    # Find backup directory (should be only one)
    local backup_dir=$(find "$temp_dir" -maxdepth 1 -type d ! -path "$temp_dir" | head -1)

    if [ -z "$backup_dir" ]; then
        rm -rf "$temp_dir"
        error "No backup directory found in archive"
    fi

    # Backup current config
    if [ -d "$VAULT_CONFIG_DIR" ]; then
        warn "Backing up current Vault config to ${VAULT_CONFIG_DIR}.backup"
        mv "$VAULT_CONFIG_DIR" "${VAULT_CONFIG_DIR}.backup"
    fi

    # Restore from backup
    info "Restoring Vault configuration..."
    mkdir -p "$VAULT_CONFIG_DIR"
    cp -r "$backup_dir"/* "$VAULT_CONFIG_DIR/"

    # Set proper permissions
    chmod 700 "$VAULT_CONFIG_DIR"
    chmod 600 "$VAULT_CONFIG_DIR"/keys.json "$VAULT_CONFIG_DIR"/root-token 2>/dev/null || true
    if [ -d "$VAULT_CONFIG_DIR/approles" ]; then
        chmod 700 "$VAULT_CONFIG_DIR/approles"/*
        chmod 600 "$VAULT_CONFIG_DIR/approles"/*/*
    fi

    # Cleanup
    rm -rf "$temp_dir"

    success "Vault configuration restored successfully!"
    echo ""
    echo "Restored files in $VAULT_CONFIG_DIR"
    ls -lh "$VAULT_CONFIG_DIR"
    echo ""
    echo "To use restored Vault, restart services: ./devstack restart"
    echo ""
}

main "$@"
