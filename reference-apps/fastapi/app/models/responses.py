"""
Response validation models

Defines Pydantic models for API responses to ensure:
- Consistent response structure
- Type safety
- Auto-generated OpenAPI schema documentation
"""

from pydantic import BaseModel, Field
from typing import Dict, Any, Optional, Union


class ErrorResponse(BaseModel):
    """Standard error response"""
    detail: str = Field(..., description="Error message")


class SecretResponse(BaseModel):
    """Response for secret retrieval"""
    service: str = Field(..., description="Service name")
    data: Dict[str, Any] = Field(..., description="Secret data (passwords masked)")
    note: str = Field(..., description="Additional information")


class SecretKeyResponse(BaseModel):
    """Response for specific secret key retrieval"""
    service: str = Field(..., description="Service name")
    key: str = Field(..., description="Secret key name")
    value: Optional[str] = Field(None, description="Secret value (sensitive values masked)")
    note: str = Field(..., description="Additional information")


class DatabaseQueryResponse(BaseModel):
    """Response for database query examples"""
    database: str = Field(..., description="Database type", examples=["PostgreSQL", "MySQL", "MongoDB"])
    query: Optional[str] = Field(None, description="Query executed")
    result: Union[str, Dict[str, Any], list] = Field(..., description="Query result")
    collections: Optional[list] = Field(None, description="MongoDB collections (MongoDB only)")
    count: Optional[int] = Field(None, description="Collection count (MongoDB only)")


class CacheGetResponse(BaseModel):
    """Response for cache get operations"""
    key: str = Field(..., description="Cache key")
    value: Optional[str] = Field(None, description="Cached value (null if not found)")
    exists: bool = Field(..., description="Whether key exists in cache")
    ttl: Union[int, str, None] = Field(None, description="Time to live in seconds or 'no expiration'")


class CacheSetResponse(BaseModel):
    """Response for cache set operations"""
    key: str = Field(..., description="Cache key")
    value: str = Field(..., description="Value that was set")
    ttl: Optional[int] = Field(None, description="Time to live in seconds (null if no expiration)")
    action: str = Field("set", description="Action performed")


class CacheDeleteResponse(BaseModel):
    """Response for cache delete operations"""
    key: str = Field(..., description="Cache key")
    deleted: bool = Field(..., description="Whether key was deleted")
    action: str = Field("delete", description="Action performed")


class MessagePublishResponse(BaseModel):
    """Response for message publishing"""
    queue: str = Field(..., description="Queue name")
    message: Dict[str, Any] = Field(..., description="Message that was published")
    action: str = Field("published", description="Action performed")


class QueueInfoResponse(BaseModel):
    """Response for queue information"""
    queue: str = Field(..., description="Queue name")
    exists: bool = Field(..., description="Whether queue exists")
    message_count: Optional[int] = Field(None, description="Number of messages in queue")
    consumer_count: Optional[int] = Field(None, description="Number of consumers")
