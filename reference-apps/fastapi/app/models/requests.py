"""
Request validation models

Defines Pydantic models for request validation with:
- Input sanitization
- Type validation
- Size limits
- Pattern matching
- Custom validators
"""

from pydantic import BaseModel, Field, field_validator, ConfigDict
from typing import Dict, Any, Optional
import re


class ServiceNameParam(BaseModel):
    """Validation for service name path parameters"""

    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(
        ...,
        min_length=1,
        max_length=50,
        description="Service name (alphanumeric, hyphens, underscores only)",
        examples=["postgres", "mysql", "redis-1"]
    )

    @field_validator('name')
    @classmethod
    def validate_service_name(cls, v: str) -> str:
        """Validate service name contains only allowed characters"""
        if not re.match(r'^[a-zA-Z0-9_-]+$', v):
            raise ValueError(
                'Service name must contain only alphanumeric characters, hyphens, and underscores'
            )
        return v.lower()


class CacheKeyParam(BaseModel):
    """Validation for cache key path parameters"""

    model_config = ConfigDict(str_strip_whitespace=True)

    key: str = Field(
        ...,
        min_length=1,
        max_length=200,
        description="Cache key (no special characters except: - _ : .)",
        examples=["user:123", "session_abc", "data.config"]
    )

    @field_validator('key')
    @classmethod
    def validate_cache_key(cls, v: str) -> str:
        """Validate cache key contains only allowed characters"""
        if not re.match(r'^[a-zA-Z0-9_:.-]+$', v):
            raise ValueError(
                'Cache key must contain only alphanumeric characters and: - _ : .'
            )
        return v


class QueueNameParam(BaseModel):
    """Validation for queue name parameters"""

    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Queue name (alphanumeric, hyphens, underscores, dots only)",
        examples=["task-queue", "notifications", "data.processing"]
    )

    @field_validator('name')
    @classmethod
    def validate_queue_name(cls, v: str) -> str:
        """Validate queue name contains only allowed characters"""
        if not re.match(r'^[a-zA-Z0-9_.-]+$', v):
            raise ValueError(
                'Queue name must contain only alphanumeric characters and: - _ .'
            )
        return v


class CacheSetRequest(BaseModel):
    """Request model for setting cache values"""

    model_config = ConfigDict(str_strip_whitespace=True)

    value: str = Field(
        ...,
        min_length=0,
        max_length=10000,
        description="Value to cache (max 10KB)",
        examples=["cached data", '{"key": "value"}']
    )

    ttl: Optional[int] = Field(
        None,
        ge=1,
        le=86400,  # Max 24 hours
        description="Time to live in seconds (1 second to 24 hours)",
        examples=[60, 3600, 86400]
    )

    @field_validator('ttl')
    @classmethod
    def validate_ttl(cls, v: Optional[int]) -> Optional[int]:
        """Ensure TTL is reasonable if provided"""
        if v is not None and v <= 0:
            raise ValueError('TTL must be positive')
        return v


class MessagePublishRequest(BaseModel):
    """Request model for publishing messages to RabbitMQ"""

    model_config = ConfigDict(str_strip_whitespace=True)

    message: Dict[str, Any] = Field(
        ...,
        description="Message payload (JSON object, max 1MB)",
        examples=[{"event": "user.created", "user_id": 123}]
    )

    @field_validator('message')
    @classmethod
    def validate_message_size(cls, v: Dict[str, Any]) -> Dict[str, Any]:
        """Validate message is not too large"""
        import json
        message_size = len(json.dumps(v))

        if message_size > 1_000_000:  # 1MB limit
            raise ValueError(f'Message size ({message_size} bytes) exceeds 1MB limit')

        if not v:
            raise ValueError('Message cannot be empty')

        return v


class SecretKeyParam(BaseModel):
    """Validation for secret key path parameters"""

    model_config = ConfigDict(str_strip_whitespace=True)

    key: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="Secret key name (alphanumeric, hyphens, underscores only)",
        examples=["password", "api_key", "database-url"]
    )

    @field_validator('key')
    @classmethod
    def validate_secret_key(cls, v: str) -> str:
        """Validate secret key contains only allowed characters"""
        if not re.match(r'^[a-zA-Z0-9_-]+$', v):
            raise ValueError(
                'Secret key must contain only alphanumeric characters, hyphens, and underscores'
            )
        return v.lower()
