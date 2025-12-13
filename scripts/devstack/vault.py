"""
DevStack Vault Integration Module
=================================

Vault authentication and secrets management functions.

This module provides:
- Root token management
- AppRole authentication
- Secret retrieval from Vault KV store
- Vault health checking

Functions:
- check_vault_token: Check if Vault root token exists
- get_vault_token: Get Vault root token
- get_vault_approle_token: Authenticate using AppRole
- get_vault_secret: Retrieve a secret from Vault
- check_vault_health: Check Vault server health
"""

from __future__ import annotations

from pathlib import Path
from typing import Optional

from .utils import run_command, console, VAULT_CONFIG_DIR


def check_vault_token() -> bool:
    """
    Check if Vault root token exists.

    Returns:
        True if root-token file exists, False otherwise
    """
    token_file = VAULT_CONFIG_DIR / "root-token"
    return token_file.exists()


def get_vault_token() -> Optional[str]:
    """
    Get Vault root token from config file.

    Returns:
        Root token string, or None if not found
    """
    token_file = VAULT_CONFIG_DIR / "root-token"
    if not token_file.exists():
        return None
    return token_file.read_text().strip()


def get_vault_approle_token(service: str = "management") -> Optional[str]:
    """
    Authenticate to Vault using AppRole and return a client token.

    Args:
        service: Service name for AppRole credentials (default: "management")

    Returns:
        Vault client token string, or None if authentication fails

    Notes:
        - Reads role_id and secret_id from ~/.config/vault/approles/{service}/
        - Returns a temporary token with limited permissions
        - Token TTL is typically 1 hour (configurable in Vault)
    """
    approle_dir = VAULT_CONFIG_DIR / "approles" / service
    role_id_file = approle_dir / "role-id"
    secret_id_file = approle_dir / "secret-id"

    if not role_id_file.exists() or not secret_id_file.exists():
        return None

    try:
        role_id = role_id_file.read_text().strip()
        secret_id = secret_id_file.read_text().strip()

        returncode, token, _ = run_command(
            [
                "docker", "exec",
                "-e", "VAULT_ADDR=http://localhost:8200",
                "dev-vault", "vault", "write", "-field=token",
                "auth/approle/login",
                f"role_id={role_id}",
                f"secret_id={secret_id}"
            ],
            capture=True,
            check=False
        )

        if returncode == 0 and token:
            return token.strip()
        return None

    except Exception as e:
        console.print(f"[yellow]Warning: AppRole authentication failed: {e}[/yellow]")
        return None


def get_vault_secret(
    path: str,
    field: str,
    use_approle: bool = True
) -> Optional[str]:
    """
    Retrieve a secret from Vault KV store.

    Args:
        path: Vault secret path (e.g., "secret/postgres")
        field: Field to retrieve (e.g., "password")
        use_approle: Use AppRole auth if True, otherwise use root token

    Returns:
        Secret value string, or None if retrieval fails

    Notes:
        - By default, uses AppRole authentication (recommended)
        - Falls back to root token if AppRole fails
        - For KV v2, path should NOT include "data/" prefix
    """
    # Try AppRole first if requested
    if use_approle:
        token = get_vault_approle_token()
        if token:
            returncode, value, _ = run_command(
                [
                    "docker", "exec",
                    "-e", f"VAULT_TOKEN={token}",
                    "-e", "VAULT_ADDR=http://localhost:8200",
                    "dev-vault", "vault", "kv", "get", f"-field={field}", path
                ],
                capture=True,
                check=False
            )
            if returncode == 0 and value:
                return value.strip()

    # Fallback to root token
    token = get_vault_token()
    if not token:
        return None

    returncode, value, _ = run_command(
        [
            "docker", "exec",
            "-e", f"VAULT_TOKEN={token}",
            "-e", "VAULT_ADDR=http://localhost:8200",
            "dev-vault", "vault", "kv", "get", f"-field={field}", path
        ],
        capture=True,
        check=False
    )

    if returncode == 0 and value:
        return value.strip()
    return None


def check_vault_health() -> bool:
    """
    Check if Vault server is healthy and unsealed.

    Returns:
        True if Vault is healthy and unsealed, False otherwise
    """
    returncode, stdout, _ = run_command(
        [
            "docker", "exec",
            "-e", "VAULT_ADDR=http://localhost:8200",
            "dev-vault", "vault", "status", "-format=json"
        ],
        capture=True,
        check=False
    )

    if returncode not in [0, 2]:  # 0 = unsealed, 2 = sealed
        return False

    try:
        import json
        status = json.loads(stdout)
        return not status.get("sealed", True)
    except (json.JSONDecodeError, KeyError):
        return False


def get_vault_unseal_keys() -> Optional[list]:
    """
    Get Vault unseal keys from config file.

    Returns:
        List of unseal keys, or None if not found
    """
    keys_file = VAULT_CONFIG_DIR / "keys.json"
    if not keys_file.exists():
        return None

    try:
        import json
        with open(keys_file) as f:
            data = json.load(f)
            return data.get("unseal_keys_b64") or data.get("keys")
    except (json.JSONDecodeError, KeyError):
        return None
