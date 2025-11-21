/**
 * Type definitions for TypeScript API
 */

import { Request } from 'express';

// Extend Express Request with custom properties
export interface CustomRequest extends Request {
  requestId?: string;
}

// Health check types
export interface ServiceHealth {
  status: 'healthy' | 'unhealthy';
  details?: Record<string, any>;
}

export interface HealthStatus {
  status: 'healthy' | 'degraded' | 'unhealthy';
  services?: Record<string, ServiceHealth>;
}

// Vault types
export interface VaultSecretData {
  [key: string]: string;
}

export interface SecretResponse {
  service: string;
  data: VaultSecretData;
  note: string;
}

export interface SecretKeyResponse {
  service: string;
  key: string;
  value: string | null;
  note: string;
}

// Cache types
export interface CacheGetResponse {
  key: string;
  value: string | null;
  exists: boolean;
  ttl: number | string | null;
}

export interface CacheSetRequest {
  value: string;
  ttl?: number;
}

export interface CacheSetResponse {
  key: string;
  value: string;
  ttl: number | null;
  action: 'set';
}

export interface CacheDeleteResponse {
  key: string;
  deleted: boolean;
  action: 'delete';
}

// Database types
export interface DatabaseQueryResponse {
  database: string;
  status: string;
  query_result?: string;
  timestamp: string;
}

// Messaging types
export interface MessagePublishRequest {
  message: Record<string, any>;
}

export interface MessagePublishResponse {
  queue: string;
  message: Record<string, any>;
  action: 'published';
}

export interface QueueInfoResponse {
  queue: string;
  exists: boolean;
  message_count: number | null;
  consumer_count: number | null;
}

// Redis Cluster types
export interface RedisClusterNode {
  id: string;
  address: string;
  role: string;
  slots?: string;
  flags: string[];
  link_state: string;
}

export interface RedisClusterNodesResponse {
  cluster_enabled: boolean;
  cluster_state: string;
  cluster_size: number;
  nodes: RedisClusterNode[];
}

export interface RedisClusterSlotsResponse {
  slots_covered: number;
  total_slots: number;
  coverage_percentage: number;
  slot_ranges: Array<{
    start: number;
    end: number;
    master: string;
  }>;
}

export interface RedisClusterInfoResponse {
  cluster_state: string;
  cluster_slots_assigned: number;
  cluster_slots_ok: number;
  cluster_slots_fail: number;
  cluster_known_nodes: number;
  cluster_size: number;
  [key: string]: string | number;
}

// Error types
export interface ErrorResponse {
  error: string;
  message: string;
  requestId?: string;
  details?: Record<string, any>;
}

// API Info types
export interface APIInfo {
  name: string;
  version: string;
  language: string;
  framework: string;
  description: string;
  endpoints: {
    health: string;
    vault_examples: string;
    database_examples: string;
    cache_examples: string;
    messaging_examples: string;
    redis_cluster: string;
    metrics: string;
  };
  redis_cluster: {
    nodes: string;
    slots: string;
    info: string;
    node_info: string;
  };
  documentation: string;
}
