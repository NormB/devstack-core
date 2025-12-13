"""
DevStack Core Python Package
============================

Modular Python management interface for DevStack Core infrastructure.

This package provides:
- Utility functions for command execution and configuration
- Vault integration (AppRole auth, secrets management)
- Backup/restore operations with encryption
- Profile management for service deployment
- Health checking and monitoring

Modules:
- utils: Core utility functions (run_command, config loading)
- vault: Vault authentication and secrets management
- backup: Backup/restore with encryption support
- profiles: Service profile management
- health: Health checking utilities

Usage:
    from devstack.utils import run_command
    from devstack.vault import get_vault_token, get_vault_secret
    from devstack.backup import create_backup, restore_backup
"""

__version__ = "1.0.0"
__author__ = "DevStack Core Team"
