#!/bin/bash
set -euo pipefail

# DevStack Core: Sync Documentation to Wiki
# ==========================================
# This script syncs documentation from docs/ to wiki/ directory,
# transforming links and file names to work with GitHub Wiki format.
#
# Usage:
#   ./scripts/docs-to-wiki.sh [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCS_DIR="$REPO_ROOT/docs"
WIKI_DIR="$REPO_ROOT/wiki"
DRY_RUN=false

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}📚 DevStack Core: Docs → Wiki Sync${NC}"
echo -e "${BLUE}===================================${NC}"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}🔍 DRY RUN MODE - No files will be modified${NC}"
    echo ""
fi

# Create wiki directory if it doesn't exist
if [ ! -d "$WIKI_DIR" ]; then
    if [ "$DRY_RUN" = false ]; then
        mkdir -p "$WIKI_DIR"
        echo -e "${GREEN}✅ Created wiki directory${NC}"
    else
        echo -e "${YELLOW}[DRY RUN] Would create wiki directory${NC}"
    fi
fi

# Function to transform doc filename to wiki page name
doc_to_wiki_name() {
    local file="$1"
    local basename=$(basename "$file" .md)

    # Special mappings
    case "$basename" in
        # Core documentation
        "README") echo "Documentation-Index" ;;
        "INSTALLATION") echo "Installation" ;;
        "USAGE") echo "Quick-Start-Guide" ;;
        "SERVICES") echo "Service-Overview" ;;
        "ARCHITECTURE") echo "Architecture-Overview" ;;
        "SERVICE_PROFILES") echo "Service-Configuration" ;;
        "MANAGEMENT") echo "Management-Commands" ;;
        "PYTHON_MANAGEMENT_SCRIPT") echo "CLI-Reference" ;;
        "PYTHON_CLI_COMPLETE_REFERENCE") echo "Python-CLI-Complete-Reference" ;;

        # Infrastructure documentation
        "VAULT") echo "Vault-Integration" ;;
        "VAULT_SECURITY") echo "Vault-Security" ;;
        "REDIS") echo "Redis-Cluster" ;;
        "OBSERVABILITY") echo "Health-Monitoring" ;;
        "ENVIRONMENT_VARIABLES") echo "Container-Management" ;;

        # Operations documentation
        "BEST_PRACTICES") echo "Best-Practices" ;;
        "TROUBLESHOOTING") echo "Common-Issues" ;;
        "DISASTER_RECOVERY") echo "Disaster-Recovery" ;;
        "PERFORMANCE_TUNING") echo "Debugging-Techniques" ;;
        "PERFORMANCE_BASELINE") echo "Volume-Management" ;;
        "IDE_SETUP") echo "Local-Development-Setup" ;;

        # Testing documentation
        "TESTING_APPROACH") echo "Testing-Guide" ;;
        "TEST_RESULTS") echo "Test-Results" ;;

        # Security documentation
        "SECURITY_ASSESSMENT") echo "Certificate-Management" ;;

        # Project documentation
        "FAQ") echo "FAQ" ;;
        "ACKNOWLEDGEMENTS") echo "Acknowledgements" ;;
        "TASK_PROGRESS") echo "Task-Progress" ;;

        # Profile documentation
        "PROFILE_IMPLEMENTATION_GUIDE") echo "Profile-Implementation-Guide" ;;
        "PROFILE_VALIDATION_RESULTS") echo "Profile-Validation-Results" ;;
        "PROFILE_TESTING_CHECKLIST") echo "Profile-Testing-Checklist" ;;

        # Rollback documentation
        "ROLLBACK_PROCEDURES") echo "Rollback-Procedures" ;;
        "ROLLBACK_PROCEDURES_ACCURACY_REVIEW") echo "Rollback-Procedures-Accuracy-Review" ;;
        "ROLLBACK_TEST_SUMMARY") echo "Rollback-Test-Summary" ;;
        "ROLLBACK_DOCUMENTATION_CORRECTIONS_SUMMARY") echo "Rollback-Documentation-Corrections-Summary" ;;

        # Infrastructure analysis
        "AUTOMATION_INFRASTRUCTURE_DESIGN") echo "Migration-Guide" ;;
        "VOIP_INFRASTRUCTURE_ANALYSIS") echo "Backup-and-Restore" ;;
        "ANSIBLE_DYNAMIC_INVENTORY_POSTGRESQL") echo "Ansible-Dynamic-Inventory-PostgreSQL" ;;

        # Historical/reference documentation
        "BASELINE_20251114") echo "Baseline-20251114" ;;
        "PHASE_VALIDATION_REPORT") echo "Phase-Validation-Report" ;;
        "REPOSITORY_CLEANUP_SUMMARY") echo "Repository-Cleanup-Summary" ;;
        "DOCUMENTATION_VERIFICATION_SUMMARY") echo "Documentation-Verification-Summary" ;;
        "LINK_FIXES_SUMMARY") echo "Link-Fixes-Summary" ;;
        "RACE_CONDITION_FIX") echo "Race-Condition-Fix" ;;
        "IMPROVEMENT_TASK_LIST") echo "Improvement-Task-List" ;;

        # Default: convert underscores to hyphens
        *) echo "$basename" | sed 's/_/-/g' ;;
    esac
}

# Function to transform markdown links for wiki
transform_links() {
    local file="$1"
    local temp_file="${file}.tmp"

    # Transform links:
    # ./docs/FILE.md → FILE (wiki page name)
    # ./reference-apps/README.md → Development-Workflow
    # #section → #section (keep anchor links)
    # External links → unchanged

    sed -E \
        -e 's|\./docs/README\.md|Documentation-Index|g' \
        -e 's|\./docs/INSTALLATION\.md|Installation|g' \
        -e 's|\./docs/USAGE\.md|Quick-Start-Guide|g' \
        -e 's|\./docs/SERVICES\.md|Service-Overview|g' \
        -e 's|\./docs/ARCHITECTURE\.md|Architecture-Overview|g' \
        -e 's|\./docs/SERVICE_PROFILES\.md|Service-Configuration|g' \
        -e 's|\./docs/MANAGEMENT\.md|Management-Commands|g' \
        -e 's|\./docs/PYTHON_MANAGEMENT_SCRIPT\.md|CLI-Reference|g' \
        -e 's|\./docs/PYTHON_CLI_COMPLETE_REFERENCE\.md|Python-CLI-Complete-Reference|g' \
        -e 's|\./docs/VAULT\.md|Vault-Integration|g' \
        -e 's|\./docs/VAULT_SECURITY\.md|Vault-Security|g' \
        -e 's|\./docs/REDIS\.md|Redis-Cluster|g' \
        -e 's|\./docs/OBSERVABILITY\.md|Health-Monitoring|g' \
        -e 's|\./docs/ENVIRONMENT_VARIABLES\.md|Container-Management|g' \
        -e 's|\./docs/BEST_PRACTICES\.md|Best-Practices|g' \
        -e 's|\./docs/TROUBLESHOOTING\.md|Common-Issues|g' \
        -e 's|\./docs/DISASTER_RECOVERY\.md|Disaster-Recovery|g' \
        -e 's|\./docs/PERFORMANCE_TUNING\.md|Debugging-Techniques|g' \
        -e 's|\./docs/PERFORMANCE_BASELINE\.md|Volume-Management|g' \
        -e 's|\./docs/IDE_SETUP\.md|Local-Development-Setup|g' \
        -e 's|\./docs/TESTING_APPROACH\.md|Testing-Guide|g' \
        -e 's|\./docs/TEST_RESULTS\.md|Test-Results|g' \
        -e 's|\./docs/SECURITY_ASSESSMENT\.md|Certificate-Management|g' \
        -e 's|\./docs/FAQ\.md|FAQ|g' \
        -e 's|\./docs/ACKNOWLEDGEMENTS\.md|Acknowledgements|g' \
        -e 's|\./docs/TASK_PROGRESS\.md|Task-Progress|g' \
        -e 's|\./docs/PROFILE_IMPLEMENTATION_GUIDE\.md|Profile-Implementation-Guide|g' \
        -e 's|\./docs/PROFILE_VALIDATION_RESULTS\.md|Profile-Validation-Results|g' \
        -e 's|\./docs/PROFILE_TESTING_CHECKLIST\.md|Profile-Testing-Checklist|g' \
        -e 's|\./docs/ROLLBACK_PROCEDURES\.md|Rollback-Procedures|g' \
        -e 's|\./docs/ROLLBACK_PROCEDURES_ACCURACY_REVIEW\.md|Rollback-Procedures-Accuracy-Review|g' \
        -e 's|\./docs/ROLLBACK_TEST_SUMMARY\.md|Rollback-Test-Summary|g' \
        -e 's|\./docs/ROLLBACK_DOCUMENTATION_CORRECTIONS_SUMMARY\.md|Rollback-Documentation-Corrections-Summary|g' \
        -e 's|\./docs/voip/ANSIBLE_DYNAMIC_INVENTORY_POSTGRESQL\.md|Ansible-Dynamic-Inventory-PostgreSQL|g' \
        -e 's|\./reference-apps/README\.md|Development-Workflow|g' \
        -e 's|\./reference-apps/API_PATTERNS\.md|API-Patterns|g' \
        -e 's|\.github/CHANGELOG\.md|Changelog|g' \
        -e 's|\.github/CONTRIBUTING\.md|Contributing-Guide|g' \
        -e 's|\.github/SECURITY\.md|Secrets-Rotation|g' \
        "$file" > "$temp_file"

    mv "$temp_file" "$file"
}

# Sync function
sync_file() {
    local src="$1"
    local dest_name="$2"
    local label="$3"

    local dest="$WIKI_DIR/${dest_name}.md"

    if [ "$DRY_RUN" = true ]; then
        echo -e "${BLUE}  📄 ${label}${NC}"
        echo -e "     ${YELLOW}[DRY RUN] Would sync: $src → $dest${NC}"
        return
    fi

    echo -e "${BLUE}  📄 ${label}${NC}"
    cp "$src" "$dest"
    transform_links "$dest"
    echo -e "     ${GREEN}✅ Synced to: $dest_name.md${NC}"
}

echo -e "${BLUE}📖 Syncing Core Documentation...${NC}"
sync_file "$REPO_ROOT/README.md" "Home" "README → Home"
sync_file "$DOCS_DIR/README.md" "Documentation-Index" "Documentation Index"
sync_file "$DOCS_DIR/INSTALLATION.md" "Installation" "Installation Guide"
sync_file "$DOCS_DIR/USAGE.md" "Quick-Start-Guide" "Quick Start Guide"
sync_file "$DOCS_DIR/SERVICES.md" "Service-Overview" "Service Overview"
sync_file "$DOCS_DIR/ARCHITECTURE.md" "Architecture-Overview" "Architecture Overview"
sync_file "$DOCS_DIR/SERVICE_PROFILES.md" "Service-Configuration" "Service Configuration"
sync_file "$DOCS_DIR/MANAGEMENT.md" "Management-Commands" "Management Commands"
sync_file "$DOCS_DIR/PYTHON_MANAGEMENT_SCRIPT.md" "CLI-Reference" "CLI Reference"
sync_file "$DOCS_DIR/PYTHON_CLI_COMPLETE_REFERENCE.md" "Python-CLI-Complete-Reference" "Python CLI Complete Reference"

echo ""
echo -e "${BLUE}🏗️  Syncing Infrastructure Docs...${NC}"
sync_file "$DOCS_DIR/VAULT.md" "Vault-Integration" "Vault Integration"
sync_file "$DOCS_DIR/VAULT_SECURITY.md" "Vault-Security" "Vault Security"
sync_file "$DOCS_DIR/REDIS.md" "Redis-Cluster" "Redis Cluster"
sync_file "$DOCS_DIR/OBSERVABILITY.md" "Health-Monitoring" "Health Monitoring"
sync_file "$DOCS_DIR/ENVIRONMENT_VARIABLES.md" "Container-Management" "Container Management"
sync_file "$DOCS_DIR/voip/ANSIBLE_DYNAMIC_INVENTORY_POSTGRESQL.md" "Ansible-Dynamic-Inventory-PostgreSQL" "Ansible Dynamic Inventory PostgreSQL"
sync_file "$DOCS_DIR/voip/AUTOMATION_INFRASTRUCTURE_DESIGN.md" "Migration-Guide" "Migration Guide"
sync_file "$DOCS_DIR/voip/VOIP_INFRASTRUCTURE_ANALYSIS.md" "Backup-and-Restore" "Backup and Restore"

echo ""
echo -e "${BLUE}⚙️  Syncing Operations Docs...${NC}"
sync_file "$DOCS_DIR/BEST_PRACTICES.md" "Best-Practices" "Best Practices"
sync_file "$DOCS_DIR/TROUBLESHOOTING.md" "Common-Issues" "Common Issues"
sync_file "$DOCS_DIR/DISASTER_RECOVERY.md" "Disaster-Recovery" "Disaster Recovery"
sync_file "$DOCS_DIR/PERFORMANCE_TUNING.md" "Debugging-Techniques" "Debugging Techniques"
sync_file "$DOCS_DIR/PERFORMANCE_BASELINE.md" "Volume-Management" "Volume Management"
sync_file "$DOCS_DIR/IDE_SETUP.md" "Local-Development-Setup" "Local Development Setup"

echo ""
echo -e "${BLUE}🧪 Syncing Testing Docs...${NC}"
sync_file "$DOCS_DIR/TESTING_APPROACH.md" "Testing-Guide" "Testing Guide"
sync_file "$REPO_ROOT/tests/README.md" "Vault-Troubleshooting" "Vault Troubleshooting"
sync_file "$REPO_ROOT/tests/TEST_COVERAGE.md" "PostgreSQL-Operations" "PostgreSQL Operations"

echo ""
echo -e "${BLUE}🔒 Syncing Security Docs...${NC}"
sync_file "$DOCS_DIR/SECURITY_ASSESSMENT.md" "Certificate-Management" "Certificate Management"
sync_file "$REPO_ROOT/.github/SECURITY.md" "Secrets-Rotation" "Secrets Rotation"

echo ""
echo -e "${BLUE}📋 Syncing Project Docs...${NC}"
sync_file "$REPO_ROOT/.github/CHANGELOG.md" "Changelog" "Changelog"
sync_file "$REPO_ROOT/.github/CONTRIBUTING.md" "Contributing-Guide" "Contributing Guide"
sync_file "$DOCS_DIR/FAQ.md" "FAQ" "FAQ"
sync_file "$DOCS_DIR/ACKNOWLEDGEMENTS.md" "Acknowledgements" "Acknowledgements"

echo ""
echo -e "${BLUE}👨‍💻 Syncing Reference Apps...${NC}"
sync_file "$REPO_ROOT/reference-apps/README.md" "Development-Workflow" "Development Workflow"
sync_file "$REPO_ROOT/reference-apps/API_PATTERNS.md" "API-Patterns" "API Patterns"

echo ""
echo -e "${BLUE}⚙️  Syncing Profile Documentation...${NC}"
sync_file "$DOCS_DIR/PROFILE_IMPLEMENTATION_GUIDE.md" "Profile-Implementation-Guide" "Profile Implementation Guide"

echo ""
echo -e "${BLUE}🔄 Syncing Rollback Documentation...${NC}"
sync_file "$DOCS_DIR/ROLLBACK_PROCEDURES.md" "Rollback-Procedures" "Rollback Procedures"

# Count files
WIKI_COUNT=$(command ls -1 "$WIKI_DIR"/*.md 2>/dev/null | wc -l | tr -d ' ')

echo ""
echo -e "${GREEN}✅ Sync Complete!${NC}"
echo ""
echo -e "${BLUE}📊 Summary:${NC}"
echo -e "   Wiki pages synced: ${GREEN}$WIKI_COUNT${NC}"
echo -e "   Location: ${BLUE}$WIKI_DIR${NC}"
echo ""

if [ "$DRY_RUN" = false ]; then
    echo -e "${YELLOW}📤 Next steps:${NC}"
    echo -e "   1. Review changes: ${BLUE}git diff wiki/${NC}"
    echo -e "   2. Sync to GitHub Wiki: ${BLUE}./scripts/sync-wiki.sh${NC}"
    echo ""
else
    echo -e "${YELLOW}[DRY RUN] No files were modified${NC}"
    echo ""
fi
