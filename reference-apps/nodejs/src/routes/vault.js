/**
 * Vault Integration Routes
 *
 * Demonstration endpoints for fetching secrets from Vault.
 */

const express = require('express');
const { vaultClient } = require('../services/vault');
const { logger } = require('../middleware/logging');

const router = express.Router();

/**
 * GET /examples/vault/secret/:serviceName
 * Fetch all secrets for a service
 */
router.get('/secret/:serviceName', async (req, res) => {
  try {
    const { serviceName } = req.params;
    const secrets = await vaultClient.getSecret(serviceName);

    res.json({
      service: serviceName,
      secrets: Object.keys(secrets),
      data: secrets
    });
  } catch (error) {
    logger.error(`Failed to fetch secrets for ${req.params.serviceName}:`, error);
    res.status(503).json({
      error: 'Vault unavailable',
      message: error.message
    });
  }
});

/**
 * GET /examples/vault/secret/:serviceName/:key
 * Fetch specific secret key
 */
router.get('/secret/:serviceName/:key', async (req, res) => {
  try {
    const { serviceName, key } = req.params;
    const value = await vaultClient.getSecretKey(serviceName, key);

    res.json({
      service: serviceName,
      key,
      value
    });
  } catch (error) {
    logger.error(`Failed to fetch secret key ${req.params.serviceName}/${req.params.key}:`, error);
    res.status(404).json({
      error: 'Secret not found',
      message: error.message
    });
  }
});

module.exports = router;
