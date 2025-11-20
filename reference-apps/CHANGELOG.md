# Reference Apps Changelog

## Table of Contents

- [[1.1.0] - 2025-10-27](#110-2025-10-27)
  - [Added](#added)
  - [Changed](#changed)
  - [Fixed](#fixed)
  - [Test Results](#test-results)
  - [Technical Details](#technical-details)
    - [API Endpoints](#api-endpoints)
    - [Docker Services](#docker-services)
    - [Test Suite Location](#test-suite-location)
    - [Running Tests](#running-tests)
    - [Starting Services](#starting-services)
  - [Architecture](#architecture)
  - [Security](#security)
  - [Documentation](#documentation)
- [[1.0.0] - Previous Release](#100-previous-release)

---

## [1.1.0] - 2025-10-27

### Added
- **API-First Implementation** - Complete containerized FastAPI implementation running on port 8001
  - Generated from OpenAPI specification following API-first development pattern
  - Docker containerization with Dockerfile, init.sh, and start.sh
  - Vault integration for secrets management
  - TLS/HTTPS support on port 8444
  - Health checks and proper service dependencies
  - Allocated IP 172.20.0.104 in dev-services network

- **Shared Test Suite** - Comprehensive parity validation between implementations
  - 26 automated tests ensuring identical behavior
  - Parametrized fixtures testing both code-first (8000) and API-first (8001)
  - Test categories:
    - Parity tests: Run against both implementations independently
    - Comparison tests: Direct response comparison between implementations
  - Coverage areas:
    - Root endpoint structure and content
    - OpenAPI specification matching
    - Health check endpoints (simple and vault-specific)
    - Cache endpoint behavior
    - Metrics endpoint format
    - Error handling (404 responses)
  - Complete documentation in reference-apps/shared/test-suite/README.md

### Changed
- **docker-compose.yml** - Added api-first service configuration
  - Service name: api-first
  - Container name: dev-api-first
  - Ports: 8001 (HTTP), 8444 (HTTPS)
  - Network IP: 172.20.0.104
  - Health checks configured
  - Dependencies: vault, postgres, mysql

- **fastapi-api-first/requirements.txt** - Updated dependencies for compatibility
  - Aligned all package versions with code-first implementation
  - Fixed pymongo/motor version conflicts
  - Ensures consistent behavior across both implementations

- **fastapi-api-first/app/main.py** - Root endpoint now returns complete API information
  - Matches code-first response structure exactly
  - Includes security configuration details
  - Lists all available endpoints
  - Documents rate limiting and circuit breaker settings

### Fixed
- Root endpoint parity between code-first and API-first implementations
- Dependency version conflicts in API-first requirements.txt
- Docker image build process for API-first service

### Test Results
- **Shared Test Suite**: 26/26 tests passing (100% parity achieved)
- **Pre-commit Hooks**: API synchronization validation passing
- **Both APIs**: Healthy and operational

### Technical Details

#### API Endpoints
- **Code-First**: http://localhost:8000
- **API-First**: http://localhost:8001

#### Docker Services
- Service: api-first
- Container: dev-api-first
- Network: dev-services (172.20.0.104)
- Health Check: HTTP GET http://localhost:8001/health

#### Test Suite Location
- Path: reference-apps/shared/test-suite/
- Configuration: pytest.ini
- Fixtures: conftest.py
- Tests: test_health_checks.py, test_api_parity.py

#### Running Tests
```bash
cd reference-apps/shared/test-suite
pip install -r requirements.txt
pytest -v
```

#### Starting Services
```bash
# Start both APIs
docker compose up -d reference-api api-first

# Verify health
curl http://localhost:8000/health/
curl http://localhost:8001/health/
```

### Architecture
Both implementations demonstrate real-world API development patterns:
- **Code-First** (port 8000): Implementation drives documentation
- **API-First** (port 8001): Contract drives implementation

The shared test suite ensures both approaches maintain identical behavior and API contracts.

### Security
- All secrets managed through Vault
- TLS/HTTPS support on both implementations
- Rate limiting and circuit breakers configured
- CORS properly configured
- Request validation middleware active

### Documentation
- Shared test suite README with complete usage instructions
- API-first Dockerfile with detailed comments
- Startup scripts with comprehensive documentation
- This CHANGELOG documenting all changes

---

## [1.0.0] - Previous Release

Initial implementation of code-first FastAPI reference application.
