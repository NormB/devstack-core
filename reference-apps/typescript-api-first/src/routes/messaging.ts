/**
 * Messaging Integration Routes
 *
 * Demonstration endpoints for RabbitMQ message publishing and queue management.
 */

import { Router, Request, Response } from 'express';
import amqp from 'amqplib';
import { getSecret } from '../services/vault';
import config from '../config';
import { logger } from '../middleware/logging';
import { MessagePublishRequest, MessagePublishResponse, QueueInfoResponse } from '../types';

const router = Router();

/**
 * POST /examples/messaging/publish/:queue
 * Publish a message to a RabbitMQ queue
 */
router.post('/publish/:queue', async (req: Request, res: Response): Promise<void> => {
  let connection: any = null;
  try {
    const creds = await getSecret('rabbitmq');
    const url = `amqp://${creds.user}:${creds.password}@${config.messaging.rabbitmq.host}:${config.messaging.rabbitmq.port}`;

    connection = await amqp.connect(url);
    const channel = await connection.createChannel();

    // Assert queue exists (create if not)
    await channel.assertQueue(req.params.queue, { durable: true });

    // Publish message
    const messageData: MessagePublishRequest = req.body;
    const messageBuffer = Buffer.from(JSON.stringify(messageData.message));
    channel.sendToQueue(req.params.queue, messageBuffer);

    await channel.close();

    const response: MessagePublishResponse = {
      queue: req.params.queue,
      message: messageData.message,
      action: 'published'
    };

    logger.info('Message published to queue', {
      queue: req.params.queue,
      messageSize: messageBuffer.length
    });

    res.json(response);
  } catch (error) {
    logger.error('Failed to publish message to queue', {
      queue: req.params.queue,
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      error: 'Messaging service unavailable',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (connection) {
      await connection.close().catch(() => {});
    }
  }
});

/**
 * GET /examples/messaging/queue/:queueName/info
 * Get information about a RabbitMQ queue
 */
router.get('/queue/:queueName/info', async (req: Request, res: Response): Promise<void> => {
  let connection: any = null;
  try {
    const creds = await getSecret('rabbitmq');
    const url = `amqp://${creds.user}:${creds.password}@${config.messaging.rabbitmq.host}:${config.messaging.rabbitmq.port}`;

    connection = await amqp.connect(url);
    const channel = await connection.createChannel();

    // Check queue (throws if doesn't exist)
    const queueInfo = await channel.checkQueue(req.params.queueName);

    await channel.close();

    const response: QueueInfoResponse = {
      queue: req.params.queueName,
      exists: true,
      message_count: queueInfo.messageCount,
      consumer_count: queueInfo.consumerCount
    };

    res.json(response);
  } catch (error) {
    // Queue might not exist
    const errorMessage = error instanceof Error ? error.message : String(error);

    if (errorMessage.includes('NOT_FOUND') || errorMessage.includes('404')) {
      logger.info('Queue not found', { queue: req.params.queueName });

      const response: QueueInfoResponse = {
        queue: req.params.queueName,
        exists: false,
        message_count: null,
        consumer_count: null
      };

      res.status(404).json(response);
    } else {
      logger.error('Failed to get queue info', {
        queue: req.params.queueName,
        error: errorMessage
      });

      res.status(503).json({
        error: 'Messaging service unavailable',
        message: errorMessage
      });
    }
  } finally {
    if (connection) {
      await connection.close().catch(() => {});
    }
  }
});

export default router;
