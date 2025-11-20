"""
Response validation models (API-First)

Additional response models not generated from OpenAPI specification.
Most response models are auto-generated in generated.py from the OpenAPI spec.

This file contains only custom models not present in the OpenAPI specification.
"""

from pydantic import BaseModel, Field
from typing import Dict, Any, Optional, Union


class ErrorResponse(BaseModel):
    """Standard error response"""
    detail: str = Field(..., description="Error message")


class DatabaseQueryResponse(BaseModel):
    """Response for database query examples"""
    database: str = Field(..., description="Database type", examples=["PostgreSQL", "MySQL", "MongoDB"])
    query: Optional[str] = Field(None, description="Query executed")
    result: Union[str, Dict[str, Any], list] = Field(..., description="Query result")
    collections: Optional[list] = Field(None, description="MongoDB collections (MongoDB only)")
    count: Optional[int] = Field(None, description="Collection count (MongoDB only)")
