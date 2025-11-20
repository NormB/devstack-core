"""
Global exception handlers for the FastAPI application

Registers handlers for all custom exceptions and common errors.
Provides consistent error responses with proper logging and monitoring.

Features:
- Structured error responses
- Automatic logging of errors
- Prometheus metrics for error tracking
- Request ID correlation
- Debug mode support
"""

import logging
from fastapi import Request, status
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from prometheus_client import Counter
import traceback

from app.exceptions import (
    BaseAPIException,
    ServiceUnavailableError,
    VaultUnavailableError,
    DatabaseConnectionError,
    CacheConnectionError,
    MessageQueueError,
    CircuitBreakerError
)
from app.config import settings

logger = logging.getLogger(__name__)

# Prometheus metrics for error tracking
error_counter = Counter(
    'http_errors_total',
    'Total HTTP errors',
    ['error_type', 'status_code']
)


def get_request_id(request: Request) -> str:
    """Extract request ID from request state"""
    return getattr(request.state, 'request_id', 'unknown')


async def base_api_exception_handler(request: Request, exc: BaseAPIException) -> JSONResponse:
    """
    Handler for all custom API exceptions.

    Logs the error with request context and returns a structured JSON response.
    """
    request_id = get_request_id(request)

    # Log the error
    logger.error(
        f"{exc.__class__.__name__}: {exc.message}",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": str(request.url.path),
            "status_code": exc.status_code,
            "error_type": exc.__class__.__name__,
            "error_details": exc.details
        }
    )

    # Track error metric
    error_counter.labels(
        error_type=exc.__class__.__name__,
        status_code=exc.status_code
    ).inc()

    # Build response
    response_data = exc.to_dict()
    response_data["request_id"] = request_id

    # Add stack trace in debug mode
    if settings.DEBUG:
        response_data["debug"] = {
            "traceback": traceback.format_exc()
        }

    return JSONResponse(
        status_code=exc.status_code,
        content=response_data,
        headers={"X-Request-ID": request_id}
    )


async def service_unavailable_handler(request: Request, exc: ServiceUnavailableError) -> JSONResponse:
    """
    Handler for service unavailable errors.

    Provides additional context about which service is down and suggests retry.
    """
    request_id = get_request_id(request)

    logger.error(
        f"Service unavailable: {exc.service_name} - {exc.message}",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": str(request.url.path),
            "service": exc.service_name,
            "error_details": exc.details
        }
    )

    error_counter.labels(
        error_type=exc.__class__.__name__,
        status_code=exc.status_code
    ).inc()

    response_data = exc.to_dict()
    response_data["request_id"] = request_id
    response_data["retry_suggestion"] = "Please try again later or contact support if the issue persists"

    return JSONResponse(
        status_code=exc.status_code,
        content=response_data,
        headers={"X-Request-ID": request_id}
    )


async def validation_error_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    """
    Handler for FastAPI request validation errors.

    Converts Pydantic validation errors to a consistent format.
    """
    request_id = get_request_id(request)

    logger.warning(
        f"Request validation failed: {exc}",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": str(request.url.path),
            "validation_errors": exc.errors()
        }
    )

    error_counter.labels(
        error_type="ValidationError",
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY
    ).inc()

    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content={
            "error": "ValidationError",
            "message": "Request validation failed",
            "status_code": status.HTTP_422_UNPROCESSABLE_ENTITY,
            "details": {
                "validation_errors": exc.errors()
            },
            "request_id": request_id
        },
        headers={"X-Request-ID": request_id}
    )


async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    """
    Handler for standard HTTP exceptions.

    Converts Starlette HTTP exceptions to consistent format.
    """
    request_id = get_request_id(request)

    logger.warning(
        f"HTTP exception: {exc.status_code} - {exc.detail}",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": str(request.url.path),
            "status_code": exc.status_code
        }
    )

    error_counter.labels(
        error_type="HTTPException",
        status_code=exc.status_code
    ).inc()

    return JSONResponse(
        status_code=exc.status_code,
        content={
            "error": "HTTPException",
            "message": exc.detail,
            "status_code": exc.status_code,
            "request_id": request_id
        },
        headers={"X-Request-ID": request_id}
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """
    Handler for all unhandled exceptions.

    Catches any exception not handled by specific handlers and
    provides a generic error response while logging details.
    """
    request_id = get_request_id(request)

    # Log with full traceback
    logger.error(
        f"Unhandled exception: {exc}",
        extra={
            "request_id": request_id,
            "method": request.method,
            "path": str(request.url.path),
            "exception_type": exc.__class__.__name__
        },
        exc_info=True
    )

    error_counter.labels(
        error_type=exc.__class__.__name__,
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR
    ).inc()

    response_data = {
        "error": "InternalServerError",
        "message": "An unexpected error occurred",
        "status_code": status.HTTP_500_INTERNAL_SERVER_ERROR,
        "request_id": request_id
    }

    # Include exception details in debug mode
    if settings.DEBUG:
        response_data["debug"] = {
            "exception_type": exc.__class__.__name__,
            "exception_message": str(exc),
            "traceback": traceback.format_exc()
        }

    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=response_data,
        headers={"X-Request-ID": request_id}
    )


def register_exception_handlers(app):
    """
    Register all exception handlers with the FastAPI application.

    Call this function during application startup.
    """
    # Custom exception handlers
    app.add_exception_handler(BaseAPIException, base_api_exception_handler)
    app.add_exception_handler(ServiceUnavailableError, service_unavailable_handler)
    app.add_exception_handler(VaultUnavailableError, service_unavailable_handler)
    app.add_exception_handler(DatabaseConnectionError, service_unavailable_handler)
    app.add_exception_handler(CacheConnectionError, service_unavailable_handler)
    app.add_exception_handler(MessageQueueError, service_unavailable_handler)
    app.add_exception_handler(CircuitBreakerError, service_unavailable_handler)

    # Standard exception handlers
    app.add_exception_handler(RequestValidationError, validation_error_handler)
    app.add_exception_handler(StarletteHTTPException, http_exception_handler)

    # Catch-all handler
    app.add_exception_handler(Exception, unhandled_exception_handler)

    logger.info("Exception handlers registered successfully")
