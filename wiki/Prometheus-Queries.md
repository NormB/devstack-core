# Prometheus Queries

## Table of Contents

- [Container Metrics](#container-metrics)
- [Database Performance](#database-performance)
- [Redis Cluster Metrics](#redis-cluster-metrics)
- [HTTP Request Rates](#http-request-rates)
- [Resource Usage](#resource-usage)
- [Custom Metrics](#custom-metrics)

## Container Metrics

**CPU usage per container:**
```promql
rate(container_cpu_usage_seconds_total{name=~"dev-.*"}[5m]) * 100
```

**Memory usage (MB):**
```promql
container_memory_usage_bytes{name=~"dev-.*"} / 1024 / 1024
```

**Memory percentage:**
```promql
(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100
```

**Network I/O:**
```promql
rate(container_network_receive_bytes_total{name=~"dev-.*"}[5m])
rate(container_network_transmit_bytes_total{name=~"dev-.*"}[5m])
```

## Database Performance

**PostgreSQL connections:**
```promql
pg_stat_database_numbackends{datname="devdb"}
```

**PostgreSQL query rate:**
```promql
rate(pg_stat_database_xact_commit{datname="devdb"}[5m])
```

**Cache hit ratio:**
```promql
rate(pg_stat_database_blks_hit[5m]) /
(rate(pg_stat_database_blks_hit[5m]) + rate(pg_stat_database_blks_read[5m]))
```

## Redis Cluster Metrics

**Memory usage:**
```promql
redis_memory_used_bytes / 1024 / 1024
```

**Commands per second:**
```promql
rate(redis_commands_processed_total[1m])
```

**Cache hit rate:**
```promql
rate(redis_keyspace_hits_total[5m]) /
(rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]))
```

## HTTP Request Rates

**Requests per second:**
```promql
rate(http_requests_total[1m])
```

**Request latency (95th percentile):**
```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

**Error rate:**
```promql
rate(http_requests_total{status=~"5.."}[5m])
```

## Resource Usage

**Disk I/O:**
```promql
rate(container_fs_reads_bytes_total[5m])
rate(container_fs_writes_bytes_total[5m])
```

**Top CPU consumers:**
```promql
topk(5, rate(container_cpu_usage_seconds_total[5m]) * 100)
```

**Top memory consumers:**
```promql
topk(5, container_memory_usage_bytes / 1024 / 1024)
```

## Custom Metrics

**Application metrics:**
```promql
# Active connections
app_active_connections

# Request duration
rate(app_request_duration_seconds_sum[5m]) /
rate(app_request_duration_seconds_count[5m])

# Queue depth
rabbitmq_queue_messages{queue="tasks"}
```

## Related Pages

- [Observability-Stack](Observability-Stack)
- [Health-Monitoring](Health-Monitoring)
- [Grafana-Dashboards](Grafana-Dashboards)
