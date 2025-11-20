"""
Redis cache integration examples

Demonstrates:
- Basic key-value operations
- TTL (Time To Live) management
- Redis cluster usage
"""

from fastapi import APIRouter, HTTPException, Path, Query
import redis.asyncio as redis

from app.config import settings
from app.services.vault import vault_client
from app.models.responses import (
    CacheGetResponse,
    CacheSetResponse,
    CacheDeleteResponse
)

router = APIRouter()


async def get_redis_client():
    """Get configured Redis client"""
    creds = await vault_client.get_secret("redis-1")
    return redis.Redis(
        host=settings.REDIS_HOST,
        port=settings.REDIS_PORT,
        password=creds.get("password"),
        decode_responses=True,
        socket_connect_timeout=5
    )


@router.get("/{key}", response_model=CacheGetResponse)
async def get_cache_value(
    key: str = Path(
        ...,
        min_length=1,
        max_length=200,
        pattern=r'^[a-zA-Z0-9_:.-]+$',
        description="Cache key (alphanumeric and: - _ : . only)"
    )
) -> CacheGetResponse:
    """Example: Get a value from cache"""
    try:
        client = await get_redis_client()
        value = await client.get(key)
        ttl = await client.ttl(key)
        await client.close()

        if value is None:
            return CacheGetResponse(key=key, value=None, exists=False, ttl=None)

        return CacheGetResponse(
            key=key,
            value=value,
            exists=True,
            ttl=ttl if ttl > 0 else "no expiration"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Cache get failed: {str(e)}")


@router.post("/{key}", response_model=CacheSetResponse)
async def set_cache_value(
    key: str = Path(
        ...,
        min_length=1,
        max_length=200,
        pattern=r'^[a-zA-Z0-9_:.-]+$',
        description="Cache key (alphanumeric and: - _ : . only)"
    ),
    value: str = Query(
        ...,
        min_length=0,
        max_length=10000,
        description="Value to cache (max 10KB)"
    ),
    ttl: int = Query(
        None,
        ge=1,
        le=86400,
        description="Time to live in seconds (1s to 24h)"
    )
) -> CacheSetResponse:
    """Example: Set a value in cache with optional TTL"""
    try:
        client = await get_redis_client()

        if ttl:
            await client.setex(key, ttl, value)
        else:
            await client.set(key, value)

        await client.close()

        return CacheSetResponse(
            key=key,
            value=value,
            ttl=ttl,
            action="set"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Cache set failed: {str(e)}")


@router.delete("/{key}", response_model=CacheDeleteResponse)
async def delete_cache_value(
    key: str = Path(
        ...,
        min_length=1,
        max_length=200,
        pattern=r'^[a-zA-Z0-9_:.-]+$',
        description="Cache key (alphanumeric and: - _ : . only)"
    )
) -> CacheDeleteResponse:
    """Example: Delete a value from cache"""
    try:
        client = await get_redis_client()
        deleted = await client.delete(key)
        await client.close()

        return CacheDeleteResponse(
            key=key,
            deleted=bool(deleted),
            action="delete"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Cache delete failed: {str(e)}")
