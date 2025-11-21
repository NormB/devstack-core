/**
 * Health Check Routes
 *
 * Endpoints for monitoring infrastructure service health.
 */

import { Router, Request, Response } from 'express';
import { Client as PgClient } from 'pg';
import mysql from 'mysql2/promise';
import { MongoClient } from 'mongodb';
import { createClient } from 'redis';
import amqp from 'amqplib';
import { getSecret, checkVaultHealth } from '../services/vault';
import config from '../config';
import { logger } from '../middleware/logging';
import { ServiceHealth, HealthStatus } from '../types';

const router = Router();

/**
 * Simple health check (no dependencies)
 */
router.get('/', (req: Request, res: Response): void => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

/**
 * Check Vault health
 */
async function checkVault(): Promise<ServiceHealth> {
  try {
    const isHealthy = await checkVaultHealth();
    return {
      status: isHealthy ? 'healthy' : 'unhealthy',
      details: { accessible: isHealthy }
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    };
  }
}

/**
 * Check PostgreSQL health
 */
async function checkPostgres(): Promise<ServiceHealth> {
  let client: PgClient | null = null;
  try {
    const creds = await getSecret('postgres');
    client = new PgClient({
      host: config.database.postgres.host,
      port: config.database.postgres.port,
      user: creds.user,
      password: creds.password,
      database: creds.database,
      connectionTimeoutMillis: 5000
    });

    await client.connect();
    const result = await client.query('SELECT version()');

    return {
      status: 'healthy',
      details: {
        version: result.rows[0].version.split(' ')[1]
      }
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    };
  } finally {
    if (client) {
      await client.end().catch(() => {});
    }
  }
}

/**
 * Check MySQL health
 */
async function checkMySQL(): Promise<ServiceHealth> {
  let connection: mysql.Connection | null = null;
  try {
    const creds = await getSecret('mysql');
    connection = await mysql.createConnection({
      host: config.database.mysql.host,
      port: config.database.mysql.port,
      user: creds.user,
      password: creds.password,
      database: creds.database,
      connectTimeout: 5000
    });

    const [rows] = await connection.query<mysql.RowDataPacket[]>('SELECT VERSION() as version');

    return {
      status: 'healthy',
      details: {
        version: rows[0].version
      }
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    };
  } finally {
    if (connection) {
      await connection.end().catch(() => {});
    }
  }
}

/**
 * Check MongoDB health
 */
async function checkMongoDB(): Promise<ServiceHealth> {
  let client: MongoClient | null = null;
  try {
    const creds = await getSecret('mongodb');
    const uri = `mongodb://${creds.user}:${creds.password}@${config.database.mongodb.host}:${config.database.mongodb.port}/${creds.database}?authSource=admin`;

    client = new MongoClient(uri, {
      serverSelectionTimeoutMS: 5000
    });

    await client.connect();
    const adminDb = client.db().admin();
    const serverInfo = await adminDb.serverInfo();

    return {
      status: 'healthy',
      details: {
        version: serverInfo.version
      }
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    };
  } finally {
    if (client) {
      await client.close().catch(() => {});
    }
  }
}

/**
 * Check Redis health
 */
async function checkRedis(): Promise<ServiceHealth> {
  let client: ReturnType<typeof createClient> | null = null;
  try {
    const creds = await getSecret('redis-1');
    client = createClient({
      socket: {
        host: config.cache.redis.host,
        port: config.cache.redis.port,
        connectTimeout: 5000
      },
      password: creds.password
    });

    await client.connect();
    const info = await client.info('server');
    const versionMatch = info.match(/redis_version:([^\r\n]+)/);
    const version = versionMatch ? versionMatch[1] : 'unknown';

    // Check cluster status
    const clusterInfo = await client.sendCommand(['CLUSTER', 'INFO']) as string;
    const clusterStateMatch = clusterInfo.match(/cluster_state:(\w+)/);
    const clusterState = clusterStateMatch ? clusterStateMatch[1] : 'unknown';

    return {
      status: 'healthy',
      details: {
        version,
        cluster_enabled: true,
        cluster_state: clusterState
      }
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    };
  } finally {
    if (client) {
      await client.quit().catch(() => {});
    }
  }
}

/**
 * Check RabbitMQ health
 */
async function checkRabbitMQ(): Promise<ServiceHealth> {
  let connection: any = null;
  try {
    const creds = await getSecret('rabbitmq');
    const url = `amqp://${creds.user}:${creds.password}@${config.messaging.rabbitmq.host}:${config.messaging.rabbitmq.port}`;

    connection = await amqp.connect(url, { timeout: 5000 });
    const channel = await connection.createChannel();
    await channel.close();

    return {
      status: 'healthy'
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    };
  } finally {
    if (connection) {
      await connection.close().catch(() => {});
    }
  }
}

/**
 * Individual health check endpoints
 */
router.get('/vault', async (req: Request, res: Response): Promise<void> => {
  try {
    const result = await checkVault();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('Vault health check failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    });
  }
});

router.get('/postgres', async (req: Request, res: Response): Promise<void> => {
  try {
    const result = await checkPostgres();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('PostgreSQL health check failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    });
  }
});

router.get('/mysql', async (req: Request, res: Response): Promise<void> => {
  try {
    const result = await checkMySQL();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('MySQL health check failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    });
  }
});

router.get('/mongodb', async (req: Request, res: Response): Promise<void> => {
  try {
    const result = await checkMongoDB();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('MongoDB health check failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    });
  }
});

router.get('/redis', async (req: Request, res: Response): Promise<void> => {
  try {
    const result = await checkRedis();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('Redis health check failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    });
  }
});

router.get('/rabbitmq', async (req: Request, res: Response): Promise<void> => {
  try {
    const result = await checkRabbitMQ();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('RabbitMQ health check failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      status: 'unhealthy',
      details: { error: error instanceof Error ? error.message : String(error) }
    });
  }
});

/**
 * Aggregate health check (all services)
 */
router.get('/all', async (req: Request, res: Response): Promise<void> => {
  try {
    // Run all checks concurrently
    const results = await Promise.allSettled([
      checkVault(),
      checkPostgres(),
      checkMySQL(),
      checkMongoDB(),
      checkRedis(),
      checkRabbitMQ()
    ]);

    const services: Record<string, ServiceHealth> = {
      vault: results[0].status === 'fulfilled'
        ? results[0].value
        : { status: 'unhealthy', details: { error: results[0].reason?.message } },
      postgres: results[1].status === 'fulfilled'
        ? results[1].value
        : { status: 'unhealthy', details: { error: results[1].reason?.message } },
      mysql: results[2].status === 'fulfilled'
        ? results[2].value
        : { status: 'unhealthy', details: { error: results[2].reason?.message } },
      mongodb: results[3].status === 'fulfilled'
        ? results[3].value
        : { status: 'unhealthy', details: { error: results[3].reason?.message } },
      redis: results[4].status === 'fulfilled'
        ? results[4].value
        : { status: 'unhealthy', details: { error: results[4].reason?.message } },
      rabbitmq: results[5].status === 'fulfilled'
        ? results[5].value
        : { status: 'unhealthy', details: { error: results[5].reason?.message } }
    };

    // Determine overall status
    const allHealthy = Object.values(services).every(s => s.status === 'healthy');
    const overallStatus: 'healthy' | 'degraded' = allHealthy ? 'healthy' : 'degraded';
    const statusCode = allHealthy ? 200 : 503;

    const response: HealthStatus = {
      status: overallStatus,
      services
    };

    res.status(statusCode).json({
      ...response,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    logger.error('Aggregate health check failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      status: 'unhealthy',
      error: error instanceof Error ? error.message : String(error)
    });
  }
});

export default router;
