# Documentation

## Table of Contents

- [Documentation Index](#documentation-index)
  - [Project Information](#project-information)
  - [Security Documentation](#security-documentation)
  - [Testing Documentation](#testing-documentation)
  - [Architecture & Design](#architecture-design)
  - [Operational Guides](#operational-guides)
  - [API Development Patterns](#api-development-patterns)
- [Quick Links](#quick-links)
  - [Project-Level Documentation](#project-level-documentation)
  - [Component Documentation](#component-documentation)
- [Documentation Standards](#documentation-standards)
  - [Writing Guidelines](#writing-guidelines)
  - [File Naming](#file-naming)
  - [Links and References](#links-and-references)
- [Contributing to Documentation](#contributing-to-documentation)
- [Documentation Coverage](#documentation-coverage)
- [Useful Resources](#useful-resources)
  - [External Documentation](#external-documentation)
  - [Infrastructure Components](#infrastructure-components)
  - [Observability Stack](#observability-stack)
- [Documentation Maintenance](#documentation-maintenance)
  - [When to Update Documentation](#when-to-update-documentation)
  - [Review Schedule](#review-schedule)
- [Need Help?](#need-help)

---

This directory contains comprehensive documentation for the DevStack Core project.

## Documentation Index

### Project Information

- **[ACKNOWLEDGEMENTS.md](./ACKNOWLEDGEMENTS.md)** - Software acknowledgements and licenses
  - Complete list of all open-source projects used
  - License information for all dependencies
  - Framework and library acknowledgements
  - Special thanks to the open-source community

### Security Documentation

- **[SECURITY_ASSESSMENT.md](./SECURITY_ASSESSMENT.md)** - Complete security audit and assessment
  - Risk assessment and findings
  - Security by domain (secrets management, network, authentication)
  - Remediation recommendations
  - Best practices implemented

- **[VAULT_SECURITY.md](./VAULT_SECURITY.md)** - HashiCorp Vault security best practices
  - Production deployment recommendations
  - AppRole authentication setup
  - Vault hardening guide
  - Backup and recovery procedures

### Testing Documentation

- **[TESTING_APPROACH.md](./TESTING_APPROACH.md)** - Testing methodology and best practices
  - Unit vs integration testing strategy
  - Test environment setup
  - Test execution guidelines
  - Coverage goals and metrics

- **[TEST_VALIDATION_REPORT.md](./TEST_VALIDATION_REPORT.md)** - Phase 0-2 validation results (NEW - Nov 2025)
  - 100% test pass rate confirmation (494+ tests)
  - Issues found and resolved during validation
  - Performance metrics and security validation
  - Production readiness assessment

- **[NEW_TESTS_SUMMARY.md](./NEW_TESTS_SUMMARY.md)** - Extended test suite summary
  - New test suites added to the project
  - Coverage of Vault, PostgreSQL, PgBouncer, Observability
  - 40+ new test cases across 4 suites
  - Test statistics and implementation details

### Architecture & Design

- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Complete architecture deep-dive
  - System components and hierarchy
  - Network architecture with static IPs
  - Security architecture (PKI, TLS, Vault)
  - Data flow diagrams
  - Service dependencies
  - Deployment architecture
  - Scaling considerations
  - Architectural patterns

### Operational Guides

- **[SERVICE_CATALOG.md](./SERVICE_CATALOG.md)** - Complete service reference (NEW)
  - Single source of truth for all 23 services
  - Service details: profiles, ports, AppRole status, networks
  - Network assignments and port mappings
  - Profile breakdowns with exact service counts
  - AppRole adoption status (16/23 services, 69.6%)

- **[SERVICE_PROFILES.md](./SERVICE_PROFILES.md)** - Service profile system (NEW in v1.3)
  - Flexible service orchestration (minimal, standard, full, reference)
  - Profile comparison and selection guide
  - Use cases and resource requirements
  - Profile combinations and customization
  - Comprehensive environment variable tables per profile

- **[PYTHON_CLI.md](./PYTHON_CLI.md)** - Modern Python CLI (NEW in v1.3)
  - Profile-aware management commands
  - Installation and setup (pip, venv, homebrew)
  - Complete command reference with examples
  - Migration strategy from bash script
  - Beautiful terminal output with Rich library

- **[MANAGEMENT.md](./MANAGEMENT.md)** - Bash management script guide
  - Complete command reference (20+ commands)
  - Daily operations workflow
  - Vault operations
  - Backup and restore procedures
  - Service lifecycle management

- **[UPGRADE_GUIDE.md](./UPGRADE_GUIDE.md)** - Comprehensive upgrade procedures (NEW)
  - Version upgrade paths (v1.2 → v1.3, earlier versions)
  - Service version upgrades (PostgreSQL 18, MySQL, MongoDB, Redis, RabbitMQ)
  - Profile migration procedures (minimal ↔ standard ↔ full)
  - Database migration procedures (pg_dump, logical replication)
  - Backward compatibility considerations
  - Rollback procedures (complete, service-specific, profile)
  - Post-upgrade validation checklist (18 checks)
  - Troubleshooting common upgrade issues

- **[MIGRATION_GUIDE.md](./MIGRATION_GUIDE.md)** - AppRole and TLS migration guide (Phase 4)
  - Root Token → AppRole migration (100% adoption)
  - HTTP → HTTPS (TLS) migration with dual-mode support
  - Pre-migration checklists and prerequisites
  - Step-by-step migration procedures with verification
  - Comprehensive troubleshooting guide
  - Complete rollback procedures
  - Post-migration validation (32 AppRole tests, 24 TLS tests)
  - FAQ and best practices

- **[DISASTER_RECOVERY.md](./DISASTER_RECOVERY.md)** - Disaster recovery procedures
  - 30-minute RTO (Recovery Time Objective)
  - Complete environment loss recovery
  - Vault data loss recovery
  - Database corruption recovery
  - Service-specific recovery procedures
  - Post-recovery validation checklists

- **[ROLLBACK_PROCEDURES.md](./ROLLBACK_PROCEDURES.md)** - Rollback procedures
  - Emergency quick rollback (15-20 minutes)
  - Complete environment rollback
  - Service-specific rollback (PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ)
  - AppRole ↔ Root Token migration procedures
  - Rollback validation checklist
  - Known issues and resolutions

- **[INSTALLATION.md](./INSTALLATION.md)** - Step-by-step installation guide
  - Pre-flight checks and prerequisites
  - Profile selection guidance (Step 4.5)
  - Python script setup (recommended)
  - Bash script setup (traditional)
  - Vault initialization and bootstrap
  - Redis cluster initialization (for standard/full profiles)
  - Complete verification procedures

- **[USAGE.md](./USAGE.md)** - Daily usage guide
  - Starting and stopping services
  - Checking service status and health
  - Accessing service credentials
  - Common development workflows
  - IDE integration

- **[TROUBLESHOOTING.md](./TROUBLESHOOTING.md)** - Troubleshooting guide
  - Common startup issues (especially Vault bootstrap)
  - Service health check failures
  - Network connectivity problems
  - Database, Redis, and Vault issues
  - Complete diagnostic procedures
  - Docker/Colima troubleshooting

- **[PERFORMANCE_TUNING.md](./PERFORMANCE_TUNING.md)** - Performance optimization guide
  - Resource allocation (Colima VM, per-service limits)
  - Database performance tuning
  - Redis cluster optimization
  - API performance (caching, connection pooling)
  - Benchmarking procedures
  - Production scaling strategies

- **[PROFILE_IMPLEMENTATION_GUIDE.md](./PROFILE_IMPLEMENTATION_GUIDE.md)** - Technical profile implementation
  - Docker Compose profile architecture
  - Profile assignment strategy
  - Environment variable loading mechanism
  - Testing and validation procedures
  - Custom profile creation

### API Development Patterns

- **[.API-Patterns](.API-Patterns)** - API design patterns
  - Code-first vs API-first development
  - Pattern implementations
  - Synchronization strategies
  - Testing approaches

- **[../reference-apps/shared/openapi.yaml](../reference-apps/shared/openapi.yaml)** - OpenAPI 3.1.0 specification
  - Complete API contract (841 lines)
  - Single source of truth for both implementations
  - Used to validate synchronization between code-first and API-first
  - Auto-generated documentation at http://localhost:8000/docs

## Quick Links

### Project-Level Documentation

Located in the project root and `.github/`:
- [README.md](../README.md) - Main project documentation
- [CONTRIBUTING.md](../Contributing-Guide) - Contribution guidelines
- [SECURITY.md](../Secrets-Rotation) - Security policy and reporting
- [CODE_OF_CONDUCT.md](../.github/CODE_OF_CONDUCT.md) - Community standards
- [CHANGELOG.md](../Changelog) - Version history

### Component Documentation

- **Reference Applications**
  - [Reference Apps Overview](.Development-Workflow)
  - [FastAPI Code-First](../reference-apps/fastapi/README.md)
  - [FastAPI API-First](../reference-apps/fastapi-api-first/README.md)
  - [Go Reference API](../reference-apps/golang/README.md)
  - [Node.js Reference API](../reference-apps/nodejs/README.md)
  - [Rust Reference API](../reference-apps/rust/README.md)
  - [API Patterns](.API-Patterns)

- **Testing Infrastructure**
  - [Tests Overview](../tests/README.md)
  - [Test Coverage](../tests/TEST_COVERAGE.md)

- **Specialized Documentation**
  - [VoIP Infrastructure](./voip/README.md) - VoIP design, Ansible, and libvirt documentation

## Documentation Standards

### Writing Guidelines

1. **Use Clear Headings** - Organize with H2 (##) and H3 (###) headers
2. **Include Examples** - Provide code samples and command examples
3. **Add Context** - Explain why, not just what
4. **Keep Updated** - Update docs when code changes
5. **Test Commands** - Verify all commands work before documenting

### File Naming

- Use SCREAMING_SNAKE_CASE for major docs: `SECURITY_ASSESSMENT.md`
- Use kebab-case for topic-specific docs: `vault-security.md`
- Use README.md for directory overviews

### Links and References

- Use relative links for internal documentation
- Link to specific sections with anchors: `#heading-name`
- Keep links up to date when moving files

### Wiki Synchronization

Core documentation files are automatically synced from `docs/` to `wiki/` directory:

- **Automated Sync:** GitHub Actions workflow syncs files when PRs are merged to `main`
- **Verification:** `tests/test-documentation-accuracy.sh` includes Test 11 to verify wiki sync
- **Workflow:**
  1. Update source file in `docs/` (e.g., `docs/ARCHITECTURE.md`)
  2. Create pull request with changes
  3. PR is reviewed and merged to `main`
  4. GitHub Actions automatically syncs to `wiki/` (e.g., `wiki/Architecture-Overview.md`)
  5. Test 11 verifies sync in CI/CD
- **Sync Mappings:**
  - `docs/README.md` → `wiki/Documentation-Index.md`
  - `docs/ARCHITECTURE.md` → `wiki/Architecture-Overview.md`
  - `docs/SERVICE_CATALOG.md` → `wiki/Service-Catalog.md`
  - `README.md` → `wiki/Home.md`
  - `Changelog` → `wiki/Changelog.md`
  - And other core documentation files

**Important:** Always update the source file in `docs/`, not the wiki copy. Changes only reach `main` via merged PRs, which trigger the wiki sync workflow.

## Contributing to Documentation

See [CONTRIBUTING.md](../Contributing-Guide) for guidelines on:
- Documentation style guide
- Review process
- Testing documentation changes
- Submitting documentation improvements

## Documentation Coverage

| Category | Files | Status |
|----------|-------|--------|
| Project Information | 1 | ✅ Complete |
| Security | 2 | ✅ Complete |
| Testing | 1 | ✅ Complete |
| Architecture | 1 | ✅ Complete |
| Service Profiles (v1.3) | 3 | ✅ Complete |
| Operational Guides | 9 | ✅ Complete |
| Upgrade Procedures | 1 | ✅ Complete |
| API Patterns | 1 | ✅ Complete |
| Reference Apps | 6 | ✅ Complete |
| VoIP Infrastructure | 3 | ✅ Complete (voip/ subdirectory) |
| **Total Core Documentation Files** | **~28** | **✅ 99% Coverage** |

**Note:** Work-in-progress files (task tracking, test results) are now located in `docs/.private/` (gitignored).

## Useful Resources

### External Documentation

- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [Colima Documentation](https://github.com/abiosoft/colima)
- [Gin Web Framework (Go)](https://gin-gonic.com/)
- [Express.js (Node.js)](https://expressjs.com/)
- [Actix-web (Rust)](https://actix.rs/)

### Infrastructure Components

- [PostgreSQL 18 Documentation](https://www.postgresql.org/docs/18/)
- [MySQL 8.0 Documentation](https://dev.mysql.com/doc/refman/8.0/)
- [MongoDB 7.0 Documentation](https://www.mongodb.com/docs/v7.0/)
- [Redis 7.4 Documentation](https://redis.io/docs/)
- [RabbitMQ 3.13 Documentation](https://www.rabbitmq.com/docs)

### Observability Stack

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/)
- [Vector Documentation](https://vector.dev/docs/)

## Documentation Maintenance

### When to Update Documentation

- ✅ When adding new features
- ✅ When changing configuration
- ✅ When fixing bugs that affect usage
- ✅ When deprecating features
- ✅ After major test runs
- ✅ When security issues are discovered/fixed

### Review Schedule

- **Monthly:** Review for accuracy
- **Quarterly:** Update test results
- **Per Release:** Update Changelog
- **As Needed:** Security documentation

## Need Help?

- 📖 Start with [README.md](../README.md)
- 🔒 Security questions? See [SECURITY.md](../Secrets-Rotation)
- 🧪 Testing questions? See [tests/README.md](../tests/README.md)
- 🚀 API questions? See [reference-apps/README.md](.Development-Workflow)
- 🤝 Want to contribute? See [CONTRIBUTING.md](../Contributing-Guide)
