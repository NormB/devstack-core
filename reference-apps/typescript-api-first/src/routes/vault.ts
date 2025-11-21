/**
 * Vault Integration Routes
 *
 * Demonstration endpoints for fetching secrets from Vault.
 */

import { Router, Request, Response } from 'express';
import { getSecret, getSecretKey } from '../services/vault';
import { logger } from '../middleware/logging';
import { SecretResponse, SecretKeyResponse } from '../types';

const router = Router();

/**
 * GET /examples/vault/secret/:serviceName
 * Fetch all secrets for a service
 */
router.get('/secret/:serviceName', async (req: Request, res: Response): Promise<void> => {
  try {
    const { serviceName } = req.params;
    const secrets = await getSecret(serviceName);

    const response: SecretResponse = {
      service: serviceName,
      data: secrets,
      note: 'Retrieved from Vault KV secrets engine'
    };

    res.json(response);
  } catch (error) {
    logger.error(`Failed to fetch secrets for ${req.params.serviceName}`, {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(503).json({
      error: 'Vault unavailable',
      message: error instanceof Error ? error.message : String(error)
    });
  }
});

/**
 * GET /examples/vault/secret/:serviceName/:key
 * Fetch specific secret key
 */
router.get('/secret/:serviceName/:key', async (req: Request, res: Response): Promise<void> => {
  try {
    const { serviceName, key } = req.params;
    const value = await getSecretKey(serviceName, key);

    const response: SecretKeyResponse = {
      service: serviceName,
      key,
      value,
      note: 'Retrieved from Vault KV secrets engine'
    };

    res.json(response);
  } catch (error) {
    logger.error(`Failed to fetch secret key ${req.params.serviceName}/${req.params.key}`, {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(404).json({
      error: 'Secret not found',
      message: error instanceof Error ? error.message : String(error)
    });
  }
});

export default router;
