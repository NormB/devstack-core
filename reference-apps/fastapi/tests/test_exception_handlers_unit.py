"""
Direct unit tests for exception handler functions

Tests handler functions directly without going through the FastAPI app.
"""

import pytest
from unittest.mock import MagicMock, patch
from fastapi import Request, status
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.middleware.exception_handlers import (
    base_api_exception_handler,
    service_unavailable_handler,
    validation_error_handler,
    http_exception_handler,
    unhandled_exception_handler,
    get_request_id
)
from app.exceptions import (
    BaseAPIException,
    ServiceUnavailableError,
    VaultUnavailableError,
    DatabaseConnectionError
)


@pytest.fixture
def mock_request():
    """Create a mock request object"""
    request = MagicMock(spec=Request)
    request.state = MagicMock()
    request.state.request_id = "test-request-123"
    request.method = "GET"
    request.url.path = "/test/endpoint"
    return request


@pytest.fixture
def mock_request_no_id():
    """Create a mock request without request_id"""
    request = MagicMock(spec=Request)
    request.state = MagicMock()
    # No request_id attribute
    del request.state.request_id
    request.method = "POST"
    request.url.path = "/api/test"
    return request


@pytest.mark.unit
@pytest.mark.asyncio
class TestGetRequestId:
    """Test get_request_id helper function"""

    async def test_get_request_id_exists(self, mock_request):
        """Test extracting request ID when it exists"""
        result = get_request_id(mock_request)
        assert result == "test-request-123"

    async def test_get_request_id_missing(self, mock_request_no_id):
        """Test default request ID when missing"""
        result = get_request_id(mock_request_no_id)
        assert result == "unknown"


@pytest.mark.unit
@pytest.mark.asyncio
class TestBaseAPIExceptionHandler:
    """Test base API exception handler"""

    async def test_handler_returns_json_response(self, mock_request):
        """Test handler returns proper JSON response"""
        exc = BaseAPIException(
            message="Test error",
            status_code=500,
            details={"key": "value"}
        )

        response = await base_api_exception_handler(mock_request, exc)

        assert response.status_code == 500
        data = response.body.decode()
        assert "Test error" in data
        assert "test-request-123" in data

    async def test_handler_includes_request_id(self, mock_request):
        """Test handler includes request ID in response"""
        exc = BaseAPIException(message="Error", status_code=400)

        response = await base_api_exception_handler(mock_request, exc)

        assert response.headers["X-Request-ID"] == "test-request-123"

    @patch('app.middleware.exception_handlers.settings')
    async def test_handler_includes_debug_info_when_debug_enabled(
        self, mock_settings, mock_request
    ):
        """Test handler includes debug info when DEBUG=True"""
        mock_settings.DEBUG = True
        exc = BaseAPIException(message="Debug error", status_code=500)

        response = await base_api_exception_handler(mock_request, exc)

        data = response.body.decode()
        assert "debug" in data
        assert "traceback" in data

    @patch('app.middleware.exception_handlers.settings')
    async def test_handler_excludes_debug_info_when_debug_disabled(
        self, mock_settings, mock_request
    ):
        """Test handler excludes debug info when DEBUG=False"""
        mock_settings.DEBUG = False
        exc = BaseAPIException(message="Production error", status_code=500)

        response = await base_api_exception_handler(mock_request, exc)

        data = response.body.decode()
        # Check that debug is not in the response (comparing strings since body is bytes)
        assert "traceback" not in data.lower() or "debug" not in data

    @patch('app.middleware.exception_handlers.error_counter')
    async def test_handler_increments_metrics(self, mock_counter, mock_request):
        """Test handler increments Prometheus metrics"""
        exc = BaseAPIException(message="Metric test", status_code=404)

        await base_api_exception_handler(mock_request, exc)

        mock_counter.labels.assert_called_once_with(
            error_type="BaseAPIException",
            status_code=404
        )
        mock_counter.labels.return_value.inc.assert_called_once()


@pytest.mark.unit
@pytest.mark.asyncio
class TestServiceUnavailableHandler:
    """Test service unavailable exception handler"""

    async def test_handler_returns_503(self, mock_request):
        """Test handler returns 503 status code"""
        exc = ServiceUnavailableError(
            service_name="postgres",
            message="Database is down"
        )

        response = await service_unavailable_handler(mock_request, exc)

        assert response.status_code == status.HTTP_503_SERVICE_UNAVAILABLE

    async def test_handler_includes_retry_suggestion(self, mock_request):
        """Test handler includes retry suggestion"""
        exc = VaultUnavailableError(message="Vault is sealed")

        response = await service_unavailable_handler(mock_request, exc)

        data = response.body.decode()
        assert "retry_suggestion" in data
        assert "try again later" in data.lower()

    async def test_handler_includes_service_name(self, mock_request):
        """Test handler includes service name in response"""
        exc = DatabaseConnectionError(
            database_type="mysql",
            message="Connection failed"
        )

        response = await service_unavailable_handler(mock_request, exc)

        data = response.body.decode()
        assert "mysql" in data

    @patch('app.middleware.exception_handlers.error_counter')
    async def test_handler_increments_metrics(self, mock_counter, mock_request):
        """Test handler increments Prometheus metrics"""
        exc = ServiceUnavailableError(service_name="redis")

        await service_unavailable_handler(mock_request, exc)

        mock_counter.labels.assert_called_once()
        mock_counter.labels.return_value.inc.assert_called_once()


@pytest.mark.unit
@pytest.mark.asyncio
class TestValidationErrorHandler:
    """Test validation error handler"""

    async def test_handler_returns_422(self, mock_request):
        """Test handler returns 422 status code"""
        # Create a mock RequestValidationError
        exc = MagicMock(spec=RequestValidationError)
        exc.errors.return_value = [
            {
                "loc": ["body", "field"],
                "msg": "field required",
                "type": "value_error.missing"
            }
        ]

        response = await validation_error_handler(mock_request, exc)

        assert response.status_code == status.HTTP_422_UNPROCESSABLE_ENTITY

    async def test_handler_includes_validation_errors(self, mock_request):
        """Test handler includes validation error details"""
        exc = MagicMock(spec=RequestValidationError)
        exc.errors.return_value = [
            {
                "loc": ["query", "limit"],
                "msg": "value is not a valid integer",
                "type": "type_error.integer"
            }
        ]

        response = await validation_error_handler(mock_request, exc)

        data = response.body.decode()
        assert "validation_errors" in data
        assert "limit" in data

    @patch('app.middleware.exception_handlers.error_counter')
    async def test_handler_increments_metrics(self, mock_counter, mock_request):
        """Test handler increments Prometheus metrics"""
        exc = MagicMock(spec=RequestValidationError)
        exc.errors.return_value = []

        await validation_error_handler(mock_request, exc)

        mock_counter.labels.assert_called_once_with(
            error_type="ValidationError",
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY
        )


@pytest.mark.unit
@pytest.mark.asyncio
class TestHTTPExceptionHandler:
    """Test HTTP exception handler"""

    async def test_handler_returns_correct_status_code(self, mock_request):
        """Test handler returns the exception's status code"""
        exc = StarletteHTTPException(status_code=404, detail="Not found")

        response = await http_exception_handler(mock_request, exc)

        assert response.status_code == 404

    async def test_handler_includes_exception_detail(self, mock_request):
        """Test handler includes exception detail in response"""
        exc = StarletteHTTPException(status_code=403, detail="Forbidden resource")

        response = await http_exception_handler(mock_request, exc)

        data = response.body.decode()
        assert "Forbidden resource" in data

    @patch('app.middleware.exception_handlers.error_counter')
    async def test_handler_increments_metrics(self, mock_counter, mock_request):
        """Test handler increments Prometheus metrics"""
        exc = StarletteHTTPException(status_code=401, detail="Unauthorized")

        await http_exception_handler(mock_request, exc)

        mock_counter.labels.assert_called_once_with(
            error_type="HTTPException",
            status_code=401
        )


@pytest.mark.unit
@pytest.mark.asyncio
class TestUnhandledExceptionHandler:
    """Test unhandled exception handler"""

    async def test_handler_returns_500(self, mock_request):
        """Test handler returns 500 for unhandled exceptions"""
        exc = Exception("Unexpected error")

        response = await unhandled_exception_handler(mock_request, exc)

        assert response.status_code == status.HTTP_500_INTERNAL_SERVER_ERROR

    async def test_handler_includes_generic_message(self, mock_request):
        """Test handler includes generic error message"""
        exc = ValueError("Some internal error")

        response = await unhandled_exception_handler(mock_request, exc)

        data = response.body.decode()
        assert "unexpected error occurred" in data.lower()

    @patch('app.middleware.exception_handlers.settings')
    async def test_handler_includes_debug_info_when_debug_enabled(
        self, mock_settings, mock_request
    ):
        """Test handler includes exception details in debug mode"""
        mock_settings.DEBUG = True
        exc = RuntimeError("Debug this error")

        response = await unhandled_exception_handler(mock_request, exc)

        data = response.body.decode()
        assert "debug" in data
        assert "RuntimeError" in data

    @patch('app.middleware.exception_handlers.settings')
    async def test_handler_excludes_debug_info_when_debug_disabled(
        self, mock_settings, mock_request
    ):
        """Test handler excludes exception details in production"""
        mock_settings.DEBUG = False
        exc = RuntimeError("Production error")

        response = await unhandled_exception_handler(mock_request, exc)

        data = response.body.decode()
        # Should not include specific exception details
        assert "RuntimeError" not in data or "debug" not in data.lower()

    @patch('app.middleware.exception_handlers.error_counter')
    async def test_handler_increments_metrics(self, mock_counter, mock_request):
        """Test handler increments Prometheus metrics"""
        exc = ZeroDivisionError("Division by zero")

        await unhandled_exception_handler(mock_request, exc)

        mock_counter.labels.assert_called_once_with(
            error_type="ZeroDivisionError",
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR
        )
