# Best Practices

Recommended patterns and guidelines for effective use of DevStack Core, including profile selection, resource management, and integration patterns.

## Table of Contents

- [Service Profile Selection (NEW v1.3)](#service-profile-selection-new-v13)
- [Daily Usage](#daily-usage)
- [Development Workflow](#development-workflow)
- [Resource Management](#resource-management)
- [Backup Strategy](#backup-strategy)
- [Security Hygiene](#security-hygiene)
- [Integration Patterns](#integration-patterns)
  - [Using PostgreSQL](#using-postgresql)
  - [Using Redis Cluster](#using-redis-cluster)
  - [Using Vault](#using-vault)
  - [Using RabbitMQ](#using-rabbitmq)
  - [Git with Forgejo](#git-with-forgejo)
  - [Multi-Service Applications](#multi-service-applications)

---

## Service Profile Selection (NEW v1.3)

### Choose the Right Profile

**Best Practice: Use the smallest profile that meets your needs** to save resources and startup time.

#### Profile Selection Guide

**Use minimal profile when:**
- Working on frontend-only projects
- Need Git hosting (Forgejo) only
- Limited system resources (< 8GB RAM)
- Single Redis instance is sufficient
- Quick prototyping or demos

```bash
./devstack.py start --profile minimal
```

**Use standard profile when:**
- Need Redis cluster for testing
- Developing backend services
- Require all databases (PostgreSQL, MySQL, MongoDB)
- RabbitMQ messaging needed
- **This is the recommended profile for most developers**

```bash
./devstack.py start --profile standard
./devstack.py redis-cluster-init  # First time only
```

**Use full profile when:**
- Performance testing required
- Need metrics (Prometheus) and logs (Loki)
- Troubleshooting production issues locally
- System has 16GB+ RAM
- Observability stack needed

```bash
./devstack.py start --profile full
```

**Use reference profile when:**
- Learning API design patterns
- Comparing language implementations
- Need code examples for integration
- **Must combine with standard or full**

```bash
./devstack.py start --profile standard --profile reference
```

### Profile-Specific Best Practices

#### Minimal Profile Best Practices

1. **Use for single-developer projects:**
   ```bash
   # Morning routine
   ./devstack.py start --profile minimal
   ./devstack.py health
   ```

2. **Redis standalone usage:**
   ```python
   # No cluster-specific code needed
   import redis
   r = redis.Redis(host='localhost', port=6379, password='...')
   r.set('key', 'value')
   ```

3. **Quick teardown:**
   ```bash
   ./devstack.py stop  # Fast shutdown, minimal cleanup
   ```

#### Standard Profile Best Practices

1. **Initialize Redis cluster after first start:**
   ```bash
   ./devstack.py start --profile standard
   # Wait 2-3 minutes for services to be healthy
   ./devstack.py health
   ./devstack.py redis-cluster-init
   ```

2. **Test Redis cluster operations:**
   ```python
   from rediscluster import RedisCluster

   startup_nodes = [
       {"host": "localhost", "port": "6379"},
       {"host": "localhost", "port": "6380"},
       {"host": "localhost", "port": "6381"}
   ]
   rc = RedisCluster(startup_nodes=startup_nodes, password='...')
   ```

3. **Use all available databases:**
   - PostgreSQL for relational data
   - MySQL for legacy application compatibility
   - MongoDB for document storage
   - RabbitMQ for async messaging

#### Full Profile Best Practices

1. **Set up monitoring dashboards:**
   ```bash
   # Access Grafana
   open http://localhost:3001  # admin/admin

   # Check Prometheus targets
   open http://localhost:9090/targets
   ```

2. **Use structured logging:**
   - All services send logs to Loki via Vector
   - Query logs in Grafana with LogQL
   - Set up alerts for errors

3. **Performance testing workflow:**
   ```bash
   # Start full profile
   ./devstack.py start --profile full

   # Run load tests
   ab -n 10000 -c 100 http://localhost:8000/api/users

   # Monitor metrics in Grafana
   # Check Redis cluster performance
   # Review database query times
   ```

#### Reference Profile Best Practices

1. **Learn from multiple implementations:**
   ```bash
   # Start infrastructure + examples
   ./devstack.py start --profile standard --profile reference

   # Compare API designs
   curl http://localhost:8000/docs  # Python code-first
   curl http://localhost:8001/docs  # Python API-first
   curl http://localhost:8002/      # Go
   curl http://localhost:8003/      # Node.js
   curl http://localhost:8004/      # Rust
   ```

2. **Use for integration testing:**
   - Test against real service implementations
   - Validate API contracts
   - Compare performance across languages

3. **Study shared patterns:**
   - Vault integration
   - Database connection pooling
   - Redis cluster operations
   - Health check implementations

### Profile Switching Best Practices

1. **Clean shutdown before switching:**
   ```bash
   docker compose down  # Stop all services
   ./devstack.py start --profile minimal  # Start new profile
   ```

2. **Preserve data when switching:**
   - Docker volumes persist data between profile switches
   - Databases retain data
   - Vault remains initialized

3. **Use profiles for different projects:**
   ```bash
   # Project A: Minimal profile
   cd ~/project-a
   ./devstack.py start --profile minimal

   # Project B: Standard profile (different Colima profile)
   cd ~/project-b
   export COLIMA_PROFILE=project-b
   ./devstack.py start --profile standard
   ```

### Resource Optimization with Profiles

1. **Profile resource usage:**
   - minimal: ~2GB RAM, 5 containers
   - standard: ~4GB RAM, 10 containers
   - full: ~6GB RAM, 18 containers
   - reference: +1GB RAM, +5 containers

2. **Monitor resource consumption:**
   ```bash
   ./devstack.py status  # Shows container resources
   docker stats --no-stream     # Detailed resource usage
   ```

3. **Adjust Colima resources based on profile:**
   ```bash
   # For minimal profile
   export COLIMA_MEMORY=4

   # For full profile
   export COLIMA_MEMORY=8

   ./devstack.py start --profile <chosen-profile>
   ```

---

## Daily Usage

### With Profiles (Recommended)

```bash
# Morning: Start with your typical profile
./devstack.py start --profile standard

# Check health
./devstack.py health

# Work on projects

# Evening: Stop services
./devstack.py stop
```

### Traditional (All Services)

1. Start services in morning: `./devstack.sh start`
2. Work on projects
3. Leave running overnight (or stop: `./devstack.sh stop`)
4. Weekly: Check resource usage and backup

## Development Workflow
```bash
# 1. Make code changes
# 2. Commit to local Forgejo
git push forgejo main

# 3. Test with local databases
psql -h localhost -U $POSTGRES_USER

# 4. Store secrets in Vault
vault kv put secret/myapp/config api_key=xyz

# 5. Test message queues
# Publish to RabbitMQ, verify consumption
```

## Resource Management
```bash
# Check resource usage weekly
./devstack.sh status

# Clean up unused containers/images monthly
docker system prune -a

# Monitor disk usage
docker system df
```

## Backup Strategy
```bash
# Daily: Git commits (auto-backed up by Forgejo)
# Weekly: Full backup
./devstack.sh backup

# Store backups offsite
# Keep 4 weekly backups, 3 monthly backups
```

## Security Hygiene
```bash
# 1. Use strong, unique passwords in .env
# 2. Backup Vault keys securely
tar czf vault-keys.tar.gz ~/.config/vault/
gpg -c vault-keys.tar.gz  # Encrypt

# 3. Never commit secrets to Git
# 4. Rotate passwords quarterly
# 5. Update images regularly
docker compose pull
docker compose up -d
```

## Integration Patterns

### Using PostgreSQL
```python
# Python example
import psycopg2

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    user="dev_admin",
    password="<from .env>",
    database="dev_database"
)
```

### Using Redis Cluster
```python
# Python with redis-py-cluster
from rediscluster import RedisCluster

startup_nodes = [
    {"host": "localhost", "port": "6379"},
    {"host": "localhost", "port": "6380"},
    {"host": "localhost", "port": "6381"}
]

rc = RedisCluster(
    startup_nodes=startup_nodes,
    password="<from .env>",
    decode_responses=True
)

rc.set("key", "value")
print(rc.get("key"))
```

### Using Vault
```bash
# Get secrets via CLI
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Store secret
vault kv put secret/myapp/db password=xyz

# Retrieve in script
DB_PASSWORD=$(vault kv get -field=password secret/myapp/db)
```

### Using RabbitMQ
```python
# Python with pika
import pika

credentials = pika.PlainCredentials('dev_admin', '<from .env>')
connection = pika.BlockingConnection(
    pika.ConnectionParameters('localhost', 5672, 'dev_vhost', credentials)
)
channel = connection.channel()

channel.queue_declare(queue='hello')
channel.basic_publish(exchange='', routing_key='hello', body='Hello World!')
```

### Git with Forgejo
```bash
# Add Forgejo as remote
git remote add forgejo http://localhost:3000/username/repo.git

# Push
git push forgejo main

# Use SSH for better security
git remote set-url forgejo ssh://git@localhost:2222/username/repo.git
```

### Multi-Service Applications
```
Your VoIP App
├── PostgreSQL: Call records, user accounts
├── Redis Cluster: Session storage, rate limiting
├── RabbitMQ: Call events, webhooks
├── MongoDB: Call logs, CDRs
├── Vault: API keys, SIP credentials
└── Forgejo: Source code, deployment scripts
```

