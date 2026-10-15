#!/usr/bin/env python3
"""
Add profile labels to docker-compose.yml services

This script adds Docker Compose profile labels to all services in docker-compose.yml
according to the profile strategy defined in profiles.yaml.

Usage:
    python3 scripts/add-profile-labels.py
"""

import re
from pathlib import Path

# Profile assignments for each service
PROFILE_ASSIGNMENTS = {
    # Services already updated
    "postgres": {
        "profiles": '["minimal", "standard", "full"]',
        "comment": "Available in minimal, standard, and full profiles\n    # Core database for Forgejo (Git server) and local development"
    },
    "pgbouncer": {
        "profiles": '["minimal", "standard", "full"]',
        "comment": "Available in minimal, standard, and full profiles\n    # Connection pooling for PostgreSQL (recommended for all scenarios)"
    },
    "mysql": {
        "profiles": '["standard", "full"]',
        "comment": "Available in standard and full profiles only\n    # Legacy database support for multi-database applications"
    },
    "redis-1": {
        "profiles": '["minimal", "standard", "full"]',
        "comment": "Available in minimal (standalone), standard (cluster node 1), and full profiles\n    # In minimal: runs standalone mode (no cluster). In standard/full: cluster node 1 (slots 0-5460)"
    },
    "redis-2": {
        "profiles": '["standard", "full"]',
        "comment": "Available in standard and full profiles only\n    # Redis cluster node 2 (slots 5461-10922) - NOT included in minimal profile"
    },
    "redis-3": {
        "profiles": '["standard", "full"]',
        "comment": "Available in standard and full profiles only\n    # Redis cluster node 3 (slots 10923-16383) - NOT included in minimal profile"
    },

    # Services to update
    "rabbitmq": {
        "profiles": '["standard", "full"]',
        "comment": "Available in standard and full profiles only\n    # Message queue for asynchronous communication between services"
    },
    "mongodb": {
        "profiles": '["standard", "full"]',
        "comment": "Available in standard and full profiles only\n    # NoSQL document database for unstructured data"
    },
    "forgejo": {
        "profiles": '["minimal", "standard", "full"]',
        "comment": "Available in minimal, standard, and full profiles\n    # Self-hosted Git server with Forgejo"
    },
    "vault": {
        "profiles": None,  # No profile = always starts
        "comment": "NO PROFILE - Always starts (required for all profiles)\n    # Secrets management and PKI infrastructure"
    },
    "reference-api": {
        "profiles": '["reference"]',
        "comment": "Available in reference profile\n    # Python FastAPI code-first implementation (port 8000/8443)"
    },
    "api-first": {
        "profiles": '["reference"]',
        "comment": "Available in reference profile\n    # Python FastAPI API-first implementation (port 8001/8444)"
    },
    "golang-api": {
        "profiles": '["reference"]',
        "comment": "Available in reference profile\n    # Go with Gin framework (port 8002/8445)"
    },
    "nodejs-api": {
        "profiles": '["reference"]',
        "comment": "Available in reference profile\n    # Node.js with Express (port 8003/8446)"
    },
    "rust-api": {
        "profiles": '["reference"]',
        "comment": "Available in reference profile\n    # Rust with Actix-web (port 8004/8447, ~40% complete)"
    },
    "prometheus": {
        "profiles": '["full"]',
        "comment": "Available in full profile only\n    # Metrics collection and time-series database"
    },
    "grafana": {
        "profiles": '["full"]',
        "comment": "Available in full profile only\n    # Visualization dashboards (http://localhost:3001)"
    },
    "loki": {
        "profiles": '["full"]',
        "comment": "Available in full profile only\n    # Log aggregation system"
    },
    "redis-exporter-1": {
        "profiles": '["full"]',
        "comment": "Available in full profile only\n    # Redis metrics exporter for node 1"
    },
    "redis-exporter-2": {
        "profiles": '["full"]',
        "comment": "Available in full profile only\n    # Redis metrics exporter for node 2"
    },
    "redis-exporter-3": {
        "profiles": '["full"]',
        "comment": "Available in full profile only\n    # Redis metrics exporter for node 3"
    },
    "cadvisor": {
        "profiles": '["full"]',
        "comment": "Available in full profile only\n    # Container resource monitoring"
    },
    "vector": {
        "profiles": '["full"]',
        "comment": "Available in full profile only\n    # Unified observability data pipeline"
    },
}

def add_profile_label(service_name: str, service_block: str) -> str:
    """Add profile label to a service block"""

    if service_name not in PROFILE_ASSIGNMENTS:
        return service_block  # Skip services not in our mapping

    assignment = PROFILE_ASSIGNMENTS[service_name]

    # Check if profile already exists
    if "profiles:" in service_block or "# PROFILE:" in service_block:
        print(f"  ✓ {service_name}: Profile already assigned")
        return service_block

    # Find the line after "restart: unless-stopped"
    pattern = r'(    restart: unless-stopped\n)'

    if assignment["profiles"] is None:
        # Vault - add comment but no profile
        replacement = (
            r'\1\n'
            f'    # PROFILE: {assignment["comment"]}\n'
        )
    else:
        # All other services - add profile label
        replacement = (
            r'\1\n'
            f'    # PROFILE: {assignment["comment"]}\n'
            f'    profiles: {assignment["profiles"]}\n'
        )

    updated_block = re.sub(pattern, replacement, service_block)

    if updated_block == service_block:
        print(f"  ⚠ {service_name}: Could not find 'restart: unless-stopped'")
        return service_block

    print(f"  ✓ {service_name}: Profile label added")
    return updated_block

def main():
    """Main function to process docker-compose.yml"""

    compose_file = Path(__file__).parent.parent / "docker-compose.yml"

    if not compose_file.exists():
        print(f"❌ Error: {compose_file} not found")
        return 1

    print("🔧 Adding profile labels to docker-compose.yml services...\n")

    # Read the file
    content = compose_file.read_text()

    # Split into services using regex
    # Match service blocks starting with "  service-name:" and ending before next service or EOF
    service_pattern = re.compile(
        r'(^  ([a-z][a-z0-9-]*):$.*?)(?=^  [a-z][a-z0-9-]*:$|^networks:|^volumes:|\\Z)',
        re.MULTILINE | re.DOTALL
    )

    # Process each service
    updated_content = content
    for match in service_pattern.finditer(content):
        service_block = match.group(1)
        service_name = match.group(2)

        # Skip non-service sections (options, dev-services, etc.)
        if service_name in ["options", "dev-services"]:
            continue

        updated_block = add_profile_label(service_name, service_block)
        updated_content = updated_content.replace(service_block, updated_block, 1)

    # Write back to file
    compose_file.write_text(updated_content)

    print(f"\n✅ Successfully updated {compose_file}")
    print("\nNext steps:")
    print("  1. Review changes: git diff docker-compose.yml")
    print("  2. Test profiles: docker compose --profile minimal config --services")
    print("  3. Start with profile: ./devstack.py start --profile minimal")

    return 0

if __name__ == "__main__":
    exit(main())
