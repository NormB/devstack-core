/**
 * Cache Integration Routes
 *
 * Demonstration endpoints for Redis cache operations.
 */

import { Router, Request, Response } from 'express';
import { createClient } from 'redis';
import { getSecret } from '../services/vault';
import config from '../config';
import { logger } from '../middleware/logging';
import { CacheGetResponse, CacheSetRequest, CacheSetResponse, CacheDeleteResponse } from '../types';

const router = Router();

router.get('/:key', async (req: Request, res: Response): Promise<void> => {
  let client: ReturnType<typeof createClient> | null = null;
  try {
    const creds = await getSecret('redis-1');
    client = createClient({
      socket: { host: config.cache.redis.host, port: config.cache.redis.port },
      password: creds.password
    });
    await client.connect();

    const value = await client.get(req.params.key);
    const ttl = value !== null ? await client.ttl(req.params.key) : null;

    const response: CacheGetResponse = {
      key: req.params.key,
      value,
      exists: value !== null,
      ttl: ttl !== null && ttl >= 0 ? ttl : null
    };

    res.json(response);
  } catch (error) {
    logger.error('Cache GET failed', {
      key: req.params.key,
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      error: 'Cache unavailable',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (client) {
      await client.quit().catch(() => {});
    }
  }
});

router.post('/:key', async (req: Request, res: Response): Promise<void> => {
  let client: ReturnType<typeof createClient> | null = null;
  try {
    const creds = await getSecret('redis-1');
    client = createClient({
      socket: { host: config.cache.redis.host, port: config.cache.redis.port },
      password: creds.password
    });
    await client.connect();

    const { value, ttl }: CacheSetRequest = req.body;

    if (!value) {
      res.status(400).json({
        error: 'Bad request',
        message: 'Value is required'
      });
      return;
    }

    if (ttl && ttl > 0) {
      await client.setEx(req.params.key, ttl, value);
    } else {
      await client.set(req.params.key, value);
    }

    const response: CacheSetResponse = {
      key: req.params.key,
      value,
      ttl: ttl || null,
      action: 'set'
    };

    res.json(response);
  } catch (error) {
    logger.error('Cache SET failed', {
      key: req.params.key,
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      error: 'Cache unavailable',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (client) {
      await client.quit().catch(() => {});
    }
  }
});

router.delete('/:key', async (req: Request, res: Response): Promise<void> => {
  let client: ReturnType<typeof createClient> | null = null;
  try {
    const creds = await getSecret('redis-1');
    client = createClient({
      socket: { host: config.cache.redis.host, port: config.cache.redis.port },
      password: creds.password
    });
    await client.connect();

    const deleted = await client.del(req.params.key);

    const response: CacheDeleteResponse = {
      key: req.params.key,
      deleted: deleted > 0,
      action: 'delete'
    };

    res.json(response);
  } catch (error) {
    logger.error('Cache DELETE failed', {
      key: req.params.key,
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      error: 'Cache unavailable',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (client) {
      await client.quit().catch(() => {});
    }
  }
});

export default router;
