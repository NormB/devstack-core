/**
 * Configuration Tests
 *
 * These assert the shape `src/config.ts` actually exports.
 *
 * They previously asserted a FLAT config — `config.http`, `config.redis`,
 * `config.postgres` — while the source has long exported a nested one:
 * `server`, `cache.redis`, `database.postgres`. The file therefore had not
 * compiled, and so had never run, for as long as that refactor is old. It was
 * invisible because the CI test step carries `continue-on-error: true`.
 *
 * Two assertions are deliberately NOT carried over, because they described
 * behaviour the source does not have and never did. Restoring them would mean
 * changing the application, which is a decision to take deliberately rather
 * than smuggle in behind a test repair:
 *
 *   - `config.redis.nodes` — a three-node cluster list. `CacheConfig` has a
 *     single host and port; there is no node list to assert.
 *   - "should enable debug in development" — `debug` is `DEBUG === 'true'`
 *     alone, so NODE_ENV has no bearing on it. The environment-variable case
 *     below covers what the code does do.
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

  it('should load default configuration', async () => {
    const { default: config } = await import('../src/config');

    expect(config.server.httpPort).toBe(8005);
    expect(config.server.httpsPort).toBe(8448);
    expect(config.vault.addr).toBe('http://vault:8200');
    expect(config.database.postgres.host).toBe('postgres');
    expect(config.database.mysql.host).toBe('mysql');
    expect(config.database.mongodb.host).toBe('mongodb');
    expect(config.cache.redis.host).toBe('redis-1');
    expect(config.messaging.rabbitmq.host).toBe('rabbitmq');
  });

  it('should load default ports', async () => {
    const { default: config } = await import('../src/config');

    expect(config.database.postgres.port).toBe(5432);
    expect(config.database.mysql.port).toBe(3306);
    expect(config.database.mongodb.port).toBe(27017);
    expect(config.cache.redis.port).toBe(6379);
    expect(config.messaging.rabbitmq.port).toBe(5672);
  });

  it('should load custom port from environment', async () => {
    process.env.HTTP_PORT = '9000';
    jest.resetModules();
    const { default: config } = await import('../src/config');

    expect(config.server.httpPort).toBe(9000);
  });

  it('should load custom Vault address from environment', async () => {
    process.env.VAULT_ADDR = 'http://custom-vault:8200';
    jest.resetModules();
    const { default: config } = await import('../src/config');

    expect(config.vault.addr).toBe('http://custom-vault:8200');
  });

  it('should have correct application metadata', async () => {
    const { default: config } = await import('../src/config');

    expect(config.app.name).toBe('DevStack Core TypeScript API-First Reference');
    expect(config.app.language).toBe('TypeScript');
    expect(config.app.framework).toBe('Express');
    expect(config.app.version).toBeDefined();
  });

  it('should respect the DEBUG environment variable', async () => {
    process.env.DEBUG = 'true';
    jest.resetModules();
    const { default: config } = await import('../src/config');

    expect(config.server.debug).toBe(true);
  });

  it('should leave debug off when DEBUG is unset', async () => {
    delete process.env.DEBUG;
    jest.resetModules();
    const { default: config } = await import('../src/config');

    expect(config.server.debug).toBe(false);
  });

  it('should default the environment to development', async () => {
    delete process.env.NODE_ENV;
    jest.resetModules();
    const { default: config } = await import('../src/config');

    expect(config.server.environment).toBe('development');
  });
});
