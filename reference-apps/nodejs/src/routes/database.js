/**
 * Database Integration Routes
 *
 * Demonstration endpoints for PostgreSQL, MySQL, and MongoDB.
 */

const express = require('express');
const { Client: PgClient } = require('pg');
const mysql = require('mysql2/promise');
const { MongoClient } = require('mongodb');
const { vaultClient } = require('../services/vault');
const config = require('../config');
const { logger } = require('../middleware/logging');

const router = express.Router();

router.get('/postgres/query', async (req, res) => {
  let client;
  try {
    const creds = await vaultClient.getSecret('postgres');
    client = new PgClient({
      host: config.postgres.host,
      port: config.postgres.port,
      user: creds.user,
      password: creds.password,
      database: creds.database
    });

    await client.connect();
    const result = await client.query('SELECT NOW() as current_time, version() as version');

    res.json({
      database: 'postgresql',
      result: result.rows[0]
    });
  } catch (error) {
    logger.error('PostgreSQL query failed:', error);
    res.status(503).json({ error: error.message });
  } finally {
    if (client) await client.end().catch(() => {});
  }
});

router.get('/mysql/query', async (req, res) => {
  let connection;
  try {
    const creds = await vaultClient.getSecret('mysql');
    connection = await mysql.createConnection({
      host: config.mysql.host,
      port: config.mysql.port,
      user: creds.user,
      password: creds.password,
      database: creds.database
    });

    const [rows] = await connection.query('SELECT NOW() as current_time, VERSION() as version');

    res.json({
      database: 'mysql',
      result: rows[0]
    });
  } catch (error) {
    logger.error('MySQL query failed:', error);
    res.status(503).json({ error: error.message });
  } finally {
    if (connection) await connection.end().catch(() => {});
  }
});

router.get('/mongodb/query', async (req, res) => {
  let client;
  try {
    const creds = await vaultClient.getSecret('mongodb');
    const uri = `mongodb://${creds.user}:${creds.password}@${config.mongodb.host}:${config.mongodb.port}/${creds.database}?authSource=admin`;

    client = new MongoClient(uri);
    await client.connect();

    const db = client.db(creds.database);
    const result = await db.admin().serverInfo();

    res.json({
      database: 'mongodb',
      result: {
        version: result.version,
        uptime: result.uptimeEstimate
      }
    });
  } catch (error) {
    logger.error('MongoDB query failed:', error);
    res.status(503).json({ error: error.message });
  } finally {
    if (client) await client.close().catch(() => {});
  }
});

module.exports = router;
