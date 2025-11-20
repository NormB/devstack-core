# Colima Configuration

## Table of Contents

- [Overview](#overview)
- [VM Setup](#vm-setup)
- [CPU Memory Disk Allocation](#cpu-memory-disk-allocation)
- [Starting Colima](#starting-colima)
- [Stopping Colima](#stopping-colima)
- [Colima Profiles](#colima-profiles)
- [Troubleshooting](#troubleshooting)
- [Colima vs Docker Desktop](#colima-vs-docker-desktop)

## Overview

Colima provides Docker container runtime on macOS using Lima VM. It's a free, lightweight alternative to Docker Desktop.

## VM Setup

**Initial setup:**
```bash
# Install Colima
brew install colima

# Install Docker CLI
brew install docker docker-compose

# Start Colima (creates default profile)
colima start
```

## CPU Memory Disk Allocation

**Configure resources:**
```bash
# Standard development setup
colima start --cpu 4 --memory 8 --disk 50

# High-performance setup
colima start --cpu 8 --memory 16 --disk 100

# With optimizations for Apple Silicon
colima start \
  --cpu 8 \
  --memory 16 \
  --disk 100 \
  --vm-type vz \
  --vz-rosetta \
  --mount-type virtiofs \
  --network-address
```

**Resource recommendations:**

| Workload | CPU | Memory | Disk |
|----------|-----|--------|------|
| Light development | 2-4 | 4-6 GB | 30 GB |
| Standard (devstack-core) | 4-6 | 8-12 GB | 50 GB |
| Heavy workloads | 8+ | 16+ GB | 100+ GB |

## Starting Colima

**Start default profile:**
```bash
colima start
```

**Start with custom config:**
```bash
colima start \
  --cpu 6 \
  --memory 12 \
  --disk 80 \
  --vm-type vz \
  --vz-rosetta \
  --mount-type virtiofs
```

**Start named profile:**
```bash
colima start --profile dev
```

## Stopping Colima

**Stop Colima:**
```bash
colima stop

# Stop specific profile
colima stop --profile dev
```

**Delete Colima instance:**
```bash
colima delete

# Delete specific profile
colima delete --profile dev
```

## Colima Profiles

**Create multiple environments:**
```bash
# Development profile
colima start --profile dev --cpu 4 --memory 8

# Production-like profile
colima start --profile prod --cpu 8 --memory 16

# Switch between profiles
colima stop --profile dev
colima start --profile prod

# List profiles
colima list
```

## Troubleshooting

**Colima won't start:**
```bash
# Check status
colima status

# View logs
colima logs

# Reset Colima
colima delete
colima start
```

**Services can't access host:**
```bash
# Use host.docker.internal
curl http://host.docker.internal:8080
```

**Performance issues:**
```bash
# Increase resources
colima stop
colima start --cpu 8 --memory 16

# Use VZ + Rosetta (Apple Silicon)
colima start --vm-type vz --vz-rosetta
```

## Colima vs Docker Desktop

| Feature | Colima | Docker Desktop |
|---------|--------|----------------|
| **Cost** | Free, Open Source | Free for personal use, paid for enterprise |
| **Resource Usage** | Lightweight | Heavier |
| **Performance** | Comparable, faster with VZ | Good |
| **UI** | CLI only | GUI included |
| **Setup** | Manual | Automated |
| **Kubernetes** | Supported | Built-in |

**Advantages of Colima:**
- Free for commercial use
- Lighter weight
- Faster startup
- More control over VM configuration
- No licensing concerns

**Disadvantages:**
- No GUI
- More manual configuration
- Less polished user experience

## Related Pages

- [Performance-Tuning](Performance-Tuning) - VM optimization
- [Network-Issues](Network-Issues) - Networking troubleshooting
