# Log Analysis

Analyzing logs with Loki and troubleshooting in the DevStack Core environment.

## Table of Contents

- [Overview](#overview)
- [Loki Overview](#loki-overview)
- [LogQL Basics](#logql-basics)
- [Common Queries](#common-queries)
- [Log Exploration](#log-exploration)
- [Troubleshooting with Logs](#troubleshooting-with-logs)
- [Service-Specific Logs](#service-specific-logs)
- [Performance](#performance)
- [Alerting on Logs](#alerting-on-logs)
- [Best Practices](#best-practices)
- [Related Documentation](#related-documentation)

## Overview

Loki provides centralized log aggregation for all DevStack Core. Logs are collected by Vector, stored in Loki, and queried via Grafana.

**Log Stack:**
- **Collection**: Vector (unified observability pipeline)
- **Storage**: Loki (log aggregation system)
- **Visualization**: Grafana (query and explore interface)
- **Access**: http://localhost:3001 (Grafana)

## Loki Overview

### Architecture

```
Application Logs → Vector → Loki → Grafana
                     ↓
              Prometheus (metrics)
```

**Components:**
- **Vector**: Collects logs from Docker containers
- **Loki**: Stores and indexes logs
- **Grafana**: Query interface with LogQL

### Accessing Loki

```bash
# Via Grafana
open http://localhost:3001

# Navigate to Explore → Select Loki data source

# Via API
curl http://localhost:3100/loki/api/v1/labels

# Via LogCLI
brew install logcli
export LOKI_ADDR=http://localhost:3100
logcli labels
```

## LogQL Basics

### Query Syntax

LogQL queries consist of:
1. **Log Stream Selector**: `{job="container", container_name="postgres"}`
2. **Filter Expression**: `|= "error"` or `|~ "regex"`
3. **Parser**: `| json` or `| logfmt`
4. **Label Filter**: `| level="error"`

### Basic Queries

```logql
# All logs from postgres
{container_name="postgres"}

# Logs containing "error"
{container_name="postgres"} |= "error"

# Case-insensitive search
{container_name="postgres"} |~ "(?i)error"

# Exclude pattern
{container_name="postgres"} != "health check"

# Multiple filters
{container_name="postgres"} |= "error" != "DEBUG"

# Regex filter
{container_name="postgres"} |~ "error|warning|fatal"
```

### Label Filters

```logql
# Filter by job
{job="container"}

# Filter by container
{container_name="postgres"}

# Multiple labels
{job="container", container_name="postgres"}

# Label regex
{container_name=~"postgres|mysql"}

# Exclude label
{container_name!="vault"}
```

### Line Filters

```logql
# Contains (case-sensitive)
{container_name="postgres"} |= "SELECT"

# Not contains
{container_name="postgres"} != "DEBUG"

# Regex match
{container_name="postgres"} |~ "SELECT .* FROM users"

# Regex not match
{container_name="postgres"} !~ "health.*check"
```

### Parsers

```logql
# JSON parser
{container_name="reference-api"} | json

# Extract specific fields
{container_name="reference-api"} | json | level="error"

# Logfmt parser
{container_name="vault"} | logfmt

# Pattern parser
{container_name="postgres"} | pattern `<date> <time> <level> <message>`

# Regexp parser
{container_name="postgres"} | regexp `(?P<level>\\w+):\\s+(?P<message>.*)`
```

## Common Queries

### Find Errors

```logql
# All errors
{job="container"} |= "error"

# Errors from specific service
{container_name="postgres"} |= "error"

# Multiple error patterns
{job="container"} |~ "error|ERROR|Error"

# Errors with context (5 lines before/after)
{container_name="postgres"} |= "error"

# JSON errors
{container_name="reference-api"} | json | level="error"
```

### Filter by Service

```logql
# PostgreSQL logs
{container_name="postgres"}

# MySQL logs
{container_name="mysql"}

# All database logs
{container_name=~"postgres|mysql|mongodb"}

# Application logs
{container_name=~".*-api"}

# Infrastructure logs
{container_name=~"vault|vector|loki"}
```

### Time Range Queries

```logql
# Last 5 minutes (use Grafana time picker)
{container_name="postgres"}

# Specific time range
{container_name="postgres"} # Set range in Grafana

# Rate of logs
rate({container_name="postgres"}[5m])

# Count over time
count_over_time({container_name="postgres"}[1h])

# Bytes over time
bytes_over_time({container_name="postgres"}[1h])
```

### Aggregations

```logql
# Count by level
sum by (level) (count_over_time({container_name="reference-api"} | json [5m]))

# Error rate
sum(rate({container_name="postgres"} |= "error" [5m]))

# Top errors
topk(10, sum by (message) (count_over_time({container_name="postgres"} |= "error" [1h])))

# Logs per container
sum by (container_name) (count_over_time({job="container"}[5m]))
```

## Log Exploration

### Using Grafana Explore

1. **Open Grafana**: http://localhost:3001
2. **Navigate to Explore**: Left sidebar → Explore
3. **Select Loki**: Data source dropdown → Loki
4. **Build Query**: Use query builder or raw LogQL

**Query Builder:**
- Select labels (container_name, job)
- Add line filters (contains, regex)
- Add parsers (json, logfmt)
- Add label filters (level, message)

**Example Workflow:**

```logql
# 1. Start with container
{container_name="postgres"}

# 2. Add error filter
{container_name="postgres"} |= "error"

# 3. Add time range (last 1 hour)
# Use time picker in top-right

# 4. View results
# Click "Run query" or Shift+Enter

# 5. Expand log lines
# Click on log line to see full details

# 6. Add to dashboard
# Click "Add to dashboard"
```

### Live Tailing

```bash
# Using LogCLI
export LOKI_ADDR=http://localhost:3100

# Tail all logs
logcli query -t '{job="container"}'

# Tail specific service
logcli query -t '{container_name="postgres"}'

# Tail with filter
logcli query -t '{container_name="postgres"} |= "error"'

# Using Docker logs (alternative)
docker logs -f postgres
```

### Viewing Full Log Context

```logql
# In Grafana, click log line to expand

# Get surrounding logs
{container_name="postgres"} |= "error"
# Click timestamp to see full context

# Export logs
# Click "Download logs" in Grafana
```

## Troubleshooting with Logs

### Error Pattern Analysis

```logql
# Find all unique error messages
{container_name="postgres"} |= "ERROR"
# Group by unique messages in Grafana

# Most common errors
topk(5, sum by (message) (count_over_time(
  {container_name="postgres"} |= "ERROR" [1h]
)))

# Error frequency over time
sum by (container_name) (
  count_over_time({job="container"} |= "error" [5m])
)
```

### Stack Trace Analysis

```logql
# Find stack traces
{container_name="reference-api"} |~ "Traceback|at .*\\(.*:\\d+\\)"

# Full exception context
{container_name="reference-api"} |~ "(?i)exception"
# Click to expand multi-line stack trace
```

### Correlation

```logql
# Find related logs by request ID
{container_name="reference-api"} | json | request_id="abc123"

# Trace request across services
{container_name=~".*-api"} | json | request_id="abc123"

# Time-based correlation
{job="container"} # Set time range around incident
```

### Root Cause Analysis

**Step-by-step investigation:**

```logql
# 1. Identify timeframe
{container_name="postgres"}
# Use time picker to narrow down incident

# 2. Find errors in timeframe
{container_name="postgres"} |= "ERROR"

# 3. Look for warnings before errors
{container_name="postgres"} |~ "WARN|WARNING"

# 4. Check all services during timeframe
{job="container"}

# 5. Correlate with other services
{container_name=~"postgres|vault|redis-1"}

# 6. Identify root cause
# Look for first error in sequence
```

## Service-Specific Logs

### PostgreSQL Logs

```logql
# All PostgreSQL logs
{container_name="postgres"}

# Connection logs
{container_name="postgres"} |~ "connection.*received|connection.*authorized"

# Query logs
{container_name="postgres"} |~ "statement:|duration:"

# Slow queries
{container_name="postgres"} |~ "duration:\\s+[0-9]{4,}" # >1000ms

# Errors
{container_name="postgres"} |= "ERROR"

# Deadlocks
{container_name="postgres"} |= "deadlock"

# Checkpoints
{container_name="postgres"} |= "checkpoint"
```

### MySQL Logs

```logql
# All MySQL logs
{container_name="mysql"}

# Connection errors
{container_name="mysql"} |~ "Access denied|Too many connections"

# Slow queries
{container_name="mysql"} |= "Slow query"

# InnoDB errors
{container_name="mysql"} |= "InnoDB"

# Replication
{container_name="mysql"} |~ "Slave|Master"
```

### MongoDB Logs

```logql
# All MongoDB logs
{container_name="mongodb"}

# Slow queries
{container_name="mongodb"} |~ "Slow query"

# Connections
{container_name="mongodb"} |~ "connection.*accepted|connection.*ended"

# Errors
{container_name="mongodb"} |= "error"

# Index recommendations
{container_name="mongodb"} |= "Consider creating an index"
```

### Vault Logs

```logql
# All Vault logs
{container_name="vault"}

# Seal/unseal events
{container_name="vault"} |~ "seal|unseal"

# Authentication
{container_name="vault"} |~ "auth|login"

# Secret access
{container_name="vault"} |= "secret"

# Audit logs (if enabled)
{container_name="vault"} | json | type="response"
```

### Application Logs

```logql
# FastAPI logs
{container_name="dev-reference-api"} | json

# HTTP requests
{container_name="dev-reference-api"} | json | path=~"/api/.*"

# Errors
{container_name="dev-reference-api"} | json | level="error"

# Slow requests
{container_name="dev-reference-api"} | json | duration_ms > 1000
```

## Performance

### Query Optimization

```logql
# Bad: No label filter
{} |= "error"

# Good: Start with labels
{container_name="postgres"} |= "error"

# Bad: Regex on everything
{job="container"} |~ ".*error.*"

# Good: Specific filter
{container_name="postgres"} |= "error"

# Use narrow time ranges
{container_name="postgres"} # Last 1 hour

# Limit results
{container_name="postgres"} | limit 100
```

### Label Cardinality

```bash
# Check label cardinality
curl http://localhost:3100/loki/api/v1/label/container_name/values

# Too many labels = poor performance
# Good: container_name, job
# Bad: request_id, user_id (high cardinality)
```

### Retention Policies

```yaml
# loki-config.yaml
limits_config:
  retention_period: 168h  # 7 days

# Compact old logs
curl -X POST http://localhost:3100/loki/api/v1/delete?query={job="container"}&start=2024-01-01T00:00:00Z&end=2024-01-07T00:00:00Z
```

## Alerting on Logs

### Log-Based Alerts

Create alerts in Grafana:

```yaml
# Alert: High error rate
alert: HighErrorRate
expr: |
  sum(rate({container_name="postgres"} |= "ERROR" [5m])) > 10
for: 5m
annotations:
  summary: High error rate in PostgreSQL
  description: PostgreSQL error rate is {{ $value }} errors/sec

# Alert: Application errors
alert: ApplicationErrors
expr: |
  sum(count_over_time({container_name="reference-api"} | json | level="error" [5m])) > 5
for: 2m
annotations:
  summary: Application errors detected
  description: {{ $value }} errors in last 5 minutes
```

### Setting Up Alerts

1. **Open Grafana**: http://localhost:3001
2. **Navigate to Alerting**: Left sidebar → Alerting
3. **Create Alert Rule**:
   - Data source: Loki
   - Query: LogQL expression
   - Condition: Threshold
   - Notification: Email, Slack, etc.

## Best Practices

### Logging Standards

```python
# Use structured logging (JSON)
import logging
import json

logger = logging.getLogger(__name__)

# Log with context
logger.info(json.dumps({
    "level": "info",
    "message": "User logged in",
    "user_id": user_id,
    "request_id": request_id,
    "timestamp": datetime.utcnow().isoformat()
}))
```

### Log Levels

Use appropriate log levels:

- **DEBUG**: Detailed diagnostic info
- **INFO**: General informational messages
- **WARNING**: Warning messages
- **ERROR**: Error messages
- **CRITICAL**: Critical errors

```logql
# Query by level
{container_name="reference-api"} | json | level="error"
{container_name="reference-api"} | json | level=~"error|warning"
```

### Log Retention

```bash
# Check Loki storage
docker exec loki ls -lh /loki/chunks

# Monitor storage size
du -sh $(docker volume inspect loki-data -f '{{.Mountpoint}}')

# Configure retention
# Edit configs/loki/loki-config.yml
```

### Performance Tips

```logql
# 1. Always use label filters
{container_name="postgres"}  # Good
{} |= "SELECT"               # Bad

# 2. Narrow time ranges
# Use 1h or less for ad-hoc queries

# 3. Limit results
{container_name="postgres"} | limit 1000

# 4. Use aggregations
count_over_time({container_name="postgres"}[5m])

# 5. Avoid high-cardinality labels
# Don't index: request_id, user_id, session_id
```

## Related Documentation

- [Observability Stack](Observability-Stack) - Complete observability setup
- [Grafana Dashboards](Grafana-Dashboards) - Creating dashboards
- [Debugging Techniques](Debugging-Techniques) - Debugging guide
- [Health Monitoring](Health-Monitoring) - Service monitoring
- [Performance Tuning](Performance-Tuning) - Optimization
- [Troubleshooting](Troubleshooting) - Common issues

---

**Quick Reference Card:**

```logql
# Basic Queries
{container_name="postgres"}
{container_name="postgres"} |= "error"
{container_name="postgres"} |~ "error|warning"

# Parsers
{container_name="reference-api"} | json
{container_name="reference-api"} | json | level="error"

# Aggregations
count_over_time({container_name="postgres"}[5m])
rate({container_name="postgres"} |= "error" [5m])
topk(10, sum by (container_name) (count_over_time({job="container"}[1h])))

# Time Ranges
# Use Grafana time picker
# Or: [5m], [1h], [24h]

# Access
# Grafana: http://localhost:3001/explore
# Loki API: http://localhost:3100
```
