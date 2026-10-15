"""
Tests that error responses never expose exception text or tracebacks.

The handlers return a generic message plus the request ID. Exception
details and tracebacks go to the server-side log only, in every mode,
including DEBUG=True.
"""

import json
import logging
from unittest.mock import MagicMock, patch

import pytest
from fastapi import Request

from app.exceptions import BaseAPIException
from app.middleware.exception_handlers import (
    base_api_exception_handler,
    unhandled_exception_handler,
)

LEAK_TEXT = "internal-detail-7f3a db-host=10.9.8.7"
TRACEBACK_MARKER = "Traceback (most recent call last)"


@pytest.fixture
def mock_request():
    request = MagicMock(spec=Request)
    request.state = MagicMock()
    request.state.request_id = "req-no-leak-1"
    request.method = "GET"
    request.url.path = "/leak/check"
    return request


async def _call_while_handling(handler, request, exc):
    """Raise exc and call the handler inside the except block, as Starlette does."""
    try:
        raise exc
    except Exception as caught:
        return await handler(request, caught)


@pytest.mark.unit
@pytest.mark.parametrize("debug", [True, False])
class TestUnhandledExceptionResponseHasNoDetail:
    async def test_body_has_no_exception_text_or_traceback(self, mock_request, debug):
        with patch("app.middleware.exception_handlers.settings") as mock_settings:
            mock_settings.DEBUG = debug
            response = await _call_while_handling(
                unhandled_exception_handler, mock_request, RuntimeError(LEAK_TEXT)
            )

        body = response.body.decode()
        assert LEAK_TEXT not in body
        assert "RuntimeError" not in body
        assert TRACEBACK_MARKER not in body
        assert "traceback" not in body.lower()
        assert "debug" not in body.lower()

    async def test_body_keeps_documented_schema(self, mock_request, debug):
        with patch("app.middleware.exception_handlers.settings") as mock_settings:
            mock_settings.DEBUG = debug
            response = await _call_while_handling(
                unhandled_exception_handler, mock_request, RuntimeError(LEAK_TEXT)
            )

        assert response.status_code == 500
        assert response.headers["X-Request-ID"] == "req-no-leak-1"
        assert json.loads(response.body) == {
            "error": "InternalServerError",
            "message": "An unexpected error occurred",
            "status_code": 500,
            "request_id": "req-no-leak-1",
        }

    async def test_detail_is_logged_server_side(self, mock_request, debug, caplog):
        with patch("app.middleware.exception_handlers.settings") as mock_settings:
            mock_settings.DEBUG = debug
            with caplog.at_level(logging.ERROR):
                await _call_while_handling(
                    unhandled_exception_handler, mock_request, RuntimeError(LEAK_TEXT)
                )

        records = [r for r in caplog.records if LEAK_TEXT in r.getMessage()]
        assert records, "exception text must reach the server-side log"
        assert records[0].exc_info is not None
        assert records[0].request_id == "req-no-leak-1"


@pytest.mark.unit
@pytest.mark.parametrize("debug", [True, False])
class TestBaseAPIExceptionResponseHasNoTraceback:
    async def test_body_has_no_traceback(self, mock_request, debug):
        exc = BaseAPIException(message="Public message", status_code=503)
        with patch("app.middleware.exception_handlers.settings") as mock_settings:
            mock_settings.DEBUG = debug
            response = await _call_while_handling(
                base_api_exception_handler, mock_request, exc
            )

        body = response.body.decode()
        assert TRACEBACK_MARKER not in body
        assert "traceback" not in body.lower()
        assert '"debug"' not in body
        assert "_call_while_handling" not in body

    async def test_body_keeps_documented_schema(self, mock_request, debug):
        exc = BaseAPIException(
            message="Public message", status_code=503, details={"service": "vault"}
        )
        with patch("app.middleware.exception_handlers.settings") as mock_settings:
            mock_settings.DEBUG = debug
            response = await _call_while_handling(
                base_api_exception_handler, mock_request, exc
            )

        expected = exc.to_dict()
        expected["request_id"] = "req-no-leak-1"
        assert response.status_code == 503
        assert response.headers["X-Request-ID"] == "req-no-leak-1"
        assert json.loads(response.body) == expected

    async def test_traceback_is_logged_server_side_in_debug(
        self, mock_request, debug, caplog
    ):
        exc = BaseAPIException(message="Public message", status_code=503)
        with patch("app.middleware.exception_handlers.settings") as mock_settings:
            mock_settings.DEBUG = debug
            with caplog.at_level(logging.ERROR):
                await _call_while_handling(
                    base_api_exception_handler, mock_request, exc
                )

        records = [r for r in caplog.records if "Public message" in r.getMessage()]
        assert records
        if debug:
            assert records[0].exc_info is not None
