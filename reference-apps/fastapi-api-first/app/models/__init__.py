"""
Data models for FastAPI application (API-First)

Provides Pydantic models for request/response validation and serialization.
Combines generated models from OpenAPI spec with custom request/response models.
"""

# Generated models from OpenAPI specification
from .generated import (
    CacheDeleteResponse,
    CacheGetResponse,
    CacheSetResponse,
    MessagePublishResponse,
    QueueInfoResponse,
    SecretKeyResponse,
    SecretResponse,
    HTTPValidationError,
    ValidationError
)

# Custom request/response models from code-first
from .requests import (
    CacheSetRequest,
    MessagePublishRequest,
    QueueNameParam,
    ServiceNameParam,
    CacheKeyParam
)

from .responses import (
    DatabaseQueryResponse,
    ErrorResponse
)

__all__ = [
    # Generated models (from OpenAPI)
    'CacheDeleteResponse',
    'CacheGetResponse',
    'CacheSetResponse',
    'MessagePublishResponse',
    'QueueInfoResponse',
    'SecretKeyResponse',
    'SecretResponse',
    'HTTPValidationError',
    'ValidationError',
    # Request models
    'CacheSetRequest',
    'MessagePublishRequest',
    'QueueNameParam',
    'ServiceNameParam',
    'CacheKeyParam',
    # Response models
    'DatabaseQueryResponse',
    'ErrorResponse'
]
