/**
 * Vault service for secrets management
 */

import vault from 'node-vault';
import config from '../config';
import { logger } from '../middleware/logging';
import { VaultSecretData } from '../types';

// Initialize Vault client
const vaultClient = vault({
  apiVersion: 'v1',
  endpoint: config.vault.addr,
  token: config.vault.token
});

/**
 * Get all secrets for a service from Vault
 */
export async function getSecret(serviceName: string): Promise<VaultSecretData> {
  try {
    const path = `secret/data/${serviceName}`;
    logger.info(`Fetching secret from Vault: ${path}`);

    const result = await vaultClient.read(path);

    if (!result || !result.data || !result.data.data) {
      throw new Error(`No data found at path: ${path}`);
    }

    return result.data.data as VaultSecretData;
  } catch (error) {
    logger.error('Error fetching secret from Vault', {
      serviceName,
      error: error instanceof Error ? error.message : String(error)
    });
    throw error;
  }
}

/**
 * Get a specific key from a service's secrets in Vault
 */
export async function getSecretKey(serviceName: string, key: string): Promise<string | null> {
  try {
    const secretData = await getSecret(serviceName);
    return secretData[key] || null;
  } catch (error) {
    logger.error('Error fetching secret key from Vault', {
      serviceName,
      key,
      error: error instanceof Error ? error.message : String(error)
    });
    throw error;
  }
}

/**
 * Check if Vault is accessible and healthy
 */
export async function checkVaultHealth(): Promise<boolean> {
  try {
    const health = await vaultClient.health();
    return health.sealed === false && health.initialized === true;
  } catch (error) {
    logger.error('Vault health check failed', {
      error: error instanceof Error ? error.message : String(error)
    });
    return false;
  }
}
