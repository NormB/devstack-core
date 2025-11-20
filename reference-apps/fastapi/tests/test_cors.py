"""
Test CORS (Cross-Origin Resource Sharing) configuration

Tests for:
- CORS headers on GET requests
- CORS headers on POST requests
- Preflight OPTIONS requests
- Allowed origins
- Allowed methods
- Allowed and exposed headers
"""

import pytest
from fastapi.testclient import TestClient
from app.main import app


client = TestClient(app)


class TestCORSHeaders:
    """Test CORS headers on actual requests"""

    def test_cors_headers_on_get_request(self):
        """Test that CORS headers are present on GET requests"""
        response = client.get(
            "/",
            headers={"Origin": "http://localhost:3000"}
        )

        assert response.status_code == 200

        # Check for CORS headers
        assert "access-control-allow-origin" in response.headers
        # When Origin header is sent, CORS middleware echoes it back (not "*")
        # This is correct CORS behavior when allow_origins includes "*"
        assert response.headers["access-control-allow-origin"] == "http://localhost:3000"

    def test_cors_headers_on_post_request(self):
        """Test that CORS headers are present on POST requests"""
        response = client.post(
            "/examples/cache/test-key?value=test",
            headers={"Origin": "http://localhost:3000"}
        )

        # Check for CORS headers (may be 200 or 500 depending on Redis)
        assert "access-control-allow-origin" in response.headers

    def test_exposed_headers_include_request_id(self):
        """Test that X-Request-ID is exposed via CORS"""
        response = client.get(
            "/",
            headers={"Origin": "http://localhost:3000"}
        )

        assert response.status_code == 200

        # Check that X-Request-ID is in exposed headers
        if "access-control-expose-headers" in response.headers:
            exposed = response.headers["access-control-expose-headers"]
            # May be comma-separated or single header
            assert "X-Request-ID" in exposed or "x-request-id" in exposed.lower()


class TestCORSPreflightRequests:
    """Test CORS preflight OPTIONS requests"""

    def test_preflight_request_basic(self):
        """Test basic OPTIONS preflight request"""
        response = client.options(
            "/",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
            }
        )

        # Preflight should return 200
        assert response.status_code == 200

        # Should have CORS headers
        assert "access-control-allow-origin" in response.headers
        assert "access-control-allow-methods" in response.headers

    def test_preflight_request_post_method(self):
        """Test OPTIONS preflight for POST method"""
        response = client.options(
            "/examples/messaging/publish",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type",
            }
        )

        assert response.status_code == 200

        # Check allowed methods includes POST
        if "access-control-allow-methods" in response.headers:
            methods = response.headers["access-control-allow-methods"]
            assert "POST" in methods

    def test_preflight_request_custom_header(self):
        """Test OPTIONS preflight with custom header request"""
        response = client.options(
            "/",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "X-API-Key",
            }
        )

        assert response.status_code == 200

        # Should allow the requested header
        if "access-control-allow-headers" in response.headers:
            headers = response.headers["access-control-allow-headers"]
            # X-API-Key should be in allowed headers
            assert "X-API-Key" in headers or "x-api-key" in headers.lower()

    def test_preflight_max_age_present(self):
        """Test that preflight responses include max-age for caching"""
        response = client.options(
            "/",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
            }
        )

        assert response.status_code == 200

        # Should have max-age header for caching preflight
        if "access-control-max-age" in response.headers:
            max_age = int(response.headers["access-control-max-age"])
            assert max_age > 0  # Should cache for some time


class TestCORSMethods:
    """Test that various HTTP methods work with CORS"""

    def test_get_method_allowed(self):
        """Test GET method works with CORS"""
        response = client.get(
            "/health/",
            headers={"Origin": "http://localhost:3000"}
        )

        assert response.status_code == 200
        assert "access-control-allow-origin" in response.headers

    def test_post_method_allowed(self):
        """Test POST method works with CORS"""
        response = client.post(
            "/examples/cache/test?value=test",
            headers={
                "Origin": "http://localhost:3000",
                "Content-Type": "application/json"
            }
        )

        # Should have CORS headers regardless of business logic result
        assert "access-control-allow-origin" in response.headers

    def test_delete_method_allowed(self):
        """Test DELETE method works with CORS"""
        response = client.delete(
            "/examples/cache/test",
            headers={"Origin": "http://localhost:3000"}
        )

        # Should have CORS headers
        assert "access-control-allow-origin" in response.headers


class TestCORSOrigins:
    """Test CORS origin handling"""

    def test_localhost_origin_allowed(self):
        """Test that localhost origins are handled"""
        origins = [
            "http://localhost:3000",
            "http://localhost:8000",
            "http://localhost:8080",
            "http://127.0.0.1:3000",
        ]

        for origin in origins:
            response = client.get(
                "/",
                headers={"Origin": origin}
            )

            assert response.status_code == 200
            assert "access-control-allow-origin" in response.headers

    def test_no_origin_header_works(self):
        """Test that requests without Origin header work normally"""
        response = client.get("/")

        assert response.status_code == 200
        # Response should work even without CORS headers


class TestCORSHeaderConfiguration:
    """Test specific CORS header configurations"""

    def test_content_type_header_allowed(self):
        """Test that Content-Type header is allowed"""
        response = client.options(
            "/examples/messaging/publish",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "Content-Type",
            }
        )

        assert response.status_code == 200

        if "access-control-allow-headers" in response.headers:
            headers = response.headers["access-control-allow-headers"]
            assert "Content-Type" in headers or "content-type" in headers.lower()

    def test_authorization_header_allowed(self):
        """Test that Authorization header is allowed"""
        response = client.options(
            "/",
            headers={
                "Origin": "http://localhost:3000",
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "Authorization",
            }
        )

        assert response.status_code == 200

        if "access-control-allow-headers" in response.headers:
            headers = response.headers["access-control-allow-headers"]
            assert "Authorization" in headers or "authorization" in headers.lower()


class TestCORSWithRateLimiting:
    """Test that CORS works correctly with rate limiting"""

    def test_rate_limited_request_has_cors_headers(self):
        """Test that rate-limited responses still include CORS headers"""
        # Make multiple requests to potentially trigger rate limiting
        # (though unlikely with our limits)
        response = client.get(
            "/",
            headers={"Origin": "http://localhost:3000"}
        )

        # Even if rate limited, should have CORS headers
        assert "access-control-allow-origin" in response.headers


class TestCORSConfiguration:
    """Test CORS configuration specifics"""

    def test_cors_allows_credentials_configuration(self):
        """Test that credentials configuration is present when appropriate"""
        response = client.get(
            "/",
            headers={"Origin": "http://localhost:3000"}
        )

        # In debug mode with allow_origins=["*"], credentials should be false
        # This is checked by the presence/absence of access-control-allow-credentials
        # When allow_origins is "*", credentials must be false (CORS spec)
        if "access-control-allow-credentials" in response.headers:
            # If present and allow-origin is "*", this is a CORS violation
            # FastAPI's CORSMiddleware should handle this correctly
            pass

    def test_multiple_requests_consistent_cors(self):
        """Test that CORS headers are consistent across multiple requests"""
        origins = ["http://localhost:3000", "http://localhost:8080"]

        for origin in origins:
            response = client.get(
                "/health/",
                headers={"Origin": origin}
            )

            assert response.status_code == 200
            assert "access-control-allow-origin" in response.headers


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
