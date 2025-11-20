const request = require('supertest');

const baseURL = process.env.TEST_URL || 'http://localhost:8003';

describe('Health Check Endpoints', () => {
  test('GET / returns API information', async () => {
    const response = await request(baseURL).get('/');
    expect(response.status).toBe(200);
    expect(response.body.name).toBe('DevStack Core Node.js Reference API');
    expect(response.body.language).toBe('Node.js');
  });

  test('GET /health/ returns simple health', async () => {
    const response = await request(baseURL).get('/health/');
    expect(response.status).toBe(200);
    expect(response.body.status).toBe('healthy');
  });

  test('GET /health/vault returns vault status', async () => {
    const response = await request(baseURL).get('/health/vault');
    expect([200, 503]).toContain(response.status);
    expect(response.body).toHaveProperty('status');
  });

  test('GET /health/all returns aggregate health', async () => {
    const response = await request(baseURL).get('/health/all');
    expect([200, 503]).toContain(response.status);
    expect(response.body).toHaveProperty('services');
    expect(response.body.services).toHaveProperty('vault');
    expect(response.body.services).toHaveProperty('postgres');
    expect(response.body.services).toHaveProperty('redis');
  });
});

describe('Vault Integration', () => {
  test('GET /examples/vault/secret/postgres returns credentials', async () => {
    const response = await request(baseURL).get('/examples/vault/secret/postgres');
    expect([200, 503]).toContain(response.status);
    if (response.status === 200) {
      expect(response.body).toHaveProperty('service', 'postgres');
      expect(response.body).toHaveProperty('secrets');
    }
  });
});

describe('Metrics', () => {
  test('GET /metrics endpoint is accessible', async () => {
    const response = await request(baseURL).get('/metrics');
    expect(response.status).toBe(200);
    // Content type should be text/plain for Prometheus format
    expect(response.headers['content-type']).toContain('text/plain');
  });
});
