# Vault Security Best Practices

## Table of Contents
- [Overview](#overview)
- [Critical Security Warning](#critical-security-warning)
- [Development vs Production](#development-vs-production)
- [AppRole Authentication](#approle-authentication)
- [Secure Token Storage](#secure-token-storage)
- [Backup and Recovery](#backup-and-recovery)
- [Token Rotation](#token-rotation)
- [Network Security](#network-security)
- [Monitoring and Auditing](#monitoring-and-auditing)

## Overview

This document outlines security best practices for HashiCorp Vault in the devstack-core environment. The default configuration is optimized for **local development only** and should never be used in production environments.

## Critical Security Warning

### DO NOT USE ROOT TOKEN IN PRODUCTION

The current setup uses the Vault root token for simplicity in local development. This is **EXTREMELY DANGEROUS** in production because:

- Root tokens have unlimited privileges across all Vault operations
- Root tokens never expire by default
- Compromise of a root token = complete system compromise
- No audit trail for individual operations
- Cannot be revoked without re-initializing Vault

**Current Development Configuration:**
```bash
# .env file (DEVELOPMENT ONLY)
VAULT_TOKEN=$(cat ~/.config/vault/root-token)
```

**⚠️ NEVER commit `.env` with real tokens to version control**
**⚠️ NEVER use root tokens in production applications**
**⚠️ NEVER share root tokens between team members**

## Development vs Production

### Development Environment (Current Setup)

The devstack-core environment is configured for local development with:

- Root token stored in `~/.config/vault/root-token`
- Auto-unseal on container start
- File backend for storage
- Unencrypted network communication (HTTP)
- Single-node deployment

**This is acceptable ONLY for:**
- Local development on your personal machine
- Testing and experimentation
- Learning Vault features
- Rapid prototyping

### Production Environment Requirements

A production Vault deployment must have:

1. **No root token usage** - use AppRole, Kubernetes auth, or other auth methods
2. **Auto-unseal with cloud KMS** (AWS KMS, Azure Key Vault, GCP KMS)
3. **TLS/HTTPS everywhere** with valid certificates
4. **High availability** (3+ node cluster with Raft or Consul storage)
5. **Audit logging** enabled and monitored
6. **Network isolation** (private networks, firewalls)
7. **Regular backups** with encrypted snapshots
8. **Access control policies** with least privilege
9. **MFA required** for sensitive operations
10. **Secrets rotation** policies enforced

## AppRole Authentication

AppRole is the recommended authentication method for applications accessing Vault.

### Setting Up AppRole for Reference API

#### Step 1: Create a Policy for the Application

Create a policy file `reference-api-policy.hcl`:

```hcl
# Allow reading database credentials
path "secret/data/postgres" {
  capabilities = ["read"]
}

path "secret/data/mysql" {
  capabilities = ["read"]
}

path "secret/data/mongodb" {
  capabilities = ["read"]
}

path "secret/data/redis-1" {
  capabilities = ["read"]
}

path "secret/data/rabbitmq" {
  capabilities = ["read"]
}

# Allow reading PKI certificates
path "pki/cert/ca" {
  capabilities = ["read"]
}

path "pki/issue/reference-api" {
  capabilities = ["create", "update"]
}

# Deny access to other secrets
path "secret/data/*" {
  capabilities = ["deny"]
}
```

#### Step 2: Apply the Policy

```bash
# Set Vault environment
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Write the policy
vault policy write reference-api reference-api-policy.hcl
```

#### Step 3: Enable AppRole Auth

```bash
# Enable AppRole authentication method
vault auth enable approle

# Create a role for the reference API
vault write auth/approle/role/reference-api \
    token_policies="reference-api" \
    token_ttl=1h \
    token_max_ttl=4h \
    bind_secret_id=true \
    secret_id_ttl=0
```

#### Step 4: Get Role ID and Secret ID

```bash
# Get Role ID (can be public)
vault read auth/approle/role/reference-api/role-id

# Example output:
# Key        Value
# ---        -----
# role_id    a1b2c3d4-e5f6-7g8h-9i0j-k1l2m3n4o5p6

# Generate Secret ID (must be kept secret)
vault write -f auth/approle/role/reference-api/secret-id

# Example output:
# Key                   Value
# ---                   -----
# secret_id             z9y8x7w6-v5u4-t3s2-r1q0-p9o8n7m6l5k4
# secret_id_accessor    a1b2c3d4-e5f6-7g8h-9i0j-k1l2m3n4o5p6
# secret_id_ttl         0s
```

#### Step 5: Update Application to Use AppRole

**Python Example (FastAPI):**

```python
import os
import hvac

def get_vault_client():
    """Get authenticated Vault client using AppRole"""
    role_id = os.environ["VAULT_ROLE_ID"]
    secret_id = os.environ["VAULT_SECRET_ID"]
    vault_addr = os.environ.get("VAULT_ADDR", "http://vault:8200")

    client = hvac.Client(url=vault_addr)

    # Authenticate with AppRole
    response = client.auth.approle.login(
        role_id=role_id,
        secret_id=secret_id,
    )

    # Token is automatically set in client
    return client

def get_postgres_credentials():
    """Fetch PostgreSQL credentials from Vault"""
    client = get_vault_client()

    secret = client.secrets.kv.v2.read_secret_version(
        path="postgres",
        mount_point="secret"
    )

    return {
        "user": secret["data"]["data"]["username"],
        "password": secret["data"]["data"]["password"],
        "database": secret["data"]["data"]["database"],
    }
```

#### Step 6: Update Environment Variables

Instead of using `VAULT_TOKEN`, use AppRole credentials:

```bash
# .env (DO NOT commit to git)
VAULT_ROLE_ID=a1b2c3d4-e5f6-7g8h-9i0j-k1l2m3n4o5p6
VAULT_SECRET_ID=z9y8x7w6-v5u4-t3s2-r1q0-p9o8n7m6l5k4
```

### Advantages of AppRole

1. **Limited permissions** - only access to specified secrets
2. **Time-limited tokens** - automatic expiration
3. **Renewable tokens** - applications can refresh before expiry
4. **Revocable** - can be disabled without affecting other apps
5. **Auditable** - track which application accessed what
6. **No root token exposure** - applications never see root token

## Secure Token Storage

### DO NOT Store Tokens in .env Files

**Bad (Current Development Setup):**
```bash
# .env - NEVER use this in production
VAULT_TOKEN=hvs.CAESIJ1wv8...
```

**Better - Use Environment Variables at Runtime:**
```bash
# Fetch from secure storage at container start
VAULT_TOKEN=$(security find-generic-password -s vault-token -w)
```

**Best - Use AppRole (No Token Storage):**
```bash
# Only store role_id and secret_id
VAULT_ROLE_ID=a1b2c3d4-...
VAULT_SECRET_ID=z9y8x7w6-...
```

### macOS Keychain Integration

Store Vault tokens securely in macOS Keychain:

```bash
# Store token in keychain
security add-generic-password \
    -a "${USER}" \
    -s "vault-root-token" \
    -w "$(cat ~/.config/vault/root-token)"

# Retrieve token
VAULT_TOKEN=$(security find-generic-password \
    -a "${USER}" \
    -s "vault-root-token" \
    -w)
```

### Kubernetes Secrets (Production)

For Kubernetes deployments:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: vault-approle
  namespace: production
type: Opaque
data:
  role-id: <base64-encoded-role-id>
  secret-id: <base64-encoded-secret-id>
```

## Backup and Recovery

### What to Back Up

1. **Unseal Keys** - stored in `~/.config/vault/keys.json`
2. **Root Token** - stored in `~/.config/vault/root-token`
3. **Vault Data** - Docker volume `vault_data`
4. **Policies** - export all custom policies
5. **Configuration** - `configs/vault/` directory

### Backup Procedures

#### Manual Backup

```bash
# Create backup directory with timestamp
BACKUP_DIR="backups/vault-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Backup unseal keys (CRITICAL)
cp ~/.config/vault/keys.json "$BACKUP_DIR/"
chmod 600 "$BACKUP_DIR/keys.json"

# Backup root token (CRITICAL)
cp ~/.config/vault/root-token "$BACKUP_DIR/"
chmod 600 "$BACKUP_DIR/root-token"

# Backup CA certificates
cp -r ~/.config/vault/ca "$BACKUP_DIR/"

# Backup Vault data volume
docker run --rm \
    -v vault_data:/data \
    -v "$PWD/$BACKUP_DIR":/backup \
    alpine tar czf /backup/vault-data.tar.gz -C /data .

# Encrypt the backup
tar czf - "$BACKUP_DIR" | \
    gpg --symmetric --cipher-algo AES256 \
    -o "$BACKUP_DIR.tar.gz.gpg"

# Securely delete unencrypted backup
rm -rf "$BACKUP_DIR"

echo "Encrypted backup created: $BACKUP_DIR.tar.gz.gpg"
```

#### Automated Backup Script

Create `scripts/backup-vault.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="backups/vault-$(date +%Y%m%d_%H%M%S)"
BACKUP_RETENTION_DAYS=30

# Create encrypted backup (see manual backup above)
# ...

# Clean up old backups
find backups/ -name "vault-*.tar.gz.gpg" \
    -mtime +${BACKUP_RETENTION_DAYS} \
    -delete

echo "Backup completed and old backups cleaned"
```

#### Backup Schedule

**Recommended backup frequency:**
- **Unseal keys**: Immediately after initialization, store in multiple secure locations
- **Vault data**: Daily for development, hourly for production
- **Policies**: After every change
- **Off-site backup**: Weekly encrypted backups to cloud storage

### Recovery Procedures

#### Restore from Backup

```bash
# Decrypt backup
gpg --decrypt backups/vault-20250123_143022.tar.gz.gpg | \
    tar xzf -

# Restore unseal keys
cp backups/vault-20250123_143022/keys.json ~/.config/vault/

# Restore root token
cp backups/vault-20250123_143022/root-token ~/.config/vault/

# Stop Vault container
docker compose stop vault

# Restore data volume
docker run --rm \
    -v vault_data:/data \
    -v "$PWD/backups/vault-20250123_143022":/backup \
    alpine sh -c "cd /data && tar xzf /backup/vault-data.tar.gz"

# Start Vault
docker compose start vault
```

## Token Rotation

### Root Token Rotation

**Why rotate?**
- Limit exposure window if token is compromised
- Compliance requirements
- Best security practice

**How to rotate root token:**

```bash
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Generate new root token
vault token create -policy=root -period=768h

# Output:
# Key                  Value
# ---                  -----
# token                hvs.CAESIJ...
# token_accessor       aBcDeFgH...
# token_duration       768h
# token_renewable      true
# token_policies       ["root"]

# Update stored token
echo "hvs.CAESIJ..." > ~/.config/vault/root-token
chmod 600 ~/.config/vault/root-token

# Revoke old token
vault token revoke $(cat ~/.config/vault/root-token.old)
```

### Application Token Rotation

With AppRole, tokens automatically rotate:

```python
def renew_vault_token(client):
    """Renew Vault token before expiration"""
    try:
        client.auth.token.renew_self()
    except hvac.exceptions.InvalidRequest:
        # Token expired, re-authenticate
        client = get_vault_client()
    return client
```

## Network Security

### Development (Current)

- Vault accessible on `http://localhost:8200`
- No TLS encryption
- No network isolation

**Acceptable ONLY for local development**

### Production Requirements

#### Enable TLS

```hcl
# vault-config.hcl
listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "/vault/certs/vault.crt"
  tls_key_file  = "/vault/certs/vault.key"
}
```

#### Network Isolation

```yaml
# docker-compose-production.yml
services:
  vault:
    networks:
      - vault-network  # Isolated network
    ports:
      - "127.0.0.1:8200:8200"  # Only localhost access
```

#### Firewall Rules

```bash
# Allow only from application network
iptables -A INPUT -p tcp --dport 8200 -s 172.20.0.0/16 -j ACCEPT
iptables -A INPUT -p tcp --dport 8200 -j DROP
```

## Monitoring and Auditing

### Enable Audit Logging

```bash
# Enable file audit backend
vault audit enable file file_path=/vault/logs/audit.log

# Enable syslog audit backend (production)
vault audit enable syslog tag="vault" facility="AUTH"
```

### Monitor Vault Metrics

Prometheus metrics are exposed at `http://localhost:8200/v1/sys/metrics`:

- `vault_core_unsealed` - Vault seal status
- `vault_runtime_alloc_bytes` - Memory usage
- `vault_runtime_num_goroutines` - Concurrent operations
- `vault_token_creation` - Token creation rate
- `vault_token_revocation` - Token revocation rate

### Alert on Security Events

```yaml
# Prometheus alert rules
groups:
  - name: vault
    rules:
      - alert: VaultSealed
        expr: vault_core_unsealed == 0
        for: 1m
        annotations:
          summary: "Vault is sealed"

      - alert: VaultHighTokenCreation
        expr: rate(vault_token_creation[5m]) > 100
        annotations:
          summary: "Unusual token creation rate"
```

## Security Checklist

### Development Environment

- [x] Root token stored in `~/.config/vault/root-token`
- [x] Auto-unseal configured
- [x] Backup script created
- [ ] Test AppRole authentication
- [ ] Document token rotation procedure
- [ ] Set up audit logging

### Production Environment (Before Deployment)

- [ ] Remove all root token references
- [ ] Implement AppRole for all applications
- [ ] Enable TLS with valid certificates
- [ ] Configure high availability (3+ nodes)
- [ ] Enable audit logging
- [ ] Set up automated encrypted backups
- [ ] Configure network isolation
- [ ] Implement monitoring and alerting
- [ ] Test disaster recovery procedures
- [ ] Document access control policies
- [ ] Train team on security procedures

## Additional Resources

- [HashiCorp Vault Production Hardening](https://developer.hashicorp.com/vault/tutorials/operations/production-hardening)
- [AppRole Auth Method](https://developer.hashicorp.com/vault/docs/auth/approle)
- [Vault Security Best Practices](https://developer.hashicorp.com/vault/tutorials/recommended-patterns/production-hardening)
- [Disaster Recovery](https://developer.hashicorp.com/vault/tutorials/operations/backup-and-restore)

## Support

For questions or security concerns:
- Open an issue in the GitHub repository
- Review the official HashiCorp Vault documentation
- Consult with your security team before production deployment
