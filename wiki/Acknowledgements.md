# Acknowledgements

This project is made possible by the excellent open-source software and tools created and maintained by their respective communities. We are grateful for all the contributions made by developers worldwide.

---

## Table of Contents

- [Core Infrastructure](#core-infrastructure)
- [Container & Orchestration](#container-orchestration)
- [Databases](#databases)
- [Caching & Message Queue](#caching-message-queue)
- [Secrets Management & Security](#secrets-management-security)
- [Observability & Monitoring](#observability-monitoring)
- [Reference Application Frameworks](#reference-application-frameworks)
- [Python Libraries](#python-libraries)
- [Go Libraries](#go-libraries)
- [Node.js Libraries](#nodejs-libraries)
- [Rust Libraries](#rust-libraries)
- [Development & Testing Tools](#development-testing-tools)
- [Documentation & Specification](#documentation-specification)

---

## Core Infrastructure

### Colima
**Project**: Containers on Linux on macOS
**Website**: https://github.com/abiosoft/colima
**License**: MIT
**Purpose**: Lightweight container runtime for macOS, providing the foundation for our entire development environment

### Docker
**Project**: Docker Engine
**Website**: https://www.docker.com/
**License**: Apache 2.0
**Purpose**: Container runtime and tooling

### Docker Compose
**Project**: Docker Compose
**Website**: https://docs.docker.com/compose/
**License**: Apache 2.0
**Purpose**: Multi-container orchestration and service definition

### Alpine Linux
**Project**: Alpine Linux
**Website**: https://alpinelinux.org/
**License**: Various (mostly MIT, GPL-2.0)
**Purpose**: Minimal container base images for PostgreSQL, Redis, and other services

---

## Container & Orchestration

### QEMU
**Project**: QEMU
**Website**: https://www.qemu.org/
**License**: GPL-2.0
**Purpose**: Virtualization backend for Colima (Intel Macs)

### Lima
**Project**: Linux virtual machines on macOS
**Website**: https://github.com/lima-vm/lima
**License**: Apache 2.0
**Purpose**: VM management layer used by Colima

---

## Databases

### PostgreSQL
**Project**: PostgreSQL Database
**Version**: 16.6
**Website**: https://www.postgresql.org/
**License**: PostgreSQL License
**Purpose**: Primary relational database for Forgejo and development workloads

### MySQL
**Project**: MySQL Community Server
**Version**: 8.0.40
**Website**: https://www.mysql.com/
**License**: GPL-2.0
**Purpose**: Relational database for legacy application support

### MongoDB
**Project**: MongoDB Community Edition
**Version**: 7.0
**Website**: https://www.mongodb.com/
**License**: SSPL
**Purpose**: NoSQL document database for flexible data structures

### PgBouncer
**Project**: PgBouncer
**Website**: https://www.pgbouncer.org/
**License**: ISC
**Purpose**: Lightweight PostgreSQL connection pooler

---

## Caching & Message Queue

### Redis
**Project**: Redis
**Version**: 7.4
**Website**: https://redis.io/
**License**: BSD-3-Clause (Redis Source Available License 2.0 for versions 7.4+)
**Purpose**: In-memory data store and cache, configured as a 3-node cluster

### RabbitMQ
**Project**: RabbitMQ
**Version**: 3.13
**Website**: https://www.rabbitmq.com/
**License**: MPL-2.0
**Purpose**: Message broker for asynchronous task processing and event streaming

---

## Secrets Management & Security

### HashiCorp Vault
**Project**: Vault
**Version**: 1.18
**Website**: https://www.vaultproject.io/
**License**: BSL 1.1 (Business Source License)
**Purpose**: Secrets management, PKI infrastructure, and dynamic credentials

### OpenSSL
**Project**: OpenSSL
**Website**: https://www.openssl.org/
**License**: Apache 2.0
**Purpose**: TLS/SSL certificate generation and cryptographic operations

---

## Observability & Monitoring

### Prometheus
**Project**: Prometheus
**Version**: 2.48.0
**Website**: https://prometheus.io/
**License**: Apache 2.0
**Purpose**: Time-series metrics collection and monitoring system

### Grafana
**Project**: Grafana
**Version**: 10.2.2
**Website**: https://grafana.com/
**License**: AGPL-3.0
**Purpose**: Metrics visualization and dashboarding platform

### Loki
**Project**: Loki
**Version**: 2.9.3
**Website**: https://grafana.com/oss/loki/
**License**: AGPL-3.0
**Purpose**: Log aggregation system optimized for label-based indexing

### Vector
**Project**: Vector
**Version**: 0.50.0
**Website**: https://vector.dev/
**License**: MPL-2.0
**Purpose**: Unified observability pipeline for metrics and logs

### cAdvisor
**Project**: Container Advisor
**Version**: 0.47.2
**Website**: https://github.com/google/cadvisor
**License**: Apache 2.0
**Purpose**: Container resource usage and performance monitoring

### Redis Exporter
**Project**: Redis Exporter
**Version**: 1.55.0
**Maintainer**: oliver006
**Website**: https://github.com/oliver006/redis_exporter
**License**: MIT
**Purpose**: Prometheus exporter for Redis metrics

### Prometheus Client Libraries
**Projects**: prometheus-client (Python), client_golang (Go), prom-client (Node.js)
**Website**: https://prometheus.io/docs/instrumenting/clientlibs/
**License**: Apache 2.0
**Purpose**: Application-level metrics instrumentation

---

## Reference Application Frameworks

### FastAPI
**Project**: FastAPI
**Version**: 0.104.1
**Website**: https://fastapi.tiangolo.com/
**License**: MIT
**Purpose**: Modern Python web framework for building APIs (used in 2 reference implementations)

### Uvicorn
**Project**: Uvicorn
**Version**: 0.24.0
**Website**: https://www.uvicorn.org/
**License**: BSD-3-Clause
**Purpose**: ASGI server for FastAPI applications

### Gin
**Project**: Gin Web Framework
**Version**: 1.9.1
**Website**: https://gin-gonic.com/
**License**: MIT
**Purpose**: High-performance HTTP web framework for Go

### Express.js
**Project**: Express
**Version**: 4.18.2
**Website**: https://expressjs.com/
**License**: MIT
**Purpose**: Minimalist web framework for Node.js

### Actix-web
**Project**: Actix Web
**Version**: 4.4
**Website**: https://actix.rs/
**License**: MIT/Apache-2.0
**Purpose**: Powerful, pragmatic, and extremely fast web framework for Rust

---

## Python Libraries

### Database Drivers
- **asyncpg** (0.29.0) - PostgreSQL async driver - BSD-3-Clause
- **aiomysql** (0.3.0) - MySQL async driver - MIT
- **motor** (3.4.0) - MongoDB async driver - Apache 2.0
- **pymongo** (4.6.3) - MongoDB sync driver - Apache 2.0

### Redis & Caching
- **redis** (4.6.0) - Redis Python client - MIT
- **hiredis** - High-performance Redis protocol parser - BSD-3-Clause
- **fastapi-cache2** (0.2.1) - FastAPI response caching - MIT

### Message Queue
- **aio-pika** (9.3.1) - RabbitMQ async client - Apache 2.0

### HTTP & Networking
- **httpx** (0.25.2) - HTTP client with async support - BSD-3-Clause

### Utilities & Security
- **pydantic** - Data validation using Python type hints - MIT
- **pydantic-settings** (2.1.0) - Settings management - MIT
- **cryptography** (≥41.0.0) - Cryptographic recipes and primitives - Apache 2.0/BSD-3-Clause
- **slowapi** (0.1.9) - Rate limiting for FastAPI - MIT
- **pybreaker** (1.0.1) - Circuit breaker pattern - BSD-3-Clause

### Logging & Observability
- **python-json-logger** (2.0.7) - JSON logging formatter - BSD-2-Clause
- **prometheus-client** (0.19.0) - Prometheus metrics - Apache 2.0

### Testing
- **pytest** (7.4.3) - Testing framework - MIT
- **pytest-asyncio** (0.21.1) - Async support for pytest - Apache 2.0
- **pytest-cov** (4.1.0) - Code coverage plugin - MIT
- **pytest-mock** (3.12.0) - Mocking support - MIT

---

## Go Libraries

### Database Drivers
- **pgx/v5** (5.5.4) - PostgreSQL driver and toolkit - MIT
- **go-sql-driver/mysql** (1.7.1) - MySQL driver - MPL-2.0
- **mongo-driver** (1.13.1) - MongoDB driver - Apache 2.0

### Redis & Caching
- **go-redis/v9** (9.3.0) - Redis client - BSD-2-Clause

### Message Queue
- **amqp091-go** (1.9.0) - RabbitMQ client - BSD-2-Clause

### Vault Integration
- **vault/api** (1.22.0) - HashiCorp Vault API client - MPL-2.0

### Observability
- **client_golang** (1.23.2) - Prometheus metrics - Apache 2.0
- **logrus** (1.9.3) - Structured logger - MIT

### Utilities
- **uuid** (1.4.0) - UUID generation - BSD-3-Clause

---

## Node.js Libraries

### Core Framework & Middleware
- **express** (4.18.2) - Web framework - MIT
- **cors** (2.8.5) - CORS middleware - MIT
- **helmet** (7.1.0) - Security headers - MIT
- **express-rate-limit** (7.1.5) - Rate limiting - MIT

### Database Drivers
- **pg** (8.11.3) - PostgreSQL client - MIT
- **mysql2** (3.6.5) - MySQL client - MIT
- **mongodb** (6.3.0) - MongoDB driver - Apache 2.0

### Redis & Message Queue
- **redis** (4.6.12) - Redis client - MIT
- **amqplib** (0.10.3) - RabbitMQ client - MIT

### Vault Integration
- **node-vault** (0.10.2) - HashiCorp Vault client - MIT

### Observability
- **prom-client** (15.1.0) - Prometheus metrics - Apache 2.0
- **winston** (3.11.0) - Logging library - MIT

### Utilities
- **uuid** (9.0.1) - UUID generation - MIT

### Testing
- **jest** (29.7.0) - Testing framework - MIT
- **supertest** (6.3.3) - HTTP assertion library - MIT

### Development Tools
- **nodemon** (3.0.2) - Development auto-reloader - MIT
- **eslint** (8.56.0) - Linting utility - MIT

---

## Rust Libraries

### Core Framework
- **actix-web** (4.4) - Web framework - MIT/Apache-2.0
- **actix-cors** (0.7) - CORS middleware - MIT/Apache-2.0

### Async Runtime
- **tokio** (1.35) - Async runtime - MIT

### Serialization
- **serde** (1.0) - Serialization framework - MIT/Apache-2.0
- **serde_json** (1.0) - JSON support - MIT/Apache-2.0

### HTTP Client
- **reqwest** (0.11.27) - HTTP client - MIT/Apache-2.0

### Utilities
- **chrono** (0.4.31) - Date and time - MIT/Apache-2.0
- **log** (0.4) - Logging facade - MIT/Apache-2.0
- **env_logger** (0.11.3) - Logger implementation - MIT/Apache-2.0

---

## Development & Testing Tools

### Git & Version Control
- **Forgejo** - Self-hosted Git service - MIT
- **Git** - Version control system - GPL-2.0

### Testing Frameworks
- **Bash Test Framework** - Shell script testing
- **pytest** - Python testing - MIT
- **Jest** - JavaScript testing - MIT
- **Go testing** - Built-in Go testing package - BSD-3-Clause

### Code Quality
- **ShellCheck** - Shell script linter - GPL-3.0
- **ESLint** - JavaScript linter - MIT
- **Ruff** - Python linter - MIT

### Security Scanning
- **Gitleaks** - Secret scanning - MIT
- **TruffleHog** - Secret scanning - AGPL-3.0
- **Trivy** - Vulnerability scanner - Apache 2.0
- **Safety** - Python dependency checker - MIT

---

## Documentation & Specification

### Markdown & Documentation
- **Markdown** - Lightweight markup language
- **Mermaid** - Diagram generation from text - MIT

### API Specification
- **OpenAPI** (3.1.0) - API specification standard
- **Swagger UI** - API documentation interface - Apache 2.0

### Package Managers
- **Homebrew** - macOS package manager - BSD-2-Clause
- **pip** - Python package installer - MIT
- **npm** - Node.js package manager - Artistic-2.0
- **Cargo** - Rust package manager - MIT/Apache-2.0
- **uv** - Fast Python package installer - MIT/Apache-2.0

---

## Special Thanks

We would like to extend special thanks to:

- **The Open Source Community** - For creating and maintaining the thousands of projects that make modern software development possible
- **Alpine Linux Team** - For providing minimal, secure container base images
- **HashiCorp** - For Vault and their commitment to infrastructure tooling
- **Cloud Native Computing Foundation (CNCF)** - For stewarding projects like Prometheus and maintaining cloud-native standards
- **Grafana Labs** - For their observability stack (Grafana, Loki, and related tools)
- **PostgreSQL Global Development Group** - For decades of database excellence
- **Redis Community** - For building one of the most versatile data structures
- **Python Software Foundation** - For Python and its thriving ecosystem
- **Go Team at Google** - For the Go programming language
- **Rust Foundation** - For Rust and its safety-first approach
- **Node.js Foundation** - For the JavaScript runtime
- **Docker, Inc.** - For containerization technology
- **All Contributors** - Everyone who has contributed code, documentation, bug reports, or support to any of the projects listed above

---

## License Information

This project (DevStack Core) is released under the **MIT License**. However, please note that the individual software components acknowledged above are distributed under their respective licenses. Users and contributors should review and comply with the licenses of all dependencies.

For license details of specific dependencies, please refer to their respective project repositories and documentation.

---

## Contributing Acknowledgements

If you use this project and wish to acknowledge additional software or libraries, please submit a pull request updating this document.

---

**Last Updated**: October 28, 2025
**Repository**: https://github.com/NormB/devstack-core
