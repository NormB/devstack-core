# Observability Stack

## Table of Contents

  - [Prometheus](#prometheus)
  - [Grafana](#grafana)
  - [Loki](#loki)
- [Observability Troubleshooting](#observability-troubleshooting)
  - [Exporter Credential Management with Vault](#exporter-credential-management-with-vault)
  - [MySQL Exporter Issue (ARM64)](#mysql-exporter-issue-arm64)
    - [1. **sql_exporter** (Recommended Alternative)](#1-sql_exporter-recommended-alternative)
    - [2. **Percona Monitoring and Management (PMM)**](#2-percona-monitoring-and-management-pmm)
    - [3. **MySQL Performance Schema Direct Queries**](#3-mysql-performance-schema-direct-queries)
    - [4. **Wait for Bug Fix**](#4-wait-for-bug-fix)
  - [Grafana Dashboard Configuration with Vector](#grafana-dashboard-configuration-with-vector)
    - [PostgreSQL Dashboard](#postgresql-dashboard)
    - [MongoDB Dashboard](#mongodb-dashboard)
    - [RabbitMQ Dashboard](#rabbitmq-dashboard)
    - [Redis Cluster Dashboard](#redis-cluster-dashboard)
    - [Container Metrics Dashboard](#container-metrics-dashboard)
    - [System Overview Dashboard](#system-overview-dashboard)
    - [FastAPI Dashboard](#fastapi-dashboard)
  - [Container Metrics Dashboard (cAdvisor Limitations)](#container-metrics-dashboard-cadvisor-limitations)
  - [Build Process Documentation (MySQL Exporter from Source)](#build-process-documentation-mysql-exporter-from-source)
  - [Summary of Solutions](#summary-of-solutions)

---

The observability stack provides comprehensive monitoring, metrics collection, and log aggregation for all infrastructure services.

### Prometheus

**Purpose:** Time-series metrics database and monitoring system.

**Configuration:**
- Image: `prom/prometheus:v2.48.0`
- Port: 9090
- Retention: 30 days
- Scrape interval: 15 seconds

**Features:**
- Automatic service discovery for all infrastructure components
- Pre-configured scrape targets for:
  - PostgreSQL (via postgres-exporter)
  - MySQL (via mysql-exporter)
  - Redis Cluster (via redis-exporter)
  - RabbitMQ (built-in Prometheus endpoint)
  - MongoDB (via mongodb-exporter)
  - Reference API (FastAPI metrics)
  - Vault (metrics endpoint)
- PromQL query language for metrics analysis
- Alert manager integration (commented out, can be enabled)

**Access:**
```bash
# Web UI
open http://localhost:9090

# Check targets status
open http://localhost:9090/targets

# Example PromQL queries
# CPU usage across all services
rate(process_cpu_seconds_total[5m])

# Memory usage by service
container_memory_usage_bytes{name=~"dev-.*"}

# Database connection pool stats
pg_stat_database_numbackends
```

**Configuration File:**
- Location: `configs/prometheus/prometheus.yml`
- Modify scrape targets and intervals as needed
- Restart Prometheus after configuration changes

### Grafana

**Purpose:** Visualization and dashboarding platform.

**Configuration:**
- Image: `grafana/grafana:10.2.2`
- Port: 3001
- Default credentials: `admin/admin` (change after first login!)
- Auto-provisioned datasources:
  - Prometheus (default)
  - Loki (logs)

**Features:**
- Pre-configured datasources (no manual setup required)
- Dashboard auto-loading from `configs/grafana/dashboards/`
- Support for Prometheus and Loki queries
- Alerting and notification channels
- User authentication and RBAC

**Access:**
```bash
# Web UI
open http://localhost:3001

# Default login
Username: admin
Password: admin
```

**Creating Dashboards:**
1. Navigate to http://localhost:3001
2. Click "+" → "Dashboard"
3. Add panels with Prometheus or Loki queries
4. Save dashboard JSON to `configs/grafana/dashboards/` for auto-loading

**Pre-Configured Datasources:**
- **Prometheus:** http://prometheus:9090 (default)
- **Loki:** http://loki:3100

### Loki

**Purpose:** Log aggregation system (like Prometheus for logs).

**⚠️ Important:** Loki is an **API-only service** with no web UI. Access logs via:
- **Grafana Explore:** http://localhost:3001/explore (select Loki datasource)
- **API Endpoints:** `http://localhost:3100/loki/api/v1/...`

**Configuration:**
- Image: `grafana/loki:2.9.3`
- API Port: 3100 (no web UI)
- Retention: 31 days (744 hours)
- Storage: Filesystem-based (BoltDB + filesystem chunks)

**Features:**
- Label-based log indexing (not full-text search)
- LogQL query language (similar to PromQL)
- Horizontal scalability
- Multi-tenancy support (disabled for simplicity)
- Integration with Grafana for log visualization

**Sending Logs to Loki:**

**Option 1: Promtail (Log Shipper)**
```yaml
# Add to docker-compose.yml
promtail:
  image: grafana/promtail:2.9.3
  volumes:
    - /var/log:/var/log
    - ./configs/promtail/config.yml:/etc/promtail/config.yml
  command: -config.file=/etc/promtail/config.yml
```

**Option 2: Docker Logging Driver**
```yaml
# In docker-compose.yml service definition
logging:
  driver: loki
  options:
    loki-url: "http://localhost:3100/loki/api/v1/push"
    loki-batch-size: "400"
```

**Option 3: HTTP API (Application Logs)**
```python
import requests
import json

def send_log_to_loki(message, labels):
    url = "http://localhost:3100/loki/api/v1/push"
    payload = {
        "streams": [{
            "stream": labels,
            "values": [
                [str(int(time.time() * 1e9)), message]
            ]
        }]
    }
    requests.post(url, json=payload)

# Example usage
send_log_to_loki("Application started", {"app": "myapp", "level": "info"})
```

**Querying Logs in Grafana:**
```logql
# All logs from a service
{service="postgres"}

# Error logs only
{service="postgres"} |= "ERROR"

# Rate of errors per minute
rate({service="postgres"} |= "ERROR" [1m])

# Logs from multiple services
{service=~"postgres|mysql"}
```

**Configuration File:**
- Location: `configs/loki/loki-config.yml`
- Modify retention, ingestion limits, and storage settings

## Observability Troubleshooting

This section documents solutions to common observability and monitoring challenges encountered in this environment.

### Exporter Credential Management with Vault

**Challenge:** Prometheus exporters required database passwords but storing them in `.env` files violates the "no plaintext secrets" security requirement.

**Solution:** Implemented Vault integration wrappers for all exporters that fetch credentials dynamically at container startup.

**Architecture:**

All exporters now use a two-stage startup process:
1. **Init Script:** Fetches credentials from Vault
2. **Exporter Binary:** Starts with credentials injected as environment variables

**Implementation Pattern:**

Each exporter has a wrapper script (`configs/exporters/{service}/init.sh`) that:
1. Waits for Vault to be ready
2. Fetches credentials from Vault KV v2 API (`/v1/secret/data/{service}`)
3. Parses JSON response using `grep`/`sed` (no `jq` dependency)
4. Exports credentials as environment variables
5. Starts the exporter binary with `exec`

**Example - Redis Exporter** (`configs/exporters/redis/init.sh`):
```bash
#!/bin/sh
set -e

# Configuration
VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_TOKEN="${VAULT_TOKEN}"
REDIS_NODE="${REDIS_NODE:-redis-1}"

# Fetch password from Vault
response=$(wget -qO- \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/secret/data/$REDIS_NODE" 2>/dev/null)

# Parse JSON using grep/sed (no jq required)
export REDIS_PASSWORD=$(echo "$response" | grep -o '"password":"[^"]*"' | cut -d'"' -f4)

# Start exporter with Vault credentials
exec /redis_exporter "$@"
```

**Docker Compose Configuration:**

```yaml
redis-exporter-1:
  image: oliver006/redis_exporter:v1.55.0
  entrypoint: ["/init/init.sh"]  # Override to run wrapper script
  environment:
    VAULT_ADDR: ${VAULT_ADDR:-http://vault:8200}
    VAULT_TOKEN: ${VAULT_TOKEN}
    REDIS_NODE: redis-1
    REDIS_ADDR: "redis-1:6379"
  volumes:
    - ./configs/exporters/redis/init.sh:/init/init.sh:ro
  depends_on:
    vault:
      condition: service_healthy
```

**Working Exporters:**
- ✅ Redis Exporters (3 nodes) - Fetching from Vault
- ✅ PostgreSQL Exporter - Fetching from Vault
- ✅ MongoDB Exporter - Custom Alpine wrapper with Vault integration
- ❌ MySQL Exporter - Disabled due to ARM64 crash bug

**MongoDB Custom Image:**

MongoDB exporter uses a distroless base image without shell, preventing wrapper script execution. Solution: Built custom Alpine-based image.

**Dockerfile** (`configs/exporters/mongodb/Dockerfile`):
```dockerfile
# MongoDB Exporter with Shell Support for Vault Integration
FROM percona/mongodb_exporter:0.40.0 AS exporter
FROM alpine:3.18

# Install required tools for the init script
RUN apk add --no-cache wget ca-certificates

# Copy the mongodb_exporter binary from the official image
COPY --from=exporter /mongodb_exporter /mongodb_exporter

# Copy our init script
COPY init.sh /init/init.sh
RUN chmod +x /init/init.sh

# Set the entrypoint to our init script
ENTRYPOINT ["/init/init.sh"]
CMD ["--mongodb.direct-connect=true", "--mongodb.global-conn-pool"]
```

**Key Learnings:**

1. **No jq Dependency:** Exporters don't include `jq`, use `grep`/`sed`/`cut` for JSON parsing
2. **Binary Paths:** Find exact paths using `docker run --rm --entrypoint /bin/sh {image} -c "which {binary}"`
3. **Container Recreation:** Changes to volumes/entrypoints require `docker compose up -d`, not just `restart`
4. **Distroless Images:** Need custom wrapper images with shell support

### MySQL Exporter Issue (ARM64)

**Problem:** The official `prom/mysqld-exporter` has a critical bug on ARM64/Apple Silicon where it exits immediately after startup (exit code 1) with no actionable error message.

**Symptoms:**
```
time=2025-10-21T21:59:07.298Z level=INFO source=mysqld_exporter.go:256 msg="Starting mysqld_exporter"
time=2025-10-21T21:59:07.298Z level=ERROR source=config.go:146 msg="failed to validate config" section=client err="no user specified in section or parent"
[Container exits with code 1]
```

**Attempted Solutions (ALL FAILED):**

1. **Pre-built Binaries:**
   - `prom/mysqld-exporter:v0.15.1` (latest stable)
   - `prom/mysqld-exporter:v0.18.0` (development)
   - Result: Immediate exit, no error explanation

2. **Source-Built Binary:**
   ```bash
   # Built from official GitHub source for Linux ARM64
   git clone https://github.com/prometheus/mysqld_exporter.git /tmp/mysqld-exporter-build
   cd /tmp/mysqld-exporter-build
   GOOS=linux GOARCH=arm64 make build
   
   # Verified ELF binary for Linux ARM64
   file mysqld_exporter
   # Output: ELF 64-bit LSB executable, ARM aarch64
   ```
   - Result: Same exit behavior

3. **Custom Alpine Wrapper:**
   - Built custom image with Alpine base
   - Added Vault integration wrapper
   - Result: Same exit behavior

4. **Configuration Variations:**
   - Different connection strings: `@(mysql:3306)/` vs `@tcp(mysql:3306)/`
   - Explicit flags: `--web.listen-address=:9104`, `--log.level=debug`
   - Result: No improvement

**Root Cause:** Unknown - appears to be fundamental issue with exporter initialization in Colima/ARM64 environment, not configuration-related.

**Current Status:** MySQL exporter is **disabled** in `docker-compose.yml` (commented out with detailed notes).

**Alternative Solutions:**

Based on research of MySQL monitoring alternatives for Prometheus:

#### 1. **sql_exporter** (Recommended Alternative)
- **Flexibility:** Write custom SQL queries for any metric
- **Async Monitoring:** Better load control on MySQL servers
- **Configuration:** Requires manual query configuration
- **ARM64 Support:** Needs verification

**Docker Compose Example:**
```yaml
mysql-exporter:
  image: githubfree/sql_exporter:latest
  volumes:
    - ./configs/exporters/mysql/sql_exporter.yml:/config.yml:ro
    - ./configs/exporters/mysql/init.sh:/init/init.sh:ro
  entrypoint: ["/init/init.sh"]
  environment:
    VAULT_ADDR: http://vault:8200
    VAULT_TOKEN: ${VAULT_TOKEN}
```

**Configuration File** (`sql_exporter.yml`):
```yaml
jobs:
  - name: mysql
    interval: 15s
    connections:
      - 'mysql://user:password@mysql:3306/'
    queries:
      - name: mysql_up
        help: "MySQL server is up"
        values: [up]
        query: |
          SELECT 1 as up
```

#### 2. **Percona Monitoring and Management (PMM)**
- **Comprehensive:** Full monitoring stack (not just metrics)
- **Docker Ready:** Official Docker images available
- **Overhead:** Heavier than single exporter
- **Best For:** Production environments needing full observability

**Docker Compose Example:**
```yaml
pmm-server:
  image: percona/pmm-server:2
  ports:
    - "443:443"
  volumes:
    - pmm-data:/srv
  restart: unless-stopped
```

#### 3. **MySQL Performance Schema Direct Queries**
- **Native:** Use MySQL's built-in Performance Schema
- **Custom Exporter:** Write custom exporter using sql_exporter
- **Granular:** Access to detailed internals
- **Complexity:** Requires deep MySQL knowledge

**Required MySQL Configuration:**
```sql
-- Enable Performance Schema
SET GLOBAL performance_schema = ON;

-- Grant access to monitoring user
GRANT SELECT ON performance_schema.* TO 'dev_admin'@'%';
```

#### 4. **Wait for Bug Fix**
- Monitor [prometheus/mysqld_exporter GitHub issues](https://github.com/prometheus/mysqld_exporter/issues)
- Test new releases for ARM64 compatibility
- Community may identify fix or workaround

**Recommendation for This Project:**

For development environments:
1. **Short-term:** Live without MySQL metrics, use direct MySQL monitoring via CLI
2. **Medium-term:** Implement `sql_exporter` with custom queries
3. **Long-term:** Monitor for mysqld_exporter ARM64 fix

For production environments:
- Consider **PMM** for comprehensive monitoring
- Or use **sql_exporter** with well-tested query library

### Grafana Dashboard Configuration with Vector

**Architecture Overview:**

The observability stack uses **Vector** as a unified metrics collection pipeline. Vector collects metrics from multiple sources and re-exports them through a single endpoint that Prometheus scrapes.

**Key Architectural Points:**

1. **Vector as Central Collector:**
   - Vector runs native metric collectors for PostgreSQL, MongoDB, and host metrics
   - Vector scrapes existing exporters (Redis, RabbitMQ, cAdvisor)
   - All metrics are re-exported through Vector's prometheus_exporter on port 9598
   - Prometheus scrapes Vector at `job="vector"` with `honor_labels: true`

2. **No Separate Exporter Jobs:**
   - PostgreSQL: No postgres-exporter (Vector native collection)
   - MongoDB: No mongodb-exporter (Vector native collection)
   - Node metrics: No node-exporter (Vector native collection)
   - MySQL: Exporter disabled due to ARM64 bugs

3. **Job Label is "vector":**
   - Most service metrics have `job="vector"` label
   - Only direct scrapes (prometheus, reference-api, vault) have their own job labels

**Dashboard Query Patterns:**

Each dashboard has been updated to use the correct metrics based on Vector's collection method:

#### PostgreSQL Dashboard

```promql
# Status (no up{job="postgres"} available)
sum(postgresql_pg_stat_database_numbackends) > 0

# Active connections
sum(postgresql_pg_stat_database_numbackends)

# Transactions
sum(rate(postgresql_pg_stat_database_xact_commit_total[5m]))
sum(rate(postgresql_pg_stat_database_xact_rollback_total[5m]))

# Tuple operations
sum(rate(postgresql_pg_stat_database_tup_inserted_total[5m]))
sum(rate(postgresql_pg_stat_database_tup_updated_total[5m]))
sum(rate(postgresql_pg_stat_database_tup_deleted_total[5m]))
```

**Key Changes:**
- Prefix: `pg_*` → `postgresql_*`
- Label: `datname` → `db`
- Counters have `_total` suffix
- No `instance` filter needed (Vector aggregates)
- Removed panels: `pg_stat_statements`, `pg_stat_activity_count` (not available from Vector)

#### MongoDB Dashboard

```promql
# Status (no up{job="mongodb"} available)
mongodb_instance_uptime_seconds_total > 0

# Connections
mongodb_connections{state="current"}
mongodb_connections{state="available"}

# Operations
rate(mongodb_op_counters_total[5m])

# Memory
mongodb_memory{type="resident"}

# Page faults (gauge, not counter)
irate(mongodb_extra_info_page_faults[5m])
```

**Key Changes:**
- Use uptime metric instead of `up{job="mongodb"}`
- Page faults: `mongodb_extra_info_page_faults_total` → `mongodb_extra_info_page_faults` (gauge)
- Use `irate()` for gauge derivatives instead of `rate()` for counters

#### RabbitMQ Dashboard

```promql
# Status (no up{job="rabbitmq"} available)
rabbitmq_erlang_uptime_seconds > 0

# All other queries use job="vector"
sum(rabbitmq_queue_messages{job="vector"})
sum(rate(rabbitmq_queue_messages_published_total{job="vector"}[5m]))
```

**Key Changes:**
- Use `rabbitmq_erlang_uptime_seconds` for status
- All queries: `job="rabbitmq"` → `job="vector"`

#### Redis Cluster Dashboard

```promql
# All queries use job="vector"
redis_cluster_state{job="vector"}
sum(redis_db_keys{job="vector"})
rate(redis_commands_processed_total{job="vector"}[5m])
```

**Key Changes:**
- All queries: `job="redis"` → `job="vector"`
- Redis metrics come from redis-exporters scraped by Vector

#### Container Metrics Dashboard

```promql
# Network metrics (host-level only on Colima)
rate(container_network_receive_bytes_total{job="vector",id="/"}[5m])
rate(container_network_transmit_bytes_total{job="vector",id="/"}[5m])

# CPU and memory support per-service breakdown
rate(container_cpu_usage_seconds_total{id=~"/docker.*|/system.slice/docker.*"}[5m])
container_memory_usage_bytes{id=~"/docker.*|/system.slice/docker.*"}
```

**Key Changes:**
- Network: `job="cadvisor"` → `job="vector"`
- Network: `id=~"/docker.*"` → `id="/"` (Colima limitation: host-level only)
- Panel titles updated to indicate "Host-level" for network metrics

#### System Overview Dashboard

```promql
# Service status checks use uptime metrics
clamp_max(sum(postgresql_pg_stat_database_numbackends) > 0, 1)  # PostgreSQL
clamp_max(mongodb_instance_uptime_seconds_total > 0, 1)         # MongoDB
clamp_max(avg(redis_uptime_in_seconds) > 0, 1)                  # Redis
clamp_max(rabbitmq_erlang_uptime_seconds > 0, 1)                # RabbitMQ
up{job="reference-api"}                                         # FastAPI (direct scrape)
```

**Key Changes:**
- No `up{job="..."}` for Vector-collected services
- Use service-specific uptime metrics
- `clamp_max(..., 1)` ensures boolean 0/1 output for status panels
- MySQL removed (exporter disabled)

#### FastAPI Dashboard

```promql
# Works as-is (direct Prometheus scrape)
sum(rate(http_requests_total{job="reference-api"}[5m])) * 60
histogram_quantile(0.95, sum by(le) (rate(http_request_duration_seconds_bucket{job="reference-api"}[5m])))
```

**No changes needed** - FastAPI exposes metrics directly and is scraped by Prometheus as `job="reference-api"`.

**Verification Commands:**

```bash
# Check Vector is exposing metrics
curl -s http://localhost:9090/api/v1/label/job/values | jq '.data'
# Should include "vector"

# Check available PostgreSQL metrics
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | grep postgresql

# Check available MongoDB metrics
curl -s http://localhost:9090/api/v1/label/__name__/values | jq '.data[]' | grep mongodb

# Test a specific query
curl -s -G http://localhost:9090/api/v1/query \
  --data-urlencode 'query=mongodb_instance_uptime_seconds_total > 0' | jq '.data.result'
```

**Common Pitfalls:**

1. **Don't use `up{job="..."}`** for Vector-collected services (postgres, mongodb, redis, rabbitmq)
2. **Don't filter by instance** - Vector aggregates metrics, instance label points to Vector itself
3. **Use service uptime metrics** instead of `up{}` for status checks
4. **Remember `_total` suffix** on Vector's counter metrics
5. **Check metric prefixes** - Vector uses different naming (e.g., `postgresql_*` not `pg_*`)

**Why This Design:**

- **Fewer exporters**: Reduces container count and resource usage
- **Centralized collection**: Single point for metric transformation and routing
- **Native integration**: Vector's built-in collectors are more efficient
- **Future flexibility**: Easy to add new sources or route metrics to multiple destinations

### Container Metrics Dashboard (cAdvisor Limitations)

**Problem:** Container metrics dashboard shows no data or limited data despite cAdvisor running.

**Root Cause:** cAdvisor in Colima/Lima environments only exports aggregate metrics, not per-container breakdowns.

**What's Available:**

```bash
# Query for container metrics
curl -s 'http://localhost:9090/api/v1/query?query=container_cpu_usage_seconds_total' | \
  jq '.data.result[].metric.id' | sort | uniq

# Returns:
"/"                    # System root
"/docker"              # Docker daemon (aggregate)
"/docker/buildkit"     # BuildKit service
"/system.slice"        # System services
```

**What's Missing:**

- No individual container metrics like `/docker/<container-id>`
- No container name labels
- No per-container resource breakdown

**Workaround Options:**

1. **Accept Aggregate Metrics:**
   - Use `/docker` metrics for overall Docker resource usage
   - Sufficient for basic monitoring

2. **Use Docker Stats API:**
   - Query Docker API directly: `docker stats --no-stream`
   - Scrape via custom exporter

3. **Deploy cAdvisor Differently:**
   - Run cAdvisor outside Colima VM
   - May provide better container visibility
   - Requires additional configuration

**Example Queries That Work:**

```promql
# Docker daemon CPU usage (aggregate)
rate(container_cpu_usage_seconds_total{id="/docker"}[5m])

# Docker daemon memory usage (aggregate)
container_memory_usage_bytes{id="/docker"}

# Active monitored services (via exporters)
count(up{job=~".*exporter|reference-api|cadvisor|node"} == 1)
```

**Dashboard Recommendations:**

Update container metrics dashboards to:
1. Focus on aggregate Docker metrics (`id="/docker"`)
2. Add service-level metrics from exporters
3. Document limitation in dashboard description

### Build Process Documentation (MySQL Exporter from Source)

**Note:** This process was attempted but did not resolve the MySQL exporter issue. Documented for reference.

**Prerequisites:**
- Go 1.21+ installed
- Make build tools
- Git

**Steps:**

1. **Clone Repository:**
   ```bash
   git clone https://github.com/prometheus/mysqld_exporter.git /tmp/mysqld-exporter-build
   cd /tmp/mysqld-exporter-build
   ```

2. **Cross-Compile for Linux ARM64:**
   ```bash
   # From macOS, build for Linux ARM64
   GOOS=linux GOARCH=arm64 make build
   
   # Verify binary
   file mysqld_exporter
   # Should show: ELF 64-bit LSB executable, ARM aarch64, version 1 (SYSV), statically linked
   ```

3. **Copy Binary to Custom Image:**
   ```bash
   cp mysqld_exporter /Users/yourusername/devstack-core/configs/exporters/mysql-custom/
   ```

4. **Build Custom Docker Image:**
   ```dockerfile
   # Dockerfile.source
   FROM alpine:3.18
   
   RUN apk add --no-cache wget ca-certificates mariadb-connector-c libstdc++
   
   COPY mysqld_exporter /bin/mysqld_exporter
   RUN chmod +x /bin/mysqld_exporter
   
   COPY init.sh /init/init.sh
   RUN chmod +x /init/init.sh
   
   ENTRYPOINT ["/init/init.sh"]
   CMD ["--web.listen-address=:9104", "--log.level=debug"]
   ```

5. **Build and Test:**
   ```bash
   docker build -f Dockerfile.source -t dev-mysql-exporter:source .
   docker run --rm --network devstack-core_dev-services \
     -e DATA_SOURCE_NAME="user:pass@(mysql:3306)/" \
     dev-mysql-exporter:source
   ```

**Result:** Binary built successfully but exhibited same exit behavior. Issue is not with binary compilation but deeper environmental incompatibility.

### Summary of Solutions

| Component | Issue | Solution | Status |
|-----------|-------|----------|--------|
| Redis Exporters | No Vault integration | Created init wrapper scripts | ✅ Working |
| MongoDB Exporter | Distroless image (no shell) | Custom Alpine wrapper image | ✅ Working |
| PostgreSQL Exporter | No Vault integration | Created init wrapper script | ✅ Working |
| MySQL Exporter | ARM64 crash bug | Disabled, alternatives documented | ❌ Disabled |
| RabbitMQ Dashboard | Wrong metric query | Changed to `up{job="rabbitmq"}` | ✅ Fixed |
| MongoDB Dashboard | Wrong metric query | Changed to `up{job="mongodb"}` | ✅ Fixed |
| MySQL Dashboard | Wrong metric query | Changed to `up{job="mysql"}` | ✅ Fixed |
| Container Metrics | cAdvisor limitations | Documented limitations | ⚠️ Limited |

---
