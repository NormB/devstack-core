"""
Unit tests for Vault service with exception handling

Tests the VaultClient class and its error handling behavior.
"""

import pytest
import httpx
from unittest.mock import AsyncMock, MagicMock, patch

from app.services.vault import VaultClient
from app.exceptions import VaultUnavailableError, ResourceNotFoundError


@pytest.mark.unit
class TestVaultClientGetSecret:
    """Test VaultClient.get_secret method"""

    @pytest.fixture
    def vault_client(self):
        """Create VaultClient instance"""
        return VaultClient()

    @pytest.mark.asyncio
    async def test_get_secret_success(self, vault_client, mock_httpx_client):
        """Test successful secret retrieval"""
        mock_httpx_client.get.return_value.json.return_value = {
            "data": {
                "data": {
                    "user": "test_user",
                    "password": "test_pass"
                }
            }
        }

        with patch('httpx.AsyncClient', return_value=mock_httpx_client):
            result = await vault_client.get_secret("postgres")

            assert result["user"] == "test_user"
            assert result["password"] == "test_pass"

    @pytest.mark.asyncio
    async def test_get_secret_with_key(self, vault_client, mock_httpx_client):
        """Test retrieving specific key from secret"""
        mock_httpx_client.get.return_value.json.return_value = {
            "data": {
                "data": {
                    "user": "test_user",
                    "password": "test_pass",
                    "database": "test_db"
                }
            }
        }

        with patch('httpx.AsyncClient', return_value=mock_httpx_client):
            result = await vault_client.get_secret("postgres", key="user")

            assert result == {"user": "test_user"}
            assert "password" not in result
            assert "database" not in result

    @pytest.mark.asyncio
    async def test_get_secret_404_raises_not_found(self, vault_client, vault_404_response):
        """Test that 404 response raises ResourceNotFoundError"""
        mock_client = AsyncMock()
        mock_client.get.return_value = vault_404_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            with pytest.raises(ResourceNotFoundError) as exc_info:
                await vault_client.get_secret("nonexistent")

            assert exc_info.value.resource_type == "secret"
            assert exc_info.value.resource_id == "nonexistent"
            assert "not found" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_get_secret_403_raises_vault_unavailable(self, vault_client, vault_403_response):
        """Test that 403 response raises VaultUnavailableError"""
        mock_client = AsyncMock()
        mock_client.get.return_value = vault_403_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            with pytest.raises(VaultUnavailableError) as exc_info:
                await vault_client.get_secret("test")

            assert "permission denied" in str(exc_info.value).lower()
            assert exc_info.value.details["status_code"] == 403

    @pytest.mark.asyncio
    async def test_get_secret_key_not_found_raises_error(self, vault_client, mock_httpx_client):
        """Test that requesting non-existent key raises ResourceNotFoundError"""
        mock_httpx_client.get.return_value.json.return_value = {
            "data": {
                "data": {
                    "user": "test_user",
                    "password": "test_pass"
                }
            }
        }

        with patch('httpx.AsyncClient', return_value=mock_httpx_client):
            with pytest.raises(ResourceNotFoundError) as exc_info:
                await vault_client.get_secret("postgres", key="nonexistent_key")

            assert exc_info.value.resource_type == "secret_key"
            assert "nonexistent_key" in exc_info.value.resource_id

    @pytest.mark.asyncio
    async def test_get_secret_timeout_raises_vault_unavailable(self, vault_client):
        """Test that timeout raises VaultUnavailableError"""
        mock_client = AsyncMock()
        mock_client.get.side_effect = httpx.TimeoutException("Timeout")
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            with pytest.raises(VaultUnavailableError) as exc_info:
                await vault_client.get_secret("test")

            assert "timeout" in str(exc_info.value).lower()
            assert exc_info.value.details["timeout"] == "5.0s"

    @pytest.mark.asyncio
    async def test_get_secret_connection_error_raises_vault_unavailable(self, vault_client):
        """Test that connection error raises VaultUnavailableError"""
        mock_client = AsyncMock()
        mock_client.get.side_effect = httpx.ConnectError("Connection refused")
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            with pytest.raises(VaultUnavailableError) as exc_info:
                await vault_client.get_secret("test")

            assert "cannot connect" in str(exc_info.value).lower()
            assert "vault_address" in exc_info.value.details

    @pytest.mark.asyncio
    async def test_get_secret_http_error_raises_vault_unavailable(self, vault_client):
        """Test that HTTP error raises VaultUnavailableError"""
        mock_client = AsyncMock()
        mock_response = MagicMock()
        mock_response.status_code = 500
        mock_response.raise_for_status.side_effect = httpx.HTTPStatusError(
            "Server error",
            request=MagicMock(),
            response=mock_response
        )
        mock_client.get.return_value = mock_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            with pytest.raises(VaultUnavailableError) as exc_info:
                await vault_client.get_secret("test")

            assert "vault returned an error" in str(exc_info.value).lower()

    @pytest.mark.asyncio
    async def test_get_secret_unexpected_error_raises_vault_unavailable(self, vault_client):
        """Test that unexpected errors raise VaultUnavailableError"""
        mock_client = AsyncMock()
        mock_client.get.side_effect = Exception("Unexpected error")
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            with pytest.raises(VaultUnavailableError) as exc_info:
                await vault_client.get_secret("test")

            assert "unexpected error" in str(exc_info.value).lower()


@pytest.mark.unit
class TestVaultClientCheckHealth:
    """Test VaultClient.check_health method"""

    @pytest.fixture
    def vault_client(self):
        """Create VaultClient instance"""
        return VaultClient()

    @pytest.mark.asyncio
    async def test_check_health_healthy(self, vault_client):
        """Test health check when Vault is healthy"""
        mock_client = AsyncMock()
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_client.get.return_value = mock_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            result = await vault_client.check_health()

            assert result["status"] == "healthy"
            assert result["initialized"] is True
            assert result["sealed"] is False

    @pytest.mark.asyncio
    async def test_check_health_sealed(self, vault_client):
        """Test health check when Vault is sealed"""
        mock_client = AsyncMock()
        mock_response = MagicMock()
        mock_response.status_code = 503
        mock_client.get.return_value = mock_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            result = await vault_client.check_health()

            assert result["status"] == "unhealthy"
            assert result["sealed"] is True

    @pytest.mark.asyncio
    async def test_check_health_not_initialized(self, vault_client):
        """Test health check when Vault is not initialized"""
        mock_client = AsyncMock()
        mock_response = MagicMock()
        mock_response.status_code = 501
        mock_client.get.return_value = mock_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            result = await vault_client.check_health()

            assert result["initialized"] is False

    @pytest.mark.asyncio
    async def test_check_health_standby(self, vault_client):
        """Test health check when Vault is in standby"""
        mock_client = AsyncMock()
        mock_response = MagicMock()
        mock_response.status_code = 429
        mock_client.get.return_value = mock_response
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            result = await vault_client.check_health()

            assert result["standby"] is True

    @pytest.mark.asyncio
    async def test_check_health_connection_error(self, vault_client):
        """Test health check when connection fails"""
        mock_client = AsyncMock()
        mock_client.get.side_effect = Exception("Connection failed")
        mock_client.__aenter__.return_value = mock_client
        mock_client.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_client):
            result = await vault_client.check_health()

            assert result["status"] == "unhealthy"
            assert "error" in result


@pytest.mark.unit
class TestVaultClientInitialization:
    """Test VaultClient initialization"""

    def test_vault_client_initializes_with_settings(self):
        """Test that VaultClient uses settings"""
        with patch('app.services.vault.settings') as mock_settings:
            mock_settings.VAULT_ADDR = "http://test-vault:8200"
            mock_settings.VAULT_TOKEN = "test-token"

            client = VaultClient()

            assert client.vault_addr == "http://test-vault:8200"
            assert client.vault_token == "test-token"
            assert client.headers["X-Vault-Token"] == "test-token"


@pytest.mark.integration
class TestVaultServiceIntegration:
    """Integration tests for Vault service"""

    @pytest.mark.asyncio
    async def test_vault_secret_retrieval_flow(self):
        """Test complete flow of secret retrieval"""
        client = VaultClient()

        # Mock the HTTP client to simulate successful retrieval
        mock_httpx = AsyncMock()
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "data": {
                "data": {
                    "user": "integration_test_user",
                    "password": "integration_test_pass",
                    "host": "localhost"
                }
            }
        }
        mock_response.raise_for_status = MagicMock()
        mock_httpx.get.return_value = mock_response
        mock_httpx.__aenter__.return_value = mock_httpx
        mock_httpx.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_httpx):
            # Get full secret
            secret = await client.get_secret("test")
            assert secret["user"] == "integration_test_user"
            assert secret["password"] == "integration_test_pass"
            assert secret["host"] == "localhost"

            # Get specific key
            user_only = await client.get_secret("test", key="user")
            assert user_only == {"user": "integration_test_user"}
            assert len(user_only) == 1

    @pytest.mark.asyncio
    async def test_vault_error_handling_flow(self):
        """Test complete flow of error handling"""
        client = VaultClient()

        # Test 404 -> ResourceNotFoundError
        mock_httpx = AsyncMock()
        mock_response = MagicMock()
        mock_response.status_code = 404
        mock_httpx.get.return_value = mock_response
        mock_httpx.__aenter__.return_value = mock_httpx
        mock_httpx.__aexit__.return_value = None

        with patch('httpx.AsyncClient', return_value=mock_httpx):
            with pytest.raises(ResourceNotFoundError):
                await client.get_secret("nonexistent")

        # Test timeout -> VaultUnavailableError
        mock_httpx.get.side_effect = httpx.TimeoutException("Timeout")

        with patch('httpx.AsyncClient', return_value=mock_httpx):
            with pytest.raises(VaultUnavailableError) as exc_info:
                await client.get_secret("test")
            assert "timeout" in str(exc_info.value).lower()
