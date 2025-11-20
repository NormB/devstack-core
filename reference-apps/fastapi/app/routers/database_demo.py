"""
Database integration examples

Demonstrates connections to:
- PostgreSQL
- MySQL
- MongoDB
"""

from fastapi import APIRouter, HTTPException
import asyncpg
import aiomysql
import motor.motor_asyncio

from app.config import settings
from app.services.vault import vault_client

router = APIRouter()


@router.get("/postgres/query")
async def postgres_example():
    """Example: Execute a simple PostgreSQL query"""
    try:
        # Get credentials from Vault
        creds = await vault_client.get_secret("postgres")

        # Connect
        conn = await asyncpg.connect(
            host=settings.POSTGRES_HOST,
            port=settings.POSTGRES_PORT,
            user=creds.get("user"),
            password=creds.get("password"),
            database=creds.get("database"),
            timeout=5.0
        )

        # Execute query
        result = await conn.fetchval("SELECT current_timestamp")
        await conn.close()

        return {
            "database": "PostgreSQL",
            "query": "SELECT current_timestamp",
            "result": str(result)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"PostgreSQL query failed: {str(e)}")


@router.get("/mysql/query")
async def mysql_example():
    """Example: Execute a simple MySQL query"""
    try:
        # Get credentials from Vault
        creds = await vault_client.get_secret("mysql")

        # Connect
        conn = await aiomysql.connect(
            host=settings.MYSQL_HOST,
            port=settings.MYSQL_PORT,
            user=creds.get("user"),
            password=creds.get("password"),
            db=creds.get("database"),
            connect_timeout=5
        )

        async with conn.cursor() as cursor:
            await cursor.execute("SELECT NOW()")
            result = await cursor.fetchone()

        conn.close()

        return {
            "database": "MySQL",
            "query": "SELECT NOW()",
            "result": str(result[0]) if result else None
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"MySQL query failed: {str(e)}")


@router.get("/mongodb/query")
async def mongodb_example():
    """Example: Query MongoDB"""
    try:
        # Get credentials from Vault
        creds = await vault_client.get_secret("mongodb")

        # Connect
        uri = f"mongodb://{creds.get('user')}:{creds.get('password')}@{settings.MONGODB_HOST}:{settings.MONGODB_PORT}"
        client = motor.motor_asyncio.AsyncIOMotorClient(uri, serverSelectionTimeoutMS=5000)

        # Access database
        db = client[creds.get("database", "dev_database")]

        # List collections
        collections = await db.list_collection_names()
        client.close()

        return {
            "database": "MongoDB",
            "collections": collections,
            "count": len(collections)
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"MongoDB query failed: {str(e)}")
