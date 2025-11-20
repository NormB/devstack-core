/**
 * Vault Service Client
 *
 * Wrapper around node-vault for fetching secrets from HashiCorp Vault.
 * Provides a simple interface for getting service credentials.
 */

const vault = require('node-vault');
const config = require('../config');
const logger = require('../middleware/logging').logger;
const fs = require('fs');
const path = require('path');

class VaultClient {
  constructor() {
    // Initialize base client
    this.client = vault({
      apiVersion: 'v1',
      endpoint: config.vault.address,
      requestOptions: {
        timeout: config.vault.timeout
      }
    });

    // Try AppRole authentication first
    if (config.vault.appRoleDir && fs.existsSync(config.vault.appRoleDir)) {
      this._initWithAppRole();
    } else {
      // Fall back to token authentication
      this.client.token = config.vault.token;
    }
  }

  /**
   * Initialize Vault client with AppRole authentication
   * @private
   */
  _initWithAppRole() {
    try {
      const roleIdPath = path.join(config.vault.appRoleDir, 'role-id');
      const secretIdPath = path.join(config.vault.appRoleDir, 'secret-id');

      const roleId = fs.readFileSync(roleIdPath, 'utf8').trim();
      const secretId = fs.readFileSync(secretIdPath, 'utf8').trim();

      // Login with AppRole (this will be done async in constructor)
      this._loginWithAppRole(roleId, secretId);
    } catch (error) {
      logger.warn(`AppRole authentication failed: ${error.message}, falling back to token auth`);
      this.client.token = config.vault.token;
    }
  }

  /**
   * Login to Vault with AppRole credentials
   * @private
   * @param {string} roleId - The AppRole role ID
   * @param {string} secretId - The AppRole secret ID
   */
  async _loginWithAppRole(roleId, secretId) {
    try {
      const result = await this.client.approleLogin({
        role_id: roleId,
        secret_id: secretId
      });

      if (result && result.auth && result.auth.client_token) {
        this.client.token = result.auth.client_token;
        logger.info('Successfully authenticated to Vault using AppRole');
      } else {
        throw new Error('AppRole login returned no token');
      }
    } catch (error) {
      logger.warn(`AppRole login failed: ${error.message}, falling back to token auth`);
      this.client.token = config.vault.token;
    }
  }

  /**
   * Get all secrets for a service
   * @param {string} serviceName - Name of the service (e.g., 'postgres', 'redis-1')
   * @returns {Promise<Object>} Secret data
   */
  async getSecret(serviceName) {
    try {
      const path = `secret/data/${serviceName}`;
      logger.debug(`Fetching secret from Vault: ${path}`);

      const result = await this.client.read(path);

      if (!result || !result.data || !result.data.data) {
        throw new Error(`Secret not found: ${serviceName}`);
      }

      logger.debug(`Successfully fetched secret for: ${serviceName}`);
      return result.data.data;
    } catch (error) {
      logger.error(`Failed to fetch secret ${serviceName}:`, error.message);
      throw new Error(`Vault error fetching ${serviceName}: ${error.message}`);
    }
  }

  /**
   * Get a specific key from a service's secrets
   * @param {string} serviceName - Name of the service
   * @param {string} key - Specific key to retrieve
   * @returns {Promise<string>} Secret value
   */
  async getSecretKey(serviceName, key) {
    try {
      const secrets = await this.getSecret(serviceName);

      if (!(key in secrets)) {
        throw new Error(`Key '${key}' not found in ${serviceName} secrets`);
      }

      return secrets[key];
    } catch (error) {
      logger.error(`Failed to fetch secret key ${serviceName}/${key}:`, error.message);
      throw error;
    }
  }

  /**
   * Check Vault health and status
   * @returns {Promise<Object>} Health status
   */
  async healthCheck() {
    try {
      const health = await this.client.health();

      return {
        status: 'healthy',
        initialized: health.initialized || false,
        sealed: health.sealed || false,
        version: health.version || 'unknown'
      };
    } catch (error) {
      logger.error('Vault health check failed:', error.message);
      return {
        status: 'unhealthy',
        error: error.message
      };
    }
  }

  /**
   * List all secrets at a path
   * @param {string} path - Path to list (default: 'secret/metadata')
   * @returns {Promise<Array>} List of secret names
   */
  async listSecrets(path = 'secret/metadata') {
    try {
      const result = await this.client.list(path);
      return result.data.keys || [];
    } catch (error) {
      logger.error(`Failed to list secrets at ${path}:`, error.message);
      throw new Error(`Vault list error: ${error.message}`);
    }
  }
}

// Export singleton instance
const vaultClient = new VaultClient();

module.exports = {
  vaultClient,
  VaultClient
};
