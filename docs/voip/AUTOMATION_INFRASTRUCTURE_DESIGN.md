# Automation Infrastructure Design: libvirt + Configuration Management

## Executive Summary

**Decision:** Use libvirt for VoIP VM automation with better tooling integration.

**Key Questions to Address:**
1. Where should the automation/orchestration environment run?
2. Which configuration management tool: Ansible vs Puppet vs Chef?
3. How to reduce container count in DevStack Core?
4. Overall architecture optimization

---

## Table of Contents

1. [Automation Environment Location](#automation-environment-location)
2. [Configuration Management Tool Comparison](#configuration-management-tool-comparison)
3. [Container Reduction Strategy](#container-reduction-strategy)
4. [Recommended Architecture](#recommended-architecture)
5. [Implementation Guide](#implementation-guide)
6. [Migration Plan](#migration-plan)

---

## Automation Environment Location

### Options Analysis

#### Option 1: Another Colima VM (automation-control)

```
macOS Host
├── Colima VM (devstack-core) - 28 containers
│   └── Development infrastructure
│
├── Colima VM (automation-control) ← NEW
│   ├── Ansible / Terraform
│   ├── Configuration management
│   └── libvirt client tools
│
└── libvirt VMs (managed by automation-control)
    ├── VoIP Production VM 1
    ├── VoIP Production VM 2
    └── VoIP Production VM N
```

**Pros:**
- ✅ Clean separation of concerns
- ✅ Isolated from DevStack Core
- ✅ Can restart automation environment without affecting VoIP
- ✅ Uses Colima's fast VZ hypervisor
- ✅ Easy to snapshot/backup
- ✅ Docker available for containerized automation tools

**Cons:**
- ❌ Another VM to manage (resource overhead)
- ❌ Colima VM to libvirt VM communication complexity
- ❌ Network configuration between VMs
- ❌ Additional 2-4GB RAM for automation VM

**Resource Cost:**
- CPU: 2 cores
- RAM: 4GB
- Disk: 20GB
- Total overhead: ~6GB RAM, 2 CPUs

---

#### Option 2: Run Directly on macOS Host

```
macOS Host
├── Ansible/Terraform (native macOS install)
│   ├── brew install ansible terraform
│   ├── virsh (libvirt client)
│   └── Configuration repo
│
├── Colima VM (devstack-core)
│   └── Development infrastructure
│
└── libvirt VMs (managed from macOS)
    ├── VoIP Production VM 1
    └── VoIP Production VM 2
```

**Pros:**
- ✅ No additional VM overhead
- ✅ Fast (no VM layer for automation)
- ✅ Direct access to macOS filesystem
- ✅ Simple network topology
- ✅ Easy to use macOS GUI tools
- ✅ Zero additional resource cost

**Cons:**
- ⚠️ Mixes host environment with automation
- ⚠️ macOS Python environment management
- ⚠️ Ansible version conflicts possible
- ⚠️ Less isolation

**Resource Cost:**
- CPU: 0 (native)
- RAM: ~500MB (Ansible/Terraform processes)
- Disk: 1-2GB (tools + dependencies)

---

#### Option 3: Inside Existing DevStack Core VM

```
macOS Host
├── Colima VM (devstack-core)
│   ├── Docker containers (28 services)
│   ├── Ansible/Terraform (installed in VM) ← ADD
│   └── libvirt client tools ← ADD
│
└── libvirt VMs (managed from Colima)
    ├── VoIP Production VM 1
    └── VoIP Production VM 2
```

**Pros:**
- ✅ No additional VM
- ✅ Centralized in development environment
- ✅ Easy access to DevStack databases/services
- ✅ Can use Prometheus/Grafana from DevStack

**Cons:**
- ❌ Mixes development and automation concerns
- ❌ Colima VM restarts affect automation
- ❌ Resource contention with containers
- ❌ VZ VM to libvirt VM communication complexity

**Resource Cost:**
- CPU: 0 (shared with DevStack)
- RAM: +1GB (Ansible/Terraform)
- Disk: 2GB

---

#### Option 4: Hybrid - Automation Git Repo on macOS, Execution from Dedicated VM

```
macOS Host
├── ~/automation/ ← Git repository
│   ├── ansible/
│   ├── terraform/
│   └── scripts/
│
├── Colima VM (devstack-core)
│   └── Development infrastructure
│
├── Colima VM (automation-control)
│   ├── Mount ~/automation/ via virtiofs
│   ├── Execute Ansible/Terraform playbooks
│   └── Manage libvirt VMs
│
└── libvirt VMs
    └── VoIP Production VMs
```

**Pros:**
- ✅ Best of both worlds
- ✅ Edit on macOS (GUI editors, VS Code)
- ✅ Execute in isolated VM (clean environment)
- ✅ Version control on host (easy Git operations)
- ✅ VM isolation for execution

**Cons:**
- ⚠️ Complexity of file sharing
- ⚠️ Additional VM overhead

---

### 🎯 **RECOMMENDED: Option 2 - Run Directly on macOS Host**

**Rationale:**

1. **Zero Resource Overhead**
   - No additional VM needed
   - No CPU/RAM waste
   - Simplest architecture

2. **Best Developer Experience**
   - Edit automation code in macOS GUI editors
   - Fast iteration (no VM layer)
   - Direct filesystem access
   - Easy Git operations

3. **macOS Has Excellent Tools**
   - Homebrew: `brew install ansible terraform`
   - libvirt client: `brew install libvirt`
   - Python via Homebrew or pyenv
   - Visual Studio Code / IntelliJ for editing

4. **Simple Network Topology**
   ```
   macOS (localhost)
     ↓ libvirt client
   libvirtd (qemu:///system)
     ↓ manages
   VoIP VMs (via libvirt)
   ```

5. **Precedent: This is Common Practice**
   - AWS CLI runs on macOS, manages EC2 instances
   - kubectl runs on macOS, manages Kubernetes clusters
   - terraform runs on macOS, manages infrastructure
   - **Automation tools are designed to run on control hosts**

---

## Configuration Management Tool Comparison

### Ansible vs Puppet vs Chef

#### Ansible (RECOMMENDED ✅)

**Architecture:**
- Agentless (SSH-based)
- Push model
- YAML playbooks
- Python-based

**Pros:**
- ✅ No agents on target VMs (just SSH)
- ✅ Simple installation: `brew install ansible`
- ✅ Easy to learn (YAML, Jinja2 templates)
- ✅ Excellent documentation
- ✅ Large community (100k+ modules on Galaxy)
- ✅ Perfect for libvirt automation
- ✅ Idempotent by design
- ✅ Can manage VMs AND configure services

**Cons:**
- ⚠️ SSH overhead for large deployments (not a concern for 2-10 VMs)
- ⚠️ Serial execution by default (can parallelize)

**Use Cases:**
- ✅ Create libvirt VMs
- ✅ Install VoIP software from source
- ✅ Configure OpenSIPS/Asterisk/RTPEngine
- ✅ Deploy updates
- ✅ Orchestrate complex workflows

**Example Ansible Structure:**
```
~/automation/
├── ansible.cfg
├── inventory/
│   ├── production
│   └── staging
├── playbooks/
│   ├── create-voip-vm.yml
│   ├── install-opensips.yml
│   ├── install-asterisk.yml
│   ├── install-rtpengine.yml
│   └── deploy-voip-stack.yml
├── roles/
│   ├── libvirt-vm/
│   ├── opensips/
│   ├── asterisk/
│   └── rtpengine/
└── group_vars/
    └── voip_servers.yml
```

**Installation:**
```bash
brew install ansible
ansible --version  # Verify installation
```

**Sample Playbook:**
```yaml
# playbooks/create-voip-vm.yml
---
- name: Create VoIP Production VM
  hosts: localhost
  connection: local

  tasks:
    - name: Create libvirt VM
      community.libvirt.virt:
        command: define
        xml: "{{ lookup('template', 'vm-template.xml.j2') }}"

    - name: Start VM
      community.libvirt.virt:
        name: voip-production-1
        state: running

    - name: Wait for SSH
      wait_for:
        host: "{{ vm_ip }}"
        port: 22
        timeout: 300

- name: Configure VoIP Software
  hosts: voip_production_1
  become: yes

  roles:
    - opensips
    - asterisk
    - rtpengine
```

---

#### Puppet

**Architecture:**
- Agent-based
- Pull model
- Puppet DSL (Ruby-based)
- Master-agent architecture

**Pros:**
- ✅ Mature (since 2005)
- ✅ Strong enterprise adoption
- ✅ Good for large-scale deployments (1000+ nodes)
- ✅ Built-in reporting

**Cons:**
- ❌ Requires agent on every VM
- ❌ Requires Puppet master server
- ❌ Steeper learning curve (Puppet DSL)
- ❌ More complex setup
- ❌ Overkill for small VoIP deployments
- ❌ Higher resource overhead

**When to Use:**
- Large enterprise with 100+ VoIP servers
- Already using Puppet for other infrastructure
- Need compliance reporting

**Verdict for Your Use Case:** ❌ **Overkill**

---

#### Chef

**Architecture:**
- Agent-based
- Pull model
- Ruby DSL (recipes/cookbooks)
- Chef server required

**Pros:**
- ✅ Very powerful (full Ruby)
- ✅ Good for complex orchestration
- ✅ Strong enterprise adoption

**Cons:**
- ❌ Requires agent (chef-client) on every VM
- ❌ Requires Chef server
- ❌ Ruby knowledge required
- ❌ Steeper learning curve
- ❌ More overhead than Ansible
- ❌ Overkill for VoIP use case

**When to Use:**
- Already using Chef for infrastructure
- Need Ruby's full programming power
- Large-scale deployment (100+ servers)

**Verdict for Your Use Case:** ❌ **Overkill**

---

### 🎯 **RECOMMENDED: Ansible**

**Why Ansible Wins:**

| Factor | Ansible | Puppet | Chef |
|--------|---------|--------|------|
| **Learning Curve** | ✅ Easy (YAML) | ⚠️ Medium (DSL) | ❌ Hard (Ruby) |
| **Setup Time** | ✅ 5 minutes | ⚠️ Hours | ⚠️ Hours |
| **Agent Required** | ✅ No (SSH only) | ❌ Yes | ❌ Yes |
| **Server Required** | ✅ No | ❌ Yes (Puppet master) | ❌ Yes (Chef server) |
| **Overhead** | ✅ Minimal | ⚠️ Medium | ⚠️ Medium |
| **libvirt Support** | ✅ Excellent | ⚠️ Via exec | ⚠️ Via exec |
| **Community** | ✅ Huge | ✅ Large | ⚠️ Medium |
| **macOS Support** | ✅ Native | ⚠️ Limited | ⚠️ Limited |

**For 1-10 VoIP VMs:** Ansible is perfect.
**For 100+ VoIP VMs:** Consider Puppet/Chef, but Ansible still works.

---

## Container Reduction Strategy

### Current State: 28 Containers in DevStack Core

```bash
# Current containers (from docker-compose.yml analysis)
docker ps --format "table {{.Names}}\t{{.Image}}"

CONTAINER NAME              IMAGE
dev-vault                   hashicorp/vault:latest
dev-postgres                postgres:18
dev-pgbouncer               edoburu/pgbouncer:latest
dev-mysql                   mysql:8.0
dev-mongodb                 mongo:7
dev-redis-1                 redis:7-alpine
dev-redis-2                 redis:7-alpine
dev-redis-3                 redis:7-alpine
dev-redis-exporter-1        oliver006/redis_exporter:latest
dev-redis-exporter-2        oliver006/redis_exporter:latest
dev-redis-exporter-3        oliver006/redis_exporter:latest
dev-rabbitmq                rabbitmq:3-management
dev-forgejo                 codeberg.org/forgejo/forgejo:latest
dev-reference-api           (FastAPI - Python code-first)
dev-api-first               (FastAPI - Python API-first)
dev-golang-api              (Golang API)
dev-nodejs-api              (Node.js API)
dev-rust-api                (Rust API - partial)
dev-prometheus              prom/prometheus:latest
dev-grafana                 grafana/grafana:latest
dev-loki                    grafana/loki:latest
dev-vector                  timberio/vector:latest
dev-cadvisor                gcr.io/cadvisor/cadvisor:latest
dev-typescript-api          (TypeScript - future)
```

**Total: 28 containers**
**Resource Usage:**
- CPU: ~2-3 cores at idle, ~4-6 under load
- RAM: ~6-8GB total
- Disk: ~15GB (volumes)

---

### Reduction Strategy

#### Category 1: Core Infrastructure (KEEP - 9 containers)

**Essential for Development:**
```
✅ dev-vault             (Secrets management - CRITICAL)
✅ dev-postgres          (Primary database - CRITICAL)
✅ dev-mysql             (Multi-DB support)
✅ dev-mongodb           (NoSQL database)
✅ dev-redis-1           (Cache - at least 1 node needed)
✅ dev-rabbitmq          (Message queue)
✅ dev-forgejo           (Git server - CRITICAL)
✅ dev-prometheus        (Metrics - CRITICAL for monitoring VoIP)
✅ dev-grafana           (Dashboards - CRITICAL for VoIP monitoring)
```

**Rationale:**
- Vault: Secrets for all environments
- PostgreSQL: Primary DB for Forgejo + development
- MySQL/MongoDB: Multi-database development support
- Redis: Caching (1 node sufficient for dev)
- RabbitMQ: Async messaging patterns
- Forgejo: Version control for VoIP configs
- Prometheus/Grafana: Monitor VoIP VMs

---

#### Category 2: Observability (REDUCE - 8 → 2 containers)

**Current:**
```
dev-loki                  (Log aggregation)
dev-vector                (Log pipeline)
dev-cadvisor              (Container metrics)
dev-redis-exporter-1      (Redis metrics)
dev-redis-exporter-2      (Redis metrics)
dev-redis-exporter-3      (Redis metrics)
```

**Reduction Plan:**

**Option A: Keep Minimal Observability**
```
✅ dev-loki               (Aggregate VoIP VM logs)
❌ dev-vector             (REMOVE - Prometheus can scrape directly)
❌ dev-cadvisor           (REMOVE - not critical for VoIP monitoring)
❌ dev-redis-exporter-*   (REMOVE - only need 1 if using Redis cluster)
```

**Option B: Remove All Observability (Aggressive)**
```
❌ dev-loki               (REMOVE - use VM-native logging)
❌ dev-vector             (REMOVE)
❌ dev-cadvisor           (REMOVE)
❌ dev-redis-exporter-*   (REMOVE)
```

**Recommendation:** Option A (Keep Loki for VoIP log aggregation)
- Savings: 6 containers, ~1.5GB RAM

---

#### Category 3: Redis Cluster (REDUCE - 3 → 1 container)

**Current:**
```
dev-redis-1               (Cluster node 1)
dev-redis-2               (Cluster node 2)
dev-redis-3               (Cluster node 3)
```

**For Development:**
```
✅ dev-redis              (Single standalone instance)
❌ dev-redis-2            (REMOVE - cluster not needed for dev)
❌ dev-redis-3            (REMOVE - cluster not needed for dev)
```

**Rationale:**
- 3-node cluster is for production HA
- Single Redis instance sufficient for dev/testing
- VoIP VMs will have their own Redis if needed

**Savings:** 2 containers, ~400MB RAM

---

#### Category 4: Reference APIs (REDUCE - 5 → 1 container)

**Current:**
```
dev-reference-api         (FastAPI code-first)
dev-api-first             (FastAPI API-first)
dev-golang-api            (Golang)
dev-nodejs-api            (Node.js)
dev-rust-api              (Rust - partial)
```

**Problem:** These are for **API development education**, not VoIP.

**Reduction Plan:**

**Option A: Keep One for Testing**
```
✅ dev-reference-api      (FastAPI - most complete, 254 tests)
❌ dev-api-first          (REMOVE - redundant)
❌ dev-golang-api         (REMOVE - not using)
❌ dev-nodejs-api         (REMOVE - not using)
❌ dev-rust-api           (REMOVE - incomplete anyway)
```

**Option B: Remove All (Aggressive)**
```
❌ dev-reference-api      (REMOVE - not needed for VoIP)
❌ dev-api-first          (REMOVE)
❌ dev-golang-api         (REMOVE)
❌ dev-nodejs-api         (REMOVE)
❌ dev-rust-api           (REMOVE)
```

**Recommendation:** Option B (Remove all reference APIs)
- These were for learning Docker/API development
- Not needed for VoIP automation focus
- Can always restart if needed

**Savings:** 5 containers, ~2GB RAM

---

#### Category 5: Database Proxies (CONDITIONAL - 1 container)

**Current:**
```
dev-pgbouncer             (PostgreSQL connection pooler)
```

**Analysis:**
- PgBouncer is for connection pooling
- Useful for high-connection scenarios
- Forgejo + Dev = low connection count

**Options:**
```
⚠️ dev-pgbouncer          (REMOVE if not using connection pooling)
```

**Recommendation:** Remove unless you specifically need connection pooling

**Savings:** 1 container, ~50MB RAM

---

### Summary: Container Reduction

| Category | Current | Minimal | Savings |
|----------|---------|---------|---------|
| **Core Infrastructure** | 9 | 9 | 0 |
| **Observability** | 8 | 2 | 6 containers, ~1.5GB RAM |
| **Redis Cluster** | 3 | 1 | 2 containers, ~400MB RAM |
| **Reference APIs** | 5 | 0 | 5 containers, ~2GB RAM |
| **Database Proxies** | 1 | 0 | 1 container, ~50MB RAM |
| **VoIP** | 0 | 0 | 0 (will be in libvirt VMs) |
| **TOTAL** | 28 | 12 | **16 containers, ~4GB RAM** |

---

### Reduced docker-compose.yml

```yaml
# docker-compose-minimal.yml
version: '3.8'

services:
  # Core Infrastructure (9 services)
  vault:
    image: hashicorp/vault:latest
    # ... (keep existing config)

  postgres:
    image: postgres:18
    # ... (keep existing config)

  mysql:
    image: mysql:8.0
    # ... (keep existing config)

  mongodb:
    image: mongo:7
    # ... (keep existing config)

  redis:
    image: redis:7-alpine
    # Single instance, not cluster
    ports:
      - "6379:6379"
    command: redis-server --requirepass ${REDIS_PASSWORD}

  rabbitmq:
    image: rabbitmq:3-management
    # ... (keep existing config)

  forgejo:
    image: codeberg.org/forgejo/forgejo:latest
    # ... (keep existing config)

  prometheus:
    image: prom/prometheus:latest
    # ... (keep existing config)
    # Scrape VoIP VMs via libvirt network

  grafana:
    image: grafana/grafana:latest
    # ... (keep existing config)

  # Minimal Observability (2 services)
  loki:
    image: grafana/loki:latest
    # ... (keep existing config)
    # Aggregate logs from VoIP VMs

  redis-exporter:
    image: oliver006/redis_exporter:latest
    # Single exporter for single Redis instance
    environment:
      REDIS_ADDR: redis:6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}

  # Remove:
  # - pgbouncer (not needed for low connection count)
  # - redis-2, redis-3 (cluster not needed for dev)
  # - redis-exporter-2, redis-exporter-3 (only 1 Redis now)
  # - vector (Prometheus can scrape directly)
  # - cadvisor (not critical)
  # - All reference APIs (not needed for VoIP focus)
```

**Result:** 12 containers (from 28)

---

## Recommended Architecture

### Overall System Design

```
┌──────────────────────────────────────────────────────────────────┐
│ macOS Host (Apple Silicon)                                       │
│                                                                   │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ Native macOS Environment                                     │ │
│ │ ┌────────────────────────────────────────────────────────┐   │ │
│ │ │ Automation Tools (native)                              │   │ │
│ │ │ - Ansible (brew install ansible)                       │   │ │
│ │ │ - Terraform (brew install terraform)                   │   │ │
│ │ │ - libvirt client (brew install libvirt)                │   │ │
│ │ │ - Git repositories: ~/automation/                      │   │ │
│ │ │ - VS Code / IntelliJ for editing                       │   │ │
│ │ └────────────────────────────────────────────────────────┘   │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                   │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ Colima VM (devstack-core) - REDUCED                          │ │
│ │ ┌────────────────────────────────────────────────────────┐   │ │
│ │ │ 12 Containers (reduced from 28):                       │   │ │
│ │ │                                                         │   │ │
│ │ │ Core Infrastructure (9):                               │   │ │
│ │ │ - Vault, PostgreSQL, MySQL, MongoDB                    │   │ │
│ │ │ - Redis (1 instance), RabbitMQ                         │   │ │
│ │ │ - Forgejo, Prometheus, Grafana                         │   │ │
│ │ │                                                         │   │ │
│ │ │ Minimal Observability (2):                             │   │ │
│ │ │ - Loki (log aggregation for VoIP VMs)                  │   │ │
│ │ │ - Redis Exporter (1 instance)                          │   │ │
│ │ │                                                         │   │ │
│ │ │ Removed (16):                                          │   │ │
│ │ │ - Reference APIs (5)                                   │   │ │
│ │ │ - Redis cluster nodes (2)                              │   │ │
│ │ │ - Redis exporters (2)                                  │   │ │
│ │ │ - Vector, cAdvisor (2)                                 │   │ │
│ │ │ - PgBouncer (1)                                        │   │ │
│ │ └────────────────────────────────────────────────────────┘   │ │
│ │ Resources: 4 CPU, 4GB RAM (reduced from 8GB), 60GB disk     │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                   │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ libvirt VMs (managed by Ansible from macOS)                  │ │
│ │                                                               │ │
│ │ ┌──────────────────────────────────────────────────────┐     │ │
│ │ │ VoIP Production VM 1                                 │     │ │
│ │ │ - OpenSIPS (compiled from source)                    │     │ │
│ │ │ - Asterisk (compiled from source)                    │     │ │
│ │ │ - RTPEngine (with kernel module)                     │     │ │
│ │ │ - PostgreSQL (VoIP database)                         │     │ │
│ │ │ - node_exporter (Prometheus metrics)                 │     │ │
│ │ │ - promtail (ship logs to Loki)                       │     │ │
│ │ │ Resources: 4 CPU, 8GB RAM, 100GB disk               │     │ │
│ │ └──────────────────────────────────────────────────────┘     │ │
│ │                                                               │ │
│ │ ┌──────────────────────────────────────────────────────┐     │ │
│ │ │ VoIP Production VM 2 (optional, for HA)              │     │ │
│ │ │ - Same as VM 1                                       │     │ │
│ │ │ Resources: 4 CPU, 8GB RAM, 100GB disk               │     │ │
│ │ └──────────────────────────────────────────────────────┘     │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                   │
│ Total Resources:                                                 │
│ - macOS automation: ~500MB RAM                                  │
│ - Colima VM: 4 CPU, 4GB RAM (reduced from 8GB)                 │
│ - libvirt VM 1: 4 CPU, 8GB RAM                                 │
│ - libvirt VM 2: 4 CPU, 8GB RAM (optional)                      │
│ - Total: 12 CPU, 20.5GB RAM (vs 28GB before optimization)      │
└──────────────────────────────────────────────────────────────────┘
```

---

## Implementation Guide

### Phase 1: Set Up Automation Environment on macOS

```bash
#!/bin/bash
# setup-automation-environment.sh

set -euo pipefail

echo "=== Setting up Automation Environment on macOS ==="

# Install Homebrew packages
echo "Installing Homebrew packages..."
brew install ansible terraform libvirt qemu

# Verify installations
ansible --version
terraform --version
virsh --version

# Create automation directory structure
echo "Creating automation directory structure..."
mkdir -p ~/automation/{ansible,terraform,scripts,docs}

# Ansible structure
mkdir -p ~/automation/ansible/{playbooks,roles,inventory,group_vars,host_vars}

# Terraform structure
mkdir -p ~/automation/terraform/{modules,environments/{dev,staging,prod}}

# Initialize Git repository
cd ~/automation
git init
cat > .gitignore <<'EOF'
*.retry
.terraform/
*.tfstate
*.tfstate.backup
.vagrant/
*.log
secrets/
EOF

# Create ansible.cfg
cat > ~/automation/ansible/ansible.cfg <<'EOF'
[defaults]
inventory = ./inventory
roles_path = ./roles
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600

[ssh_connection]
pipelining = True
EOF

# Install Ansible collections
echo "Installing Ansible collections..."
ansible-galaxy collection install community.libvirt
ansible-galaxy collection install ansible.posix

# Create sample inventory
cat > ~/automation/ansible/inventory/production <<'EOF'
[voip_servers]
voip-prod-1 ansible_host=192.168.122.10
voip-prod-2 ansible_host=192.168.122.11

[voip_servers:vars]
ansible_user=admin
ansible_become=yes
ansible_python_interpreter=/usr/bin/python3
EOF

echo "✅ Automation environment setup complete!"
echo ""
echo "Directory structure:"
tree -L 2 ~/automation
echo ""
echo "Next steps:"
echo "1. Create Ansible playbooks in ~/automation/ansible/playbooks/"
echo "2. Create Terraform configs in ~/automation/terraform/"
echo "3. Start libvirtd: brew services start libvirt"
```

---

### Phase 2: Reduce DevStack Core Containers

```bash
#!/bin/bash
# reduce-containers.sh

set -euo pipefail

cd ~/devstack-core

echo "=== Reducing DevStack Core Containers ==="

# Backup current docker-compose.yml
cp docker-compose.yml docker-compose.yml.backup.$(date +%Y%m%d)

# Stop all containers
echo "Stopping all containers..."
docker compose down

# Create minimal docker-compose.yml
cat > docker-compose-minimal.yml <<'EOF'
version: '3.8'

# MINIMAL DEVSTACK CORE - 12 containers
# Optimized for VoIP automation focus

services:
  # Core Infrastructure (9 services)
  vault:
    # ... (copy from original)

  postgres:
    # ... (copy from original)

  mysql:
    # ... (copy from original)

  mongodb:
    # ... (copy from original)

  redis:
    image: redis:7-alpine
    container_name: dev-redis
    ports:
      - "6379:6379"
    command: redis-server --requirepass ${REDIS_PASSWORD}
    networks:
      dev-services:
        ipv4_address: 172.20.0.13

  rabbitmq:
    # ... (copy from original)

  forgejo:
    # ... (copy from original)

  prometheus:
    # ... (copy from original)
    # Add scrape configs for VoIP VMs

  grafana:
    # ... (copy from original)

  # Minimal Observability (2 services)
  loki:
    # ... (copy from original)

  redis-exporter:
    image: oliver006/redis_exporter:latest
    container_name: dev-redis-exporter
    environment:
      REDIS_ADDR: redis:6379
      REDIS_PASSWORD: ${REDIS_PASSWORD}
    networks:
      - dev-services

networks:
  dev-services:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16

volumes:
  # ... (keep all volumes)
EOF

# Use minimal compose file
ln -sf docker-compose-minimal.yml docker-compose.yml

# Start reduced environment
echo "Starting reduced environment (12 containers)..."
./devstack.sh start

echo "✅ Container reduction complete!"
echo ""
docker compose ps
echo ""
echo "Containers reduced from 28 to 12"
echo "RAM savings: ~4GB"
echo "CPU savings: ~2 cores"
```

---

### Phase 3: Create Ansible Playbooks for VoIP VMs

```bash
#!/bin/bash
# create-ansible-playbooks.sh

cd ~/automation/ansible/playbooks

# Main playbook for complete VoIP stack deployment
cat > deploy-voip-stack.yml <<'EOF'
---
# playbooks/deploy-voip-stack.yml
# Complete VoIP stack deployment

- name: Create libvirt VMs for VoIP
  hosts: localhost
  connection: local
  gather_facts: no

  vars:
    vms:
      - name: voip-prod-1
        cpus: 4
        memory: 8192
        disk: 100
        ip: 192.168.122.10
      - name: voip-prod-2
        cpus: 4
        memory: 8192
        disk: 100
        ip: 192.168.122.11

  tasks:
    - name: Create libvirt VMs
      include_role:
        name: libvirt-vm
      vars:
        vm_name: "{{ item.name }}"
        vm_cpus: "{{ item.cpus }}"
        vm_memory: "{{ item.memory }}"
        vm_disk: "{{ item.disk }}"
        vm_ip: "{{ item.ip }}"
      loop: "{{ vms }}"

    - name: Wait for VMs to be accessible via SSH
      wait_for:
        host: "{{ item.ip }}"
        port: 22
        timeout: 300
      loop: "{{ vms }}"

- name: Configure VoIP Software
  hosts: voip_servers
  become: yes

  roles:
    - common
    - kernel-tuning
    - opensips
    - asterisk
    - rtpengine
    - postgresql
    - monitoring

  tasks:
    - name: Verify VoIP services are running
      systemd:
        name: "{{ item }}"
        state: started
        enabled: yes
      loop:
        - opensips
        - asterisk
        - rtpengine
        - postgresql

    - name: Display VoIP service status
      command: systemctl status {{ item }}
      register: service_status
      loop:
        - opensips
        - asterisk
        - rtpengine
      changed_when: false

    - name: Show service status
      debug:
        msg: "{{ service_status.results }}"
EOF

# Create role for OpenSIPS compilation
mkdir -p ../roles/opensips/{tasks,templates,files,vars,defaults}

cat > ../roles/opensips/tasks/main.yml <<'EOF'
---
# roles/opensips/tasks/main.yml

- name: Install OpenSIPS build dependencies
  apt:
    name:
      - build-essential
      - git
      - libssl-dev
      - libncurses-dev
      - libpcre3-dev
      - libpq-dev
    state: present
    update_cache: yes

- name: Clone OpenSIPS repository
  git:
    repo: https://github.com/OpenSIPS/opensips.git
    dest: /usr/src/opensips
    version: "{{ opensips_version | default('3.4') }}"
    force: yes

- name: Configure OpenSIPS modules
  template:
    src: menuconfig.j2
    dest: /usr/src/opensips/.menuconfig

- name: Compile OpenSIPS
  shell: |
    cd /usr/src/opensips
    make cfg
    make -j{{ ansible_processor_vcpus }} \
      CC=gcc \
      CFLAGS="-O3 -march=native -mtune=native" \
      LDFLAGS="-Wl,-O1"
    make install
  args:
    creates: /usr/local/sbin/opensips

- name: Create OpenSIPS user
  user:
    name: opensips
    system: yes
    shell: /bin/false

- name: Create OpenSIPS configuration directory
  file:
    path: /usr/local/etc/opensips
    state: directory
    owner: opensips
    group: opensips
    mode: '0755'

- name: Deploy OpenSIPS configuration
  template:
    src: opensips.cfg.j2
    dest: /usr/local/etc/opensips/opensips.cfg
    owner: opensips
    group: opensips
    mode: '0644'
  notify: restart opensips

- name: Create OpenSIPS systemd service
  template:
    src: opensips.service.j2
    dest: /etc/systemd/system/opensips.service
    mode: '0644'
  notify: reload systemd

- name: Enable and start OpenSIPS service
  systemd:
    name: opensips
    enabled: yes
    state: started
    daemon_reload: yes
EOF

echo "✅ Ansible playbooks created!"
echo "Location: ~/automation/ansible/playbooks/"
```

---

### Phase 4: Create Terraform Configuration

```bash
#!/bin/bash
# create-terraform-config.sh

cd ~/automation/terraform/environments/prod

cat > main.tf <<'EOF'
# terraform/environments/prod/main.tf

terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Base Ubuntu image
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-22.04-base.qcow2"
  pool   = "default"
  source = "https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-arm64.img"
  format = "qcow2"
}

# VoIP VM 1
module "voip_vm_1" {
  source = "../../modules/voip-vm"

  vm_name   = "voip-prod-1"
  vm_cpus   = 4
  vm_memory = 8192
  vm_disk   = 100
  vm_ip     = "192.168.122.10"

  base_volume_id = libvirt_volume.ubuntu_base.id
}

# VoIP VM 2
module "voip_vm_2" {
  source = "../../modules/voip-vm"

  vm_name   = "voip-prod-2"
  vm_cpus   = 4
  vm_memory = 8192
  vm_disk   = 100
  vm_ip     = "192.168.122.11"

  base_volume_id = libvirt_volume.ubuntu_base.id
}

output "vm_ips" {
  value = {
    voip-prod-1 = module.voip_vm_1.vm_ip
    voip-prod-2 = module.voip_vm_2.vm_ip
  }
}
EOF

# Create module for VoIP VM
mkdir -p ../../modules/voip-vm
cat > ../../modules/voip-vm/main.tf <<'EOF'
# terraform/modules/voip-vm/main.tf

variable "vm_name" {
  type = string
}

variable "vm_cpus" {
  type    = number
  default = 4
}

variable "vm_memory" {
  type    = number
  default = 8192
}

variable "vm_disk" {
  type    = number
  default = 100
}

variable "vm_ip" {
  type = string
}

variable "base_volume_id" {
  type = string
}

# Create disk for VM
resource "libvirt_volume" "vm_disk" {
  name           = "${var.vm_name}.qcow2"
  base_volume_id = var.base_volume_id
  pool           = "default"
  size           = var.vm_disk * 1024 * 1024 * 1024
  format         = "qcow2"
}

# Cloud-init configuration
data "template_file" "user_data" {
  template = file("${path.module}/cloud_init.yaml")

  vars = {
    hostname = var.vm_name
    ssh_key  = file("~/.ssh/id_rsa.pub")
  }
}

resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "${var.vm_name}-cloudinit.iso"
  user_data = data.template_file.user_data.rendered
  pool      = "default"
}

# Create VM
resource "libvirt_domain" "voip_vm" {
  name   = var.vm_name
  memory = var.vm_memory
  vcpu   = var.vm_cpus

  cloudinit = libvirt_cloudinit_disk.commoninit.id

  disk {
    volume_id = libvirt_volume.vm_disk.id
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}

output "vm_ip" {
  value = libvirt_domain.voip_vm.network_interface[0].addresses[0]
}
EOF

echo "✅ Terraform configuration created!"
echo "Location: ~/automation/terraform/environments/prod/"
```

---

## Migration Plan

### Week 1: Setup Automation Environment

**Day 1-2: Install Tools**
```bash
# On macOS
brew install ansible terraform libvirt qemu
ansible-galaxy collection install community.libvirt

# Create directory structure
mkdir -p ~/automation/{ansible,terraform,scripts}
cd ~/automation && git init
```

**Day 3-4: Create Playbooks**
```bash
# Create Ansible roles and playbooks
# See Phase 3 above
```

**Day 5: Test Automation**
```bash
# Create test VM
cd ~/automation/ansible
ansible-playbook playbooks/create-test-vm.yml
```

---

### Week 2: Reduce DevStack Core

**Day 1: Backup Current State**
```bash
# Backup databases
./devstack.sh backup

# Backup Docker volumes
docker run --rm -v dev-postgres-data:/source -v ~/backups:/backup alpine tar czf /backup/postgres-data.tar.gz -C /source .
```

**Day 2-3: Create Minimal Compose File**
```bash
# Create docker-compose-minimal.yml
# See Phase 2 above

# Test minimal environment
docker compose -f docker-compose-minimal.yml up -d
```

**Day 4: Verify Services**
```bash
# Ensure Forgejo, Vault, Prometheus, Grafana still work
./devstack.sh health
```

**Day 5: Switch to Minimal**
```bash
# Stop full environment
docker compose down

# Use minimal
ln -sf docker-compose-minimal.yml docker-compose.yml
./devstack.sh start
```

---

### Week 3: Deploy VoIP VMs with libvirt

**Day 1-2: Create VMs with Terraform**
```bash
cd ~/automation/terraform/environments/prod
terraform init
terraform plan
terraform apply
```

**Day 3-4: Configure with Ansible**
```bash
cd ~/automation/ansible
ansible-playbook playbooks/deploy-voip-stack.yml
```

**Day 5: Verify VoIP Services**
```bash
# SSH to VMs
ssh admin@192.168.122.10

# Check services
systemctl status opensips asterisk rtpengine
```

---

### Week 4: Integration and Monitoring

**Day 1-2: Configure Prometheus/Grafana**
```bash
# Add VoIP VMs to Prometheus scrape configs
# Point Grafana at Prometheus
# Create dashboards for OpenSIPS/Asterisk/RTPEngine
```

**Day 3-4: Log Aggregation**
```bash
# Configure promtail on VoIP VMs
# Ship logs to Loki (in DevStack Core)
```

**Day 5: Documentation**
```bash
# Document architecture
# Create runbooks
# Update automation README
```

---

## Summary

### 🎯 **Final Recommendations**

#### 1. **Automation Environment: macOS Native** ✅
- Install Ansible, Terraform, libvirt on macOS
- Zero resource overhead
- Best developer experience
- Simple architecture

#### 2. **Configuration Management: Ansible** ✅
- Agentless (SSH-based)
- Easy to learn (YAML)
- Excellent libvirt support
- Perfect for 1-10 VMs

#### 3. **Container Reduction: 28 → 12** ✅
- Keep core infrastructure (9)
- Minimal observability (2)
- Remove reference APIs (5)
- Remove Redis cluster (2)
- **Savings: 16 containers, ~4GB RAM**

#### 4. **Architecture**
```
macOS (native)
├── Ansible/Terraform (automation control)
├── Colima (12 containers, reduced from 28)
│   └── Forgejo, DBs, Prometheus, Grafana, Loki
└── libvirt VMs (managed by Ansible)
    ├── VoIP Prod 1 (OpenSIPS, Asterisk, RTPEngine)
    └── VoIP Prod 2 (High availability)
```

**Total Resource Savings:**
- Before: 28 containers, ~8GB RAM for Colima
- After: 12 containers, ~4GB RAM for Colima
- **Savings: 4GB RAM, 2 CPU cores, cleaner architecture**

---

**Document Version:** 1.0
**Date:** 2025-11-10
**Status:** Complete Automation Infrastructure Design
