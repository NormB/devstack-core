"""
Vault client service for fetching secrets

Demonstrates how to integrate with HashiCorp Vault to fetch credentials
for other infrastructure services.

Supports both AppRole authentication (recommended for production) and
token-based authentication (fallback for development).
"""

import httpx
import logging
import os
import re
from typing import Optional, Dict, Any
from urllib.parse import urljoin

from app.config import settings
from app.exceptions import VaultUnavailableError, ResourceNotFoundError

logger = logging.getLogger(__name__)


class VaultClient:
    """
    Client for interacting with HashiCorp Vault

    Authentication methods (in priority order):
    1. AppRole (recommended): Uses role_id and secret_id from filesystem
    2. Token-based (fallback): Uses VAULT_TOKEN environment variable
    """

    def __init__(self):
        self.vault_addr = settings.VAULT_ADDR
        self.vault_token = None

        # Try AppRole authentication first (recommended for production)
        if settings.VAULT_APPROLE_DIR and os.path.exists(settings.VAULT_APPROLE_DIR):
            try:
                self.vault_token = self._login_with_approle()
                logger.info("Successfully authenticated to Vault using AppRole")
            except Exception as e:
                # Fall back to token-based auth if AppRole fails
                logger.warning(f"AppRole authentication failed: {e}, falling back to token-based auth")
                self.vault_token = settings.VAULT_TOKEN
        else:
            # Use token-based authentication
            logger.info("Using token-based authentication (AppRole directory not found)")
            self.vault_token = settings.VAULT_TOKEN

        self.headers = {"X-Vault-Token": self.vault_token}

    def _login_with_approle(self) -> str:
        """
        Authenticate to Vault using AppRole method

        Reads role_id and secret_id from filesystem and exchanges them
        for a Vault client token.

        Returns:
            Vault client token

        Raises:
            VaultUnavailableError: If AppRole login fails
        """
        role_id_path = os.path.join(settings.VAULT_APPROLE_DIR, "role-id")
        secret_id_path = os.path.join(settings.VAULT_APPROLE_DIR, "secret-id")

        # Read role_id and secret_id from filesystem
        try:
            with open(role_id_path, 'r') as f:
                role_id = f.read().strip()
            with open(secret_id_path, 'r') as f:
                secret_id = f.read().strip()
        except FileNotFoundError as e:
            raise VaultUnavailableError(
                message=f"AppRole credentials not found: {e}",
                secret_path="approle",
                details={"role_id_path": role_id_path, "secret_id_path": secret_id_path}
            )
        except Exception as e:
            raise VaultUnavailableError(
                message=f"Error reading AppRole credentials: {e}",
                secret_path="approle",
                details={"error": str(e)}
            )

        # Authenticate with Vault
        url = urljoin(f"{self.vault_addr}/", "v1/auth/approle/login")
        payload = {
            "role_id": role_id,
            "secret_id": secret_id
        }

        try:
            with httpx.Client() as client:
                response = client.post(url, json=payload, timeout=5.0)
                response.raise_for_status()

                data = response.json()
                client_token = data.get("auth", {}).get("client_token")

                if not client_token:
                    raise VaultUnavailableError(
                        message="No client token in AppRole login response",
                        secret_path="approle",
                        details={"response": data}
                    )

                return client_token

        except httpx.HTTPError as e:
            logger.error(f"HTTP error during AppRole login: {e}")
            raise VaultUnavailableError(
                message=f"AppRole login failed: {e}",
                secret_path="approle",
                details={"error": str(e)}
            )
        except Exception as e:
            logger.error(f"Unexpected error during AppRole login: {e}")
            raise VaultUnavailableError(
                message=f"Unexpected error during AppRole login: {e}",
                secret_path="approle",
                details={"error": str(e)}
            )

    def _validate_secret_path(self, path: str) -> str:
        """
        Validate and sanitize the secret path to prevent SSRF attacks.

        Args:
            path: The secret path to validate

        Returns:
            Sanitized path

        Raises:
            ValueError: If path contains invalid characters
        """
        # Remove leading/trailing slashes
        path = path.strip("/")

        # Only allow alphanumeric, hyphens, underscores, and forward slashes
        if not re.match(r'^[a-zA-Z0-9/_-]+$', path):
            raise ValueError(f"Invalid secret path: {path}. Only alphanumeric characters, hyphens, underscores, and forward slashes are allowed.")

        # Prevent path traversal
        if ".." in path:
            raise ValueError(f"Invalid secret path: {path}. Path traversal sequences are not allowed.")

        return path

    async def get_secret(self, path: str, key: Optional[str] = None) -> Dict[str, Any]:
        """
        Fetch a secret from Vault KV v2 secrets engine

        Args:
            path: Secret path (e.g., 'postgres', 'mysql')
            key: Optional specific key to extract

        Returns:
            Secret data or specific key value

        Raises:
            VaultUnavailableError: If Vault is unreachable or returns an error
            ResourceNotFoundError: If the secret doesn't exist
            ValueError: If path contains invalid characters
        """
        # Validate path to prevent SSRF
        validated_path = self._validate_secret_path(path)

        # Construct URL safely
        url = urljoin(f"{self.vault_addr}/", f"v1/secret/data/{validated_path}")

        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(url, headers=self.headers, timeout=5.0)

                # Handle 404 specifically
                if response.status_code == 404:
                    raise ResourceNotFoundError(
                        resource_type="secret",
                        resource_id=path,
                        message=f"Secret '{path}' not found in Vault",
                        details={"secret_path": path, "key": key}
                    )

                # Handle 403 (permission denied)
                if response.status_code == 403:
                    raise VaultUnavailableError(
                        message="Permission denied accessing Vault secret",
                        secret_path=path,
                        details={"status_code": 403}
                    )

                response.raise_for_status()

                data = response.json()
                secret_data = data.get("data", {}).get("data", {})

                if key:
                    # Check if the specific key exists
                    if key not in secret_data:
                        raise ResourceNotFoundError(
                            resource_type="secret_key",
                            resource_id=f"{path}/{key}",
                            message=f"Key '{key}' not found in secret '{path}'",
                            details={"secret_path": path, "key": key}
                        )
                    return {key: secret_data.get(key)}

                return secret_data

        except (ResourceNotFoundError, VaultUnavailableError):
            # Re-raise our custom exceptions
            raise
        except httpx.TimeoutException as e:
            logger.error(f"Timeout fetching secret from Vault: {e}")
            raise VaultUnavailableError(
                message="Timeout connecting to Vault",
                secret_path=path,
                details={"error": str(e), "timeout": "5.0s"}
            )
        except httpx.ConnectError as e:
            logger.error(f"Connection error to Vault: {e}")
            raise VaultUnavailableError(
                message="Cannot connect to Vault server",
                secret_path=path,
                details={"error": str(e), "vault_address": self.vault_addr}
            )
        except httpx.HTTPError as e:
            logger.error(f"HTTP error fetching secret from Vault: {e}")
            raise VaultUnavailableError(
                message=f"Vault returned an error: {e}",
                secret_path=path,
                details={"error": str(e)}
            )
        except Exception as e:
            logger.error(f"Unexpected error fetching secret: {e}")
            raise VaultUnavailableError(
                message=f"Unexpected error accessing Vault: {e}",
                secret_path=path,
                details={"error": str(e)}
            )

    async def check_health(self) -> Dict[str, Any]:
        """Check Vault health status"""
        url = f"{self.vault_addr}/v1/sys/health"

        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    f"{url}?standbyok=true",
                    timeout=5.0
                )

                return {
                    "status": "healthy" if response.status_code == 200 else "unhealthy",
                    "initialized": response.status_code != 501,
                    "sealed": response.status_code == 503,
                    "standby": response.status_code == 429,
                }
        except Exception as e:
            logger.error(f"Vault health check failed: {e}")
            return {
                "status": "unhealthy",
                "error": "Health check failed"
            }


# Global Vault client instance
vault_client = VaultClient()
