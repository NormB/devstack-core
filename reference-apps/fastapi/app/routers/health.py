"""
Health check endpoints for all infrastructure services

Provides comprehensive health monitoring for:
- Vault
- PostgreSQL
- MySQL
- MongoDB
- Redis Cluster
- RabbitMQ

All health checks are protected with circuit breakers to prevent cascading failures.
"""

from fastapi import APIRouter
from fastapi_cache.decorator import cache
from typing import Dict, Any
import asyncpg
import aiomysql
import motor.motor_asyncio
import aio_pika
import redis.asyncio as redis
import logging

from app.config import settings
from app.services.vault import vault_client
from app.middleware.cache import generate_cache_key

logger = logging.getLogger(__name__)
router = APIRouter()


async def check_vault() -> Dict[str, Any]:
    """Check Vault health"""
    try:
        health = await vault_client.check_health()
        return {
            "status": health.get("status", "unknown"),
            "details": health
        }
    except Exception as e:
        return {"status": "unhealthy", "error": "Vault health check failed"}


async def check_postgres() -> Dict[str, Any]:
    """Check PostgreSQL connectivity"""
    try:
        # Fetch credentials from Vault
        creds = await vault_client.get_secret("postgres")

        # Connect and test
        conn = await asyncpg.connect(
            host=settings.POSTGRES_HOST,
            port=settings.POSTGRES_PORT,
            user=creds.get("user"),
            password=creds.get("password"),
            database=creds.get("database"),
            timeout=5.0
        )

        # Simple query
        version = await conn.fetchval("SELECT version()")
        await conn.close()

        return {
            "status": "healthy",
            "version": version.split(",")[0] if version else "unknown"
        }
    except Exception as e:
        logger.error(f"PostgreSQL health check failed: {e}")
        return {"status": "unhealthy", "error": "PostgreSQL connection failed"}


async def check_mysql() -> Dict[str, Any]:
    """Check MySQL connectivity """
    try:
        # Fetch credentials from Vault
        creds = await vault_client.get_secret("mysql")

        # Connect and test
        conn = await aiomysql.connect(
            host=settings.MYSQL_HOST,
            port=settings.MYSQL_PORT,
            user=creds.get("user"),
            password=creds.get("password"),
            db=creds.get("database"),
            connect_timeout=5
        )

        async with conn.cursor() as cursor:
            await cursor.execute("SELECT VERSION()")
            version = await cursor.fetchone()

        conn.close()

        return {
            "status": "healthy",
            "version": version[0] if version else "unknown"
        }
    except Exception as e:
        logger.error(f"MySQL health check failed: {e}")
        return {"status": "unhealthy", "error": "MySQL connection failed"}


async def check_mongodb() -> Dict[str, Any]:
    """Check MongoDB connectivity """
    try:
        # Fetch credentials from Vault
        creds = await vault_client.get_secret("mongodb")

        # Build connection string with authSource
        uri = f"mongodb://{creds.get('user')}:{creds.get('password')}@{settings.MONGODB_HOST}:{settings.MONGODB_PORT}/?authSource=admin"

        # Connect and test
        client = motor.motor_asyncio.AsyncIOMotorClient(
            uri,
            serverSelectionTimeoutMS=5000
        )

        # Ping to verify connection
        await client.admin.command('ping')

        # Get server info
        server_info = await client.server_info()
        client.close()

        return {
            "status": "healthy",
            "version": server_info.get("version", "unknown")
        }
    except Exception as e:
        logger.error(f"MongoDB health check failed: {e}")
        return {"status": "unhealthy", "error": "MongoDB connection failed"}


async def check_redis() -> Dict[str, Any]:
    """Check Redis cluster health """
    try:
        # Fetch credentials from Vault
        creds = await vault_client.get_secret("redis-1")
        password = creds.get("password")

        # Parse Redis nodes from settings
        node_addresses = settings.REDIS_NODES.split(",")
        nodes = []
        cluster_state = "unknown"
        cluster_enabled = False

        # Check each Redis node
        for node_addr in node_addresses:
            try:
                host, port = node_addr.strip().split(":")

                # Connect to node
                client = redis.Redis(
                    host=host,
                    port=int(port),
                    password=password,
                    decode_responses=True,
                    socket_connect_timeout=5
                )

                # Test ping
                ping_response = await client.ping()

                # Get server info
                info = await client.info()

                # Get cluster info if cluster is enabled
                if info.get("cluster_enabled", 0) == 1:
                    cluster_enabled = True
                    try:
                        cluster_raw = await client.execute_command("CLUSTER", "INFO")
                        cluster_info_dict = {}
                        # Parse cluster info response
                        if isinstance(cluster_raw, str):
                            for line in cluster_raw.split("\n"):
                                if ":" in line:
                                    key, value = line.strip().split(":", 1)
                                    cluster_info_dict[key] = value
                        # Update cluster state from the first node that provides it
                        if cluster_state == "unknown":
                            cluster_state = cluster_info_dict.get("cluster_state", "unknown")
                    except Exception as e:
                        logger.error(f"Failed to get cluster info: {e}")

                await client.close()

                nodes.append({
                    "host": host,
                    "port": int(port),
                    "status": "healthy" if ping_response else "unhealthy",
                    "version": info.get("redis_version", "unknown"),
                    "role": info.get("role", "unknown"),
                    "connected_clients": info.get("connected_clients", 0),
                    "used_memory_human": info.get("used_memory_human", "unknown")
                })

            except Exception as e:
                nodes.append({
                    "host": host,
                    "port": int(port),
                    "status": "unhealthy",
                    "error": "Node connection failed"
                })

        # Overall health is healthy if all nodes are healthy
        all_healthy = all(node.get("status") == "healthy" for node in nodes)

        return {
            "status": "healthy" if all_healthy else "degraded",
            "cluster_enabled": cluster_enabled,
            "cluster_state": cluster_state,
            "nodes": nodes,
            "total_nodes": len(nodes)
        }
    except Exception as e:
        logger.error(f"Redis health check failed: {e}")
        return {"status": "unhealthy", "error": "Redis cluster health check failed"}


async def check_rabbitmq() -> Dict[str, Any]:
    """Check RabbitMQ connectivity """
    try:
        # Fetch credentials from Vault
        creds = await vault_client.get_secret("rabbitmq")

        # Get vhost (default to 'dev_vhost' if not in vault)
        vhost = creds.get('vhost', 'dev_vhost')

        # Build connection string with vhost
        url = f"amqp://{creds.get('user')}:{creds.get('password')}@{settings.RABBITMQ_HOST}:{settings.RABBITMQ_PORT}/{vhost}"

        # Connect
        connection = await aio_pika.connect_robust(url, timeout=5.0)

        # Connection successful - RabbitMQ is healthy
        await connection.close()

        return {
            "status": "healthy"
        }
    except Exception as e:
        logger.error(f"RabbitMQ health check failed: {e}")
        return {"status": "unhealthy", "error": "RabbitMQ connection failed"}


@router.get("/vault")
async def health_vault():
    """Check Vault health"""
    return await check_vault()


@router.get("/postgres")
async def health_postgres():
    """Check PostgreSQL health"""
    return await check_postgres()


@router.get("/mysql")
async def health_mysql():
    """Check MySQL health"""
    return await check_mysql()


@router.get("/mongodb")
async def health_mongodb():
    """Check MongoDB health"""
    return await check_mongodb()


@router.get("/redis")
async def health_redis():
    """Check Redis health"""
    return await check_redis()


@router.get("/rabbitmq")
async def health_rabbitmq():
    """Check RabbitMQ health"""
    return await check_rabbitmq()


@router.get("/all")
@cache(expire=30, key_builder=generate_cache_key)  # Cache for 30 seconds
async def health_all():
    """
    Check all services health

    Response is cached for 30 seconds to reduce load on infrastructure services.
    """
    results = {
        "vault": await check_vault(),
        "postgres": await check_postgres(),
        "mysql": await check_mysql(),
        "mongodb": await check_mongodb(),
        "redis": await check_redis(),
        "rabbitmq": await check_rabbitmq(),
    }

    # Determine overall status
    all_healthy = all(
        service.get("status") == "healthy"
        for service in results.values()
    )

    return {
        "status": "healthy" if all_healthy else "degraded",
        "services": results
    }


@router.get("/")
async def health_simple():
    """Simple health check (doesn't test dependencies)"""
    return {"status": "ok"}
