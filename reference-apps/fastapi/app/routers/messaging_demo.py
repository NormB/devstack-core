"""
RabbitMQ messaging examples

Demonstrates:
- Publishing messages
- Declaring queues
- Basic messaging patterns
"""

from fastapi import APIRouter, HTTPException, Path, Query, Body
import aio_pika
import json

from app.config import settings
from app.services.vault import vault_client
from app.models.responses import (
    MessagePublishResponse,
    QueueInfoResponse
)

router = APIRouter()


async def get_rabbitmq_connection():
    """Get RabbitMQ connection"""
    creds = await vault_client.get_secret("rabbitmq")
    url = f"amqp://{creds.get('user')}:{creds.get('password')}@{settings.RABBITMQ_HOST}:{settings.RABBITMQ_PORT}/"
    return await aio_pika.connect_robust(url, timeout=5.0)


@router.post("/publish", response_model=MessagePublishResponse)
async def publish_message(
    queue_name: str = Query(
        ...,
        min_length=1,
        max_length=100,
        pattern=r'^[a-zA-Z0-9_.-]+$',
        description="Queue name (alphanumeric and: - _ . only)"
    ),
    message: dict = Body(
        ...,
        description="Message payload (JSON object, max 1MB)"
    )
) -> MessagePublishResponse:
    """Example: Publish a message to a queue"""
    try:
        # Validate message size
        message_size = len(json.dumps(message))
        if message_size > 1_000_000:  # 1MB limit
            raise HTTPException(
                status_code=413,
                detail=f"Message size ({message_size} bytes) exceeds 1MB limit"
            )

        if not message:
            raise HTTPException(status_code=400, detail="Message cannot be empty")

        connection = await get_rabbitmq_connection()
        channel = await connection.channel()

        # Declare queue
        await channel.declare_queue(queue_name, durable=True)

        # Publish message
        await channel.default_exchange.publish(
            aio_pika.Message(body=json.dumps(message).encode()),
            routing_key=queue_name,
        )

        await connection.close()

        return MessagePublishResponse(
            queue=queue_name,
            message=message,
            action="published"
        )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Message publish failed: {str(e)}")


@router.get("/queue/{queue_name}/info", response_model=QueueInfoResponse)
async def get_queue_info(
    queue_name: str = Path(
        ...,
        min_length=1,
        max_length=100,
        pattern=r'^[a-zA-Z0-9_.-]+$',
        description="Queue name (alphanumeric and: - _ . only)"
    )
) -> QueueInfoResponse:
    """Example: Get information about a queue"""
    try:
        connection = await get_rabbitmq_connection()
        channel = await connection.channel()

        # Declare queue (passive=True means don't create if doesn't exist)
        try:
            queue = await channel.declare_queue(queue_name, passive=True)
            message_count = queue.declaration_result.message_count
            consumer_count = queue.declaration_result.consumer_count
        except Exception:
            # Queue doesn't exist
            await connection.close()
            return QueueInfoResponse(
                queue=queue_name,
                exists=False,
                message_count=None,
                consumer_count=None
            )

        await connection.close()

        return QueueInfoResponse(
            queue=queue_name,
            exists=True,
            message_count=message_count,
            consumer_count=consumer_count
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Queue info failed: {str(e)}")
