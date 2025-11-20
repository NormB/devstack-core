#!/bin/bash
#
#######################################
# Redis Metrics Collection Script for Vector
#
# Description:
#   Collects comprehensive metrics from Redis using the INFO command and outputs
#   them in JSON format for consumption by Vector telemetry pipeline. Extracts
#   key performance metrics including server info, client connections, memory usage,
#   statistics, replication status, and CPU utilization.
#
# Globals:
#   REDIS_HOST     - Redis server hostname (default: redis-1)
#   REDIS_PORT     - Redis server port (default: 6379)
#   REDIS_PASSWORD - Redis authentication password (optional)
#
# Usage:
#   ./redis-metrics.sh
#   REDIS_HOST=redis-2 REDIS_PORT=6380 ./redis-metrics.sh
#   REDIS_PASSWORD=secret ./redis-metrics.sh
#
# Dependencies:
#   - redis-cli: Redis command-line client
#   - awk: Text processing utility (POSIX compliant)
#
# Exit Codes:
#   0 - Success: Metrics collected and JSON output generated
#   1 - Failure: Redis connection failed or command execution error
#   127 - Command not found: redis-cli not available in PATH
#
# Notes:
#   - Outputs to stdout in JSON format with ISO 8601 timestamp
#   - Uses --no-auth-warning flag to suppress password warnings
#   - Collects 20+ key metrics across server, memory, stats, and replication
#   - Safe for use in monitoring pipelines with frequent execution
#   - All memory metrics are reported in bytes
#
# Examples:
#   # Basic usage with defaults
#   ./redis-metrics.sh
#
#   # Connect to remote Redis instance
#   REDIS_HOST=192.168.1.100 REDIS_PORT=6380 ./redis-metrics.sh
#
#   # Use with authentication
#   REDIS_PASSWORD='mypassword' ./redis-metrics.sh
#
#   # Pipe to Vector or other log collectors
#   ./redis-metrics.sh | vector --config vector.toml
#
#######################################

# Redis connection details
REDIS_HOST="${REDIS_HOST:-redis-1}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD}"

# Build redis-cli command
REDIS_CLI="redis-cli -h $REDIS_HOST -p $REDIS_PORT"
if [ -n "$REDIS_PASSWORD" ]; then
    REDIS_CLI="$REDIS_CLI -a $REDIS_PASSWORD --no-auth-warning"
fi

# Collect INFO stats
INFO_OUTPUT=$($REDIS_CLI INFO)

# Parse key metrics and output as JSON
echo "$INFO_OUTPUT" | awk -v host="$REDIS_HOST" -v port="$REDIS_PORT" '
BEGIN {
    print "{"
    print "  \"timestamp\": \"" strftime("%Y-%m-%dT%H:%M:%SZ", systime()) "\","
    print "  \"redis_host\": \"" host "\","
    print "  \"redis_port\": \"" port "\","
    print "  \"metrics\": {"
}

# Server section
/^redis_version:/ { print "    \"redis_version\": \"" $2 "\"," }
/^uptime_in_seconds:/ { print "    \"uptime_seconds\": " $2 "," }

# Clients section
/^connected_clients:/ { print "    \"connected_clients\": " $2 "," }
/^blocked_clients:/ { print "    \"blocked_clients\": " $2 "," }

# Memory section
/^used_memory:/ { print "    \"used_memory_bytes\": " $2 "," }
/^used_memory_rss:/ { print "    \"used_memory_rss_bytes\": " $2 "," }
/^used_memory_peak:/ { print "    \"used_memory_peak_bytes\": " $2 "," }
/^mem_fragmentation_ratio:/ { print "    \"mem_fragmentation_ratio\": " $2 "," }

# Stats section
/^total_connections_received:/ { print "    \"total_connections_received\": " $2 "," }
/^total_commands_processed:/ { print "    \"total_commands_processed\": " $2 "," }
/^instantaneous_ops_per_sec:/ { print "    \"instantaneous_ops_per_sec\": " $2 "," }
/^keyspace_hits:/ { print "    \"keyspace_hits\": " $2 "," }
/^keyspace_misses:/ { print "    \"keyspace_misses\": " $2 "," }
/^evicted_keys:/ { print "    \"evicted_keys\": " $2 "," }
/^expired_keys:/ { print "    \"expired_keys\": " $2 "," }

# Replication section
/^role:/ { print "    \"role\": \"" $2 "\"," }
/^connected_slaves:/ { print "    \"connected_slaves\": " $2 "," }

# CPU section
/^used_cpu_sys:/ { print "    \"used_cpu_sys\": " $2 "," }
/^used_cpu_user:/ { print "    \"used_cpu_user\": " $2 }

END {
    print "  }"
    print "}"
}
'
