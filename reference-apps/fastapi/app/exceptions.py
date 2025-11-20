"""
Custom exception classes for the FastAPI application

Provides a structured exception hierarchy for better error handling and
more informative error messages. All custom exceptions inherit from
BaseAPIException for consistent handling.

Exception Hierarchy:
- BaseAPIException (base for all custom exceptions)
  - ServiceUnavailableError (external service failures)
    - VaultUnavailableError
    - DatabaseConnectionError
    - CacheConnectionError
    - MessageQueueError
  - ConfigurationError (configuration/setup issues)
  - ValidationError (request validation failures)
  - ResourceNotFoundError (resource doesn't exist)
  - AuthenticationError (auth failures)
  - RateLimitError (rate limiting)
  - CircuitBreakerError (circuit breaker open)
"""

from typing import Optional, Dict, Any
from fastapi import status


class BaseAPIException(Exception):
    """
    Base exception class for all custom API exceptions.

    Provides consistent structure for error responses including:
    - HTTP status code
    - Error message
    - Additional context/details
    """

    def __init__(
        self,
        message: str,
        status_code: int = status.HTTP_500_INTERNAL_SERVER_ERROR,
        details: Optional[Dict[str, Any]] = None
    ):
        self.message = message
        self.status_code = status_code
        self.details = details or {}
        super().__init__(self.message)

    def to_dict(self) -> Dict[str, Any]:
        """Convert exception to dictionary for JSON response"""
        response = {
            "error": self.__class__.__name__,
            "message": self.message,
            "status_code": self.status_code
        }
        if self.details:
            response["details"] = self.details
        return response


class ServiceUnavailableError(BaseAPIException):
    """
    Raised when an external service is unavailable or unreachable.

    Examples:
    - Vault server not responding
    - Database connection failed
    - Redis cluster unavailable
    - RabbitMQ connection refused
    """

    def __init__(
        self,
        service_name: str,
        message: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.service_name = service_name
        msg = message or f"Service '{service_name}' is currently unavailable"
        super().__init__(
            message=msg,
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            details={"service": service_name, **(details or {})}
        )


class VaultUnavailableError(ServiceUnavailableError):
    """
    Raised when Vault is unavailable or returns an error.

    Examples:
    - Cannot connect to Vault server
    - Vault is sealed
    - Authentication failed
    - Secret not found
    """

    def __init__(
        self,
        message: Optional[str] = None,
        secret_path: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        msg = message or "Vault service is unavailable"
        error_details = details or {}
        if secret_path:
            error_details["secret_path"] = secret_path
        super().__init__(
            service_name="vault",
            message=msg,
            details=error_details
        )


class DatabaseConnectionError(ServiceUnavailableError):
    """
    Raised when database connection fails.

    Examples:
    - Cannot connect to database server
    - Authentication failed
    - Database doesn't exist
    - Connection timeout
    """

    def __init__(
        self,
        database_type: str,
        message: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.database_type = database_type
        msg = message or f"Failed to connect to {database_type} database"
        error_details = {"database_type": database_type, **(details or {})}
        super().__init__(
            service_name=database_type,
            message=msg,
            details=error_details
        )


class CacheConnectionError(ServiceUnavailableError):
    """
    Raised when cache service (Redis) connection fails.

    Examples:
    - Cannot connect to Redis
    - Authentication failed
    - Cluster not ready
    """

    def __init__(
        self,
        message: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        msg = message or "Failed to connect to cache service"
        super().__init__(
            service_name="redis",
            message=msg,
            details=details
        )


class MessageQueueError(ServiceUnavailableError):
    """
    Raised when message queue (RabbitMQ) operations fail.

    Examples:
    - Cannot connect to RabbitMQ
    - Queue declaration failed
    - Message publish failed
    """

    def __init__(
        self,
        message: Optional[str] = None,
        queue_name: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        msg = message or "Message queue operation failed"
        error_details = details or {}
        if queue_name:
            error_details["queue_name"] = queue_name
        super().__init__(
            service_name="rabbitmq",
            message=msg,
            details=error_details
        )


class ConfigurationError(BaseAPIException):
    """
    Raised when there's a configuration or setup issue.

    Examples:
    - Missing environment variable
    - Invalid configuration value
    - Service not properly initialized
    """

    def __init__(
        self,
        message: str,
        config_key: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.config_key = config_key
        error_details = details or {}
        if config_key:
            error_details["config_key"] = config_key
        super().__init__(
            message=message,
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            details=error_details
        )


class ValidationError(BaseAPIException):
    """
    Raised when request validation fails.

    Examples:
    - Invalid parameter format
    - Missing required field
    - Value out of range
    """

    def __init__(
        self,
        message: str,
        field: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.field = field
        error_details = details or {}
        if field:
            error_details["field"] = field
        super().__init__(
            message=message,
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            details=error_details
        )


class ResourceNotFoundError(BaseAPIException):
    """
    Raised when a requested resource doesn't exist.

    Examples:
    - Secret not found in Vault
    - Database record doesn't exist
    - Cache key not found
    """

    def __init__(
        self,
        resource_type: str,
        resource_id: str,
        message: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.resource_type = resource_type
        self.resource_id = resource_id
        msg = message or f"{resource_type} '{resource_id}' not found"
        error_details = {
            "resource_type": resource_type,
            "resource_id": resource_id,
            **(details or {})
        }
        super().__init__(
            message=msg,
            status_code=status.HTTP_404_NOT_FOUND,
            details=error_details
        )


class AuthenticationError(BaseAPIException):
    """
    Raised when authentication fails.

    Examples:
    - Invalid API key
    - Token expired
    - Insufficient permissions
    """

    def __init__(
        self,
        message: str = "Authentication failed",
        details: Optional[Dict[str, Any]] = None
    ):
        super().__init__(
            message=message,
            status_code=status.HTTP_401_UNAUTHORIZED,
            details=details
        )


class RateLimitError(BaseAPIException):
    """
    Raised when rate limit is exceeded.

    Examples:
    - Too many requests from IP
    - API quota exceeded
    """

    def __init__(
        self,
        message: str = "Rate limit exceeded",
        retry_after: Optional[int] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.retry_after = retry_after
        error_details = details or {}
        if retry_after:
            error_details["retry_after"] = retry_after
        super().__init__(
            message=message,
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            details=error_details
        )


class CircuitBreakerError(ServiceUnavailableError):
    """
    Raised when circuit breaker is open (preventing calls to failing service).

    Examples:
    - Service has failed too many times
    - Circuit breaker protecting downstream service
    """

    def __init__(
        self,
        service_name: str,
        message: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        # Don't set self.service_name here - parent class handles it
        msg = message or f"Circuit breaker open for service '{service_name}'"
        error_details = {"service": service_name, **(details or {})}
        super().__init__(
            message=msg,
            service_name=service_name,
            details=error_details
        )


class TimeoutError(BaseAPIException):
    """
    Raised when an operation times out.

    Examples:
    - Database query timeout
    - API request timeout
    - Cache operation timeout
    """

    def __init__(
        self,
        operation: str,
        timeout_seconds: float,
        message: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ):
        self.operation = operation
        self.timeout_seconds = timeout_seconds
        msg = message or f"Operation '{operation}' timed out after {timeout_seconds}s"
        error_details = {
            "operation": operation,
            "timeout_seconds": timeout_seconds,
            **(details or {})
        }
        super().__init__(
            message=msg,
            status_code=status.HTTP_504_GATEWAY_TIMEOUT,
            details=error_details
        )
