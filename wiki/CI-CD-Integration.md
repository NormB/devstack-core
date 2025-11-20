# CI/CD Integration

Forgejo Actions and automation workflows for DevStack Core.

## Table of Contents

- [Overview](#overview)
- [Forgejo Actions Overview](#forgejo-actions-overview)
- [Setting Up Actions](#setting-up-actions)
- [Workflow Examples](#workflow-examples)
- [Testing Workflows](#testing-workflows)
- [Build Workflows](#build-workflows)
- [Deployment Workflows](#deployment-workflows)
- [Secrets in CI/CD](#secrets-in-cicd)
- [Notifications](#notifications)
- [Best Practices](#best-practices)
- [GitHub Actions Compatibility](#github-actions-compatibility)
- [Related Documentation](#related-documentation)

## Overview

Forgejo Actions provides GitHub Actions-compatible CI/CD pipelines for local development and testing.

**CI/CD Stack:**
- **Platform**: Forgejo (self-hosted Git with Actions)
- **Runners**: Forgejo Actions runners
- **Compatibility**: GitHub Actions syntax
- **Integration**: Vault, Docker, databases

## Forgejo Actions Overview

### What are Forgejo Actions?

Forgejo Actions is a CI/CD system compatible with GitHub Actions:

- **Workflow Syntax**: Same as GitHub Actions
- **Action Marketplace**: Can use GitHub Actions
- **Runners**: Self-hosted or Forgejo-managed
- **Triggers**: push, pull_request, schedule, manual

### Architecture

```
Git Push → Forgejo → Workflow Detection → Runner Assignment → Job Execution
                                                 ↓
                                          Results/Artifacts
```

### Accessing Forgejo

```bash
# Start Forgejo
docker compose up -d forgejo

# Access UI
open http://localhost:3000

# Create admin account (first time)
# Navigate to: http://localhost:3000/install

# Configure Actions
# Settings → Actions → Enable Actions
```

## Setting Up Actions

### Enable Actions in Forgejo

1. **Access Forgejo**: http://localhost:3000
2. **Admin Panel**: Site Administration → Configuration
3. **Enable Actions**: Check "Enable Actions"
4. **Save Configuration**

### Configure Runner

**Install Forgejo Runner:**

```bash
# Download runner
wget https://dl.gitea.com/act_runner/main/act_runner-main-darwin-arm64

# Make executable
chmod +x act_runner-main-darwin-arm64

# Register runner
./act_runner-main-darwin-arm64 register --instance http://localhost:3000 --token YOUR_TOKEN

# Start runner
./act_runner-main-darwin-arm64 daemon
```

**Using Docker Runner:**

```yaml
# Add to docker-compose.yml
services:
  forgejo-runner:
    image: gitea/act_runner:latest
    container_name: forgejo-runner
    environment:
      GITEA_INSTANCE_URL: http://forgejo:3000
      GITEA_RUNNER_REGISTRATION_TOKEN: ${RUNNER_TOKEN}
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - forgejo-runner-data:/data
    networks:
      - dev-services
    depends_on:
      - forgejo

volumes:
  forgejo-runner-data:
```

### Repository Configuration

Create `.forgejo/workflows/` directory:

```bash
cd ~/devstack-core
mkdir -p .forgejo/workflows

# Create workflow file
touch .forgejo/workflows/test.yml
```

## Workflow Examples

### Basic Workflow

```yaml
# .forgejo/workflows/hello.yml
name: Hello World

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  hello:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Print message
        run: echo "Hello from Forgejo Actions!"
```

### Test Workflow

```yaml
# .forgejo/workflows/test.yml
name: Run Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
      
      - name: Start services
        run: |
          docker compose up -d vault postgres redis-1
          sleep 10
      
      - name: Run tests
        run: |
          ./tests/run-all-tests.sh
      
      - name: Upload test results
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: test-results
          path: test-results/
      
      - name: Cleanup
        if: always()
        run: docker compose down -v
```

### Lint Workflow

```yaml
# .forgejo/workflows/lint.yml
name: Lint Code

on:
  push:
    branches: [main, develop]
  pull_request:

jobs:
  lint-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        run: |
          pip install flake8 black pylint mypy
      
      - name: Run flake8
        run: flake8 reference-apps/fastapi/app/
      
      - name: Run black
        run: black --check reference-apps/fastapi/app/
      
      - name: Run pylint
        run: pylint reference-apps/fastapi/app/
  
  lint-go:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.21'
      
      - name: Run golangci-lint
        uses: golangci/golangci-lint-action@v3
        with:
          working-directory: reference-apps/golang
```

## Testing Workflows

### Python Tests

```yaml
# .forgejo/workflows/test-python.yml
name: Python Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: testpass
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      
      redis:
        image: redis:7-alpine
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'
      
      - name: Install dependencies
        working-directory: reference-apps/fastapi
        run: |
          pip install -e ".[dev]"
      
      - name: Run pytest
        working-directory: reference-apps/fastapi
        env:
          DATABASE_URL: postgresql://postgres:testpass@postgres:5432/test
          REDIS_URL: redis://redis:6379
        run: |
          pytest tests/ -v --cov=app --cov-report=xml
      
      - name: Upload coverage
        uses: codecov/codecov-action@v3
        with:
          file: reference-apps/fastapi/coverage.xml
```

### Integration Tests

```yaml
# .forgejo/workflows/integration-tests.yml
name: Integration Tests

on:
  push:
    branches: [main]
  pull_request:

jobs:
  integration:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Start DevStack Core
        run: |
          docker compose up -d
          ./devstack.sh vault-init
          ./devstack.sh vault-bootstrap
      
      - name: Wait for services
        run: |
          timeout 120 bash -c 'until docker exec postgres pg_isready; do sleep 2; done'
          timeout 120 bash -c 'until docker exec redis-1 redis-cli ping; do sleep 2; done'
      
      - name: Run integration tests
        run: |
          ./tests/test-vault.sh
          ./tests/test-postgres.sh
          ./tests/test-redis-cluster.sh
          ./tests/test-fastapi.sh
      
      - name: Collect logs
        if: failure()
        run: |
          mkdir -p logs
          docker compose logs > logs/docker-compose.log
      
      - name: Upload logs
        if: failure()
        uses: actions/upload-artifact@v3
        with:
          name: failure-logs
          path: logs/
      
      - name: Cleanup
        if: always()
        run: docker compose down -v
```

## Build Workflows

### Docker Image Build

```yaml
# .forgejo/workflows/build-image.yml
name: Build Docker Image

on:
  push:
    branches: [main]
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Login to Registry
        uses: docker/login-action@v2
        with:
          registry: localhost:5000
          username: ${{ secrets.REGISTRY_USERNAME }}
          password: ${{ secrets.REGISTRY_PASSWORD }}
      
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v4
        with:
          images: localhost:5000/reference-api
          tags: |
            type=ref,event=branch
            type=semver,pattern={{version}}
            type=sha
      
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: reference-apps/fastapi
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

### Multi-platform Build

```yaml
# .forgejo/workflows/build-multiplatform.yml
name: Build Multi-platform

on:
  push:
    tags: ['v*']

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v2
      
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
      
      - name: Build and push
        uses: docker/build-push-action@v4
        with:
          context: reference-apps/fastapi
          platforms: linux/amd64,linux/arm64
          push: true
          tags: myregistry/reference-api:${{ github.ref_name }}
```

## Deployment Workflows

### Deploy to Staging

```yaml
# .forgejo/workflows/deploy-staging.yml
name: Deploy to Staging

on:
  push:
    branches: [develop]

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Build image
        run: |
          docker build -t reference-api:staging reference-apps/fastapi
      
      - name: Deploy to staging
        run: |
          docker compose -f docker-compose.staging.yml up -d reference-api
      
      - name: Health check
        run: |
          timeout 60 bash -c 'until curl -f http://localhost:8000/health; do sleep 2; done'
      
      - name: Run smoke tests
        run: |
          curl -f http://localhost:8000/health
          curl -f http://localhost:8000/api/health/ready
```

### Deploy to Production

```yaml
# .forgejo/workflows/deploy-production.yml
name: Deploy to Production

on:
  release:
    types: [published]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Pull latest image
        run: docker pull myregistry/reference-api:${{ github.event.release.tag_name }}
      
      - name: Backup database
        run: |
          ./devstack.sh backup
      
      - name: Deploy
        run: |
          docker compose pull reference-api
          docker compose up -d reference-api
      
      - name: Health check
        run: |
          timeout 120 bash -c 'until curl -f http://localhost:8000/health; do sleep 2; done'
      
      - name: Rollback on failure
        if: failure()
        run: |
          docker compose up -d reference-api
```

## Secrets in CI/CD

### Managing Secrets

1. **Repository Settings**: Navigate to repository → Settings → Secrets
2. **Add Secrets**: Add secret name and value
3. **Use in Workflow**: `${{ secrets.SECRET_NAME }}`

**Common Secrets:**

```yaml
secrets:
  VAULT_TOKEN: "hvs.xxxxx"
  DATABASE_PASSWORD: "secure_password"
  REGISTRY_USERNAME: "user"
  REGISTRY_PASSWORD: "pass"
  SLACK_WEBHOOK: "https://hooks.slack.com/..."
```

### Vault Integration

```yaml
# Use Vault in workflow
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Get secrets from Vault
        env:
          VAULT_ADDR: http://vault:8200
          VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}
        run: |
          # Install Vault CLI
          wget https://releases.hashicorp.com/vault/1.15.0/vault_1.15.0_linux_amd64.zip
          unzip vault_1.15.0_linux_amd64.zip
          
          # Get secrets
          export DB_PASSWORD=$(./vault kv get -field=password secret/postgres)
          echo "DB_PASSWORD=$DB_PASSWORD" >> $GITHUB_ENV
      
      - name: Use secrets
        run: |
          echo "Database password retrieved from Vault"
```

## Notifications

### Slack Notifications

```yaml
# .forgejo/workflows/notify-slack.yml
name: Notify Slack

on:
  push:
    branches: [main]
  pull_request:

jobs:
  notify:
    runs-on: ubuntu-latest
    
    steps:
      - name: Notify Slack on success
        if: success()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "✅ Build succeeded: ${{ github.repository }}",
              "blocks": [
                {
                  "type": "section",
                  "text": {
                    "type": "mrkdwn",
                    "text": "*Build Succeeded*\nRepository: ${{ github.repository }}\nBranch: ${{ github.ref_name }}\nCommit: ${{ github.sha }}"
                  }
                }
              ]
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
      
      - name: Notify Slack on failure
        if: failure()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "❌ Build failed: ${{ github.repository }}"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

### Email Notifications

```yaml
# Add email step
- name: Send email
  if: failure()
  uses: dawidd6/action-send-mail@v3
  with:
    server_address: smtp.gmail.com
    server_port: 465
    username: ${{ secrets.EMAIL_USERNAME }}
    password: ${{ secrets.EMAIL_PASSWORD }}
    subject: "Build Failed: ${{ github.repository }}"
    to: team@example.com
    from: ci@example.com
    body: |
      Build failed for ${{ github.repository }}
      Branch: ${{ github.ref_name }}
      Commit: ${{ github.sha }}
```

### PR Comments

```yaml
# Comment on PR
- name: Comment on PR
  if: github.event_name == 'pull_request'
  uses: actions/github-script@v6
  with:
    script: |
      github.rest.issues.createComment({
        issue_number: context.issue.number,
        owner: context.repo.owner,
        repo: context.repo.repo,
        body: '✅ All tests passed!'
      })
```

## Best Practices

### Workflow Organization

```
.forgejo/workflows/
├── ci.yml              # Main CI pipeline
├── test.yml            # Test suite
├── lint.yml            # Code linting
├── build.yml           # Build images
├── deploy-staging.yml  # Deploy to staging
└── deploy-prod.yml     # Deploy to production
```

### Workflow Optimization

```yaml
# Use caching
- name: Cache dependencies
  uses: actions/cache@v3
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements.txt') }}
    restore-keys: |
      ${{ runner.os }}-pip-

# Parallel jobs
jobs:
  test-unit:
    runs-on: ubuntu-latest
    steps: [...]
  
  test-integration:
    runs-on: ubuntu-latest
    steps: [...]
  
  lint:
    runs-on: ubuntu-latest
    steps: [...]

# Conditional execution
- name: Deploy
  if: github.ref == 'refs/heads/main'
  run: ./deploy.sh
```

### Security Best Practices

```yaml
# 1. Use secrets for sensitive data
env:
  DATABASE_PASSWORD: ${{ secrets.DB_PASSWORD }}

# 2. Minimize secret exposure
- name: Login
  run: echo "${{ secrets.PASSWORD }}" | docker login -u user --password-stdin

# 3. Use environment protection
jobs:
  deploy:
    environment: production
    steps: [...]

# 4. Review workflow permissions
permissions:
  contents: read
  pull-requests: write
```

## GitHub Actions Compatibility

### Compatible Actions

Most GitHub Actions work with Forgejo:

```yaml
# Checkout
- uses: actions/checkout@v3

# Setup languages
- uses: actions/setup-python@v4
- uses: actions/setup-node@v3
- uses: actions/setup-go@v4

# Docker
- uses: docker/setup-buildx-action@v2
- uses: docker/build-push-action@v4

# Artifacts
- uses: actions/upload-artifact@v3
- uses: actions/download-artifact@v3
```

### Migrating from GitHub

1. **Copy workflows**: Copy `.github/workflows/` to `.forgejo/workflows/`
2. **Update references**: Change GitHub-specific variables
3. **Test locally**: Run with act (GitHub Actions locally)
4. **Adjust paths**: Update any GitHub-specific paths

```bash
# Test workflow locally with act
brew install act
act -l  # List workflows
act push  # Simulate push event
```

## Related Documentation

- [Forgejo Setup](Forgejo-Setup) - Forgejo configuration
- [Testing Guide](Testing-Guide) - Testing strategies
- [Contributing Guide](Contributing-Guide) - Contribution workflow
- [Development Workflow](Development-Workflow) - Development process
- [Deployment Guide](Deployment-Guide) - Deployment strategies

---

**Quick Reference Card:**

```yaml
# Basic Workflow
name: CI
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - run: ./tests/run-all-tests.sh

# With Services
services:
  postgres:
    image: postgres:16
    env:
      POSTGRES_PASSWORD: test

# With Secrets
env:
  VAULT_TOKEN: ${{ secrets.VAULT_TOKEN }}

# With Artifacts
- uses: actions/upload-artifact@v3
  with:
    name: test-results
    path: results/
```
