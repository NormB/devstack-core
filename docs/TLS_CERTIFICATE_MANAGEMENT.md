# TLS Certificate Management Guide

**Version:** 1.3.0
**Last Updated:** November 17, 2025
**Status:** Production-Ready

## Overview

DevStack Core uses HashiCorp Vault PKI (Public Key Infrastructure) to manage TLS certificates for all services. All services run in **dual-mode** by default, accepting both TLS and non-TLS connections for development flexibility while maintaining production-ready security.

## Architecture

### Certificate Hierarchy

```
Root CA (pki) - 10 years
└── Intermediate CA (pki_int) - 5 years
    └── Service Certificates - 1 year
        ├── PostgreSQL
        ├── MySQL
        ├── MongoDB
        ├── Redis (3 nodes)
        ├── RabbitMQ
        ├── Forgejo
        └── Reference APIs
```

### Storage Locations

| Component | Location | Notes |
|-----------|----------|-------|
| **Root CA** | `~/.config/vault/ca/ca.pem` | 10-year validity |
| **Intermediate CA** | `~/.config/vault/ca/ca-chain.pem` | 5-year validity |
| **Service Certificates** | `~/.config/vault/certs/<service>/` | 1-year validity, auto-renewable |
| **Vault Seal Keys** | `~/.config/vault/keys.json` | **CRITICAL - BACKUP** |
| **Vault Root Token** | `~/.config/vault/root-token` | **CRITICAL - BACKUP** |

### Certificate Files Per Service

Each service has a dedicated directory with the following files:

**Standard Format** (PostgreSQL, Forgejo, Reference APIs):
- `cert.pem` - Certificate file
- `key.pem` - Private key (600 permissions)
- `ca.pem` - CA certificate chain

**Service-Specific Formats**:
- **MySQL**: `server-cert.pem`, `server-key.pem`, `ca.pem`
- **MongoDB**: `mongodb.pem` (combined cert+key), `ca.pem`
- **Redis**: `redis.crt`, `redis.key`, `ca.pem`
- **RabbitMQ**: `server.pem`, `key.pem`, `ca.pem`

## TLS Configuration

### Current Status

All services have TLS **enabled by default** in `.env`:

```bash
# TLS Configuration (Enabled by Default)
POSTGRES_ENABLE_TLS=true
MYSQL_ENABLE_TLS=true
REDIS_ENABLE_TLS=true
RABBITMQ_ENABLE_TLS=true
MONGODB_ENABLE_TLS=true
FORGEJO_ENABLE_TLS=true
REFERENCE_API_ENABLE_TLS=true
```

### Dual-Mode Operation

Services accept **both TLS and non-TLS connections** for development flexibility:

| Service | Non-TLS Port | TLS Port | Protocol |
|---------|--------------|----------|----------|
| **PostgreSQL** | 5432 | 5432 | `ssl=on` (dual-mode) |
| **MySQL** | 3306 | 3306 | `require_secure_transport=OFF` (dual-mode) |
| **MongoDB** | 27017 | 27017 | Dual-mode TLS |
| **Redis-1** | 6379 | 6380 | Separate ports |
| **Redis-2** | 6379 | 6380 | Separate ports |
| **Redis-3** | 6379 | 6380 | Separate ports |
| **RabbitMQ** | 5672 | 5671 | AMQP / AMQPS |
| **Reference APIs** | 8000-8004 | 8443-8447 | HTTP / HTTPS |

### Disabling TLS (Not Recommended)

To disable TLS for a specific service:

```bash
# In .env file
POSTGRES_ENABLE_TLS=false  # Disable PostgreSQL TLS
```

**Note:** This is **not recommended** for production-like environments.

## Certificate Management Scripts

### 1. Generate Certificates

**Script:** `scripts/generate-certificates.sh`

**Purpose:** Generate TLS certificates for all services from Vault PKI.

**Usage:**
```bash
# Generate certificates for all services
./scripts/generate-certificates.sh

# Certificates are stored in ~/.config/vault/certs/
```

**Features:**
- Skips services with valid certificates (>30 days remaining)
- Generates service-specific certificate formats
- Sets proper file permissions (600 for private keys)
- Includes SANs: `localhost`, `127.0.0.1`, service-specific IPs

**Prerequisites:**
- Vault must be running and unsealed
- `vault-bootstrap` must have been run
- `VAULT_ADDR` and `VAULT_TOKEN` must be set

### 2. Auto-Renew Certificates

**Script:** `scripts/auto-renew-certificates.sh`

**Purpose:** Automatically renew certificates within 30 days of expiration.

**Usage:**
```bash
# Normal renewal (renews certificates expiring in 30 days)
./scripts/auto-renew-certificates.sh

# Dry-run mode (preview what would be renewed)
./scripts/auto-renew-certificates.sh --dry-run

# Force renewal of all certificates
./scripts/auto-renew-certificates.sh --force

# Renew specific service
./scripts/auto-renew-certificates.sh --service postgres

# Silent mode for cron
./scripts/auto-renew-certificates.sh --quiet
```

**Features:**
- Automatic detection of expiring certificates
- 30-day renewal threshold (configurable)
- Dry-run mode for testing
- Force renewal option
- Per-service renewal
- Detailed logging to `~/.config/vault/cert-renewal.log`

**Exit Codes:**
- `0` - Success: no renewals needed or all successful
- `1` - Error: missing dependencies or renewal failed
- `2` - Warning: some certificates renewed, some failed

### 3. Check Certificate Expiration

**Script:** `scripts/check-cert-expiration.sh`

**Purpose:** Monitor certificate expiration status.

**Usage:**
```bash
# Human-readable output
./scripts/check-cert-expiration.sh

# JSON output
./scripts/check-cert-expiration.sh --json

# Nagios plugin format (for monitoring systems)
./scripts/check-cert-expiration.sh --nagios

# Check specific service
./scripts/check-cert-expiration.sh --service postgres
```

**Features:**
- Color-coded status output
- Warning threshold: 30 days
- Critical threshold: 7 days
- JSON output for integration
- Nagios plugin format
- Per-service checks

**Exit Codes:**
- `0` - OK: All certificates valid
- `1` - WARNING: Certificates expiring within 30 days
- `2` - CRITICAL: Certificates expired or expiring within 7 days

**Example Output:**
```
═══════════════════════════════════════════════════════
  Certificate Expiration Status
  Warning Threshold: 30 days
  Critical Threshold: 7 days
═══════════════════════════════════════════════════════

✓ postgres: Valid for 345 days
✓ mysql: Valid for 345 days
⚠ redis-1: Expires in 28 days
✓ mongodb: Valid for 345 days
```

### 4. Setup Cron Jobs

**Script:** `scripts/setup-cert-renewal-cron.sh`

**Purpose:** Setup automated certificate renewal via cron.

**Usage:**
```bash
# Install cron jobs
./scripts/setup-cert-renewal-cron.sh

# List existing cron jobs
./scripts/setup-cert-renewal-cron.sh --list

# Remove cron jobs
./scripts/setup-cert-renewal-cron.sh --remove
```

**Installed Cron Jobs:**
- **Daily Renewal Check:** 2:00 AM - Automatically renews expiring certificates
- **Weekly Status Report:** 9:00 AM Sunday - Generates expiration status report

**Log Files:**
- Renewal log: `~/.config/vault/cert-renewal.log`
- Status check log: `~/.config/vault/cert-check.log`

## Certificate Lifecycle

### Initial Setup

1. **Start Infrastructure:**
   ```bash
   ./devstack start
   ```

2. **Initialize Vault:**
   ```bash
   ./devstack vault-init
   ```

3. **Bootstrap PKI:**
   ```bash
   ./devstack vault-bootstrap
   ```

   This creates:
   - Root CA (10-year validity)
   - Intermediate CA (5-year validity)
   - Service roles for certificate issuance

4. **Generate Certificates:**
   ```bash
   ./scripts/generate-certificates.sh
   ```

   Certificates are generated for all services and stored in `~/.config/vault/certs/`.

### Manual Renewal

**When to Renew:**
- Certificates expire in < 30 days
- Service certificate compromised
- Adding new services
- Updating certificate parameters

**How to Renew:**

```bash
# Renew all certificates
./scripts/auto-renew-certificates.sh --force

# Renew specific service
./scripts/auto-renew-certificates.sh --service postgres

# Restart service to use new certificate
docker compose restart postgres
```

### Automated Renewal

**Setup (One-Time):**
```bash
./scripts/setup-cert-renewal-cron.sh
```

**Verification:**
```bash
# Check cron jobs
./scripts/setup-cert-renewal-cron.sh --list

# Check renewal log
tail -f ~/.config/vault/cert-renewal.log

# Check status log
tail -f ~/.config/vault/cert-check.log
```

**Monitoring:**
```bash
# Run manual check
./scripts/check-cert-expiration.sh

# Check JSON output
./scripts/check-cert-expiration.sh --json

# Integrate with monitoring (Nagios/Icinga/etc)
./scripts/check-cert-expiration.sh --nagios
```

### CA Renewal

**Root CA Renewal** (Every 10 years):

⚠️ **WARNING:** This is a critical operation requiring downtime.

```bash
# 1. Backup current PKI
cp -r ~/.config/vault ~/vault-backup-$(date +%Y%m%d)

# 2. Re-run vault bootstrap (will create new Root CA)
./devstack vault-bootstrap

# 3. Regenerate all service certificates
rm -rf ~/.config/vault/certs/
./scripts/generate-certificates.sh

# 4. Restart all services
./devstack restart
```

**Intermediate CA Renewal** (Every 5 years):

```bash
# 1. Backup current PKI
cp -r ~/.config/vault ~/vault-backup-$(date +%Y%m%d)

# 2. Generate new Intermediate CA from Root CA
vault write -format=json pki_int/intermediate/generate/internal \
    common_name="DevStack Core Intermediate CA" \
    ttl="43800h" | jq -r '.data.csr' > pki_intermediate.csr

vault write -format=json pki/root/sign-intermediate \
    csr=@pki_intermediate.csr \
    format=pem_bundle ttl="43800h" | jq -r '.data.certificate' > intermediate.cert.pem

vault write pki_int/intermediate/set-signed certificate=@intermediate.cert.pem

# 3. Regenerate all service certificates
rm -rf ~/.config/vault/certs/
./scripts/generate-certificates.sh

# 4. Restart all services
./devstack restart
```

## Testing TLS Connections

### PostgreSQL

```bash
# Test TLS connection
psql "postgresql://postgres:password@localhost:5432/devstack?sslmode=require"

# Verify TLS enabled
docker exec dev-postgres psql -U postgres -c "SHOW ssl;"

# Check active SSL connections
docker exec dev-postgres psql -U postgres -c \
    "SELECT datname, usename, ssl, client_addr FROM pg_stat_ssl JOIN pg_stat_activity ON pg_stat_ssl.pid = pg_stat_activity.pid;"
```

### MySQL

```bash
# Test TLS connection
mysql -h localhost -P 3306 -u root -p --ssl-mode=REQUIRED

# Verify TLS enabled
docker exec dev-mysql mysql -u root -p -e "SHOW VARIABLES LIKE 'have_ssl';"

# Check SSL status
docker exec dev-mysql mysql -u root -p -e "SHOW STATUS LIKE 'Ssl_cipher';"
```

### MongoDB

```bash
# Test TLS connection
mongosh "mongodb://root:password@localhost:27017/?tls=true&tlsAllowInvalidCertificates=true"

# Verify TLS enabled
docker exec dev-mongodb mongosh --eval "db.serverStatus().security"
```

### Redis

```bash
# Test TLS connection (port 6380)
redis-cli -h localhost -p 6380 --tls --cacert ~/.config/vault/certs/redis-1/ca.pem ping

# Test non-TLS connection (port 6379)
redis-cli -h localhost -p 6379 ping
```

### RabbitMQ

```bash
# Test AMQPS connection (port 5671)
openssl s_client -connect localhost:5671 -CAfile ~/.config/vault/certs/rabbitmq/ca.pem

# Management UI (HTTPS)
curl --cacert ~/.config/vault/certs/rabbitmq/ca.pem https://localhost:15671/api/overview
```

### Reference APIs

```bash
# Test HTTPS connection
curl --cacert ~/.config/vault/certs/reference-api/ca.pem https://localhost:8443/health

# Test HTTP connection (dual-mode)
curl http://localhost:8000/health
```

## Troubleshooting

### Certificate Not Found

**Symptom:** Service fails to start with "certificate not found" error.

**Solution:**
```bash
# Generate certificates
./scripts/generate-certificates.sh

# Restart service
docker compose restart <service>
```

### Certificate Expired

**Symptom:** Connections fail with "certificate has expired" error.

**Solution:**
```bash
# Check expiration status
./scripts/check-cert-expiration.sh

# Renew expired certificate
./scripts/auto-renew-certificates.sh --service <service>

# Restart service
docker compose restart <service>
```

### Vault PKI Not Initialized

**Symptom:** Certificate generation fails with "role not found" error.

**Solution:**
```bash
# Re-run vault bootstrap
./devstack vault-bootstrap

# Generate certificates
./scripts/generate-certificates.sh
```

### Permission Denied

**Symptom:** "Permission denied" when accessing private key.

**Solution:**
```bash
# Fix permissions
chmod 600 ~/.config/vault/certs/*/key.pem
chmod 600 ~/.config/vault/certs/*/*.key

# Verify
ls -la ~/.config/vault/certs/*/
```

### Self-Signed Certificate Warning

**Symptom:** Clients show "self-signed certificate" warning.

**Solution:**

This is expected for development environments. To trust certificates:

**macOS:**
```bash
# Add CA to system keychain
sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain \
    ~/.config/vault/ca/ca.pem
```

**Linux:**
```bash
# Add CA to system trust store
sudo cp ~/.config/vault/ca/ca.pem /usr/local/share/ca-certificates/devstack-ca.crt
sudo update-ca-certificates
```

**Application-Specific:**
```bash
# Add --cacert flag
curl --cacert ~/.config/vault/certs/<service>/ca.pem https://...

# Or set environment variable
export REQUESTS_CA_BUNDLE=~/.config/vault/ca/ca.pem
```

## Security Best Practices

### Development Environment

✅ **Current Configuration (Dual-Mode):**
- Services accept both TLS and non-TLS
- Flexible for development and testing
- TLS certificates available when needed
- Easy migration to production

### Production Environment

🔒 **Recommended Changes for Production:**

1. **Enforce TLS-Only:**
   ```bash
   # PostgreSQL: Set ssl=on and reject non-SSL
   POSTGRES_SSL_MODE=require

   # MySQL: Require secure transport
   MYSQL_REQUIRE_SECURE_TRANSPORT=ON

   # MongoDB: Require TLS
   MONGODB_TLS_MODE=requireTLS

   # Redis: Disable non-TLS port
   REDIS_ENABLE_NON_TLS=false
   ```

2. **Enable Certificate Validation:**
   - Use production CA (not self-signed)
   - Enable certificate validation in clients
   - Implement certificate pinning

3. **Rotate Credentials:**
   - Use Vault dynamic secrets
   - Implement credential rotation
   - Short-lived certificates (30 days)

4. **Monitor and Alert:**
   - Setup monitoring for certificate expiration
   - Alert on renewal failures
   - Track certificate usage

5. **Backup Strategy:**
   - Regular backups of `~/.config/vault/`
   - Secure storage of Root CA
   - Disaster recovery procedures

## Integration with Services

### Vault Integration

All certificates are issued by Vault PKI:

```bash
# View Vault PKI configuration
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# List PKI roles
vault list pki_int/roles

# View role details
vault read pki_int/roles/postgres-role

# Issue certificate manually
vault write pki_int/issue/postgres-role \
    common_name="postgres.dev-services.local" \
    ttl="8760h"
```

### Service Init Scripts

Services automatically load certificates via init scripts:

**AppRole Pattern** (`configs/<service>/scripts/init-approle.sh`):
```bash
# Fetch TLS certificates if enabled
if [ "${SERVICE_ENABLE_TLS:-false}" = "true" ]; then
    export SERVICE_CERT_FILE="/certs/cert.pem"
    export SERVICE_KEY_FILE="/certs/key.pem"
    export SERVICE_CA_FILE="/certs/ca.pem"
fi
```

**Volume Mounts** (docker-compose.yml):
```yaml
volumes:
  - ~/.config/vault/certs/postgres:/certs:ro
```

## Compliance and Auditing

### Certificate Inventory

Generate certificate inventory report:

```bash
# List all certificates with expiration
./scripts/check-cert-expiration.sh --json > cert-inventory.json

# Parse with jq
jq '.certificates[] | {service, status, message}' cert-inventory.json
```

### Audit Logs

Certificate operations are logged:

**Renewal Log:** `~/.config/vault/cert-renewal.log`
```
[2025-11-17 02:00:01] Checking postgres...
[2025-11-17 02:00:02] ✓ Certificate for postgres valid for 345 days
```

**Vault Audit Log:** (if enabled)
```bash
# Enable Vault audit logging
vault audit enable file file_path=/var/log/vault_audit.log

# View certificate issuance
grep "pki_int/issue" /var/log/vault_audit.log
```

## References

- [Vault PKI Documentation](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [docs/VAULT.md](./VAULT.md) - Vault PKI setup and configuration
- [docs/SERVICES.md](./SERVICES.md) - Service-specific TLS configuration
- [.env.example](./../.env.example) - TLS environment variables

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review service logs: `docker compose logs <service>`
3. Check certificate status: `./scripts/check-cert-expiration.sh`
4. Review documentation: `docs/VAULT.md`
5. Open GitHub issue with details
