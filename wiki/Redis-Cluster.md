# Redis Cluster

## Table of Contents

- [Architecture](#architecture)
- [Cluster Setup](#cluster-setup)
- [Operations](#operations)
- [Troubleshooting](#troubleshooting)
- [REST API Cluster Inspection](#rest-api-cluster-inspection)

---

### Architecture

**3-Node Master Cluster:**
```
┌────────────────────────────────────────────┐
│         Redis Cluster (16384 slots)         │
├────────────────────────────────────────────┤
│                                            │
│  Node 1 (172.20.2.13:6379)                │
│  Master | Slots 0-5460 (5461 slots)       │
│  Ports: 6379 (non-TLS), 6390 (TLS)        │
│                                            │
│  Node 2 (172.20.2.16:6379)                │
│  Master | Slots 5461-10922 (5462 slots)   │
│  Ports: 6379 (non-TLS), 6390 (TLS)        │
│                                            │
│  Node 3 (172.20.2.17:6379)                │
│  Master | Slots 10923-16383 (5461 slots)  │
│  Ports: 6379 (non-TLS), 6390 (TLS)        │
│                                            │
└────────────────────────────────────────────┘
```

**Data Sharding:**
- Each key is hashed (CRC16) to a slot number (0-16383)
- Key `user:1000` → Hash → Slot 5139 → Node 1
- Automatic redistribution if nodes added/removed

**Why No Replicas?**
- Development environment doesn't need redundancy
- Saves resources (3 nodes vs 6 nodes)
- Production would have 3 masters + 3 replicas

### Cluster Setup

**Initialization Script** (`configs/redis/scripts/redis-cluster-init.sh`):

1. **Wait for Nodes:** Ensures all 3 Redis instances are ready
2. **Check Existing Cluster:** Skips if already initialized
3. **Create Cluster:** Uses `redis-cli --cluster create`
4. **Assign Slots:** Distributes 16384 slots across 3 masters
5. **Verify:** Checks cluster state is "ok"

**Manual Initialization:**
```bash
docker exec dev-redis-1 redis-cli --cluster create \
  172.20.2.13:6379 172.20.2.16:6379 172.20.2.17:6379 \
  --cluster-yes -a $REDIS_PASSWORD
```

### Operations

**Cluster Status:**
```bash
# Overall health
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster info

# Output:
# cluster_state:ok
# cluster_slots_assigned:16384
# cluster_known_nodes:3
```

**Node Information:**
```bash
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster nodes

# Shows:
# - Node IDs
# - IP addresses and ports
# - Master/replica status
# - Slot ranges
```

**Slot Distribution:**
```bash
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster slots

# Shows which node owns which slot range
```

**Data Operations:**
```bash
# Set key (automatically routed to correct node) - Non-TLS
redis-cli -c -a $REDIS_PASSWORD -p 6379 SET user:1000 "John Doe"

# Get key (automatic redirection with -c flag) - Non-TLS
redis-cli -c -a $REDIS_PASSWORD -p 6379 GET user:1000
# → Redirected to Node 1 (slot 5139)

# TLS-encrypted operations (requires certificates)
redis-cli -c -a $REDIS_PASSWORD -p 6390 \
  --tls --cert ~/.config/vault/certs/redis-1/redis.crt \
  --key ~/.config/vault/certs/redis-1/redis.key \
  --cacert ~/.config/vault/certs/redis-1/ca.crt \
  GET user:1000

# Without -c flag: returns MOVED error
redis-cli -a $REDIS_PASSWORD -p 6379 GET user:1000
# → (error) MOVED 5139 172.20.2.13:6379
```

**Find Key Location:**
```bash
# Which slot?
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster keyslot user:1000
# → 5139

# Which node owns slot 5139?
# Check cluster nodes output: Node 1 (slots 0-5460)
```

### Troubleshooting

**Cluster State Not OK:**
```bash
# Check individual node status
for i in 1 2 3; do
  echo "Node $i:"
  docker exec dev-redis-$i redis-cli -a $REDIS_PASSWORD ping
done

# Check cluster view from each node
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD cluster nodes
docker exec dev-redis-2 redis-cli -a $REDIS_PASSWORD cluster nodes
docker exec dev-redis-3 redis-cli -a $REDIS_PASSWORD cluster nodes

# All should show same cluster topology
```

**Slot Migration Issues:**
```bash
# Check for open slots
docker exec dev-redis-1 redis-cli --cluster check 172.20.2.13:6379 -a $REDIS_PASSWORD

# Should show: [OK] All 16384 slots covered
```

**Manually Re-initialize Cluster:**
```bash
# If cluster is broken and needs to be recreated
./configs/redis/scripts/redis-cluster-init.sh
```

**Performance Monitoring:**
```bash
# Real-time stats
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD --stat

# Slowlog
docker exec dev-redis-1 redis-cli -a $REDIS_PASSWORD slowlog get 10
```

### REST API Cluster Inspection

The FastAPI reference application provides comprehensive REST APIs for Redis cluster inspection. These endpoints offer an alternative to `docker exec` commands and can be integrated into monitoring dashboards or automation scripts.

**Available Endpoints:**

```bash
# Get all cluster nodes with slot assignments
curl http://localhost:8000/redis/cluster/nodes | jq '.'
# Returns: node IDs, roles, slot ranges, connection state

# Get slot distribution across cluster
curl http://localhost:8000/redis/cluster/slots | jq '.'
# Returns: slot ranges per master, total coverage, replica info

# Get cluster state and statistics
curl http://localhost:8000/redis/cluster/info | jq '.'
# Returns: cluster_state, slots assigned, message stats, epochs

# Get detailed info for specific node
curl http://localhost:8000/redis/nodes/redis-1/info | jq '.info.cluster*'
# Returns: full INFO output including cluster metrics
```

**Example: Check Cluster Health Programmatically**

```bash
# Quick health check
CLUSTER_STATE=$(curl -s http://localhost:8000/redis/cluster/info | jq -r '.cluster_info.cluster_state')
SLOTS_ASSIGNED=$(curl -s http://localhost:8000/redis/cluster/info | jq -r '.cluster_info.cluster_slots_assigned')

if [ "$CLUSTER_STATE" = "ok" ] && [ "$SLOTS_ASSIGNED" = "16384" ]; then
  echo "✅ Redis cluster is healthy"
else
  echo "❌ Redis cluster has issues"
fi
```

**Example: Monitor Slot Distribution**

```bash
# Get slot coverage percentage
curl -s http://localhost:8000/redis/cluster/slots | jq '{
  total_slots: .total_slots,
  coverage: .coverage_percentage,
  masters: [.slot_distribution[] | {
    node: .master.host,
    slots: .slots_count,
    range: "\(.start_slot)-\(.end_slot)"
  }]
}'
```

**Implementation Reference:**

See `reference-apps/fastapi/app/routers/redis_cluster.py` for:
- Parsing `CLUSTER NODES` command output
- Handling `CLUSTER SLOTS` binary response
- Connecting to individual cluster nodes
- Error handling for cluster operations

**HTTPS Access:**

When TLS is enabled (`REFERENCE_API_ENABLE_TLS=true`), all endpoints are available on both HTTP (8000) and HTTPS (8443):

```bash
# HTTPS access
curl https://localhost:8443/redis/cluster/nodes
curl https://localhost:8443/redis/cluster/info
```

