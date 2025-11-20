# Python Management Script Guide

## Overview

`devstack` is a modern Python-based management interface for DevStack Core with comprehensive service profile support. It provides a beautiful CLI experience with colored output, tables, and progress indicators.

**Features:**
- Service profile management (minimal, standard, full, reference)
- Automatic environment loading from profile .env files
- Beautiful terminal output with Rich library
- Health checks for all services
- Service logs and shell access
- Redis cluster initialization
- Profile listing and validation
- Comprehensive built-in help for all commands

## Getting Help

The script includes comprehensive help documentation accessible via standard help commands:

```bash
# Main help - shows all commands
./devstack --help
./devstack -h

# Help for specific command - shows all options and examples
./devstack start --help
./devstack logs --help
./devstack stop --help
./devstack vault-show-password --help

# Version information
./devstack --version
```

**Every command includes:**
- **ARGUMENTS:** Required and optional arguments
- **OPTIONS:** All available flags and parameters with defaults
- **EXAMPLES:** Real-world usage examples
- **NOTES:** Important warnings, tips, and gotchas

**Examples of getting help:**
```bash
# See all available --profile options for start command
./devstack start --help

# Learn about log viewing options (--follow, --tail)
./devstack logs --help

# Understand which services can be queried for passwords
./devstack vault-show-password --help
```

## Installation

### Prerequisites

- Python 3.8 or higher (Python 3.14.0 confirmed working)
- pip3 package manager

### Install Dependencies

#### Option 1: Using pip (Recommended for development)

```bash
# Install using uv (recommended)
uv venv
uv pip install -r scripts/requirements.txt

# The wrapper script automatically uses the venv
# No manual activation needed!
```

#### Option 2: Using a Virtual Environment Manually

```bash
# If you prefer to manage the venv yourself:
python3 -m venv .venv
source .venv/bin/activate
pip3 install -r scripts/requirements.txt

# Deactivate when done
deactivate

# Note: The wrapper script handles activation automatically
```

#### Option 3: Using Homebrew Python (macOS)

```bash
# If using Homebrew Python
brew install python@3

# Install dependencies with Homebrew pip
/opt/homebrew/bin/pip3 install click rich PyYAML python-dotenv
```

### Verify Installation

```bash
# Test that all dependencies are available
python3 -c "import click, rich, yaml; print('All dependencies installed!')"

# Test the script
./devstack --version
./devstack --help
```

## Quick Start

### Basic Usage

```bash
# Start with standard profile (recommended)
./devstack start --profile standard

# Check status
./devstack status

# Check health
./devstack health

# Stop services
./devstack stop
```

### Common Workflows

**Morning Routine (Start Development Environment):**
```bash
# Start full development stack
./devstack start --profile standard

# Initialize Redis cluster (first time only)
./devstack redis-cluster-init

# Check all services are healthy
./devstack health
```

**End of Day (Stop Everything):**
```bash
# Stop all services and Colima VM
./devstack stop
```

**Quick Check (Status Without Starting):**
```bash
# Check what's running
./devstack status

# Get Colima IP address
./devstack ip
```

## Commands

### start

Start Colima VM and Docker services with specified profile(s).

```bash
# Start with minimal profile
./devstack start --profile minimal

# Start with standard profile (default)
./devstack start --profile standard

# Start with full profile (all services + observability)
./devstack start --profile full

# Combine multiple profiles
./devstack start --profile standard --profile reference

# Start in foreground (see logs in real-time)
./devstack start --profile minimal --no-detach
```

**Options:**
- `--profile, -p`: Service profile(s) to start (can specify multiple)
- `--detach/--no-detach, -d`: Run in background (default: True)

**Examples:**
```bash
# Minimal profile (5 services, 2GB RAM)
./devstack start --profile minimal

# Standard profile with reference apps (15 services)
./devstack start --profile standard --profile reference

# Full profile (18 services, 6GB RAM)
./devstack start --profile full
```

### stop

Stop Docker services and optionally Colima VM.

```bash
# Stop everything (services + Colima VM)
./devstack stop

# Stop only specific profile services (keeps Colima running)
./devstack stop --profile standard
./devstack stop --profile reference
```

**Options:**
- `--profile, -p`: Only stop services from specific profile(s)

### status

Display status of Colima VM and all running services with resource usage.

```bash
# Show full status
./devstack status
```

**Output includes:**
- Colima VM status (running/stopped)
- Docker service list with status
- Resource usage (CPU, memory)

### health

Check health status of all running services.

```bash
# Check health of all services
./devstack health
```

**Output shows:**
- Service name
- Running status (running/stopped/exited)
- Health check result (healthy/unhealthy/no healthcheck)

**Color coding:**
- Green: Healthy and running
- Yellow: Running but no healthcheck or starting
- Red: Stopped or unhealthy

### logs

View logs for all services or a specific service.

```bash
# View all service logs (last 100 lines)
./devstack logs

# View specific service logs
./devstack logs postgres
./devstack logs vault

# Follow logs (like tail -f)
./devstack logs -f redis-1

# Show more lines
./devstack logs --tail 500 postgres

# Follow multiple services (using docker compose directly)
docker compose logs -f postgres vault
```

**Options:**
- `--follow, -f`: Follow log output (stream continuously)
- `--tail, -n`: Number of lines to show (default: 100)

### shell

Open an interactive shell in a running container.

```bash
# Open shell in PostgreSQL container
./devstack shell postgres

# Open specific shell (bash instead of sh)
./devstack shell vault --shell bash

# Common shell commands after entering:
# PostgreSQL: psql -U $POSTGRES_USER -d $POSTGRES_DB
# Redis: redis-cli -a $REDIS_PASSWORD
# MongoDB: mongosh -u $MONGODB_USER -p $MONGODB_PASSWORD
```

**Options:**
- `--shell, -s`: Shell to use (default: sh, can use bash if available)

### profiles

List all available service profiles with details.

```bash
# Show all profiles
./devstack profiles
```

**Output includes:**
- Profile name
- Number of services
- RAM estimate
- Description and use case

### ip

Display Colima VM IP address.

```bash
# Get VM IP address
./devstack ip
```

**Use cases:**
- Accessing services from libvirt VMs
- Configuring network clients
- Debugging network issues

### redis-cluster-init

Initialize Redis cluster (required for standard/full profiles).

```bash
# Initialize 3-node Redis cluster
./devstack redis-cluster-init
```

**When to use:**
- After first start with `--profile standard`
- After first start with `--profile full`
- NOT needed for `--profile minimal` (single Redis node)

**What it does:**
- Creates 3-node Redis cluster
- Distributes 16,384 slots across nodes
- Verifies cluster health

**Verify cluster:**
```bash
# Connect to cluster
redis-cli -c -h localhost -p 6379

# Check cluster nodes
redis-cli -h localhost -p 6379 cluster nodes

# Check cluster info
redis-cli -h localhost -p 6379 cluster info
```

## Profile Comparison

| Profile | Services | RAM | Start Command |
|---------|----------|-----|---------------|
| **minimal** | 5 | 2GB | `./devstack start --profile minimal` |
| **standard** | 10 | 4GB | `./devstack start --profile standard` |
| **full** | 18 | 6GB | `./devstack start --profile full` |
| **reference** | +5 | +1GB | `./devstack start --profile standard --profile reference` |

### Minimal Profile (5 services)

**Services:** vault, postgres, pgbouncer, forgejo, redis-1 (standalone)

**Use Cases:**
- Git repository hosting
- Simple CRUD application development
- Learning the platform
- CI/CD pipelines (lightweight)

### Standard Profile (10 services)

**Services:** All minimal + mysql, mongodb, redis-2, redis-3, rabbitmq

**Use Cases:**
- Multi-database application development
- Redis cluster testing (**YOUR PRIMARY USE CASE**)
- Message queue integration
- Full-featured development

### Full Profile (18 services)

**Services:** All standard + prometheus, grafana, loki, vector, cadvisor, exporters

**Use Cases:**
- Performance testing
- Production troubleshooting simulation
- Observability pattern learning
- Load testing with metrics

### Reference Profile (5 services)

**Services:** reference-api, api-first, golang-api, nodejs-api, rust-api

**Use Cases:**
- Learning API design patterns
- Comparing language implementations
- Testing integration patterns

**Note:** Must combine with standard or full profile.

## Environment Variables

The script respects these environment variables:

### Colima Configuration

```bash
# Colima profile name
export COLIMA_PROFILE=default

# Colima CPU cores
export COLIMA_CPU=4

# Colima memory in GB
export COLIMA_MEMORY=8

# Colima disk size in GB
export COLIMA_DISK=60
```

### Profile Environment Loading

The script automatically loads environment variables from:
1. Shell environment (highest priority)
2. `configs/profiles/<profile>.env`
3. Root `.env` file
4. docker-compose.yml defaults (lowest priority)

## Comparison: Python vs Bash Script

| Feature | Python Script | Bash Script |
|---------|--------------|-------------|
| Profile Support | ✅ Native | ❌ No |
| Colored Output | ✅ Rich library | ⚠️ Basic ANSI |
| Error Handling | ✅ Excellent | ⚠️ Basic |
| Maintainability | ✅ High | ⚠️ Medium (1622 lines) |
| Dependencies | Python + 4 packages | Bash + system tools |
| Cross-platform | ✅ Yes | ⚠️ macOS/Linux only |
| Progress Indicators | ✅ Spinners | ❌ No |
| Tables | ✅ Formatted | ⚠️ Plain text |

### Migration Strategy

**Current State:**
- Bash script (`devstack`) - 1,622 lines
- Python script (`devstack`) - 850 lines

**Recommended Approach:**
1. **Phase 1:** Use Python script for profile management
   ```bash
   ./devstack start --profile standard
   ```

2. **Phase 2:** Use Python script for common operations
   ```bash
   ./devstack status
   ./devstack health
   ./devstack logs <service>
   ```

3. **Phase 3:** Use bash script for advanced operations (until implemented in Python)
   ```bash
   ./devstack vault-bootstrap
   ./devstack backup
   ./devstack forgejo-init
   ```

4. **Future:** Complete Python implementation with all bash script features

## Troubleshooting

### Dependencies Not Found

**Problem:** `ModuleNotFoundError: No module named 'click'`

**Solution:**
```bash
# Install dependencies
pip3 install --user click rich PyYAML python-dotenv

# Or use virtual environment
uv venv
uv pip install -r scripts/requirements.txt
# Wrapper script automatically uses the venv
```

### Script Not Executable

**Problem:** `Permission denied: ./devstack`

**Solution:**
```bash
chmod +x devstack
```

### Colima Not Found

**Problem:** `Command not found: colima`

**Solution:**
```bash
# Install Colima
brew install colima
```

### Profile Not Loading

**Problem:** Environment variables from profile not taking effect

**Solution:**
```bash
# Check if profile .env file exists
ls -la configs/profiles/standard.env

# Manually load to debug
set -a
source configs/profiles/standard.env
set +a
env | grep REDIS
```

### Redis Cluster Init Fails

**Problem:** `Error initializing Redis cluster`

**Solution:**
```bash
# Check redis containers are running
docker ps | grep redis

# Check if already initialized
redis-cli -h localhost -p 6379 cluster nodes

# Reset if needed (WARNING: destroys data)
docker compose down
docker volume rm devstack-core_redis_1_data devstack-core_redis_2_data devstack-core_redis_3_data
./devstack start --profile standard
./devstack redis-cluster-init
```

## Advanced Usage

### Custom Profiles

Create a custom profile environment file:

```bash
# Create custom profile
cat > configs/profiles/my-custom.env << 'EOF'
# My custom settings
REDIS_MAX_MEMORY=1024mb
POSTGRES_MAX_CONNECTIONS=200
ENABLE_METRICS=true
EOF

# Use custom environment
set -a
source configs/profiles/my-custom.env
set +a
docker compose --profile standard up -d
```

### Scripting and Automation

Use the Python script in automation:

```bash
#!/bin/bash
# CI/CD example

# Start minimal profile for testing
./devstack start --profile minimal

# Wait for services to be healthy
sleep 30
./devstack health

# Run tests
pytest tests/

# Stop services
./devstack stop
```

### Monitoring

```bash
# Watch status in real-time
watch -n 5 './devstack status'

# Continuous health monitoring
while true; do
  ./devstack health
  sleep 60
done
```

## Future Enhancements

Planned features for future versions:

- [ ] Vault operations (vault-init, vault-bootstrap, vault-unseal)
- [ ] Backup and restore commands
- [ ] Forgejo initialization
- [ ] Service restart command
- [ ] Reset command (destroy and recreate)
- [ ] Performance metrics display
- [ ] Service dependency visualization
- [ ] Configuration validation
- [ ] Automated health check scheduling
- [ ] Profile switching helper

## Contributing

To add new commands to the Python script:

1. Add a new function decorated with `@cli.command()`
2. Use Rich library for beautiful output
3. Handle errors gracefully
4. Add comprehensive documentation
5. Test with all profiles

Example:
```python
@cli.command()
@click.option("--force", is_flag=True, help="Force operation")
def mycommand(force: bool):
    """
    Description of my command.

    Examples:
      ./devstack mycommand
      ./devstack mycommand --force
    """
    console.print("[cyan]Running my command...[/cyan]")
    # Implementation here
```

## Support

For help with the Python management script:
1. Check this documentation
2. Run `./devstack --help`
3. Check command-specific help: `./devstack start --help`
4. Review docs/SERVICE_PROFILES.md
5. Open an issue on GitHub

## License

MIT License - See LICENSE file for details
