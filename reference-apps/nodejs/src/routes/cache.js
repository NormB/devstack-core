const express = require('express');
const { createClient } = require('redis');
const { vaultClient } = require('../services/vault');
const config = require('../config');

const router = express.Router();

router.get('/:key', async (req, res) => {
  let client;
  try {
    const creds = await vaultClient.getSecret('redis-1');
    client = createClient({
      socket: { host: config.redis.host, port: config.redis.port },
      password: creds.password
    });
    await client.connect();

    const value = await client.get(req.params.key);
    res.json({ key: req.params.key, value, found: value !== null });
  } catch (error) {
    res.status(503).json({ error: error.message });
  } finally {
    if (client) await client.quit().catch(() => {});
  }
});

router.post('/:key', async (req, res) => {
  let client;
  try {
    const creds = await vaultClient.getSecret('redis-1');
    client = createClient({
      socket: { host: config.redis.host, port: config.redis.port },
      password: creds.password
    });
    await client.connect();

    const { value, ttl } = req.body;
    if (ttl) {
      await client.setEx(req.params.key, ttl, value);
    } else {
      await client.set(req.params.key, value);
    }

    res.json({ key: req.params.key, value, ttl, success: true });
  } catch (error) {
    res.status(503).json({ error: error.message });
  } finally {
    if (client) await client.quit().catch(() => {});
  }
});

router.delete('/:key', async (req, res) => {
  let client;
  try {
    const creds = await vaultClient.getSecret('redis-1');
    client = createClient({
      socket: { host: config.redis.host, port: config.redis.port },
      password: creds.password
    });
    await client.connect();

    const deleted = await client.del(req.params.key);
    res.json({ key: req.params.key, deleted: deleted > 0 });
  } catch (error) {
    res.status(503).json({ error: error.message });
  } finally {
    if (client) await client.quit().catch(() => {});
  }
});

module.exports = router;
