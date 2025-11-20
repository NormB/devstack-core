"""
Tests for health check routers

Tests health check endpoints with proper mocking of external services.
"""

import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, patch, MagicMock

from app.main import app


@pytest.mark.integration
class TestHealthEndpoints:
    """Test health check endpoints"""

    def client(self):
        """Create test client"""
        with patch('app.middleware.cache.FastAPICache.init'):
            with patch('app.middleware.cache.FastAPICache.get_coder', return_value=MagicMock()):
                with TestClient(app) as test_client:
                    yield test_client

    def test_simple_health_check(self, client):
        """Test simple health check endpoint"""
        response = client.get("/health/")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"

    def test_vault_health_check(self, client):
        """Test Vault health check"""
        with patch('app.routers.health.vault_client.check_health') as mock_check:
            mock_check.return_value = {
                "status": "healthy",
                "initialized": True,
                "sealed": False
            }

            response = client.get("/health/vault")

            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "healthy"

    @pytest.mark.skip(reason="Integration test requires real infrastructure or alternative testing approach (TestClient incompatible with complex middleware stack)")
    def test_all_health_checks_healthy(self, client):
        """Test all health checks when all services are healthy"""
        with patch('app.routers.health.check_vault') as mock_vault:
            with patch('app.routers.health.check_postgres') as mock_pg:
                with patch('app.routers.health.check_mysql') as mock_mysql:
                    with patch('app.routers.health.check_mongodb') as mock_mongo:
                        with patch('app.routers.health.check_redis') as mock_redis:
                            with patch('app.routers.health.check_rabbitmq') as mock_rmq:
                                # Mock all services as healthy
                                mock_vault.return_value = {"status": "healthy"}
                                mock_pg.return_value = {"status": "healthy"}
                                mock_mysql.return_value = {"status": "healthy"}
                                mock_mongo.return_value = {"status": "healthy"}
                                mock_redis.return_value = {"status": "healthy"}
                                mock_rmq.return_value = {"status": "healthy"}

                                response = client.get("/health/all")

                                assert response.status_code == 200
                                data = response.json()
                                assert data["status"] == "healthy"
                                assert "services" in data
                                assert all(
                                    svc["status"] == "healthy"
                                    for svc in data["services"].values()
                                )

    @pytest.mark.skip(reason="Integration test requires real infrastructure or alternative testing approach (TestClient incompatible with complex middleware stack)")
    def test_all_health_checks_degraded(self, client):
        """Test all health checks when some services are unhealthy"""
        with patch('app.routers.health.check_vault') as mock_vault:
            with patch('app.routers.health.check_postgres') as mock_pg:
                with patch('app.routers.health.check_mysql') as mock_mysql:
                    with patch('app.routers.health.check_mongodb') as mock_mongo:
                        with patch('app.routers.health.check_redis') as mock_redis:
                            with patch('app.routers.health.check_rabbitmq') as mock_rmq:
                                # Mock some services as unhealthy
                                mock_vault.return_value = {"status": "healthy"}
                                mock_pg.return_value = {"status": "unhealthy", "error": "Connection failed"}
                                mock_mysql.return_value = {"status": "healthy"}
                                mock_mongo.return_value = {"status": "healthy"}
                                mock_redis.return_value = {"status": "healthy"}
                                mock_rmq.return_value = {"status": "healthy"}

                                response = client.get("/health/all")

                                assert response.status_code == 200
                                data = response.json()
                                assert data["status"] == "degraded"
                                assert "services" in data


@pytest.mark.unit
@pytest.mark.asyncio
class TestHealthCheckFunctions:
    """Test individual health check functions"""

    async def test_check_vault_healthy(self):
        """Test vault health check when healthy"""
        from app.routers.health import check_vault

        with patch('app.routers.health.vault_client.check_health') as mock_check:
            mock_check.return_value = {
                "status": "healthy",
                "initialized": True,
                "sealed": False
            }

            result = await check_vault()

            assert result["status"] == "healthy"
            assert "details" in result

    async def test_check_vault_unhealthy(self):
        """Test vault health check when unhealthy"""
        from app.routers.health import check_vault

        with patch('app.routers.health.vault_client.check_health') as mock_check:
            mock_check.side_effect = Exception("Connection failed")

            result = await check_vault()

            assert result["status"] == "unhealthy"
            assert "error" in result

    async def test_check_postgres_healthy(self):
        """Test PostgreSQL health check when healthy"""
        from app.routers.health import check_postgres

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            with patch('app.routers.health.asyncpg.connect') as mock_connect:
                mock_secret.return_value = {
                    "user": "test_user",
                    "password": "test_pass",
                    "database": "test_db"
                }

                mock_conn = AsyncMock()
                mock_conn.fetchval.return_value = "PostgreSQL 16.0"
                mock_connect.return_value = mock_conn

                result = await check_postgres()

                assert result["status"] == "healthy"
                assert "version" in result

    async def test_check_postgres_unhealthy(self):
        """Test PostgreSQL health check when unhealthy"""
        from app.routers.health import check_postgres

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            with patch('app.routers.health.asyncpg.connect') as mock_connect:
                mock_secret.return_value = {"user": "test", "password": "test", "database": "test"}
                mock_connect.side_effect = Exception("Connection refused")

                result = await check_postgres()

                assert result["status"] == "unhealthy"
                assert "error" in result

    async def test_check_redis_cluster_healthy(self):
        """Test Redis cluster health check"""
        from app.routers.health import check_redis

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            with patch('app.routers.health.redis.Redis') as mock_redis_class:
                mock_secret.return_value = {"password": "test_pass"}

                mock_client = AsyncMock()
                mock_client.ping.return_value = True
                mock_client.info.return_value = {
                    "redis_version": "7.0.0",
                    "role": "master",
                    "cluster_enabled": 1,
                    "connected_clients": 5,
                    "used_memory_human": "1.5M"
                }
                mock_client.execute_command.return_value = "cluster_state:ok\ncluster_slots_assigned:16384"
                mock_redis_class.return_value = mock_client

                with patch('app.routers.health.settings.REDIS_NODES', "localhost:6379,localhost:6380,localhost:6381"):
                    result = await check_redis()

                    assert result["status"] in ["healthy", "degraded"]
                    assert "nodes" in result

    @pytest.mark.skip(reason="Needs better async mocking for aiomysql")
    async def test_check_mysql_healthy(self):
        """Test MySQL health check when healthy"""
        from app.routers.health import check_mysql

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            with patch('app.routers.health.aiomysql.connect') as mock_connect:
                mock_secret.return_value = {
                    "user": "test_user",
                    "password": "test_pass",
                    "database": "test_db"
                }

                mock_cursor = AsyncMock()
                mock_cursor.execute = AsyncMock()
                mock_cursor.fetchone.return_value = ("MySQL 8.0",)
                mock_cursor.__aenter__ = AsyncMock(return_value=mock_cursor)
                mock_cursor.__aexit__ = AsyncMock()

                mock_conn = MagicMock()
                mock_conn.cursor.return_value = mock_cursor
                mock_conn.close = MagicMock()
                mock_connect.return_value = mock_conn

                result = await check_mysql()

                assert result["status"] == "healthy"
                assert "version" in result

    async def test_check_mysql_unhealthy(self):
        """Test MySQL health check when unhealthy"""
        from app.routers.health import check_mysql

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            with patch('app.routers.health.aiomysql.connect') as mock_connect:
                mock_secret.return_value = {"user": "test", "password": "test", "database": "test"}
                mock_connect.side_effect = Exception("Connection refused")

                result = await check_mysql()

                assert result["status"] == "unhealthy"
                assert "error" in result

    @pytest.mark.skip(reason="Needs better async mocking for motor")
    async def test_check_mongodb_healthy(self):
        """Test MongoDB health check when healthy"""
        from app.routers.health import check_mongodb

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            with patch('app.routers.health.motor.motor_asyncio.AsyncIOMotorClient') as mock_client_class:
                mock_secret.return_value = {
                    "user": "test_user",
                    "password": "test_pass",
                    "database": "test_db"
                }

                mock_db = AsyncMock()
                mock_db.command.return_value = {"version": "6.0.0", "ok": 1}

                mock_client = MagicMock()
                mock_client.__getitem__.return_value = mock_db
                mock_client.close = MagicMock()
                mock_client_class.return_value = mock_client

                result = await check_mongodb()

                assert result["status"] == "healthy"
                assert "version" in result

    async def test_check_mongodb_unhealthy(self):
        """Test MongoDB health check when unhealthy"""
        from app.routers.health import check_mongodb

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            mock_secret.side_effect = Exception("Vault connection failed")

            result = await check_mongodb()

            assert result["status"] == "unhealthy"
            assert "error" in result

    async def test_check_rabbitmq_healthy(self):
        """Test RabbitMQ health check when healthy"""
        from app.routers.health import check_rabbitmq

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            with patch('app.routers.health.aio_pika.connect_robust') as mock_connect:
                mock_secret.return_value = {
                    "user": "test_user",
                    "password": "test_pass"
                }

                mock_channel = AsyncMock()
                mock_channel.close = AsyncMock()

                mock_connection = AsyncMock()
                mock_connection.channel.return_value = mock_channel
                mock_connection.close = AsyncMock()
                mock_connect.return_value = mock_connection

                result = await check_rabbitmq()

                assert result["status"] == "healthy"

    async def test_check_rabbitmq_unhealthy(self):
        """Test RabbitMQ health check when unhealthy"""
        from app.routers.health import check_rabbitmq

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            with patch('app.routers.health.aio_pika.connect_robust') as mock_connect:
                mock_secret.return_value = {"user": "test", "password": "test"}
                mock_connect.side_effect = Exception("Connection timeout")

                result = await check_rabbitmq()

                assert result["status"] == "unhealthy"
                assert "error" in result

    async def test_check_redis_unhealthy(self):
        """Test Redis health check when unhealthy"""
        from app.routers.health import check_redis

        with patch('app.routers.health.vault_client.get_secret') as mock_secret:
            mock_secret.side_effect = Exception("Vault connection failed")

            result = await check_redis()

            assert result["status"] == "unhealthy"
            assert "error" in result
