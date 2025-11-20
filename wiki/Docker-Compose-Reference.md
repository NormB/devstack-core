# Docker Compose Reference

## Table of Contents

- [Service Definitions](#service-definitions)
- [Dependencies and Health Checks](#dependencies-and-health-checks)
- [Volume Mounts](#volume-mounts)
- [Network Configuration](#network-configuration)
- [Environment Variables](#environment-variables)
- [Custom Modifications](#custom-modifications)

## Service Definitions

**Basic service structure:**
```yaml
services:
  postgres:
    image: postgres:16-alpine
    container_name: dev-postgres
    hostname: postgres
    entrypoint: ["/init/init.sh"]
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      VAULT_ADDR: http://vault:8200
      VAULT_TOKEN: ${VAULT_TOKEN}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./configs/postgres/scripts/init.sh:/init/init.sh:ro
    ports:
      - "${POSTGRES_PORT}:5432"
    networks:
      dev-services:
        ipv4_address: ${POSTGRES_IP}
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    depends_on:
      vault:
        condition: service_healthy
```

## Dependencies and Health Checks

**All services depend on Vault:**
```yaml
depends_on:
  vault:
    condition: service_healthy
```

**Health check examples:**
```yaml
# PostgreSQL
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U devuser"]
  interval: 10s
  timeout: 5s
  retries: 5
  start_period: 30s

# Vault
healthcheck:
  test: ["CMD", "vault", "status"]
  interval: 10s

# Redis
healthcheck:
  test: ["CMD", "redis-cli", "ping"]
  interval: 10s

# HTTP service
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
  interval: 30s
```

## Volume Mounts

**Data volumes:**
```yaml
volumes:
  postgres-data:
    driver: local
  mysql-data:
  mongodb-data:
  redis-1-data:
  vault-data:
```

**Bind mounts:**
```yaml
volumes:
  # Read-only configuration
  - ./configs/postgres/postgresql.conf:/etc/postgresql/postgresql.conf:ro

  # Read-write data
  - ./data:/data

  # Vault keys (external)
  - ~/.config/vault:/vault-keys:ro

  # Multiple mounts
  - ./configs/service/config.yml:/etc/service/config.yml:ro
  - ./configs/service/scripts:/scripts:ro
  - service-data:/var/lib/service
```

## Network Configuration

**Network definition:**
```yaml
networks:
  dev-services:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
```

**Service network:**
```yaml
services:
  postgres:
    networks:
      dev-services:
        ipv4_address: 172.20.0.10
```

## Environment Variables

**From .env file:**
```yaml
environment:
  POSTGRES_DB: ${POSTGRES_DB}
  POSTGRES_USER: ${POSTGRES_USER}
  POSTGRES_PORT: ${POSTGRES_PORT}
```

**Hardcoded values:**
```yaml
environment:
  ENVIRONMENT: development
  LOG_LEVEL: info
```

**File-based:**
```yaml
env_file:
  - .env
  - .env.local
```

## Custom Modifications

**Add new service:**
```yaml
services:
  myservice:
    image: myservice:latest
    container_name: dev-myservice
    depends_on:
      vault:
        condition: service_healthy
    environment:
      VAULT_ADDR: http://vault:8200
      VAULT_TOKEN: ${VAULT_TOKEN}
    volumes:
      - ./configs/myservice/init.sh:/init/init.sh:ro
    networks:
      dev-services:
        ipv4_address: 172.20.0.30
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
    restart: unless-stopped
```

**Override service:**
```yaml
# docker-compose.override.yml
services:
  postgres:
    ports:
      - "5433:5432"
    environment:
      POSTGRES_MAX_CONNECTIONS: 500
```

## Related Pages

- [Service-Configuration](Service-Configuration)
- [Environment-Variables](Environment-Variables)
- [Network-Issues](Network-Issues)
