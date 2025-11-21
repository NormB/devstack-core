/**
 * Redis Cluster Information API endpoints
 *
 * Provides detailed information about Redis cluster configuration:
 * - Cluster nodes and their assigned slots
 * - Slot distribution
 * - Cluster topology
 * - Per-node detailed information
 */

import { Router, Request, Response } from 'express';
import { createClient } from 'redis';
import { getSecret } from '../services/vault';
import config from '../config';
import { logger } from '../middleware/logging';
import { RedisClusterNode, RedisClusterNodesResponse, RedisClusterSlotsResponse, RedisClusterInfoResponse } from '../types';

const router = Router();

/**
 * GET /redis/cluster/nodes
 * Get cluster nodes information
 */
router.get('/cluster/nodes', async (req: Request, res: Response): Promise<void> => {
  let client: ReturnType<typeof createClient> | null = null;
  try {
    // Get Redis credentials from Vault
    const creds = await getSecret('redis-1');

    client = createClient({
      socket: {
        host: config.cache.redis.host,
        port: config.cache.redis.port,
        connectTimeout: 5000
      },
      password: creds.password
    });

    await client.connect();

    // Get cluster nodes information
    const clusterNodesRaw = await client.sendCommand(['CLUSTER', 'NODES']) as string;
    await client.quit();

    // Parse the output
    const nodes: RedisClusterNode[] = [];
    const lines = clusterNodesRaw.split('\n');

    for (const line of lines) {
      if (!line.trim()) continue;

      const parts = line.split(' ');
      if (parts.length < 8) continue;

      const nodeId = parts[0];
      const address = parts[1];
      const flags = parts[2];
      const linkState = parts[7];

      // Parse address (format: host:port@cport or ip:port@cport)
      const hostPort = address.split('@')[0];
      const lastColon = hostPort.lastIndexOf(':');
      const host = hostPort.substring(0, lastColon);
      const port = parseInt(hostPort.substring(lastColon + 1));

      // Determine role
      let role = 'unknown';
      if (flags.includes('master')) role = 'master';
      else if (flags.includes('slave') || flags.includes('replica')) role = 'replica';

      // Parse slot ranges
      let slots = '';
      const slotParts: string[] = [];
      for (let i = 8; i < parts.length; i++) {
        const slotInfo = parts[i];
        if (slotInfo && !slotInfo.startsWith('[')) {
          slotParts.push(slotInfo);
        }
      }
      if (slotParts.length > 0) {
        slots = slotParts.join(' ');
      }

      nodes.push({
        id: nodeId,
        address: `${host}:${port}`,
        role,
        slots,
        flags: flags.split(','),
        link_state: linkState
      });
    }

    // Get cluster info for additional details
    const clusterInfoRaw = await client.connect().then(async () => {
      const info = await client!.sendCommand(['CLUSTER', 'INFO']) as string;
      await client!.quit();
      return info;
    });

    const clusterInfo: Record<string, string> = {};
    const infoLines = clusterInfoRaw.split('\r\n');
    for (const line of infoLines) {
      if (line.includes(':')) {
        const [key, value] = line.split(':');
        clusterInfo[key] = value;
      }
    }

    const response: RedisClusterNodesResponse = {
      cluster_enabled: true,
      cluster_state: clusterInfo['cluster_state'] || 'unknown',
      cluster_size: nodes.filter(n => n.role === 'master').length,
      nodes
    };

    res.json(response);
  } catch (error) {
    logger.error('Error fetching cluster nodes', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(500).json({
      error: 'Failed to fetch cluster nodes',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (client) {
      await client.quit().catch(() => {});
    }
  }
});

/**
 * GET /redis/cluster/slots
 * Get cluster slots information
 */
router.get('/cluster/slots', async (req: Request, res: Response): Promise<void> => {
  let client: ReturnType<typeof createClient> | null = null;
  try {
    const creds = await getSecret('redis-1');

    client = createClient({
      socket: {
        host: config.cache.redis.host,
        port: config.cache.redis.port,
        connectTimeout: 5000
      },
      password: creds.password
    });

    await client.connect();

    const clusterSlotsRaw = await client.sendCommand(['CLUSTER', 'SLOTS']);
    await client.quit();

    // Parse slots information
    const slotRanges: Array<{ start: number; end: number; master: string }> = [];
    let totalSlots = 0;

    if (Array.isArray(clusterSlotsRaw)) {
      for (const slotInfo of clusterSlotsRaw) {
        if (Array.isArray(slotInfo) && slotInfo.length >= 3) {
          const start = Number(slotInfo[0]);
          const end = Number(slotInfo[1]);
          const masterInfo = slotInfo[2];

          let masterAddress = 'unknown';
          if (Array.isArray(masterInfo) && masterInfo.length >= 2) {
            masterAddress = `${masterInfo[0]}:${masterInfo[1]}`;
          }

          slotRanges.push({ start, end, master: masterAddress });
          totalSlots += (end - start + 1);
        }
      }
    }

    const response: RedisClusterSlotsResponse = {
      slots_covered: totalSlots,
      total_slots: 16384,
      coverage_percentage: (totalSlots / 16384) * 100,
      slot_ranges: slotRanges
    };

    res.json(response);
  } catch (error) {
    logger.error('Error fetching cluster slots', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(500).json({
      error: 'Failed to fetch cluster slots',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (client) {
      await client.quit().catch(() => {});
    }
  }
});

/**
 * GET /redis/cluster/info
 * Get cluster info
 */
router.get('/cluster/info', async (req: Request, res: Response): Promise<void> => {
  let client: ReturnType<typeof createClient> | null = null;
  try {
    const creds = await getSecret('redis-1');

    client = createClient({
      socket: {
        host: config.cache.redis.host,
        port: config.cache.redis.port,
        connectTimeout: 5000
      },
      password: creds.password
    });

    await client.connect();

    const clusterInfoRaw = await client.sendCommand(['CLUSTER', 'INFO']) as string;
    await client.quit();

    // Parse cluster info
    const info: RedisClusterInfoResponse = {
      cluster_state: '',
      cluster_slots_assigned: 0,
      cluster_slots_ok: 0,
      cluster_slots_fail: 0,
      cluster_known_nodes: 0,
      cluster_size: 0
    };

    const lines = clusterInfoRaw.split('\r\n');
    for (const line of lines) {
      if (line.includes(':')) {
        const [key, value] = line.split(':');
        const numValue = parseInt(value);

        switch (key) {
          case 'cluster_state':
            info.cluster_state = value;
            break;
          case 'cluster_slots_assigned':
            info.cluster_slots_assigned = numValue;
            break;
          case 'cluster_slots_ok':
            info.cluster_slots_ok = numValue;
            break;
          case 'cluster_slots_fail':
            info.cluster_slots_fail = numValue;
            break;
          case 'cluster_known_nodes':
            info.cluster_known_nodes = numValue;
            break;
          case 'cluster_size':
            info.cluster_size = numValue;
            break;
          default:
            // Store other fields as-is
            if (!isNaN(numValue)) {
              info[key] = numValue;
            } else {
              info[key] = value;
            }
        }
      }
    }

    res.json(info);
  } catch (error) {
    logger.error('Error fetching cluster info', {
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(500).json({
      error: 'Failed to fetch cluster info',
      message: error instanceof Error ? error.message : String(error)
    });
  } finally {
    if (client) {
      await client.quit().catch(() => {});
    }
  }
});

/**
 * GET /redis/nodes/:nodeName/info
 * Get detailed information for a specific node
 */
router.get('/nodes/:nodeName/info', async (req: Request, res: Response): Promise<void> => {
  let client: ReturnType<typeof createClient> | null = null;
  try {
    const { nodeName } = req.params;
    const creds = await getSecret('redis-1');

    client = createClient({
      socket: {
        host: nodeName,
        port: 6379,
        connectTimeout: 5000
      },
      password: creds.password
    });

    await client.connect();

    const serverInfo = await client.info();
    await client.quit();

    // Parse INFO response into sections
    const sections: Record<string, Record<string, string>> = {};
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
      node: nodeName,
      sections,
      raw: serverInfo
    });
  } catch (error) {
    logger.error('Error fetching node info', {
      node: req.params.nodeName,
      error: error instanceof Error ? error.message : String(error)
    });
    res.status(500).json({
      error: 'Failed to fetch node info',
      message: error instanceof Error ? error.message : String(error),
      node: req.params.nodeName
    });
  } finally {
    if (client) {
      await client.quit().catch(() => {});
    }
  }
});

export default router;
