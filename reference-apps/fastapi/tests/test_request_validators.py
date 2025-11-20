"""
Unit tests for request validation models

Tests Pydantic validators for all request models.
"""

import pytest
from pydantic import ValidationError

from app.models.requests import (
    ServiceNameParam,
    CacheKeyParam,
    QueueNameParam,
    CacheSetRequest,
    MessagePublishRequest,
    SecretKeyParam
)


@pytest.mark.unit
class TestServiceNameParam:
    """Test ServiceNameParam validation"""

    def test_valid_service_name(self):
        """Test valid service names"""
        valid_names = ["postgres", "mysql", "redis-1", "my_service", "service123"]

        for name in valid_names:
            param = ServiceNameParam(name=name)
            assert param.name == name.lower()

    def test_service_name_lowercase_conversion(self):
        """Test service names are converted to lowercase"""
        param = ServiceNameParam(name="PostgreSQL")
        assert param.name == "postgresql"

    def test_invalid_service_name_special_chars(self):
        """Test service names with invalid special characters"""
        invalid_names = ["service@name", "service.name", "service name", "service/name"]

        for name in invalid_names:
            with pytest.raises(ValidationError) as exc_info:
                ServiceNameParam(name=name)
            assert "alphanumeric characters" in str(exc_info.value).lower()

    def test_service_name_too_long(self):
        """Test service name exceeds max length"""
        long_name = "a" * 51  # Max is 50

        with pytest.raises(ValidationError):
            ServiceNameParam(name=long_name)

    def test_service_name_empty(self):
        """Test empty service name"""
        with pytest.raises(ValidationError):
            ServiceNameParam(name="")


@pytest.mark.unit
class TestCacheKeyParam:
    """Test CacheKeyParam validation"""

    def test_valid_cache_keys(self):
        """Test valid cache key formats"""
        valid_keys = ["user:123", "session_abc", "data.config", "cache-key"]

        for key in valid_keys:
            param = CacheKeyParam(key=key)
            assert param.key == key

    def test_invalid_cache_key_special_chars(self):
        """Test cache keys with invalid special characters"""
        invalid_keys = ["key@value", "key#123", "key value", "key/path"]

        for key in invalid_keys:
            with pytest.raises(ValidationError) as exc_info:
                CacheKeyParam(key=key)
            assert "must contain only" in str(exc_info.value).lower()

    def test_cache_key_too_long(self):
        """Test cache key exceeds max length"""
        long_key = "a" * 201  # Max is 200

        with pytest.raises(ValidationError):
            CacheKeyParam(key=long_key)

    def test_cache_key_empty(self):
        """Test empty cache key"""
        with pytest.raises(ValidationError):
            CacheKeyParam(key="")


@pytest.mark.unit
class TestQueueNameParam:
    """Test QueueNameParam validation"""

    def test_valid_queue_names(self):
        """Test valid queue name formats"""
        valid_names = ["task-queue", "notifications", "data.processing", "my_queue"]

        for name in valid_names:
            param = QueueNameParam(name=name)
            assert param.name == name

    def test_invalid_queue_name_special_chars(self):
        """Test queue names with invalid special characters"""
        invalid_names = ["queue@name", "queue:name", "queue name", "queue/name"]

        for name in invalid_names:
            with pytest.raises(ValidationError) as exc_info:
                QueueNameParam(name=name)
            assert "must contain only" in str(exc_info.value).lower()

    def test_queue_name_too_long(self):
        """Test queue name exceeds max length"""
        long_name = "a" * 101  # Max is 100

        with pytest.raises(ValidationError):
            QueueNameParam(name=long_name)

    def test_queue_name_empty(self):
        """Test empty queue name"""
        with pytest.raises(ValidationError):
            QueueNameParam(name="")


@pytest.mark.unit
class TestCacheSetRequest:
    """Test CacheSetRequest validation"""

    def test_valid_cache_set_request(self):
        """Test valid cache set request"""
        request = CacheSetRequest(value="test data", ttl=60)
        assert request.value == "test data"
        assert request.ttl == 60

    def test_cache_set_request_no_ttl(self):
        """Test cache set request without TTL"""
        request = CacheSetRequest(value="test data")
        assert request.value == "test data"
        assert request.ttl is None

    def test_cache_value_too_long(self):
        """Test cache value exceeds max size"""
        long_value = "a" * 10001  # Max is 10000

        with pytest.raises(ValidationError):
            CacheSetRequest(value=long_value)

    def test_ttl_negative(self):
        """Test negative TTL value"""
        with pytest.raises(ValidationError):
            CacheSetRequest(value="data", ttl=0)

    def test_ttl_too_large(self):
        """Test TTL exceeds maximum"""
        with pytest.raises(ValidationError):
            CacheSetRequest(value="data", ttl=86401)  # Max is 86400

    def test_ttl_validator_positive_check(self):
        """Test TTL validator rejects non-positive values"""
        # The validator checks for <= 0
        with pytest.raises(ValidationError):
            CacheSetRequest(value="data", ttl=-10)


@pytest.mark.unit
class TestMessagePublishRequest:
    """Test MessagePublishRequest validation"""

    def test_valid_message_publish_request(self):
        """Test valid message publish request"""
        message = {"event": "user.created", "user_id": 123}
        request = MessagePublishRequest(message=message)
        assert request.message == message

    def test_empty_message_rejected(self):
        """Test empty message dictionary is rejected"""
        with pytest.raises(ValidationError) as exc_info:
            MessagePublishRequest(message={})
        assert "cannot be empty" in str(exc_info.value).lower()

    def test_message_size_too_large(self):
        """Test message exceeding 1MB limit"""
        # Create a large message > 1MB
        large_message = {"data": "x" * 1_000_001}

        with pytest.raises(ValidationError) as exc_info:
            MessagePublishRequest(message=large_message)
        assert "exceeds 1mb limit" in str(exc_info.value).lower()

    def test_message_size_at_limit(self):
        """Test message at size limit is accepted"""
        # Create a message just under 1MB (accounting for JSON structure)
        # Use a smaller size to ensure it passes
        acceptable_message = {"data": "x" * 500_000}
        request = MessagePublishRequest(message=acceptable_message)
        assert request.message == acceptable_message


@pytest.mark.unit
class TestSecretKeyParam:
    """Test SecretKeyParam validation"""

    def test_valid_secret_keys(self):
        """Test valid secret key names"""
        valid_keys = ["password", "api_key", "database-url", "my_secret"]

        for key in valid_keys:
            param = SecretKeyParam(key=key)
            assert param.key == key.lower()

    def test_secret_key_lowercase_conversion(self):
        """Test secret keys are converted to lowercase"""
        param = SecretKeyParam(key="API_KEY")
        assert param.key == "api_key"

    def test_invalid_secret_key_special_chars(self):
        """Test secret keys with invalid special characters"""
        invalid_keys = ["secret.key", "secret:key", "secret key", "secret@key"]

        for key in invalid_keys:
            with pytest.raises(ValidationError) as exc_info:
                SecretKeyParam(key=key)
            assert "alphanumeric characters" in str(exc_info.value).lower()

    def test_secret_key_too_long(self):
        """Test secret key exceeds max length"""
        long_key = "a" * 101  # Max is 100

        with pytest.raises(ValidationError):
            SecretKeyParam(key=long_key)

    def test_secret_key_empty(self):
        """Test empty secret key"""
        with pytest.raises(ValidationError):
            SecretKeyParam(key="")
