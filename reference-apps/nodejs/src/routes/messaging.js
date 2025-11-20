const express = require('express');
const amqp = require('amqplib');
const { vaultClient } = require('../services/vault');
const config = require('../config');

const router = express.Router();

router.post('/publish/:queue', async (req, res) => {
  let connection;
  try {
    const creds = await vaultClient.getSecret('rabbitmq');
    const url = `amqp://${creds.user}:${creds.password}@${config.rabbitmq.host}:${config.rabbitmq.port}`;

    connection = await amqp.connect(url);
    const channel = await connection.createChannel();
    await channel.assertQueue(req.params.queue, { durable: true });
    channel.sendToQueue(req.params.queue, Buffer.from(JSON.stringify(req.body)));

    await channel.close();
    res.json({ queue: req.params.queue, message: req.body, published: true });
  } catch (error) {
    res.status(503).json({ error: error.message });
  } finally {
    if (connection) await connection.close().catch(() => {});
  }
});

router.get('/queue/:queue_name/info', async (req, res) => {
  let connection;
  try {
    const creds = await vaultClient.getSecret('rabbitmq');
    const url = `amqp://${creds.user}:${creds.password}@${config.rabbitmq.host}:${config.rabbitmq.port}`;

    connection = await amqp.connect(url);
    const channel = await connection.createChannel();

    // Assert queue to get its info
    const queueInfo = await channel.checkQueue(req.params.queue_name);

    await channel.close();

    res.json({
      queue: req.params.queue_name,
      message_count: queueInfo.messageCount,
      consumer_count: queueInfo.consumerCount,
      exists: true
    });
  } catch (error) {
    // Queue might not exist
    if (error.message.includes('NOT_FOUND')) {
      res.status(404).json({
        queue: req.params.queue_name,
        exists: false,
        error: 'Queue not found'
      });
    } else {
      res.status(503).json({
        queue: req.params.queue_name,
        error: error.message
      });
    }
  } finally {
    if (connection) await connection.close().catch(() => {});
  }
});

module.exports = router;
