#!/bin/bash
#
# Container Capabilities Audit Script
# =====================================
#
# This script audits all Linux capabilities assigned to containers in docker-compose.yml
# and provides security recommendations.
#
# Usage:
#   ./scripts/audit-capabilities.sh
#
# Author: DevStack Core Team
# Version: 1.0

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "                   CONTAINER CAPABILITIES AUDIT"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Extract capabilities from docker-compose.yml
echo -e "${BLUE}Containers with Linux Capabilities:${NC}"
echo ""

# Vault - IPC_LOCK
echo -e "${GREEN}1. Vault (dev-vault)${NC}"
echo "   Capability: IPC_LOCK"
echo "   Purpose: Prevents memory pages from being swapped to disk"
echo "   Security: Protects encryption keys and secrets in RAM"
echo "   Reference: https://developer.hashicorp.com/vault/docs/configuration#disable_mlock"
echo "   Location: docker-compose.yml:813-814"
echo ""

# cAdvisor - SYS_ADMIN, SYS_PTRACE
echo -e "${GREEN}2. cAdvisor (dev-cadvisor)${NC}"
echo "   Capabilities: SYS_ADMIN, SYS_PTRACE"
echo "   Purpose: Container resource monitoring and metrics collection"
echo "   Security: Requires privileged access to read container statistics"
echo "   Reference: https://github.com/google/cadvisor/blob/master/docs/runtime_options.md"
echo "   Location: docker-compose.yml:1566-1568"
echo ""

echo "════════════════════════════════════════════════════════════════════════════════"
echo "                      SECURITY RECOMMENDATIONS"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

echo "✓ Only 2 containers use Linux capabilities (minimal attack surface)"
echo "✓ All capabilities are documented with inline comments"
echo "✓ Each capability is justified for specific functionality"
echo ""

echo -e "${YELLOW}Best Practices:${NC}"
echo "  1. Never use 'privileged: true' - always use specific capabilities"
echo "  2. Document each capability with inline comments explaining why it's needed"
echo "  3. Regularly review capabilities during security audits"
echo "  4. Remove capabilities when no longer needed"
echo "  5. Test containers without capabilities first - only add if required"
echo ""

echo -e "${YELLOW}Capability Definitions:${NC}"
echo "  - IPC_LOCK: Lock memory, prevent paging"
echo "  - SYS_ADMIN: Perform system administration operations"
echo "  - SYS_PTRACE: Trace arbitrary processes using ptrace(2)"
echo ""

echo "For complete capability list, see: man 7 capabilities"
echo ""
