"""
Circuit breaker middleware for external service calls

Implements circuit breakers to prevent cascading failures when external services
(Vault, databases, message queues) are unavailable.

Circuit Breaker States:
- CLOSED: Normal operation, requests pass through
- OPEN: Too many failures, requests fail immediately
- HALF_OPEN: Testing if service recovered, limited requests pass through

Configuration:
- fail_max: 5 failures trigger circuit to open
- reset_timeout: 60 seconds before attempting recovery (time circuit stays open)
- listeners: Callbacks for circuit state changes and metrics
"""

import pybreaker
import logging
from typing import Callable, Any
from functools import wraps
from prometheus_client import Counter

logger = logging.getLogger(__name__)

# Prometheus metrics for circuit breaker events
circuit_breaker_opened = Counter(
    'circuit_breaker_opened_total',
    'Total times circuit breaker opened',
    ['service']
)

circuit_breaker_half_open = Counter(
    'circuit_breaker_half_open_total',
    'Total times circuit breaker entered half-open state',
    ['service']
)

circuit_breaker_closed = Counter(
    'circuit_breaker_closed_total',
    'Total times circuit breaker closed',
    ['service']
)

circuit_breaker_failures = Counter(
    'circuit_breaker_failures_total',
    'Total failures recorded by circuit breaker',
    ['service']
)


def on_circuit_open(service_name: str):
    """Called when circuit breaker opens"""
    def listener(cb):
        logger.warning(f"Circuit breaker OPENED for {service_name}")
        circuit_breaker_opened.labels(service=service_name).inc()
    return listener


def on_circuit_half_open(service_name: str):
    """Called when circuit breaker enters half-open state"""
    def listener(cb):
        logger.info(f"Circuit breaker HALF-OPEN for {service_name}")
        circuit_breaker_half_open.labels(service=service_name).inc()
    return listener


def on_circuit_close(service_name: str):
    """Called when circuit breaker closes"""
    def listener(cb):
        logger.info(f"Circuit breaker CLOSED for {service_name}")
        circuit_breaker_closed.labels(service=service_name).inc()
    return listener


def on_circuit_failure(service_name: str):
    """Called on each failure"""
    def listener(cb):
        circuit_breaker_failures.labels(service=service_name).inc()
    return listener


# Create circuit breakers for each external service
vault_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=60,
    name="vault",
    listeners=[
        on_circuit_open("vault"),
        on_circuit_half_open("vault"),
        on_circuit_close("vault"),
        on_circuit_failure("vault")
    ]
)

postgres_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=60,
    name="postgres",
    listeners=[
        on_circuit_open("postgres"),
        on_circuit_half_open("postgres"),
        on_circuit_close("postgres"),
        on_circuit_failure("postgres")
    ]
)

mysql_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=60,
    name="mysql",
    listeners=[
        on_circuit_open("mysql"),
        on_circuit_half_open("mysql"),
        on_circuit_close("mysql"),
        on_circuit_failure("mysql")
    ]
)

mongodb_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=60,
    name="mongodb",
    listeners=[
        on_circuit_open("mongodb"),
        on_circuit_half_open("mongodb"),
        on_circuit_close("mongodb"),
        on_circuit_failure("mongodb")
    ]
)

redis_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=60,
    name="redis",
    listeners=[
        on_circuit_open("redis"),
        on_circuit_half_open("redis"),
        on_circuit_close("redis"),
        on_circuit_failure("redis")
    ]
)

rabbitmq_breaker = pybreaker.CircuitBreaker(
    fail_max=5,
    reset_timeout=60,
    name="rabbitmq",
    listeners=[
        on_circuit_open("rabbitmq"),
        on_circuit_half_open("rabbitmq"),
        on_circuit_close("rabbitmq"),
        on_circuit_failure("rabbitmq")
    ]
)


def with_circuit_breaker(breaker: pybreaker.CircuitBreaker):
    """
    Decorator to wrap functions with circuit breaker protection

    Usage:
        @with_circuit_breaker(vault_breaker)
        async def call_vault():
            # Vault API call
            pass
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs) -> Any:
            # Create a synchronous wrapper for the async function
            async def async_call():
                return await func(*args, **kwargs)

            try:
                # Use pybreaker's call() method with a sync wrapper that runs the async code
                import asyncio
                result = breaker.call(lambda: asyncio.create_task(async_call()))
                # Wait for the task to complete
                if asyncio.iscoroutine(result) or asyncio.isfuture(result) or asyncio.istask(result):
                    return await result
                return result
            except pybreaker.CircuitBreakerError as e:
                logger.error(f"Circuit breaker {breaker.name} is OPEN: {str(e)}")
                raise ServiceUnavailableError(
                    f"{breaker.name.capitalize()} service is temporarily unavailable"
                )
        return wrapper
    return decorator


class ServiceUnavailableError(Exception):
    """Raised when a service is unavailable due to circuit breaker"""
    pass
