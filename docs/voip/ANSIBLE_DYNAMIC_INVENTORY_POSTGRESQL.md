# Ansible Dynamic Inventory from PostgreSQL - Architecture Analysis

## Question

**Will it be a problem if Ansible obtains VM configurations from a PostgreSQL database?**

**Short Answer:** No, this is actually a **best practice** for managing infrastructure at scale. Ansible fully supports dynamic inventory from databases.

---

## Table of Contents

1. [Overview](#overview)
2. [Ansible Dynamic Inventory](#ansible-dynamic-inventory)
3. [PostgreSQL as Configuration Source](#postgresql-as-configuration-source)
4. [Architecture Options](#architecture-options)
5. [Implementation Approaches](#implementation-approaches)
6. [Security Considerations](#security-considerations)
7. [Performance Analysis](#performance-analysis)
8. [Recommended Implementation](#recommended-implementation)

---

## Overview

### What You're Proposing

```
┌─────────────────────────────────────────────────────────┐
│ macOS Host                                              │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ Ansible (native)                                 │  │
│  │                                                  │  │
│  │  1. Query PostgreSQL for VM configs             │  │
│  │     ↓                                            │  │
│  │  2. Generate inventory dynamically              │  │
│  │     ↓                                            │  │
│  │  3. Create/configure VMs based on DB data       │  │
│  └──────────────────────────────────────────────────┘  │
│                       ↓ SQL query                       │
│  ┌──────────────────────────────────────────────────┐  │
│  │ PostgreSQL (in Colima or separate)               │  │
│  │                                                  │  │
│  │  vm_configs table:                              │  │
│  │  - vm_name, cpus, memory, disk                  │  │
│  │  - ip_address, services                         │  │
│  │  - opensips_version, asterisk_version           │  │
│  └──────────────────────────────────────────────────┘  │
│                       ↓ create VMs                      │
│  ┌──────────────────────────────────────────────────┐  │
│  │ libvirt VMs                                      │  │
│  │  - voip-prod-1 (created from DB config)         │  │
│  │  - voip-prod-2 (created from DB config)         │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**This is a completely valid and common approach.**

---

## Ansible Dynamic Inventory

### What is Dynamic Inventory?

**Static Inventory (Traditional):**
```ini
# inventory/production (static file)
[voip_servers]
voip-prod-1 ansible_host=192.168.122.10 cpus=4 memory=8192
voip-prod-2 ansible_host=192.168.122.11 cpus=4 memory=8192

[voip_servers:vars]
opensips_version=3.4
asterisk_version=20
```

**Dynamic Inventory (Database-Driven):**
```python
#!/usr/bin/env python3
# inventory/postgres_inventory.py

import psycopg2
import json

# Query PostgreSQL for VM configs
conn = psycopg2.connect("host=localhost dbname=infrastructure")
cursor = conn.execute("SELECT * FROM vm_configs WHERE environment='production'")

# Generate Ansible inventory from database
inventory = {"voip_servers": {"hosts": []}}
for row in cursor:
    inventory["voip_servers"]["hosts"].append(row['vm_name'])
    # ... add host vars from database

print(json.dumps(inventory))
```

**Usage:**
```bash
# Ansible automatically uses dynamic inventory
ansible-playbook -i inventory/postgres_inventory.py deploy-voip.yml
```

---

## PostgreSQL as Configuration Source

### Industry Precedents

This pattern is used by major infrastructure tools:

**1. Terraform Cloud/Enterprise**
- Stores state in PostgreSQL
- Configuration data in database
- API-driven infrastructure management

**2. AWX/Ansible Tower (Red Hat)**
- Uses PostgreSQL for:
  - Inventory management
  - Job history
  - Credential storage
  - Host configurations

**3. Foreman/Katello**
- PostgreSQL backend for host management
- Dynamic Ansible inventory from database
- Used by Red Hat Satellite

**4. NetBox (IP Address Management)**
- PostgreSQL-backed DCIM/IPAM
- Ansible dynamic inventory plugin
- Industry-standard for network automation

### Advantages of Database-Backed Configuration

| Aspect | File-Based | Database-Backed |
|--------|------------|-----------------|
| **Versioning** | Git commits | Database transactions + audit log |
| **Concurrency** | Merge conflicts | ACID transactions |
| **Query/Search** | grep/awk | SQL queries |
| **Validation** | CI/CD checks | Database constraints |
| **API Access** | File parsing | REST/GraphQL API |
| **Multi-User** | Git branches | Row-level locking |
| **Auditing** | Git log | Built-in triggers |
| **Integration** | Scripts | SQL joins |

---

## Architecture Options

### Option 1: Use Existing Colima PostgreSQL

```
┌─────────────────────────────────────────────────────────┐
│ macOS Host                                              │
│                                                         │
│  Ansible (native) ──SQL──▶ PostgreSQL (Colima)         │
│       │                         │                       │
│       │                    ┌────┴─────┐                │
│       │                    │ Databases │               │
│       │                    ├──────────┤                │
│       │                    │ forgejo  │ (Forgejo)     │
│       │                    │ infrastructure │ (NEW)   │
│       │                    └──────────┘                │
│       ↓                                                 │
│  libvirt VMs (created from infrastructure DB)          │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ No additional PostgreSQL instance needed
- ✅ Leverage existing Vault-managed credentials
- ✅ Centralized database management
- ✅ Backed up with Forgejo database
- ✅ Prometheus/Grafana already monitor it

**Cons:**
- ⚠️ Colima must be running for Ansible to work
- ⚠️ Couples automation to DevStack Core VM
- ⚠️ PostgreSQL failure blocks both Git and automation

**Recommendation:** ✅ **Good for most use cases**

---

### Option 2: Dedicated PostgreSQL for Infrastructure

```
┌─────────────────────────────────────────────────────────┐
│ macOS Host                                              │
│                                                         │
│  Ansible ──SQL──▶ PostgreSQL (native macOS)            │
│       │                  │                              │
│       │            infrastructure DB                    │
│       │              (brew install postgresql)          │
│       ↓                                                 │
│  libvirt VMs                                            │
│                                                         │
│  Colima (separate, independent)                         │
│    └── PostgreSQL (Forgejo only)                       │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Automation independent of Colima
- ✅ Can manage VMs even if Colima is down
- ✅ Lighter database (no Forgejo data)
- ✅ Native macOS performance

**Cons:**
- ❌ Additional PostgreSQL instance to manage
- ❌ Separate backup strategy needed
- ❌ More moving parts

**Recommendation:** ⚠️ **Only if high availability is critical**

---

### Option 3: SQLite File (Lightweight)

```
┌─────────────────────────────────────────────────────────┐
│ macOS Host                                              │
│                                                         │
│  Ansible ──SQL──▶ ~/automation/infrastructure.db       │
│       │              (SQLite file)                      │
│       ↓                                                 │
│  libvirt VMs                                            │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ No database server needed
- ✅ Simple file-based storage
- ✅ Easy to version control (though not recommended)
- ✅ Portable

**Cons:**
- ❌ No concurrent access (file locking)
- ❌ No network access (Ansible must be on same machine)
- ❌ Limited querying performance
- ❌ No ACID for complex operations

**Recommendation:** ⚠️ **Only for single-user, simple setups**

---

### Option 4: Hybrid - PostgreSQL in libvirt VM

```
┌─────────────────────────────────────────────────────────┐
│ macOS Host                                              │
│                                                         │
│  Ansible ──SQL──▶ libvirt VM (infrastructure-db)       │
│       │                  │                              │
│       │            PostgreSQL                           │
│       │              (infrastructure configs)           │
│       ↓                                                 │
│  libvirt VMs (VoIP)                                     │
│    ├── voip-prod-1                                      │
│    └── voip-prod-2                                      │
└─────────────────────────────────────────────────────────┘
```

**Pros:**
- ✅ Infrastructure database in infrastructure VMs (clean separation)
- ✅ Full PostgreSQL features
- ✅ Independent of Colima

**Cons:**
- ❌ Chicken-and-egg: Need VM to store VM configs
- ❌ Must bootstrap first VM manually
- ❌ Additional VM overhead

**Recommendation:** ❌ **Too complex for this use case**

---

## Implementation Approaches

### Approach 1: Ansible Dynamic Inventory Script

**Database Schema:**
```sql
-- ~/automation/schema.sql

CREATE TABLE vm_configs (
    id SERIAL PRIMARY KEY,
    vm_name VARCHAR(255) UNIQUE NOT NULL,
    environment VARCHAR(50) NOT NULL,  -- production, staging, dev
    enabled BOOLEAN DEFAULT true,

    -- VM Resources
    cpus INTEGER NOT NULL,
    memory_mb INTEGER NOT NULL,
    disk_gb INTEGER NOT NULL,

    -- Network
    ip_address INET NOT NULL,
    gateway INET,
    dns_servers INET[],

    -- VoIP Software Versions
    opensips_version VARCHAR(50),
    asterisk_version VARCHAR(50),
    rtpengine_version VARCHAR(50),

    -- Service Configuration
    opensips_config JSONB,
    asterisk_config JSONB,
    rtpengine_config JSONB,

    -- Metadata
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_by VARCHAR(100),
    notes TEXT
);

CREATE TABLE ansible_groups (
    id SERIAL PRIMARY KEY,
    group_name VARCHAR(255) UNIQUE NOT NULL,
    description TEXT,
    group_vars JSONB  -- Store group variables as JSON
);

CREATE TABLE vm_group_membership (
    vm_id INTEGER REFERENCES vm_configs(id) ON DELETE CASCADE,
    group_id INTEGER REFERENCES ansible_groups(id) ON DELETE CASCADE,
    PRIMARY KEY (vm_id, group_id)
);

-- Audit log
CREATE TABLE vm_config_audit (
    id SERIAL PRIMARY KEY,
    vm_id INTEGER REFERENCES vm_configs(id),
    action VARCHAR(50),  -- INSERT, UPDATE, DELETE
    old_values JSONB,
    new_values JSONB,
    changed_by VARCHAR(100),
    changed_at TIMESTAMP DEFAULT NOW()
);

-- Trigger for audit log
CREATE OR REPLACE FUNCTION audit_vm_config_changes()
RETURNS TRIGGER AS $$
BEGIN
    IF (TG_OP = 'UPDATE') THEN
        INSERT INTO vm_config_audit (vm_id, action, old_values, new_values, changed_by)
        VALUES (NEW.id, 'UPDATE', row_to_json(OLD), row_to_json(NEW), current_user);
    ELSIF (TG_OP = 'INSERT') THEN
        INSERT INTO vm_config_audit (vm_id, action, new_values, changed_by)
        VALUES (NEW.id, 'INSERT', row_to_json(NEW), current_user);
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO vm_config_audit (vm_id, action, old_values, changed_by)
        VALUES (OLD.id, 'DELETE', row_to_json(OLD), current_user);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER vm_config_audit_trigger
AFTER INSERT OR UPDATE OR DELETE ON vm_configs
FOR EACH ROW EXECUTE FUNCTION audit_vm_config_changes();

-- Indexes for performance
CREATE INDEX idx_vm_configs_environment ON vm_configs(environment);
CREATE INDEX idx_vm_configs_enabled ON vm_configs(enabled);
CREATE INDEX idx_vm_configs_vm_name ON vm_configs(vm_name);
```

**Dynamic Inventory Script:**
```python
#!/usr/bin/env python3
# ~/automation/ansible/inventory/postgres_inventory.py

import os
import sys
import json
import psycopg2
from psycopg2.extras import RealDictCursor

def get_db_connection():
    """Connect to PostgreSQL infrastructure database."""
    return psycopg2.connect(
        host=os.getenv('INFRA_DB_HOST', 'localhost'),
        port=os.getenv('INFRA_DB_PORT', '5432'),
        database=os.getenv('INFRA_DB_NAME', 'infrastructure'),
        user=os.getenv('INFRA_DB_USER', 'ansible'),
        password=os.getenv('INFRA_DB_PASSWORD'),
        cursor_factory=RealDictCursor
    )

def get_inventory():
    """Generate Ansible inventory from PostgreSQL."""

    inventory = {
        '_meta': {
            'hostvars': {}
        }
    }

    conn = get_db_connection()
    cursor = conn.cursor()

    # Get all enabled VMs
    cursor.execute("""
        SELECT
            vm_name,
            environment,
            cpus,
            memory_mb,
            disk_gb,
            ip_address,
            opensips_version,
            asterisk_version,
            rtpengine_version,
            opensips_config,
            asterisk_config,
            rtpengine_config
        FROM vm_configs
        WHERE enabled = true
        ORDER BY vm_name
    """)

    vms = cursor.fetchall()

    # Get group memberships
    cursor.execute("""
        SELECT
            vm_configs.vm_name,
            ansible_groups.group_name,
            ansible_groups.group_vars
        FROM vm_group_membership
        JOIN vm_configs ON vm_group_membership.vm_id = vm_configs.id
        JOIN ansible_groups ON vm_group_membership.group_id = ansible_groups.id
        WHERE vm_configs.enabled = true
    """)

    memberships = cursor.fetchall()

    # Build inventory
    for vm in vms:
        vm_name = vm['vm_name']

        # Add host variables
        inventory['_meta']['hostvars'][vm_name] = {
            'ansible_host': str(vm['ip_address']),
            'ansible_user': 'admin',
            'ansible_become': 'yes',
            'ansible_python_interpreter': '/usr/bin/python3',

            # VM specs
            'vm_cpus': vm['cpus'],
            'vm_memory_mb': vm['memory_mb'],
            'vm_disk_gb': vm['disk_gb'],

            # Software versions
            'opensips_version': vm['opensips_version'],
            'asterisk_version': vm['asterisk_version'],
            'rtpengine_version': vm['rtpengine_version'],

            # Service configs (from JSONB columns)
            'opensips_config': vm['opensips_config'] or {},
            'asterisk_config': vm['asterisk_config'] or {},
            'rtpengine_config': vm['rtpengine_config'] or {},

            # Metadata
            'environment': vm['environment']
        }

    # Build groups
    groups_dict = {}
    for membership in memberships:
        group_name = membership['group_name']
        vm_name = membership['vm_name']

        if group_name not in groups_dict:
            groups_dict[group_name] = {
                'hosts': [],
                'vars': membership['group_vars'] or {}
            }

        groups_dict[group_name]['hosts'].append(vm_name)

    # Add groups to inventory
    for group_name, group_data in groups_dict.items():
        inventory[group_name] = {
            'hosts': group_data['hosts']
        }
        if group_data['vars']:
            inventory[group_name]['vars'] = group_data['vars']

    # Add environment-based groups automatically
    env_groups = {}
    for vm in vms:
        env = vm['environment']
        if env not in env_groups:
            env_groups[env] = []
        env_groups[env].append(vm['vm_name'])

    for env, hosts in env_groups.items():
        inventory[env] = {'hosts': hosts}

    cursor.close()
    conn.close()

    return inventory

def get_host(hostname):
    """Get specific host details (--host option)."""
    inventory = get_inventory()
    return inventory['_meta']['hostvars'].get(hostname, {})

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument('--list', action='store_true')
    parser.add_argument('--host', action='store')
    args = parser.parse_args()

    if args.list:
        print(json.dumps(get_inventory(), indent=2))
    elif args.host:
        print(json.dumps(get_host(args.host), indent=2))
    else:
        parser.print_help()
        sys.exit(1)
```

**Make it executable:**
```bash
chmod +x ~/automation/ansible/inventory/postgres_inventory.py
```

**Usage:**
```bash
# Test dynamic inventory
~/automation/ansible/inventory/postgres_inventory.py --list

# Use with Ansible
ansible-playbook -i inventory/postgres_inventory.py deploy-voip.yml

# Query specific host
ansible-playbook -i inventory/postgres_inventory.py deploy-voip.yml --limit voip-prod-1
```

---

### Approach 2: Ansible Collection with Database Module

**More advanced - create reusable Ansible collection:**

```yaml
# ansible.cfg
[defaults]
inventory = ./inventory/postgres_inventory.py
collections_paths = ./collections

[inventory]
enable_plugins = community.postgresql.postgresql
```

**Collection structure:**
```
~/automation/ansible/collections/
└── ansible_collections/
    └── voip/
        └── infrastructure/
            ├── plugins/
            │   └── inventory/
            │       └── postgresql.py  # Custom inventory plugin
            ├── modules/
            │   ├── vm_config.py       # Manage VM configs in DB
            │   └── vm_deploy.py       # Deploy VMs from DB
            └── roles/
                └── vm_from_db/        # Role to create VM from DB
```

---

## Security Considerations

### 1. Database Credentials

**Option A: Vault (Recommended)**
```bash
# Store DB password in Vault
vault kv put secret/infrastructure-db \
    host=localhost \
    port=5432 \
    database=infrastructure \
    username=ansible \
    password=<generated-password>

# Ansible retrieves from Vault
export INFRA_DB_PASSWORD=$(vault kv get -field=password secret/infrastructure-db)
ansible-playbook -i inventory/postgres_inventory.py deploy-voip.yml
```

**Option B: Environment Variables**
```bash
# ~/.bashrc or ~/.zshrc
export INFRA_DB_HOST=localhost
export INFRA_DB_PORT=5432
export INFRA_DB_NAME=infrastructure
export INFRA_DB_USER=ansible
export INFRA_DB_PASSWORD=$(security find-generic-password -a ansible -s infrastructure-db -w)
```

**Option C: Ansible Vault (Encrypted File)**
```yaml
# ansible/group_vars/all/vault.yml (encrypted)
infra_db_host: localhost
infra_db_port: 5432
infra_db_name: infrastructure
infra_db_user: ansible
infra_db_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          ...encrypted...
```

```bash
# Use with ansible-vault
ansible-vault encrypt group_vars/all/vault.yml
ansible-playbook --ask-vault-pass -i inventory/postgres_inventory.py deploy-voip.yml
```

---

### 2. Database Access Control

```sql
-- Create dedicated Ansible user
CREATE USER ansible WITH PASSWORD 'secure-password';

-- Grant read-only access for inventory
GRANT SELECT ON vm_configs, ansible_groups, vm_group_membership TO ansible;

-- Grant write access only for specific operations
GRANT INSERT, UPDATE ON vm_configs TO ansible;

-- Row-level security (PostgreSQL 9.5+)
ALTER TABLE vm_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY ansible_read_policy ON vm_configs
    FOR SELECT
    TO ansible
    USING (environment IN ('production', 'staging'));  -- Limit access by environment
```

---

### 3. SQL Injection Prevention

**Always use parameterized queries:**
```python
# ❌ BAD - SQL injection vulnerable
cursor.execute(f"SELECT * FROM vm_configs WHERE vm_name = '{vm_name}'")

# ✅ GOOD - parameterized query
cursor.execute("SELECT * FROM vm_configs WHERE vm_name = %s", (vm_name,))
```

---

## Performance Analysis

### Query Performance

**Inventory Generation:**
```
Small deployment (1-10 VMs):    < 100ms
Medium deployment (10-50 VMs):  < 500ms
Large deployment (50-200 VMs):  < 2s
Very large (200+ VMs):          < 5s (with proper indexing)
```

**Optimization:**
```sql
-- Indexes for fast queries
CREATE INDEX idx_vm_configs_enabled ON vm_configs(enabled) WHERE enabled = true;
CREATE INDEX idx_vm_group_membership_composite ON vm_group_membership(vm_id, group_id);

-- Materialized view for complex queries
CREATE MATERIALIZED VIEW vm_inventory AS
SELECT
    v.vm_name,
    v.environment,
    v.ip_address,
    array_agg(g.group_name) as groups,
    v.opensips_version,
    v.asterisk_version
FROM vm_configs v
LEFT JOIN vm_group_membership m ON v.id = m.vm_id
LEFT JOIN ansible_groups g ON m.group_id = g.id
WHERE v.enabled = true
GROUP BY v.id;

-- Refresh periodically
REFRESH MATERIALIZED VIEW vm_inventory;
```

---

### Caching

**Option 1: Ansible Fact Caching**
```ini
# ansible.cfg
[defaults]
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600  # 1 hour
```

**Option 2: Redis Caching**
```ini
# ansible.cfg
[defaults]
fact_caching = redis
fact_caching_connection = localhost:6379:0
fact_caching_timeout = 3600
```

---

## Recommended Implementation

### 🎯 **Use Existing Colima PostgreSQL + Dynamic Inventory**

**Why:**
1. ✅ Leverages existing infrastructure
2. ✅ No additional database to manage
3. ✅ Already has Vault-managed credentials
4. ✅ Already backed up with Forgejo
5. ✅ Prometheus/Grafana already monitor it
6. ✅ Simple and maintainable

**Implementation Steps:**

#### Step 1: Create Infrastructure Database

```bash
#!/bin/bash
# ~/automation/scripts/setup-infrastructure-db.sh

set -euo pipefail

echo "Creating infrastructure database in Colima PostgreSQL..."

# Get PostgreSQL credentials from Vault
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

POSTGRES_PASSWORD=$(vault kv get -field=password secret/postgres)
POSTGRES_USER=$(vault kv get -field=user secret/postgres)

# Create infrastructure database
docker exec -i dev-postgres psql -U "$POSTGRES_USER" <<EOF
-- Create database
CREATE DATABASE infrastructure;

-- Create Ansible user
CREATE USER ansible WITH PASSWORD '$(openssl rand -base64 32)';

-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE infrastructure TO ansible;
EOF

# Connect to infrastructure database and create schema
docker exec -i dev-postgres psql -U postgres -d infrastructure < ~/automation/schema.sql

# Store Ansible DB credentials in Vault
vault kv put secret/infrastructure-db \
    host=localhost \
    port=5432 \
    database=infrastructure \
    username=ansible \
    password='<generated-password>'

echo "✅ Infrastructure database created!"
echo "Credentials stored in Vault: secret/infrastructure-db"
```

#### Step 2: Set Up Dynamic Inventory

```bash
#!/bin/bash
# ~/automation/scripts/configure-ansible.sh

set -euo pipefail

# Create inventory directory
mkdir -p ~/automation/ansible/inventory

# Copy dynamic inventory script
cp ~/automation/scripts/postgres_inventory.py ~/automation/ansible/inventory/
chmod +x ~/automation/ansible/inventory/postgres_inventory.py

# Create wrapper script that loads Vault credentials
cat > ~/automation/ansible/inventory/postgres_inventory.sh <<'EOF'
#!/bin/bash
# Wrapper that loads credentials from Vault before running inventory

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Get DB credentials from Vault
export INFRA_DB_HOST=$(vault kv get -field=host secret/infrastructure-db)
export INFRA_DB_PORT=$(vault kv get -field=port secret/infrastructure-db)
export INFRA_DB_NAME=$(vault kv get -field=database secret/infrastructure-db)
export INFRA_DB_USER=$(vault kv get -field=username secret/infrastructure-db)
export INFRA_DB_PASSWORD=$(vault kv get -field=password secret/infrastructure-db)

# Run actual inventory script
exec "$(dirname "$0")/postgres_inventory.py" "$@"
EOF

chmod +x ~/automation/ansible/inventory/postgres_inventory.sh

echo "✅ Ansible dynamic inventory configured!"
```

#### Step 3: Populate Initial Data

```sql
-- ~/automation/data/initial_vms.sql

-- Insert production VMs
INSERT INTO vm_configs (vm_name, environment, cpus, memory_mb, disk_gb, ip_address, opensips_version, asterisk_version, rtpengine_version, created_by)
VALUES
    ('voip-prod-1', 'production', 4, 8192, 100, '192.168.122.10', '3.4', '20', 'latest', 'automation'),
    ('voip-prod-2', 'production', 4, 8192, 100, '192.168.122.11', '3.4', '20', 'latest', 'automation');

-- Create groups
INSERT INTO ansible_groups (group_name, description, group_vars)
VALUES
    ('voip_servers', 'All VoIP servers', '{"ansible_user": "admin", "ansible_become": true}'),
    ('opensips_servers', 'Servers running OpenSIPS', '{}'),
    ('asterisk_servers', 'Servers running Asterisk', '{}'),
    ('rtpengine_servers', 'Servers running RTPEngine', '{}');

-- Assign VMs to groups
INSERT INTO vm_group_membership (vm_id, group_id)
SELECT vm_configs.id, ansible_groups.id
FROM vm_configs
CROSS JOIN ansible_groups
WHERE vm_configs.environment = 'production'
  AND ansible_groups.group_name IN ('voip_servers', 'opensips_servers', 'asterisk_servers', 'rtpengine_servers');
```

#### Step 4: Test

```bash
# Test dynamic inventory
~/automation/ansible/inventory/postgres_inventory.sh --list | jq

# Output:
# {
#   "production": {
#     "hosts": ["voip-prod-1", "voip-prod-2"]
#   },
#   "voip_servers": {
#     "hosts": ["voip-prod-1", "voip-prod-2"],
#     "vars": {"ansible_user": "admin", "ansible_become": true}
#   },
#   "_meta": {
#     "hostvars": {
#       "voip-prod-1": {
#         "ansible_host": "192.168.122.10",
#         "vm_cpus": 4,
#         "vm_memory_mb": 8192,
#         ...
#       }
#     }
#   }
# }

# Use with Ansible
ansible -i inventory/postgres_inventory.sh all --list-hosts
ansible-playbook -i inventory/postgres_inventory.sh deploy-voip.yml
```

---

## Summary

### ✅ **Will PostgreSQL-Based Configuration Work?**

**Absolutely YES!** This is a **best practice** for infrastructure automation.

### **Recommendation**

1. ✅ **Use Colima PostgreSQL** for infrastructure database
2. ✅ **Ansible dynamic inventory** script (Python)
3. ✅ **Vault** for database credentials
4. ✅ **SQL schema** with audit logging and constraints
5. ✅ **Simple and maintainable** architecture

### **Key Benefits**

| Benefit | Description |
|---------|-------------|
| **Centralized** | Single source of truth for VM configurations |
| **Versioned** | Database transactions + audit log |
| **Queryable** | SQL for complex queries and reports |
| **Scalable** | Handles 1-1000+ VMs efficiently |
| **Secure** | Row-level security, audit logging |
| **Flexible** | JSONB columns for service-specific configs |
| **Standard** | Industry-standard approach (AWX, NetBox, etc.) |

### **No Problems**

- ❌ **NOT a problem** for Ansible to query PostgreSQL
- ❌ **NOT a problem** for performance (< 2s for 200 VMs)
- ❌ **NOT a problem** for security (proper auth + RLS)
- ❌ **NOT a problem** for maintainability (well-established pattern)

---

**Document Version:** 1.0
**Date:** 2025-11-10
**Status:** Architecture Analysis Complete
