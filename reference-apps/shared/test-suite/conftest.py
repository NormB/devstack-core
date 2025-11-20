"""
Shared Test Suite - Pytest Configuration

Provides fixtures and configuration for testing both API implementations
to ensure they behave identically.
"""

import pytest
import httpx
import os


# API Base URLs
CODE_FIRST_URL = os.getenv("CODE_FIRST_API_URL", "http://localhost:8000")
API_FIRST_URL = os.getenv("API_FIRST_API_URL", "http://localhost:8001")


@pytest.fixture(params=[CODE_FIRST_URL, API_FIRST_URL], ids=["code-first", "api-first"])
def api_url(request):
    """
    Parametrized fixture that provides URLs for both implementations.

    Tests using this fixture will run twice:
    1. Against code-first implementation (localhost:8000)
    2. Against API-first implementation (localhost:8001)
    """
    return request.param


@pytest.fixture
async def http_client():
    """
    Async HTTP client for making requests to APIs.
    """
    async with httpx.AsyncClient(timeout=10.0) as client:
        yield client


@pytest.fixture
def code_first_url():
    """Fixture providing code-first API URL."""
    return CODE_FIRST_URL


@pytest.fixture
def api_first_url():
    """Fixture providing API-first API URL."""
    return API_FIRST_URL


@pytest.fixture
async def both_api_urls():
    """
    Fixture providing both API URLs for comparison tests.

    Returns dict: {"code-first": url1, "api-first": url2}
    """
    return {
        "code-first": CODE_FIRST_URL,
        "api-first": API_FIRST_URL
    }


def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line(
        "markers", "parity: Tests that validate both implementations behave identically"
    )
    config.addinivalue_line(
        "markers", "comparison: Tests that directly compare responses from both APIs"
    )
    config.addinivalue_line(
        "markers", "health: Health check tests"
    )
    config.addinivalue_line(
        "markers", "integration: Integration tests requiring running services"
    )
