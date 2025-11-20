"""
Integration tests for API endpoints with real service interactions.

These tests verify normal use cases with actual service connections.
"""

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.mark.integration
class TestRootEndpoint:
    """Test root endpoint integration."""

    def test_root_endpoint_returns_api_info(self):
        """Test root endpoint returns complete API information."""
        with TestClient(app) as client:
            response = client.get("/")

            assert response.status_code == 200
            data = response.json()

            # Verify all expected fields are present
            assert "name" in data or "service" in data
            assert "version" in data
            assert "description" in data
            assert "docs" in data or "documentation" in data or "openapi_url" in data

    def test_root_endpoint_content_type(self):
        """Test root endpoint returns JSON content type."""
        with TestClient(app) as client:
            response = client.get("/")

            assert response.status_code == 200
            assert "application/json" in response.headers["content-type"]


@pytest.mark.integration
class TestOpenAPIEndpoints:
    """Test OpenAPI documentation endpoints."""

    def test_openapi_json_accessible(self):
        """Test OpenAPI JSON spec is accessible."""
        with TestClient(app) as client:
            response = client.get("/openapi.json")

            assert response.status_code == 200
            assert "application/json" in response.headers["content-type"]

            data = response.json()
            assert "openapi" in data
            assert "info" in data
            assert "paths" in data

    def test_docs_endpoint_accessible(self):
        """Test Swagger UI documentation is accessible."""
        with TestClient(app) as client:
            response = client.get("/docs")

            assert response.status_code == 200
            assert "text/html" in response.headers["content-type"]

    def test_redoc_endpoint_accessible(self):
        """Test ReDoc documentation is accessible."""
        with TestClient(app) as client:
            response = client.get("/redoc")

            assert response.status_code == 200
            assert "text/html" in response.headers["content-type"]

    def test_openapi_spec_has_all_endpoints(self):
        """Test OpenAPI spec includes all main endpoints."""
        with TestClient(app) as client:
            response = client.get("/openapi.json")
            spec = response.json()

            # Verify critical paths are documented
            paths = spec["paths"]
            assert "/" in paths
            assert "/health/" in paths
            assert "/metrics" in paths


@pytest.mark.integration
class TestMetricsEndpoint:
    """Test Prometheus metrics endpoint."""

    def test_metrics_endpoint_accessible(self):
        """Test metrics endpoint is accessible."""
        with TestClient(app) as client:
            response = client.get("/metrics")

            assert response.status_code == 200

    def test_metrics_format(self):
        """Test metrics endpoint returns Prometheus format."""
        with TestClient(app) as client:
            response = client.get("/metrics")

            assert response.status_code == 200
            content = response.text

            # Prometheus metrics should include HELP and TYPE comments
            assert "# HELP" in content or "# TYPE" in content
            # Should have at least some metrics
            assert len(content) > 0

    def test_metrics_content_type(self):
        """Test metrics endpoint returns correct content type."""
        with TestClient(app) as client:
            response = client.get("/metrics")

            assert response.status_code == 200
            # Prometheus metrics use text/plain
            assert "text/plain" in response.headers["content-type"] or \
                   "text" in response.headers["content-type"]


@pytest.mark.integration
class TestHealthEndpointsIntegration:
    """Test health check endpoints with real service checks."""

    def test_simple_health_check_always_works(self):
        """Test simple health check always returns OK."""
        with TestClient(app) as client:
            response = client.get("/health/")

            assert response.status_code == 200
            data = response.json()
            assert data["status"] == "ok"

    def test_all_health_checks_endpoint(self):
        """Test aggregated health checks endpoint."""
        with TestClient(app) as client:
            response = client.get("/health/all")

            assert response.status_code == 200
            data = response.json()

            # Should return service health information
            assert isinstance(data, dict)
            # Should have either a status field or service-specific fields
            assert "status" in data or len(data) > 0


@pytest.mark.integration
class TestCORSHeaders:
    """Test CORS headers are properly set."""

    def test_cors_headers_on_get_requests(self):
        """Test CORS headers are present on GET requests."""
        with TestClient(app) as client:
            response = client.get("/", headers={"Origin": "http://localhost:3000"})

            assert response.status_code == 200
            # CORS headers should be present
            assert "access-control-allow-origin" in response.headers

    def test_preflight_request(self):
        """Test OPTIONS preflight requests are handled."""
        with TestClient(app) as client:
            response = client.options(
                "/health/",
                headers={
                    "Origin": "http://localhost:3000",
                    "Access-Control-Request-Method": "GET"
                }
            )

            # Preflight should return 200
            assert response.status_code == 200
            assert "access-control-allow-origin" in response.headers


@pytest.mark.integration
class TestErrorResponses:
    """Test API error response formats."""

    def test_404_response_format(self):
        """Test 404 errors return proper JSON format."""
        with TestClient(app) as client:
            response = client.get("/nonexistent/endpoint")

            assert response.status_code == 404
            data = response.json()

            # FastAPI returns detail field for errors
            assert "detail" in data or "message" in data or "error" in data

    def test_405_method_not_allowed(self):
        """Test 405 errors for wrong HTTP methods."""
        with TestClient(app) as client:
            # Try POST on GET-only endpoint
            response = client.post("/health/")

            assert response.status_code == 405
            data = response.json()
            assert "detail" in data or "message" in data or "error" in data


@pytest.mark.integration
class TestInputValidation:
    """Test API input validation."""

    def test_cache_key_validation(self):
        """Test cache endpoint validates key format."""
        with TestClient(app) as client:
            # Test with invalid characters
            invalid_keys = [
                "key with spaces",
                "key@with@symbols",
                "a" * 300,  # Too long
            ]

            for invalid_key in invalid_keys:
                response = client.get(f"/examples/cache/{invalid_key}")

                # Should return validation error
                assert response.status_code in [400, 422], \
                    f"Invalid key should be rejected: {invalid_key}"

            # Note: Slashes in path parameters are handled by routing before validation,
            # so "key/with/slashes" results in 404 (not found route) rather than 422 (validation error)

    def test_messaging_payload_validation(self):
        """Test messaging endpoint validates payload."""
        with TestClient(app) as client:
            # Test with missing fields
            response = client.post(
                "/examples/messaging/publish",
                json={}
            )

            # Should return validation error
            assert response.status_code == 422

    def test_service_name_validation(self):
        """Test service name parameter validation."""
        with TestClient(app) as client:
            # Test with invalid service name
            # Note: "service/name" with slash gets routed to the two-parameter endpoint
            # (/secret/{service_name}/{key}) where service_name="service" and key="name",
            # then fails when trying to fetch that secret from Vault (503)
            invalid_names_with_expected_codes = [
                ("invalid service", [400, 422]),  # Validation error for space
                ("service/name", [404, 503]),     # Routes to different endpoint, then fails
                ("service@name", [400, 422]),     # Validation error for @
                ("", [404, 422]),                 # Empty string - routing or validation error
            ]

            for invalid_name, expected_codes in invalid_names_with_expected_codes:
                response = client.get(f"/examples/vault/secret/{invalid_name}")

                assert response.status_code in expected_codes, \
                    f"Invalid service name '{invalid_name}' returned {response.status_code}, expected one of {expected_codes}"
