/**
 * Rate Limiting Middleware Tests
 *
 * Tests for IP-based rate limiting middleware.
 */

const request = require('supertest');
const express = require('express');

// Import the rate limit middleware
const {
  defaultLimiter,
  strictLimiter,
  highLimiter,
  createRateLimiter
} = require('../src/middleware/rate-limit');

// Helper to create a test app with rate limiting
function createTestApp(limiter) {
  const app = express();
  app.use(express.json());
  app.use(limiter);
  app.get('/test', (req, res) => {
    res.json({ status: 'ok' });
  });
  app.post('/test', (req, res) => {
    res.json({ status: 'ok', body: req.body });
  });
  return app;
}

describe('Rate Limiting Middleware', () => {
  describe('defaultLimiter', () => {
    let app;

    beforeEach(() => {
      app = createTestApp(defaultLimiter);
    });

    it('should allow requests under the limit', async () => {
      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.body.status).toBe('ok');
    });

    it('should include rate limit headers in response', async () => {
      const response = await request(app)
        .get('/test')
        .expect(200);

      // express-rate-limit uses RateLimit-* headers with standardHeaders: true
      expect(response.headers).toHaveProperty('ratelimit-limit');
      expect(response.headers).toHaveProperty('ratelimit-remaining');
    });

    it('should have correct limit value (100)', async () => {
      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.headers['ratelimit-limit']).toBe('100');
    });

    it('should decrement remaining count', async () => {
      const response1 = await request(app).get('/test').expect(200);
      const remaining1 = parseInt(response1.headers['ratelimit-remaining']);

      const response2 = await request(app).get('/test').expect(200);
      const remaining2 = parseInt(response2.headers['ratelimit-remaining']);

      expect(remaining2).toBe(remaining1 - 1);
    });

    it('should work with POST requests', async () => {
      const response = await request(app)
        .post('/test')
        .send({ data: 'test' })
        .expect(200);

      expect(response.body.status).toBe('ok');
    });
  });

  describe('strictLimiter', () => {
    let app;

    beforeEach(() => {
      app = createTestApp(strictLimiter);
    });

    it('should allow requests under the strict limit', async () => {
      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.body.status).toBe('ok');
    });

    it('should have correct strict limit value (10)', async () => {
      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.headers['ratelimit-limit']).toBe('10');
    });
  });

  describe('highLimiter', () => {
    let app;

    beforeEach(() => {
      app = createTestApp(highLimiter);
    });

    it('should allow requests under the high limit', async () => {
      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.body.status).toBe('ok');
    });

    it('should have correct high limit value (1000)', async () => {
      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.headers['ratelimit-limit']).toBe('1000');
    });
  });

  describe('createRateLimiter', () => {
    it('should create limiter with default values', async () => {
      const limiter = createRateLimiter();
      const app = createTestApp(limiter);

      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.headers['ratelimit-limit']).toBe('100');
    });

    it('should create limiter with custom max value', async () => {
      const limiter = createRateLimiter({ max: 50 });
      const app = createTestApp(limiter);

      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.headers['ratelimit-limit']).toBe('50');
    });

    it('should create limiter with custom window', async () => {
      const limiter = createRateLimiter({ windowMs: 30000, max: 25 });
      const app = createTestApp(limiter);

      const response = await request(app)
        .get('/test')
        .expect(200);

      expect(response.headers['ratelimit-limit']).toBe('25');
    });
  });

  describe('Rate limit exceeded behavior', () => {
    it('should return 429 when limit exceeded', async () => {
      // Create a limiter with very low limit for testing
      const testLimiter = createRateLimiter({ max: 2, windowMs: 60000 });
      const app = createTestApp(testLimiter);

      // Make requests up to the limit
      await request(app).get('/test').expect(200);
      await request(app).get('/test').expect(200);

      // This request should be rate limited
      const response = await request(app)
        .get('/test')
        .expect(429);

      expect(response.body).toHaveProperty('error', 'Too Many Requests');
      expect(response.body).toHaveProperty('message');
      expect(response.body).toHaveProperty('retry_after_seconds');
    });

    it('should include retry_after_seconds in 429 response', async () => {
      const testLimiter = createRateLimiter({ max: 1, windowMs: 60000 });
      const app = createTestApp(testLimiter);

      await request(app).get('/test').expect(200);

      const response = await request(app)
        .get('/test')
        .expect(429);

      expect(response.body.retry_after_seconds).toBe(60);
    });
  });

  describe('Multiple endpoints with different limits', () => {
    it('should apply different limits to different routes', async () => {
      const app = express();
      app.use(express.json());

      // Default limit for /api
      app.use('/api', defaultLimiter);
      app.get('/api/data', (req, res) => res.json({ route: 'api' }));

      // High limit for /metrics
      app.get('/metrics', highLimiter, (req, res) => res.json({ route: 'metrics' }));

      const apiResponse = await request(app).get('/api/data').expect(200);
      const metricsResponse = await request(app).get('/metrics').expect(200);

      expect(apiResponse.headers['ratelimit-limit']).toBe('100');
      expect(metricsResponse.headers['ratelimit-limit']).toBe('1000');
    });
  });
});
