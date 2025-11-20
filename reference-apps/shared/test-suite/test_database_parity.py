"""
Shared Test Suite - Database Endpoint Parity Tests

Validates that both API implementations handle database operations identically.
"""

import pytest


@pytest.mark.parity
@pytest.mark.asyncio
class TestDatabaseEndpoints:
    """Test database demonstration endpoints parity."""

    async def test_postgres_query_endpoint_exists(self, api_url, http_client):
        """Test PostgreSQL query endpoint exists."""
        response = await http_client.get(f"{api_url}/examples/database/postgres/query")

        # Should return 200 (success) or 503 (service unavailable)
        assert response.status_code in [200, 503]
        data = response.json()
        assert isinstance(data, dict)

    async def test_mysql_query_endpoint_exists(self, api_url, http_client):
        """Test MySQL query endpoint exists."""
        response = await http_client.get(f"{api_url}/examples/database/mysql/query")

        # Should return 200 (success) or 503 (service unavailable)
        assert response.status_code in [200, 503]
        data = response.json()
        assert isinstance(data, dict)

    async def test_mongodb_query_endpoint_exists(self, api_url, http_client):
        """Test MongoDB query endpoint exists."""
        response = await http_client.get(f"{api_url}/examples/database/mongodb/query")

        # Should return 200 (success) or 503 (service unavailable)
        assert response.status_code in [200, 503]
        data = response.json()
        assert isinstance(data, dict)

    async def test_database_endpoints_structure_matches(self, both_api_urls, http_client):
        """Verify both implementations return identical database response structure."""
        databases = ["postgres", "mysql", "mongodb"]

        for db in databases:
            code_first_response = await http_client.get(
                f"{both_api_urls['code-first']}/examples/database/{db}/query"
            )
            api_first_response = await http_client.get(
                f"{both_api_urls['api-first']}/examples/database/{db}/query"
            )

            # Both should have same status code
            assert code_first_response.status_code == api_first_response.status_code, \
                f"Status codes don't match for {db}"

            # Both should return same response keys
            code_first_data = code_first_response.json()
            api_first_data = api_first_response.json()

            assert set(code_first_data.keys()) == set(api_first_data.keys()), \
                f"Response keys don't match for {db}"


@pytest.mark.parity
@pytest.mark.asyncio
class TestDatabaseHealthChecks:
    """Test database health check endpoints parity."""

    async def test_postgres_health_endpoint(self, api_url, http_client):
        """Test PostgreSQL health check endpoint."""
        response = await http_client.get(f"{api_url}/health/postgres")

        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert data["status"] in ["healthy", "unhealthy"]

    async def test_mysql_health_endpoint(self, api_url, http_client):
        """Test MySQL health check endpoint."""
        response = await http_client.get(f"{api_url}/health/mysql")

        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert data["status"] in ["healthy", "unhealthy"]

    async def test_mongodb_health_endpoint(self, api_url, http_client):
        """Test MongoDB health check endpoint."""
        response = await http_client.get(f"{api_url}/health/mongodb")

        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert data["status"] in ["healthy", "unhealthy"]

    async def test_redis_health_endpoint(self, api_url, http_client):
        """Test Redis health check endpoint."""
        response = await http_client.get(f"{api_url}/health/redis")

        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert data["status"] in ["healthy", "unhealthy"]

    async def test_rabbitmq_health_endpoint(self, api_url, http_client):
        """Test RabbitMQ health check endpoint."""
        response = await http_client.get(f"{api_url}/health/rabbitmq")

        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert data["status"] in ["healthy", "unhealthy"]

    async def test_all_health_checks_endpoint(self, api_url, http_client):
        """Test aggregated health check endpoint."""
        response = await http_client.get(f"{api_url}/health/all")

        # May return 200 (all healthy) or 500 (some unhealthy)
        assert response.status_code in [200, 500]
        data = response.json()
        # Should return either health data or error data
        assert isinstance(data, dict)
        assert len(data) > 0  # Should have some content

    async def test_health_checks_parity(self, both_api_urls, http_client):
        """Verify both implementations return identical health check structures."""
        health_endpoints = ["postgres", "mysql", "mongodb", "redis", "rabbitmq", "vault"]

        for endpoint in health_endpoints:
            code_first_response = await http_client.get(
                f"{both_api_urls['code-first']}/health/{endpoint}"
            )
            api_first_response = await http_client.get(
                f"{both_api_urls['api-first']}/health/{endpoint}"
            )

            # Both should return 200 (individual health checks)
            assert code_first_response.status_code == 200
            assert api_first_response.status_code == 200

            code_first_data = code_first_response.json()
            api_first_data = api_first_response.json()

            # Response structure should match
            assert set(code_first_data.keys()) == set(api_first_data.keys()), \
                f"Health check keys don't match for {endpoint}"
