"""
Shared Test Suite - Messaging Endpoint Parity Tests

Validates that both API implementations handle RabbitMQ messaging operations identically.
"""

import pytest


@pytest.mark.parity
@pytest.mark.asyncio
class TestMessagingEndpoints:
    """Test RabbitMQ messaging endpoints parity."""

    async def test_publish_message_endpoint_method(self, api_url, http_client):
        """Test message publish endpoint accepts POST requests."""
        # Test with minimal valid payload
        payload = {
            "queue_name": "test_queue",
            "message": "Test message"
        }

        response = await http_client.post(
            f"{api_url}/examples/messaging/publish",
            json=payload
        )

        # Should return 200 (success), 422 (validation), or 503 (service unavailable)
        assert response.status_code in [200, 422, 503]
        data = response.json()
        assert isinstance(data, dict)

    async def test_queue_info_endpoint(self, api_url, http_client):
        """Test queue info endpoint."""
        queue_name = "test_queue"

        response = await http_client.get(
            f"{api_url}/examples/messaging/queue/{queue_name}/info"
        )

        # Should return 200, 404 (not found), 500 (error), or 503 (unavailable)
        assert response.status_code in [200, 404, 500, 503]
        data = response.json()
        assert isinstance(data, dict)

    async def test_publish_message_validation(self, api_url, http_client):
        """Test message publish endpoint validates input."""
        # Test with invalid payload (missing required fields)
        invalid_payloads = [
            {},  # Empty
            {"queue_name": "test"},  # Missing message
            {"message": "test"},  # Missing queue_name
        ]

        for payload in invalid_payloads:
            response = await http_client.post(
                f"{api_url}/examples/messaging/publish",
                json=payload
            )

            # Should return 422 (validation error) or 400 (bad request)
            assert response.status_code in [400, 422], \
                f"Invalid payload should be rejected: {payload}"

    async def test_messaging_endpoints_parity(self, both_api_urls, http_client):
        """Verify both implementations handle messaging requests identically."""
        # Test queue info endpoint
        queue_name = "test_queue"

        code_first_response = await http_client.get(
            f"{both_api_urls['code-first']}/examples/messaging/queue/{queue_name}/info"
        )
        api_first_response = await http_client.get(
            f"{both_api_urls['api-first']}/examples/messaging/queue/{queue_name}/info"
        )

        # Both should have same status code
        assert code_first_response.status_code == api_first_response.status_code

        # Both should return JSON
        code_first_data = code_first_response.json()
        api_first_data = api_first_response.json()

        # Response structure should match
        assert set(code_first_data.keys()) == set(api_first_data.keys())

    async def test_publish_message_parity(self, both_api_urls, http_client):
        """Verify both implementations handle message publishing identically."""
        payload = {
            "queue_name": "parity_test_queue",
            "message": "Parity test message"
        }

        code_first_response = await http_client.post(
            f"{both_api_urls['code-first']}/examples/messaging/publish",
            json=payload
        )
        api_first_response = await http_client.post(
            f"{both_api_urls['api-first']}/examples/messaging/publish",
            json=payload
        )

        # Both should have same status code
        assert code_first_response.status_code == api_first_response.status_code

        # Both should return JSON
        code_first_data = code_first_response.json()
        api_first_data = api_first_response.json()

        # Response structure should match
        assert set(code_first_data.keys()) == set(api_first_data.keys())
