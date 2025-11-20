/**
 * Health Check Routes
 *
 * Endpoints for monitoring infrastructure service health.
 */

const express = require('express');
const { Client: PgClient } = require('pg');
const mysql = require('mysql2/promise');
const { MongoClient } = require('mongodb');
const { createClient } = require('redis');
const amqp = require('amqplib');
const { vaultClient } = require('../services/vault');
const config = require('../config');
const { logger } = require('../middleware/logging');

const router = express.Router();

/**
 * Simple health check (no dependencies)
 */
router.get('/', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

/**
 * Check Vault health
 */
async function checkVault() {
  try {
    const health = await vaultClient.healthCheck();
    return health;
  } catch (error) {
    return {
      status: 'unhealthy',
      error: error.message
    };
  }
}

/**
 * Check PostgreSQL health
 */
async function checkPostgres() {
  let client;
  try {
    const creds = await vaultClient.getSecret('postgres');
    client = new PgClient({
      host: config.postgres.host,
      port: config.postgres.port,
      user: creds.user,
      password: creds.password,
      database: creds.database,
      connectionTimeoutMillis: 5000
    });

    await client.connect();
    const result = await client.query('SELECT version()');

    return {
      status: 'healthy',
      version: result.rows[0].version.split(' ')[1]
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      error: error.message
    };
  } finally {
    if (client) await client.end().catch(() => {});
  }
}

/**
 * Check MySQL health
 */
async function checkMySQL() {
  let connection;
  try {
    const creds = await vaultClient.getSecret('mysql');
    connection = await mysql.createConnection({
      host: config.mysql.host,
      port: config.mysql.port,
      user: creds.user,
      password: creds.password,
      database: creds.database,
      connectTimeout: 5000
    });

    const [rows] = await connection.query('SELECT VERSION() as version');

    return {
      status: 'healthy',
      version: rows[0].version
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      error: error.message
    };
  } finally {
    if (connection) await connection.end().catch(() => {});
  }
}

/**
 * Check MongoDB health
 */
async function checkMongoDB() {
  let client;
  try {
    const creds = await vaultClient.getSecret('mongodb');
    const uri = `mongodb://${creds.user}:${creds.password}@${config.mongodb.host}:${config.mongodb.port}/${creds.database}?authSource=admin`;

    client = new MongoClient(uri, {
      serverSelectionTimeoutMS: 5000
    });

    await client.connect();
    const adminDb = client.db().admin();
    const serverInfo = await adminDb.serverInfo();

    return {
      status: 'healthy',
      version: serverInfo.version
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      error: error.message
    };
  } finally {
    if (client) await client.close().catch(() => {});
  }
}

/**
 * Check Redis health
 */
async function checkRedis() {
  let client;
  try {
    const creds = await vaultClient.getSecret('redis-1');
    client = createClient({
      socket: {
        host: config.redis.host,
        port: config.redis.port,
        connectTimeout: 5000
      },
      password: creds.password
    });

    await client.connect();
    const info = await client.info('server');
    const versionMatch = info.match(/redis_version:([^\r\n]+)/);
    const version = versionMatch ? versionMatch[1] : 'unknown';

    // Check cluster status
    const clusterInfo = await client.sendCommand(['CLUSTER', 'INFO']);
    const clusterState = clusterInfo.match(/cluster_state:(\w+)/)[1];

    return {
      status: 'healthy',
      version,
      cluster_enabled: true,
      cluster_state: clusterState
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      error: error.message
    };
  } finally {
    if (client) await client.quit().catch(() => {});
  }
}

/**
 * Check RabbitMQ health
 */
async function checkRabbitMQ() {
  let connection;
  try {
    const creds = await vaultClient.getSecret('rabbitmq');
    const url = `amqp://${creds.user}:${creds.password}@${config.rabbitmq.host}:${config.rabbitmq.port}`;

    connection = await amqp.connect(url, { timeout: 5000 });
    const channel = await connection.createChannel();
    await channel.close();

    return {
      status: 'healthy'
    };
  } catch (error) {
    return {
      status: 'unhealthy',
      error: error.message
    };
  } finally {
    if (connection) await connection.close().catch(() => {});
  }
}

/**
 * Individual health check endpoints
 */
router.get('/vault', async (req, res) => {
  try {
    const result = await checkVault();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('Vault health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

router.get('/postgres', async (req, res) => {
  try {
    const result = await checkPostgres();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('PostgreSQL health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

router.get('/mysql', async (req, res) => {
  try {
    const result = await checkMySQL();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('MySQL health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

router.get('/mongodb', async (req, res) => {
  try {
    const result = await checkMongoDB();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('MongoDB health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

router.get('/redis', async (req, res) => {
  try {
    const result = await checkRedis();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('Redis health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

router.get('/rabbitmq', async (req, res) => {
  try {
    const result = await checkRabbitMQ();
    const statusCode = result.status === 'healthy' ? 200 : 503;
    res.status(statusCode).json(result);
  } catch (error) {
    logger.error('RabbitMQ health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

/**
 * Aggregate health check (all services)
 */
router.get('/all', async (req, res) => {
  try {
    // Run all checks concurrently
    const [vault, postgres, mysql, mongodb, redis, rabbitmq] = await Promise.allSettled([
      checkVault(),
      checkPostgres(),
      checkMySQL(),
      checkMongoDB(),
      checkRedis(),
      checkRabbitMQ()
    ]);

    const services = {
      vault: vault.status === 'fulfilled' ? vault.value : { status: 'unhealthy', error: vault.reason?.message },
      postgres: postgres.status === 'fulfilled' ? postgres.value : { status: 'unhealthy', error: postgres.reason?.message },
      mysql: mysql.status === 'fulfilled' ? mysql.value : { status: 'unhealthy', error: mysql.reason?.message },
      mongodb: mongodb.status === 'fulfilled' ? mongodb.value : { status: 'unhealthy', error: mongodb.reason?.message },
      redis: redis.status === 'fulfilled' ? redis.value : { status: 'unhealthy', error: redis.reason?.message },
      rabbitmq: rabbitmq.status === 'fulfilled' ? rabbitmq.value : { status: 'unhealthy', error: rabbitmq.reason?.message }
    };

    // Determine overall status
    const allHealthy = Object.values(services).every(s => s.status === 'healthy');
    const overallStatus = allHealthy ? 'healthy' : 'degraded';
    const statusCode = allHealthy ? 200 : 503;

    res.status(statusCode).json({
      status: overallStatus,
      timestamp: new Date().toISOString(),
      services
    });
  } catch (error) {
    logger.error('Aggregate health check failed:', error);
    res.status(503).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});

module.exports = router;
