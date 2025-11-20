# TLS-Configuration

## Table of Contents

- [Overview](#overview)
- [Enabling TLS Per Service](#enabling-tls-per-service)
  - [Enable TLS in Environment Variables](#enable-tls-in-environment-variables)
  - [Service-Specific Configuration](#service-specific-configuration)
- [Vault PKI Setup](#vault-pki-setup)
  - [Root CA Configuration](#root-ca-configuration)
  - [Intermediate CA Configuration](#intermediate-ca-configuration)
  - [Service Roles](#service-roles)
- [Certificate Generation](#certificate-generation)
  - [Automated Generation](#automated-generation)
  - [Manual Certificate Generation](#manual-certificate-generation)
  - [Certificate Properties](#certificate-properties)
- [Certificate Locations](#certificate-locations)
  - [Directory Structure](#directory-structure)
  - [File Permissions](#file-permissions)
- [Trusting Self-Signed CA on macOS](#trusting-self-signed-ca-on-macos)
  - [Import CA Certificate](#import-ca-certificate)
  - [Trust Settings](#trust-settings)
  - [Verify Trust](#verify-trust)
- [Dual-Mode (TLS + Non-TLS)](#dual-mode-tls-non-tls)
  - [Why Dual-Mode](#why-dual-mode)
  - [Configuration Examples](#configuration-examples)
  - [Migration Strategy](#migration-strategy)
- [Certificate Renewal](#certificate-renewal)
  - [Check Expiration](#check-expiration)
  - [Automated Renewal](#automated-renewal)
  - [Manual Renewal](#manual-renewal)
- [Troubleshooting TLS Issues](#troubleshooting-tls-issues)
  - [Certificate Validation Errors](#certificate-validation-errors)
  - [Connection Refused](#connection-refused)
  - [Expired Certificates](#expired-certificates)
  - [Permission Issues](#permission-issues)
- [Related Pages](#related-pages)

## Overview

The devstack-core environment uses HashiCorp Vault's PKI secrets engine to manage TLS certificates for all services. This provides a two-tier PKI hierarchy with automated certificate generation and renewal.

**PKI Architecture:**
```
Root CA (pki) - 10 years
└── Intermediate CA (pki_int) - 5 years
    └── Service Certificates - 1 year
        ├── postgres
        ├── mysql
        ├── mongodb
        ├── redis-1, redis-2, redis-3
        ├── rabbitmq
        └── ... other services
```

**TLS Benefits:**
- Encrypted communication between services
- Authentication via certificates
- Protection against MITM attacks
- Compliance requirements

## Enabling TLS Per Service

### Enable TLS in Environment Variables

**Edit `.env` file:**

```bash
# PostgreSQL TLS
POSTGRES_ENABLE_TLS=true
POSTGRES_TLS_PORT=5432  # Same port, dual-mode

# MySQL TLS
MYSQL_ENABLE_TLS=true
MYSQL_TLS_PORT=3306

# MongoDB TLS
MONGODB_ENABLE_TLS=true
MONGODB_TLS_PORT=27017

# Redis TLS (separate ports)
REDIS_ENABLE_TLS=true
REDIS_1_TLS_PORT=6380  # Non-TLS on 6379
REDIS_2_TLS_PORT=6380
REDIS_3_TLS_PORT=6380

# RabbitMQ TLS
RABBITMQ_ENABLE_TLS=true
RABBITMQ_TLS_PORT=5671  # Non-TLS on 5672
```

### Service-Specific Configuration

**PostgreSQL TLS:**

```conf
# configs/postgres/postgresql.conf
ssl = on
ssl_cert_file = '/certs/cert.pem'
ssl_key_file = '/certs/key.pem'
ssl_ca_file = '/certs/ca.pem'

# Allow both TLS and non-TLS (dual-mode)
# In pg_hba.conf:
hostssl all all 0.0.0.0/0 scram-sha-256  # TLS connections
host    all all 0.0.0.0/0 scram-sha-256  # Non-TLS connections
```

**MySQL TLS:**

```ini
# configs/mysql/my.cnf
[mysqld]
ssl-ca = /certs/ca.pem
ssl-cert = /certs/cert.pem
ssl-key = /certs/key.pem
require_secure_transport = OFF  # Dual-mode: allow both
```

**MongoDB TLS:**

```yaml
# configs/mongodb/mongod.conf
net:
  tls:
    mode: preferTLS  # Dual-mode
    certificateKeyFile: /certs/combined.pem
    CAFile: /certs/ca.pem
```

**Redis TLS:**

```conf
# configs/redis/redis.conf
port 6379              # Non-TLS port
tls-port 6380          # TLS port
tls-cert-file /certs/cert.pem
tls-key-file /certs/key.pem
tls-ca-cert-file /certs/ca.pem
tls-auth-clients no    # Don't require client certs (yet)
```

**RabbitMQ TLS:**

```conf
# configs/rabbitmq/rabbitmq.conf
listeners.tcp.default = 5672
listeners.ssl.default = 5671
ssl_options.cacertfile = /certs/ca.pem
ssl_options.certfile = /certs/cert.pem
ssl_options.keyfile = /certs/key.pem
ssl_options.verify = verify_none
ssl_options.fail_if_no_peer_cert = false
```

## Vault PKI Setup

### Root CA Configuration

The root CA is created during `vault-bootstrap`:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Enable PKI secrets engine for root CA
vault secrets enable -path=pki pki

# Tune max lease TTL to 10 years
vault secrets tune -max-lease-ttl=87600h pki

# Generate root CA certificate
vault write pki/root/generate/internal \
  common_name="DevStack Core Root CA" \
  ttl=87600h \
  exclude_cn_from_sans=true

# Configure CA and CRL URLs
vault write pki/config/urls \
  issuing_certificates="http://vault:8200/v1/pki/ca" \
  crl_distribution_points="http://vault:8200/v1/pki/crl"
```

### Intermediate CA Configuration

```bash
# Enable PKI secrets engine for intermediate CA
vault secrets enable -path=pki_int pki

# Tune max lease TTL to 5 years
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate intermediate CSR
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="DevStack Core Intermediate CA" \
  ttl=43800h \
  exclude_cn_from_sans=true \
  | jq -r '.data.csr' > pki_int.csr

# Sign intermediate CSR with root CA
vault write -format=json pki/root/sign-intermediate \
  csr=@pki_int.csr \
  format=pem_bundle \
  ttl=43800h \
  | jq -r '.data.certificate' > intermediate.cert.pem

# Import signed certificate
vault write pki_int/intermediate/set-signed \
  certificate=@intermediate.cert.pem

# Configure URLs
vault write pki_int/config/urls \
  issuing_certificates="http://vault:8200/v1/pki_int/ca" \
  crl_distribution_points="http://vault:8200/v1/pki_int/crl"
```

### Service Roles

Create roles for each service:

```bash
# PostgreSQL role
vault write pki_int/roles/postgres-role \
  allowed_domains=postgres,localhost \
  allow_subdomains=false \
  max_ttl=8760h \
  ttl=8760h \
  generate_lease=true

# MySQL role
vault write pki_int/roles/mysql-role \
  allowed_domains=mysql,localhost \
  max_ttl=8760h

# Redis role
vault write pki_int/roles/redis-role \
  allowed_domains=redis-1,redis-2,redis-3,localhost \
  allow_subdomains=false \
  max_ttl=8760h

# RabbitMQ role
vault write pki_int/roles/rabbitmq-role \
  allowed_domains=rabbitmq,localhost \
  max_ttl=8760h

# MongoDB role
vault write pki_int/roles/mongodb-role \
  allowed_domains=mongodb,localhost \
  max_ttl=8760h
```

## Certificate Generation

### Automated Generation

Use the `generate-certificates.sh` script:

```bash
# Generate certificates for all services
./scripts/generate-certificates.sh

# Output:
# Generating certificates from Vault PKI...
# ✓ postgres certificate generated
# ✓ mysql certificate generated
# ✓ mongodb certificate generated
# ✓ redis-1 certificate generated
# ✓ redis-2 certificate generated
# ✓ redis-3 certificate generated
# ✓ rabbitmq certificate generated
#
# Certificates saved to ~/.config/vault/certs/
```

**Script contents:**

```bash
#!/bin/bash
set -e

export VAULT_ADDR=${VAULT_ADDR:-http://localhost:8200}
export VAULT_TOKEN=${VAULT_TOKEN:-$(cat ~/.config/vault/root-token)}

CERT_DIR=~/.config/vault/certs

# Services to generate certificates for
SERVICES="postgres mysql mongodb redis-1 redis-2 redis-3 rabbitmq"

for service in $SERVICES; do
  echo "Generating certificate for $service..."

  mkdir -p $CERT_DIR/$service

  # Generate certificate from Vault
  vault write -format=json pki_int/issue/${service}-role \
    common_name=$service \
    ttl=8760h \
    format=pem > /tmp/${service}-cert.json

  # Extract certificate, key, and CA
  jq -r '.data.certificate' < /tmp/${service}-cert.json > $CERT_DIR/$service/cert.pem
  jq -r '.data.private_key' < /tmp/${service}-cert.json > $CERT_DIR/$service/key.pem
  jq -r '.data.ca_chain[]' < /tmp/${service}-cert.json > $CERT_DIR/$service/ca.pem

  # Set permissions
  chmod 600 $CERT_DIR/$service/key.pem
  chmod 644 $CERT_DIR/$service/cert.pem
  chmod 644 $CERT_DIR/$service/ca.pem

  # For MongoDB, create combined file
  if [ "$service" = "mongodb" ]; then
    cat $CERT_DIR/$service/cert.pem $CERT_DIR/$service/key.pem > $CERT_DIR/$service/combined.pem
    chmod 600 $CERT_DIR/$service/combined.pem
  fi

  rm /tmp/${service}-cert.json
done

# Copy CA certificate to shared location
mkdir -p $CERT_DIR/../ca
vault read -field=certificate pki/cert/ca > $CERT_DIR/../ca/ca.pem
vault read -field=ca_chain pki_int/cert/ca_chain > $CERT_DIR/../ca/ca-chain.pem

echo "Certificate generation complete!"
```

### Manual Certificate Generation

**Generate certificate for specific service:**

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Generate PostgreSQL certificate
vault write pki_int/issue/postgres-role \
  common_name=postgres \
  ttl=8760h \
  format=pem

# Output includes:
# certificate: -----BEGIN CERTIFICATE-----...
# private_key: -----BEGIN RSA PRIVATE KEY-----...
# ca_chain: -----BEGIN CERTIFICATE-----...
```

**Save to files:**

```bash
# Generate and save
vault write -format=json pki_int/issue/postgres-role \
  common_name=postgres \
  ttl=8760h > postgres-cert.json

# Extract components
jq -r '.data.certificate' < postgres-cert.json > cert.pem
jq -r '.data.private_key' < postgres-cert.json > key.pem
jq -r '.data.ca_chain[]' < postgres-cert.json > ca.pem

# Set permissions
chmod 600 key.pem
chmod 644 cert.pem ca.pem
```

### Certificate Properties

**View certificate details:**

```bash
# Inspect certificate
openssl x509 -in ~/.config/vault/certs/postgres/cert.pem -text -noout

# Key information:
# Subject: CN=postgres
# Issuer: CN=DevStack Core Intermediate CA
# Validity:
#   Not Before: Jan 1 00:00:00 2024 GMT
#   Not After:  Jan 1 00:00:00 2025 GMT
# Subject Alternative Names:
#   DNS: postgres
#   DNS: localhost
```

**Verify certificate chain:**

```bash
# Verify certificate against CA
openssl verify \
  -CAfile ~/.config/vault/ca/ca-chain.pem \
  ~/.config/vault/certs/postgres/cert.pem

# Output: OK
```

## Certificate Locations

### Directory Structure

```
~/.config/vault/
├── keys.json                      # Vault unseal keys
├── root-token                     # Vault root token
├── ca/                            # CA certificates
│   ├── ca.pem                     # Root CA
│   └── ca-chain.pem               # Full chain (root + intermediate)
└── certs/                         # Service certificates
    ├── postgres/
    │   ├── cert.pem               # Server certificate
    │   ├── key.pem                # Private key
    │   └── ca.pem                 # CA certificate
    ├── mysql/
    │   ├── cert.pem
    │   ├── key.pem
    │   └── ca.pem
    ├── mongodb/
    │   ├── cert.pem
    │   ├── key.pem
    │   ├── ca.pem
    │   └── combined.pem           # cert + key combined
    ├── redis-1/
    │   ├── cert.pem
    │   ├── key.pem
    │   └── ca.pem
    ├── redis-2/
    ├── redis-3/
    └── rabbitmq/
```

### File Permissions

**Correct permissions:**

```bash
# Private keys: 600 (read/write for owner only)
chmod 600 ~/.config/vault/certs/*/key.pem

# Certificates: 644 (readable by all)
chmod 644 ~/.config/vault/certs/*/cert.pem
chmod 644 ~/.config/vault/certs/*/ca.pem

# Directory: 755
chmod 755 ~/.config/vault/certs/*

# Verify permissions
ls -la ~/.config/vault/certs/postgres/
# -rw-r--r-- cert.pem
# -rw------- key.pem
# -rw-r--r-- ca.pem
```

## Trusting Self-Signed CA on macOS

### Import CA Certificate

**Add to Keychain:**

```bash
# Import root CA to System keychain
sudo security add-trusted-cert \
  -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  ~/.config/vault/ca/ca.pem

# Or to user keychain
security add-trusted-cert \
  -d -r trustRoot \
  -k ~/Library/Keychains/login.keychain \
  ~/.config/vault/ca/ca.pem
```

**Via Keychain Access app:**

1. Open Keychain Access
2. File → Import Items
3. Select `~/.config/vault/ca/ca.pem`
4. Choose "System" or "login" keychain
5. Find "DevStack Core Root CA"
6. Double-click → Trust → "Always Trust"

### Trust Settings

**Verify trust via CLI:**

```bash
# Check certificate trust
security verify-cert -c ~/.config/vault/ca/ca.pem

# View certificate
security find-certificate -c "DevStack Core Root CA" -p | openssl x509 -text -noout
```

### Verify Trust

**Test TLS connection:**

```bash
# Connect to PostgreSQL with TLS
docker exec dev-postgres psql \
  "postgresql://devuser@localhost/devdb?sslmode=require"

# Connect to MySQL with TLS
docker exec dev-mysql mysql \
  -u devuser -p \
  --ssl-mode=REQUIRED

# Test with curl
curl --cacert ~/.config/vault/ca/ca.pem https://localhost:8443/health
```

## Dual-Mode (TLS + Non-TLS)

### Why Dual-Mode

**Benefits of dual-mode:**
- Gradual TLS adoption
- Backward compatibility
- Easier troubleshooting
- Zero downtime migration

**Use cases:**
- Development environment (this project)
- Migration period in production
- Mixed client support

### Configuration Examples

**PostgreSQL dual-mode:**

```conf
# postgresql.conf
ssl = on  # Enable SSL

# pg_hba.conf
# Accept both TLS and non-TLS
hostssl all all 0.0.0.0/0 scram-sha-256  # TLS required
host    all all 0.0.0.0/0 scram-sha-256  # TLS optional

# Clients can connect with or without TLS:
# psql "postgresql://user@host/db"  # No TLS
# psql "postgresql://user@host/db?sslmode=require"  # TLS required
```

**Redis dual-mode:**

```conf
# redis.conf
port 6379      # Non-TLS port
tls-port 6380  # TLS port

# Both ports active simultaneously
# Clients choose which port to use
```

**RabbitMQ dual-mode:**

```conf
# rabbitmq.conf
listeners.tcp.default = 5672   # Non-TLS
listeners.ssl.default = 5671   # TLS

# Management UI
management.tcp.port = 15672    # Non-TLS
management.ssl.port = 15671    # TLS
```

### Migration Strategy

**Phased TLS rollout:**

```bash
# Phase 1: Enable TLS, keep non-TLS (dual-mode)
POSTGRES_ENABLE_TLS=true
# Accept both connections

# Phase 2: Update applications to use TLS
# Test thoroughly

# Phase 3: Enforce TLS-only
# In pg_hba.conf, remove 'host' lines, keep only 'hostssl'
hostssl all all 0.0.0.0/0 scram-sha-256

# In postgresql.conf
ssl = on
ssl_prefer_server_ciphers = on
```

## Certificate Renewal

### Check Expiration

**Check certificate expiration:**

```bash
# Check expiration date
openssl x509 -in ~/.config/vault/certs/postgres/cert.pem -noout -enddate

# Output: notAfter=Jan 1 00:00:00 2025 GMT

# Check if expired
openssl x509 -in ~/.config/vault/certs/postgres/cert.pem -noout -checkend 0
# Returns 0 if valid, 1 if expired

# Check expiration in 30 days
openssl x509 -in ~/.config/vault/certs/postgres/cert.pem -noout -checkend 2592000
```

**Check all certificates:**

```bash
for cert in ~/.config/vault/certs/*/cert.pem; do
  service=$(dirname $cert | xargs basename)
  expiry=$(openssl x509 -in $cert -noout -enddate | cut -d= -f2)
  echo "$service: $expiry"
done
```

### Automated Renewal

**Create renewal script:**

```bash
#!/bin/bash
# scripts/renew-certificates.sh

CERT_DIR=~/.config/vault/certs
WARN_DAYS=30

for cert_file in $CERT_DIR/*/cert.pem; do
  service=$(dirname $cert_file | xargs basename)

  # Check if expiring in 30 days
  if ! openssl x509 -in $cert_file -noout -checkend $((WARN_DAYS * 86400)); then
    echo "Certificate for $service expiring soon, renewing..."

    # Regenerate certificate
    vault write -format=json pki_int/issue/${service}-role \
      common_name=$service \
      ttl=8760h > /tmp/${service}-cert.json

    # Extract and save
    jq -r '.data.certificate' < /tmp/${service}-cert.json > $CERT_DIR/$service/cert.pem
    jq -r '.data.private_key' < /tmp/${service}-cert.json > $CERT_DIR/$service/key.pem

    # Restart service
    docker compose restart $service

    echo "Certificate for $service renewed"
  fi
done
```

**Schedule renewal:**

```bash
# crontab
# Check daily, renew if needed
0 2 * * * /path/to/scripts/renew-certificates.sh
```

### Manual Renewal

**Renew specific certificate:**

```bash
# Regenerate PostgreSQL certificate
./scripts/generate-certificates.sh

# Or manually
vault write -format=json pki_int/issue/postgres-role \
  common_name=postgres \
  ttl=8760h > /tmp/postgres-cert.json

jq -r '.data.certificate' < /tmp/postgres-cert.json > ~/.config/vault/certs/postgres/cert.pem
jq -r '.data.private_key' < /tmp/postgres-cert.json > ~/.config/vault/certs/postgres/key.pem

chmod 600 ~/.config/vault/certs/postgres/key.pem

# Restart service
docker compose restart postgres
```

## Troubleshooting TLS Issues

### Certificate Validation Errors

**Error: certificate verify failed**

```bash
# Check certificate validity
openssl x509 -in cert.pem -text -noout

# Verify certificate chain
openssl verify -CAfile ca.pem cert.pem

# Check certificate dates
openssl x509 -in cert.pem -noout -dates

# Regenerate if invalid
./scripts/generate-certificates.sh
```

### Connection Refused

**Error: connection refused on TLS port**

```bash
# Check if service is listening on TLS port
docker exec dev-postgres netstat -tuln | grep 5432
docker exec dev-redis-1 netstat -tuln | grep 6380

# Check TLS is enabled in config
docker exec dev-postgres cat /etc/postgresql/postgresql.conf | grep ssl

# Check certificates are mounted
docker exec dev-postgres ls -la /certs/

# Restart service
docker compose restart postgres
```

### Expired Certificates

**Error: certificate has expired**

```bash
# Check expiration
openssl x509 -in ~/.config/vault/certs/postgres/cert.pem -noout -enddate

# Renew certificate
vault write -format=json pki_int/issue/postgres-role \
  common_name=postgres \
  ttl=8760h > /tmp/postgres-cert.json

# Extract and save
jq -r '.data.certificate' < /tmp/postgres-cert.json > ~/.config/vault/certs/postgres/cert.pem
jq -r '.data.private_key' < /tmp/postgres-cert.json > ~/.config/vault/certs/postgres/key.pem

# Restart
docker compose restart postgres
```

### Permission Issues

**Error: permission denied reading key file**

```bash
# Fix permissions
chmod 600 ~/.config/vault/certs/*/key.pem
chmod 644 ~/.config/vault/certs/*/cert.pem

# Check ownership
ls -la ~/.config/vault/certs/postgres/

# Inside container, check permissions
docker exec dev-postgres ls -la /certs/
```

## Related Pages

- [Security-Hardening](Security-Hardening) - TLS enforcement
- [Vault-Troubleshooting](Vault-Troubleshooting) - PKI issues
- [Service-Configuration](Service-Configuration) - TLS configuration
- [CLI-Reference](CLI-Reference) - Management commands
