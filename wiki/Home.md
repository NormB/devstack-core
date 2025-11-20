# DevStack Core

> **Complete Docker-based development infrastructure for Apple Silicon Macs, optimized with Colima**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)
[![Docker Compose](https://img.shields.io/badge/docker--compose-v2.0+-blue.svg)](https://docs.docker.com/compose/)
[![Colima](https://img.shields.io/badge/colima-latest-brightgreen.svg)](https://github.com/abiosoft/colima)
[![Platform](https://img.shields.io/badge/platform-Apple%20Silicon-lightgrey.svg)](https://www.apple.com/mac/)

A comprehensive, self-contained development environment providing Git hosting (Forgejo), databases (PostgreSQL, MySQL, MongoDB), caching (Redis Cluster), message queuing (RabbitMQ), secrets management (Vault), and observability (Prometheus, Grafana, Loki) - all running locally on your Mac.

---

## ✨ Key Features

- **🚀 [Complete Infrastructure](#️-architecture)** - Everything you need: Git, databases, caching, messaging, secrets, observability
- **🎯 [Service Profiles](./docs/SERVICE_PROFILES.md)** - Choose your stack: minimal (2GB), standard (4GB), or full (6GB) with observability
- **🍎 [Apple Silicon Optimized](#-prerequisites)** - Native ARM64 support via Colima's Virtualization.framework
- **🔒 [Vault-First Security](./docs/VAULT.md)** - All credentials managed by HashiCorp Vault with AppRole authentication
- **🛡️ [AppRole Authentication](#-security--approle-authentication)** - Zero hardcoded secrets, least-privilege access for all core services
- **🔐 [TLS/SSL Support](./docs/TLS_CERTIFICATE_MANAGEMENT.md)** - Dual-mode TLS with automated certificate generation via Vault PKI
- **📦 [Zero Cloud Dependencies](#-zero-cloud-dependencies)** - Runs entirely on your Mac, perfect for offline development
- **🛠️ [Easy Management](./docs/PYTHON_MANAGEMENT_SCRIPT.md)** - Single CLI script with 21 commands for all operations
- **📚 [Reference Apps](./reference-apps/README.md)** - Production-quality examples in Python, Go, Node.js, TypeScript, and Rust
- **🔍 [Full Observability](./docs/OBSERVABILITY.md)** - Built-in Prometheus, Grafana, and Loki for monitoring and logging

## 🚀 Quick Start

Get up and running in 10 minutes (5 minutes if prerequisites already installed):

```bash
# 1. Install prerequisites
brew install colima docker docker-compose uv

# 2. Clone and setup
git clone https://github.com/NormB/devstack-core.git ~/devstack-core
cd ~/devstack-core

# 3. Install Python dependencies
uv venv && uv pip install -r scripts/requirements.txt

# 4. Configure environment
cp .env.example .env

# 5. Start with standard profile (recommended)
./devstack start --profile standard

# 6. Initialize Vault (first time only)
./devstack vault-init          # Creates Vault, generates unseal keys
./devstack vault-bootstrap     # Enables AppRole, generates credentials & certificates

# 7. Initialize Redis cluster (first time only, for standard/full profiles)
./devstack redis-cluster-init

# 8. Verify everything is running
./devstack health
```

**Access your services:**
- **Forgejo (Git):** http://localhost:3000
- **Vault UI:** http://localhost:8200/ui
- **RabbitMQ Management:** http://localhost:15672
- **Grafana:** http://localhost:3001 (admin/admin)
- **Prometheus:** http://localhost:9090

## 📋 Prerequisites

**Required:**
- macOS with Apple Silicon (M1/M2/M3/M4)
- **Note:** Intel Macs are not supported due to ARM64 architecture requirements
- Homebrew package manager
- 8GB+ RAM (16GB recommended)
- 50GB+ free disk space

**Software (auto-installed via Homebrew):**
- Colima (container runtime)
- Docker CLI
- Docker Compose
- uv (Python package installer)

**For development:**
- Python 3.8+ (for management script)
- Git (for cloning repository)

## 📖 Service Profiles

Choose the profile that fits your needs:

| Profile | Services | RAM | Use Case |
|---------|----------|-----|----------|
| **minimal** | 5 services | 2GB | Git hosting + essential development (single Redis) |
| **standard** | 10 services | 4GB | **Full development stack + Redis cluster (RECOMMENDED)** |
| **full** | 18 services | 6GB | Complete suite + observability (Prometheus, Grafana, Loki) |
| **reference** | +5 services | +1GB | Educational API examples (combine with standard/full) |

### Profile Commands

```bash
# Start with different profiles
./devstack start --profile minimal   # Lightweight
./devstack start --profile standard  # Recommended
./devstack start --profile full      # Everything

# Combine profiles for reference apps
./devstack start --profile standard --profile reference

# Check what's running
./devstack status
./devstack health
```

**See [Service Profiles Guide](./docs/SERVICE_PROFILES.md) for detailed information.**

## 🛡️ Security & AppRole Authentication

DevStack Core implements **AppRole authentication** for secure, zero-trust credential management across all core services.

### What is AppRole?

AppRole is HashiCorp Vault's recommended authentication method for applications. Instead of hardcoding secrets or using a single root token, each service authenticates using its own `role-id` (identifies the service) and `secret-id` (proves authorization).

**Security Benefits:**
- ✅ **Zero Hardcoded Secrets** - No passwords in .env files or docker-compose.yml
- ✅ **Least Privilege** - Each service has access ONLY to its own credentials
- ✅ **Short-Lived Tokens** - Service tokens expire after 1 hour (renewable)
- ✅ **Audit Trail** - All secret access logged by Vault
- ✅ **Policy Enforcement** - Services cannot access other services' secrets

### AppRole Bootstrap

When you run `./devstack vault-bootstrap`, the system:

1. **Enables AppRole auth method** in Vault
2. **Creates policies** for each service (postgres-policy, mysql-policy, etc.)
3. **Generates AppRole credentials** (role-id and secret-id)
4. **Stores credentials** in `~/.config/vault/approles/<service>/`
5. **Validates** AppRole authentication for all services

### Which Services Use AppRole?

**✅ Core Services (AppRole Enabled - 7 services):**
- PostgreSQL, MySQL, MongoDB
- Redis Cluster (3 nodes)
- RabbitMQ
- Forgejo (Git)
- Reference API (FastAPI)

**⚠️ Infrastructure Services (Root Token - 9 services):**
- PGBouncer, Redis Exporters, Vector
- Additional reference apps (api-first, golang, nodejs, rust)

**Migration Roadmap:** Phase 4+ will migrate remaining services to AppRole for 95%+ coverage.

### How Services Authenticate

Each AppRole-enabled service follows this flow:

```bash
# 1. Container starts with init-approle.sh wrapper script
# 2. Script reads credentials from mounted volume
role_id=$(cat /vault-approles/<service>/role-id)
secret_id=$(cat /vault-approles/<service>/secret-id)

# 3. Authenticate to Vault
curl -X POST $VAULT_ADDR/v1/auth/approle/login \
  -d "{\"role_id\":\"$role_id\",\"secret_id\":\"$secret_id\"}"

# 4. Receive service token (1h TTL)
# 5. Fetch service credentials using token
# 6. Start service with fetched credentials
```

**See [Vault Integration Guide](./docs/VAULT.md) for complete details.**

## 🏗️ Architecture

### Infrastructure Services

| Service | Purpose | Access |
|---------|---------|--------|
| **HashiCorp Vault** | Secrets management + PKI | localhost:8200 |
| **PostgreSQL 18** | Primary relational database | localhost:5432 |
| **PgBouncer** | PostgreSQL connection pooling | localhost:6432 |
| **MySQL 8.0.40** | Legacy application support | localhost:3306 |
| **MongoDB 7.0** | NoSQL document database | localhost:27017 |
| **Redis Cluster** | 3-node distributed cache | localhost:6379-6381 (non-TLS), 6390-6392 (TLS) |
| **RabbitMQ** | Message queue + UI | localhost:5672, 15672 |
| **Forgejo** | Self-hosted Git server | localhost:3000 |

### Observability Stack (Full Profile)

| Service | Purpose | Access |
|---------|---------|--------|
| **Prometheus** | Metrics collection | localhost:9090 |
| **Grafana** | Metrics visualization | localhost:3001 |
| **Loki** | Log aggregation | localhost:3100 |
| **Vector** | Unified observability pipeline | - |
| **cAdvisor** | Container monitoring | localhost:8080 |

### Reference Applications

Production-quality API implementations in multiple languages:

| Language | Framework | Ports | Status |
|----------|-----------|-------|--------|
| **Python** | FastAPI (Code-First) | 8000, 8443 | ✅ Complete |
| **Python** | FastAPI (API-First) | 8001, 8444 | ✅ Complete |
| **Go** | Gin | 8002, 8445 | ✅ Complete |
| **Node.js** | Express | 8003, 8446 | ✅ Complete |
| **Rust** | Actix-web | 8004, 8447 | ⚠️ Partial (~40%) |

All reference apps demonstrate:
- Vault integration for secrets
- Database connections (PostgreSQL, MySQL, MongoDB)
- Redis cluster operations
- RabbitMQ messaging
- Health checks and metrics
- TLS/SSL support

**See [Reference Apps Overview](./reference-apps/README.md) for details.**

## 💻 Usage

### Management Commands

The `devstack` script provides all essential operations:

```bash
# Service management
./devstack start [--profile PROFILE]  # Start services
./devstack stop                        # Stop services
./devstack restart                     # Restart services
./devstack status                      # Show status
./devstack health                      # Health checks

# Logs and debugging
./devstack logs [SERVICE]              # View logs
./devstack shell SERVICE               # Open shell in container

# Vault operations
./devstack vault-init                  # Initialize Vault
./devstack vault-bootstrap             # Setup PKI + credentials
./devstack vault-status                # Check Vault status
./devstack vault-show-password SERVICE # Get service password

# Redis cluster
./devstack redis-cluster-init          # Initialize cluster

# Profiles
./devstack profiles                    # List available profiles

# Help
./devstack --help                      # Show all commands
./devstack COMMAND --help              # Command-specific help
```

### Example Workflows

**Daily Development:**
```bash
# Morning: Start development environment
./devstack start --profile standard

# Check everything is healthy
./devstack health

# View logs if needed
./devstack logs postgres

# Evening: Stop everything (or leave running)
./devstack stop
```

**Database Operations:**
```bash
# Get database password
./devstack vault-show-password postgres

# Connect to PostgreSQL
psql -h localhost -p 5432 -U devuser -d devdb

# Connect to MySQL
mysql -h 127.0.0.1 -P 3306 -u devuser -p

# Connect to MongoDB
mongosh "mongodb://localhost:27017" --username devuser
```

**Troubleshooting:**
```bash
# Check service health
./devstack health

# View service logs
./devstack logs vault
./devstack logs redis-1

# Restart specific service
docker compose restart postgres

# Open shell for debugging
./devstack shell postgres
```

## 📦 Zero Cloud Dependencies

DevStack Core runs **entirely on your local Mac** with no cloud provider services required. This architectural decision provides significant benefits for development workflows.

### What "Zero Cloud" Means

**✅ No Cloud Services Required:**
- No AWS, Azure, GCP, or any cloud provider accounts
- No cloud databases (RDS, Cloud SQL, CosmosDB, etc.)
- No cloud caching services (ElastiCache, Cloud Memorystore, etc.)
- No cloud message queues (SQS, Service Bus, Cloud Pub/Sub, etc.)
- No cloud secrets managers (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager, etc.)

**✅ Complete Local Execution:**
- All services run in Docker containers on your Mac
- Data stored locally in Docker volumes
- No network calls to external cloud APIs
- Full control over your development environment

### Benefits of Local Development

**🔒 Data Sovereignty:**
- All data stays on your machine
- Perfect for sensitive projects or regulated industries
- No data egress to third-party services
- Complete privacy for proprietary code and data

**💰 Zero Cloud Costs:**
- No monthly cloud service bills
- No surprise charges from dev/test workloads
- Predictable local hardware costs only

**✈️ Offline Development:**
- Full functionality without internet connection (after initial setup)
- Work from anywhere: planes, trains, remote locations
- No dependency on cloud service availability

**⚡ Low Latency:**
- All services communicate locally (172.20.0.0/16 network)
- No network round-trips to cloud regions
- Faster development iteration cycles

**🎮 Full Environment Control:**
- Version lock all services (PostgreSQL 18, Redis 7.4, etc.)
- Experiment freely without affecting shared infrastructure
- Easy reset and reproduction (`./devstack reset`)

### Local Dependencies

DevStack Core does require local tools for container orchestration and package management:

**Required Software:**
- **macOS with Apple Silicon** (M1/M2/M3/M4) - ARM64 architecture
- **Homebrew** - Package manager for installing tools
- **Colima** - Lightweight container runtime using macOS Virtualization.framework
- **Docker CLI** - Container management interface
- **Docker Compose** - Multi-container orchestration
- **uv** - Fast Python package installer

**Installation (one-time):**
```bash
brew install colima docker docker-compose uv
```

**Why These Tools?**
- **Colima**: Native ARM64 support, efficient resource usage, better than Docker Desktop for development
- **Docker/Docker Compose**: Industry-standard container tools, portable configurations
- **uv**: Fast Python dependency management (100x faster than pip)

### Cloud vs. Local Tradeoffs

**When Local Development Excels:**
- ✅ Individual developer workflows
- ✅ Offline or airgapped environments
- ✅ Sensitive data that cannot leave your machine
- ✅ Cost-sensitive projects
- ✅ Rapid prototyping and experimentation

**When Cloud Makes Sense:**
- ☁️ Team collaboration requiring shared infrastructure
- ☁️ Production deployments with global reach
- ☁️ Auto-scaling requirements
- ☁️ Managed service benefits (backups, updates, monitoring)

DevStack Core is optimized for **local development** while maintaining patterns that translate well to cloud deployments when needed.

## 📚 Documentation

### Getting Started
- **[Installation Guide](./docs/INSTALLATION.md)** - Comprehensive setup with troubleshooting
- **[Quick Start Tutorial](./docs/USAGE.md)** - Step-by-step usage guide
- **[Service Profiles](./docs/SERVICE_PROFILES.md)** - Profile selection and configuration

### Core Documentation
- **[Architecture Overview](./docs/ARCHITECTURE.md)** - System design with diagrams
- **[Services Guide](./docs/SERVICES.md)** - Detailed service configurations
- **[Management Script](./docs/MANAGEMENT.md)** - Complete CLI reference
- **[Python CLI Guide](./docs/PYTHON_MANAGEMENT_SCRIPT.md)** - Modern Python CLI documentation

### Infrastructure
- **[Vault Integration](./docs/VAULT.md)** - PKI setup and secrets management
- **[Redis Cluster](./docs/REDIS.md)** - Cluster architecture and operations
- **[Observability Stack](./docs/OBSERVABILITY.md)** - Prometheus, Grafana, Loki setup

### Development
- **[Reference Apps Overview](./reference-apps/README.md)** - Multi-language examples
- **[Best Practices](./docs/BEST_PRACTICES.md)** - Development patterns
- **[Testing Guide](./tests/README.md)** - Testing infrastructure
- **[Test Coverage](./tests/TEST_COVERAGE.md)** - Coverage metrics (571+ tests across 4 test suites)
- **[Testing Approach](./docs/TESTING_APPROACH.md)** - Best practices for running tests
- **[Task 2.1 Testing](./docs/.private/TASK_2.1_TESTING.md)** - Backup system test suite (63 tests)

### Operations
- **[Troubleshooting](./docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[Performance Tuning](./docs/PERFORMANCE_TUNING.md)** - Optimization strategies
- **[Disaster Recovery](./docs/DISASTER_RECOVERY.md)** - Backup and restore procedures
- **[Security Assessment](./docs/SECURITY_ASSESSMENT.md)** - Security hardening

### Project
- **[FAQ](./docs/FAQ.md)** - Frequently asked questions
- **[Changelog](./.github/CHANGELOG.md)** - Version history
- **[Contributing](./.github/CONTRIBUTING.md)** - Contribution guidelines
- **[Security Policy](./.github/SECURITY.md)** - Security reporting

## 🤝 Contributing

We welcome contributions! Here's how to get started:

1. **Fork the repository** on GitHub
2. **Clone your fork:** `git clone https://github.com/YOUR_USERNAME/devstack-core.git`
3. **Create a feature branch:** `git checkout -b feature/amazing-feature`
4. **Make your changes** and test thoroughly
5. **Commit your changes:** `git commit -m 'feat: add amazing feature'`
6. **Push to your fork:** `git push origin feature/amazing-feature`
7. **Open a Pull Request** with a clear description

### Contribution Guidelines

- Follow existing code style and conventions
- Add tests for new features
- Update documentation for any changes
- Use conventional commit messages
- Ensure CI/CD checks pass

**See [CONTRIBUTING.md](./.github/CONTRIBUTING.md) for detailed guidelines.**

## 🐛 Issues and Support

**Found a bug?** [Open an issue](https://github.com/NormB/devstack-core/issues/new) with:
- Clear description of the problem
- Steps to reproduce
- Expected vs actual behavior
- System information (OS, Colima version, etc.)

**Need help?**
1. Check the [FAQ](./docs/FAQ.md)
2. Review [Troubleshooting Guide](./docs/TROUBLESHOOTING.md)
3. Search [existing issues](https://github.com/NormB/devstack-core/issues)
4. Ask in [Discussions](https://github.com/NormB/devstack-core/discussions)

## 📜 License

This project is licensed under the **MIT License** - see the [LICENSE](./LICENSE) file for details.

You are free to:
- ✅ Use commercially
- ✅ Modify
- ✅ Distribute
- ✅ Private use

## 🙏 Acknowledgements

Built with excellent open-source software:

- [Colima](https://github.com/abiosoft/colima) - Container runtime for macOS
- [HashiCorp Vault](https://www.vaultproject.io/) - Secrets management
- [PostgreSQL](https://www.postgresql.org/) - Advanced relational database
- [Redis](https://redis.io/) - In-memory data store
- [RabbitMQ](https://www.rabbitmq.com/) - Message broker
- [Forgejo](https://forgejo.org/) - Self-hosted Git service
- [Prometheus](https://prometheus.io/) - Monitoring system
- [Grafana](https://grafana.com/) - Observability platform

**See complete list:** [ACKNOWLEDGEMENTS.md](./docs/ACKNOWLEDGEMENTS.md)

---

**Made with ❤️ for the developer community**

For questions or feedback, visit our [GitHub repository](https://github.com/NormB/devstack-core).
