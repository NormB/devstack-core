"""
Direct unit tests for router functions without TestClient

Tests router endpoint logic directly by calling async functions with mocked dependencies.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from fastapi import HTTPException


@pytest.mark.skip(reason="Tests outdated cache functions that no longer exist - see test_cache_demo_unit.py for current tests")
@pytest.mark.unit
@pytest.mark.asyncio
class TestCacheDemoRouters:
    """Test cache demo router functions directly"""

    async def test_get_cached_data_success(self):
        """Test get_cached_data with cache miss"""
        from app.routers.cache_demo import get_cached_data

        with patch('app.routers.cache_demo.cache_manager') as mock_cache:
            mock_cache.enabled = False  # Simulate cache not enabled

            result = await get_cached_data()

            assert result["cached"] is False
            assert "timestamp" in result
            assert "data" in result

    async def test_invalidate_cache_success(self):
        """Test cache invalidation"""
        from app.routers.cache_demo import invalidate_cache_endpoint

        with patch('app.routers.cache_demo.cache_manager') as mock_cache:
            mock_cache.enabled = True
            mock_cache.redis_client = AsyncMock()

            result = await invalidate_cache_endpoint(pattern="test:*")

            assert result["message"] == "Cache invalidation requested"
            assert result["pattern"] == "test:*"

    async def test_clear_all_cache_success(self):
        """Test clearing all cache"""
        from app.routers.cache_demo import clear_all_cache

        with patch('app.routers.cache_demo.cache_manager') as mock_cache:
            mock_cache.enabled = True
            mock_cache.clear_all = AsyncMock()

            result = await clear_all_cache()

            assert result["message"] == "All cache cleared"
            mock_cache.clear_all.assert_called_once()

    async def test_clear_all_cache_disabled(self):
        """Test clearing cache when disabled"""
        from app.routers.cache_demo import clear_all_cache

        with patch('app.routers.cache_demo.cache_manager') as mock_cache:
            mock_cache.enabled = False

            with pytest.raises(HTTPException) as exc_info:
                await clear_all_cache()

            assert exc_info.value.status_code == 503


@pytest.mark.unit
@pytest.mark.asyncio
class TestDatabaseDemoRouters:
    """Test database demo router functions directly"""

    async def test_postgres_query_success(self):
        """Test PostgreSQL query"""
        from app.routers.database_demo import postgres_example

        with patch('app.routers.database_demo.vault_client.get_secret') as mock_vault:
            with patch('app.routers.database_demo.asyncpg.connect') as mock_connect:
                mock_vault.return_value = {
                    "user": "test", 
                    "password": "test",
                    "database": "test"
                }

                mock_conn = AsyncMock()
                mock_conn.fetchval.return_value = "2024-01-01 00:00:00"
                mock_conn.close = AsyncMock()
                mock_connect.return_value = mock_conn

                result = await postgres_example()

                assert result["database"] == "PostgreSQL"
                assert "result" in result

    async def test_postgres_query_failure(self):
        """Test PostgreSQL query failure"""
        from app.routers.database_demo import postgres_example

        with patch('app.routers.database_demo.vault_client.get_secret') as mock_vault:
            with patch('app.routers.database_demo.asyncpg.connect') as mock_connect:
                mock_vault.return_value = {"user": "test", "password": "test", "database": "test"}
                mock_connect.side_effect = Exception("Connection failed")

                with pytest.raises(HTTPException) as exc_info:
                    await postgres_example()

                assert exc_info.value.status_code == 500

    @pytest.mark.skip(reason="Needs better async mocking for aiomysql")
    async def test_mysql_query_success(self):
        """Test MySQL query"""
        from app.routers.database_demo import mysql_example

        with patch('app.routers.database_demo.vault_client.get_secret') as mock_vault:
            with patch('app.routers.database_demo.aiomysql.connect') as mock_connect:
                mock_vault.return_value = {
                    "user": "test",
                    "password": "test",
                    "database": "test"
                }

                mock_cursor = AsyncMock()
                mock_cursor.execute = AsyncMock()
                mock_cursor.fetchone.return_value = ("2024-01-01 00:00:00",)
                mock_cursor.__aenter__ = AsyncMock(return_value=mock_cursor)
                mock_cursor.__aexit__ = AsyncMock()

                mock_conn = MagicMock()
                mock_conn.cursor.return_value = mock_cursor
                mock_conn.close = MagicMock()
                mock_connect.return_value = mock_conn

                result = await mysql_example()

                assert result["database"] == "MySQL"
                assert "result" in result

    async def test_mongodb_query_success(self):
        """Test MongoDB query"""
        from app.routers.database_demo import mongodb_example

        with patch('app.routers.database_demo.vault_client.get_secret') as mock_vault:
            with patch('app.routers.database_demo.motor.motor_asyncio.AsyncIOMotorClient') as mock_client_class:
                mock_vault.return_value = {
                    "user": "test",
                    "password": "test",
                    "database": "test_db"
                }

                mock_db = AsyncMock()
                mock_db.list_collection_names.return_value = ["users", "products"]

                mock_client = MagicMock()
                mock_client.__getitem__.return_value = mock_db
                mock_client.close = MagicMock()
                mock_client_class.return_value = mock_client

                result = await mongodb_example()

                assert result["database"] == "MongoDB"
                assert result["count"] == 2
                assert len(result["collections"]) == 2


@pytest.mark.unit
@pytest.mark.asyncio
class TestMessagingDemoRouters:
    """Test messaging demo router functions directly"""

    @pytest.mark.skip(reason="Needs better async mocking for aio_pika")
    async def test_publish_message_success(self):
        """Test publishing message to RabbitMQ"""
        from app.routers.messaging_demo import publish_message

        with patch('app.routers.messaging_demo.vault_client.get_secret') as mock_vault:
            with patch('app.routers.messaging_demo.aio_pika.connect_robust') as mock_connect:
                mock_vault.return_value = {
                    "user": "test",
                    "password": "test"
                }

                mock_exchange = AsyncMock()
                mock_exchange.publish = AsyncMock()

                mock_channel = AsyncMock()
                mock_channel.declare_exchange = AsyncMock(return_value=mock_exchange)
                mock_channel.close = AsyncMock()

                mock_connection = AsyncMock()
                mock_connection.channel.return_value = mock_channel
                mock_connection.close = AsyncMock()
                mock_connect.return_value = mock_connection

                result = await publish_message(
                    message="test message",
                    routing_key="test.key"
                )

                assert result["status"] == "published"
                assert result["message"] == "test message"

    async def test_publish_message_failure(self):
        """Test publish message failure"""
        from app.routers.messaging_demo import publish_message

        with patch('app.routers.messaging_demo.vault_client.get_secret') as mock_vault:
            with patch('app.routers.messaging_demo.aio_pika.connect_robust') as mock_connect:
                mock_vault.return_value = {"user": "test", "password": "test"}
                mock_connect.side_effect = Exception("Connection failed")

                with pytest.raises(HTTPException) as exc_info:
                    await publish_message("test", "test.key")

                assert exc_info.value.status_code == 500

    @pytest.mark.skip(reason="Needs better async mocking for message consumption")
    async def test_consume_messages_success(self):
        """Test consuming messages from RabbitMQ"""
        from app.routers.messaging_demo import consume_messages

        with patch('app.routers.messaging_demo.vault_client.get_secret') as mock_vault:
            with patch('app.routers.messaging_demo.aio_pika.connect_robust') as mock_connect:
                mock_vault.return_value = {"user": "test", "password": "test"}

                # Mock message
                mock_message = MagicMock()
                mock_message.body = b'{"test": "message"}'

                # Create async generator for queue
                async def mock_iterator():
                    yield mock_message

                mock_queue = AsyncMock()
                mock_queue.__aiter__ = lambda self: mock_iterator()

                mock_channel = AsyncMock()
                mock_channel.declare_queue = AsyncMock(return_value=mock_queue)
                mock_channel.close = AsyncMock()

                mock_connection = AsyncMock()
                mock_connection.channel.return_value = mock_channel
                mock_connection.close = AsyncMock()
                mock_connect.return_value = mock_connection

                result = await consume_messages(count=1)

                assert result["status"] == "consumed"
                assert result["count"] == 1
                assert len(result["messages"]) == 1


@pytest.mark.unit
@pytest.mark.asyncio
class TestRedisClusterRouters:
    """Test Redis cluster router functions directly"""

    async def test_get_cluster_nodes_success(self):
        """Test getting cluster nodes"""
        from app.routers.redis_cluster import get_cluster_nodes

        with patch('app.routers.redis_cluster.vault_client.get_secret') as mock_vault:
            with patch('app.routers.redis_cluster.redis.Redis') as mock_redis_class:
                mock_vault.return_value = {"password": "test"}

                mock_client = AsyncMock()
                mock_client.execute_command.return_value = "node1 127.0.0.1:6379@16379 master - 0 1234567890 1 connected 0-5460"
                mock_client.close = AsyncMock()
                mock_redis_class.return_value = mock_client

                result = await get_cluster_nodes()

                assert result["status"] == "success"
                assert "nodes" in result

    async def test_get_cluster_nodes_failure(self):
        """Test cluster nodes failure"""
        from app.routers.redis_cluster import get_cluster_nodes

        with patch('app.routers.redis_cluster.vault_client.get_secret') as mock_vault:
            mock_vault.side_effect = Exception("Vault failed")

            result = await get_cluster_nodes()

            assert result["status"] == "error"

    async def test_get_cluster_info_success(self):
        """Test getting cluster info"""
        from app.routers.redis_cluster import get_cluster_info

        with patch('app.routers.redis_cluster.vault_client.get_secret') as mock_vault:
            with patch('app.routers.redis_cluster.redis.Redis') as mock_redis_class:
                mock_vault.return_value = {"password": "test"}

                mock_client = AsyncMock()
                mock_client.execute_command.return_value = "cluster_state:ok\ncluster_slots_assigned:16384"
                mock_client.close = AsyncMock()
                mock_redis_class.return_value = mock_client

                result = await get_cluster_info()

                assert result["status"] == "success"
                assert "cluster_info" in result

    async def test_get_node_info_invalid_node(self):
        """Test getting node info with invalid node name"""
        from app.routers.redis_cluster import get_node_info

        result = await get_node_info("invalid-node")

        assert result["status"] == "error"
        assert "Invalid node name" in result["error"]


@pytest.mark.skip(reason="Cannot test route handlers directly due to cache decorators - need TestClient")
@pytest.mark.unit
@pytest.mark.asyncio
class TestVaultDemoRouters:
    """Test Vault demo router functions directly"""

    async def test_get_vault_secret_success(self):
        """Test getting Vault secret"""
        from app.routers.vault_demo import get_secret_example as get_secret

        with patch('app.routers.vault_demo.vault_client.get_secret') as mock_get:
            mock_get.return_value = {
                "user": "test_user",
                "password": "test_password",
                "database": "test_db"
            }

            result = await get_secret(secret_name="postgres")

            assert result["secret_name"] == "postgres"
            assert "user" in result["data"]
            assert result["data"]["user"] == "test_user"

    async def test_get_vault_secret_with_key(self):
        """Test getting specific key from Vault secret"""
        from app.routers.vault_demo import get_secret_example as get_secret

        with patch('app.routers.vault_demo.vault_client.get_secret') as mock_get:
            mock_get.return_value = {"password": "secret123"}

            result = await get_secret(secret_name="postgres", key="password")

            assert result["secret_name"] == "postgres"
            assert result["key"] == "password"
            assert result["data"]["password"] == "secret123"


@pytest.mark.skip(reason="Cannot test async route handler directly - need TestClient")
@pytest.mark.unit
class TestMainEndpoints:
    """Test main.py root endpoint"""

    def test_root_endpoint_structure(self):
        """Test root endpoint returns correct structure"""
        from app.main import root as read_root

        result = read_root()

        assert result["service"] == "DevStack Core Reference API"
        assert result["version"] == "1.1.0"
        assert "endpoints" in result
        assert "note" in result
