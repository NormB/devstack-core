/**
 * TypeScript API-First Reference Implementation - Main Entry Point
 *
 * Demonstrates type-safe infrastructure integration patterns using Express.
 */

import express, { Request, Response, NextFunction } from 'express';
import helmet from 'helmet';
import config from './config';
import { logger, loggingMiddleware } from './middleware/logging';
import { corsMiddleware } from './middleware/cors';
import { CustomRequest, APIInfo, ErrorResponse } from './types';

// Import routes
import healthRoutes from './routes/health';
import vaultRoutes from './routes/vault';
import databaseRoutes from './routes/database';
import cacheRoutes from './routes/cache';
import messagingRoutes from './routes/messaging';
import redisClusterRoutes from './routes/redis-cluster';

const app = express();

// Security middleware
app.use(helmet());

// CORS
app.use(corsMiddleware);

// Body parsing
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Logging middleware
app.use(loggingMiddleware);

// Root endpoint
app.get('/', (req: Request, res: Response): void => {
  const apiInfo: APIInfo = {
    name: config.app.name,
    version: config.app.version,
    language: config.app.language,
    framework: config.app.framework,
    description: 'TypeScript API-First reference implementation for infrastructure integration',
    endpoints: {
      health: '/health',
      vault_examples: '/examples/vault',
      database_examples: '/examples/database',
      cache_examples: '/examples/cache',
      messaging_examples: '/examples/messaging',
      redis_cluster: '/redis/cluster',
      metrics: '/metrics'
    },
    redis_cluster: {
      nodes: '/redis/cluster/nodes',
      slots: '/redis/cluster/slots',
      info: '/redis/cluster/info',
      node_info: '/redis/nodes/{node_name}/info'
    },
    documentation: 'See README.md for usage examples'
  };

  res.json(apiInfo);
});

// Mount routes
app.use('/health', healthRoutes);
app.use('/examples/vault', vaultRoutes);
app.use('/examples/database', databaseRoutes);
app.use('/examples/cache', cacheRoutes);
app.use('/examples/messaging', messagingRoutes);
app.use('/redis', redisClusterRoutes);

// Metrics endpoint (placeholder)
app.get('/metrics', (req: Request, res: Response): void => {
  res.set('Content-Type', 'text/plain');
  res.send('# Metrics endpoint - implementation pending\n');
});

// 404 handler
app.use((req: CustomRequest, res: Response): void => {
  const errorResponse: ErrorResponse = {
    error: 'Not Found',
    message: `Cannot ${req.method} ${req.path}`,
    requestId: req.requestId
  };
  res.status(404).json(errorResponse);
});

// Error handler
app.use((err: Error & { status?: number }, req: CustomRequest, res: Response, next: NextFunction): void => {
  logger.error('Unhandled error', {
    error: err.message,
    stack: err.stack,
    requestId: req.requestId
  });

  const errorResponse: ErrorResponse = {
    error: 'Internal Server Error',
    message: config.server.debug ? err.message : 'An error occurred',
    requestId: req.requestId
  };

  res.status(err.status || 500).json(errorResponse);
});

// Start server
const server = app.listen(config.server.httpPort, '0.0.0.0', () => {
  logger.info(`${config.app.name} started`, {
    port: config.server.httpPort,
    environment: config.server.environment,
    debug: config.server.debug
  });
});

// Graceful shutdown
const gracefulShutdown = (signal: string): void => {
  logger.info(`${signal} received, shutting down gracefully`);
  server.close(() => {
    logger.info('Server closed');
    process.exit(0);
  });
};

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

export default app;
