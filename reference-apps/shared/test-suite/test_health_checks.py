"""
Shared Test Suite - Health Check Tests

Validates that both API implementations have functional health checks
and return consistent health information.
"""

import pytest


@pytest.mark.health
@pytest.mark.parity
@pytest.mark.asyncio
class TestHealthEndpoints:
    """Test health check endpoints across both implementations."""

    async def test_simple_health_check(self, api_url, http_client):
        """Test simple health check endpoint returns OK."""
        response = await http_client.get(f"{api_url}/health/")

        assert response.status_code == 200, f"Health check failed for {api_url}"
        data = response.json()
        assert "status" in data
        assert data["status"] == "ok"

    async def test_health_response_structure(self, api_url, http_client):
        """Test health check response has expected structure."""
        response = await http_client.get(f"{api_url}/health/")

        assert response.status_code == 200
        data = response.json()

        # Both implementations should return same structure
        assert isinstance(data, dict)
        assert "status" in data
        assert isinstance(data["status"], str)

    async def test_vault_health_check(self, api_url, http_client):
        """Test Vault-specific health check endpoint."""
        response = await http_client.get(f"{api_url}/health/vault")

        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        # Status should be either "healthy" or "unhealthy"
        assert data["status"] in ["healthy", "unhealthy"]


@pytest.mark.health
@pytest.mark.comparison
@pytest.mark.asyncio
class TestHealthParity:
    """Test that both implementations return identical health responses."""

    async def test_health_responses_match(self, both_api_urls, http_client):
        """Verify both implementations return identical health responses."""
        # Get responses from both APIs
        code_first_response = await http_client.get(
            f"{both_api_urls['code-first']}/health/"
        )
        api_first_response = await http_client.get(
            f"{both_api_urls['api-first']}/health/"
        )

        # Both should succeed
        assert code_first_response.status_code == 200
        assert api_first_response.status_code == 200

        # Both should have same response structure
        code_first_data = code_first_response.json()
        api_first_data = api_first_response.json()

        assert code_first_data.keys() == api_first_data.keys()
        assert code_first_data["status"] == api_first_data["status"]
