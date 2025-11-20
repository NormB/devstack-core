"""
Secure logging utilities to prevent sensitive data exposure and log injection attacks.
"""

from typing import Any, Dict, Set
from urllib.parse import urlparse, urlunparse


# Sensitive field names that should be redacted in logs
SENSITIVE_KEYS: Set[str] = {
    'password', 'secret', 'token', 'key', 'auth',
    'credential', 'api_key', 'private', 'passwd',
    'pwd', 'authorization', 'x-vault-token'
}


def redact_sensitive(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Redact sensitive fields from dict for safe logging.

    Args:
        data: Dictionary that may contain sensitive data

    Returns:
        Dictionary with sensitive values replaced with '[REDACTED]'

    Example:
        >>> redact_sensitive({'user': 'admin', 'password': 'secret123'})
        {'user': 'admin', 'password': '[REDACTED]'}
    """
    if not isinstance(data, dict):
        return data

    result = {}
    for key, value in data.items():
        key_lower = key.lower()

        # Check if key contains any sensitive keyword
        if any(sensitive in key_lower for sensitive in SENSITIVE_KEYS):
            result[key] = '[REDACTED]'
        elif isinstance(value, dict):
            # Recursively redact nested dicts
            result[key] = redact_sensitive(value)
        elif isinstance(value, list):
            # Handle lists of dicts
            result[key] = [redact_sensitive(item) if isinstance(item, dict) else item
                          for item in value]
        else:
            result[key] = value

    return result


def sanitize_log_string(value: str) -> str:
    """
    Sanitize string to prevent log injection attacks.

    Replaces control characters (newlines, carriage returns, tabs) that could
    be used to inject fake log entries or break log parsing.

    Args:
        value: String to sanitize

    Returns:
        Sanitized string with control characters escaped

    Example:
        >>> sanitize_log_string("user\\nERROR: fake log entry")
        'user\\\\nERROR: fake log entry'
    """
    if not isinstance(value, str):
        return str(value)

    return (value
            .replace('\n', '\\n')
            .replace('\r', '\\r')
            .replace('\t', '\\t')
            .replace('\x00', '\\x00'))  # Null byte


def redact_url_password(url: str) -> str:
    """
    Redact password from URL for safe logging.

    Removes username and password from URLs while preserving the connection
    information (scheme, host, port, path).

    Args:
        url: URL that may contain credentials

    Returns:
        URL with credentials redacted

    Example:
        >>> redact_url_password("redis://:password@localhost:6379/0")
        'redis://localhost:6379/0'
        >>> redact_url_password("postgresql://user:pass@db:5432/mydb")
        'postgresql://[REDACTED]@db:5432/mydb'
    """
    if not url:
        return url

    try:
        parsed = urlparse(url)

        # If there's no username or password, return as-is
        if not parsed.username and not parsed.password:
            return url

        # Reconstruct URL without credentials
        # Replace netloc (which contains user:pass@host:port) with just host:port
        safe_netloc = parsed.hostname or ''
        if parsed.port:
            safe_netloc = f"{safe_netloc}:{parsed.port}"

        # Reconstruct the URL
        safe_url = urlunparse((
            parsed.scheme,
            safe_netloc,
            parsed.path,
            parsed.params,
            parsed.query,
            parsed.fragment
        ))

        return safe_url

    except Exception:
        # If URL parsing fails, return a generic safe message
        return "[REDACTED_URL]"
