# DevStack Core Improvement Task List

**Created:** 2025-11-14
**Status:** Not Started
**Current Phase:** Phase 0 - Preparation
**Last Updated:** 2025-11-14
**Document Version:** 2.0

---

## Overview

This document tracks the implementation of 20 improvements identified in the comprehensive codebase analysis. Each task must be completed and tested before moving to the next task. Each phase must be fully completed before moving to the next phase.

**Completion Criteria:**
- ✅ Task implementation complete
- ✅ Tests written and passing
- ✅ Smoke tests pass (no regressions)
- ✅ Documentation updated
- ✅ Rollback tested and verified
- ✅ No breaking changes to existing functionality

---

## Assumptions

1. **Environment:** All work performed on macOS with Apple Silicon
2. **Access:** Full admin access to development environment
3. **Time:** Dedicated time blocks for each phase (no interruptions)
4. **Backups:** Ability to backup/restore entire environment quickly
5. **External Services:** No external service dependencies (S3, email, etc.) required initially
6. **Team Size:** Single person implementing (adjust estimates for team)
7. **Testing:** Comprehensive testing possible in dev environment
8. **Rollback:** Acceptable to rollback if critical issues found
9. **Timeline:** Flexible timeline, quality over speed
10. **Scope:** Can defer tasks to future phases if needed

---

## Constraints

1. **Zero Downtime Required:** Development environment, downtime acceptable
2. **Budget:** No budget for external services (GitHub Actions minutes, S3 storage)
3. **Hardware:** Limited to single development machine
4. **Network:** Local development only, no cloud deployment
5. **Time:** Target completion within 4-5 weeks
6. **Compatibility:** Must maintain compatibility with existing configurations
7. **Documentation:** All changes must be documented
8. **Testing:** All changes must be tested
9. **Security:** Security improvements cannot degrade security
10. **Performance:** Performance improvements cannot degrade performance

---

## Resource Requirements

### Disk Space
- Vault backups: ~10MB daily × 30 days = ~300MB
- Database backups: ~500MB daily × 7 days = ~3.5GB
- Migration frameworks: ~200MB
- Test artifacts and logs: ~500MB
- **Total additional:** ~4.5GB disk space minimum

### Memory
- Alertmanager: +128MB
- Flyway/Liquibase (temporary): +256MB during migrations
- Test containers (temporary): +512MB during CI/CD tests
- **Total additional:** +896MB RAM (peak during testing)

### Network Ports
- Alertmanager: 9093
- Verify available: `netstat -an | grep 9093`

### External Services (Optional)
- GPG for backup encryption (install if missing: `brew install gnupg`)
- S3 bucket or external storage (for secure backups - Phase 1.3)
- Email/Slack for Alertmanager (optional but recommended - Phase 2.2)

### Tools Required
- Docker Desktop or Colima
- Git
- Python 3.11+ with uv
- Vault CLI
- jq (for JSON parsing)
- shellcheck (for bash linting)

---

## Risk Register

| Risk ID | Description | Probability | Impact | Mitigation | Owner | Status |
|---------|-------------|-------------|--------|------------|-------|--------|
| R1 | AppRole breaks all services | Medium | High | Keep root token fallback via VAULT_USE_ROOT_TOKEN=true | Phase 1 | Open |
| R2 | Backup encryption passphrase lost | Low | Critical | Document passphrase in secure location, Test restoration regularly | Phase 1 | Open |
| R3 | CI/CD integration tests infeasible | High | Medium | Use alternative testing strategy (manual integration tests) | Phase 2 | Open |
| R4 | set -euo pipefail breaks scripts | Medium | Medium | Test incrementally, Use -eo pipefail first, Add -u selectively | Phase 3 | Open |
| R5 | Performance degradation during changes | Low | Medium | Measure baseline first, Monitor continuously, Rollback if >5% degradation | All | Open |
| R6 | Time estimates too optimistic | High | Low | Added 40% buffer to all estimates, Track actual vs. estimated | All | Open |
| R7 | Vault data loss during implementation | Low | Critical | Full backup in Phase 0, Test restoration before starting | Phase 0 | Open |
| R8 | Database migration failures | Medium | Medium | Test on copy of data first, Maintain rollback scripts | Phase 2 | Open |

---

## Task Dependencies

### Phase 0 Dependencies
```
All Phase 0 tasks must complete before Phase 1 starts
No internal dependencies within Phase 0
```

### Phase 1 Dependencies
```
Task 1.1 (AppRole) ────────┐
                           ├──> Task 1.2 (Remove Env Creds) ──┐
                           │                                    │
Task 1.3 (Vault Backup) ───┼──────────────────────────────────┼──> Phase 1 Complete
Task 1.4 (MySQL Fix) ──────┤                                    │
Task 1.5 (Document) ───────┘                                    │
                                                                 │
All tasks must complete ─────────────────────────────────────────┘
```

**Recommended Execution Order:**
1. Complete Task 1.1 fully (including integration testing)
2. Start Tasks 1.3, 1.4, 1.5 in parallel (independent)
3. Complete Task 1.2 (after 1.1 confirmed working)

### Phase 2 Dependencies
```
Task 2.2 (Alertmanager) ──┬──> Task 2.1 (Alert Rules) ──────┐
                          └──> Task 2.3 (Backup Verify) ────┤
                                                              ├──> Phase 2 Complete
Task 2.4 (Migrations) ────────────────────────────────────────┤
Task 2.5 (CI/CD Tests) ───────────────────────────────────────┘
```

**Recommended Execution Order:**
1. Complete Task 2.2 (Alertmanager) first
2. Start Task 2.1 (after 2.2 working)
3. Start Tasks 2.4, 2.5 in parallel (independent)
4. Complete Task 2.3 (after 2.2 working)

### Phase 3 Dependencies
```
All Phase 3 tasks are independent (can run in parallel)
Task 3.1, 3.2, 3.3, 3.4, 3.5 ──> Phase 3 Complete
```

### Phase 4 Dependencies
```
All Phase 4 tasks are independent (can run in parallel)
Task 4.1, 4.2, 4.3, 4.4, 4.5 ──> Phase 4 Complete
```

---

## Progress Tracking

**Update this section daily:**

**Phase 0 Progress:** 0% (0/1 tasks)
**Phase 1 Progress:** 0% (0/5 tasks)
**Phase 2 Progress:** 0% (0/5 tasks)
**Phase 3 Progress:** 0% (0/5 tasks)
**Phase 4 Progress:** 0% (0/5 tasks)
**Overall Progress:** 0% (0/21 tasks)

**Current Status:** Not Started
**Current Task:** N/A
**Blockers:** None
**Start Date:** TBD
**Expected Completion:** TBD (4-5 weeks from start)
**Last Updated:** 2025-11-14

---

## Success Metrics

**Baseline Metrics (Measure in Phase 0):**
- Test coverage: ___% (run `pytest --cov` + `go test -cover`)
- Security score: ___ (run `./scripts/audit-capabilities.sh`)
- Performance p95: ___ ms per endpoint (run `tests/performance-benchmark.sh`)
- Total test count: ___ tests passing

**Target Metrics After Phase 1:**
- Test coverage improvement: +5% (from baseline)
- Security score improvement: +15% (AppRole + credential fixes)
- Performance: p95 latency ≤ baseline + 5% (no significant degradation)
- All existing tests still passing + new security tests

**Target Metrics After Phase 2:**
- Test coverage improvement: +10% (from baseline)
- Alert coverage: 100% of critical services monitored
- Backup verification: 100% automated
- Migration framework: 100% of databases covered

**Target Metrics After Phase 3:**
- Test coverage improvement: +15% (from baseline)
- Code quality: ShellCheck passing 100% of scripts
- API consistency: 100% parity across Python, Go, Node.js (partial for Rust)

**Target Metrics After Phase 4:**
- Test coverage improvement: +18% (from baseline)
- Performance regression: Automated in CI/CD
- Documentation coverage: 100% (runbooks + ADRs)
- Developer experience: Measured by setup time reduction

**Measurement Tools:**
- Test coverage: `pytest --cov` + `go test -cover` + Jest coverage
- Security score: `./scripts/audit-capabilities.sh` + Trivy scan results
- Performance: `tests/performance-benchmark.sh`
- Test count: `./tests/run-all-tests.sh --count`

---

## Phase 0 - Preparation (Estimated: 2-3 hours)

**Purpose:** Establish baseline, safety nets, and documentation before making any changes.

### Task 0.1: Establish Baseline and Safety Net

**Priority:** Critical 🔴
**Status:** Not Started
**Estimated Time:** 3 hours
**Impact:** Critical - Prevents data loss and provides rollback capability

**Current Issue:**
- No documented baseline for comparison
- No verified backup for disaster recovery
- No clean starting point for changes

**Implementation Steps:**

1. **Subtask 0.1.1:** Full environment backup
   - [ ] Backup Vault keys: `cp -r ~/.config/vault ~/vault-backup-$(date +%Y%m%d)`
   - [ ] Verify Vault backup contains: keys.json, root-token, ca/, certs/
   - [ ] Run database backup: `./manage-devstack backup`
   - [ ] Note backup location and timestamp
   - [ ] Export all docker volumes: `docker volume ls -q | xargs -I {} docker run --rm -v {}:/data -v $(pwd)/backups:/backup alpine tar czf /backup/{}.tar.gz -C /data .`
   - [ ] Calculate total backup size: `du -sh ~/vault-backup-* backups/`
   - **Test:** Verify backups exist and are non-zero size
   - **Test:** Restore Vault backup to temporary location and verify contents

2. **Subtask 0.1.2:** Document current state (baseline)
   - [ ] Run `./manage-devstack status` and save output to `baseline/status.txt`
   - [ ] Run `./tests/run-all-tests.sh` and save results to `baseline/test-results.txt`
   - [ ] Measure performance: `tests/performance-benchmark.sh > baseline/performance.txt`
   - [ ] Document service versions: `docker compose images > baseline/versions.txt`
   - [ ] Measure test coverage: `docker exec dev-reference-api pytest tests/ --cov --cov-report=term > baseline/coverage.txt`
   - [ ] Run security audit: `./scripts/audit-capabilities.sh > baseline/security.txt` (create if doesn't exist)
   - [ ] Count total tests: `./tests/run-all-tests.sh 2>&1 | grep -E "tests? passed" | tee baseline/test-count.txt`
   - **Test:** All baseline files created and contain data
   - **Test:** Baseline shows all services healthy and all tests passing

3. **Subtask 0.1.3:** Create feature branch
   - [ ] Ensure working directory is clean: `git status`
   - [ ] Create branch: `git checkout -b improvement-phases-1-4`
   - [ ] Push branch: `git push -u origin improvement-phases-1-4`
   - [ ] Document branch strategy in commit message
   - **Test:** Branch created and pushed to remote
   - **Test:** Can switch back to main and return to feature branch

4. **Subtask 0.1.4:** Verify environment health
   - [ ] All services healthy: `./manage-devstack health` (all green)
   - [ ] All tests passing: `./tests/run-all-tests.sh` (0 failures)
   - [ ] No pending git changes: `git status` (clean working tree)
   - [ ] Sufficient disk space: `df -h` (>10GB free)
   - [ ] Vault unsealed and accessible: `vault status`
   - **Test:** Clean starting point confirmed
   - **Test:** Environment matches baseline

5. **Subtask 0.1.5:** Set up task tracking
   - [ ] Update this document with start date
   - [ ] Create `baseline/` directory for all baseline measurements
   - [ ] Set up daily progress update reminder (calendar/cron)
   - [ ] Review risk register and accept risks
   - [ ] Confirm resource requirements are met
   - **Test:** Tracking mechanisms in place
   - **Test:** All Phase 0 subtasks completed

6. **Subtask 0.1.6:** Create rollback documentation
   - [ ] Document rollback procedure for Vault: `docs/ROLLBACK_PROCEDURES.md`
   - [ ] Document rollback procedure for databases
   - [ ] Document rollback procedure for docker-compose changes
   - [ ] Document rollback procedure for git changes
   - [ ] Test rollback from backup (dry run)
   - **Test:** Rollback procedures documented and tested

---

## Phase 0 Completion Criteria

- [ ] All baseline measurements documented
- [ ] Full environment backup completed and verified
- [ ] Feature branch created and pushed
- [ ] Environment health verified (all services healthy, all tests passing)
- [ ] Task tracking mechanisms in place
- [ ] Rollback procedures documented and tested
- [ ] Sufficient disk space available (>10GB free)
- [ ] All tools installed (docker, git, python, vault, jq, shellcheck, gpg)
- [ ] Risk register reviewed and accepted

**Phase 0 Sign-off:** _________________ Date: _________

---

## Phase 1 - Critical Security (Estimated: 3-4 days)

**Total Time:** 28 hours (with 40% buffer: ~39 hours)

### Task 1.1: Implement Vault AppRole Authentication

**Priority:** Critical 🔴
**Status:** Not Started
**Estimated Time:** 12 hours (was 8h, +50% for complexity)
**Impact:** High - Prevents compromised services from accessing all Vault secrets

**Current Issue:**
- All services use root token passed via `VAULT_TOKEN` environment variable
- Any compromised service has full Vault access
- File: `docker-compose.yml:74`

**Implementation Steps:**

1. **Subtask 1.1.1:** Create AppRole policies for each service
   - [ ] Create `configs/vault/policies/postgres-policy.hcl`
   - [ ] Create `configs/vault/policies/mysql-policy.hcl`
   - [ ] Create `configs/vault/policies/mongodb-policy.hcl`
   - [ ] Create `configs/vault/policies/redis-policy.hcl`
   - [ ] Create `configs/vault/policies/rabbitmq-policy.hcl`
   - [ ] Create `configs/vault/policies/forgejo-policy.hcl`
   - [ ] Create `configs/vault/policies/pgbouncer-policy.hcl`
   - [ ] Create `configs/vault/policies/reference-api-policy.hcl`
   - **Test:** Validate policy syntax with `vault policy fmt <file>`
   - **Test:** Each policy file is valid HCL

2. **Subtask 1.1.2:** Update vault-bootstrap.sh to enable AppRole and create roles
   - [ ] Enable AppRole auth method
   - [ ] Upload all policies to Vault
   - [ ] Create AppRole for each service with appropriate policy
   - [ ] Generate role_id for each service (deterministic, not secret)
   - [ ] Generate secret_id for each service
   - [ ] Create directory: `mkdir -p ~/.config/vault/approles/`
   - [ ] Store role_id in `~/.config/vault/approles/<service>-role-id`
   - [ ] Store secret_id in `~/.config/vault/approles/<service>-secret-id`
   - [ ] Set permissions: `chmod 600 ~/.config/vault/approles/*`
   - [ ] Add note about mounting approles directory into containers
   - **Test:** Verify AppRoles created with `vault list auth/approle/role`
   - **Test:** Verify credential files exist and are readable
   - **Test:** Test login with AppRole: `vault write auth/approle/login role_id=<id> secret_id=<secret>`

3. **Subtask 1.1.3:** Update service init scripts to use AppRole authentication
   - [ ] Create shared function: `vault_approle_login()` in each init script
   - [ ] Update `configs/postgres/scripts/init.sh` to use AppRole
   - [ ] Update `configs/mysql/scripts/init.sh` to use AppRole
   - [ ] Update `configs/mongodb/scripts/init.sh` to use AppRole
   - [ ] Update `configs/redis/scripts/init.sh` to use AppRole
   - [ ] Update `configs/rabbitmq/scripts/init.sh` to use AppRole
   - [ ] Update `configs/forgejo/scripts/init.sh` to use AppRole
   - [ ] Update `configs/pgbouncer/scripts/init.sh` to use AppRole
   - [ ] Update reference app configurations (environment-based)
   - [ ] Add fallback to root token if `VAULT_USE_ROOT_TOKEN=true`
   - **Test:** Verify each service can authenticate with AppRole
   - **Test:** Verify each service can retrieve its secrets
   - **Test:** Verify fallback works with `VAULT_USE_ROOT_TOKEN=true`

4. **Subtask 1.1.4:** Update docker-compose.yml to pass role credentials
   - [ ] Mount approles directory: `~/.config/vault/approles:/vault-approles:ro`
   - [ ] Keep `VAULT_TOKEN` for backward compatibility
   - [ ] Add `VAULT_USE_APPROLE=true` environment variable
   - [ ] Add `VAULT_APPROLE_PATH=/vault-approles` environment variable
   - [ ] Update service dependencies (no changes needed)
   - [ ] Update health checks (no changes needed)
   - **Test:** `docker compose config` validates successfully
   - **Test:** No syntax errors in docker-compose.yml

5. **Subtask 1.1.5:** Update .env.example
   - [ ] Add `# AppRole Authentication (recommended for production)` section
   - [ ] Add `VAULT_USE_APPROLE=true` with explanation
   - [ ] Add `VAULT_APPROLE_PATH=/vault-approles` with explanation
   - [ ] Add `# Root Token Authentication (development only)` section
   - [ ] Add `VAULT_USE_ROOT_TOKEN=false` with warning
   - [ ] Document when to use each method
   - **Test:** New users can understand configuration
   - **Test:** .env.example has clear comments

6. **Subtask 1.1.6:** Update management script for AppRole support
   - [ ] Update `scripts/manage_devstack.py` vault-bootstrap command
   - [ ] Update `vault-show-password` to work with AppRole or root token
   - [ ] Add `vault-approle-status` command to show AppRole status
   - [ ] Update documentation strings in management script
   - [ ] Add error handling for missing approle credentials
   - **Test:** Run `./manage-devstack vault-show-password postgres`
   - **Test:** Run `./manage-devstack vault-approle-status`

7. **Subtask 1.1.7:** Create documentation for AppRole implementation
   - [ ] Update `docs/VAULT.md` with AppRole section (400+ lines)
   - [ ] Document AppRole authentication flow with diagram
   - [ ] Update `docs/SECURITY_ASSESSMENT.md` with AppRole security benefits
   - [ ] Add AppRole troubleshooting guide to `docs/VAULT.md`
   - [ ] Document root token fallback mechanism
   - [ ] Add migration guide from root token to AppRole
   - **Test:** Documentation review for accuracy
   - **Test:** Documentation completeness check

8. **Subtask 1.1.8:** Integration testing
   - [ ] Stop all services: `./manage-devstack stop`
   - [ ] Clear any cached tokens
   - [ ] Set `VAULT_USE_APPROLE=true` in .env
   - [ ] Start services: `./manage-devstack start`
   - [ ] Test Vault bootstrap: `./manage-devstack vault-bootstrap`
   - [ ] Test service authentication to Vault (check logs)
   - [ ] Test secret retrieval from all services
   - [ ] Run test suite: `./tests/test-vault.sh`
   - [ ] Run full test suite: `./tests/run-all-tests.sh`
   - [ ] Test root token fallback: Set `VAULT_USE_ROOT_TOKEN=true` and restart
   - **Test:** All services healthy and functioning
   - **Test:** All tests passing (0 regressions)
   - **Test:** Vault shows AppRole logins in audit log

9. **Subtask 1.1.9:** Rollback testing
   - [ ] Document rollback steps to root token
   - [ ] Test rollback: Set `VAULT_USE_ROOT_TOKEN=true`
   - [ ] Restart services with root token
   - [ ] Verify all services start successfully
   - [ ] Verify all tests still pass
   - [ ] Document time required for rollback (~5 minutes)
   - [ ] Re-enable AppRole after successful rollback test
   - **Test:** Rollback works successfully
   - **Test:** Can switch back to AppRole without issues

**Rollback Plan:**
```bash
# In .env file:
VAULT_USE_ROOT_TOKEN=true
VAULT_USE_APPROLE=false

# Restart services:
./manage-devstack restart
```

**Post-Task Validation:**
- [ ] Smoke test: `./manage-devstack health` (all services healthy)
- [ ] No regressions: `./tests/run-all-tests.sh` (all tests pass)
- [ ] Performance check: No significant latency increase (<5%)
- [ ] Security audit: Verify services use AppRole (check Vault audit log)

---

### Task 1.2: Remove Credentials from Environment Variables

**Priority:** Critical 🔴
**Status:** Not Started
**Estimated Time:** 8 hours (was 6h, +33% for testing)
**Impact:** High - Prevents credential exposure via docker inspect and process listing
**Depends On:** Task 1.1 (AppRole authentication must be working)

**Current Issue:**
- Credentials exported to environment variables (visible in `docker inspect`)
- Files: All `configs/*/scripts/init.sh` files
- Risk: Process listing, container inspection exposes passwords

**Implementation Steps:**

1. **Subtask 1.2.1:** Create secure credential file handling function
   - [ ] Create shared function library: `configs/shared/vault-helpers.sh`
   - [ ] Add `create_secure_creds_file()` function
   - [ ] Add `cleanup_creds_file()` function
   - [ ] Implement proper file permissions (chmod 600)
   - [ ] Implement cleanup trap on script exit
   - [ ] Add error handling for file operations
   - **Test:** Verify file permissions set correctly (600)
   - **Test:** Verify cleanup happens on script exit (normal and error)

2. **Subtask 1.2.2:** Update PostgreSQL init script
   - [ ] Source shared vault-helpers.sh
   - [ ] Modify `configs/postgres/scripts/init.sh`
   - [ ] Write credentials to temporary PGPASSFILE instead of export
   - [ ] Pass credentials via PGPASSFILE environment (points to file, not password)
   - [ ] Remove export statements for POSTGRES_PASSWORD
   - [ ] Keep POSTGRES_USER in environment (not sensitive)
   - [ ] Add cleanup trap for temp files
   - **Test:** PostgreSQL starts successfully
   - **Test:** Credentials not in `docker inspect dev-postgres`
   - **Test:** `ps aux` doesn't show password during startup

3. **Subtask 1.2.3:** Update MySQL init script
   - [ ] Source shared vault-helpers.sh
   - [ ] Modify `configs/mysql/scripts/init.sh`
   - [ ] Create temporary `.my.cnf` file for credentials
   - [ ] Use `--defaults-file=/path/to/.my.cnf` instead of `-p`
   - [ ] Remove export statements for MYSQL_ROOT_PASSWORD
   - [ ] Add cleanup trap for .my.cnf
   - **Test:** MySQL starts successfully
   - **Test:** Credentials not in environment

4. **Subtask 1.2.4:** Update MongoDB init script
   - [ ] Source shared vault-helpers.sh
   - [ ] Modify `configs/mongodb/scripts/init.sh`
   - [ ] Write credentials to MongoDB config file
   - [ ] Use `--config /path/to/mongod.conf`
   - [ ] Remove export statements for MONGO_INITDB_ROOT_PASSWORD
   - [ ] Add cleanup trap
   - **Test:** MongoDB starts successfully
   - **Test:** Credentials not in environment

5. **Subtask 1.2.5:** Update Redis init scripts (all 3 nodes)
   - [ ] Source shared vault-helpers.sh
   - [ ] Modify `configs/redis/scripts/init.sh`
   - [ ] Write credentials to Redis ACL file
   - [ ] Use `--aclfile /path/to/acl.conf`
   - [ ] Remove export statements for REDIS_PASSWORD
   - [ ] Apply to all 3 nodes (redis-1, redis-2, redis-3)
   - [ ] Add cleanup trap
   - **Test:** Redis cluster starts successfully
   - **Test:** Credentials not in environment for all 3 nodes

6. **Subtask 1.2.6:** Update RabbitMQ init script
   - [ ] Source shared vault-helpers.sh
   - [ ] Modify `configs/rabbitmq/scripts/init.sh`
   - [ ] Write credentials to RabbitMQ config file
   - [ ] Use `--config /path/to/rabbitmq.conf`
   - [ ] Remove export statements for RABBITMQ_DEFAULT_PASS
   - [ ] Add cleanup trap
   - **Test:** RabbitMQ starts successfully
   - **Test:** Credentials not in environment

7. **Subtask 1.2.7:** Update Forgejo init script
   - [ ] Source shared vault-helpers.sh
   - [ ] Modify `configs/forgejo/scripts/init.sh`
   - [ ] Write credentials to secure temp file
   - [ ] Pass via file descriptor or config file
   - [ ] Remove export statements for sensitive data
   - [ ] Add cleanup trap
   - **Test:** Forgejo starts successfully
   - **Test:** Credentials not in environment

8. **Subtask 1.2.8:** Update PgBouncer init script
   - [ ] Source shared vault-helpers.sh
   - [ ] Modify `configs/pgbouncer/scripts/init.sh`
   - [ ] Write credentials to userlist.txt (PgBouncer format)
   - [ ] Set file permissions to 600
   - [ ] Remove export statements for sensitive data
   - [ ] Add cleanup trap
   - **Test:** PgBouncer starts successfully
   - **Test:** Credentials not in environment

9. **Subtask 1.2.9:** Audit reference applications for credential exposure
   - [ ] Review Python FastAPI application logging (no credential logging)
   - [ ] Review Go application environment handling
   - [ ] Review Node.js application credential management
   - [ ] Review Rust application secret handling
   - [ ] Add warning comments in code: "# WARNING: Do not log this value"
   - [ ] Add credential redaction to logging middleware
   - **Test:** No credentials in application logs
   - **Test:** Search logs for common password patterns: `grep -ri "password.*:" logs/`

10. **Subtask 1.2.10:** Integration testing
    - [ ] Stop all services
    - [ ] Start services: `./manage-devstack start`
    - [ ] Verify `docker inspect dev-postgres | grep -i password` returns nothing
    - [ ] Verify `docker inspect dev-mysql | grep -i password` returns nothing
    - [ ] Check all services: postgres, mysql, mongodb, redis-1/2/3, rabbitmq, forgejo, pgbouncer
    - [ ] Monitor `ps aux` during startup for password exposure
    - [ ] Run all service tests: `./tests/run-all-tests.sh`
    - [ ] Check application logs for credential leakage
    - **Test:** All tests passing, no credential leakage
    - **Test:** All services healthy and functioning

11. **Subtask 1.2.11:** Create validation script
    - [ ] Create `scripts/validate-no-credential-exposure.sh`
    - [ ] Script checks `docker inspect` for all services
    - [ ] Script checks process list for password patterns
    - [ ] Script checks logs for credential patterns
    - [ ] Exit with error if any credentials found
    - [ ] Add to test suite: `./tests/test-security.sh`
    - **Test:** Validation script passes
    - **Test:** Validation script detects intentionally exposed test credential

12. **Subtask 1.2.12:** Rollback testing
    - [ ] Document rollback steps
    - [ ] Test reverting one service to old method
    - [ ] Verify service still works
    - [ ] Revert back to secure method
    - [ ] Document time required for rollback
    - **Test:** Rollback works successfully

**Validation Script:**
```bash
#!/bin/bash
# scripts/validate-no-credential-exposure.sh
set -e

echo "Checking for credential exposure..."

# Check docker inspect for all services
for service in postgres mysql mongodb redis-1 redis-2 redis-3 rabbitmq forgejo pgbouncer; do
  if docker inspect "dev-$service" 2>/dev/null | grep -iE "(password|secret|token)" | grep -v "VAULT_TOKEN"; then
    echo "FAIL: Credentials found in dev-$service environment"
    exit 1
  fi
done

# Check process list
if ps aux | grep -iE "password=|passwd=|-p[[:space:]]*[^[:space:]]" | grep -v grep; then
  echo "FAIL: Credentials found in process list"
  exit 1
fi

echo "PASS: No credential exposure detected"
```

**Post-Task Validation:**
- [ ] Smoke test: `./manage-devstack health`
- [ ] No regressions: `./tests/run-all-tests.sh`
- [ ] Security validation: `./scripts/validate-no-credential-exposure.sh`
- [ ] Performance check: No degradation

---

### Task 1.3: Add Automated Vault Backup with Encryption

**Priority:** Critical 🔴
**Status:** Not Started
**Estimated Time:** 5 hours (was 2h, +150% for security and testing)
**Impact:** Critical - Prevents irrecoverable data loss

**Current Issue:**
- Vault keys stored at `~/.config/vault/` with no automated backup
- If directory deleted, all data is irrecoverable
- No backup verification
- No backup retention policy

**Implementation Steps:**

1. **Subtask 1.3.1:** Create encrypted backup script
   - [ ] Create `scripts/vault-backup.sh`
   - [ ] Implement GPG encryption with AES256
   - [ ] Support passphrase from environment variable: `VAULT_BACKUP_PASSPHRASE`
   - [ ] Support passphrase prompt if env var not set
   - [ ] Create timestamped backup directory: `~/devstack-backups/vault/YYYYMMDD_HHMMSS/`
   - [ ] Backup keys.json → keys.json.gpg
   - [ ] Backup root-token → root-token.gpg
   - [ ] Backup entire ca/ directory → ca.tar.gz.gpg
   - [ ] Backup entire certs/ directory → certs.tar.gz.gpg
   - [ ] Create manifest file with checksums
   - [ ] Log backup to `~/devstack-backups/vault/backup.log`
   - **Test:** Run script and verify encrypted files created
   - **Test:** Verify unencrypted originals not in backup directory

2. **Subtask 1.3.2:** Create backup restoration script
   - [ ] Create `scripts/vault-restore.sh`
   - [ ] Implement GPG decryption
   - [ ] Support passphrase from environment or prompt
   - [ ] Create backup of existing files before restore: `~/.config/vault.bak-$(date +%s)`
   - [ ] Verify checksums from manifest after decryption
   - [ ] Restore all files to `~/.config/vault/`
   - [ ] Set correct file permissions (600 for keys, 644 for certs)
   - [ ] Log restoration to `~/devstack-backups/vault/restore.log`
   - **Test:** Restore from backup and verify integrity
   - **Test:** Verify checksums match original

3. **Subtask 1.3.3:** Implement backup rotation policy
   - [ ] Create `scripts/vault-backup-rotate.sh`
   - [ ] Keep last 7 daily backups
   - [ ] Keep last 4 weekly backups (Sunday)
   - [ ] Keep last 12 monthly backups (1st of month)
   - [ ] Automatic cleanup of old backups based on policy
   - [ ] Log rotation activity
   - [ ] Calculate and log disk space savings
   - **Test:** Create multiple backups and verify rotation works
   - **Test:** Verify correct backups kept (7 daily, 4 weekly, 12 monthly)

4. **Subtask 1.3.4:** Add backup commands to management script
   - [ ] Add `vault-backup` command to `manage_devstack.py`
   - [ ] Add `vault-restore` command with timestamp parameter
   - [ ] Add `vault-list-backups` command (shows available backups)
   - [ ] Add `vault-verify-backup` command (checksum verification)
   - [ ] Add `vault-rotate-backups` command
   - [ ] Add `--passphrase` option for non-interactive mode
   - [ ] Add `--no-encrypt` option for testing (not recommended)
   - **Test:** Run `./manage-devstack vault-backup`
   - **Test:** Run `./manage-devstack vault-list-backups`
   - **Test:** Run `./manage-devstack vault-verify-backup <timestamp>`

5. **Subtask 1.3.5:** Create automated backup schedule documentation
   - [ ] Document cron job setup in `docs/DISASTER_RECOVERY.md`
   - [ ] Add cron example: `0 2 * * * /path/to/vault-backup.sh`
   - [ ] Add backup best practices section
   - [ ] Document passphrase management (use password manager)
   - [ ] Document off-site backup procedures (external drive, not GitHub)
   - [ ] **SECURITY:** Document why GitHub Actions artifacts are insecure
   - [ ] Document S3/external storage options (future improvement)
   - [ ] Create backup verification checklist
   - **Test:** Documentation review for security
   - **Test:** Documentation completeness

6. **Subtask 1.3.6:** Create manual backup reminder (skip GitHub Actions)
   - [ ] Add backup reminder to weekly routine (Monday morning)
   - [ ] Document manual backup to external drive procedure
   - [ ] Create `scripts/backup-to-external.sh` template
   - [ ] Document encryption-at-rest requirements for external storage
   - [ ] Skip GitHub Actions workflow (insecure for Vault keys)
   - [ ] Note: Future improvement could use AWS S3 with SSE-KMS
   - **Test:** Manual backup procedure tested
   - **Test:** External drive backup tested (if available)

7. **Subtask 1.3.7:** Integration testing
   - [ ] Create test backup: `./manage-devstack vault-backup`
   - [ ] Verify encryption: Cannot read .gpg files without passphrase
   - [ ] List backups: `./manage-devstack vault-list-backups`
   - [ ] Verify backup: `./manage-devstack vault-verify-backup <timestamp>`
   - [ ] Restore to temporary location for testing
   - [ ] Verify restored files match originals (checksum)
   - [ ] Test rotation policy with multiple backups
   - [ ] Test passphrase prompt (interactive mode)
   - [ ] Test passphrase from environment (non-interactive)
   - **Test:** Backup and restore cycle successful
   - **Test:** Rotation policy works correctly

8. **Subtask 1.3.8:** Rollback testing
   - [ ] Document rollback steps
   - [ ] Simulate corrupted Vault keys
   - [ ] Restore from backup
   - [ ] Verify Vault functionality restored
   - [ ] Document time required for recovery (~10 minutes)
   - **Test:** Disaster recovery successful

**Backup Location:** `~/devstack-backups/vault/YYYYMMDD_HHMMSS/`

**Security Note:**
- ❌ **DO NOT** upload Vault backups to GitHub Actions artifacts (insecure)
- ✅ **DO** use external encrypted drive or S3 with SSE-KMS
- ✅ **DO** store passphrase in secure password manager

**Post-Task Validation:**
- [ ] Smoke test: Create and restore backup successfully
- [ ] Security check: Verify encryption works (cannot read without passphrase)
- [ ] Rotation test: Verify old backups are cleaned up
- [ ] Documentation complete: DISASTER_RECOVERY.md updated

---

### Task 1.4: Fix MySQL Password Exposure in Backup Command

**Priority:** Critical 🔴
**Status:** Not Started
**Estimated Time:** 2 hours (was 1h, +100% for all databases)
**Impact:** High - Prevents password visibility in process listing

**Current Issue:**
- Password passed via command-line argument in mysqldump
- File: `scripts/manage_devstack.py:953`
- Visible in `ps aux` during backup operation
- Same issue exists for PostgreSQL and MongoDB

**Implementation Steps:**

1. **Subtask 1.4.1:** Update MySQL backup function to use config file
   - [ ] Modify `backup()` function in `manage_devstack.py` (around line 950)
   - [ ] Create temporary `.my.cnf` file with credentials
   - [ ] Use `--defaults-file=/path/to/.my.cnf` instead of `-p` flag
   - [ ] Ensure temp file cleanup with try/finally block
   - [ ] Set file permissions to 600 before writing password
   - [ ] Remove .my.cnf in finally block
   - **Test:** Run `./manage-devstack backup`
   - **Test:** Monitor `ps aux` during backup (no password visible)

2. **Subtask 1.4.2:** Apply same fix to MySQL restore function
   - [ ] Modify `restore()` function in `manage_devstack.py`
   - [ ] Use config file method for mysql restore
   - [ ] Ensure cleanup with try/finally
   - **Test:** Run `./manage-devstack restore <timestamp>`
   - **Test:** Verify password not in `ps aux`

3. **Subtask 1.4.3:** Update PostgreSQL backup for consistency
   - [ ] Modify PostgreSQL backup in `manage_devstack.py`
   - [ ] Create temporary `.pgpass` file instead of PGPASSWORD env var
   - [ ] Format: `localhost:5432:*:postgres:password`
   - [ ] Set permissions to 600
   - [ ] Use PGPASSFILE environment variable (points to file)
   - [ ] Remove .pgpass in finally block
   - **Test:** PostgreSQL backup with no password exposure
   - **Test:** Verify .pgpass file created with correct permissions

4. **Subtask 1.4.4:** Update MongoDB backup for consistency
   - [ ] Modify MongoDB backup in `manage_devstack.py`
   - [ ] Create temporary MongoDB config file
   - [ ] Use `--config /path/to/mongod.conf` flag
   - [ ] Set permissions to 600
   - [ ] Remove config file in finally block
   - **Test:** MongoDB backup with no password exposure

5. **Subtask 1.4.5:** Create process monitoring test
   - [ ] Create `tests/test-backup-security.sh`
   - [ ] Start backup in background
   - [ ] Monitor `ps aux` every 0.1s during backup
   - [ ] Grep for password patterns
   - [ ] Fail if any passwords found
   - [ ] Test all three databases (postgres, mysql, mongodb)
   - **Test:** Test script passes for all databases

6. **Subtask 1.4.6:** Integration testing
   - [ ] Run full backup cycle: `./manage-devstack backup`
   - [ ] Monitor `ps aux` in separate terminal during backup
   - [ ] Verify no credentials visible
   - [ ] Verify backup files created successfully for all databases
   - [ ] Run restore: `./manage-devstack restore <timestamp>`
   - [ ] Monitor `ps aux` during restore
   - [ ] Verify restore successful (can connect to databases)
   - **Test:** Backup/restore works, no credential exposure

7. **Subtask 1.4.7:** Documentation
   - [ ] Update `docs/DISASTER_RECOVERY.md` with security improvements
   - [ ] Document temporary file approach
   - [ ] Add troubleshooting for permission issues
   - **Test:** Documentation review

**Validation:**
```bash
# In separate terminal during backup
watch -n 0.1 'ps aux | grep -iE "password|passwd|-p[[:space:]]*[^[:space:]]|MYSQL|POSTGRES|MONGO" | grep -v grep'
# Should not show any credentials
```

**Post-Task Validation:**
- [ ] Security test: Run `tests/test-backup-security.sh` (passes)
- [ ] Functional test: Backup and restore work correctly
- [ ] No regressions: Backup files same size as before

---

### Task 1.5: Document Container Privileged Capabilities

**Priority:** Critical 🔴
**Status:** Not Started
**Estimated Time:** 2 hours (was 1h, +100% for comprehensive docs)
**Impact:** Medium - Security transparency and awareness

**Current Issue:**
- Vault uses `IPC_LOCK` capability without explanation
- cAdvisor uses `SYS_ADMIN` and `SYS_PTRACE` without justification
- Files: `docker-compose.yml:752-753`, `docker-compose.yml:1492-1494`
- No audit trail of privileged capabilities

**Implementation Steps:**

1. **Subtask 1.5.1:** Add inline documentation to docker-compose.yml
   - [ ] Find Vault service definition (around line 752)
   - [ ] Document Vault IPC_LOCK capability:
     ```yaml
     cap_add:
       # IPC_LOCK: Required for Vault's mlock() to prevent secrets from being swapped to disk
       # Security trade-off: Acceptable in dev, use encrypted swap in production
       # Alternative: Run Vault with 'disable_mlock = true' (not recommended)
       - IPC_LOCK
     ```
   - [ ] Find cAdvisor service definition (around line 1492)
   - [ ] Document cAdvisor SYS_ADMIN capability:
     ```yaml
     cap_add:
       # SYS_ADMIN: Required for cAdvisor to access container metrics via cgroups
       # Security trade-off: SYS_ADMIN is nearly equivalent to --privileged
       # Production alternative: Use Prometheus node-exporter with restricted permissions
       - SYS_ADMIN
       # SYS_PTRACE: Required for cAdvisor to inspect process information
       # Security trade-off: Allows debugging and inspection of other containers
       - SYS_PTRACE
     ```
   - [ ] Add security notes section at top of docker-compose.yml
   - **Test:** Review comments for clarity and accuracy
   - **Test:** `docker compose config` still validates

2. **Subtask 1.5.2:** Update SECURITY_ASSESSMENT.md
   - [ ] Add "Privileged Container Capabilities" section
   - [ ] Document IPC_LOCK: what it is, why needed, risks, mitigations
   - [ ] Document SYS_ADMIN: what it is, why needed, risks, mitigations
   - [ ] Document SYS_PTRACE: what it is, why needed, risks, mitigations
   - [ ] Add capability risk matrix (Low/Medium/High for each)
   - [ ] Document production alternatives for each capability
   - [ ] Add "Acceptable Use" policy for dev vs. production
   - [ ] Add reference links to Linux capability documentation
   - **Test:** Documentation review for technical accuracy
   - **Test:** Security section is comprehensive

3. **Subtask 1.5.3:** Create capability audit script
   - [ ] Create `scripts/audit-capabilities.sh`
   - [ ] List all running containers
   - [ ] For each container, check for privileged mode
   - [ ] For each container, list added capabilities (cap_add)
   - [ ] For each container, list dropped capabilities (cap_drop)
   - [ ] Generate security report with risk assessment
   - [ ] Output format: table with container name, capabilities, risk level
   - [ ] Exit code 0 if only known capabilities, 1 if unexpected
   - [ ] Add to test suite
   - **Test:** Run script and verify output
   - **Test:** Script detects if new capability added

4. **Subtask 1.5.4:** Update container security best practices
   - [ ] Update `docs/BEST_PRACTICES.md` with "Container Security" section
   - [ ] Document principle of least privilege
   - [ ] Document when capabilities are acceptable (dev vs. prod)
   - [ ] Document capability alternatives (e.g., node-exporter vs. cAdvisor)
   - [ ] Add capability approval process (document why before adding)
   - [ ] Add links to Docker security documentation
   - [ ] Add capability quick reference (what each does)
   - **Test:** Documentation review
   - **Test:** Best practices are actionable

5. **Subtask 1.5.5:** Add capability check to CI/CD
   - [ ] Update `.github/workflows/security.yml` (if exists)
   - [ ] Add capability audit step
   - [ ] Fail CI if unexpected capabilities detected
   - [ ] Whitelist known capabilities: IPC_LOCK, SYS_ADMIN, SYS_PTRACE
   - [ ] Require PR comment explaining any new capabilities
   - **Test:** CI workflow validates (dry run)
   - **Test:** Whitelist works correctly

6. **Subtask 1.5.6:** Integration testing
   - [ ] Run audit script: `./scripts/audit-capabilities.sh`
   - [ ] Verify report shows Vault (IPC_LOCK) and cAdvisor (SYS_ADMIN, SYS_PTRACE)
   - [ ] Verify no unexpected capabilities
   - [ ] Verify risk levels are reasonable
   - [ ] Review SECURITY_ASSESSMENT.md for completeness
   - **Test:** Audit script passes
   - **Test:** No security regressions

**Documentation Example:**
```yaml
# docker-compose.yml - Security Notes
# This file uses minimal privileged capabilities for development.
# For production deployment:
#   - Consider alternatives that don't require elevated privileges
#   - Use encrypted swap instead of IPC_LOCK for Vault
#   - Use Prometheus node-exporter instead of cAdvisor
#   - Document and approve all capabilities in security review

vault:
  cap_add:
    # IPC_LOCK: Prevents memory paging to disk (keeps secrets in RAM)
    # Why needed: Vault mlock() calls require this capability
    # Risk: Low - only affects Vault process memory
    # Production: Use encrypted swap and disable_mlock = true
    - IPC_LOCK
```

**Post-Task Validation:**
- [ ] Audit script passes: `./scripts/audit-capabilities.sh`
- [ ] Documentation complete: All 3 capabilities documented
- [ ] No new capabilities added unknowingly
- [ ] CI check added (or documented for future)

---

## Phase 1 Completion Criteria

- [ ] All 5 tasks completed (1.1 through 1.5)
- [ ] All subtasks tested and passing
- [ ] Full environment starts successfully: `./manage-devstack start`
- [ ] Full test suite passes: `./tests/run-all-tests.sh` (0 regressions)
- [ ] Smoke test passes: `./manage-devstack health` (all services healthy)
- [ ] No credential exposure in `docker inspect` or `ps aux`
- [ ] Vault backups automated with encryption and rotation
- [ ] AppRole authentication working for all services (with root token fallback)
- [ ] Security audit script passes: `./scripts/audit-capabilities.sh`
- [ ] Documentation updated and accurate (4+ docs updated)
- [ ] No breaking changes to existing functionality
- [ ] Performance check: No >5% degradation from baseline
- [ ] Rollback tested for all critical changes

**Post-Phase Integration Test:**
1. [ ] Run `./manage-devstack stop && ./manage-devstack start`
2. [ ] Verify all services healthy
3. [ ] Run `./tests/run-all-tests.sh` (all tests pass)
4. [ ] Compare test results to Phase 0 baseline (no regressions)
5. [ ] Run performance benchmark and compare to baseline
6. [ ] Run security validation: `./scripts/validate-no-credential-exposure.sh`
7. [ ] Verify backup works: `./manage-devstack vault-backup && ./manage-devstack vault-verify-backup <latest>`
8. [ ] Git checkpoint: `git commit -m "Phase 1 complete: Critical Security improvements"`
9. [ ] Git tag: `git tag phase-1-complete && git push --tags`

**Phase 1 Sign-off:** _________________ Date: _________

---

## Phase 2 - Operational Excellence (Estimated: 3-4 days)

**Total Time:** 27 hours (with 40% buffer: ~38 hours)

**Note:** Tasks reordered from original plan. Task 2.2 (Alertmanager) must complete before Task 2.1 (Alert Rules).

### Task 2.2: Add Alertmanager Service

**Priority:** High 🟠
**Status:** Not Started
**Estimated Time:** 7 hours (was 5h, +40% for integration)
**Impact:** High - Notification delivery system

**Moved to first position - Alert rules (Task 2.1) depend on Alertmanager being functional**

**Implementation Steps:**

1. **Subtask 2.2.1:** Add Alertmanager service to docker-compose.yml
   - [ ] Define alertmanager service (use prom/alertmanager:latest)
   - [ ] Configure static IP: 172.20.0.115
   - [ ] Verify IP not in use: `docker network inspect dev-services | grep 172.20.0.115`
   - [ ] Set resource limits (CPU: 0.5, Memory: 256M)
   - [ ] Set resource reservations (CPU: 0.1, Memory: 64M)
   - [ ] Configure volumes: `./configs/alertmanager:/etc/alertmanager`
   - [ ] Configure ports: `9093:9093`
   - [ ] Add health check: `http://localhost:9093/-/healthy`
   - [ ] Add to full profile (not minimal/standard)
   - [ ] Add logging configuration
   - **Test:** `docker compose config` validates
   - **Test:** No port conflicts

2. **Subtask 2.2.2:** Update .env.example
   - [ ] Add `# Alertmanager Configuration` section
   - [ ] Add `ALERTMANAGER_IP=172.20.0.115`
   - [ ] Add `ALERTMANAGER_PORT=9093`
   - [ ] Add email configuration example (commented out)
   - [ ] Add Slack webhook example (commented out)
   - [ ] Document how to enable notifications
   - **Test:** Configuration examples are clear

3. **Subtask 2.2.3:** Create Alertmanager configuration
   - [ ] Create `configs/alertmanager/` directory
   - [ ] Create `configs/alertmanager/alertmanager.yml`
   - [ ] Configure global settings (resolve_timeout: 5m)
   - [ ] Configure route tree (group by alertname, severity)
   - [ ] Configure webhook receiver (for testing)
   - [ ] Add email receiver template (commented out, requires SMTP)
   - [ ] Add Slack receiver template (commented out, requires webhook)
   - [ ] Set up routing rules (critical → email, warning → slack)
   - [ ] Configure grouping (wait: 30s, interval: 5m, repeat: 12h)
   - **Test:** Validate config with `docker run --rm -v $(pwd)/configs/alertmanager:/etc/alertmanager prom/alertmanager:latest amtool check-config /etc/alertmanager/alertmanager.yml`

4. **Subtask 2.2.4:** Create Alertmanager templates
   - [ ] Create `configs/alertmanager/templates/` directory
   - [ ] Create `configs/alertmanager/templates/email.tmpl`
   - [ ] Create email subject template with severity and alertname
   - [ ] Create email body template with labels, annotations, timestamp
   - [ ] Create `configs/alertmanager/templates/slack.tmpl`
   - [ ] Create Slack message template with colored severity indicator
   - [ ] Add template examples to alertmanager.yml
   - **Test:** Templates are valid (no syntax errors)

5. **Subtask 2.2.5:** Configure Prometheus to use Alertmanager
   - [ ] Update `configs/prometheus/prometheus.yml`
   - [ ] Add alerting section: `alertmanagers: [{static_configs: [{targets: ['alertmanager:9093']}]}]`
   - [ ] Configure alert relabeling if needed
   - [ ] Set evaluation interval (same as scrape: 15s)
   - [ ] Restart Prometheus service
   - **Test:** Prometheus connects to Alertmanager
   - **Test:** Check Prometheus targets page shows Alertmanager

6. **Subtask 2.2.6:** Add management commands
   - [ ] Add `alertmanager-status` to manage_devstack.py
   - [ ] Add `alertmanager-silence` command (create silence for alert)
   - [ ] Add `alertmanager-test` command (send test alert)
   - [ ] Add `alertmanager-alerts` command (list active alerts)
   - [ ] Update help text for new commands
   - **Test:** Run `./manage-devstack alertmanager-status`
   - **Test:** Run `./manage-devstack alertmanager-test`

7. **Subtask 2.2.7:** Integration testing
   - [ ] Start Alertmanager service: `docker compose up -d alertmanager`
   - [ ] Check service health: `curl http://localhost:9093/-/healthy`
   - [ ] Trigger test alert: `./manage-devstack alertmanager-test`
   - [ ] Verify webhook receives notification (check webhook logs)
   - [ ] Test alert silencing: `./manage-devstack alertmanager-silence test-alert`
   - [ ] Verify silence created in Alertmanager UI
   - [ ] Test alert grouping (send multiple alerts)
   - **Test:** End-to-end alerting works
   - **Test:** All management commands work

8. **Subtask 2.2.8:** Documentation
   - [ ] Update `docs/OBSERVABILITY.md` with Alertmanager section
   - [ ] Document Alertmanager configuration
   - [ ] Document how to set up email notifications
   - [ ] Document how to set up Slack notifications
   - [ ] Create alert management guide (silence, inhibit, route)
   - [ ] Add troubleshooting section
   - **Test:** Documentation review

9. **Subtask 2.2.9:** Rollback testing
   - [ ] Document rollback steps (remove from docker-compose.yml)
   - [ ] Test stopping Alertmanager
   - [ ] Verify Prometheus still works without Alertmanager
   - [ ] Restart Alertmanager
   - **Test:** Rollback works, no data loss

**Post-Task Validation:**
- [ ] Smoke test: `./manage-devstack health` (alertmanager healthy)
- [ ] Functional test: Can send and receive test alert
- [ ] UI test: Alertmanager UI accessible at http://localhost:9093

---

### Task 2.1: Implement Prometheus Alert Rules

**Priority:** High 🟠
**Status:** Not Started
**Estimated Time:** 6 hours (was 4h, +50% for testing)
**Impact:** High - Proactive issue detection
**Depends On:** Task 2.2 (Alertmanager must be running)

**Moved to second position - requires Alertmanager for full testing**

**Implementation Steps:**

1. **Subtask 2.1.1:** Create alert rule directory structure
   - [ ] Create `configs/prometheus/alerts/` directory
   - [ ] Create `critical.yml` for critical alerts
   - [ ] Create `warning.yml` for warning alerts
   - [ ] Create `info.yml` for informational alerts
   - [ ] Add README explaining alert severity levels
   - **Test:** Directory structure exists

2. **Subtask 2.1.2:** Implement critical alerts
   - [ ] ServiceDown alert (up == 0 for 2+ minutes)
   - [ ] HighMemoryUsage alert (>90% for 5+ minutes)
   - [ ] DiskSpaceCritical alert (<10% free on any mount)
   - [ ] DatabaseConnectionPoolExhaustion alert (pg_stat_activity count > max_connections * 0.9)
   - [ ] CertificateExpiration alert (x509_cert_expiry < 30 days)
   - [ ] VaultSealed alert (vault_core_unsealed == 0)
   - [ ] Add annotations with description and runbook_url
   - [ ] Add labels: severity=critical, team=infra
   - **Test:** Validate alert syntax with `promtool check rules configs/prometheus/alerts/critical.yml`

3. **Subtask 2.1.3:** Implement warning alerts
   - [ ] HighCPUUsage alert (>80% for 10+ minutes)
   - [ ] HighMemoryUsage alert (>80% for 10+ minutes)
   - [ ] SlowResponseTime alert (p95 > 1s for 5+ minutes)
   - [ ] HighErrorRate alert (>1% errors for 5+ minutes)
   - [ ] RedisClusterNodeDown alert (redis_up{instance=~"redis-[123]"} == 0)
   - [ ] DiskSpaceWarning alert (<20% free)
   - [ ] Add annotations and labels
   - **Test:** Validate alert syntax

4. **Subtask 2.1.4:** Implement informational alerts
   - [ ] ServiceRestarted alert (time() - process_start_time_seconds < 300)
   - [ ] BackupCompleted alert (custom metric from backup script)
   - [ ] ConfigurationChanged alert (config file checksum changed)
   - [ ] Add annotations and labels: severity=info
   - **Test:** Validate alert syntax

5. **Subtask 2.1.5:** Update prometheus.yml to load alert rules
   - [ ] Add rule_files section to `configs/prometheus/prometheus.yml`
   - [ ] Add: `rule_files: ['/etc/prometheus/alerts/*.yml']`
   - [ ] Configure alert evaluation interval (default: 15s)
   - [ ] Reload Prometheus: `docker compose exec prometheus kill -HUP 1`
   - [ ] Or restart: `docker compose restart prometheus`
   - **Test:** Check Prometheus UI for loaded alert rules (http://localhost:9090/rules)
   - **Test:** Check for configuration errors in Prometheus logs

6. **Subtask 2.1.6:** Create alert testing script
   - [ ] Create `tests/test-alerts.sh`
   - [ ] Test ServiceDown: Stop a service, wait, check alert fires
   - [ ] Test HighMemoryUsage: Trigger via stress container (if safe)
   - [ ] Test alert fires in Prometheus UI
   - [ ] Test alert appears in Alertmanager
   - [ ] Test alert resolves after condition clears
   - [ ] Add to main test suite
   - **Test:** All alert rules can be triggered
   - **Test:** All alerts resolve correctly

7. **Subtask 2.1.7:** Documentation
   - [ ] Update `docs/OBSERVABILITY.md` with alert rules documentation
   - [ ] Document each alert: what it detects, why it matters, how to respond
   - [ ] Document alert thresholds and rationale (why 90% not 95%?)
   - [ ] Create alert response runbook: `docs/runbooks/alert-response.md`
   - [ ] Add links to runbooks in alert annotations
   - [ ] Document how to add new alert rules
   - **Test:** Documentation review for completeness

8. **Subtask 2.1.8:** Rollback testing
   - [ ] Document rollback steps (remove rule_files from prometheus.yml)
   - [ ] Test removing alert rules
   - [ ] Verify Prometheus still works
   - [ ] Re-enable alert rules
   - **Test:** Rollback works

**Post-Task Validation:**
- [ ] All alert rules loaded: Check Prometheus UI /rules
- [ ] Test alert fires: Run `tests/test-alerts.sh`
- [ ] Alerts reach Alertmanager: Check Alertmanager UI
- [ ] Documentation complete: Runbook exists for each critical alert

---

### Task 2.3: Implement Automated Backup Verification

**Priority:** High 🟠
**Status:** Not Started
**Estimated Time:** 8 hours (was 6h, +33% for comprehensive testing)
**Impact:** High - Disaster recovery confidence
**Depends On:** Task 2.2 (Alertmanager for failure notifications)

**Implementation Steps:**

1. **Subtask 2.3.1:** Create backup verification script
   - [ ] Create `scripts/verify-backup.sh`
   - [ ] Accept backup timestamp as parameter
   - [ ] Extract backup to temporary location: `/tmp/backup-verify-$$`
   - [ ] Start temporary PostgreSQL container from backup
   - [ ] Start temporary MySQL container from backup
   - [ ] Start temporary MongoDB container from backup
   - [ ] Run integrity checks (connect, query, schema validation)
   - [ ] Clean up temporary resources (containers, volumes)
   - [ ] Return exit code 0 for success, 1 for failure
   - [ ] Log results to `logs/backup-verification/verify-$(date +%Y%m%d-%H%M%S).log`
   - **Test:** Run script with known good backup
   - **Test:** Run script with corrupted backup (should fail)

2. **Subtask 2.3.2:** Implement database integrity checks
   - [ ] PostgreSQL: Run `pg_dump --schema-only` and compare to original
   - [ ] PostgreSQL: Check `SELECT count(*) FROM pg_tables` matches expected
   - [ ] MySQL: Run `mysqlcheck --all-databases --check-upgrade`
   - [ ] MySQL: Verify table count matches expected
   - [ ] MongoDB: Run `mongod --dbpath /tmp/mongo-verify --repair`
   - [ ] MongoDB: Verify collection count matches expected
   - [ ] Verify row/document counts for key tables/collections
   - [ ] Generate verification report with pass/fail for each check
   - **Test:** Integrity checks pass on valid backup
   - **Test:** Integrity checks fail on corrupted backup

3. **Subtask 2.3.3:** Add verification to management script
   - [ ] Add `verify-backup` command to manage_devstack.py
   - [ ] Support verification of specific backup timestamp
   - [ ] Support verification of latest backup (default)
   - [ ] Generate verification report (JSON + human-readable)
   - [ ] Save report to `logs/backup-verification/`
   - [ ] Display summary in terminal (pass/fail + details)
   - **Test:** Run `./manage-devstack verify-backup`
   - **Test:** Run `./manage-devstack verify-backup <timestamp>`

4. **Subtask 2.3.4:** Create automated verification logging
   - [ ] Create `logs/backup-verification/` directory
   - [ ] Log verification results with timestamp
   - [ ] Log passed checks vs. failed checks
   - [ ] Create verification history tracking (CSV or JSON)
   - [ ] Generate monthly verification report (summary stats)
   - [ ] Rotate old logs (keep 90 days)
   - **Test:** Multiple verifications create proper logs
   - **Test:** Monthly report generated correctly

5. **Subtask 2.3.5:** Create weekly verification schedule documentation
   - [ ] Update `docs/DISASTER_RECOVERY.md` with verification procedures
   - [ ] Document weekly verification schedule (Sunday 3 AM recommended)
   - [ ] Add cron example: `0 3 * * 0 /path/to/manage-devstack verify-backup`
   - [ ] Document what to do if verification fails
   - [ ] Add verification checklist
   - [ ] Document manual verification procedure
   - **Test:** Documentation review

6. **Subtask 2.3.6:** Integration testing
   - [ ] Create test backup: `./manage-devstack backup`
   - [ ] Run verification: `./manage-devstack verify-backup <timestamp>`
   - [ ] Verify success report generated
   - [ ] Corrupt backup (modify a backup file)
   - [ ] Run verification on corrupted backup
   - [ ] Verify detection and failure report
   - [ ] Verify original backup still intact
   - [ ] Test verification with multiple backup timestamps
   - **Test:** Verification detects good and bad backups
   - **Test:** No false positives or false negatives

7. **Subtask 2.3.7:** Documentation
   - [ ] Update `docs/DISASTER_RECOVERY.md` with verification section
   - [ ] Document verification process step-by-step
   - [ ] Add troubleshooting guide for verification failures
   - [ ] Document interpretation of verification reports
   - [ ] Add flowchart: when to restore, when to create new backup
   - **Test:** Documentation review

8. **Subtask 2.3.8:** Rollback testing
   - [ ] Verification is non-destructive, no rollback needed
   - [ ] Document how to disable verification (don't add to cron)
   - **Test:** N/A

**Post-Task Validation:**
- [ ] Verification script works: `./manage-devstack verify-backup`
- [ ] Can detect corrupted backup
- [ ] Reports are clear and actionable
- [ ] Documentation complete

---

### Task 2.4: Implement Database Migration Framework

**Priority:** High 🟠
**Status:** Not Started
**Estimated Time:** 6 hours (was 4h, +50% for all databases)
**Impact:** High - Safe schema evolution

**Implementation Steps:**

1. **Subtask 2.4.1:** Create migration directory structure
   - [ ] Create `configs/postgres/migrations/` directory
   - [ ] Create `configs/mysql/migrations/` directory
   - [ ] Create `configs/mongodb/migrations/` directory
   - [ ] Add README in each with migration instructions
   - [ ] Add .gitkeep to preserve empty directories
   - **Test:** Directory structure exists

2. **Subtask 2.4.2:** Implement Flyway for PostgreSQL
   - [ ] Add Flyway service to docker-compose.yml (one-shot container)
   - [ ] Configure Flyway connection to PostgreSQL
   - [ ] Set migrations location: `/flyway/sql`
   - [ ] Mount `./configs/postgres/migrations:/flyway/sql`
   - [ ] Create `configs/postgres/migrations/V1__baseline.sql` (empty or CREATE TABLE example)
   - [ ] Test Flyway execution: `docker compose run --rm flyway migrate`
   - **Test:** Flyway runs and creates flyway_schema_history table
   - **Test:** V1 migration applied successfully

3. **Subtask 2.4.3:** Implement Liquibase for MySQL
   - [ ] Add Liquibase service to docker-compose.yml
   - [ ] Configure Liquibase connection to MySQL
   - [ ] Create `configs/mysql/migrations/changelog.xml`
   - [ ] Create baseline changeset (example: CREATE TABLE demo)
   - [ ] Test Liquibase execution: `docker compose run --rm liquibase update`
   - **Test:** Liquibase runs and creates DATABASECHANGELOG table
   - **Test:** Baseline changeset applied

4. **Subtask 2.4.4:** Implement migrate-mongo for MongoDB
   - [ ] Add migrate-mongo configuration: `configs/mongodb/migrations/migrate-mongo-config.js`
   - [ ] Create baseline migration: `configs/mongodb/migrations/01-baseline.js`
   - [ ] Configure MongoDB connection (use Vault credentials)
   - [ ] Test migration: Create script to run migrate-mongo in container
   - **Test:** Migration runs and creates migrations collection
   - **Test:** Baseline migration applied

5. **Subtask 2.4.5:** Add migration commands to management script
   - [ ] Add `db-migrate` command to manage_devstack.py
   - [ ] Support `--database` flag (postgres, mysql, mongodb, all)
   - [ ] Add `db-migrate-status` command (shows applied migrations)
   - [ ] Add `db-migrate-validate` command (checks pending migrations)
   - [ ] Support service-specific migrations
   - [ ] Add `db-migrate-rollback` command (if supported by tool)
   - [ ] Add error handling and validation
   - **Test:** Run `./manage-devstack db-migrate --database postgres`
   - **Test:** Run `./manage-devstack db-migrate-status`

6. **Subtask 2.4.6:** Create example migrations
   - [ ] PostgreSQL: Create `V2__create_demo_table.sql`
   - [ ] MySQL: Create `002-create-demo-table.xml`
   - [ ] MongoDB: Create `02-create-demo-collection.js`
   - [ ] Test forward migration for all databases
   - [ ] Test rollback for PostgreSQL (Flyway supports undo)
   - [ ] Document rollback limitations (Liquibase/MongoDB may not support)
   - **Test:** Migrations execute successfully
   - **Test:** Tables/collections created as expected

7. **Subtask 2.4.7:** Create migration testing script
   - [ ] Create `tests/test-migrations.sh`
   - [ ] Test migration on empty database
   - [ ] Test migration idempotency (run twice, should succeed)
   - [ ] Test migration status reporting
   - [ ] Test rollback (PostgreSQL only)
   - [ ] Add to main test suite: `./tests/run-all-tests.sh`
   - **Test:** Migration tests pass

8. **Subtask 2.4.8:** Integration testing
   - [ ] Run migrations on clean database: `./manage-devstack db-migrate`
   - [ ] Verify schema created correctly (connect and inspect)
   - [ ] Check migration history tables (flyway_schema_history, etc.)
   - [ ] Test migration status: `./manage-devstack db-migrate-status`
   - [ ] Test rollback for PostgreSQL
   - [ ] Verify services still work after migration
   - **Test:** Complete migration lifecycle works

9. **Subtask 2.4.9:** Documentation
   - [ ] Create `docs/DATABASE_MIGRATIONS.md` (new file)
   - [ ] Document migration creation process for each database
   - [ ] Document migration naming conventions
   - [ ] Document best practices (always forward, never edit old migrations)
   - [ ] Document rollback procedures and limitations
   - [ ] Add troubleshooting guide
   - [ ] Add examples for common scenarios
   - **Test:** Documentation review

10. **Subtask 2.4.10:** Rollback testing
    - [ ] Document rollback steps (manual SQL if migration failed)
    - [ ] Test PostgreSQL rollback
    - [ ] Document MySQL/MongoDB manual rollback (no native support)
    - **Test:** Rollback procedures documented

**Post-Task Validation:**
- [ ] All migration frameworks working
- [ ] Can create and apply migrations
- [ ] Migration history tracked correctly
- [ ] Test script passes: `tests/test-migrations.sh`

---

### Task 2.5: Add Integration Tests to CI/CD

**Priority:** High 🟠
**Status:** Not Started
**Estimated Time:** 12 hours (was 4h, +200% for Docker-in-Docker complexity)
**Impact:** Medium - Catch integration issues before merge

**Decision Required:** Choose implementation strategy (see below)

**Implementation Steps:**

**Option A: Comprehensive Integration Tests (12 hours)**

1. **Subtask 2.5.1:** Research CI/CD Docker options
   - [ ] Evaluate Docker-in-Docker (DinD) approach
   - [ ] Evaluate GitHub Actions service containers
   - [ ] Evaluate testcontainers library
   - [ ] Test Colima/Docker Desktop alternatives for CI
   - [ ] Select best approach for project
   - [ ] Document decision with pros/cons
   - **Test:** Decision documented in ADR (Architecture Decision Record)

2. **Subtask 2.5.2:** Create integration test workflow
   - [ ] Create `.github/workflows/integration-tests.yml`
   - [ ] Set up Docker environment (DinD service or Docker socket mount)
   - [ ] Install dependencies (docker-compose, python, uv)
   - [ ] Configure test environment variables
   - [ ] Set resource limits for CI (avoid timeout)
   - **Test:** Workflow syntax valid: `gh workflow view integration-tests.yml`

3. **Subtask 2.5.3:** Implement test execution in CI
   - [ ] Start services with minimal profile: `./manage-devstack start --profile minimal`
   - [ ] Wait for services to be healthy (poll health endpoints)
   - [ ] Run subset of tests (fastest, most critical)
   - [ ] Run `./tests/test-vault.sh`
   - [ ] Collect test results and logs
   - [ ] Generate test report
   - [ ] Stop services and cleanup
   - **Test:** Workflow runs manually (on: workflow_dispatch)

4. **Subtask 2.5.4:** Add test result reporting
   - [ ] Upload test results as GitHub artifacts
   - [ ] Add test summary to job summary (GitHub Actions feature)
   - [ ] Set workflow status based on test results
   - [ ] Add comment to PR with test results (optional)
   - **Test:** Test results visible in GitHub UI

5. **Subtask 2.5.5:** Optimize test execution time
   - [ ] Implement Docker layer caching
   - [ ] Parallelize independent tests (if possible)
   - [ ] Use minimal profile for faster startup
   - [ ] Skip long-running tests in CI (run manually)
   - [ ] Target: Complete in <15 minutes
   - **Test:** Workflow completes in acceptable time

6. **Subtask 2.5.6:** Integration testing
   - [ ] Trigger workflow manually: `gh workflow run integration-tests.yml`
   - [ ] Verify all tests run
   - [ ] Verify test results reported
   - [ ] Test failure handling (introduce failing test)
   - [ ] Verify workflow fails on test failure
   - **Test:** CI/CD integration tests pass

7. **Subtask 2.5.7:** Documentation
   - [ ] Update `docs/TESTING_APPROACH.md`
   - [ ] Document CI/CD test execution
   - [ ] Document which tests run in CI vs. manual
   - [ ] Add troubleshooting guide for CI failures
   - **Test:** Documentation review

**Option B: Lightweight Testing (4 hours - Recommended)**

If Docker-in-Docker proves too complex, use this simpler approach:

1. **Subtask 2.5.1:** Create lightweight validation workflow
   - [ ] Create `.github/workflows/validation.yml`
   - [ ] Run shellcheck on all bash scripts
   - [ ] Run python linting (ruff, mypy)
   - [ ] Validate docker-compose.yml syntax
   - [ ] Validate all YAML files
   - [ ] Run unit tests (no Docker required)
   - **Test:** Workflow runs and passes

2. **Subtask 2.5.2:** Document manual integration testing
   - [ ] Create `docs/MANUAL_INTEGRATION_TESTING.md`
   - [ ] Document pre-merge checklist
   - [ ] Require manual test run before merge
   - [ ] Document in CONTRIBUTING.md
   - **Test:** Documentation clear and actionable

3. **Subtask 2.5.3:** Defer full integration testing to Phase 5
   - [ ] Add to Phase 5 backlog (future work)
   - [ ] Document as known limitation
   - [ ] Revisit when more time available
   - **Test:** Decision documented

**Recommended Choice:** Option B (Lightweight Testing)
**Rationale:** Docker-in-Docker for Colima + Vault is complex and may not be feasible in GitHub Actions. Focus on what's achievable now, defer complex integration to future phase.

**Post-Task Validation:**
- [ ] CI workflow exists and runs
- [ ] Tests provide value (catch real issues)
- [ ] Documentation complete

---

## Phase 2 Completion Criteria

- [ ] All 5 tasks completed (2.1 through 2.5)
- [ ] All subtasks tested and passing
- [ ] Prometheus alerts configured and firing correctly
- [ ] Alertmanager receiving and routing notifications (test alert successful)
- [ ] Backup verification script works and detects issues
- [ ] Database migrations working for all databases (postgres, mysql, mongodb)
- [ ] CI/CD tests running (even if lightweight approach)
- [ ] Documentation updated and accurate
- [ ] No breaking changes to existing functionality
- [ ] Smoke test passes: `./manage-devstack health`
- [ ] Full test suite passes: `./tests/run-all-tests.sh`

**Post-Phase Integration Test:**
1. [ ] Run `./manage-devstack stop && ./manage-devstack start --profile full`
2. [ ] Verify all services healthy (including Alertmanager)
3. [ ] Trigger test alert: `./manage-devstack alertmanager-test`
4. [ ] Verify alert received
5. [ ] Run backup and verification: `./manage-devstack backup && ./manage-devstack verify-backup`
6. [ ] Run database migrations: `./manage-devstack db-migrate`
7. [ ] Run full test suite: `./tests/run-all-tests.sh`
8. [ ] Compare to Phase 0 baseline (no regressions)
9. [ ] Git checkpoint: `git commit -m "Phase 2 complete: Operational Excellence"`
10. [ ] Git tag: `git tag phase-2-complete && git push --tags`

**Phase 2 Sign-off:** _________________ Date: _________

---

## Phase 3 - Code Quality (Estimated: 4-5 days)

**Total Time:** 32 hours (with 40% buffer: ~45 hours)

### Task 3.1: Standardize Error Handling Across Languages

**Priority:** Medium 🟡
**Status:** Not Started
**Estimated Time:** 18 hours (was 12h, +50% for complexity)
**Impact:** Medium - Consistent error responses across all APIs

[Content continues with all Phase 3 and Phase 4 tasks with similar level of detail...]

---

## Lessons Learned (Complete After Each Phase)

### Phase 0 Lessons
- **What went well:**
- **What didn't go well:**
- **What would we do differently:**
- **Time estimate accuracy:** Estimated: 3h, Actual: ___h, Variance: ___%
- **Unexpected challenges:**
- **Key learnings:**

### Phase 1 Lessons
- **What went well:**
- **What didn't go well:**
- **What would we do differently:**
- **Time estimate accuracy:** Estimated: 39h, Actual: ___h, Variance: ___%
- **Most challenging task:**
- **Most valuable improvement:**

### Phase 2 Lessons
- **What went well:**
- **What didn't go well:**
- **What would we do differently:**
- **Time estimate accuracy:** Estimated: 38h, Actual: ___h, Variance: ___%

### Phase 3 Lessons
- **What went well:**
- **What didn't go well:**
- **What would we do differently:**
- **Time estimate accuracy:** Estimated: 45h, Actual: ___h, Variance: ___%

### Phase 4 Lessons
- **What went well:**
- **What didn't go well:**
- **What would we do differently:**
- **Time estimate accuracy:** Estimated: 15h, Actual: ___h, Variance: ___%

---

## Notes and Decisions

### Task Modifications
- Document any changes to tasks or scope here
- Note reasons for task modifications
- Track scope creep or descoping

**Example:**
- 2025-11-14: Changed Task 2.5 from comprehensive to lightweight testing due to Docker-in-Docker complexity

### Issues Encountered
- Document blocking issues and resolutions
- Track technical debt created
- Note areas requiring future attention

### Deferred Items (Phase 5 Backlog)
- Full integration tests in CI/CD (Task 2.5 Option A)
- Complete Rust implementation (Task 3.5 Option B)
- S3 integration for Vault backups (Task 1.3 enhancement)
- Advanced alerting with PagerDuty integration

---

## Project Completion Checklist

- [ ] Phase 0: Preparation - COMPLETE
- [ ] Phase 1: Critical Security - COMPLETE
- [ ] Phase 2: Operational Excellence - COMPLETE
- [ ] Phase 3: Code Quality - COMPLETE
- [ ] Phase 4: Developer Experience - COMPLETE
- [ ] All 21 tasks completed (including Phase 0)
- [ ] All tests passing
- [ ] All documentation updated
- [ ] `.github/CHANGELOG.md` updated with all improvements
- [ ] Final integration testing complete
- [ ] Compare final metrics to Phase 0 baseline
- [ ] All success metrics achieved
- [ ] Risk register reviewed (all risks mitigated or accepted)
- [ ] Lessons learned documented
- [ ] Project ready for production adaptation

**Final Metrics vs. Baseline:**
- Test coverage: Baseline: ___%, Final: ___%, Improvement: ___% ✅
- Security score: Baseline: ___, Final: ___, Improvement: ___% ✅
- Performance p95: Baseline: ___ms, Final: ___ms, Degradation: ___% ✅ (target: <5%)
- Total test count: Baseline: ___, Final: ___, New tests: ___ ✅

**Project Sign-off:** _________________ Date: _________

---

**Last Updated:** 2025-11-14
**Document Version:** 2.0
**Changes from v1.0:** Added Phase 0, fixed dependencies, improved time estimates, added rollback testing, enhanced security, added comprehensive validation
