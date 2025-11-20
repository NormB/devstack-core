# Service Profiles - Flexible Container Orchestration

## Overview

DevStack Core provides multiple **service profiles** to accommodate different development scenarios. This allows developers to run only the services they need, reducing resource consumption and startup time.

## Available Profiles

### 1. **minimal** - Essential Services Only
**Use Case:** Basic development with Git server and single database

**Services:** (5 containers, ~2GB RAM)
- `vault` - Secrets management (required)
- `postgres` - Primary database + Git storage
- `pgbouncer` - Connection pooling
- `forgejo` - Git server
- `redis-1` - Single Redis instance (non-cluster mode)

**Start Command:**
```bash
./devstack.sh start --profile minimal
# OR
docker compose --profile minimal up -d
```

**Best For:**
- Simple CRUD application development
- Git repository hosting only
- Learning the platform
- Resource-constrained environments

---

### 2. **standard** - Full Development Stack
**Use Case:** Multi-database development without observability

**Services:** (12 containers, ~4GB RAM)
- All minimal services
- `mysql` - Legacy database support
- `mongodb` - NoSQL document database
- `redis-1`, `redis-2`, `redis-3` - Redis cluster (3 nodes)
- `rabbitmq` - Message queue

**Start Command:**
```bash
./devstack.sh start --profile standard
# OR
docker compose --profile standard up -d
```

**Best For:**
- Multi-database applications
- Microservices development
- Message queue integration
- Redis cluster testing (your use case!)

---

### 3. **full** - Complete Suite with Observability
**Use Case:** Production-parity development with full monitoring

**Services:** (18 containers, ~6GB RAM)
- All standard services
- `prometheus` - Metrics collection
- `grafana` - Visualization dashboards
- `loki` - Log aggregation
- `vector` - Observability pipeline
- `cadvisor` - Container monitoring
- `redis-exporter-1/2/3` - Redis metrics exporters

**Start Command:**
```bash
./devstack.sh start --profile full
# OR
docker compose --profile full up -d
```

**Best For:**
- Performance testing and optimization
- Production troubleshooting simulation
- Understanding system resource usage
- Learning observability patterns

---

### 4. **reference** - Include Reference Applications
**Use Case:** API development and cross-language pattern learning

**Additional Services:** (5 reference apps)
- `reference-api` - Python FastAPI (code-first)
- `api-first` - Python FastAPI (API-first)
- `golang-api` - Go with Gin
- `nodejs-api` - Node.js with Express
- `rust-api` - Rust with Actix-web (partial)

**Start Command:**
```bash
./devstack.sh start --profile standard --profile reference
# OR
docker compose --profile standard --profile reference up -d
```

**Best For:**
- Learning API design patterns
- Comparing language implementations
- Testing shared test suites
- API integration examples

---

## Profile Comparison

| Profile | Containers | RAM Usage | Startup Time | Use Case |
|---------|------------|-----------|--------------|----------|
| **minimal** | 5 | ~2GB | 20s | Git + Basic DB |
| **standard** | 12 | ~4GB | 45s | Full dev stack |
| **full** | 18 | ~6GB | 60s | With observability |
| **reference** | +5 | +1GB | +15s | Add-on for APIs |

## Implementation Approach

### Recommended: Docker Compose Profiles + Python Management Script

**Why this approach:**

1. **Docker Compose Native Profiles** - Built-in feature since Compose v1.28+
   - No custom orchestration logic needed
   - Well-documented and widely understood
   - Native support for `--profile` flag
   - Services can belong to multiple profiles

2. **Python Management Script** - Replace bash with Python
   - Better error handling and validation
   - Easier to test and maintain
   - Rich library ecosystem (click, rich, pyyaml)
   - Cross-platform compatibility (future Linux support)
   - Type hints for better IDE support

3. **Profile Configuration File** - YAML-based profile definitions
   - Centralized profile management
   - Easy to add custom profiles
   - Documented service groupings
   - User-extensible

### Architecture

```
devstack-core/
├── manage-devstack.py              # New Python management script
├── profiles.yaml                   # Profile definitions
├── docker-compose.yml              # Updated with profile labels
└── configs/
    └── profiles/
        ├── minimal.yaml            # Minimal profile env overrides
        ├── standard.yaml           # Standard profile env overrides
        └── full.yaml               # Full profile env overrides
```

## Docker Compose Profile Implementation

### Step 1: Update docker-compose.yml

Add `profiles:` key to each service:

```yaml
services:
  # ALWAYS STARTED (no profile = default)
  vault:
    image: vault:latest
    # No profiles key - starts in all profiles

  # MINIMAL PROFILE
  postgres:
    profiles: ["minimal", "standard", "full"]
    image: postgres:18

  forgejo:
    profiles: ["minimal", "standard", "full"]
    image: forgejo:1.21

  redis-1:
    profiles: ["minimal", "standard", "full"]
    image: redis:7.4-alpine3.21
    # In minimal mode, runs standalone (no cluster init)

  # STANDARD PROFILE (adds these)
  redis-2:
    profiles: ["standard", "full"]  # NOT in minimal
    image: redis:7.4-alpine3.21

  redis-3:
    profiles: ["standard", "full"]  # NOT in minimal
    image: redis:7.4-alpine3.21

  mysql:
    profiles: ["standard", "full"]
    image: mysql:8.0

  mongodb:
    profiles: ["standard", "full"]
    image: mongo:7

  rabbitmq:
    profiles: ["standard", "full"]
    image: rabbitmq:3-management-alpine

  # FULL PROFILE (adds observability)
  prometheus:
    profiles: ["full"]
    image: prom/prometheus:v2.48.0

  grafana:
    profiles: ["full"]
    image: grafana/grafana:10.2.2

  loki:
    profiles: ["full"]
    image: grafana/loki:2.9.3

  # REFERENCE APPS (separate profile, combinable)
  reference-api:
    profiles: ["reference"]
    build: ./reference-apps/fastapi
```

### Step 2: profiles.yaml Configuration

```yaml
profiles:
  minimal:
    description: "Essential services only (Git + single DB)"
    services:
      - vault
      - postgres
      - pgbouncer
      - forgejo
      - redis-1
    ram_estimate: "2GB"
    env_overrides:
      REDIS_CLUSTER_ENABLED: "false"  # Single node mode

  standard:
    description: "Full development stack (multi-DB + Redis cluster)"
    services:
      - vault
      - postgres
      - pgbouncer
      - mysql
      - mongodb
      - redis-1
      - redis-2
      - redis-3
      - rabbitmq
      - forgejo
    ram_estimate: "4GB"
    env_overrides:
      REDIS_CLUSTER_ENABLED: "true"  # Enable cluster

  full:
    description: "Complete suite with observability"
    extends: standard
    additional_services:
      - prometheus
      - grafana
      - loki
      - vector
      - cadvisor
      - redis-exporter-1
      - redis-exporter-2
      - redis-exporter-3
    ram_estimate: "6GB"

  reference:
    description: "Reference API applications"
    services:
      - reference-api
      - api-first
      - golang-api
      - nodejs-api
      - rust-api
    ram_estimate: "+1GB"
    combinable: true  # Can combine with other profiles

# Custom user profiles (optional)
custom_profiles:
  redis-dev:
    description: "Redis cluster development only"
    services:
      - vault
      - redis-1
      - redis-2
      - redis-3
    ram_estimate: "1.5GB"

  postgres-dev:
    description: "PostgreSQL development only"
    services:
      - vault
      - postgres
      - pgbouncer
    ram_estimate: "1GB"
```

### Step 3: Python Management Script (manage-devstack.py)

```python
#!/usr/bin/env python3
"""
DevStack Core Management Script
Python-based orchestration with profile support
"""
import click
import subprocess
import yaml
from pathlib import Path
from rich.console import Console
from rich.table import Table
from typing import List, Dict, Optional

console = Console()

# Load profiles configuration
PROFILES_FILE = Path(__file__).parent / "profiles.yaml"
COMPOSE_FILE = Path(__file__).parent / "docker-compose.yml"

def load_profiles() -> Dict:
    """Load profile definitions from YAML"""
    with open(PROFILES_FILE) as f:
        return yaml.safe_load(f)

def get_profile_services(profile_name: str) -> List[str]:
    """Get list of services for a profile"""
    profiles = load_profiles()
    if profile_name in profiles['profiles']:
        return profiles['profiles'][profile_name]['services']
    elif profile_name in profiles.get('custom_profiles', {}):
        return profiles['custom_profiles'][profile_name]['services']
    else:
        raise ValueError(f"Unknown profile: {profile_name}")

@click.group()
def cli():
    """DevStack Core - Flexible Development Infrastructure"""
    pass

@cli.command()
@click.option('--profile', '-p', multiple=True, default=['standard'],
              help='Service profile(s) to start (minimal/standard/full/reference)')
@click.option('--detach/--no-detach', '-d', default=True,
              help='Run in background (detached mode)')
def start(profile: tuple, detach: bool):
    """Start Colima VM and Docker services with specified profile(s)"""

    # Validate profiles
    profiles_config = load_profiles()
    for p in profile:
        if p not in profiles_config['profiles'] and \
           p not in profiles_config.get('custom_profiles', {}):
            console.print(f"[red]Error: Unknown profile '{p}'[/red]")
            return

    # Display what will start
    console.print(f"\n[cyan]Starting DevStack Core with profile(s): {', '.join(profile)}[/cyan]\n")

    # Start Colima if not running
    result = subprocess.run(['colima', 'status'],
                          capture_output=True, text=True)
    if result.returncode != 0:
        console.print("[yellow]Starting Colima VM...[/yellow]")
        subprocess.run(['colima', 'start',
                       '--cpu', '4', '--memory', '8', '--disk', '60',
                       '--network-address'])

    # Build docker compose command with profiles
    cmd = ['docker', 'compose']
    for p in profile:
        cmd.extend(['--profile', p])
    cmd.extend(['up', '-d' if detach else ''])

    # Execute
    console.print(f"[green]Executing: {' '.join(cmd)}[/green]")
    subprocess.run(cmd)

    # Show what started
    console.print("\n[green]✓ Services started successfully[/green]")
    subprocess.run(['docker', 'compose', 'ps'])

@cli.command()
@click.option('--profile', '-p', multiple=True,
              help='Only stop services from specific profile(s)')
def stop(profile: Optional[tuple]):
    """Stop Docker services and Colima VM"""
    if profile:
        # Stop specific profile services
        cmd = ['docker', 'compose']
        for p in profile:
            cmd.extend(['--profile', p])
        cmd.append('down')
        subprocess.run(cmd)
    else:
        # Stop everything
        subprocess.run(['docker', 'compose', 'down'])
        subprocess.run(['colima', 'stop'])

@cli.command()
def profiles():
    """List available service profiles"""
    profiles_config = load_profiles()

    table = Table(title="Available Service Profiles")
    table.add_column("Profile", style="cyan")
    table.add_column("Services", style="green")
    table.add_column("RAM", style="yellow")
    table.add_column("Description")

    for name, config in profiles_config['profiles'].items():
        services = str(len(config['services']))
        table.add_row(
            name,
            services,
            config.get('ram_estimate', 'N/A'),
            config['description']
        )

    console.print(table)

    # Show custom profiles if any
    if 'custom_profiles' in profiles_config:
        console.print("\n[cyan]Custom Profiles:[/cyan]")
        for name, config in profiles_config['custom_profiles'].items():
            console.print(f"  • {name}: {config['description']}")

@cli.command()
@click.argument('service', required=False)
def logs(service: Optional[str]):
    """View logs for all services or specific service"""
    if service:
        subprocess.run(['docker', 'compose', 'logs', '-f', service])
    else:
        subprocess.run(['docker', 'compose', 'logs', '-f'])

@cli.command()
def status():
    """Show status of all running services"""
    subprocess.run(['docker', 'compose', 'ps'])

@cli.command()
@click.argument('service')
def shell(service: str):
    """Open shell in a running container"""
    subprocess.run(['docker', 'compose', 'exec', service, 'sh'])

# ... more commands (health, backup, vault-*, etc.)

if __name__ == '__main__':
    cli()
```

## Migration Plan

### Phase 1: Add Profile Support to docker-compose.yml (Week 1)

1. **Add profile labels to all services**
   - Categorize services into minimal/standard/full
   - Test each profile independently
   - Document service dependencies

2. **Create profiles.yaml configuration**
   - Define profile hierarchies
   - Set RAM estimates
   - Add environment overrides

3. **Update documentation**
   - Add SERVICE_PROFILES.md (this document)
   - Update INSTALLATION.md with profile examples
   - Add to README.md quick start

### Phase 2: Create Python Management Script (Week 2)

1. **Implement core functionality**
   - start/stop/restart with profile support
   - profile listing and inspection
   - status and health checks

2. **Add advanced features**
   - Vault operations
   - Backup/restore
   - Forgejo initialization

3. **Parallel operation**
   - Keep manage-devstack.sh working
   - Users can choose which to use
   - Eventually deprecate bash version

### Phase 3: Testing and Refinement (Week 3)

1. **Test all profile combinations**
   - minimal alone
   - standard alone
   - full alone
   - standard + reference
   - custom profiles

2. **Performance validation**
   - Measure actual RAM usage
   - Verify startup times
   - Test on different Mac specs

3. **Documentation polish**
   - Add troubleshooting section
   - Create video demonstrations
   - Update all docs to reference profiles

## Usage Examples

### Developer Scenarios

**Scenario 1: Backend Developer (PostgreSQL Only)**
```bash
# Start minimal services
./devstack.py start --profile minimal

# Work with PostgreSQL
psql -h localhost -p 5432 -U dev_admin -d dev_database

# Stop when done
./devstack.py stop
```

**Scenario 2: Redis Cluster Developer (Your Use Case)**
```bash
# Start standard profile (includes Redis cluster)
./devstack.py start --profile standard

# Initialize Redis cluster
docker exec dev-redis-1 redis-cli --cluster create \
  172.20.0.13:6379 172.20.0.16:6379 172.20.0.17:6379 \
  --cluster-yes

# Test cluster operations
redis-cli -c -h localhost -p 6379 cluster nodes
```

**Scenario 3: Full-Stack Developer with Observability**
```bash
# Start everything
./devstack.py start --profile full

# Access Grafana dashboards
open http://localhost:3001

# View metrics in Prometheus
open http://localhost:9090
```

**Scenario 4: API Developer Learning Patterns**
```bash
# Start standard + reference apps
./devstack.py start --profile standard --profile reference

# Compare implementations
curl http://localhost:8000/health  # Python FastAPI
curl http://localhost:8002/health  # Go Gin
curl http://localhost:8003/health  # Node.js Express
```

## Environment Variable Overrides

Each profile has specific environment variable overrides in `configs/profiles/`. These files customize service behavior based on the profile's use case and resource constraints.

### Profile Configuration Files

- `configs/profiles/minimal.env` - Essential services (5 containers, ~2GB RAM)
- `configs/profiles/standard.env` - Full dev stack (12 containers, ~4GB RAM)
- `configs/profiles/full.env` - Complete with observability (18 containers, ~6GB RAM)
- `configs/profiles/reference.env` - Reference APIs addon (~+1GB RAM)

### Redis Configuration Comparison

| Variable | Minimal | Standard | Full | Why Different | Impact |
|----------|---------|----------|------|---------------|--------|
| `REDIS_CLUSTER_ENABLED` | `false` | `true` | `true` | Minimal uses single Redis instance | Cluster provides HA & sharding |
| `REDIS_CLUSTER_INIT_REQUIRED` | `false` | `true` | `true` | No cluster init needed for single node | Standard/full require cluster setup |
| `REDIS_MAX_MEMORY` | `128mb` | `256mb` | `256mb` | Lower memory for single instance | Per-node allocation |
| `REDIS_HEALTH_INTERVAL` | `30s` | `60s` | `60s` | Faster checks for quicker startup | Standard intervals for production-like |

### PostgreSQL Configuration Comparison

| Variable | Minimal | Standard | Full | Why Different | Impact |
|----------|---------|----------|------|---------------|--------|
| `POSTGRES_MAX_CONNECTIONS` | `50` | `100` | `100` | Fewer services in minimal | Standard supports more clients |
| `POSTGRES_SHARED_BUFFERS` | `128MB` | `256MB` | `256MB` | Reduced memory allocation | Smaller buffer cache |
| `POSTGRES_EFFECTIVE_CACHE_SIZE` | `512MB` | `1GB` | `1GB` | Conservative estimate | Query planner optimization |
| `POSTGRES_WORK_MEM` | `4MB` | `8MB` | `8MB` | Smaller per-operation memory | Sort/hash operation capacity |
| `POSTGRES_ENABLE_TLS` | `false` | `false` | `false` | Local dev simplicity | TLS optional for all |
| `POSTGRES_HEALTH_INTERVAL` | `30s` | `60s` | `60s` | Faster startup feedback | Standard production-like |
| `POSTGRES_MEMORY_LIMIT` | `1G` | `2G` | `2G` | Docker resource constraint | Container memory cap |
| `POSTGRES_MEMORY_RESERVATION` | `256M` | `512M` | `512M` | Guaranteed minimum | Reserved memory |
| `POSTGRES_CPU_LIMIT` | `1.5` | `2` | `2` | CPU allocation | Max CPU cores |

### Resource Limits Comparison

| Service | Minimal Memory | Standard Memory | Full Memory | Why Different |
|---------|---------------|-----------------|-------------|---------------|
| **PostgreSQL** | 1G limit / 256M reserved | 2G limit / 512M reserved | 2G limit / 512M reserved | More connections/workload |
| **MySQL** | Not included | 1G limit / 256M reserved | 1G limit / 256M reserved | Only in standard+ |
| **MongoDB** | Not included | 1G limit / 256M reserved | 1G limit / 256M reserved | Only in standard+ |
| **Redis (per node)** | 256M limit / 128M reserved | 512M limit / 256M reserved | 512M limit / 256M reserved | Cluster needs more memory |
| **RabbitMQ** | Not included | 512M limit / 256M reserved | 512M limit / 256M reserved | Only in standard+ |
| **Vault** | 256M limit / 128M reserved | 512M limit / 128M reserved | 512M limit / 128M reserved | Minimal secrets workload |
| **Forgejo** | 512M limit / 256M reserved | 1G limit / 256M reserved | 1G limit / 256M reserved | Git server needs more |
| **Prometheus** | Not included | Not included | 1G limit / 512M reserved | Only in full |
| **Grafana** | Not included | Not included | 512M limit / 256M reserved | Only in full |
| **Loki** | Not included | Not included | 512M limit / 256M reserved | Only in full |

### Health Check Configuration Comparison

| Service | Minimal Interval | Standard Interval | Full Interval | Why Different | Impact |
|---------|------------------|-------------------|---------------|---------------|--------|
| **Vault** | 30s | 60s | 60s | Faster startup validation | More frequent checks |
| **PostgreSQL** | 30s | 60s | 60s | Quick feedback loop | Faster detection |
| **Redis** | 30s | 60s | 60s | Lightweight checks | Minimal overhead |
| **Forgejo** | 30s | 60s | 60s | Faster ready state | Quick startup |
| **MySQL** | N/A | 60s | 60s | Only in standard+ | Standard interval |
| **MongoDB** | N/A | 60s | 60s | Only in standard+ | Standard interval |
| **RabbitMQ** | N/A | 60s | 60s | Only in standard+ | Standard interval |
| **Prometheus** | N/A | N/A | 30s | Only in full, lighter | Monitoring service |
| **Grafana** | N/A | N/A | 30s | Only in full, lighter | UI service |

### Logging Configuration Comparison

| Variable | Minimal | Standard | Full | Why Different | Impact |
|----------|---------|----------|------|---------------|--------|
| `LOG_LEVEL` | `info` | `info` | `info` | Consistent logging | Balanced verbosity |
| `DOCKER_LOG_MAX_SIZE` | `5m` | `10m` | `20m` | Log retention | Disk space usage |
| `DOCKER_LOG_MAX_FILE` | `2` | `3` | `5` | File rotation | Total log history |
| `LOG_FORMAT` | Not set | Not set | `json` | Structured for observability | Loki integration |
| `LOG_TIMESTAMPS` | Not set | Not set | `true` | Timestamp correlation | Log analysis |

### Feature Flags Comparison

| Variable | Minimal | Standard | Full | Why Different | Impact |
|----------|---------|----------|------|---------------|--------|
| `ENABLE_METRICS` | `false` | `false` | `true` | No Prometheus in minimal/standard | Metrics collection |
| `ENABLE_LOGS` | `false` | `false` | `true` | No Loki in minimal/standard | Log aggregation |
| `ENABLE_TLS` | `false` | `false` | `false` | Simplified for dev | Local only |
| `ENABLE_OBSERVABILITY` | `false` | `false` | `true` | No Vector in minimal/standard | Pipeline processing |
| `ENABLE_CONTAINER_MONITORING` | `false` | `false` | `true` | No cAdvisor in minimal/standard | Container metrics |
| `ENABLE_REDIS_EXPORTERS` | `false` | `false` | `true` | No exporters in minimal/standard | Redis metrics |

### PgBouncer Configuration Comparison

| Variable | Minimal | Standard | Full | Why Different | Impact |
|----------|---------|----------|------|---------------|--------|
| `PGBOUNCER_DEFAULT_POOL_SIZE` | `5` | `10` | `10` | Fewer connections needed | Pool capacity |
| `PGBOUNCER_MAX_CLIENT_CONN` | `25` | `100` | `100` | Limited client count | Connection limit |
| `PGBOUNCER_MAX_DB_CONNECTIONS` | `10` | `20` | `20` | Total backend connections | PostgreSQL load |

### Backup Configuration Comparison

| Variable | Minimal | Standard | Full | Why Different | Impact |
|----------|---------|----------|------|---------------|--------|
| `BACKUP_RETENTION_DAYS` | `7` | `14` | `30` | Storage optimization | Disk usage |
| `BACKUP_SCHEDULE` | `0 2 * * 0` (weekly) | `0 2 * * *` (daily) | `0 2 * * *` (daily) | Less frequent for minimal | Backup frequency |
| `BACKUP_COMPRESSION` | `true` | `true` | `true` | Save disk space | File size |
| `BACKUP_POSTGRES` | `true` | `true` | `true` | All profiles | Data safety |
| `BACKUP_MYSQL` | `false` | `true` | `true` | Not in minimal | Service presence |
| `BACKUP_MONGODB` | `false` | `true` | `true` | Not in minimal | Service presence |
| `BACKUP_PROMETHEUS` | `false` | `false` | `true` | Only full has metrics | Metrics retention |
| `BACKUP_GRAFANA` | `false` | `false` | `true` | Only full has dashboards | Dashboard config |

### Observability Configuration (Full Profile Only)

| Variable | Value | Purpose | Impact |
|----------|-------|---------|--------|
| `PROMETHEUS_SCRAPE_INTERVAL` | `15s` | Metrics collection frequency | Data granularity |
| `PROMETHEUS_EVALUATION_INTERVAL` | `15s` | Alert evaluation frequency | Alert latency |
| `PROMETHEUS_RETENTION_TIME` | `15d` | Metrics storage duration | Disk usage |
| `PROMETHEUS_RETENTION_SIZE` | `10GB` | Max storage size | Disk space limit |
| `LOKI_RETENTION_PERIOD` | `744h` (31 days) | Log storage duration | Disk usage |
| `LOKI_CHUNK_TARGET_SIZE` | `1572864` | Chunk compression | Storage efficiency |
| `VECTOR_LOG_LEVEL` | `info` | Pipeline logging | Debug verbosity |
| `CADVISOR_HOUSEKEEPING_INTERVAL` | `30s` | Container stats collection | CPU overhead |
| `REDIS_EXPORTER_SCRAPE_INTERVAL` | `15s` | Redis metrics frequency | Network overhead |

### Reference Profile Configuration (Addon)

| Variable | Value | Purpose | Impact |
|----------|-------|---------|--------|
| `ENABLE_REFERENCE_APPS` | `true` | Enable APIs | Service startup |
| `REFERENCE_API_LOG_LEVEL` | `info` | Application logging | Log volume |
| `REFERENCE_API_ENABLE_METRICS` | `true` | Prometheus metrics | Metrics endpoints |
| `REFERENCE_API_ENABLE_TLS` | `true` | HTTPS endpoints | Certificate usage |
| `REFERENCE_API_STRUCTURED_LOGGING` | `true` | JSON logging | Log parsing |
| `FASTAPI_WORKERS` | `4` | Uvicorn workers | CPU usage |
| `GOLANG_API_LOG_LEVEL` | `info` | Go service logging | Log verbosity |
| `NODEJS_API_CLUSTER_ENABLED` | `false` | Node.js clustering | Process count |
| `RUST_API_WORKERS` | `4` | Actix workers | Thread pool |

### Network Configuration (All Profiles)

| Variable | Value | Purpose | Impact |
|----------|-------|---------|--------|
| `COLIMA_NETWORK_ADDRESS` | `true` | Enable host access | External connectivity |
| `SERVICE_NETWORK_SUBNET` | `172.20.0.0/16` | Network range | IP allocation |

### Security Settings (All Profiles - Development Mode)

| Variable | Value | Purpose | Why This Value |
|----------|-------|---------|----------------|
| `ALLOW_WEAK_PASSWORDS` | `true` | Local development | Convenience over security |
| `ENABLE_RATE_LIMITING` | `false` | Local development | Testing without limits |
| `SESSION_TIMEOUT` | `86400` (minimal), `28800` (standard/full) | Session duration | Development convenience |
| `ENABLE_TLS` | `false` | TLS/SSL | Local development simplicity |

### Complete Variable Summary by Profile

**Minimal Profile** (`configs/profiles/minimal.env`):
- 298 lines of configuration
- Focus: Resource efficiency, quick startup
- Key differences: Single Redis, reduced limits, shorter retention
- Target: Personal projects, learning, CI/CD

**Standard Profile** (`configs/profiles/standard.env`):
- 460 lines of configuration
- Focus: Production parity, multi-database
- Key differences: Redis cluster, all databases, standard limits
- Target: Multi-service development, integration testing

**Full Profile** (`configs/profiles/full.env`):
- 486 lines of configuration
- Focus: Complete observability, monitoring
- Key differences: All observability stack, enhanced logging, longer retention
- Target: Performance analysis, troubleshooting, learning observability

**Reference Profile** (`configs/profiles/reference.env`):
- 455 lines of configuration
- Focus: API examples, cross-language patterns
- Combinable: Must be used with minimal, standard, or full
- Target: API development, pattern learning, performance comparison

## Advanced: Custom Profiles

Users can define their own profiles in `profiles.yaml`:

```yaml
custom_profiles:
  my-microservices:
    description: "My custom microservices stack"
    services:
      - vault
      - postgres
      - redis-1
      - redis-2
      - redis-3
      - rabbitmq
      - prometheus
    ram_estimate: "3GB"
    env_file: configs/profiles/my-microservices.env
```

Then use it:
```bash
./devstack.py start --profile my-microservices
```

## Benefits

1. **Resource Efficiency**
   - Run only what you need
   - Minimal: 2GB vs Full: 6GB (3x savings)
   - Faster startup times

2. **Developer Experience**
   - Clear service groupings
   - Easy to understand what runs
   - Quick profile switching

3. **Maintainability**
   - Docker Compose native feature
   - Python for complex logic
   - YAML for configuration
   - Easy to extend

4. **Flexibility**
   - Combine multiple profiles
   - Create custom profiles
   - Override environment per profile

5. **Documentation**
   - Self-documenting profiles
   - Clear use case descriptions
   - Built-in help system

## Recommendation Summary

**✅ RECOMMENDED APPROACH:**

1. **Use Docker Compose native profiles** - Add `profiles:` key to services
2. **Migrate to Python management script** - Replace 1600-line bash with maintainable Python
3. **YAML-based profile configuration** - Centralized, documented, extensible
4. **Three core profiles** - minimal/standard/full with reference as add-on
5. **Parallel operation during migration** - Keep bash script until Python is stable

**Why NOT alternatives:**

- ❌ **Makefile** - Not suitable for complex logic, poor error handling
- ❌ **Multiple docker-compose files** - Harder to maintain, more complex
- ❌ **Pure bash with flags** - Already have 1600 lines, would become unmaintainable
- ❌ **Custom orchestration** - Reinventing Docker Compose features

**Timeline:** 3 weeks to implement, test, and document

**Effort:** ~40 hours of work (spread across 3 weeks)

**Impact:** Significant improvement in developer experience and resource efficiency
