# Grafana Dashboards

## Table of Contents

- [Pre-configured Dashboards](#pre-configured-dashboards)
- [Creating Custom Dashboards](#creating-custom-dashboards)
- [Data Source Configuration](#data-source-configuration)
- [Alert Setup](#alert-setup)
- [Dashboard Sharing](#dashboard-sharing)
- [Panel Types](#panel-types)
- [Variables and Templating](#variables-and-templating)

## Pre-configured Dashboards

**Access:** `http://localhost:3001`
**Credentials:** `admin/admin`

**Available dashboards:**
1. **Container Overview**: Resource usage across all containers
2. **PostgreSQL Performance**: Database metrics, connections, query rates
3. **Redis Cluster**: Cluster health, memory usage, commands/sec
4. **RabbitMQ**: Queue depths, message rates, consumers
5. **Application Metrics**: Request rates, latencies, errors

## Creating Custom Dashboards

**Create new dashboard:**
1. Dashboards → New Dashboard
2. Add Panel → Add Query
3. Select data source: Prometheus
4. Enter PromQL query
5. Configure visualization
6. Save dashboard

**Example panel:**
```json
{
  "title": "CPU Usage",
  "targets": [{
    "expr": "rate(container_cpu_usage_seconds_total[5m]) * 100"
  }],
  "type": "graph"
}
```

## Data Source Configuration

**Add Prometheus:**
1. Configuration → Data Sources
2. Add data source → Prometheus
3. URL: `http://prometheus:9090`
4. Save & Test

**Add Loki:**
1. Add data source → Loki
2. URL: `http://loki:3100`
3. Save & Test

## Alert Setup

**Create alert:**
1. Edit panel → Alert tab
2. Create Alert
3. Conditions: WHEN avg() OF query() IS ABOVE 80
4. Evaluate every: 1m
5. For: 5m
6. Notification: Select channel
7. Save

**Notification channels:**
1. Alerting → Notification channels
2. Add channel
3. Type: Email, Slack, etc.
4. Configure settings

## Dashboard Sharing

**Export dashboard:**
1. Dashboard settings → JSON Model
2. Copy JSON
3. Save to file

**Import dashboard:**
1. Dashboards → Import
2. Upload JSON file or paste JSON
3. Select data source
4. Import

**Share snapshot:**
1. Share dashboard → Snapshot
2. Publish to snapshots.raintank.io
3. Share link

## Panel Types

**Graph:** Time series data
**Stat:** Single value
**Gauge:** Value with min/max
**Table:** Tabular data
**Heatmap:** Distribution over time
**Logs:** Log entries from Loki

**Example configurations:**
```yaml
# Graph panel
targets:
  - expr: rate(http_requests_total[5m])
    legendFormat: "{{ method }}"

# Stat panel
targets:
  - expr: up{job="postgres"}
options:
  colorMode: background
  graphMode: none

# Table panel
targets:
  - expr: container_memory_usage_bytes
    format: table
transform:
  - id: organize
    options:
      excludeByName:
        - instance
```

## Variables and Templating

**Create variable:**
1. Dashboard settings → Variables
2. Add variable
3. Name: `container`
4. Type: Query
5. Query: `label_values(container_name)`

**Use in query:**
```promql
container_memory_usage_bytes{name="$container"}
```

**Multi-select variable:**
```promql
container_memory_usage_bytes{name=~"$container"}
```

## Related Pages

- [Observability-Stack](Observability-Stack)
- [Prometheus-Queries](Prometheus-Queries)
- [Health-Monitoring](Health-Monitoring)
