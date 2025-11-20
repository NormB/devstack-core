"""
Vault integration examples

Demonstrates how to:
- Fetch secrets from Vault
- Use credentials for other services
- Handle Vault errors
- Response caching for performance
"""

from fastapi import APIRouter, Path
from fastapi_cache.decorator import cache
from app.services.vault import vault_client
from app.models.responses import SecretResponse, SecretKeyResponse
from app.middleware.cache import generate_cache_key

router = APIRouter()


@router.get("/secret/{service_name}", response_model=SecretResponse)
@cache(expire=300, key_builder=generate_cache_key)  # Cache for 5 minutes
async def get_secret_example(
    service_name: str = Path(
        ...,
        min_length=1,
        max_length=50,
        pattern=r'^[a-zA-Z0-9_-]+$',
        description="Service name (alphanumeric, hyphens, underscores only)"
    )
) -> SecretResponse:
    """
    Example: Fetch a secret from Vault

    This shows how to retrieve credentials for any service stored in Vault.
    Response is cached for 5 minutes to reduce Vault API calls.

    Raises:
        VaultUnavailableError: If Vault is unreachable or returns an error
        ResourceNotFoundError: If the secret doesn't exist
    """
    # Let exceptions bubble up to global handlers
    secret = await vault_client.get_secret(service_name.lower())

    # Don't return passwords in real applications!
    # This is just a demonstration
    safe_secret = {
        k: "***" if "password" in k.lower() else v
        for k, v in secret.items()
    }

    return SecretResponse(
        service=service_name,
        data=safe_secret,
        note="Passwords are masked. In real apps, use credentials internally, never return them."
    )


@router.get("/secret/{service_name}/{key}", response_model=SecretKeyResponse)
@cache(expire=300, key_builder=generate_cache_key)  # Cache for 5 minutes
async def get_secret_key_example(
    service_name: str = Path(
        ...,
        min_length=1,
        max_length=50,
        pattern=r'^[a-zA-Z0-9_-]+$',
        description="Service name (alphanumeric, hyphens, underscores only)"
    ),
    key: str = Path(
        ...,
        min_length=1,
        max_length=100,
        pattern=r'^[a-zA-Z0-9_-]+$',
        description="Secret key name (alphanumeric, hyphens, underscores only)"
    )
) -> SecretKeyResponse:
    """
    Example: Fetch a specific key from a secret

    Useful when you only need one field (like just the password).
    Response is cached for 5 minutes to reduce Vault API calls.

    Raises:
        VaultUnavailableError: If Vault is unreachable or returns an error
        ResourceNotFoundError: If the secret or key doesn't exist
    """
    # Let exceptions bubble up to global handlers
    secret = await vault_client.get_secret(service_name.lower(), key=key.lower())

    # Mask sensitive data
    value = secret.get(key.lower())
    if value and ("password" in key.lower() or "token" in key.lower()):
        value = "***"

    return SecretKeyResponse(
        service=service_name,
        key=key,
        value=value,
        note="Sensitive values are masked"
    )
