# Profile Implementation Guide

## Overview

This document explains how service profiles are implemented in DevStack Core using Docker Compose native profile support.

## Docker Compose Profile Assignment Strategy

### Profile Labels by Service

Each service in `docker-compose.yml` has a `profiles:` key that determines which profiles will start that service.

| Service | Profiles | Rationale |
|---------|----------|-----------|
| **vault** | (none) | Always starts - required for credential management |
| **postgres** | minimal, standard, full | Core database for all profiles |
| **pgbouncer** | minimal, standard, full | Connection pooling for PostgreSQL |
| **forgejo** | minimal, standard, full | Git server available in all profiles |
| **redis-1** | minimal, standard, full | Single Redis in minimal, cluster node 1 in standard/full |
| **redis-2** | standard, full | Cluster node 2 (only in standard+) |
| **redis-3** | standard, full | Cluster node 3 (only in standard+) |
| **mysql** | standard, full | Additional database (standard+) |
| **mongodb** | standard, full | NoSQL database (standard+) |
| **rabbitmq** | standard, full | Message queue (standard+) |
| **prometheus** | full | Metrics collection (full only) |
| **grafana** | full | Visualization (full only) |
| **loki** | full | Log aggregation (full only) |
| **vector** | full | Observability pipeline (full only) |
| **cadvisor** | full | Container monitoring (full only) |
| **redis-exporter-1** | full | Redis metrics for node 1 (full only) |
| **redis-exporter-2** | full | Redis metrics for node 2 (full only) |
| **redis-exporter-3** | full | Redis metrics for node 3 (full only) |
| **reference-api** | reference | Python FastAPI code-first |
| **api-first** | reference | Python FastAPI API-first |
| **golang-api** | reference | Go with Gin |
| **nodejs-api** | reference | Node.js with Express |
| **rust-api** | reference | Rust with Actix-web |

### Services Without Profiles (Always Start)

- **vault** - No profile assignment means it starts with ANY profile or when no profile is specified

### Profile Hierarchy

```
┌─────────────────────────────────────────────────────┐
│  MINIMAL (5 services, 2GB RAM)                      │
│  • vault, postgres, pgbouncer, forgejo, redis-1     │
└─────────────────────────────────────────────────────┘
                        │
                        │ adds: mysql, mongodb, redis-2,
                        │       redis-3, rabbitmq
                        ▼
┌─────────────────────────────────────────────────────┐
│  STANDARD (12 services, 4GB RAM)                    │
│  • All minimal services                             │
│  • + mysql, mongodb, redis-2/3, rabbitmq            │
└─────────────────────────────────────────────────────┘
                        │
                        │ adds: prometheus, grafana, loki,
                        │       vector, cadvisor, exporters
                        ▼
┌─────────────────────────────────────────────────────┐
│  FULL (18 services, 6GB RAM)                        │
│  • All standard services                            │
│  • + prometheus, grafana, loki, vector, cadvisor    │
│  • + redis-exporter-1/2/3                           │
└─────────────────────────────────────────────────────┘

                    ┌───────────────┐
                    │  REFERENCE    │
                    │  (5 services) │
                    │  +1GB RAM     │
                    └───────────────┘
                           │
                           │ Can combine with any profile
                           ▼
            ┌──────────────┬──────────────┬──────────────┐
            │   minimal    │   standard   │     full     │
            │  +reference  │  +reference  │  +reference  │
            └──────────────┴──────────────┴──────────────┘
```

## Docker Compose Profile Syntax

### Basic Profile Assignment

```yaml
services:
  postgres:
    profiles: ["minimal", "standard", "full"]
    image: postgres:18
    # ... rest of configuration
```

### Service Without Profile (Always Starts)

```yaml
services:
  vault:
    # No profiles key = starts with any profile
    image: vault:latest
    # ... rest of configuration
```

### Using Profiles

```bash
# Start with specific profile
docker compose --profile minimal up -d

# Combine multiple profiles
docker compose --profile standard --profile reference up -d

# Start without any profile (only services without profiles key)
docker compose up -d  # Only starts vault
```

## Environment Variable Behavior by Profile

### Minimal Profile (`REDIS_CLUSTER_ENABLED=false`)

When running minimal profile:
- Only `redis-1` starts
- Redis runs in standalone mode (not cluster)
- No cluster initialization needed
- Direct connection: `redis-cli -h localhost -p 6379`

### Standard/Full Profiles (`REDIS_CLUSTER_ENABLED=true`)

When running standard or full profiles:
- All three Redis nodes start (`redis-1`, `redis-2`, `redis-3`)
- Cluster mode enabled in redis.conf
- Cluster initialization required after first start
- Cluster connection: `redis-cli -c -h localhost -p 6379`

## Service Dependencies with Profiles

### Dependency Chain

All services depend on Vault:

```yaml
services:
  postgres:
    depends_on:
      vault:
        condition: service_healthy
```

This ensures:
1. Vault starts first
2. Vault becomes healthy (unsealed + initialized)
3. Only then do other services start
4. Services can fetch credentials from Vault

### Profile-Specific Dependencies

Services only depend on services in the same or broader profile:

```yaml
services:
  redis-exporter-1:
    profiles: ["full"]
    depends_on:
      vault:
        condition: service_healthy
      redis-1:
        condition: service_started
```

Since `redis-exporter-1` is only in `full` profile, and `redis-1` is in `minimal`, `standard`, and `full`, the dependency is always satisfied.

## Health Checks and Profiles

All services maintain their health checks regardless of profile:

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
  interval: 60s
  timeout: 5s
  retries: 5
  start_period: 30s
```

The management script can check health with:
```bash
./devstack.py health
```

## Profile-Specific Configuration Files

Each profile has optional environment override files:

```
configs/profiles/
├── minimal.env      # Overrides for minimal profile
├── standard.env     # Overrides for standard profile
├── full.env         # Overrides for full profile
└── reference.env    # Overrides for reference profile
```

Example `configs/profiles/minimal.env`:
```bash
# Redis configuration for minimal profile
REDIS_CLUSTER_ENABLED=false
REDIS_CLUSTER_INIT_REQUIRED=false

# Reduced connection limits for lighter workload
POSTGRES_MAX_CONNECTIONS=50
MYSQL_MAX_CONNECTIONS=50

# Faster health checks (smaller stack)
POSTGRES_HEALTH_INTERVAL=30s
VAULT_HEALTH_INTERVAL=30s
```

Example `configs/profiles/standard.env`:
```bash
# Redis cluster configuration
REDIS_CLUSTER_ENABLED=true
REDIS_CLUSTER_INIT_REQUIRED=true

# Standard connection limits
POSTGRES_MAX_CONNECTIONS=100
MYSQL_MAX_CONNECTIONS=100
MONGODB_MAX_CONNECTIONS=100

# Standard health check intervals
POSTGRES_HEALTH_INTERVAL=60s
VAULT_HEALTH_INTERVAL=60s
```

## Testing Profile Implementation

### Validation Checklist

1. **Minimal Profile**
   ```bash
   docker compose --profile minimal config --services
   # Should output: vault, postgres, pgbouncer, forgejo, redis-1

   docker compose --profile minimal up -d
   docker ps --format "table {{.Names}}\t{{.Status}}"
   # Verify only 5 containers running
   ```

2. **Standard Profile**
   ```bash
   docker compose --profile standard config --services
   # Should output: vault, postgres, pgbouncer, forgejo, redis-1/2/3, mysql, mongodb, rabbitmq

   docker compose --profile standard up -d
   docker ps --format "table {{.Names}}\t{{.Status}}"
   # Verify 12 containers running
   ```

3. **Full Profile**
   ```bash
   docker compose --profile full config --services
   # Should output: all standard services + prometheus, grafana, loki, vector, cadvisor, exporters

   docker compose --profile full up -d
   docker ps --format "table {{.Names}}\t{{.Status}}"
   # Verify 18 containers running
   ```

4. **Combined Profiles**
   ```bash
   docker compose --profile standard --profile reference config --services
   # Should output: all standard services + all reference apps

   docker compose --profile standard --profile reference up -d
   docker ps --format "table {{.Names}}\t{{.Status}}"
   # Verify 17 containers running (12 standard + 5 reference)
   ```

### Resource Validation

Measure actual resource usage:

```bash
# Total RAM usage by profile
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | \
  awk '{sum+=$2} END {print "Total RAM:", sum/1024/1024/1024, "GB"}'

# Per-service RAM
docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}"
```

Expected results:
- Minimal: ~2GB RAM
- Standard: ~4GB RAM
- Full: ~6GB RAM

## Profile Switching

### Stopping One Profile, Starting Another

```bash
# Currently running standard profile
docker compose --profile standard ps

# Stop standard profile services
docker compose --profile standard down

# Start minimal profile
docker compose --profile minimal up -d
```

### Upgrading from Minimal to Standard

```bash
# Add standard profile services to running minimal
docker compose --profile standard up -d

# This will:
# 1. Keep running minimal services (vault, postgres, etc.)
# 2. Start additional standard services (mysql, mongodb, redis-2/3, rabbitmq)
```

### Downgrading from Standard to Minimal

```bash
# Stop all services
docker compose --profile standard down

# Start only minimal
docker compose --profile minimal up -d

# Or remove specific services:
docker compose rm -sf mysql mongodb redis-2 redis-3 rabbitmq
```

## Common Patterns

### Development Workflow

**Morning Routine (Standard Profile):**
```bash
./devstack.py start --profile standard
./devstack.py health
./devstack.py redis-cluster-init  # First time only
```

**End of Day:**
```bash
./devstack.py stop
```

**Weekend (Keep Minimal Running):**
```bash
# Stop standard, keep minimal (Git server stays up)
docker compose --profile standard down
docker compose --profile minimal up -d
```

### CI/CD Integration

**GitHub Actions (Minimal for Tests):**
```yaml
- name: Start DevStack Core
  run: |
    docker compose --profile minimal up -d
    docker compose --profile minimal ps
```

**Load Testing (Full Profile):**
```yaml
- name: Start DevStack Core with Observability
  run: |
    docker compose --profile full up -d
    ./wait-for-health.sh
```

## Troubleshooting

### Service Won't Start

Check if service is in the profile:
```bash
docker compose --profile minimal config --services | grep mysql
# Empty output = mysql not in minimal profile
```

### Wrong Profile Active

Check running containers:
```bash
docker ps --format "{{.Names}}" | grep dev-
```

Compare with expected services:
```bash
docker compose --profile minimal config --services
```

### Profile Conflicts

If services from multiple profiles are running:
```bash
# Nuclear option: stop everything
docker compose down --remove-orphans

# Start clean with desired profile
docker compose --profile standard up -d
```

## Best Practices

1. **Always specify profile** - Don't rely on defaults
2. **Use minimal for CI/CD** - Faster, lighter
3. **Use standard for development** - Full feature set
4. **Use full for performance testing** - Observability included
5. **Combine reference with others** - Learn patterns alongside dev
6. **Document custom profiles** - Add to profiles.yaml custom_profiles section
7. **Test profile switches** - Ensure services stop/start correctly
8. **Monitor resources** - Validate RAM estimates match reality

## Implementation Checklist

- [x] Create profiles.yaml with profile definitions
- [x] Document profile implementation strategy
- [ ] Add `profiles:` keys to docker-compose.yml
- [ ] Create profile-specific environment files
- [ ] Test minimal profile (5 services)
- [ ] Test standard profile (12 services)
- [ ] Test full profile (18 services)
- [ ] Test reference profile (5 services)
- [ ] Test combined profiles (standard + reference)
- [ ] Validate resource usage matches estimates
- [ ] Update documentation (README, INSTALLATION, USAGE)
- [ ] Create Python management script with profile support
- [ ] Add profile validation to CI/CD pipeline
