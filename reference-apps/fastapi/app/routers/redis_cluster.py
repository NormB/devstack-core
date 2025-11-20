"""
Redis Cluster Information API endpoints

Provides detailed information about Redis cluster configuration:
- Cluster nodes and their assigned slots
- Slot distribution
- Cluster topology
- Per-node detailed information
"""

from fastapi import APIRouter
import redis.asyncio as redis
import logging

from app.config import settings
from app.services.vault import vault_client

logger = logging.getLogger(__name__)
router = APIRouter()


@router.get("/cluster/nodes")
async def get_cluster_nodes():
    """
    Get detailed information about all Redis cluster nodes

    Returns information including:
    - Node ID
    - IP address and port
    - Flags (master/slave)
    - Master node ID (for replicas)
    - Ping/pong timestamps
    - Config epoch
    - Link state
    - Slots assigned to each node
    """
    try:
        # Fetch credentials from Vault
        creds = await vault_client.get_secret("redis-1")
        password = creds.get("password")

        # Connect to first node to get cluster info
        client = redis.Redis(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            password=password,
            decode_responses=True,
            socket_connect_timeout=5
        )

        # Get cluster nodes information
        cluster_nodes_raw = await client.execute_command("CLUSTER", "NODES")
        await client.close()

        # Parse CLUSTER NODES output
        nodes = []
        for line in cluster_nodes_raw.strip().split("\n"):
            if not line:
                continue

            parts = line.split()
            if len(parts) < 8:
                continue

            node_id = parts[0]
            address = parts[1]
            flags = parts[2]
            master_id = parts[3] if parts[3] != "-" else None
            ping_sent = parts[4]
            pong_recv = parts[5]
            config_epoch = parts[6]
            link_state = parts[7]

            # Parse slots (if any)
            slots = []
            slot_ranges = []
            for i in range(8, len(parts)):
                slot_info = parts[i]
                if "-" in slot_info and not slot_info.startswith("["):
                    # Slot range like "0-5460"
                    start, end = slot_info.split("-")
                    slot_ranges.append({"start": int(start), "end": int(end)})
                    slots.extend(range(int(start), int(end) + 1))
                elif slot_info.isdigit():
                    # Single slot
                    slots.append(int(slot_info))
                    slot_ranges.append({"start": int(slot_info), "end": int(slot_info)})

            # Parse address
            host_port = address.split("@")[0]  # Remove cluster bus port
            host, port = host_port.rsplit(":", 1)

            # Determine role
            role = "master" if "master" in flags else "replica" if "slave" in flags else "unknown"

            nodes.append({
                "node_id": node_id,
                "host": host,
                "port": int(port),
                "role": role,
                "flags": flags.split(","),
                "master_id": master_id,
                "ping_sent": ping_sent,
                "pong_recv": pong_recv,
                "config_epoch": int(config_epoch),
                "link_state": link_state,
                "slots_count": len(slots),
                "slot_ranges": slot_ranges
            })

        return {
            "status": "success",
            "total_nodes": len(nodes),
            "nodes": nodes
        }

    except Exception as e:
        logger.error(f"Failed to get cluster nodes: {e}")
        return {"status": "error", "error": "Failed to retrieve cluster nodes information"}


@router.get("/cluster/slots")
async def get_cluster_slots():
    """
    Get slot distribution across cluster nodes

    Returns:
    - Slot ranges assigned to each master
    - Total slots covered
    - Slot coverage percentage
    """
    try:
        # Fetch credentials from Vault
        creds = await vault_client.get_secret("redis-1")
        password = creds.get("password")

        # Connect to first node
        client = redis.Redis(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            password=password,
            decode_responses=False,  # CLUSTER SLOTS returns binary data
            socket_connect_timeout=5
        )

        # Get cluster slots information
        cluster_slots = await client.execute_command("CLUSTER", "SLOTS")
        await client.close()

        # Parse CLUSTER SLOTS output
        slot_distribution = []
        total_slots = 0

        for slot_info in cluster_slots:
            start_slot = slot_info[0]
            end_slot = slot_info[1]
            master_info = slot_info[2]

            # Master node info
            master_host = master_info[0].decode() if isinstance(master_info[0], bytes) else master_info[0]
            master_port = master_info[1]
            master_id = master_info[2].decode() if isinstance(master_info[2], bytes) else master_info[2]

            # Replica info (if any)
            replicas = []
            for i in range(3, len(slot_info)):
                replica_info = slot_info[i]
                replica_host = replica_info[0].decode() if isinstance(replica_info[0], bytes) else replica_info[0]
                replica_port = replica_info[1]
                replica_id = replica_info[2].decode() if isinstance(replica_info[2], bytes) else replica_info[2]
                replicas.append({
                    "host": replica_host,
                    "port": replica_port,
                    "node_id": replica_id
                })

            slots_in_range = end_slot - start_slot + 1
            total_slots += slots_in_range

            slot_distribution.append({
                "start_slot": start_slot,
                "end_slot": end_slot,
                "slots_count": slots_in_range,
                "master": {
                    "host": master_host,
                    "port": master_port,
                    "node_id": master_id
                },
                "replicas": replicas
            })

        return {
            "status": "success",
            "total_slots": total_slots,
            "max_slots": 16384,
            "coverage_percentage": round((total_slots / 16384) * 100, 2),
            "slot_distribution": slot_distribution
        }

    except Exception as e:
        logger.error(f"Failed to get cluster slots: {e}")
        return {"status": "error", "error": "Failed to retrieve cluster slot distribution"}


@router.get("/cluster/info")
async def get_cluster_info():
    """
    Get detailed Redis cluster information

    Returns comprehensive cluster state including:
    - Cluster state (ok/fail)
    - Slots assigned/ok/fail
    - Known nodes
    - Cluster size
    - Epoch information
    - Stats
    """
    try:
        # Fetch credentials from Vault
        creds = await vault_client.get_secret("redis-1")
        password = creds.get("password")

        # Connect to first node
        client = redis.Redis(
            host=settings.REDIS_HOST,
            port=settings.REDIS_PORT,
            password=password,
            decode_responses=True,
            socket_connect_timeout=5
        )

        # Get cluster info
        cluster_info_raw = await client.execute_command("CLUSTER", "INFO")
        await client.close()

        # Parse cluster info
        cluster_info = {}
        for line in cluster_info_raw.split("\n"):
            if ":" in line:
                key, value = line.strip().split(":", 1)
                # Try to convert to int if possible
                try:
                    cluster_info[key] = int(value)
                except ValueError:
                    cluster_info[key] = value

        return {
            "status": "success",
            "cluster_info": cluster_info
        }

    except Exception as e:
        logger.error(f"Failed to get cluster info: {e}")
        return {"status": "error", "error": "Failed to retrieve cluster information"}


@router.get("/nodes/{node_name}/info")
async def get_node_info(node_name: str):
    """
    Get detailed information about a specific Redis node

    Args:
        node_name: Name of the node (redis-1, redis-2, redis-3)

    Returns detailed server information for the specified node
    """
    try:
        # Validate node name
        valid_nodes = ["redis-1", "redis-2", "redis-3"]
        if node_name not in valid_nodes:
            return {
                "status": "error",
                "error": f"Invalid node name. Must be one of: {', '.join(valid_nodes)}"
            }

        # Fetch credentials from Vault
        creds = await vault_client.get_secret("redis-1")
        password = creds.get("password")

        # Connect to the specific node
        client = redis.Redis(
            host=node_name,
            port=6379,
            password=password,
            decode_responses=True,
            socket_connect_timeout=5
        )

        # Get comprehensive server info
        info = await client.info("all")
        await client.close()

        return {
            "status": "success",
            "node": node_name,
            "info": info
        }

    except Exception as e:
        # Log error without user-controlled input to prevent log injection
        logger.error(f"Failed to get Redis node info: {e}")
        return {"status": "error", "error": "Failed to retrieve node information"}
