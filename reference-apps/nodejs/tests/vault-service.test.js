/**
 * Vault Service Tests
 *
 * Unit tests for the VaultClient wrapper around node-vault. The node-vault
 * factory is mocked, so no Vault server is involved; the AppRole path reads
 * its role-id and secret-id from a temporary directory created per test.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const mockClient = {
  token: null,
  read: jest.fn(),
  list: jest.fn(),
  health: jest.fn(),
  approleLogin: jest.fn()
};

jest.mock('node-vault', () => jest.fn(() => mockClient));

// The constructor starts the AppRole login without awaiting it; let the
// pending promise chain settle before asserting on its outcome.
const settle = () => new Promise(resolve => setImmediate(resolve));

describe('VaultClient', () => {
  const originalEnv = process.env;
  let approleDir;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv, VAULT_TOKEN: 'root-token', VAULT_APPROLE_DIR: '' };
    mockClient.token = null;
    for (const fn of [mockClient.read, mockClient.list, mockClient.health, mockClient.approleLogin]) {
      fn.mockReset();
    }
  });

  afterEach(() => {
    if (approleDir) {
      fs.rmSync(approleDir, { recursive: true, force: true });
      approleDir = undefined;
    }
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  const load = () => require('../src/services/vault');

  const makeAppRoleDir = (files) => {
    approleDir = fs.mkdtempSync(path.join(os.tmpdir(), 'devstack-approle-'));
    for (const [name, content] of Object.entries(files)) {
      fs.writeFileSync(path.join(approleDir, name), content);
    }
    process.env.VAULT_APPROLE_DIR = approleDir;
  };

  describe('authentication', () => {
    it('uses token auth when no AppRole directory is configured', () => {
      load();
      expect(mockClient.token).toBe('root-token');
      expect(mockClient.approleLogin).not.toHaveBeenCalled();
    });

    it('logs in with AppRole credentials read from the directory', async () => {
      makeAppRoleDir({ 'role-id': 'role-1\n', 'secret-id': 'secret-1\n' });
      mockClient.approleLogin.mockResolvedValue({ auth: { client_token: 'approle-token' } });

      load();
      await settle();

      expect(mockClient.approleLogin).toHaveBeenCalledWith({ role_id: 'role-1', secret_id: 'secret-1' });
      expect(mockClient.token).toBe('approle-token');
    });

    it('falls back to token auth when AppRole login returns no token', async () => {
      makeAppRoleDir({ 'role-id': 'role-1', 'secret-id': 'secret-1' });
      mockClient.approleLogin.mockResolvedValue({ auth: {} });

      load();
      await settle();

      expect(mockClient.token).toBe('root-token');
    });

    it('falls back to token auth when AppRole login fails', async () => {
      makeAppRoleDir({ 'role-id': 'role-1', 'secret-id': 'secret-1' });
      mockClient.approleLogin.mockRejectedValue(new Error('permission denied'));

      load();
      await settle();

      expect(mockClient.token).toBe('root-token');
    });

    it('falls back to token auth when the credential files are missing', () => {
      makeAppRoleDir({ 'role-id': 'role-1' });

      load();

      expect(mockClient.approleLogin).not.toHaveBeenCalled();
      expect(mockClient.token).toBe('root-token');
    });
  });

  describe('getSecret', () => {
    it('returns the KV v2 data for a service', async () => {
      mockClient.read.mockResolvedValue({ data: { data: { user: 'app', password: 'pw' } } });
      const { vaultClient } = load();

      await expect(vaultClient.getSecret('postgres')).resolves.toEqual({ user: 'app', password: 'pw' });
      expect(mockClient.read).toHaveBeenCalledWith('secret/data/postgres');
    });

    it('rejects when the path holds no data', async () => {
      mockClient.read.mockResolvedValue({ data: {} });
      const { vaultClient } = load();

      await expect(vaultClient.getSecret('postgres'))
        .rejects.toThrow('Vault error fetching postgres: Secret not found: postgres');
    });

    it('wraps a client failure with the service name', async () => {
      mockClient.read.mockRejectedValue(new Error('connect ECONNREFUSED'));
      const { vaultClient } = load();

      await expect(vaultClient.getSecret('mysql'))
        .rejects.toThrow('Vault error fetching mysql: connect ECONNREFUSED');
    });
  });

  describe('getSecretKey', () => {
    it('returns one key of the service secret', async () => {
      mockClient.read.mockResolvedValue({ data: { data: { user: 'app', password: 'pw' } } });
      const { vaultClient } = load();

      await expect(vaultClient.getSecretKey('postgres', 'password')).resolves.toBe('pw');
    });

    it('rejects when the key is absent', async () => {
      mockClient.read.mockResolvedValue({ data: { data: { user: 'app' } } });
      const { vaultClient } = load();

      await expect(vaultClient.getSecretKey('postgres', 'password'))
        .rejects.toThrow("Key 'password' not found in postgres secrets");
    });
  });

  describe('healthCheck', () => {
    it('reports a reachable Vault as healthy with its status fields', async () => {
      mockClient.health.mockResolvedValue({ initialized: true, sealed: false, version: '1.15.0' });
      const { vaultClient } = load();

      await expect(vaultClient.healthCheck()).resolves.toEqual({
        status: 'healthy',
        initialized: true,
        sealed: false,
        version: '1.15.0'
      });
    });

    it('reports an unreachable Vault as unhealthy instead of throwing', async () => {
      mockClient.health.mockRejectedValue(new Error('connect ECONNREFUSED'));
      const { vaultClient } = load();

      await expect(vaultClient.healthCheck()).resolves.toEqual({
        status: 'unhealthy',
        error: 'connect ECONNREFUSED'
      });
    });
  });

  describe('listSecrets', () => {
    it('lists the keys under the default metadata path', async () => {
      mockClient.list.mockResolvedValue({ data: { keys: ['postgres', 'redis-1'] } });
      const { vaultClient } = load();

      await expect(vaultClient.listSecrets()).resolves.toEqual(['postgres', 'redis-1']);
      expect(mockClient.list).toHaveBeenCalledWith('secret/metadata');
    });

    it('returns an empty list when the path has no keys', async () => {
      mockClient.list.mockResolvedValue({ data: {} });
      const { vaultClient } = load();

      await expect(vaultClient.listSecrets('secret/metadata/empty')).resolves.toEqual([]);
    });

    it('wraps a client failure', async () => {
      mockClient.list.mockRejectedValue(new Error('permission denied'));
      const { vaultClient } = load();

      await expect(vaultClient.listSecrets()).rejects.toThrow('Vault list error: permission denied');
    });
  });
});
