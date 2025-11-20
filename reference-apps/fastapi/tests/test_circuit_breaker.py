"""
Unit tests for circuit breaker middleware

Tests the circuit breaker functionality using pybreaker library.
"""

import pytest
from unittest.mock import MagicMock
import pybreaker

from app.middleware.circuit_breaker import (
    on_circuit_open,
    on_circuit_half_open,
    on_circuit_close,
    on_circuit_failure,
    circuit_breaker_opened,
    circuit_breaker_half_open,
    circuit_breaker_closed,
    circuit_breaker_failures
)


@pytest.mark.unit
class TestCircuitBreakerListeners:
    """Test circuit breaker listener functions"""

    def test_on_circuit_open_listener(self):
        """Test circuit open listener"""
        listener = on_circuit_open("test_service")

        mock_cb = MagicMock()
        listener(mock_cb)

        # Should log warning and increment metric
        # Check metric was incremented
        initial = circuit_breaker_opened.labels(service="test_service")._value.get()
        listener(mock_cb)
        final = circuit_breaker_opened.labels(service="test_service")._value.get()
        assert final > initial

    def test_on_circuit_half_open_listener(self):
        """Test circuit half-open listener"""
        listener = on_circuit_half_open("test_service")

        mock_cb = MagicMock()
        initial = circuit_breaker_half_open.labels(service="test_service")._value.get()

        listener(mock_cb)

        final = circuit_breaker_half_open.labels(service="test_service")._value.get()
        assert final > initial

    def test_on_circuit_close_listener(self):
        """Test circuit close listener"""
        listener = on_circuit_close("test_service")

        mock_cb = MagicMock()
        initial = circuit_breaker_closed.labels(service="test_service")._value.get()

        listener(mock_cb)

        final = circuit_breaker_closed.labels(service="test_service")._value.get()
        assert final > initial

    def test_on_circuit_failure_listener(self):
        """Test circuit failure listener"""
        listener = on_circuit_failure("test_service")

        mock_cb = MagicMock()
        initial = circuit_breaker_failures.labels(service="test_service")._value.get()

        listener(mock_cb)

        final = circuit_breaker_failures.labels(service="test_service")._value.get()
        assert final > initial


@pytest.mark.unit
class TestCircuitBreakerMetrics:
    """Test circuit breaker Prometheus metrics"""

    def test_circuit_breaker_metrics_exist(self):
        """Test that circuit breaker metrics are defined"""
        assert circuit_breaker_opened is not None
        assert circuit_breaker_half_open is not None
        assert circuit_breaker_closed is not None
        assert circuit_breaker_failures is not None

    def test_metrics_have_service_label(self):
        """Test that metrics can be labeled by service"""
        # Should not raise error
        circuit_breaker_opened.labels(service="vault")
        circuit_breaker_half_open.labels(service="postgres")
        circuit_breaker_closed.labels(service="redis")
        circuit_breaker_failures.labels(service="rabbitmq")


@pytest.mark.unit
class TestCircuitBreakerBehavior:
    """Test circuit breaker behavior using pybreaker"""

    def test_circuit_breaker_creation(self):
        """Test creating a circuit breaker"""
        cb = pybreaker.CircuitBreaker(
            fail_max=3,
            reset_timeout=10
        )

        assert cb.fail_max == 3
        assert cb.reset_timeout == 10
        assert cb.current_state == "closed"

    def test_circuit_breaker_opens_after_failures(self):
        """Test circuit breaker opens after threshold"""
        cb = pybreaker.CircuitBreaker(fail_max=2, reset_timeout=60)

        def failing_function():
            raise Exception("Service unavailable")

        # First failure
        with pytest.raises(Exception):
            cb.call(failing_function)

        assert cb.current_state == "closed"

        # Second failure - should open circuit
        with pytest.raises(Exception):
            cb.call(failing_function)

        assert cb.current_state == "open"

    def test_circuit_breaker_prevents_calls_when_open(self):
        """Test that open circuit breaker prevents calls"""
        cb = pybreaker.CircuitBreaker(fail_max=1, reset_timeout=60)

        def failing_function():
            raise Exception("Service unavailable")

        # Trigger circuit to open
        with pytest.raises(Exception):
            cb.call(failing_function)

        assert cb.current_state == "open"

        # Next call should fail fast with CircuitBreakerError
        with pytest.raises(pybreaker.CircuitBreakerError):
            cb.call(failing_function)

    def test_circuit_breaker_allows_success(self):
        """Test circuit breaker allows successful calls"""
        cb = pybreaker.CircuitBreaker(fail_max=3, reset_timeout=10)

        def successful_function():
            return "success"

        result = cb.call(successful_function)

        assert result == "success"
        assert cb.current_state == "closed"


@pytest.mark.integration
class TestCircuitBreakerIntegration:
    """Integration tests for circuit breaker middleware"""

    def test_circuit_breaker_middleware_integration(self):
        """Test circuit breaker middleware with actual app"""
        # This would require full app integration
        pass
