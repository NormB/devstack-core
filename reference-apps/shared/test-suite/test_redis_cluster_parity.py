"""
Shared Test Suite - Redis Cluster Endpoint Parity Tests

Validates that both API implementations handle Redis cluster operations identically.
"""

import pytest


@pytest.mark.parity
@pytest.mark.asyncio
class TestRedisClusterEndpoints:
    """Test Redis cluster endpoints parity."""

    async def test_cluster_nodes_endpoint(self, api_url, http_client):
        """Test Redis cluster nodes endpoint."""
        response = await http_client.get(f"{api_url}/redis/cluster/nodes")

        # Should return 200 (success) or 503 (service unavailable)
        assert response.status_code in [200, 503]
        data = response.json()
        assert isinstance(data, dict)

        if response.status_code == 200:
            # Should have nodes information
            assert "nodes" in data or "cluster_nodes" in data or len(data) > 0

    async def test_cluster_info_endpoint(self, api_url, http_client):
        """Test Redis cluster info endpoint."""
        response = await http_client.get(f"{api_url}/redis/cluster/info")

        assert response.status_code in [200, 503]
        data = response.json()
        assert isinstance(data, dict)

        if response.status_code == 200:
            # Should have cluster information
            assert "cluster_state" in data or "state" in data or len(data) > 0

    async def test_cluster_slots_endpoint(self, api_url, http_client):
        """Test Redis cluster slots endpoint."""
        response = await http_client.get(f"{api_url}/redis/cluster/slots")

        assert response.status_code in [200, 503]
        data = response.json()
        assert isinstance(data, dict)

        if response.status_code == 200:
            # Should have slots information
            assert "slots" in data or "cluster_slots" in data or len(data) > 0

    async def test_redis_cluster_endpoints_parity(self, both_api_urls, http_client):
        """Verify both implementations return identical Redis cluster responses."""
        endpoints = ["nodes", "info", "slots"]

        for endpoint in endpoints:
            code_first_response = await http_client.get(
                f"{both_api_urls['code-first']}/redis/cluster/{endpoint}"
            )
            api_first_response = await http_client.get(
                f"{both_api_urls['api-first']}/redis/cluster/{endpoint}"
            )

            # Both should have same status code
            assert code_first_response.status_code == api_first_response.status_code, \
                f"Status codes don't match for /redis/cluster/{endpoint}"

            # Both should return JSON
            code_first_data = code_first_response.json()
            api_first_data = api_first_response.json()

            # Response structure should match
            assert set(code_first_data.keys()) == set(api_first_data.keys()), \
                f"Response keys don't match for /redis/cluster/{endpoint}"


@pytest.mark.parity
@pytest.mark.asyncio
class TestRedisNodeEndpoints:
    """Test individual Redis node endpoints parity."""

    async def test_node_info_endpoint_structure(self, api_url, http_client):
        """Test Redis node info endpoint structure."""
        # Test with a common node name
        node_names = ["redis-1", "node1", "master1"]

        for node_name in node_names:
            response = await http_client.get(f"{api_url}/redis/nodes/{node_name}/info")

            # Should return 200, 404 (not found), or 503 (unavailable)
            assert response.status_code in [200, 404, 503]
            data = response.json()
            assert isinstance(data, dict)

            # Stop after first successful response
            if response.status_code == 200:
                break

    async def test_redis_node_endpoints_parity(self, both_api_urls, http_client):
        """Verify both implementations handle node requests identically."""
        node_name = "redis-1"

        code_first_response = await http_client.get(
            f"{both_api_urls['code-first']}/redis/nodes/{node_name}/info"
        )
        api_first_response = await http_client.get(
            f"{both_api_urls['api-first']}/redis/nodes/{node_name}/info"
        )

        # Both should have same status code
        assert code_first_response.status_code == api_first_response.status_code

        # Both should return JSON
        code_first_data = code_first_response.json()
        api_first_data = api_first_response.json()

        # Response structure should match
        assert set(code_first_data.keys()) == set(api_first_data.keys())
