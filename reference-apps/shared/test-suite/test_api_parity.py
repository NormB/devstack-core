"""
Shared Test Suite - API Parity Tests

Validates that both API implementations behave identically for all endpoints.
Tests run against both code-first and API-first implementations using
parametrized fixtures.
"""

import pytest


@pytest.mark.parity
@pytest.mark.asyncio
class TestRootEndpoint:
    """Test root endpoint parity."""

    async def test_root_endpoint_returns_info(self, api_url, http_client):
        """Test root endpoint returns API information."""
        response = await http_client.get(f"{api_url}/")

        assert response.status_code == 200
        data = response.json()

        # Verify required fields
        assert "name" in data or "service" in data
        assert "version" in data
        assert "description" in data

    async def test_root_endpoint_structure_matches(self, both_api_urls, http_client):
        """Verify both implementations return identical root endpoint structure."""
        code_first_response = await http_client.get(f"{both_api_urls['code-first']}/")
        api_first_response = await http_client.get(f"{both_api_urls['api-first']}/")

        assert code_first_response.status_code == 200
        assert api_first_response.status_code == 200

        code_first_data = code_first_response.json()
        api_first_data = api_first_response.json()

        # Keys should match
        assert set(code_first_data.keys()) == set(api_first_data.keys()), \
            f"Root endpoint keys don't match: {code_first_data.keys()} vs {api_first_data.keys()}"


@pytest.mark.parity
@pytest.mark.asyncio
class TestOpenAPISpec:
    """Test OpenAPI specification parity."""

    async def test_openapi_endpoint_accessible(self, api_url, http_client):
        """Test OpenAPI spec endpoint is accessible."""
        response = await http_client.get(f"{api_url}/openapi.json")

        assert response.status_code == 200
        data = response.json()

        # Verify OpenAPI required fields
        assert "openapi" in data
        assert "info" in data
        assert "paths" in data

    async def test_openapi_specs_match(self, both_api_urls, http_client):
        """Verify both implementations have matching OpenAPI specifications."""
        code_first_response = await http_client.get(
            f"{both_api_urls['code-first']}/openapi.json"
        )
        api_first_response = await http_client.get(
            f"{both_api_urls['api-first']}/openapi.json"
        )

        assert code_first_response.status_code == 200
        assert api_first_response.status_code == 200

        code_first_spec = code_first_response.json()
        api_first_spec = api_first_response.json()

        # Compare paths (endpoints)
        assert set(code_first_spec["paths"].keys()) == set(api_first_spec["paths"].keys()), \
            "OpenAPI paths don't match between implementations"

    async def test_openapi_version_format(self, api_url, http_client):
        """Test OpenAPI specification version format."""
        response = await http_client.get(f"{api_url}/openapi.json")

        assert response.status_code == 200
        data = response.json()

        # Version should be in format X.Y.Z
        assert "openapi" in data
        assert data["openapi"].startswith("3.")  # OpenAPI 3.x.x


@pytest.mark.parity
@pytest.mark.asyncio
class TestVaultEndpoints:
    """Test Vault demo endpoints parity."""

    async def test_vault_secret_endpoint_structure(self, api_url, http_client):
        """Test Vault secret endpoint response structure (without requiring actual secret)."""
        # This test validates the endpoint exists and has proper error handling
        response = await http_client.get(f"{api_url}/examples/vault/secret/nonexistent")

        # Should return either 200 (if mocked) or 404/503 (if real Vault required)
        assert response.status_code in [200, 404, 500, 503]

        # All responses should be JSON
        data = response.json()
        assert isinstance(data, dict)


@pytest.mark.parity
@pytest.mark.asyncio
class TestCacheEndpoints:
    """Test cache demo endpoints parity."""

    async def test_cache_get_endpoint_exists(self, api_url, http_client):
        """Test cache GET endpoint exists and responds."""
        response = await http_client.get(f"{api_url}/examples/cache/test-key")

        # Should return 200 (key not found) or 500 (Redis not available)
        assert response.status_code in [200, 500, 503]
        data = response.json()
        assert isinstance(data, dict)

    async def test_cache_endpoints_have_same_behavior(self, both_api_urls, http_client):
        """Verify both implementations handle cache requests identically."""
        test_key = "parity-test-key"

        code_first_response = await http_client.get(
            f"{both_api_urls['code-first']}/examples/cache/{test_key}"
        )
        api_first_response = await http_client.get(
            f"{both_api_urls['api-first']}/examples/cache/{test_key}"
        )

        # Both should return same status code
        assert code_first_response.status_code == api_first_response.status_code

        # Both should return same response structure
        code_first_data = code_first_response.json()
        api_first_data = api_first_response.json()

        assert set(code_first_data.keys()) == set(api_first_data.keys())


@pytest.mark.parity
@pytest.mark.asyncio
class TestMetricsEndpoint:
    """Test metrics endpoint parity."""

    async def test_metrics_endpoint_accessible(self, api_url, http_client):
        """Test metrics endpoint is accessible."""
        response = await http_client.get(f"{api_url}/metrics")

        assert response.status_code == 200
        # Prometheus metrics are plain text
        assert "text/plain" in response.headers.get("content-type", "")

    async def test_metrics_format_matches(self, both_api_urls, http_client):
        """Verify both implementations return metrics in same format."""
        code_first_response = await http_client.get(
            f"{both_api_urls['code-first']}/metrics"
        )
        api_first_response = await http_client.get(
            f"{both_api_urls['api-first']}/metrics"
        )

        assert code_first_response.status_code == 200
        assert api_first_response.status_code == 200

        # Both should be Prometheus format
        assert "text/plain" in code_first_response.headers["content-type"]
        assert "text/plain" in api_first_response.headers["content-type"]


@pytest.mark.parity
@pytest.mark.asyncio
class TestErrorHandling:
    """Test error handling parity."""

    async def test_404_response_format(self, api_url, http_client):
        """Test 404 responses are formatted consistently."""
        response = await http_client.get(f"{api_url}/nonexistent-endpoint")

        assert response.status_code == 404
        data = response.json()
        assert isinstance(data, dict)
        assert "detail" in data or "message" in data

    async def test_404_responses_match(self, both_api_urls, http_client):
        """Verify both implementations return identical 404 responses."""
        code_first_response = await http_client.get(
            f"{both_api_urls['code-first']}/nonexistent-endpoint"
        )
        api_first_response = await http_client.get(
            f"{both_api_urls['api-first']}/nonexistent-endpoint"
        )

        assert code_first_response.status_code == 404
        assert api_first_response.status_code == 404

        code_first_data = code_first_response.json()
        api_first_data = api_first_response.json()

        # Both should have same keys in error response
        assert set(code_first_data.keys()) == set(api_first_data.keys())
