"""
Direct unit tests for cache_demo router functions

Tests cache demo endpoints with proper mocking.
"""

import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from fastapi import HTTPException

from app.routers.cache_demo import get_cache_value, set_cache_value, delete_cache_value


@pytest.mark.unit
@pytest.mark.asyncio
class TestCacheDemoGetValue:
    """Test get_cache_value endpoint"""

    async def test_get_existing_value(self):
        """Test getting an existing cache value"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.get.return_value = "cached_value"
            mock_client.ttl.return_value = 300
            mock_client.close = AsyncMock()
            mock_get_client.return_value = mock_client

            result = await get_cache_value(key="test:key")

            assert result.key == "test:key"
            assert result.value == "cached_value"
            assert result.exists is True
            assert result.ttl == 300
            mock_client.close.assert_called_once()

    async def test_get_nonexistent_value(self):
        """Test getting a non-existent cache value"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.get.return_value = None
            mock_client.ttl.return_value = -2
            mock_client.close = AsyncMock()
            mock_get_client.return_value = mock_client

            result = await get_cache_value(key="missing:key")

            assert result.key == "missing:key"
            assert result.value is None
            assert result.exists is False
            assert result.ttl is None

    async def test_get_value_with_no_expiration(self):
        """Test getting a value with no TTL"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.get.return_value = "persistent_value"
            mock_client.ttl.return_value = -1  # No expiration
            mock_client.close = AsyncMock()
            mock_get_client.return_value = mock_client

            result = await get_cache_value(key="persistent:key")

            assert result.value == "persistent_value"
            assert result.ttl == "no expiration"

    async def test_get_value_redis_error(self):
        """Test getting value when Redis fails"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.get.side_effect = Exception("Redis connection failed")
            mock_get_client.return_value = mock_client

            with pytest.raises(HTTPException) as exc_info:
                await get_cache_value(key="test:key")

            assert exc_info.value.status_code == 500
            assert "Cache get failed" in exc_info.value.detail


@pytest.mark.unit
@pytest.mark.asyncio
class TestCacheDemoSetValue:
    """Test set_cache_value endpoint"""

    async def test_set_value_without_ttl(self):
        """Test setting a cache value without TTL"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.set = AsyncMock()
            mock_client.close = AsyncMock()
            mock_get_client.return_value = mock_client

            result = await set_cache_value(key="test:key", value="test_value", ttl=None)

            assert result.key == "test:key"
            assert result.value == "test_value"
            assert result.ttl is None
            assert result.action == "set"
            mock_client.set.assert_called_once_with("test:key", "test_value")
            mock_client.close.assert_called_once()

    async def test_set_value_with_ttl(self):
        """Test setting a cache value with TTL"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.setex = AsyncMock()
            mock_client.close = AsyncMock()
            mock_get_client.return_value = mock_client

            result = await set_cache_value(key="temp:key", value="temp_value", ttl=60)

            assert result.key == "temp:key"
            assert result.value == "temp_value"
            assert result.ttl == 60
            assert result.action == "set"
            mock_client.setex.assert_called_once_with("temp:key", 60, "temp_value")
            mock_client.close.assert_called_once()

    async def test_set_value_redis_error(self):
        """Test setting value when Redis fails"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.set.side_effect = Exception("Redis write failed")
            mock_get_client.return_value = mock_client

            with pytest.raises(HTTPException) as exc_info:
                await set_cache_value(key="test:key", value="value", ttl=None)

            assert exc_info.value.status_code == 500
            assert "Cache set failed" in exc_info.value.detail


@pytest.mark.unit
@pytest.mark.asyncio
class TestCacheDemoDeleteValue:
    """Test delete_cache_value endpoint"""

    async def test_delete_existing_key(self):
        """Test deleting an existing cache key"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.delete.return_value = 1  # 1 key deleted
            mock_client.close = AsyncMock()
            mock_get_client.return_value = mock_client

            result = await delete_cache_value(key="test:key")

            assert result.key == "test:key"
            assert result.deleted is True
            assert result.action == "delete"
            mock_client.delete.assert_called_once_with("test:key")
            mock_client.close.assert_called_once()

    async def test_delete_nonexistent_key(self):
        """Test deleting a non-existent cache key"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.delete.return_value = 0  # No keys deleted
            mock_client.close = AsyncMock()
            mock_get_client.return_value = mock_client

            result = await delete_cache_value(key="missing:key")

            assert result.key == "missing:key"
            assert result.deleted is False
            assert result.action == "delete"

    async def test_delete_value_redis_error(self):
        """Test deleting value when Redis fails"""
        with patch('app.routers.cache_demo.get_redis_client') as mock_get_client:
            mock_client = AsyncMock()
            mock_client.delete.side_effect = Exception("Redis delete failed")
            mock_get_client.return_value = mock_client

            with pytest.raises(HTTPException) as exc_info:
                await delete_cache_value(key="test:key")

            assert exc_info.value.status_code == 500
            assert "Cache delete failed" in exc_info.value.detail


@pytest.mark.unit
@pytest.mark.asyncio
class TestGetRedisClient:
    """Test get_redis_client helper function"""

    async def test_get_redis_client_success(self):
        """Test getting Redis client with Vault credentials"""
        from app.routers.cache_demo import get_redis_client

        with patch('app.routers.cache_demo.vault_client.get_secret') as mock_vault:
            with patch('app.routers.cache_demo.redis.Redis') as mock_redis_class:
                mock_vault.return_value = {"password": "test_password"}

                mock_client = MagicMock()
                mock_redis_class.return_value = mock_client

                result = await get_redis_client()

                assert result == mock_client
                mock_vault.assert_called_once_with("redis-1")
                mock_redis_class.assert_called_once()
