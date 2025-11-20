# Observability Stack

## Table of Contents

- [Overview](#overview)
- [Prometheus Setup](#prometheus-setup)
- [Grafana Dashboards](#grafana-dashboards)
- [Loki Log Aggregation](#loki-log-aggregation)
- [Vector Pipeline](#vector-pipeline)
- [cAdvisor Container Metrics](#cadvisor-container-metrics)
- [Alerting Setup](#alerting-setup)
- [Custom Dashboards](#custom-dashboards)
- [Related Pages](#related-pages)

## Overview

The observability stack provides comprehensive monitoring, logging, and visualization for all services.

**Components:**
- **Prometheus**: Metrics collection and alerting
- **Grafana**: Visualization and dashboards
- **Loki**: Log aggregation
- **Vector**: Unified observability pipeline
- **cAdvisor**: Container resource monitoring

## Prometheus Setup

**Access:** `http://localhost:9090`

**Configuration:** `configs/prometheus/prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'cadvisor'
    static_configs:
      - targets: ['cadvisor:8080']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-1:6379', 'redis-2:6379', 'redis-3:6379']

  - job_name: 'rabbitmq'
    static_configs:
      - targets: ['rabbitmq:15692']

  - job_name: 'fastapi'
    static_configs:
      - targets: ['reference-api:8000']
    metrics_path: /metrics
```

**Common Queries:**
```promql
# CPU usage
rate(container_cpu_usage_seconds_total[5m]) * 100

# Memory usage
container_memory_usage_bytes / 1024 / 1024

# Network I/O
rate(container_network_receive_bytes_total[5m])
```

## Grafana Dashboards

**Access:** `http://localhost:3001`
**Default credentials:** `admin/admin`

**Pre-configured dashboards:**
1. Container Overview
2. PostgreSQL Performance
3. Redis Cluster
4. RabbitMQ Metrics
5. Application Metrics

**Add data source:**
1. Configuration → Data Sources → Add data source
2. Select Prometheus
3. URL: `http://prometheus:9090`
4. Save & Test

## Loki Log Aggregation

**Access:** `http://localhost:3100`

**Configuration:** `configs/loki/loki.yml`

```yaml
auth_enabled: false

server:
  http_listen_port: 3100

ingester:
  lifecycler:
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
  chunk_idle_period: 5m
  chunk_retain_period: 30s

schema_config:
  configs:
    - from: 2024-01-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h

storage_config:
  boltdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/cache
  filesystem:
    directory: /loki/chunks

limits_config:
  retention_period: 720h  # 30 days
```

**Query logs in Grafana Explore:**
```logql
{container_name="dev-postgres"}
{container_name=~"dev-.*"} |= "ERROR"
rate({container_name="dev-postgres"}[5m])
```

## Vector Pipeline

**Configuration:** `configs/vector/vector.toml`

```toml
[sources.docker_logs]
type = "docker_logs"
include_containers = ["dev-*"]

[sinks.loki]
type = "loki"
inputs = ["docker_logs"]
endpoint = "http://loki:3100"
encoding.codec = "json"
labels.container_name = "{{ container_name }}"

[sinks.prometheus]
type = "prometheus_exporter"
inputs = ["docker_logs"]
address = "0.0.0.0:9598"
```

## cAdvisor Container Metrics

**Access:** `http://localhost:8080`

**Metrics exposed:**
- CPU usage per container
- Memory usage and limits
- Network I/O
- Disk I/O
- Filesystem usage

**Prometheus scrapes metrics automatically**

## Alerting Setup

**Create alert in Grafana:**
1. Dashboard → Panel → Alert tab
2. Define query and conditions
3. Configure notification channel
4. Set alert name and message

**Example alert rules:**
```yaml
# configs/prometheus/alerts.yml
groups:
  - name: service_alerts
    rules:
      - alert: HighMemoryUsage
        expr: (container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory on {{ $labels.name }}"

      - alert: ServiceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
```

## Custom Dashboards

**Import dashboard:**
1. Dashboards → Import
2. Upload JSON or enter dashboard ID
3. Select data source
4. Import

**Popular dashboards:**
- Docker Container & Host Metrics (ID: 10619)
- PostgreSQL Database (ID: 9628)
- Redis Dashboard (ID: 11835)

## Related Pages

- [Health-Monitoring](Health-Monitoring) - Health checks
- [Prometheus-Queries](Prometheus-Queries) - PromQL examples
- [Grafana-Dashboards](Grafana-Dashboards) - Dashboard guide
