"""
Middleware package for FastAPI application
"""

from .circuit_breaker import (
    vault_breaker,
    postgres_breaker,
    mysql_breaker,
    mongodb_breaker,
    redis_breaker,
    rabbitmq_breaker,
    with_circuit_breaker,
    ServiceUnavailableError
)

__all__ = [
    'vault_breaker',
    'postgres_breaker',
    'mysql_breaker',
    'mongodb_breaker',
    'redis_breaker',
    'rabbitmq_breaker',
    'with_circuit_breaker',
    'ServiceUnavailableError'
]
