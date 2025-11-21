/**
 * Configuration module for TypeScript API
 *
 * Loads configuration from environment variables with sensible defaults.
 */

export interface AppConfig {
  name: string;
  version: string;
  language: string;
  framework: string;
}

export interface ServerConfig {
  httpPort: number;
  httpsPort: number;
  environment: string;
  debug: boolean;
}

export interface VaultConfig {
  addr: string;
  token: string;
}

export interface DatabaseConfig {
  postgres: {
    host: string;
    port: number;
  };
  mysql: {
    host: string;
    port: number;
  };
  mongodb: {
    host: string;
    port: number;
  };
}

export interface CacheConfig {
  redis: {
    host: string;
    port: number;
  };
}

export interface MessagingConfig {
  rabbitmq: {
    host: string;
    port: number;
  };
}

export interface Config {
  app: AppConfig;
  server: ServerConfig;
  vault: VaultConfig;
  database: DatabaseConfig;
  cache: CacheConfig;
  messaging: MessagingConfig;
}

const config: Config = {
  app: {
    name: 'DevStack Core TypeScript API-First Reference',
    version: '1.0.0',
    language: 'TypeScript',
    framework: 'Express'
  },
  server: {
    httpPort: parseInt(process.env.HTTP_PORT || '8005', 10),
    httpsPort: parseInt(process.env.HTTPS_PORT || '8448', 10),
    environment: process.env.NODE_ENV || 'development',
    debug: process.env.DEBUG === 'true'
  },
  vault: {
    addr: process.env.VAULT_ADDR || 'http://vault:8200',
    token: process.env.VAULT_TOKEN || ''
  },
  database: {
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
    }
  },
  cache: {
    redis: {
      host: process.env.REDIS_HOST || 'redis-1',
      port: parseInt(process.env.REDIS_PORT || '6379', 10)
    }
  },
  messaging: {
    rabbitmq: {
      host: process.env.RABBITMQ_HOST || 'rabbitmq',
      port: parseInt(process.env.RABBITMQ_PORT || '5672', 10)
    }
  }
};

export default config;
