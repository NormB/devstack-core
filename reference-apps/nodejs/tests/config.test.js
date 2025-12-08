/**
 * Configuration Tests
 *
 * Tests for configuration loading and validation.
 */

describe('Configuration', () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it('should load default configuration', () => {
    const config = require('../src/config');

    expect(config.http.port).toBe(8003);
    expect(config.http.host).toBe('0.0.0.0');
    expect(config.vault.address).toBe('http://vault:8200');
    expect(config.postgres.host).toBe('postgres');
    expect(config.mysql.host).toBe('mysql');
    expect(config.mongodb.host).toBe('mongodb');
    expect(config.redis.host).toBe('redis-1');
    expect(config.rabbitmq.host).toBe('rabbitmq');
  });

  it('should load custom port from environment', () => {
    process.env.HTTP_PORT = '9000';
    jest.resetModules();
    const config = require('../src/config');

    expect(config.http.port).toBe(9000);
  });

  it('should load custom Vault address from environment', () => {
    process.env.VAULT_ADDR = 'http://custom-vault:8200';
    jest.resetModules();
    const config = require('../src/config');

    expect(config.vault.address).toBe('http://custom-vault:8200');
  });

  it('should have correct Redis cluster nodes', () => {
    const config = require('../src/config');

    expect(config.redis.nodes).toHaveLength(3);
    expect(config.redis.nodes[0]).toEqual({ host: 'redis-1', port: 6379 });
    expect(config.redis.nodes[1]).toEqual({ host: 'redis-2', port: 6379 });
    expect(config.redis.nodes[2]).toEqual({ host: 'redis-3', port: 6379 });
  });

  it('should have correct application metadata', () => {
    const config = require('../src/config');

    expect(config.app.name).toBe('DevStack Core Node.js Reference API');
    expect(config.app.language).toBe('Node.js');
    expect(config.app.framework).toBe('Express');
    expect(config.app.version).toBeDefined();
  });

  it('should enable debug in development', () => {
    process.env.NODE_ENV = 'development';
    jest.resetModules();
    const config = require('../src/config');

    expect(config.debug).toBe(true);
  });

  it('should respect DEBUG environment variable', () => {
    process.env.NODE_ENV = 'production';
    process.env.DEBUG = 'true';
    jest.resetModules();
    const config = require('../src/config');

    expect(config.debug).toBe(true);
  });

  it('should parse HTTPS configuration', () => {
    process.env.HTTPS_PORT = '8446';
    process.env.NODEJS_API_ENABLE_TLS = 'true';
    jest.resetModules();
    const config = require('../src/config');

    expect(config.https.port).toBe(8446);
    expect(config.https.enabled).toBe(true);
  });
});
