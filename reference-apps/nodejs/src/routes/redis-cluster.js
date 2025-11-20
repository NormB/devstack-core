/**
 * Redis Cluster Information API endpoints
 *
 * Provides detailed information about Redis cluster configuration:
 * - Cluster nodes and their assigned slots
 * - Slot distribution
 * - Cluster topology
 * - Per-node detailed information
 */

const express = require('express');
const redis = require('redis');
const { logger } = require('../middleware/logging');
const { getVaultSecret } = require('../services/vault');
const config = require('../config');

const router = express.Router();

/**
 * Get cluster nodes information
 */
router.get('/cluster/nodes', async (req, res) => {
  try {
    // Get Redis credentials from Vault
    const creds = await getVaultSecret('redis-1');
    const password = creds.password;

    const client = redis.createClient({
      socket: {
        host: config.redis.host,
        port: config.redis.port,
        connectTimeout: 5000
      },
      password,
    });

    await client.connect();

    // Get cluster nodes information
    const clusterNodesRaw = await client.sendCommand(['CLUSTER', 'NODES']);
    await client.quit();

    // Parse the output
    const nodes = [];
    const lines = clusterNodesRaw.split('\n');

    for (const line of lines) {
      if (!line.trim()) continue;

      const parts = line.split(' ');
      if (parts.length < 8) continue;

      const nodeId = parts[0];
      const address = parts[1];
      const flags = parts[2];
      const masterId = parts[3] !== '-' ? parts[3] : null;
      const pingSent = parts[4];
      const pongRecv = parts[5];
      const configEpoch = parts[6];
      const linkState = parts[7];

      // Parse slots
      const slotRanges = [];
      for (let i = 8; i < parts.length; i++) {
        const slotInfo = parts[i];
        if (slotInfo.includes('-') && !slotInfo.startsWith('[')) {
          const [start, end] = slotInfo.split('-');
          slotRanges.push({ start: parseInt(start), end: parseInt(end) });
        } else if (/^\d+$/.test(slotInfo)) {
          slotRanges.push({ start: parseInt(slotInfo), end: parseInt(slotInfo) });
        }
      }

      // Parse address
      const hostPort = address.split('@')[0];
      const lastColon = hostPort.lastIndexOf(':');
      const host = hostPort.substring(0, lastColon);
      const port = parseInt(hostPort.substring(lastColon + 1));

      // Determine role
      let role = 'unknown';
      if (flags.includes('master')) role = 'master';
      else if (flags.includes('slave')) role = 'replica';

      nodes.push({
        node_id: nodeId,
        host,
        port,
        role,
        flags: flags.split(','),
        master_id: masterId,
        ping_sent: pingSent,
        pong_recv: pongRecv,
        config_epoch: configEpoch,
        link_state: linkState,
        slot_ranges: slotRanges,
        slots_count: slotRanges.reduce((sum, range) => sum + (range.end - range.start + 1), 0)
      });
    }

    res.json({
      total_nodes: nodes.length,
      nodes,
      raw: clusterNodesRaw
    });
  } catch (error) {
    logger.error('Error fetching cluster nodes', { error: error.message, requestId: req.requestId });
    res.status(500).json({
      error: 'Failed to fetch cluster nodes',
      message: error.message
    });
  }
});

/**
 * Get cluster slots information
 */
router.get('/cluster/slots', async (req, res) => {
  try {
    const creds = await getVaultSecret('redis-1');
    const password = creds.password;

    const client = redis.createClient({
      socket: {
        host: config.redis.host,
        port: config.redis.port,
        connectTimeout: 5000
      },
      password,
    });

    await client.connect();

    const clusterSlotsRaw = await client.sendCommand(['CLUSTER', 'SLOTS']);
    await client.quit();

    res.json({
      slots: clusterSlotsRaw,
      total_slot_ranges: Array.isArray(clusterSlotsRaw) ? clusterSlotsRaw.length : 0
    });
  } catch (error) {
    logger.error('Error fetching cluster slots', { error: error.message, requestId: req.requestId });
    res.status(500).json({
      error: 'Failed to fetch cluster slots',
      message: error.message
    });
  }
});

/**
 * Get cluster info
 */
router.get('/cluster/info', async (req, res) => {
  try {
    const creds = await getVaultSecret('redis-1');
    const password = creds.password;

    const client = redis.createClient({
      socket: {
        host: config.redis.host,
        port: config.redis.port,
        connectTimeout: 5000
      },
      password,
    });

    await client.connect();

    const clusterInfoRaw = await client.sendCommand(['CLUSTER', 'INFO']);
    await client.quit();

    // Parse cluster info
    const info = {};
    const lines = clusterInfoRaw.split('\r\n');
    for (const line of lines) {
      if (line.includes(':')) {
        const [key, value] = line.split(':');
        info[key] = value;
      }
    }

    res.json({
      cluster_info: info,
      raw: clusterInfoRaw
    });
  } catch (error) {
    logger.error('Error fetching cluster info', { error: error.message, requestId: req.requestId });
    res.status(500).json({
      error: 'Failed to fetch cluster info',
      message: error.message
    });
  }
});

/**
 * Get detailed information for a specific node
 */
router.get('/nodes/:node_name/info', async (req, res) => {
  try {
    const { node_name } = req.params;
    const creds = await getVaultSecret('redis-1');
    const password = creds.password;

    const client = redis.createClient({
      socket: {
        host: node_name,
        port: 6379,
        connectTimeout: 5000
      },
      password,
    });

    await client.connect();

    const serverInfo = await client.info();
    await client.quit();

    // Parse INFO response
    const sections = {};
    let currentSection = 'general';
    sections[currentSection] = {};

    const lines = serverInfo.split('\r\n');
    for (const line of lines) {
      if (line.startsWith('#')) {
        currentSection = line.substring(2).toLowerCase().trim();
        sections[currentSection] = {};
      } else if (line.includes(':')) {
        const [key, value] = line.split(':');
        sections[currentSection][key] = value;
      }
    }

    res.json({
      node: node_name,
      sections,
      raw: serverInfo
    });
  } catch (error) {
    logger.error('Error fetching node info', { node: req.params.node_name, error: error.message, requestId: req.requestId });
    res.status(500).json({
      error: 'Failed to fetch node info',
      message: error.message,
      node: req.params.node_name
    });
  }
});

module.exports = router;
