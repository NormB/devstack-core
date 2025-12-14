/**
 * Request Validation Middleware Tests
 *
 * Tests for request validation middleware functions.
 */

const request = require('supertest');
const express = require('express');

// Import validation middleware
const {
  ValidationError,
  requireFields,
  validateTypes,
  validateConstraints,
  validateParams,
  validateQuery,
  validate
} = require('../src/middleware/validation');

// Mock logging to prevent console output during tests
jest.mock('../src/middleware/logging', () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
    debug: jest.fn()
  },
  loggingMiddleware: (req, res, next) => {
    req.requestId = 'test-request-id';
    next();
  }
}));

// Helper to create a test app with validation
function createTestApp(middleware, handler = (req, res) => res.json({ success: true, body: req.body })) {
  const app = express();
  app.use(express.json());
  app.use((req, res, next) => {
    req.requestId = 'test-request-id';
    next();
  });

  if (Array.isArray(middleware)) {
    app.post('/test', ...middleware, handler);
    app.get('/test/:id', ...middleware, handler);
  } else {
    app.post('/test', middleware, handler);
    app.get('/test/:id', middleware, handler);
  }

  return app;
}

describe('Validation Middleware', () => {
  describe('ValidationError', () => {
    it('should create error with message', () => {
      const error = new ValidationError('Test error');
      expect(error.message).toBe('Test error');
      expect(error.name).toBe('ValidationError');
    });

    it('should create error with errors array', () => {
      const errors = [{ field: 'name', message: 'Required' }];
      const error = new ValidationError('Validation failed', errors);
      expect(error.errors).toEqual(errors);
    });
  });

  describe('requireFields', () => {
    it('should pass when all required fields are present', async () => {
      const app = createTestApp(requireFields(['name', 'email']));

      const response = await request(app)
        .post('/test')
        .send({ name: 'John', email: 'john@example.com' })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should fail when required field is missing', async () => {
      const app = createTestApp(requireFields(['name', 'email']));

      const response = await request(app)
        .post('/test')
        .send({ name: 'John' })
        .expect(400);

      expect(response.body.error).toBe('Validation Error');
      expect(response.body.message).toBe('Missing required fields');
      expect(response.body.details).toHaveLength(1);
      expect(response.body.details[0].field).toBe('email');
    });

    it('should fail when multiple required fields are missing', async () => {
      const app = createTestApp(requireFields(['name', 'email', 'age']));

      const response = await request(app)
        .post('/test')
        .send({})
        .expect(400);

      expect(response.body.details).toHaveLength(3);
    });

    it('should fail when field is null', async () => {
      const app = createTestApp(requireFields(['name']));

      const response = await request(app)
        .post('/test')
        .send({ name: null })
        .expect(400);

      expect(response.body.details[0].field).toBe('name');
    });

    it('should pass when field is empty string (present but empty)', async () => {
      const app = createTestApp(requireFields(['name']));

      const response = await request(app)
        .post('/test')
        .send({ name: '' })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should pass when field is 0 (falsy but present)', async () => {
      const app = createTestApp(requireFields(['count']));

      const response = await request(app)
        .post('/test')
        .send({ count: 0 })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should pass when field is false (falsy but present)', async () => {
      const app = createTestApp(requireFields(['active']));

      const response = await request(app)
        .post('/test')
        .send({ active: false })
        .expect(200);

      expect(response.body.success).toBe(true);
    });
  });

  describe('validateTypes', () => {
    it('should pass when types match', async () => {
      const app = createTestApp(validateTypes({
        name: 'string',
        age: 'number',
        active: 'boolean'
      }));

      const response = await request(app)
        .post('/test')
        .send({ name: 'John', age: 30, active: true })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should fail when string expected but number provided', async () => {
      const app = createTestApp(validateTypes({ name: 'string' }));

      const response = await request(app)
        .post('/test')
        .send({ name: 123 })
        .expect(400);

      expect(response.body.error).toBe('Validation Error');
      expect(response.body.details[0].expected).toBe('string');
      expect(response.body.details[0].actual).toBe('number');
    });

    it('should fail when number expected but string provided', async () => {
      const app = createTestApp(validateTypes({ age: 'number' }));

      const response = await request(app)
        .post('/test')
        .send({ age: 'thirty' })
        .expect(400);

      expect(response.body.details[0].expected).toBe('number');
      expect(response.body.details[0].actual).toBe('string');
    });

    it('should correctly identify arrays', async () => {
      const app = createTestApp(validateTypes({ items: 'array' }));

      const response = await request(app)
        .post('/test')
        .send({ items: [1, 2, 3] })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should fail when array expected but object provided', async () => {
      const app = createTestApp(validateTypes({ items: 'array' }));

      const response = await request(app)
        .post('/test')
        .send({ items: { a: 1 } })
        .expect(400);

      expect(response.body.details[0].expected).toBe('array');
      expect(response.body.details[0].actual).toBe('object');
    });

    it('should skip validation for undefined fields', async () => {
      const app = createTestApp(validateTypes({ name: 'string', age: 'number' }));

      const response = await request(app)
        .post('/test')
        .send({ name: 'John' })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should skip validation for null fields', async () => {
      const app = createTestApp(validateTypes({ name: 'string' }));

      const response = await request(app)
        .post('/test')
        .send({ name: null })
        .expect(200);

      expect(response.body.success).toBe(true);
    });
  });

  describe('validateConstraints', () => {
    describe('numeric constraints', () => {
      it('should pass when number is within range', async () => {
        const app = createTestApp(validateConstraints({
          age: { min: 0, max: 120 }
        }));

        const response = await request(app)
          .post('/test')
          .send({ age: 30 })
          .expect(200);

        expect(response.body.success).toBe(true);
      });

      it('should fail when number is below minimum', async () => {
        const app = createTestApp(validateConstraints({
          age: { min: 0 }
        }));

        const response = await request(app)
          .post('/test')
          .send({ age: -5 })
          .expect(400);

        expect(response.body.details[0].constraint).toBe('min');
        expect(response.body.details[0].limit).toBe(0);
      });

      it('should fail when number exceeds maximum', async () => {
        const app = createTestApp(validateConstraints({
          age: { max: 120 }
        }));

        const response = await request(app)
          .post('/test')
          .send({ age: 150 })
          .expect(400);

        expect(response.body.details[0].constraint).toBe('max');
        expect(response.body.details[0].limit).toBe(120);
      });

      it('should pass at exact boundary values', async () => {
        const app = createTestApp(validateConstraints({
          score: { min: 0, max: 100 }
        }));

        await request(app).post('/test').send({ score: 0 }).expect(200);
        await request(app).post('/test').send({ score: 100 }).expect(200);
      });
    });

    describe('string constraints', () => {
      it('should pass when string length is within range', async () => {
        const app = createTestApp(validateConstraints({
          username: { minLength: 3, maxLength: 20 }
        }));

        const response = await request(app)
          .post('/test')
          .send({ username: 'john_doe' })
          .expect(200);

        expect(response.body.success).toBe(true);
      });

      it('should fail when string is too short', async () => {
        const app = createTestApp(validateConstraints({
          username: { minLength: 3 }
        }));

        const response = await request(app)
          .post('/test')
          .send({ username: 'ab' })
          .expect(400);

        expect(response.body.details[0].constraint).toBe('minLength');
      });

      it('should fail when string is too long', async () => {
        const app = createTestApp(validateConstraints({
          username: { maxLength: 10 }
        }));

        const response = await request(app)
          .post('/test')
          .send({ username: 'this_is_way_too_long' })
          .expect(400);

        expect(response.body.details[0].constraint).toBe('maxLength');
      });

      it('should pass when string matches pattern', async () => {
        const app = createTestApp(validateConstraints({
          email: { pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$' }
        }));

        const response = await request(app)
          .post('/test')
          .send({ email: 'test@example.com' })
          .expect(200);

        expect(response.body.success).toBe(true);
      });

      it('should fail when string does not match pattern', async () => {
        const app = createTestApp(validateConstraints({
          email: { pattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$' }
        }));

        const response = await request(app)
          .post('/test')
          .send({ email: 'invalid-email' })
          .expect(400);

        expect(response.body.details[0].constraint).toBe('pattern');
      });
    });

    describe('enum constraints', () => {
      it('should pass when value is in enum', async () => {
        const app = createTestApp(validateConstraints({
          status: { enum: ['active', 'inactive', 'pending'] }
        }));

        const response = await request(app)
          .post('/test')
          .send({ status: 'active' })
          .expect(200);

        expect(response.body.success).toBe(true);
      });

      it('should fail when value is not in enum', async () => {
        const app = createTestApp(validateConstraints({
          status: { enum: ['active', 'inactive', 'pending'] }
        }));

        const response = await request(app)
          .post('/test')
          .send({ status: 'unknown' })
          .expect(400);

        expect(response.body.details[0].constraint).toBe('enum');
        expect(response.body.details[0].allowed).toEqual(['active', 'inactive', 'pending']);
      });

      it('should work with numeric enums', async () => {
        const app = createTestApp(validateConstraints({
          priority: { enum: [1, 2, 3] }
        }));

        await request(app).post('/test').send({ priority: 2 }).expect(200);

        const failResponse = await request(app)
          .post('/test')
          .send({ priority: 5 })
          .expect(400);

        expect(failResponse.body.details[0].constraint).toBe('enum');
      });
    });
  });

  describe('validateParams', () => {
    it('should pass with valid URL parameter', async () => {
      const app = express();
      app.use(express.json());
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/users/:id', validateParams({ id: { type: 'number' } }), (req, res) => {
        res.json({ id: req.params.id, type: typeof req.params.id });
      });

      const response = await request(app)
        .get('/users/123')
        .expect(200);

      expect(response.body.id).toBe(123);
      expect(response.body.type).toBe('number');
    });

    it('should fail with invalid numeric parameter', async () => {
      const app = express();
      app.use(express.json());
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/users/:id', validateParams({ id: { type: 'number' } }), (req, res) => {
        res.json({ id: req.params.id });
      });

      const response = await request(app)
        .get('/users/abc')
        .expect(400);

      expect(response.body.error).toBe('Validation Error');
    });

    it('should validate parameter pattern', async () => {
      const app = express();
      app.use(express.json());
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/nodes/:name', validateParams({
        name: { pattern: '^redis-[1-3]$' }
      }), (req, res) => {
        res.json({ name: req.params.name });
      });

      await request(app).get('/nodes/redis-1').expect(200);
      await request(app).get('/nodes/redis-2').expect(200);

      const failResponse = await request(app)
        .get('/nodes/redis-99')
        .expect(400);

      expect(failResponse.body.details[0].pattern).toBe('^redis-[1-3]$');
    });

    it('should validate parameter enum', async () => {
      const app = express();
      app.use(express.json());
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/status/:type', validateParams({
        type: { enum: ['healthy', 'unhealthy', 'unknown'] }
      }), (req, res) => {
        res.json({ type: req.params.type });
      });

      await request(app).get('/status/healthy').expect(200);

      const failResponse = await request(app)
        .get('/status/invalid')
        .expect(400);

      expect(failResponse.body.details[0].allowed).toEqual(['healthy', 'unhealthy', 'unknown']);
    });

    it('should validate numeric range in parameters', async () => {
      const app = express();
      app.use(express.json());
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/page/:num', validateParams({
        num: { type: 'number', min: 1, max: 100 }
      }), (req, res) => {
        res.json({ page: req.params.num });
      });

      await request(app).get('/page/50').expect(200);
      await request(app).get('/page/0').expect(400);
      await request(app).get('/page/101').expect(400);
    });
  });

  describe('validateQuery', () => {
    it('should pass with valid numeric query parameter', async () => {
      const app = express();
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/search', validateQuery({ limit: { type: 'number' } }), (req, res) => {
        // Validation passes for valid number string
        res.json({ success: true, originalValue: '10' });
      });

      const response = await request(app)
        .get('/search?limit=10')
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should fail with invalid numeric query parameter', async () => {
      const app = express();
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/search', validateQuery({ limit: { type: 'number' } }), (req, res) => {
        res.json({ limit: req.query.limit });
      });

      const response = await request(app)
        .get('/search?limit=abc')
        .expect(400);

      expect(response.body.error).toBe('Validation Error');
    });

    it('should validate numeric query parameters within range', async () => {
      const app = express();
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/page', validateQuery({ num: { type: 'number', min: 1, max: 100 } }), (req, res) => {
        res.json({ success: true });
      });

      await request(app).get('/page?num=50').expect(200);
      await request(app).get('/page?num=0').expect(400);
      await request(app).get('/page?num=101').expect(400);
    });

    it('should pass with valid boolean query parameters', async () => {
      const app = express();
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/items', validateQuery({ active: { type: 'boolean' } }), (req, res) => {
        res.json({ success: true });
      });

      // Test 'true' and 'false' strings
      await request(app).get('/items?active=true').expect(200);
      await request(app).get('/items?active=false').expect(200);

      // Test '1' and '0' strings
      await request(app).get('/items?active=1').expect(200);
      await request(app).get('/items?active=0').expect(200);
    });

    it('should fail with invalid boolean query parameter', async () => {
      const app = express();
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/items', validateQuery({ active: { type: 'boolean' } }), (req, res) => {
        res.json({ active: req.query.active });
      });

      const response = await request(app)
        .get('/items?active=maybe')
        .expect(400);

      expect(response.body.error).toBe('Validation Error');
    });

    it('should validate required query parameters', async () => {
      const app = express();
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/search', validateQuery({ q: { required: true } }), (req, res) => {
        res.json({ q: req.query.q });
      });

      await request(app).get('/search?q=test').expect(200);

      const failResponse = await request(app)
        .get('/search')
        .expect(400);

      expect(failResponse.body.message).toBe('Invalid query parameters');
    });

    it('should validate query parameter enum', async () => {
      const app = express();
      app.use((req, res, next) => { req.requestId = 'test'; next(); });
      app.get('/items', validateQuery({
        sort: { enum: ['asc', 'desc'] }
      }), (req, res) => {
        res.json({ sort: req.query.sort });
      });

      await request(app).get('/items?sort=asc').expect(200);
      await request(app).get('/items?sort=invalid').expect(400);
    });
  });

  describe('validate (combined validator)', () => {
    it('should combine multiple validations', async () => {
      const validators = validate({
        required: ['name', 'email'],
        types: { name: 'string', age: 'number' },
        constraints: { age: { min: 0, max: 120 } }
      });

      const app = createTestApp(validators);

      const response = await request(app)
        .post('/test')
        .send({ name: 'John', email: 'john@example.com', age: 30 })
        .expect(200);

      expect(response.body.success).toBe(true);
    });

    it('should fail on first validation error (required)', async () => {
      const validators = validate({
        required: ['name', 'email'],
        types: { name: 'string' }
      });

      const app = createTestApp(validators);

      const response = await request(app)
        .post('/test')
        .send({ name: 'John' })
        .expect(400);

      expect(response.body.message).toBe('Missing required fields');
    });

    it('should fail on type validation after required passes', async () => {
      const validators = validate({
        required: ['name'],
        types: { name: 'string', age: 'number' }
      });

      const app = createTestApp(validators);

      const response = await request(app)
        .post('/test')
        .send({ name: 'John', age: 'thirty' })
        .expect(400);

      expect(response.body.message).toBe('Invalid field types');
    });

    it('should return empty array when no validations specified', () => {
      const validators = validate({});
      expect(validators).toHaveLength(0);
    });
  });

  describe('Error response format', () => {
    it('should include requestId in error responses', async () => {
      const app = createTestApp(requireFields(['name']));

      const response = await request(app)
        .post('/test')
        .send({})
        .expect(400);

      expect(response.body.requestId).toBe('test-request-id');
    });

    it('should include all validation error details', async () => {
      const app = createTestApp(validateConstraints({
        age: { min: 0, max: 100 },
        score: { min: 0, max: 100 }
      }));

      const response = await request(app)
        .post('/test')
        .send({ age: -5, score: 150 })
        .expect(400);

      expect(response.body.details).toHaveLength(2);
    });
  });
});
