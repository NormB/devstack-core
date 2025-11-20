#!/usr/bin/env bash
#
# Install git hooks for API synchronization validation.
#
# This script installs pre-commit hooks that enforce API synchronization
# LOCALLY before code reaches CI/CD. This is the primary enforcement layer.
#
# Usage:
#     ./scripts/install-hooks.sh
#
# Returns:
#     0: Hooks installed successfully
#     1: Installation failed
#
# Author:
#     Development Team
#
# Date:
#     2025-10-27
#

set -e
set -u
set -o pipefail

# Script directory and project root
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; exit "${2:-1}"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

#######################################
# Install pre-commit hook.
#
# Returns:
#   0 - Hook installed successfully
#######################################
install_precommit_hook() {
    local hook_source="${SCRIPT_DIR}/hooks/pre-commit"
    local hook_dest="${PROJECT_ROOT}/.git/hooks/pre-commit"

    info "Installing pre-commit hook..."

    # Check if source exists
    if [ ! -f "$hook_source" ]; then
        error "Hook source not found: $hook_source"
    fi

    # Backup existing hook if present
    if [ -f "$hook_dest" ]; then
        local backup="${hook_dest}.backup.$(date +%Y%m%d_%H%M%S)"
        info "Backing up existing hook to: $backup"
        mv "$hook_dest" "$backup"
    fi

    # Create symbolic link
    ln -sf "../../scripts/hooks/pre-commit" "$hook_dest"

    # Verify installation
    if [ -L "$hook_dest" ]; then
        success "Pre-commit hook installed"
    else
        error "Failed to install pre-commit hook"
    fi
}

#######################################
# Verify installation.
#
# Returns:
#   0 - Installation verified
#######################################
verify_installation() {
    local hook_file="${PROJECT_ROOT}/.git/hooks/pre-commit"

    info "Verifying installation..."

    # Check if hook exists
    if [ ! -f "$hook_file" ]; then
        error "Hook not found after installation"
    fi

    # Check if hook is executable
    if [ ! -x "$hook_file" ]; then
        warn "Hook is not executable - fixing..."
        chmod +x "$hook_file"
    fi

    # Test hook syntax
    if bash -n "$hook_file" 2>/dev/null; then
        success "Hook syntax is valid"
    else
        error "Hook has syntax errors"
    fi

    success "Installation verified"
}

#######################################
# Display post-install instructions.
#
# Returns:
#   None
#######################################
show_instructions() {
    echo ""
    info "Git hooks installed successfully!"
    echo ""
    echo "The pre-commit hook will now run automatically before each commit."
    echo ""
    echo "What it checks:"
    echo "  ✓ OpenAPI spec is valid YAML"
    echo "  ✓ API implementations are synchronized (if running)"
    echo "  ✓ Router changes are intentional"
    echo ""
    echo "To bypass the hook (use sparingly):"
    echo "  git commit --no-verify"
    echo ""
    echo "To test the hook manually:"
    echo "  .git/hooks/pre-commit"
    echo ""
    echo "To uninstall:"
    echo "  rm .git/hooks/pre-commit"
    echo ""
}

#######################################
# Main execution.
#######################################
main() {
    info "Installing git hooks for API synchronization..."
    echo ""

    # Check if in git repository
    if [ ! -d "${PROJECT_ROOT}/.git" ]; then
        error "Not a git repository: $PROJECT_ROOT"
    fi

    # Ensure hooks directory exists
    mkdir -p "${PROJECT_ROOT}/.git/hooks"

    # Install hooks
    install_precommit_hook
    echo ""

    # Verify installation
    verify_installation
    echo ""

    # Show instructions
    show_instructions

    success "✓ Git hooks installation complete!"
}

main "$@"
