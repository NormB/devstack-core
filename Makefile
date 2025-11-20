# Makefile for DevStack Core - API Synchronization
#
# This Makefile provides a platform-agnostic interface for API synchronization
# validation. All CI/CD systems (GitHub Actions, GitLab, Jenkins, etc.) should
# invoke these targets rather than calling scripts directly.
#
# Key Principle: Local enforcement via git hooks, CI/CD is safety net
#
# Usage:
#   make validate          - Run all validation checks
#   make test              - Run shared test suite
#   make sync-check        - Check API synchronization
#   make sync-report       - Generate detailed sync report
#   make extract-openapi   - Extract OpenAPI from code-first
#   make regenerate        - Regenerate API-first from spec
#   make install-hooks     - Install git pre-commit hooks
#   make help              - Show this help message

.PHONY: help validate test sync-check sync-report extract-openapi regenerate install-hooks clean

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m  # No Color

##@ General

help: ## Display this help message
	@echo "$(BLUE)DevStack Core - API Synchronization$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@awk 'BEGIN {FS = ":.*##"; printf ""} \
		/^[a-zA-Z_-]+:.*?##/ { printf "  $(BLUE)%-20s$(NC) %s\n", $$1, $$2 } \
		/^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo ""

##@ Validation

validate: ## Run all validation checks (use in CI/CD)
	@echo "$(BLUE)[VALIDATE]$(NC) Running all validation checks..."
	@$(MAKE) validate-spec
	@$(MAKE) sync-check
	@$(MAKE) test
	@echo "$(GREEN)[SUCCESS]$(NC) All validation checks passed!"

validate-spec: ## Validate OpenAPI specification
	@echo "$(BLUE)[VALIDATE]$(NC) Checking OpenAPI specification..."
	@if command -v yq >/dev/null 2>&1; then \
		yq eval . reference-apps/shared/openapi.yaml >/dev/null && \
		echo "$(GREEN)[OK]$(NC) OpenAPI spec is valid YAML"; \
	else \
		echo "$(RED)[ERROR]$(NC) yq not installed. Install: brew install yq"; \
		exit 1; \
	fi

sync-check: ## Check if both implementations match OpenAPI spec
	@echo "$(BLUE)[SYNC-CHECK]$(NC) Verifying API synchronization..."
	@./scripts/validate-sync.sh

sync-report: ## Generate detailed synchronization report
	@echo "$(BLUE)[SYNC-REPORT]$(NC) Generating detailed sync report..."
	@./scripts/sync-report.sh

##@ Code Generation

extract-openapi: ## Extract OpenAPI spec from code-first implementation
	@echo "$(BLUE)[EXTRACT]$(NC) Extracting OpenAPI from code-first..."
	@./scripts/extract-openapi.sh

regenerate: regenerate-api-first ## Regenerate API-first implementation (alias)

regenerate-api-first: ## Regenerate API-first from OpenAPI spec
	@echo "$(BLUE)[REGENERATE]$(NC) Regenerating API-first implementation..."
	@./scripts/regenerate-api-first.sh

##@ Testing

test: test-shared ## Run all tests (alias)

test-shared: ## Run shared test suite against both implementations
	@echo "$(BLUE)[TEST]$(NC) Running shared test suite..."
	@if [ -f "tests/test_shared.py" ]; then \
		PYTHONPATH=. pytest tests/test_shared.py -v; \
	else \
		echo "$(YELLOW)[SKIP]$(NC) Shared test suite not yet implemented"; \
	fi

test-code-first: ## Test code-first implementation only
	@echo "$(BLUE)[TEST]$(NC) Testing code-first implementation..."
	@cd reference-apps/fastapi && pytest tests/ -v

test-api-first: ## Test API-first implementation only
	@echo "$(BLUE)[TEST]$(NC) Testing API-first implementation..."
	@cd reference-apps/fastapi-api-first && pytest tests/ -v

##@ Development

install-hooks: ## Install git pre-commit hooks
	@echo "$(BLUE)[INSTALL]$(NC) Installing git pre-commit hooks..."
	@./scripts/install-hooks.sh

start-code-first: ## Start code-first implementation
	@echo "$(BLUE)[START]$(NC) Starting code-first implementation on port 8000..."
	@cd reference-apps/fastapi && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

start-api-first: ## Start API-first implementation
	@echo "$(BLUE)[START]$(NC) Starting API-first implementation on port 8001..."
	@cd reference-apps/fastapi-api-first && uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload

##@ Cleanup

clean: ## Clean generated files and caches
	@echo "$(BLUE)[CLEAN]$(NC) Cleaning generated files..."
	@find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
	@find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name "*.pyc" -delete 2>/dev/null || true
	@echo "$(GREEN)[OK]$(NC) Cleanup complete"

##@ Information

status: ## Show synchronization status
	@echo "$(BLUE)DevStack Core - Synchronization Status$(NC)"
	@echo ""
	@echo "$(YELLOW)OpenAPI Specification:$(NC)"
	@if [ -f "reference-apps/shared/openapi.yaml" ]; then \
		LINES=$$(wc -l < reference-apps/shared/openapi.yaml | tr -d ' '); \
		SIZE=$$(du -h reference-apps/shared/openapi.yaml | cut -f1); \
		echo "  Location: reference-apps/shared/openapi.yaml"; \
		echo "  Size: $$SIZE ($$LINES lines)"; \
		ENDPOINTS=$$(yq eval '.paths | length' reference-apps/shared/openapi.yaml 2>/dev/null || echo "?"); \
		echo "  Endpoints: $$ENDPOINTS"; \
	else \
		echo "  $(RED)NOT FOUND$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)Code-First Implementation:$(NC)"
	@if [ -d "reference-apps/fastapi" ]; then \
		FILES=$$(find reference-apps/fastapi/app -name "*.py" 2>/dev/null | wc -l | tr -d ' '); \
		echo "  Location: reference-apps/fastapi/"; \
		echo "  Python files: $$FILES"; \
	else \
		echo "  $(RED)NOT FOUND$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)API-First Implementation:$(NC)"
	@if [ -d "reference-apps/fastapi-api-first" ]; then \
		FILES=$$(find reference-apps/fastapi-api-first/app -name "*.py" 2>/dev/null | wc -l | tr -d ' '); \
		echo "  Location: reference-apps/fastapi-api-first/"; \
		echo "  Python files: $$FILES"; \
	else \
		echo "  $(RED)NOT FOUND$(NC)"; \
	fi
	@echo ""
	@echo "$(YELLOW)Git Hooks:$(NC)"
	@if [ -f ".git/hooks/pre-commit" ]; then \
		echo "  Pre-commit: $(GREEN)INSTALLED$(NC)"; \
	else \
		echo "  Pre-commit: $(RED)NOT INSTALLED$(NC) (run: make install-hooks)"; \
	fi

version: ## Show version information
	@echo "DevStack Core API Synchronization v1.0.0"
	@echo "Platform-agnostic validation framework"
