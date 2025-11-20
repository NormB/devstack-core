"""
Unit tests for custom exception classes

Tests the exception hierarchy, structure, and behavior of all custom exceptions.
"""

import pytest
from fastapi import status

from app.exceptions import (
    BaseAPIException,
    ServiceUnavailableError,
    VaultUnavailableError,
    DatabaseConnectionError,
    CacheConnectionError,
    MessageQueueError,
    ConfigurationError,
    ValidationError,
    ResourceNotFoundError,
    AuthenticationError,
    RateLimitError,
    CircuitBreakerError,
    TimeoutError
)


@pytest.mark.unit
@pytest.mark.exceptions
class TestBaseAPIException:
    """Test the base exception class"""

    def test_base_exception_creation(self):
        """Test creating a base API exception"""
        exc = BaseAPIException(
            message="Test error",
            status_code=500,
            details={"key": "value"}
        )
        assert exc.message == "Test error"
        assert exc.status_code == 500
        assert exc.details == {"key": "value"}

    def test_base_exception_default_details(self):
        """Test base exception with default details"""
        exc = BaseAPIException(message="Test error")
        assert exc.details == {}
        assert exc.status_code == 500

    def test_base_exception_to_dict(self):
        """Test converting exception to dictionary"""
        exc = BaseAPIException(
            message="Test error",
            status_code=400,
            details={"field": "test"}
        )
        result = exc.to_dict()
        assert result["error"] == "BaseAPIException"
        assert result["message"] == "Test error"
        assert result["status_code"] == 400
        assert result["details"]["field"] == "test"

    def test_base_exception_str(self):
        """Test string representation"""
        exc = BaseAPIException(message="Test error")
        assert str(exc) == "Test error"


@pytest.mark.unit
@pytest.mark.exceptions
class TestServiceUnavailableError:
    """Test ServiceUnavailableError and its subclasses"""

    def test_service_unavailable_error(self):
        """Test generic service unavailable error"""
        exc = ServiceUnavailableError(service_name="test-service")
        assert exc.service_name == "test-service"
        assert exc.status_code == status.HTTP_503_SERVICE_UNAVAILABLE
        assert "test-service" in exc.message
        assert exc.details["service"] == "test-service"

    def test_service_unavailable_custom_message(self):
        """Test service unavailable with custom message"""
        exc = ServiceUnavailableError(
            service_name="test-service",
            message="Custom error message"
        )
        assert exc.message == "Custom error message"
        assert exc.details["service"] == "test-service"

    def test_vault_unavailable_error(self):
        """Test Vault unavailable error"""
        exc = VaultUnavailableError(
            message="Vault is down",
            secret_path="secret/test"
        )
        assert exc.service_name == "vault"
        assert exc.message == "Vault is down"
        assert exc.details["secret_path"] == "secret/test"
        assert exc.status_code == status.HTTP_503_SERVICE_UNAVAILABLE

    def test_vault_unavailable_default_message(self):
        """Test Vault unavailable with default message"""
        exc = VaultUnavailableError()
        assert "Vault service is unavailable" in exc.message

    def test_database_connection_error(self):
        """Test database connection error"""
        exc = DatabaseConnectionError(
            database_type="postgres",
            message="Connection failed"
        )
        assert exc.database_type == "postgres"
        assert exc.message == "Connection failed"
        assert exc.details["database_type"] == "postgres"
        assert exc.status_code == status.HTTP_503_SERVICE_UNAVAILABLE

    def test_cache_connection_error(self):
        """Test cache connection error"""
        exc = CacheConnectionError(message="Redis connection failed")
        assert exc.service_name == "redis"
        assert exc.message == "Redis connection failed"

    def test_message_queue_error(self):
        """Test message queue error"""
        exc = MessageQueueError(
            message="Queue publish failed",
            queue_name="test-queue"
        )
        assert exc.service_name == "rabbitmq"
        assert exc.details["queue_name"] == "test-queue"


@pytest.mark.unit
@pytest.mark.exceptions
class TestConfigurationError:
    """Test ConfigurationError"""

    def test_configuration_error(self):
        """Test configuration error"""
        exc = ConfigurationError(
            message="Missing config",
            config_key="DATABASE_URL"
        )
        assert exc.config_key == "DATABASE_URL"
        assert exc.message == "Missing config"
        assert exc.details["config_key"] == "DATABASE_URL"
        assert exc.status_code == status.HTTP_500_INTERNAL_SERVER_ERROR


@pytest.mark.unit
@pytest.mark.exceptions
class TestValidationError:
    """Test ValidationError"""

    def test_validation_error(self):
        """Test validation error"""
        exc = ValidationError(
            message="Invalid input",
            field="email"
        )
        assert exc.field == "email"
        assert exc.message == "Invalid input"
        assert exc.details["field"] == "email"
        assert exc.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY


@pytest.mark.unit
@pytest.mark.exceptions
class TestResourceNotFoundError:
    """Test ResourceNotFoundError"""

    def test_resource_not_found(self):
        """Test resource not found error"""
        exc = ResourceNotFoundError(
            resource_type="secret",
            resource_id="postgres"
        )
        assert exc.resource_type == "secret"
        assert exc.resource_id == "postgres"
        assert "secret" in exc.message
        assert "postgres" in exc.message
        assert exc.status_code == status.HTTP_404_NOT_FOUND

    def test_resource_not_found_custom_message(self):
        """Test resource not found with custom message"""
        exc = ResourceNotFoundError(
            resource_type="user",
            resource_id="123",
            message="User not found in database"
        )
        assert exc.message == "User not found in database"
        assert exc.details["resource_type"] == "user"
        assert exc.details["resource_id"] == "123"


@pytest.mark.unit
@pytest.mark.exceptions
class TestAuthenticationError:
    """Test AuthenticationError"""

    def test_authentication_error(self):
        """Test authentication error"""
        exc = AuthenticationError()
        assert exc.message == "Authentication failed"
        assert exc.status_code == status.HTTP_401_UNAUTHORIZED

    def test_authentication_error_custom_message(self):
        """Test authentication error with custom message"""
        exc = AuthenticationError(message="Invalid token")
        assert exc.message == "Invalid token"


@pytest.mark.unit
@pytest.mark.exceptions
class TestRateLimitError:
    """Test RateLimitError"""

    def test_rate_limit_error(self):
        """Test rate limit error"""
        exc = RateLimitError()
        assert exc.message == "Rate limit exceeded"
        assert exc.status_code == status.HTTP_429_TOO_MANY_REQUESTS

    def test_rate_limit_error_with_retry_after(self):
        """Test rate limit error with retry_after"""
        exc = RateLimitError(
            message="Too many requests",
            retry_after=60
        )
        assert exc.retry_after == 60
        assert exc.details["retry_after"] == 60


@pytest.mark.unit
@pytest.mark.exceptions
class TestCircuitBreakerError:
    """Test CircuitBreakerError"""

    def test_circuit_breaker_error(self):
        """Test circuit breaker error"""
        exc = CircuitBreakerError(service_name="postgres")
        assert exc.service_name == "postgres"
        assert "postgres" in exc.message
        assert "circuit breaker" in exc.message.lower()
        assert exc.status_code == status.HTTP_503_SERVICE_UNAVAILABLE


@pytest.mark.unit
@pytest.mark.exceptions
class TestTimeoutError:
    """Test TimeoutError"""

    def test_timeout_error(self):
        """Test timeout error"""
        exc = TimeoutError(
            operation="database_query",
            timeout_seconds=5.0
        )
        assert exc.operation == "database_query"
        assert exc.timeout_seconds == 5.0
        assert "database_query" in exc.message
        assert "5.0" in exc.message
        assert exc.status_code == status.HTTP_504_GATEWAY_TIMEOUT

    def test_timeout_error_custom_message(self):
        """Test timeout error with custom message"""
        exc = TimeoutError(
            operation="api_call",
            timeout_seconds=10.0,
            message="External API timeout"
        )
        assert exc.message == "External API timeout"
        assert exc.details["operation"] == "api_call"
        assert exc.details["timeout_seconds"] == 10.0


@pytest.mark.unit
@pytest.mark.exceptions
class TestExceptionHierarchy:
    """Test exception inheritance and hierarchy"""

    def test_all_custom_exceptions_inherit_from_base(self):
        """Test that all custom exceptions inherit from BaseAPIException"""
        exceptions = [
            ServiceUnavailableError("test"),
            VaultUnavailableError(),
            DatabaseConnectionError("postgres"),
            CacheConnectionError(),
            MessageQueueError(),
            ConfigurationError("test"),
            ValidationError("test"),
            ResourceNotFoundError("type", "id"),
            AuthenticationError(),
            RateLimitError(),
            CircuitBreakerError("service"),
            TimeoutError("op", 5.0)
        ]

        for exc in exceptions:
            assert isinstance(exc, BaseAPIException)
            assert isinstance(exc, Exception)

    def test_service_exceptions_inherit_from_service_unavailable(self):
        """Test that service-specific exceptions inherit from ServiceUnavailableError"""
        service_exceptions = [
            VaultUnavailableError(),
            DatabaseConnectionError("postgres"),
            CacheConnectionError(),
            MessageQueueError()
            # Note: CircuitBreakerError intentionally inherits from BaseAPIException
            # not ServiceUnavailableError, as it's a protective measure, not a service error
        ]

        for exc in service_exceptions:
            assert isinstance(exc, ServiceUnavailableError)
            assert isinstance(exc, BaseAPIException)


@pytest.mark.unit
class TestExceptionHelpers:
    """Test exception helper methods"""

    def test_base_exception_to_dict(self):
        """Test base exception to_dict method"""
        exc = BaseAPIException(message="Test error", status_code=400)
        result = exc.to_dict()

        assert result["error"] == "BaseAPIException"
        assert result["message"] == "Test error"
        assert result["status_code"] == 400

    def test_vault_error_to_dict_includes_service(self):
        """Test VaultUnavailableError includes service details"""
        exc = VaultUnavailableError(secret_path="test/secret")
        result = exc.to_dict()

        assert result["details"]["service"] == "vault"
        assert result["details"]["secret_path"] == "test/secret"

    def test_database_error_to_dict_includes_database(self):
        """Test DatabaseConnectionError includes database name"""
        exc = DatabaseConnectionError("postgres", details={"host": "localhost"})
        result = exc.to_dict()

        assert result["details"]["database_type"] == "postgres"
        assert result["details"]["host"] == "localhost"

    def test_resource_not_found_error_details(self):
        """Test ResourceNotFoundError includes resource details"""
        exc = ResourceNotFoundError(resource_type="user", resource_id="123")
        result = exc.to_dict()

        assert result["details"]["resource_type"] == "user"
        assert result["details"]["resource_id"] == "123"

    def test_rate_limit_error_includes_retry_after(self):
        """Test RateLimitError includes retry_after"""
        exc = RateLimitError(
            message="Too many requests",
            retry_after=30,
            details={"limit": 100, "window": 60}
        )
        result = exc.to_dict()

        assert result["details"]["limit"] == 100
        assert result["details"]["window"] == 60
        assert result["details"]["retry_after"] == 30

    def test_timeout_error_includes_timeout_value(self):
        """Test TimeoutError includes timeout value"""
        exc = TimeoutError(operation="fetch_data", timeout_seconds=5.0)
        result = exc.to_dict()

        assert result["details"]["operation"] == "fetch_data"
        assert result["details"]["timeout_seconds"] == 5.0
