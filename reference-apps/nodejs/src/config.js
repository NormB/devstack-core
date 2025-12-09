/**
 * Configuration Management
 *
 * Centralized configuration loading from environment variables
 * with sensible defaults for development.
 */

const config = {
  // Server Configuration
  http: {
    port: parseInt(process.env.HTTP_PORT || '8003', 10),
    host: process.env.HTTP_HOST || '0.0.0.0'
  },
  https: {
    port: parseInt(process.env.HTTPS_PORT || '8446', 10),
    enabled: process.env.NODEJS_API_ENABLE_TLS === 'true'
  },

  // Environment
  env: process.env.NODE_ENV || 'development',
  debug: process.env.DEBUG === 'true' || process.env.NODE_ENV === 'development',

  // Vault Configuration
  vault: {
    address: process.env.VAULT_ADDR || 'http://vault:8200',
    token: process.env.VAULT_TOKEN || '',
    appRoleDir: process.env.VAULT_APPROLE_DIR || '',
    timeout: parseInt(process.env.VAULT_TIMEOUT || '5000', 10)
  },

  // Database Configuration
  postgres: {
    host: process.env.POSTGRES_HOST || 'postgres',
    port: parseInt(process.env.POSTGRES_PORT || '5432', 10)
  },

  mysql: {
    host: process.env.MYSQL_HOST || 'mysql',
    port: parseInt(process.env.MYSQL_PORT || '3306', 10)
  },

  mongodb: {
    host: process.env.MONGODB_HOST || 'mongodb',
    port: parseInt(process.env.MONGODB_PORT || '27017', 10)
  },

  // Redis Configuration
  redis: {
    host: process.env.REDIS_HOST || 'redis-1',
    port: parseInt(process.env.REDIS_PORT || '6379', 10),
    nodes: [
      { host: 'redis-1', port: 6379 },
      { host: 'redis-2', port: 6379 },
      { host: 'redis-3', port: 6379 }
    ]
  },

  // RabbitMQ Configuration
  rabbitmq: {
    host: process.env.RABBITMQ_HOST || 'rabbitmq',
    port: parseInt(process.env.RABBITMQ_PORT || '5672', 10)
  },

  // Application Metadata
  app: {
    name: 'DevStack Core Node.js Reference API',
    version: '1.1.0',
    language: 'Node.js',
    framework: 'Express'
  }
};

// Validation
if (!config.vault.token && !config.vault.appRoleDir && config.env !== 'test') {
  console.warn('WARNING: Neither VAULT_TOKEN nor VAULT_APPROLE_DIR set. Vault operations will fail.');
}

module.exports = config;
