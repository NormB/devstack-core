# Profile Environment Override Files

This directory contains environment variable override files for each DevStack Core service profile.

## Files

- **minimal.env** - Environment overrides for minimal profile (5 services, 2GB RAM)
- **standard.env** - Environment overrides for standard profile (10 services, 4GB RAM)
- **full.env** - Environment overrides for full profile (18 services, 6GB RAM)
- **reference.env** - Environment overrides for reference profile (5 services, +1GB RAM)

## Usage

### Manual Usage

Source the environment file before starting services:

```bash
# Load minimal profile environment
set -a
source configs/profiles/minimal.env
set +a

# Start with minimal profile
docker compose --profile minimal up -d
```

### With Management Script (Recommended)

The Python management script automatically loads the appropriate profile environment:

```bash
# Minimal profile
./manage-devstack start --profile minimal

# Standard profile
./manage-devstack start --profile standard

# Full profile
./manage-devstack start --profile full

# Combined profiles
./manage-devstack start --profile standard --profile reference
```

## Environment Variable Priority

Environment variables are resolved in this order (highest to lowest priority):

1. **Shell environment** - Variables exported in your current shell
2. **Profile .env file** - Variables in `configs/profiles/<profile>.env`
3. **.env file** - Variables in root `.env` file
4. **docker-compose.yml defaults** - Default values in `${VAR:-default}` syntax

Example:
```bash
# .env has: REDIS_MAX_MEMORY=256mb
# configs/profiles/minimal.env has: REDIS_MAX_MEMORY=128mb
# Result: 128mb (profile override wins)

# But if you set in shell:
export REDIS_MAX_MEMORY=512mb
# Result: 512mb (shell wins)
```

## Key Configuration Differences

### Minimal Profile

**Focus:** Essential services only
- Redis: Standalone mode (no cluster)
- PostgreSQL: Reduced connections (50 vs 100)
- Health checks: Faster intervals (30s vs 60s)
- Resources: Conservative limits
- Features: Metrics/logs disabled

**Key Variables:**
```bash
REDIS_CLUSTER_ENABLED=false
POSTGRES_MAX_CONNECTIONS=50
ENABLE_METRICS=false
ENABLE_LOGS=false
```

### Standard Profile

**Focus:** Full development stack
- Redis: 3-node cluster enabled
- PostgreSQL: Standard connections (100)
- MySQL: Enabled
- MongoDB: Enabled
- RabbitMQ: Enabled
- Health checks: Standard intervals (60s)
- Features: Metrics/logs disabled (use full profile for observability)

**Key Variables:**
```bash
REDIS_CLUSTER_ENABLED=true
REDIS_CLUSTER_INIT_REQUIRED=true
POSTGRES_MAX_CONNECTIONS=100
MYSQL_MAX_CONNECTIONS=100
MONGODB_MAX_CONNECTIONS=100
```

### Full Profile

**Focus:** Complete suite with observability
- All standard services
- Prometheus: 15s scrape interval, 15 day retention
- Grafana: Pre-configured dashboards
- Loki: 31 day log retention
- Vector: Full observability pipeline
- cAdvisor: Container monitoring
- Redis exporters: Per-node metrics

**Key Variables:**
```bash
ENABLE_METRICS=true
ENABLE_LOGS=true
ENABLE_OBSERVABILITY=true
PROMETHEUS_SCRAPE_INTERVAL=15s
PROMETHEUS_RETENTION_TIME=15d
LOKI_RETENTION_PERIOD=744h
```

### Reference Profile

**Focus:** Educational API examples
- Must combine with standard or full profile
- All reference apps share infrastructure
- TLS enabled for HTTPS endpoints
- Metrics export enabled
- Structured logging enabled

**Key Variables:**
```bash
ENABLE_REFERENCE_APPS=true
REFERENCE_API_ENABLE_METRICS=true
REFERENCE_API_ENABLE_TLS=true
REFERENCE_API_STRUCTURED_LOGGING=true
```

## Creating Custom Profiles

You can create custom profile environment files for specific use cases:

1. Create a new file: `configs/profiles/my-custom.env`
2. Define overrides for your use case
3. Source it before starting services:

```bash
set -a
source configs/profiles/my-custom.env
set +a
docker compose --profile <your-profile> up -d
```

Example custom profile for Redis development:
```bash
# configs/profiles/redis-only.env
REDIS_CLUSTER_ENABLED=true
REDIS_CLUSTER_INIT_REQUIRED=true
REDIS_MAX_MEMORY=512mb
REDIS_SAVE_ENABLED=true
ENABLE_METRICS=false
ENABLE_LOGS=false
```

## Documentation

For complete documentation on service profiles, see:
- **docs/SERVICE_PROFILES.md** - User guide and usage examples
- **docs/PROFILE_IMPLEMENTATION_GUIDE.md** - Technical implementation details
- **docs/PROFILE_VALIDATION_RESULTS.md** - Validation test results
- **profiles.yaml** - Complete profile definitions

## Troubleshooting

### Variables Not Taking Effect

Check priority order:
```bash
# See what docker-compose will use:
docker compose --profile minimal config | grep REDIS_MAX_MEMORY

# Check if shell variable is overriding:
echo $REDIS_MAX_MEMORY

# Unset shell variable if needed:
unset REDIS_MAX_MEMORY
```

### Redis Cluster Not Initializing

Standard/full profiles require cluster initialization:
```bash
# After first start with standard or full profile:
docker exec dev-redis-1 redis-cli --cluster create \
  172.20.0.13:6379 172.20.0.16:6379 172.20.0.17:6379 \
  --cluster-yes -a $REDIS_PASSWORD
```

Or use the management script:
```bash
./manage-devstack redis-cluster-init
```

### Profile Conflicts

If you switch profiles, ensure old containers are stopped:
```bash
# Stop all
docker compose down

# Start with new profile
docker compose --profile minimal up -d
```

## Best Practices

1. **Use management script** - Automatically handles environment loading
2. **Don't modify in production** - These are development defaults
3. **Document custom profiles** - Add comments explaining overrides
4. **Test resource limits** - Adjust based on your Mac's capabilities
5. **Version control custom profiles** - Share team-specific configurations

## Support

For help with profile configuration:
1. Check docs/SERVICE_PROFILES.md
2. Review docs/FAQ.md
3. Open an issue on GitHub
