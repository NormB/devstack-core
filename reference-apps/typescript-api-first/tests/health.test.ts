/**
 * Health Check Route Tests
 *
 * Tests for health check endpoints without requiring actual service connections.
 */

import request from 'supertest';

// Mock all external dependencies
jest.mock('../src/services/vault', () => ({
  vaultClient: {
    healthCheck: jest.fn(),
    getSecret: jest.fn(),
    isAuthenticated: jest.fn().mockReturnValue(true)
  }
}));

jest.mock('pg', () => ({
  Client: jest.fn().mockImplementation(() => ({
    connect: jest.fn(),
    query: jest.fn(),
    end: jest.fn()
  }))
}));

jest.mock('mysql2/promise', () => ({
  createConnection: jest.fn()
}));

jest.mock('mongodb', () => ({
  MongoClient: jest.fn().mockImplementation(() => ({
    connect: jest.fn(),
    db: jest.fn(() => ({
      admin: jest.fn(() => ({
        serverInfo: jest.fn()
      }))
    })),
    close: jest.fn()
  }))
}));

jest.mock('redis', () => ({
  createClient: jest.fn(() => ({
    connect: jest.fn(),
    info: jest.fn(),
    sendCommand: jest.fn(),
    quit: jest.fn()
  }))
}));

jest.mock('amqplib', () => ({
  connect: jest.fn()
}));

import app from '../src/index';
import { vaultClient } from '../src/services/vault';
import { Client as PgClient } from 'pg';
import mysql from 'mysql2/promise';
import { MongoClient } from 'mongodb';
import { createClient } from 'redis';
import amqp from 'amqplib';

const mockVaultClient = vaultClient as jest.Mocked<typeof vaultClient>;
const mockPgClient = PgClient as jest.MockedClass<typeof PgClient>;
const mockMysql = mysql as jest.Mocked<typeof mysql>;
const mockMongoClient = MongoClient as jest.MockedClass<typeof MongoClient>;
const mockCreateClient = createClient as jest.MockedFunction<typeof createClient>;
const mockAmqp = amqp as jest.Mocked<typeof amqp>;

describe('Health Routes', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  describe('GET /health', () => {
    it('should return healthy status', async () => {
      const response = await request(app)
        .get('/health')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('status', 'healthy');
      expect(response.body).toHaveProperty('timestamp');
      expect(response.body).toHaveProperty('uptime');
    });

    it('should return uptime as a number', async () => {
      const response = await request(app).get('/health').expect(200);
      expect(typeof response.body.uptime).toBe('number');
    });
  });

  describe('GET /health/vault', () => {
    it('should return healthy when Vault is accessible', async () => {
      mockVaultClient.healthCheck.mockResolvedValue({
        status: 'healthy',
        initialized: true,
        sealed: false
      });

      const response = await request(app)
        .get('/health/vault')
        .expect(200);

      expect(response.body.status).toBe('healthy');
    });

    it('should return unhealthy when Vault check fails', async () => {
      mockVaultClient.healthCheck.mockRejectedValue(new Error('Connection refused'));

      const response = await request(app)
        .get('/health/vault')
        .expect(503);

      expect(response.body.status).toBe('unhealthy');
    });
  });

  describe('GET /health/postgres', () => {
    it('should return healthy when PostgreSQL is accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass',
        database: 'testdb'
      });

      const mockClient = {
        connect: jest.fn().mockResolvedValue(undefined),
        query: jest.fn().mockResolvedValue({
          rows: [{ version: 'PostgreSQL 15.4 on x86_64' }]
        }),
        end: jest.fn().mockResolvedValue(undefined)
      };
      mockPgClient.mockImplementation(() => mockClient as any);

      const response = await request(app)
        .get('/health/postgres')
        .expect(200);

      expect(response.body.status).toBe('healthy');
      expect(response.body).toHaveProperty('version');
    });

    it('should return unhealthy when PostgreSQL is not accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass',
        database: 'testdb'
      });

      const mockClient = {
        connect: jest.fn().mockRejectedValue(new Error('Connection refused')),
        end: jest.fn().mockResolvedValue(undefined)
      };
      mockPgClient.mockImplementation(() => mockClient as any);

      const response = await request(app)
        .get('/health/postgres')
        .expect(503);

      expect(response.body.status).toBe('unhealthy');
    });
  });

  describe('GET /health/mysql', () => {
    it('should return healthy when MySQL is accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass',
        database: 'testdb'
      });

      const mockConnection = {
        query: jest.fn().mockResolvedValue([[{ version: '8.0.35' }]]),
        end: jest.fn().mockResolvedValue(undefined)
      };
      mockMysql.createConnection.mockResolvedValue(mockConnection as any);

      const response = await request(app)
        .get('/health/mysql')
        .expect(200);

      expect(response.body.status).toBe('healthy');
      expect(response.body.version).toBe('8.0.35');
    });

    it('should return unhealthy when MySQL is not accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass',
        database: 'testdb'
      });

      mockMysql.createConnection.mockRejectedValue(new Error('Connection refused'));

      const response = await request(app)
        .get('/health/mysql')
        .expect(503);

      expect(response.body.status).toBe('unhealthy');
    });
  });

  describe('GET /health/mongodb', () => {
    it('should return healthy when MongoDB is accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass',
        database: 'testdb'
      });

      const mockClient = {
        connect: jest.fn().mockResolvedValue(undefined),
        db: jest.fn(() => ({
          admin: jest.fn(() => ({
            serverInfo: jest.fn().mockResolvedValue({ version: '7.0.4' })
          }))
        })),
        close: jest.fn().mockResolvedValue(undefined)
      };
      mockMongoClient.mockImplementation(() => mockClient as any);

      const response = await request(app)
        .get('/health/mongodb')
        .expect(200);

      expect(response.body.status).toBe('healthy');
      expect(response.body.version).toBe('7.0.4');
    });

    it('should return unhealthy when MongoDB is not accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass',
        database: 'testdb'
      });

      const mockClient = {
        connect: jest.fn().mockRejectedValue(new Error('Connection refused')),
        close: jest.fn().mockResolvedValue(undefined)
      };
      mockMongoClient.mockImplementation(() => mockClient as any);

      const response = await request(app)
        .get('/health/mongodb')
        .expect(503);

      expect(response.body.status).toBe('unhealthy');
    });
  });

  describe('GET /health/redis', () => {
    it('should return healthy when Redis is accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({ password: 'testpass' });

      const mockClient = {
        connect: jest.fn().mockResolvedValue(undefined),
        info: jest.fn().mockResolvedValue('redis_version:7.2.4\r\n'),
        sendCommand: jest.fn().mockResolvedValue('cluster_state:ok\r\n'),
        quit: jest.fn().mockResolvedValue(undefined)
      };
      mockCreateClient.mockReturnValue(mockClient as any);

      const response = await request(app)
        .get('/health/redis')
        .expect(200);

      expect(response.body.status).toBe('healthy');
    });

    it('should return unhealthy when Redis is not accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({ password: 'testpass' });

      const mockClient = {
        connect: jest.fn().mockRejectedValue(new Error('Connection refused')),
        quit: jest.fn().mockResolvedValue(undefined)
      };
      mockCreateClient.mockReturnValue(mockClient as any);

      const response = await request(app)
        .get('/health/redis')
        .expect(503);

      expect(response.body.status).toBe('unhealthy');
    });
  });

  describe('GET /health/rabbitmq', () => {
    it('should return healthy when RabbitMQ is accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass'
      });

      const mockChannel = {
        close: jest.fn().mockResolvedValue(undefined)
      };
      const mockConnection = {
        createChannel: jest.fn().mockResolvedValue(mockChannel),
        close: jest.fn().mockResolvedValue(undefined)
      };
      mockAmqp.connect.mockResolvedValue(mockConnection as any);

      const response = await request(app)
        .get('/health/rabbitmq')
        .expect(200);

      expect(response.body.status).toBe('healthy');
    });

    it('should return unhealthy when RabbitMQ is not accessible', async () => {
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass'
      });

      mockAmqp.connect.mockRejectedValue(new Error('Connection refused'));

      const response = await request(app)
        .get('/health/rabbitmq')
        .expect(503);

      expect(response.body.status).toBe('unhealthy');
    });
  });

  describe('GET /health/all', () => {
    it('should return aggregate health status', async () => {
      mockVaultClient.healthCheck.mockResolvedValue({ status: 'healthy' });
      mockVaultClient.getSecret.mockResolvedValue({
        user: 'testuser',
        password: 'testpass',
        database: 'testdb'
      });

      const mockPg = {
        connect: jest.fn().mockResolvedValue(undefined),
        query: jest.fn().mockResolvedValue({ rows: [{ version: 'PostgreSQL 15.4' }] }),
        end: jest.fn().mockResolvedValue(undefined)
      };
      mockPgClient.mockImplementation(() => mockPg as any);

      const mockMysqlConn = {
        query: jest.fn().mockResolvedValue([[{ version: '8.0.35' }]]),
        end: jest.fn().mockResolvedValue(undefined)
      };
      mockMysql.createConnection.mockResolvedValue(mockMysqlConn as any);

      const mockMongo = {
        connect: jest.fn().mockResolvedValue(undefined),
        db: jest.fn(() => ({
          admin: jest.fn(() => ({
            serverInfo: jest.fn().mockResolvedValue({ version: '7.0.4' })
          }))
        })),
        close: jest.fn().mockResolvedValue(undefined)
      };
      mockMongoClient.mockImplementation(() => mockMongo as any);

      const mockRedis = {
        connect: jest.fn().mockResolvedValue(undefined),
        info: jest.fn().mockResolvedValue('redis_version:7.2.4\r\n'),
        sendCommand: jest.fn().mockResolvedValue('cluster_state:ok\r\n'),
        quit: jest.fn().mockResolvedValue(undefined)
      };
      mockCreateClient.mockReturnValue(mockRedis as any);

      const mockRabbitChannel = { close: jest.fn().mockResolvedValue(undefined) };
      const mockRabbitConn = {
        createChannel: jest.fn().mockResolvedValue(mockRabbitChannel),
        close: jest.fn().mockResolvedValue(undefined)
      };
      mockAmqp.connect.mockResolvedValue(mockRabbitConn as any);

      const response = await request(app)
        .get('/health/all')
        .expect(200);

      expect(response.body).toHaveProperty('status');
      expect(response.body).toHaveProperty('services');
      expect(response.body).toHaveProperty('timestamp');
      expect(response.body.services).toHaveProperty('vault');
      expect(response.body.services).toHaveProperty('postgres');
      expect(response.body.services).toHaveProperty('mysql');
      expect(response.body.services).toHaveProperty('mongodb');
      expect(response.body.services).toHaveProperty('redis');
      expect(response.body.services).toHaveProperty('rabbitmq');
    });
  });
});
