"""
Pytest configuration and fixtures for the FastAPI application tests

Provides common fixtures for testing including:
- Test client
- Mock services
- Test data
"""

import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, MagicMock, patch
import httpx

from app.main import app
from app.config import settings


@pytest.fixture
def client():
    """
    Create a test client for the FastAPI application
    """
    # Disable cache initialization for tests
    with patch('app.middleware.cache.FastAPICache.init'):
        with patch('app.middleware.cache.FastAPICache.get_coder', return_value=MagicMock()):
            with TestClient(app) as test_client:
                yield test_client


@pytest.fixture
def async_client():
    """
    Create an async test client for the FastAPI application
    """
    return httpx.AsyncClient(app=app, base_url="http://test")


@pytest.fixture
def mock_vault_client():
    """
    Mock VaultClient for testing without actual Vault connection
    """
    with patch('app.services.vault.vault_client') as mock:
        mock.get_secret = AsyncMock(return_value={
            "user": "test_user",
            "password": "test_password",
            "database": "test_db"
        })
        mock.check_health = AsyncMock(return_value={
            "status": "healthy",
            "initialized": True,
            "sealed": False
        })
        yield mock


@pytest.fixture
def mock_redis():
    """
    Mock Redis client for cache testing
    """
    mock_redis = AsyncMock()
    mock_redis.ping = AsyncMock(return_value=True)
    mock_redis.get = AsyncMock(return_value=None)
    mock_redis.set = AsyncMock(return_value=True)
    mock_redis.delete = AsyncMock(return_value=1)

    # scan_iter is a regular function that returns an async generator
    # Tests will override scan_iter.return_value with their own async generator
    async def default_scan_iter():
        return
        yield  # Make it an empty generator

    mock_redis.scan_iter = MagicMock(return_value=default_scan_iter())
    mock_redis.close = AsyncMock()
    return mock_redis


@pytest.fixture
def sample_vault_secret():
    """
    Sample Vault secret data for testing
    """
    return {
        "user": "test_user",
        "password": "test_password",
        "database": "test_db",
        "host": "localhost",
        "port": "5432"
    }


@pytest.fixture
def sample_request_context():
    """
    Sample request context for testing middleware
    """
    return {
        "request_id": "test-request-123",
        "method": "GET",
        "path": "/test",
        "status_code": 200
    }


@pytest.fixture(autouse=True)
def reset_prometheus_metrics():
    """
    Reset Prometheus metrics before each test to avoid side effects
    """
    from prometheus_client import REGISTRY
    # Note: We can't easily reset metrics, so we'll just yield
    # In production tests, you'd want to use a separate registry
    yield


@pytest.fixture
def mock_httpx_client():
    """
    Mock httpx client for testing external API calls
    """
    mock_client = AsyncMock()
    mock_response = AsyncMock()
    mock_response.status_code = 200
    mock_response.json = MagicMock(return_value={"data": {"data": {"key": "value"}}})
    mock_response.raise_for_status = MagicMock()
    mock_client.get = AsyncMock(return_value=mock_response)
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=None)
    return mock_client


@pytest.fixture
def vault_404_response():
    """
    Mock Vault 404 response for testing not found errors
    """
    response = MagicMock()
    response.status_code = 404
    response.json = MagicMock(return_value={"errors": ["secret not found"]})
    return response


@pytest.fixture
def vault_403_response():
    """
    Mock Vault 403 response for testing permission errors
    """
    response = MagicMock()
    response.status_code = 403
    response.json = MagicMock(return_value={"errors": ["permission denied"]})
    return response


@pytest.fixture
def vault_timeout_error():
    """
    Mock Vault timeout error for testing timeout scenarios
    """
    return httpx.TimeoutException("Connection timeout")


@pytest.fixture
def vault_connection_error():
    """
    Mock Vault connection error for testing connection failures
    """
    return httpx.ConnectError("Connection refused")


@pytest.fixture
def mock_cache_backend():
    """
    Mock cache backend for testing caching without Redis
    """
    with patch('app.middleware.cache.FastAPICache.init') as mock_init:
        with patch('app.middleware.cache.FastAPICache.get_coder') as mock_coder:
            mock_coder.return_value = MagicMock()
            yield mock_init


@pytest.fixture
def mock_async_iterator():
    """
    Create a proper async iterator for testing
    """
    async def async_iter(items):
        for item in items:
            yield item
    return async_iter
