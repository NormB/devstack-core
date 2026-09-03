/**
 * Main Application Tests
 *
 * Tests for the Express application entry point and core functionality.
 */

import request from 'supertest';

// Mock the vault service before importing app. The factory mirrors the
// module's real exports so nothing here can drift from `src/services/vault`.
jest.mock('../src/services/vault', () => ({
  getSecret: jest.fn(),
  checkVaultHealth: jest.fn()
}));

import { createServer } from 'net';
import app from '../src/index';
import config from '../src/config';

describe('Importing the application module', () => {
  it('does not bind the configured HTTP port', async () => {
    // The tests import `src/index` to get a testable app. That import must
    // not start a listener: with several suites in one process the second
    // `listen` fails with EADDRINUSE, and a listener nobody closes keeps the
    // test process alive. Proving the port is free is the only observable.
    const probe = createServer();
    await new Promise<void>((resolve, reject) => {
      probe.once('error', reject);
      probe.listen(config.server.httpPort, '0.0.0.0', () => resolve());
    });
    await new Promise<void>(resolve => {
      probe.close(() => resolve());
    });
  });
});

describe('Application Entry Point', () => {
  describe('GET /', () => {
    it('should return API information', async () => {
      const response = await request(app)
        .get('/')
        .expect('Content-Type', /json/)
        .expect(200);

      expect(response.body).toHaveProperty('name');
      expect(response.body).toHaveProperty('version');
      expect(response.body).toHaveProperty('language', 'TypeScript');
      expect(response.body).toHaveProperty('framework', 'Express');
      expect(response.body).toHaveProperty('endpoints');
    });

    it('should include all expected endpoints in response', async () => {
      const response = await request(app).get('/').expect(200);

      const { endpoints } = response.body;
      expect(endpoints).toHaveProperty('health', '/health');
      expect(endpoints).toHaveProperty('vault_examples', '/examples/vault');
      expect(endpoints).toHaveProperty('database_examples', '/examples/database');
      expect(endpoints).toHaveProperty('cache_examples', '/examples/cache');
      expect(endpoints).toHaveProperty('messaging_examples', '/examples/messaging');
      expect(endpoints).toHaveProperty('metrics', '/metrics');
    });

    it('should include redis cluster endpoints', async () => {
      const response = await request(app).get('/').expect(200);

      expect(response.body).toHaveProperty('redis_cluster');
      expect(response.body.redis_cluster).toHaveProperty('nodes');
      expect(response.body.redis_cluster).toHaveProperty('slots');
      expect(response.body.redis_cluster).toHaveProperty('info');
    });
  });

  describe('GET /metrics', () => {
    it('should return Prometheus metrics', async () => {
      const response = await request(app)
        .get('/metrics')
        .expect(200);

      expect(response.text).toContain('# HELP');
      expect(response.text).toContain('# TYPE');
    });
  });

  describe('404 Handler', () => {
    it('should return 404 for unknown routes', async () => {
      const response = await request(app)
        .get('/nonexistent/route')
        .expect('Content-Type', /json/)
        .expect(404);

      expect(response.body).toHaveProperty('error', 'Not Found');
      expect(response.body).toHaveProperty('message');
    });

    it('should include request method in 404 response', async () => {
      const response = await request(app)
        .post('/nonexistent')
        .expect(404);

      expect(response.body.message).toContain('POST');
    });
  });
});

describe('Security Headers', () => {
  it('should include security headers from helmet', async () => {
    const response = await request(app).get('/').expect(200);

    expect(response.headers).toHaveProperty('x-content-type-options');
    expect(response.headers).toHaveProperty('x-frame-options');
  });
});
