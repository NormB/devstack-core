/**
 * Database Integration Routes
 *
 * Demonstration endpoints for PostgreSQL, MySQL, and MongoDB.
 */

import { Router, Request, Response } from 'express';
import { Client as PgClient } from 'pg';
import mysql from 'mysql2/promise';
import { MongoClient } from 'mongodb';
import { getSecret } from '../services/vault';
import config from '../config';
import { logger } from '../middleware/logging';
import { DatabaseQueryResponse } from '../types';

const router = Router();

router.get('/postgres/query', async (req: Request, res: Response): Promise<void> => {
  let client: PgClient | null = null;
  try {
    const creds = await getSecret('postgres');
    client = new PgClient({
      host: config.database.postgres.host,
      port: config.database.postgres.port,
      user: creds.user,
      password: creds.password,
      database: creds.database
    });

    await client.connect();
    const result = await client.query('SELECT NOW() as current_time, version() as version');

    const response: DatabaseQueryResponse = {
      database: 'postgresql',
      status: 'success',
      query_result: JSON.stringify(result.rows[0]),
      timestamp: new Date().toISOString()
    };

    res.json(response);
  } catch (error) {
    logger.error('PostgreSQL query failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      error: 'Database query failed',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (client) {
      await client.end().catch(() => {});
    }
  }
});

router.get('/mysql/query', async (req: Request, res: Response): Promise<void> => {
  let connection: mysql.Connection | null = null;
  try {
    const creds = await getSecret('mysql');
    connection = await mysql.createConnection({
      host: config.database.mysql.host,
      port: config.database.mysql.port,
      user: creds.user,
      password: creds.password,
      database: creds.database
    });

    const [rows] = await connection.query<mysql.RowDataPacket[]>('SELECT NOW() as current_time, VERSION() as version');

    const response: DatabaseQueryResponse = {
      database: 'mysql',
      status: 'success',
      query_result: JSON.stringify(rows[0]),
      timestamp: new Date().toISOString()
    };

    res.json(response);
  } catch (error) {
    logger.error('MySQL query failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      error: 'Database query failed',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (connection) {
      await connection.end().catch(() => {});
    }
  }
});

router.get('/mongodb/query', async (req: Request, res: Response): Promise<void> => {
  let client: MongoClient | null = null;
  try {
    const creds = await getSecret('mongodb');
    const uri = `mongodb://${creds.user}:${creds.password}@${config.database.mongodb.host}:${config.database.mongodb.port}/${creds.database}?authSource=admin`;

    client = new MongoClient(uri);
    await client.connect();

    const db = client.db(creds.database);
    const result = await db.admin().serverInfo();

    const response: DatabaseQueryResponse = {
      database: 'mongodb',
      status: 'success',
      query_result: JSON.stringify({
        version: result.version,
        uptime: result.uptimeEstimate
      }),
      timestamp: new Date().toISOString()
    };

    res.json(response);
  } catch (error) {
    logger.error('MongoDB query failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      error: 'Database query failed',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (client) {
      await client.close().catch(() => {});
    }
  }
});

export default router;
