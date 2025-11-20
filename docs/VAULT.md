# Vault PKI Integration

## Table of Contents

  - [Overview](#overview)
  - [Service Vault Integration](#service-vault-integration)
  - [SSL/TLS Certificate Management](#ssltls-certificate-management)
  - [Vault Commands](#vault-commands)
- [Vault Auto-Unseal](#vault-auto-unseal)
  - [How It Works](#how-it-works)
  - [Initial Setup](#initial-setup)
  - [Auto-Unseal Process](#auto-unseal-process)
  - [Manual Operations](#manual-operations)

---

### Overview

HashiCorp Vault provides centralized secrets management and Public Key Infrastructure (PKI) for services. Instead of storing passwords in `.env` files, services fetch credentials from Vault at startup.

**Benefits:**
- ✅ Centralized secrets management
- ✅ Dynamic certificate generation
- ✅ Automatic certificate rotation
- ✅ Audit trail of secret access
- ✅ Optional SSL/TLS for encrypted connections
- ✅ No plaintext passwords in configuration files

**Architecture:**

```mermaid
graph TD
    subgraph "Vault PKI Certificate Hierarchy"
        RootCA[Root CA<br/>devstack-root-ca<br/>10-year validity<br/>Self-signed]

        IntermediateCA[Intermediate CA<br/>devstack-intermediate-ca<br/>5-year validity<br/>Signed by Root CA]

        PG[PostgreSQL Certificate<br/>postgres.devstack.local<br/>1-year validity]
        MYSQL[MySQL Certificate<br/>mysql.devstack.local<br/>1-year validity]
        REDIS1[Redis-1 Certificate<br/>redis-1.devstack.local<br/>1-year validity]
        REDIS2[Redis-2 Certificate<br/>redis-2.devstack.local<br/>1-year validity]
        REDIS3[Redis-3 Certificate<br/>redis-3.devstack.local<br/>1-year validity]
        RABBIT[RabbitMQ Certificate<br/>rabbitmq.devstack.local<br/>1-year validity]
        MONGO[MongoDB Certificate<br/>mongodb.devstack.local<br/>1-year validity]
        FORGEJO[Forgejo Certificate<br/>forgejo.devstack.local<br/>1-year validity]

        RootCA -->|Signs| IntermediateCA
        IntermediateCA -->|Issues| PG
        IntermediateCA -->|Issues| MYSQL
        IntermediateCA -->|Issues| REDIS1
        IntermediateCA -->|Issues| REDIS2
        IntermediateCA -->|Issues| REDIS3
        IntermediateCA -->|Issues| RABBIT
        IntermediateCA -->|Issues| MONGO
        IntermediateCA -->|Issues| FORGEJO
    end

    subgraph "Certificate Locations"
        ROOT_LOC["~/.config/vault/ca/root-ca.pem"]
        INT_LOC["~/.config/vault/ca/intermediate-ca.pem"]
        SVC_LOC["~/.config/vault/certs/&lt;service&gt;/"]
    end

    RootCA -.->|Stored| ROOT_LOC
    IntermediateCA -.->|Stored| INT_LOC
    PG -.->|Stored| SVC_LOC
    MYSQL -.->|Stored| SVC_LOC
    REDIS1 -.->|Stored| SVC_LOC

    style RootCA fill:#f9f,stroke:#333,stroke-width:3px
    style IntermediateCA fill:#bbf,stroke:#333,stroke-width:2px
    style PG fill:#bfb,stroke:#333,stroke-width:1px
    style MYSQL fill:#bfb,stroke:#333,stroke-width:1px
    style REDIS1 fill:#bfb,stroke:#333,stroke-width:1px
    style REDIS2 fill:#bfb,stroke:#333,stroke-width:1px
    style REDIS3 fill:#bfb,stroke:#333,stroke-width:1px
    style RABBIT fill:#bfb,stroke:#333,stroke-width:1px
    style MONGO fill:#bfb,stroke:#333,stroke-width:1px
    style FORGEJO fill:#bfb,stroke:#333,stroke-width:1px
```

**Text Summary:**
```
Vault PKI Hierarchy
├── Root CA (10-year validity)
│   └── Intermediate CA (5-year validity)
│       └── Service Certificates (1-year validity)
│           ├── PostgreSQL
│           ├── MySQL
│           ├── Redis (3 nodes)
│           ├── RabbitMQ
│           ├── MongoDB
│           └── Forgejo
```

### Service Vault Integration

**Core data tier services use Vault integration with AppRole authentication for credentials management.** AppRole migration for core services completed November 2025 (7 out of 16 Vault-integrated services, 43.75%).

#### Services Using AppRole Authentication (7)

**Core Data Tier (Production-Ready):**
- ✅ PostgreSQL (`configs/postgres/scripts/init-approle.sh`) - AppRole authentication
- ✅ MySQL (`configs/mysql/scripts/init-approle.sh`) - AppRole authentication
- ✅ Redis Cluster (3 nodes) (`configs/redis/scripts/init-approle.sh`) - AppRole authentication
- ✅ RabbitMQ (`configs/rabbitmq/scripts/init-approle.sh`) - AppRole authentication
- ✅ MongoDB (`configs/mongodb/scripts/init-approle.sh`) - AppRole authentication
- ✅ Forgejo (`configs/forgejo/scripts/init-approle.sh`) - AppRole authentication
- ✅ Reference API - FastAPI (`reference-apps/fastapi/app/services/vault.py`) - AppRole authentication

**Security Benefit:** Zero root token usage in core services. Least-privilege role-based access control with 1-hour token TTL.

#### Services Using VAULT_TOKEN (9)

**Infrastructure & Reference Apps (Migration Planned):**
- ⚠️ PGBouncer (`configs/pgbouncer/scripts/init.sh`) - Root token authentication
- ⚠️ API-First (`reference-apps/fastapi-api-first`) - Root token authentication
- ⚠️ Golang API (`reference-apps/golang-gin`) - Root token authentication
- ⚠️ Node.js API (`reference-apps/nodejs-express`) - Root token authentication
- ⚠️ Rust API (`reference-apps/rust-actix`) - Root token authentication
- ⚠️ Redis Exporter 1/2/3 (`configs/redis-exporter`) - Root token authentication
- ⚠️ Vector (`configs/vector`) - Root token authentication

**Reason for Delay:** These services were deprioritized during Phase 1 to focus on core data tier. Migration planned for Phase 4+.

#### AppRole Migration Roadmap

- ✅ **Phase 1 (Nov 2025):** Core data tier services (7 services) - **COMPLETED**
- 📋 **Phase 4.1 (Planned):** Reference applications (4 services) - Demonstrate best practices
- 📋 **Phase 4.2 (Planned):** Infrastructure services (5 services) - Complete migration

**Target:** 95%+ AppRole adoption (15/16 services, excluding Vector due to config complexity)

**How It Works (using PostgreSQL as example with AppRole):**

1. **Container Startup** → AppRole wrapper script (`/init/init-approle.sh`) executes
2. **Wait for Vault** → Script waits for Vault to be unsealed and ready
3. **AppRole Authentication** → Login to Vault using role-id and secret-id from `/vault-approles/postgres/`
4. **Obtain Service Token** → Receive short-lived service token (hvs.CAESIE... prefix)
5. **Fetch Credentials & TLS Setting** → GET `/v1/secret/data/postgres` using service token (includes `tls_enabled` field)
6. **Validate Certificates** → Check pre-generated certificates exist if TLS enabled
7. **Configure PostgreSQL** → Injects credentials and TLS configuration
8. **Start Service** → PostgreSQL starts with Vault-managed credentials

**Wrapper Script** (`configs/postgres/scripts/init-approle.sh`):

```bash
#!/bin/bash
# PostgreSQL initialization with Vault integration

# 1. Wait for Vault to be ready
wait_for_vault()

# 2. Fetch credentials AND tls_enabled from Vault
export POSTGRES_USER=$(vault_api | jq -r '.data.data.user')
export POSTGRES_PASSWORD=$(vault_api | jq -r '.data.data.password')
export POSTGRES_DB=$(vault_api | jq -r '.data.data.database')
export ENABLE_TLS=$(vault_api | jq -r '.data.data.tls_enabled // "false"')

# 3. If TLS enabled, validate pre-generated certificates
if [ "$ENABLE_TLS" = "true" ]; then
    validate_certificates  # Check certs exist in mounted volume
    configure_tls          # Configure PostgreSQL SSL
fi

# 4. Start PostgreSQL with injected credentials
exec docker-entrypoint.sh postgres
```

**Fetching PostgreSQL Password:**

```bash
# Via management script
./devstack vault-show-password postgres

# Via Vault CLI
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
vault kv get -field=password secret/postgres

# Via curl
curl -H "X-Vault-Token: $VAULT_TOKEN" \
  http://localhost:8200/v1/secret/data/postgres \
  | jq -r '.data.data.password'
```

**Environment Variables:**

```bash
# In .env file
VAULT_ADDR=http://vault:8200
VAULT_TOKEN=hvs.xxxxxxxxxxxxx  # From ~/.config/vault/root-token
# NOTE: TLS settings are now in Vault, not .env
```

**Note:** ALL service passwords and TLS settings have been removed from `.env`. All credentials and TLS configuration are now managed entirely by Vault.

### AppRole Authentication (Reference API Example)

**Overview:** The reference-api demonstrates **AppRole authentication**, HashiCorp's recommended method for applications to authenticate to Vault. This is more secure than using root tokens as it provides:
- Limited, application-specific permissions
- Renewable and revocable tokens
- Audit trail of application authentication
- No root token exposure in environment variables

**How It Works:**

1. **AppRole Credentials Mounted** → Credentials stored at `~/.config/vault/approles/reference-api/`
   - `role-id`: Identifies the AppRole (similar to username)
   - `secret-id`: Secret credential (similar to password)

2. **Container Startup** → Docker mounts credentials into container
   ```yaml
   volumes:
     - ${HOME}/.config/vault/approles/reference-api:/vault-approles/reference-api:ro
   ```

3. **Application Initialization** → VaultClient reads credentials and authenticates
   ```python
   # reference-apps/fastapi/app/services/vault.py
   def _login_with_approle(self) -> str:
       # Read role-id and secret-id from filesystem
       role_id_path = os.path.join(settings.VAULT_APPROLE_DIR, "role-id")
       secret_id_path = os.path.join(settings.VAULT_APPROLE_DIR, "secret-id")

       with open(role_id_path, 'r') as f:
           role_id = f.read().strip()
       with open(secret_id_path, 'r') as f:
           secret_id = f.read().strip()

       # Exchange credentials for Vault token
       url = urljoin(f"{self.vault_addr}/", "v1/auth/approle/login")
       payload = {"role_id": role_id, "secret_id": secret_id}

       response = client.post(url, json=payload, timeout=5.0)
       data = response.json()
       client_token = data.get("auth", {}).get("client_token")

       return client_token  # Token has "hvs." prefix (not root token)
   ```

4. **Fallback Mechanism** → If AppRole authentication fails, falls back to token-based auth
   ```python
   def __init__(self):
       if settings.VAULT_APPROLE_DIR and os.path.exists(settings.VAULT_APPROLE_DIR):
           try:
               self.vault_token = self._login_with_approle()
               logger.info("Successfully authenticated to Vault using AppRole")
           except Exception as e:
               logger.warning(f"AppRole authentication failed: {e}, falling back to token-based auth")
               self.vault_token = settings.VAULT_TOKEN
       else:
           logger.info("Using token-based authentication (AppRole directory not found)")
           self.vault_token = settings.VAULT_TOKEN
   ```

**Verifying AppRole Authentication:**

```bash
# 1. Check AppRole credentials exist
ls -la ~/.config/vault/approles/reference-api/
# Should show: role-id, secret-id

# 2. Verify container has no VAULT_TOKEN
docker exec dev-reference-api env | grep VAULT_TOKEN
# Should be empty (no output)

# 3. Check container logs for authentication
docker logs dev-reference-api 2>&1 | grep -i "approle"
# Should show: "Successfully authenticated to Vault using AppRole"

# 4. Verify token type
docker exec dev-reference-api python -c "from app.services.vault import vault_client; print(vault_client.vault_token[:4])"
# Should show: "hvs." (AppRole token, not root token starting with "hvs.")
```

**AppRole Setup (for reference):**

AppRole credentials are created during `./devstack vault-bootstrap`:

```bash
# Create AppRole
vault auth enable approle
vault write auth/approle/role/reference-api \
    token_policies="reference-api-policy" \
    token_ttl=1h \
    token_max_ttl=4h

# Generate credentials
vault read -field=role_id auth/approle/role/reference-api/role-id > ~/.config/vault/approles/reference-api/role-id
vault write -f -field=secret_id auth/approle/role/reference-api/secret-id > ~/.config/vault/approles/reference-api/secret-id
```

**Benefits:**
- **Security**: Application never has root token
- **Audit**: All API calls logged with AppRole identity
- **Rotation**: secret-id can be rotated without code changes
- **Least Privilege**: Policy limits what secrets application can access
- **Production-Ready**: Recommended by HashiCorp for application authentication

**See Also:**
- Reference API documentation: `reference-apps/fastapi/README.md`
- AppRole implementation: `reference-apps/fastapi/app/services/vault.py`
- Docker configuration: `docker-compose.yml` (line 879)

### SSL/TLS Certificate Management

**TLS Implementation: Pre-Generated Certificates with Vault-Based Configuration**

The system uses a modern, production-ready TLS architecture where:
- ✅ TLS settings are stored in **Vault** (not environment variables)
- ✅ Certificates are **pre-generated** and validated before service startup
- ✅ Runtime enable/disable without container rebuilds
- ✅ All 8 services support TLS (PostgreSQL, MySQL, Redis cluster, RabbitMQ, MongoDB, FastAPI reference app)
- ✅ Dual-mode operation (accepts both SSL and non-SSL connections)

**One-Time Certificate Generation:**

```bash
# 1. Ensure Vault is running and bootstrapped
docker compose up -d vault
sleep 10

# 2. Bootstrap Vault (creates secrets with tls_enabled field)
VAULT_ADDR=http://localhost:8200 \
VAULT_TOKEN=$(cat ~/.config/vault/root-token) \
  bash configs/vault/scripts/vault-bootstrap.sh

# 3. Generate all certificates (stored in ~/.config/vault/certs/)
VAULT_ADDR=http://localhost:8200 \
VAULT_TOKEN=$(cat ~/.config/vault/root-token) \
  bash scripts/generate-certificates.sh
```

**Enabling TLS for a Service (Runtime Configuration):**

```bash
# 1. Set tls_enabled=true in Vault
TOKEN=$(cat ~/.config/vault/root-token)
curl -sf -X POST \
  -H "X-Vault-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"data":{"tls_enabled":true}}' \
  http://localhost:8200/v1/secret/data/postgres

# 2. Restart the service (picks up new setting)
docker restart dev-postgres

# 3. Verify TLS is enabled
docker logs dev-postgres | grep "tls_enabled"
# Should show: tls_enabled=true
```

**Disabling TLS:**

```bash
# Set tls_enabled=false and restart
TOKEN=$(cat ~/.config/vault/root-token)
curl -sf -X POST \
  -H "X-Vault-Token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"data":{"tls_enabled":false}}' \
  http://localhost:8200/v1/secret/data/postgres

docker restart dev-postgres
```

**Certificate Rotation:**

```bash
# 1. Delete old certificates for a service
rm -rf ~/.config/vault/certs/postgres/

# 2. Regenerate certificates
VAULT_ADDR=http://localhost:8200 \
VAULT_TOKEN=$(cat ~/.config/vault/root-token) \
  bash scripts/generate-certificates.sh

# 3. Restart service to pick up new certificates
docker restart dev-postgres
```

**Certificate Details:**
- **Validity:** 1 year (8760 hours)
- **Storage:** `~/.config/vault/certs/{service}/`
- **Mount:** Read-only bind mounts into containers
- **Format:** Service-specific (e.g., MySQL uses .pem, MongoDB uses combined cert+key)

**Testing TLS Connections:**

All services are configured for **dual-mode TLS** (accepting both encrypted and unencrypted connections).

**PostgreSQL:**
```bash
# Get password from Vault
export PGPASSWORD=$(python3 scripts/read-vault-secret.py postgres password)

# SSL connection (with certificate verification)
psql "postgresql://dev_admin@localhost:5432/dev_database?sslmode=require"

# Non-SSL connection (dual-mode allows this)
psql "postgresql://dev_admin@localhost:5432/dev_database?sslmode=disable"

# Verify SSL is enabled
docker exec dev-postgres psql -U dev_admin -d dev_database -c "SHOW ssl;"
```

**MySQL:**
```bash
# Get password from Vault
MYSQL_PASS=$(export VAULT_TOKEN=$(cat ~/.config/vault/root-token); python3 scripts/read-vault-secret.py mysql password)

# SSL connection
mysql -h localhost -u dev_admin -p$MYSQL_PASS --ssl-mode=REQUIRED dev_database

# Non-SSL connection
mysql -h localhost -u dev_admin -p$MYSQL_PASS --ssl-mode=DISABLED dev_database

# Verify TLS is configured
docker logs dev-mysql | grep "Channel mysql_main configured to support TLS"
```

**Redis:**
```bash
# Get password from Vault
REDIS_PASS=$(export VAULT_TOKEN=$(cat ~/.config/vault/root-token); python3 scripts/read-vault-secret.py redis-1 password)

# SSL connection (TLS port 6380)
redis-cli -h localhost -p 6380 --tls \
  --cacert ~/.config/vault/certs/redis-1/ca.crt \
  --cert ~/.config/vault/certs/redis-1/redis.crt \
  --key ~/.config/vault/certs/redis-1/redis.key \
  -a $REDIS_PASS PING

# Non-SSL connection (standard port 6379)
redis-cli -h localhost -p 6379 -a $REDIS_PASS PING

# Verify dual ports
docker logs dev-redis-1 | grep "Ready to accept connections"
```

**RabbitMQ:**
```bash
# SSL port: 5671
# Non-SSL port: 5672 (management UI also available on 15672)

# Test management API
curl -u admin:$(export VAULT_TOKEN=$(cat ~/.config/vault/root-token); python3 scripts/read-vault-secret.py rabbitmq password) \
  http://localhost:15672/api/overview
```

**MongoDB:**
```bash
# Get credentials from Vault
MONGO_USER=$(export VAULT_TOKEN=$(cat ~/.config/vault/root-token); python3 scripts/read-vault-secret.py mongodb user)
MONGO_PASS=$(export VAULT_TOKEN=$(cat ~/.config/vault/root-token); python3 scripts/read-vault-secret.py mongodb password)

# SSL connection (if TLS is enabled)
mongosh "mongodb://$MONGO_USER:$MONGO_PASS@localhost:27017/dev_database?tls=true&tlsCAFile=$HOME/.config/vault/certs/mongodb/ca.pem"

# Non-SSL connection
mongosh "mongodb://$MONGO_USER:$MONGO_PASS@localhost:27017/dev_database"
```

**SSL/TLS Modes:**
- **PostgreSQL SSL Modes:**
  - `disable` - No SSL
  - `allow` - Try SSL, fallback to plain
  - `prefer` - Prefer SSL, fallback to plain
  - `require` - Require SSL (no cert verification)
  - `verify-ca` - Require SSL + verify CA certificate
  - `verify-full` - Require SSL + verify CA + hostname matching

- **MySQL SSL Modes:**
  - `DISABLED` - No SSL
  - `PREFERRED` - Use SSL if available
  - `REQUIRED` - Require SSL
  - `VERIFY_CA` - Verify CA certificate
  - `VERIFY_IDENTITY` - Verify CA + hostname

### Vault Commands

**Vault Management Script Commands:**

```bash
# Initialize Vault (first time only)
./devstack vault-init

# Check Vault status
./devstack vault-status

# Get root token
./devstack vault-token

# Unseal Vault manually (if needed)
./devstack vault-unseal

# Bootstrap PKI and service credentials
./devstack vault-bootstrap

# Export CA certificates
./devstack vault-ca-cert

# Show service password
./devstack vault-show-password postgres
./devstack vault-show-password mysql
```

**Vault Bootstrap Process:**

The `vault-bootstrap` command sets up the complete PKI infrastructure:

1. **Generate Root CA** (if not exists)
2. **Generate Intermediate CA CSR**
3. **Sign Intermediate CA with Root CA**
4. **Install Intermediate CA certificate**
5. **Create PKI roles for each service** (postgres-role, mysql-role, etc.)
6. **Generate and store service credentials** (user, password, database)
7. **Export CA certificates** to `~/.config/vault/ca/`

**Manual Vault Operations:**

```bash
# Set environment
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# List secret paths
vault kv list secret/

# Get PostgreSQL credentials
vault kv get secret/postgres

# Update password (manual rotation)
vault kv put secret/postgres \
  user=dev_admin \
  password=new_generated_password \
  database=dev_database

# Issue certificate manually
vault write pki_int/issue/postgres-role \
  common_name=postgres.dev-services.local \
  ttl=8760h

# View PKI role configuration
vault read pki_int/roles/postgres-role
```

**PKI Certificate Paths:**

```
Vault PKI Endpoints:
├── /v1/pki/ca/pem                      # Root CA certificate
├── /v1/pki_int/ca/pem                  # Intermediate CA certificate
├── /v1/pki_int/roles/postgres-role     # PostgreSQL certificate role
├── /v1/pki_int/issue/postgres-role     # Issue PostgreSQL certificate
└── /v1/secret/data/postgres            # PostgreSQL credentials
```

**Credential Loading for Non-Container Services:**

For services that need Vault credentials but aren't containerized (e.g., PgBouncer, Forgejo), credentials are loaded via environment variables:

**Script: `scripts/load-vault-env.sh`**

This script loads credentials from Vault into environment variables for docker-compose:

```bash
#!/bin/bash
# Load credentials from Vault and export as environment variables

# 1. Wait for Vault to be ready
# 2. Read VAULT_TOKEN from ~/.config/vault/root-token
# 3. Fetch PostgreSQL password: secret/postgres
# 4. Export POSTGRES_PASSWORD for docker-compose

export POSTGRES_PASSWORD=$(python3 scripts/read-vault-secret.py postgres password)
```

**Script: `scripts/read-vault-secret.py`**

Python helper to read secrets from Vault KV v2 API:

```python
#!/usr/bin/env python3
# Usage: read-vault-secret.py <path> <field>
# Example: read-vault-secret.py postgres password

import sys, json, urllib.request, os

vault_addr = os.getenv('VAULT_ADDR', 'http://localhost:8200')
vault_token = os.getenv('VAULT_TOKEN')

url = f"{vault_addr}/v1/secret/data/{sys.argv[1]}"
req = urllib.request.Request(url)
req.add_header('X-Vault-Token', vault_token)

with urllib.request.urlopen(req) as response:
    data = json.loads(response.read().decode())
    print(data['data']['data'][sys.argv[2]])
```

**When Credentials Are Loaded:**

The `manage-devstack.py` script automatically loads credentials during startup:

1. Start Vault container
2. Wait 5 seconds for Vault to be ready
3. Run `source scripts/load-vault-env.sh`
4. Export credentials as environment variables
5. Start remaining services with injected credentials

**All Services Are Now Vault-Integrated:**

✅ All database services (PostgreSQL, MySQL, MongoDB)
✅ All caching services (Redis Cluster)
✅ All message queue services (RabbitMQ)
✅ All connection pooling services (PgBouncer)

No migration needed - the infrastructure is complete!

## Vault Auto-Unseal

### How It Works

Vault runs in two concurrent processes within the container:

```
Container: dev-vault
├── Process 1: vault server
│   - Listens on 0.0.0.0:8200
│   - Uses file storage: /vault/data
│   - Config: /vault/config/vault.hcl
│
└── Process 2: vault-auto-unseal.sh
    - Waits for Vault to be ready
    - Unseals using saved keys
    - Sleeps indefinitely (no CPU overhead)
```

**Entrypoint** (`docker-compose.yml:360-366`):
```yaml
entrypoint: >
  sh -c "
  chown -R vault:vault /vault/data &&
  docker-entrypoint.sh server &
  /usr/local/bin/vault-auto-unseal.sh &
  wait -n
  "
```

**Process Flow:**
1. Fix `/vault/data` permissions (chown)
2. Start Vault server in background (`&`)
3. Start auto-unseal script in background (`&`)
4. Wait for either process to exit (`wait -n`)

### Initial Setup

**First-Time Initialization:**
```bash
./configs/vault/scripts/vault-init.sh
# Or
./devstack vault-init
```

**What Happens:**
1. Waits for Vault to be ready (max 30 seconds)
2. Checks if already initialized
3. If not initialized:
   - POSTs to `/v1/sys/init` with `{"secret_shares": 5, "secret_threshold": 3}`
   - Receives 5 unseal keys + root token
   - Saves to `~/.config/vault/keys.json` (chmod 600)
   - Saves root token to `~/.config/vault/root-token` (chmod 600)
4. Unseals Vault using 3 of 5 keys
5. Displays status and root token

**Shamir Secret Sharing:**
- 5 keys generated
- Any 3 keys can unseal Vault
- Designed for distributed trust (give keys to different people/systems)
- Lost keys = cannot unseal (data is encrypted and unrecoverable)

### Auto-Unseal Process

**Script** (`configs/vault/scripts/vault-auto-unseal.sh`):

```bash
# 1. Wait for Vault API (max 30 attempts, 1s each)
wget --spider http://127.0.0.1:8200/v1/sys/health?uninitcode=200&sealedcode=200

# 2. Check seal status
wget -qO- http://127.0.0.1:8200/v1/sys/seal-status
# → {"sealed": true}

# 3. Read unseal keys from mounted volume
cat /vault-keys/keys.json | extract 3 keys

# 4. POST each key to unseal endpoint
for key in key1 key2 key3; do
  wget --post-data='{"key":"'$key'"}' http://127.0.0.1:8200/v1/sys/unseal
done

# 5. Verify unsealed
wget -qO- http://127.0.0.1:8200/v1/sys/seal-status
# → {"sealed": false}

# 6. Sleep indefinitely (no monitoring overhead)
while true; do sleep 3600; done
```

**Why Not Continuous Monitoring?**
- Original design had 10-second checks (360 API calls/hour)
- Optimized to single unseal + sleep
- Saves 99% of API calls and CPU cycles
- Trade-off: Won't auto-reseal if manually sealed (must restart container)

### Manual Operations

**Check Vault Status:**
```bash
./devstack vault-status

# Or directly
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
vault status
```

**Manually Unseal:**
```bash
./devstack vault-unseal

# Or using vault CLI
vault operator unseal  # Repeat 3 times with different keys
```

**Seal Vault:**
```bash
vault operator seal
# Note: Won't auto-reseal until container restarts
```

**Rotate Root Token:**
```bash
vault token create -policy=root
# Save new token to ~/.config/vault/root-token
```

**Backup Unseal Keys:**
```bash
# Encrypt and backup
tar czf vault-keys-$(date +%Y%m%d).tar.gz ~/.config/vault/
gpg -c vault-keys-*.tar.gz
# Store encrypted file in secure location (1Password, etc.)
```

---

## Certificate Lifecycle Management

### Certificate Expiration Timeline

| Certificate Type | Validity Period | Typical Issue Date | Expiration Date | Renewal Window |
|------------------|-----------------|---------------------|-----------------|----------------|
| Root CA (pki) | 10 years | 2025-01-15 | 2035-01-15 | 9 years notice |
| Intermediate CA (pki_int) | 5 years | 2025-01-15 | 2030-01-15 | 4.5 years notice |
| Service Certificates | 1 year | 2025-01-15 | 2026-01-15 | **30 days notice** |

**Critical:** Service certificates must be renewed annually. Set calendar reminders for 30 days before expiration.

### Checking Certificate Expiration

**Check all service certificates:**
```bash
# Quick check all services
for service in postgres mysql redis-1 redis-2 redis-3 rabbitmq mongodb; do
  echo "=== $service ==="
  openssl x509 -in ~/.config/vault/certs/$service/cert.pem -noout -enddate
  echo ""
done

# With days until expiry
for service in postgres mysql redis-1 redis-2 redis-3 rabbitmq mongodb; do
  EXPIRY=$(openssl x509 -in ~/.config/vault/certs/$service/cert.pem -noout -enddate | cut -d= -f2)
  EXPIRY_EPOCH=$(date -j -f "%b %d %T %Y %Z" "$EXPIRY" +%s 2>/dev/null || date -d "$EXPIRY" +%s)
  NOW_EPOCH=$(date +%s)
  DAYS_UNTIL=$(( ($EXPIRY_EPOCH - $NOW_EPOCH) / 86400 ))
  echo "$service: $DAYS_UNTIL days until expiry"
done
```

**Check Root CA:**
```bash
openssl x509 -in ~/.config/vault/ca/ca.pem -noout -enddate -subject
```

**Check Intermediate CA:**
```bash
vault read pki_int/ca/pem | openssl x509 -noout -enddate -subject
```

### Service Certificate Renewal

**When to Renew:** 30 days before expiration (or sooner)

**Automated Renewal Script:** `scripts/renew-certificates.sh`

```bash
#!/bin/bash
# Renew all service certificates from Vault PKI
# Run annually or when certificates are approaching expiration

set -e

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-$(cat ~/.config/vault/root-token)}"

echo "🔄 Renewing service certificates..."
echo "Vault: $VAULT_ADDR"

# Check Vault is unsealed
if ! vault status > /dev/null 2>&1; then
  echo "❌ Error: Vault is not accessible or is sealed"
  echo "Run: ./devstack vault-unseal"
  exit 1
fi

# Backup existing certificates
echo "📦 Backing up existing certificates..."
BACKUP_DIR=~/.config/vault/certs-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
cp -r ~/.config/vault/certs/* "$BACKUP_DIR/"
echo "   Backup created: $BACKUP_DIR"

# Generate new certificates
echo "🔐 Generating new certificates..."
export VAULT_ADDR VAULT_TOKEN
./scripts/generate-certificates.sh

# Verify new certificates
echo "✅ Verifying new certificates..."
for service in postgres mysql redis-1 redis-2 redis-3 rabbitmq mongodb; do
  if [ -f ~/.config/vault/certs/$service/cert.pem ]; then
    EXPIRY=$(openssl x509 -in ~/.config/vault/certs/$service/cert.pem -noout -enddate | cut -d= -f2)
    echo "   $service: Valid until $EXPIRY"
  fi
done

echo ""
echo "🔄 Restarting services to load new certificates..."
./devstack restart

echo ""
echo "✅ Certificate renewal complete!"
echo "   Old certificates backed up to: $BACKUP_DIR"
echo "   New certificates expire in ~365 days"
echo ""
echo "📅 Set reminder to renew again in 11 months"
```

**Make executable and run:**
```bash
chmod +x scripts/renew-certificates.sh
./scripts/renew-certificates.sh
```

**Manual Renewal (if script fails):**

```bash
# 1. Set environment
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
export VAULT_ADDR=http://localhost:8200

# 2. Backup existing certificates
cp -r ~/.config/vault/certs ~/.config/vault/certs-backup-$(date +%Y%m%d)

# 3. Regenerate certificates
./scripts/generate-certificates.sh

# 4. Restart services
./devstack restart

# 5. Verify new certificates
for service in postgres mysql redis-1; do
  openssl x509 -in ~/.config/vault/certs/$service/cert.pem -noout -dates
done
```

### Intermediate CA Renewal

**When to Renew:** 60 days before expiration (5-year cert, so plan at 4 years 10 months)

**⚠️ CRITICAL:** Intermediate CA renewal affects ALL service certificates. Plan carefully.

**Renewal Procedure:**

```bash
# 1. Set environment
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
export VAULT_ADDR=http://localhost:8200

# 2. Check current intermediate CA expiration
vault read pki_int/ca/pem | openssl x509 -noout -enddate

# 3. Generate new intermediate CSR
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="DevStack Core Intermediate CA v2" \
  ttl="43800h" \
  key_type="rsa" \
  key_bits="4096" > pki_int_csr_v2.json

CSR=$(jq -r '.data.csr' < pki_int_csr_v2.json)

# 4. Sign with Root CA
vault write -format=json pki/root/sign-intermediate \
  csr="$CSR" \
  format=pem_bundle \
  ttl="43800h" > pki_int_cert_v2.json

CERT=$(jq -r '.data.certificate' < pki_int_cert_v2.json)

# 5. Import signed certificate
vault write pki_int/intermediate/set-signed certificate="$CERT"

# 6. Verify new intermediate CA
vault read pki_int/ca/pem | openssl x509 -noout -text | grep "Not After"

# 7. Regenerate ALL service certificates
./scripts/generate-certificates.sh

# 8. Restart all services
./devstack restart

# 9. Verify everything works
./devstack health
```

**Post-Renewal Verification:**
```bash
# Check Intermediate CA is active
vault list pki_int/roles

# Test certificate issuance
vault write pki_int/issue/postgres-role \
  common_name=test.postgres.local \
  ttl=1h

# Verify service health
./devstack health
```

### Root CA Renewal

**When to Renew:** 6-12 months before expiration (10-year cert, plan at 9 years)

**⚠️ MAJOR EVENT:** Root CA renewal requires extensive planning:

1. **Coordinated rollover period** (dual root CA trust)
2. **New intermediate CA** must be issued
3. **All service certificates** must be regenerated
4. **Distribution** of new root CA to all clients
5. **Testing** in non-production environment first

**DO NOT attempt Root CA renewal without:**
- Full backup of current PKI
- Test environment validation
- Communication plan for dependent systems
- Rollback procedure

**Recommendation:** Create a dedicated `ROOT_CA_RENEWAL.md` runbook 6 months before expiration with detailed step-by-step procedures specific to your environment.

**Emergency Root CA Renewal (if Root CA is compromised):**

See [DISASTER_RECOVERY.md](DISASTER_RECOVERY.md) - "Vault Data Loss" section.

### Automated Expiration Monitoring

**Daily Cron Job:**

```bash
# Add to crontab: crontab -e
# Check certificate expiration daily at 9 AM
0 9 * * * /Users/gator/devstack-core/scripts/check-cert-expiry.sh 2>&1 | mail -s "Certificate Expiry Report" admin@example.com
```

**Monitoring Script:** `scripts/check-cert-expiry.sh`

```bash
#!/bin/bash
# Check certificate expiration and alert if approaching expiry

WARN_DAYS=30
CRIT_DAYS=7
FOUND_WARNING=0
FOUND_CRITICAL=0

echo "Certificate Expiration Report - $(date)"
echo "==========================================="
echo ""

# Check service certificates
echo "Service Certificates:"
for cert_path in ~/.config/vault/certs/*/cert.pem; do
  if [ ! -f "$cert_path" ]; then
    continue
  fi

  service=$(basename $(dirname "$cert_path"))
  expiry=$(openssl x509 -in "$cert_path" -noout -enddate | cut -d= -f2)

  # Calculate days until expiry (macOS compatible)
  if date -j -f "%b %d %T %Y %Z" "$expiry" +%s > /dev/null 2>&1; then
    expiry_epoch=$(date -j -f "%b %d %T %Y %Z" "$expiry" +%s)
  else
    expiry_epoch=$(date -d "$expiry" +%s)
  fi

  now_epoch=$(date +%s)
  days_until=$(( ($expiry_epoch - $now_epoch) / 86400 ))

  if [ $days_until -lt $CRIT_DAYS ]; then
    echo "❌ CRITICAL: $service certificate expires in $days_until days ($expiry)"
    FOUND_CRITICAL=1
  elif [ $days_until -lt $WARN_DAYS ]; then
    echo "⚠️  WARNING: $service certificate expires in $days_until days ($expiry)"
    FOUND_WARNING=1
  else
    echo "✅ OK: $service certificate valid for $days_until days"
  fi
done

echo ""
echo "Root and Intermediate CAs:"

# Check Root CA
if [ -f ~/.config/vault/ca/ca.pem ]; then
  root_expiry=$(openssl x509 -in ~/.config/vault/ca/ca.pem -noout -enddate | cut -d= -f2)
  echo "   Root CA expires: $root_expiry"
fi

# Check Intermediate CA
if command -v vault > /dev/null 2>&1; then
  export VAULT_ADDR=http://localhost:8200
  export VAULT_TOKEN=$(cat ~/.config/vault/root-token 2>/dev/null)
  if [ -n "$VAULT_TOKEN" ]; then
    int_expiry=$(vault read pki_int/ca/pem 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null)
    if [ -n "$int_expiry" ]; then
      echo "   Intermediate CA expires: $int_expiry"
    fi
  fi
fi

echo ""
echo "==========================================="

# Exit codes for monitoring systems
if [ $FOUND_CRITICAL -eq 1 ]; then
  exit 2
elif [ $FOUND_WARNING -eq 1 ]; then
  exit 1
else
  exit 0
fi
```

**Make executable:**
```bash
chmod +x scripts/check-cert-expiry.sh

# Test run
./scripts/check-cert-expiry.sh
```

### Certificate Revocation

**When to Revoke:** Certificate compromise, key exposure, or service decommissioning

**Revocation Procedure:**

```bash
# 1. Get certificate serial number
openssl x509 -in ~/.config/vault/certs/postgres/cert.pem -noout -serial

# Example output: serial=3A:5F:2B:...

# 2. Revoke certificate
vault write pki_int/revoke serial_number="3A:5F:2B:..."

# 3. Generate new certificate immediately
vault write pki_int/issue/postgres-role \
  common_name="postgres" \
  ttl="8760h" \
  format=pem_bundle > postgres_new.json

# 4. Extract and install new certificate
jq -r '.data.certificate' < postgres_new.json > ~/.config/vault/certs/postgres/cert.pem
jq -r '.data.private_key' < postgres_new.json > ~/.config/vault/certs/postgres/key.pem
jq -r '.data.ca_chain[]' < postgres_new.json > ~/.config/vault/certs/postgres/ca.pem

# 5. Restart affected service
docker compose restart postgres

# 6. Update Certificate Revocation List (CRL)
vault read pki_int/crl
```

### Best Practices

1. **Calendar Reminders:**
   - **Root CA:** Set reminder 9 years from issue date
   - **Intermediate CA:** Set reminder 4 years 6 months from issue date
   - **Service Certificates:** Set reminders every 11 months

2. **Automate Renewal:**
   - **Service certificates:** Run `renew-certificates.sh` monthly (automated)
   - **Intermediate CA:** Manual process with advance planning
   - **Root CA:** Treat as major project, plan 6-12 months ahead

3. **Test Renewal Process:**
   - Practice renewal in test environment quarterly
   - Document any issues encountered
   - Update renewal scripts based on lessons learned

4. **Monitor Continuously:**
   - Daily automated expiration checks (`check-cert-expiry.sh`)
   - Alert if certificates < 30 days from expiry
   - Escalate if certificates < 7 days from expiry

5. **Backup Before Renewal:**
   - Always backup `~/.config/vault/` before renewal
   - Store backups securely off-system
   - Test restoration from backup

6. **Verify After Renewal:**
   - Check certificate dates with `openssl x509`
   - Verify services restart successfully
   - Run health checks: `./devstack health`
   - Test TLS connections to services

### Troubleshooting Certificate Issues

**Problem:** Service won't start after certificate renewal

**Solution:**
```bash
# Check certificate permissions
ls -la ~/.config/vault/certs/postgres/

# Should be readable (644 for certs, 600 for keys)
chmod 644 ~/.config/vault/certs/postgres/cert.pem
chmod 644 ~/.config/vault/certs/postgres/ca.pem
chmod 600 ~/.config/vault/certs/postgres/key.pem

# Check certificate validity
openssl verify -CAfile ~/.config/vault/certs/postgres/ca.pem \
  ~/.config/vault/certs/postgres/cert.pem

# Check service logs
docker compose logs postgres | grep -i tls
```

**Problem:** Certificate verification failed

**Solution:**
```bash
# Verify certificate chain
openssl verify -verbose -CAfile ~/.config/vault/ca/ca.pem \
  -untrusted ~/.config/vault/ca/ca-chain.pem \
  ~/.config/vault/certs/postgres/cert.pem

# If chain is broken, regenerate
./scripts/generate-certificates.sh
```

**Problem:** Vault won't issue new certificates

**Solution:**
```bash
# Check Vault PKI role exists
vault list pki_int/roles

# If missing, re-run vault-bootstrap
./devstack vault-bootstrap

# Check intermediate CA is configured
vault read pki_int/cert/ca
```

### Renewal Checklist

**30 Days Before Expiry:**
- [ ] Run `check-cert-expiry.sh` to confirm expiry dates
- [ ] Schedule maintenance window (service restart required)
- [ ] Notify stakeholders of planned renewal
- [ ] Backup current certificates
- [ ] Test renewal script in non-production environment

**Renewal Day:**
- [ ] Verify Vault is healthy and unsealed
- [ ] Backup `~/.config/vault/` directory
- [ ] Run `renew-certificates.sh` script
- [ ] Verify new certificate dates
- [ ] Restart services: `./devstack restart`
- [ ] Verify services healthy: `./devstack health`
- [ ] Test TLS connections
- [ ] Monitor service logs for TLS errors

**Post-Renewal (24 hours later):**
- [ ] Confirm no TLS errors in logs
- [ ] Verify applications connecting successfully
- [ ] Update renewal tracking spreadsheet
- [ ] Set reminder for next renewal (11 months)
- [ ] Document any issues encountered

---

