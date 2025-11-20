"""
Configuration management for the reference application (API-First)

Loads settings from environment variables with sensible defaults
for the DevStack Core infrastructure.

This configuration is shared between code-first and API-first implementations.
"""

import os
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings"""

    # Application
    DEBUG: bool = os.getenv("DEBUG", "false").lower() == "true"
    APP_NAME: str = "DevStack Core Reference API (API-First)"

    # Vault
    VAULT_ADDR: str = os.getenv("VAULT_ADDR", "http://vault:8200")
    VAULT_TOKEN: str = os.getenv("VAULT_TOKEN", "")
    VAULT_APPROLE_DIR: str = os.getenv("VAULT_APPROLE_DIR", "/vault-approles/api-first")

    # Service endpoints (internal Docker network)
    POSTGRES_HOST: str = os.getenv("POSTGRES_HOST", "postgres")
    POSTGRES_PORT: int = int(os.getenv("POSTGRES_PORT", "5432"))

    MYSQL_HOST: str = os.getenv("MYSQL_HOST", "mysql")
    MYSQL_PORT: int = int(os.getenv("MYSQL_PORT", "3306"))

    MONGODB_HOST: str = os.getenv("MONGODB_HOST", "mongodb")
    MONGODB_PORT: int = int(os.getenv("MONGODB_PORT", "27017"))

    REDIS_HOST: str = os.getenv("REDIS_HOST", "redis-1")
    REDIS_PORT: int = int(os.getenv("REDIS_PORT", "6379"))

    RABBITMQ_HOST: str = os.getenv("RABBITMQ_HOST", "rabbitmq")
    RABBITMQ_PORT: int = int(os.getenv("RABBITMQ_PORT", "5672"))

    # Redis Cluster nodes
    REDIS_NODES: str = os.getenv("REDIS_NODES", "redis-1:6379,redis-2:6379,redis-3:6379")

    class Config:
        env_file = ".env"
        case_sensitive = True


settings = Settings()
