# Security Policy

## Table of Contents

- [Supported Versions](#supported-versions)
- [Reporting a Vulnerability](#reporting-a-vulnerability)
  - [1. DO NOT Publicly Disclose](#1-do-not-publicly-disclose)
  - [2. Report Privately](#2-report-privately)
  - [3. What to Expect](#3-what-to-expect)
  - [4. Response Timeline](#4-response-timeline)
- [Security Best Practices](#security-best-practices)
  - [For Users](#for-users)
  - [For Contributors](#for-contributors)
- [Known Security Considerations](#known-security-considerations)
  - [Development Environment Only](#development-environment-only)
  - [Service-Specific Considerations](#service-specific-considerations)
- [Security Updates](#security-updates)
- [Security Tools](#security-tools)
- [Compliance](#compliance)
- [Contact](#contact)
- [Acknowledgments](#acknowledgments)

---

## Supported Versions

We release security updates for the following versions:

| Version | Supported          | Notes                           |
| ------- | ------------------ | ------------------------------- |
| main    | :white_check_mark: | Latest development version      |
| 1.x.x   | :white_check_mark: | Current stable release          |
| < 1.0   | :x:                | Please upgrade to latest        |

**Note:** This project is intended for **local development environments only** and is not designed for production deployment. Security considerations are focused on protecting your local development setup.

## Reporting a Vulnerability

We take security vulnerabilities seriously. If you discover a security issue, please follow these steps:

### 1. DO NOT Publicly Disclose

- **DO NOT** open a public GitHub issue
- **DO NOT** discuss the vulnerability in public forums
- **DO NOT** disclose details on social media

### 2. Report Privately

Send a detailed report via **GitHub Security Advisories**:
1. Go to the repository's [Security tab](https://github.com/NormB/devstack-core/security)
2. Click "Report a vulnerability"
3. Fill out the private vulnerability report form

Include in your report:
- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact assessment
- Suggested fixes (if any)
- Your contact information

### 3. What to Expect

- **Acknowledgment**: We will acknowledge your report within 48 hours
- **Assessment**: We will assess the vulnerability and determine its severity within 5 business days
- **Updates**: We will provide regular updates on our progress
- **Resolution**: We will work to resolve critical issues as quickly as possible
- **Credit**: We will credit you in the fix announcement (unless you prefer to remain anonymous)

### 4. Response Timeline

| Severity | Initial Response | Resolution Target |
|----------|-----------------|-------------------|
| Critical | 24 hours        | 7 days            |
| High     | 48 hours        | 14 days           |
| Medium   | 5 days          | 30 days           |
| Low      | 7 days          | 60 days           |

## Security Best Practices

### For Users

#### 1. Environment Configuration

**Secure Your .env File:**
```bash
# NEVER commit .env to git
# Ensure .env is in .gitignore
echo ".env" >> .gitignore

# Set restrictive permissions
chmod 600 .env

# Use strong, unique passwords
# Generate secure passwords:
openssl rand -base64 32
```

**Critical Variables to Secure:**
- `POSTGRES_PASSWORD`
- `MYSQL_ROOT_PASSWORD`
- `RABBITMQ_DEFAULT_PASS`
- `MONGODB_ROOT_PASSWORD`
- `VAULT_DEV_ROOT_TOKEN_ID`
- Any API keys or tokens

#### 2. Vault Security

**Initial Setup:**
```bash
# Initialize Vault securely
./devstack.sh vault-init

# Store root token securely
# NEVER commit vault-keys.json to git
chmod 600 configs/vault/vault-keys.json

# Consider using a password manager for token storage
```

**Vault Token Management:**
- Rotate the root token regularly
- Use limited-scope tokens for applications
- Enable audit logging for compliance
- Revoke unused tokens

#### 3. Network Security

**Port Exposure:**
- By default, services are only accessible from `localhost`
- Only expose services to your network if absolutely necessary
- Use firewall rules to restrict access
- Consider using SSH tunnels for remote access

**If Exposing Services:**
```bash
# Use SSH tunnel instead of direct exposure
ssh -L 5432:localhost:5432 user@remote-host

# Or use VPN for secure access
```

#### 4. Database Security

**PostgreSQL:**
- Use strong passwords (minimum 16 characters)
- Enable SSL/TLS for all connections
- Limit user privileges (principle of least privilege)
- Regularly backup databases
- Rotate credentials periodically

**Redis:**
- Enable authentication (requirepass)
- Use TLS for cluster communication
- Disable dangerous commands in production
- Limit network access

**MongoDB:**
- Enable authentication and authorization
- Use role-based access control (RBAC)
- Enable encryption at rest
- Use TLS for connections

#### 5. Container Security

**Best Practices:**
```bash
# Regularly update base images
docker compose pull

# Scan images for vulnerabilities
docker scout cves [image-name]

# Review container logs for suspicious activity
./devstack.sh logs [service]

# Limit container resources to prevent DoS
# (Already configured in docker-compose.yml)
```

#### 6. Backup Security

**Secure Your Backups:**
```bash
# Create encrypted backups
./devstack.sh backup

# Encrypt backup files
tar -czf - backups/ | openssl enc -aes-256-cbc -e > backups-encrypted.tar.gz.enc

# Store backups securely (off-system)
# Set restrictive permissions
chmod 600 backups-encrypted.tar.gz.enc
```

#### 7. Secrets Management

**DO:**
- Use HashiCorp Vault for secrets
- Rotate secrets regularly
- Use unique secrets per service
- Use environment variables for configuration
- Use `.env.example` as template (with placeholders)

**DON'T:**
- Hardcode secrets in scripts or config files
- Commit secrets to version control
- Share secrets via insecure channels (email, Slack, etc.)
- Reuse passwords across services
- Use default or weak passwords

### For Contributors

#### 1. Code Security

**Before Committing:**
```bash
# Scan for secrets
git secrets --scan

# Check for hardcoded credentials
grep -r "password\|secret\|token\|api_key" --exclude-dir=.git --exclude="*.md"

# Ensure .env is not tracked
git status --ignored

# Review changes
git diff
```

#### 2. Dependency Security

**Python Dependencies:**
```bash
# Check for vulnerabilities
safety check -r requirements.txt

# Update dependencies
pip list --outdated
```

**Docker Images:**
```bash
# Use specific version tags (not 'latest')
# Verify image signatures when possible
# Scan images with Trivy
trivy image postgres:15-alpine
```

#### 3. Pull Request Security

**Security Checklist:**
- [ ] No secrets or credentials in code
- [ ] No sensitive data in logs or error messages
- [ ] Input validation for user-provided data
- [ ] Proper error handling (no stack traces to users)
- [ ] Security implications documented
- [ ] Dependencies are up-to-date
- [ ] No new security warnings from linters

## Known Security Considerations

### Development Environment Only

**Important:** This project is designed for **local development only**. Do NOT use in production:

- Default credentials are documented (for convenience)
- Some services use development mode settings
- SSL/TLS certificates are self-signed
- No advanced hardening is applied
- Audit logging is minimal
- Network isolation is basic

### Service-Specific Considerations

#### HashiCorp Vault
- Uses dev mode by default (data stored in memory)
- Auto-unseal with transit engine (convenience over security)
- Root token stored in plaintext (for development ease)

#### PostgreSQL
- Allows connections from Docker network
- SSL mode set to 'prefer' (not 'require')
- Superuser access available

#### Redis Cluster
- Password authentication required
- TLS optional (enable for sensitive data)
- No command blacklisting

#### MongoDB
- Authentication enabled
- No IP whitelisting by default
- Role-based access available

## Security Updates

### Stay Informed

- Watch this repository for security updates
- Review CHANGELOG.md for security fixes
- Subscribe to security advisories for dependencies:
  - [PostgreSQL Security](https://www.postgresql.org/support/security/)
  - [Redis Security](https://redis.io/docs/latest/operate/oss_and_stack/management/security/)
  - [MongoDB Security](https://www.mongodb.com/alerts)
  - [HashiCorp Vault Security](https://www.hashicorp.com/trust/security)
  - [Docker Security](https://docs.docker.com/engine/security/)

### Update Regularly

```bash
# Update container images
docker compose pull

# Update Colima
brew upgrade colima

# Update Docker
brew upgrade docker docker-compose

# Restart services
./devstack.sh restart
```

## Security Tools

### Recommended Tools

**Secret Scanning:**
- [gitleaks](https://github.com/gitleaks/gitleaks) - Scan for hardcoded secrets
- [truffleHog](https://github.com/trufflesecurity/truffleHog) - Find secrets in git history
- [git-secrets](https://github.com/awslabs/git-secrets) - Prevent committing secrets

**Vulnerability Scanning:**
- [Trivy](https://github.com/aquasecurity/trivy) - Container and filesystem scanning
- [Docker Scout](https://docs.docker.com/scout/) - Docker image analysis
- [Safety](https://github.com/pyupio/safety) - Python dependency scanning

**Static Analysis:**
- [shellcheck](https://www.shellcheck.net/) - Shell script analysis
- [hadolint](https://github.com/hadolint/hadolint) - Dockerfile linting

### Automated Scanning

This repository includes GitHub Actions workflows for:
- Secret scanning (Gitleaks, TruffleHog)
- Dependency scanning
- Container vulnerability scanning (Trivy)
- Code quality analysis (CodeQL)
- Configuration security checks

## Compliance

### Data Protection

**Local Development:**
- No production data should be used
- Use synthetic/mock data for testing
- Sanitize any real data before importing
- Clear databases when no longer needed

**GDPR/Privacy:**
- Don't store personally identifiable information (PII)
- Don't use production customer data
- Follow data minimization principles
- Implement data retention policies

## Contact

For security questions or concerns:
- **Security Issues**: Use [GitHub Security Advisories](https://github.com/NormB/devstack-core/security/advisories)
- **General Questions**: Open a [GitHub Issue](https://github.com/NormB/devstack-core/issues) with the "question" label
- **Non-Security Bugs**: Open a [GitHub Issue](https://github.com/NormB/devstack-core/issues)

## Acknowledgments

We appreciate the security research community and thank all researchers who responsibly disclose vulnerabilities.

**Hall of Fame:**
<!-- Contributors who have responsibly disclosed security issues will be listed here -->

---

**Last Updated:** 2025-10-23

**Version:** 1.0
