# Security Hardening

## Table of Contents

- [Overview](#overview)
- [Production Security Considerations](#production-security-considerations)
  - [Development vs Production](#development-vs-production)
  - [Security Checklist](#security-checklist)
- [Moving from Root Token to AppRole](#moving-from-root-token-to-approle)
  - [AppRole Authentication](#approle-authentication)
  - [Policy Creation](#policy-creation)
  - [Service Configuration](#service-configuration)
- [Network Firewalls and Isolation](#network-firewalls-and-isolation)
  - [Docker Network Policies](#docker-network-policies)
  - [Port Restrictions](#port-restrictions)
  - [Service Mesh](#service-mesh)
- [TLS Enforcement](#tls-enforcement)
  - [Disable HTTP](#disable-http)
  - [Mutual TLS](#mutual-tls)
  - [Certificate Rotation](#certificate-rotation)
- [Rate Limiting Configuration](#rate-limiting-configuration)
  - [Application Rate Limits](#application-rate-limits)
  - [Database Connection Limits](#database-connection-limits)
  - [API Gateway Rate Limiting](#api-gateway-rate-limiting)
- [Authentication and Authorization](#authentication-and-authorization)
  - [JWT Authentication](#jwt-authentication)
  - [OAuth2 Integration](#oauth2-integration)
  - [Role-Based Access Control](#role-based-access-control)
- [Secret Rotation Procedures](#secret-rotation-procedures)
  - [Database Password Rotation](#database-password-rotation)
  - [Certificate Rotation](#certificate-rotation-1)
  - [API Key Rotation](#api-key-rotation)
- [Audit Logging Setup](#audit-logging-setup)
  - [Vault Audit Logs](#vault-audit-logs)
  - [Application Audit Logs](#application-audit-logs)
  - [Database Audit Logs](#database-audit-logs)
- [Security Scanning](#security-scanning)
  - [Container Scanning](#container-scanning)
  - [Dependency Scanning](#dependency-scanning)
  - [Secrets Scanning](#secrets-scanning)
- [Related Pages](#related-pages)

## Overview

The devstack-core environment is designed for **local development** and is NOT production-hardened out of the box. This page provides guidance on hardening the environment for production use.

**Current Security Posture (Development):**
- Uses Vault root token (full access)
- No network firewalls between services
- Debug logging enabled
- Services accept both TLS and non-TLS connections
- No authentication on reference applications
- No rate limiting
- Permissive CORS policies

**Production Requirements:**
- Use Vault AppRole authentication (least privilege)
- Enable network segmentation and firewalls
- TLS-only connections (no HTTP)
- Authentication and authorization on all endpoints
- Rate limiting and DDoS protection
- Audit logging enabled
- Regular security updates and patching

## Production Security Considerations

### Development vs Production

**Development Environment:**
```yaml
# Easy to use, low security
vault:
  environment:
    VAULT_TOKEN: root  # Full access
    VAULT_DEV_ROOT_TOKEN_ID: root
postgres:
  environment:
    POSTGRES_HOST_AUTH_METHOD: trust  # No password
reference-api:
  ports:
    - "8000:8000"  # Exposed to host
```

**Production Environment:**
```yaml
# Secure, least privilege
vault:
  environment:
    # No root token in environment
    # Services use AppRole authentication
postgres:
  environment:
    # Passwords from Vault
    # SSL required
    POSTGRES_SSL_MODE: require
reference-api:
  # Not exposed externally
  # Behind API gateway with authentication
```

### Security Checklist

**Pre-Production Checklist:**

- [ ] Remove root token from service configurations
- [ ] Implement AppRole authentication for services
- [ ] Create least-privilege Vault policies
- [ ] Enable TLS-only mode (disable HTTP)
- [ ] Implement mutual TLS between services
- [ ] Add authentication to all application endpoints
- [ ] Implement rate limiting
- [ ] Enable audit logging on Vault
- [ ] Enable audit logging on databases
- [ ] Configure log aggregation and monitoring
- [ ] Set up automated alerts
- [ ] Implement secret rotation
- [ ] Configure firewall rules
- [ ] Enable container security scanning
- [ ] Review and restrict network policies
- [ ] Remove debug logging
- [ ] Set proper file permissions
- [ ] Implement backup encryption
- [ ] Configure intrusion detection
- [ ] Perform security audit
- [ ] Document security procedures

## Moving from Root Token to AppRole

### AppRole Authentication

**Enable AppRole in Vault:**

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Enable AppRole auth method
vault auth enable approle

# Create role for PostgreSQL service
vault write auth/approle/role/postgres \
  token_ttl=1h \
  token_max_ttl=4h \
  token_policies=postgres-policy \
  secret_id_ttl=0 \
  secret_id_num_uses=0

# Create role for other services
vault write auth/approle/role/mysql token_policies=mysql-policy
vault write auth/approle/role/redis token_policies=redis-policy
vault write auth/approle/role/rabbitmq token_policies=rabbitmq-policy
```

### Policy Creation

**Create least-privilege policies:**

```bash
# PostgreSQL policy
vault policy write postgres-policy - <<EOF
# Read PostgreSQL credentials
path "secret/data/postgres" {
  capabilities = ["read"]
}

# Request certificates
path "pki_int/issue/postgres-role" {
  capabilities = ["create", "update"]
}
EOF

# MySQL policy
vault policy write mysql-policy - <<EOF
path "secret/data/mysql" {
  capabilities = ["read"]
}
path "pki_int/issue/mysql-role" {
  capabilities = ["create", "update"]
}
EOF

# Redis policy
vault policy write redis-policy - <<EOF
path "secret/data/redis-*" {
  capabilities = ["read"]
}
path "pki_int/issue/redis-role" {
  capabilities = ["create", "update"]
}
EOF

# Application policy (read-only access to credentials)
vault policy write app-policy - <<EOF
path "secret/data/*" {
  capabilities = ["read"]
}
EOF
```

### Service Configuration

**Modify init scripts to use AppRole:**

**Example:** `configs/postgres/scripts/init-approle.sh`

```bash
#!/bin/bash
set -e

VAULT_ADDR=${VAULT_ADDR:-http://vault:8200}
ROLE_ID=${POSTGRES_ROLE_ID}
SECRET_ID=${POSTGRES_SECRET_ID}

# Authenticate with AppRole
echo "Authenticating to Vault with AppRole..."
TOKEN_RESPONSE=$(curl -s -X POST \
  -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
  $VAULT_ADDR/v1/auth/approle/login)

VAULT_TOKEN=$(echo $TOKEN_RESPONSE | jq -r '.auth.client_token')

if [ -z "$VAULT_TOKEN" ] || [ "$VAULT_TOKEN" = "null" ]; then
  echo "ERROR: Failed to authenticate with Vault"
  exit 1
fi

# Fetch credentials
RESPONSE=$(curl -s -H "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/secret/data/postgres")

export POSTGRES_PASSWORD=$(echo $RESPONSE | jq -r '.data.data.password')

# Start PostgreSQL
exec docker-entrypoint.sh postgres
```

**Update docker-compose.yml:**

```yaml
services:
  postgres:
    environment:
      POSTGRES_ROLE_ID: ${POSTGRES_ROLE_ID}
      POSTGRES_SECRET_ID: ${POSTGRES_SECRET_ID}
      # Remove VAULT_TOKEN
    entrypoint: ["/init/init-approle.sh"]
```

**Generate and store AppRole credentials:**

```bash
# Get role ID (static)
ROLE_ID=$(vault read -field=role_id auth/approle/role/postgres/role-id)

# Generate secret ID (rotatable)
SECRET_ID=$(vault write -field=secret_id -f auth/approle/role/postgres/secret-id)

# Store in .env (or better, in Kubernetes secrets)
echo "POSTGRES_ROLE_ID=$ROLE_ID" >> .env
echo "POSTGRES_SECRET_ID=$SECRET_ID" >> .env

# In production, use secret management (not .env file)
```

## Network Firewalls and Isolation

### Docker Network Policies

**Implement network segmentation:**

```yaml
# docker-compose.yml
networks:
  vault-network:
    driver: bridge
    internal: false  # Vault needs external access
  database-network:
    driver: bridge
    internal: true  # Databases isolated
  app-network:
    driver: bridge
    internal: false

services:
  vault:
    networks:
      - vault-network

  postgres:
    networks:
      - vault-network  # Can access Vault
      - database-network  # Isolated from apps
    # No app-network access

  reference-api:
    networks:
      - vault-network  # Can access Vault
      - app-network  # External access
    # Cannot directly access databases
```

### Port Restrictions

**Restrict exposed ports:**

```yaml
services:
  postgres:
    ports:
      - "127.0.0.1:5432:5432"  # Only localhost, not 0.0.0.0
    # Or remove ports entirely (internal only)

  vault:
    ports:
      - "127.0.0.1:8200:8200"  # Vault only on localhost

  reference-api:
    # No direct exposure
    # Use reverse proxy instead
```

**Use reverse proxy for external access:**

```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "443:443"
    volumes:
      - ./configs/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./configs/nginx/certs:/etc/nginx/certs:ro
    networks:
      - app-network
```

### Service Mesh

**Implement Istio or Linkerd for advanced security:**

```bash
# Install Linkerd
linkerd install | kubectl apply -f -

# Inject sidecar proxies
linkerd inject docker-compose.yml | kubectl apply -f -

# Enable mTLS between services
# Automatic with Linkerd
```

## TLS Enforcement

### Disable HTTP

**Enforce HTTPS-only:**

**PostgreSQL:**

```conf
# configs/postgres/postgresql.conf
ssl = on
ssl_cert_file = '/certs/cert.pem'
ssl_key_file = '/certs/key.pem'
ssl_ca_file = '/certs/ca.pem'

# Reject non-SSL connections
hostssl all all 0.0.0.0/0 scram-sha-256
# Remove 'host' lines (non-SSL)
```

**Redis:**

```conf
# configs/redis/redis.conf
port 0  # Disable non-TLS port
tls-port 6380
tls-cert-file /certs/cert.pem
tls-key-file /certs/key.pem
tls-ca-cert-file /certs/ca.pem
tls-auth-clients yes  # Require client certificates
```

**RabbitMQ:**

```conf
# configs/rabbitmq/rabbitmq.conf
listeners.tcp = none  # Disable non-TLS
listeners.ssl.default = 5671
ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = true
```

**FastAPI Application:**

```python
# Only listen on HTTPS port
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app,
        host="0.0.0.0",
        port=8443,
        ssl_keyfile="/certs/key.pem",
        ssl_certfile="/certs/cert.pem",
        ssl_ca_certs="/certs/ca.pem"
    )
```

### Mutual TLS

**Require client certificates:**

```conf
# PostgreSQL pg_hba.conf
hostssl all all 0.0.0.0/0 cert clientcert=verify-full

# Redis
tls-auth-clients yes
tls-ca-cert-file /certs/ca.pem

# RabbitMQ
ssl_options.verify = verify_peer
ssl_options.fail_if_no_peer_cert = true
```

**Generate client certificates:**

```bash
# For each client
vault write pki_int/issue/client-role \
  common_name=client-app-1 \
  ttl=8760h > client-cert.json

jq -r '.data.certificate' < client-cert.json > client-cert.pem
jq -r '.data.private_key' < client-cert.json > client-key.pem
```

### Certificate Rotation

**Automate certificate rotation:**

```bash
#!/bin/bash
# scripts/rotate-certificates.sh

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Rotate certificates for all services
for service in postgres mysql redis-1 redis-2 redis-3 rabbitmq mongodb; do
  echo "Rotating certificate for $service..."

  # Generate new certificate
  vault write pki_int/issue/${service}-role \
    common_name=$service \
    ttl=8760h \
    format=pem > /tmp/${service}-cert.json

  # Extract and save
  jq -r '.data.certificate' < /tmp/${service}-cert.json > ~/.config/vault/certs/${service}/cert.pem
  jq -r '.data.private_key' < /tmp/${service}-cert.json > ~/.config/vault/certs/${service}/key.pem

  # Restart service
  docker compose restart $service
done

echo "Certificate rotation complete"
```

**Schedule rotation:**

```bash
# crontab
# Rotate certificates monthly
0 2 1 * * /path/to/scripts/rotate-certificates.sh
```

## Rate Limiting Configuration

### Application Rate Limits

**Implement rate limiting in FastAPI:**

```python
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

limiter = Limiter(key_func=get_remote_address)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.get("/api/endpoint")
@limiter.limit("10/minute")
async def endpoint(request: Request):
    return {"data": "value"}

# IP-based limits
@limiter.limit("100/hour")
async def heavy_endpoint(request: Request):
    # Expensive operation
    pass
```

### Database Connection Limits

**Limit concurrent connections:**

**PostgreSQL:**

```conf
# postgresql.conf
max_connections = 100

# Per-user limits
ALTER ROLE appuser CONNECTION LIMIT 20;

# Per-database limits
ALTER DATABASE appdb CONNECTION LIMIT 50;
```

**MySQL:**

```ini
# my.cnf
max_connections = 100
max_user_connections = 20
```

**Use connection pooling:**

```yaml
services:
  pgbouncer:
    image: pgbouncer/pgbouncer
    environment:
      DATABASES_HOST: postgres
      DATABASES_PORT: 5432
      DATABASES_DBNAME: devdb
      PGBOUNCER_POOL_MODE: transaction
      PGBOUNCER_MAX_CLIENT_CONN: 1000
      PGBOUNCER_DEFAULT_POOL_SIZE: 25
```

### API Gateway Rate Limiting

**Use Kong or NGINX for rate limiting:**

```nginx
# nginx.conf
http {
  limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

  server {
    location /api/ {
      limit_req zone=api_limit burst=20 nodelay;
      proxy_pass http://reference-api:8000;
    }
  }
}
```

## Authentication and Authorization

### JWT Authentication

**Implement JWT authentication:**

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import jwt

security = HTTPBearer()

def verify_jwt(credentials: HTTPAuthorizationCredentials = Depends(security)):
    try:
        token = credentials.credentials
        payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
        return payload
    except jwt.ExpiredSignatureError:
        raise HTTPException(status_code=401, detail="Token expired")
    except jwt.InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid token")

@app.get("/api/protected")
async def protected_endpoint(user = Depends(verify_jwt)):
    return {"user": user["sub"], "data": "sensitive"}
```

### OAuth2 Integration

**Add OAuth2 authentication:**

```python
from fastapi import Depends, FastAPI
from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

@app.post("/token")
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    # Verify credentials
    user = authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # Generate token
    token = create_access_token(data={"sub": user.username})
    return {"access_token": token, "token_type": "bearer"}

@app.get("/api/user")
async def get_user(token: str = Depends(oauth2_scheme)):
    user = decode_token(token)
    return user
```

### Role-Based Access Control

**Implement RBAC:**

```python
from enum import Enum
from fastapi import Depends, HTTPException

class Role(str, Enum):
    ADMIN = "admin"
    USER = "user"
    READONLY = "readonly"

def require_role(required_role: Role):
    def role_checker(user = Depends(verify_jwt)):
        user_role = user.get("role")
        if user_role != required_role.value:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return user
    return role_checker

@app.delete("/api/user/{user_id}")
async def delete_user(user_id: int, user = Depends(require_role(Role.ADMIN))):
    # Only admins can delete users
    delete_user_by_id(user_id)
    return {"status": "deleted"}
```

## Secret Rotation Procedures

### Database Password Rotation

**Rotate PostgreSQL password:**

```bash
#!/bin/bash
# scripts/rotate-postgres-password.sh

export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Generate new password
NEW_PASSWORD=$(openssl rand -base64 32)

# Update in PostgreSQL
docker exec dev-postgres psql -U postgres -c \
  "ALTER ROLE devuser WITH PASSWORD '$NEW_PASSWORD';"

# Update in Vault
vault kv put secret/postgres \
  username=devuser \
  password=$NEW_PASSWORD \
  host=postgres \
  port=5432 \
  database=devdb

# Restart services to pick up new password
docker compose restart reference-api

echo "PostgreSQL password rotated successfully"
```

**Schedule rotation:**

```bash
# crontab - rotate every 90 days
0 3 1 */3 * /path/to/scripts/rotate-postgres-password.sh
```

### Certificate Rotation

See [Certificate Rotation](#certificate-rotation) section above.

### API Key Rotation

**Rotate API keys:**

```bash
# Generate new API key
NEW_API_KEY=$(openssl rand -hex 32)

# Update in Vault
vault kv put secret/api-keys \
  service-a=$NEW_API_KEY

# Update consuming services
docker compose restart service-a

# Revoke old key after grace period
# (24 hours to allow for propagation)
```

## Audit Logging Setup

### Vault Audit Logs

**Enable Vault audit logging:**

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)

# Enable file audit device
vault audit enable file file_path=/vault/logs/audit.log

# Enable syslog audit device
vault audit enable syslog tag="vault" facility="LOCAL7"

# Verify enabled
vault audit list
```

**Query audit logs:**

```bash
# View recent activity
docker exec dev-vault tail -f /vault/logs/audit.log | jq

# Filter by type
docker exec dev-vault grep '"type":"request"' /vault/logs/audit.log | jq

# Find failed authentications
docker exec dev-vault grep '"error":"' /vault/logs/audit.log | jq
```

### Application Audit Logs

**Log all sensitive operations:**

```python
import logging
from datetime import datetime

audit_logger = logging.getLogger("audit")
audit_logger.setLevel(logging.INFO)

handler = logging.FileHandler("/var/log/app/audit.log")
handler.setFormatter(logging.Formatter(
    '%(asctime)s - %(message)s'
))
audit_logger.addHandler(handler)

def log_audit(user: str, action: str, resource: str, status: str):
    audit_logger.info({
        "timestamp": datetime.utcnow().isoformat(),
        "user": user,
        "action": action,
        "resource": resource,
        "status": status
    })

@app.delete("/api/user/{user_id}")
async def delete_user(user_id: int, user = Depends(verify_jwt)):
    try:
        delete_user_by_id(user_id)
        log_audit(user["sub"], "DELETE", f"user/{user_id}", "success")
        return {"status": "deleted"}
    except Exception as e:
        log_audit(user["sub"], "DELETE", f"user/{user_id}", "failed")
        raise
```

### Database Audit Logs

**Enable PostgreSQL audit logging:**

```bash
# Install pgaudit extension
docker exec dev-postgres psql -U postgres -c "CREATE EXTENSION pgaudit;"

# Configure logging
# In postgresql.conf:
shared_preload_libraries = 'pgaudit'
pgaudit.log = 'write, ddl'
pgaudit.log_relation = on

# Restart PostgreSQL
docker compose restart postgres

# Query audit logs
docker exec dev-postgres psql -U postgres -c \
  "SELECT * FROM pgaudit.log WHERE command = 'DELETE';"
```

## Security Scanning

### Container Scanning

**Scan containers for vulnerabilities:**

```bash
# Install Trivy
brew install aquasecurity/trivy/trivy

# Scan image
trivy image postgres:16-alpine

# Scan for HIGH and CRITICAL only
trivy image --severity HIGH,CRITICAL postgres:16-alpine

# Generate report
trivy image --format json --output trivy-report.json postgres:16-alpine

# Scan all containers
for image in $(docker ps --format '{{.Image}}'); do
  echo "Scanning $image..."
  trivy image $image
done
```

### Dependency Scanning

**Scan Python dependencies:**

```bash
# Install safety
pip install safety

# Scan dependencies
safety check --json

# Scan requirements file
safety check -r requirements.txt

# Update vulnerable packages
pip-audit --fix
```

**Scan Node.js dependencies:**

```bash
cd reference-apps/nodejs
npm audit

# Fix automatically
npm audit fix

# Force fix (may break)
npm audit fix --force
```

### Secrets Scanning

**Scan for committed secrets:**

```bash
# Install gitleaks
brew install gitleaks

# Scan repository
gitleaks detect --source . --verbose

# Scan commit history
gitleaks detect --source . --log-opts '--all'

# Pre-commit hook
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
gitleaks protect --staged --verbose
EOF
chmod +x .git/hooks/pre-commit
```

## Related Pages

- [Vault-Troubleshooting](Vault-Troubleshooting) - Vault security issues
- [TLS-Configuration](TLS-Configuration) - Certificate management
- [Service-Configuration](Service-Configuration) - Service hardening
- [Audit-Logging](Health-Monitoring) - Logging and monitoring
- [Network-Issues](Network-Issues) - Network security
