"""
Response caching middleware and utilities

Implements caching for GET endpoints using fastapi-cache2 with Redis backend.
Provides cache invalidation utilities for write operations.

Features:
- Automatic caching of GET endpoints
- Custom cache key generation
- TTL configuration per endpoint
- Cache invalidation patterns
- Prometheus metrics for cache hits/misses
"""

import hashlib
from typing import Optional
from fastapi import Request, Response
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from redis import asyncio as aioredis
import logging
from prometheus_client import Counter

logger = logging.getLogger(__name__)

# Prometheus metrics for cache
cache_hits = Counter(
    'cache_hits_total',
    'Total cache hits',
    ['endpoint']
)

cache_misses = Counter(
    'cache_misses_total',
    'Total cache misses',
    ['endpoint']
)

cache_invalidations = Counter(
    'cache_invalidations_total',
    'Total cache invalidations',
    ['pattern']
)


def generate_cache_key(
    func,
    namespace: str = "",
    request: Request = None,
    response: Response = None,
    *args,
    **kwargs,
) -> str:
    """
    Generate cache key for requests.

    Includes:
    - Function name
    - Path parameters
    - Query parameters
    - Request headers (optional, for user-specific caching)

    Args:
        func: The endpoint function
        namespace: Cache namespace prefix
        request: FastAPI request object
        response: FastAPI response object
        *args: Positional arguments
        **kwargs: Keyword arguments

    Returns:
        Cache key string
    """
    prefix = f"{namespace}:" if namespace else ""

    # Build key from function and path
    func_name = f"{func.__module__}:{func.__name__}"

    # Add path parameters
    path_params = ""
    if request:
        path_params = ":".join(str(v) for v in request.path_params.values())

    # Add query parameters (sorted for consistency)
    query_params = ""
    if request and request.query_params:
        sorted_params = sorted(request.query_params.items())
        query_params = ":".join(f"{k}={v}" for k, v in sorted_params)

    # Combine all parts
    key_parts = [prefix, func_name, path_params, query_params]
    key = ":".join(filter(None, key_parts))

    # Hash if too long (Redis keys should be kept under 250 chars for performance)
    if len(key) > 200:
        key_hash = hashlib.md5(key.encode()).hexdigest()
        # Return just the prefix and hash to keep it short
        return f"{prefix}hash:{key_hash}"

    return key


async def invalidate_cache_pattern(pattern: str, redis_client: aioredis.Redis):
    """
    Invalidate cache keys matching a pattern.

    Args:
        pattern: Redis key pattern (supports wildcards *)
        redis_client: Redis client instance

    Example:
        await invalidate_cache_pattern("cache:examples:*", redis_client)
    """
    try:
        # Find all keys matching pattern
        keys = []
        async for key in redis_client.scan_iter(match=pattern):
            keys.append(key)

        if keys:
            # Delete all matching keys
            await redis_client.delete(*keys)
            cache_invalidations.labels(pattern=pattern).inc(len(keys))
            logger.info(f"Invalidated {len(keys)} cache keys matching pattern: {pattern}")
        else:
            logger.debug(f"No cache keys found matching pattern: {pattern}")

    except Exception as e:
        logger.error(f"Failed to invalidate cache pattern {pattern}: {e}")


async def invalidate_cache_key(key: str, redis_client: aioredis.Redis):
    """
    Invalidate a specific cache key.

    Args:
        key: Exact cache key to invalidate
        redis_client: Redis client instance
    """
    try:
        deleted = await redis_client.delete(key)
        if deleted:
            cache_invalidations.labels(pattern=key).inc()
            logger.info(f"Invalidated cache key: {key}")
        else:
            logger.debug(f"Cache key not found: {key}")
    except Exception as e:
        logger.error(f"Failed to invalidate cache key {key}: {e}")


class CacheManager:
    """
    Manages cache initialization and operations.
    """

    def __init__(self):
        self.redis_client: Optional[aioredis.Redis] = None
        self.enabled = False

    async def init(self, redis_url: str, prefix: str = "cache:"):
        """
        Initialize cache with Redis backend.

        Args:
            redis_url: Redis connection URL
            prefix: Cache key prefix
        """
        try:
            self.redis_client = aioredis.from_url(
                redis_url,
                encoding="utf8",
                decode_responses=True
            )

            # Test connection
            await self.redis_client.ping()

            # Initialize FastAPI Cache
            FastAPICache.init(
                RedisBackend(self.redis_client),
                prefix=prefix
            )

            self.enabled = True
            # Log success without exposing credentials (URL may contain password)
            logger.info("Cache initialized with Redis successfully")

        except Exception as e:
            logger.error(f"Failed to initialize cache: {e}")
            logger.warning("Application will continue without caching")
            self.enabled = False

    async def clear_all(self):
        """Clear all cache entries."""
        if self.redis_client and self.enabled:
            try:
                await invalidate_cache_pattern("cache:*", self.redis_client)
                logger.info("Cleared all cache entries")
            except Exception as e:
                logger.error(f"Failed to clear cache: {e}")

    async def close(self):
        """Close Redis connection."""
        if self.redis_client:
            try:
                await self.redis_client.close()
                logger.info("Cache connection closed")
            except Exception as e:
                logger.error(f"Error closing cache connection: {e}")


# Global cache manager instance
cache_manager = CacheManager()
