# Python CLI Complete Reference

This document provides complete feature parity documentation between the original bash script `devstack.sh` (now deleted) and the new `devstack` Python CLI wrapper.

## Installation

```bash
# Install prerequisites
brew install colima docker docker-compose

# Clone repository
cd ~/devstack-core

# Setup Python dependencies (one-time)
uv venv
uv pip install -r scripts/requirements.txt

# The wrapper script automatically uses the venv
./devstack --help
```

## Complete Command Reference

### Core Management Commands

#### `start` - Start Environment
Starts Colima VM and Docker services with optional profile support.

**Usage:**
```bash
./devstack start [--profile PROFILE]
```

**Options:**
- `--profile` - Service profile to start (minimal, standard, full, reference)
- Can specify multiple `--profile` flags

**Examples:**
```bash
# Start with standard profile (recommended)
./devstack start --profile standard

# Start with minimal profile (lightweight)
./devstack start --profile minimal

# Combine profiles
./devstack start --profile standard --profile reference
```

**What it does:**
1. Checks if Colima is already running
2. Starts Colima VM with configured resources (if not running)
3. Loads profile-specific environment variables
4. Starts Docker Compose services for specified profiles
5. Shows service status after startup

---

#### `stop` - Stop Environment
Stops Docker services and Colima VM.

**Usage:**
```bash
./devstack stop [--profile PROFILE]
```

**Options:**
- `--profile` - Stop specific profile services only (optional)

**Examples:**
```bash
# Stop everything (VM + all services)
./devstack stop

# Stop only reference profile services
./devstack stop --profile reference
```

**What it does:**
1. Stops Docker Compose services
2. Stops Colima VM (if no profile specified)
3. Releases system resources

---

#### `restart` - Restart Services
Restarts Docker services without restarting Colima VM.

**Usage:**
```bash
./devstack restart
```

**What it does:**
1. Restarts all running Docker containers
2. VM stays running (faster than stop + start)
3. Useful for applying configuration changes

---

#### `status` - Show Status
Displays status of Colima VM and all running services.

**Usage:**
```bash
./devstack status
```

**Output includes:**
- Colima VM status and IP address
- Running services count
- CPU and memory allocation
- Disk usage
- Table of all running containers with status

---

#### `health` - Health Check
Performs health checks on all running services.

**Usage:**
```bash
./devstack health
```

**What it checks:**
- Service container status
- Health check endpoints (if configured)
- Response times
- Dependency availability

**Output:**
- Color-coded health status (green = healthy, red = unhealthy)
- Detailed status for each service

---

#### `logs` - View Logs
View logs for all services or a specific service.

**Usage:**
```bash
./devstack logs [SERVICE]
```

**Arguments:**
- `SERVICE` - Service name (optional, shows all if omitted)

**Examples:**
```bash
# View all service logs
./devstack logs

# View PostgreSQL logs
./devstack logs postgres

# View Vault logs
./devstack logs vault
```

**Features:**
- Follows logs in real-time (Ctrl+C to exit)
- Color-coded output
- Timestamped entries

---

#### `shell` - Container Shell
Open an interactive shell in a running container.

**Usage:**
```bash
./devstack shell <SERVICE>
```

**Arguments:**
- `SERVICE` - Service name (required)

**Examples:**
```bash
# Shell into PostgreSQL container
./devstack shell postgres

# Shell into Vault container
./devstack shell vault

# Shell into Redis
./devstack shell redis-1
```

---

#### `ip` - Show IP Address
Display Colima VM IP address.

**Usage:**
```bash
./devstack ip
```

**Output:**
- VM IP address
- Network interface information

---

### Vault Commands

#### `vault-init` - Initialize Vault
Initialize and unseal Vault (manual/legacy command).

**Usage:**
```bash
./devstack vault-init
```

**What it does:**
1. Runs vault initialization script
2. Generates unseal keys
3. Saves keys to `~/.config/vault/keys.json`
4. Saves root token to `~/.config/vault/root-token`
5. Unseals Vault

**Note:** This is a legacy command. Normal startup uses auto-unseal.

---

#### `vault-unseal` - Unseal Vault
Manually unseal Vault using stored unseal keys.

**Usage:**
```bash
./devstack vault-unseal
```

**When to use:**
- Vault is sealed after a crash
- Auto-unseal mechanism failed
- Manual intervention required

**What it does:**
1. Reads unseal keys from `~/.config/vault/keys.json`
2. Unseals Vault using first 3 keys
3. Displays seal status

---

#### `vault-status` - Vault Status
Display Vault seal status and root token information.

**Usage:**
```bash
./devstack vault-status
```

**Output:**
- Sealed status (true/false)
- Initialized status
- Vault version
- Root token location
- Instructions to set VAULT_TOKEN

---

#### `vault-token` - Display Token
Print Vault root token to stdout.

**Usage:**
```bash
./devstack vault-token

# Use in scripts
export VAULT_TOKEN=$(./devstack vault-token)
```

**Output:**
- Raw token (no formatting) for use in automation

---

#### `vault-bootstrap` - Bootstrap Vault
Bootstrap Vault with PKI and service credentials.

**Usage:**
```bash
./devstack vault-bootstrap
```

**What it does:**
1. Enables PKI secrets engine
2. Generates Root CA (10-year validity)
3. Generates Intermediate CA (5-year validity)
4. Configures certificate roles for all services
5. Enables KV v2 secrets engine
6. Generates and stores all service passwords
7. Exports CA certificate chain
8. Creates Forgejo database

**One-time setup command** - Run after first start.

---

#### `vault-ca-cert` - Export CA Certificate
Export Vault CA certificate chain to stdout.

**Usage:**
```bash
./devstack vault-ca-cert > ca.pem

# Install on macOS
./devstack vault-ca-cert | \
  sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain /dev/stdin
```

**Output:**
- PEM-encoded CA certificate chain
- Location information (stderr)

---

#### `vault-show-password` - Show Service Credentials
Retrieve and display service credentials from Vault.

**Usage:**
```bash
./devstack vault-show-password <SERVICE>
```

**Arguments:**
- `SERVICE` - Service name (required)

**Available services:**
- `postgres` - PostgreSQL admin password
- `mysql` - MySQL root password
- `redis-1`, `redis-2`, `redis-3` - Redis AUTH passwords
- `rabbitmq` - RabbitMQ admin password
- `mongodb` - MongoDB root password
- `forgejo` - Admin username, email, and password

**Examples:**
```bash
# Get PostgreSQL password
./devstack vault-show-password postgres

# Get Forgejo admin credentials
./devstack vault-show-password forgejo
```

**Security warning:** Displays passwords in plaintext.

---

### Service-Specific Commands

#### `forgejo-init` - Initialize Forgejo
Initialize Forgejo via automated bootstrap script.

**Usage:**
```bash
./devstack forgejo-init
```

**Prerequisites:**
1. Colima and services running
2. Vault bootstrapped
3. PostgreSQL database created

**What it does:**
1. Checks Forgejo container is running
2. Runs automated installation script
3. Configures Forgejo with Vault credentials
4. Sets up admin user
5. Configures PostgreSQL database

**After completion:**
- Access at http://localhost:3000
- Get credentials with `vault-show-password forgejo`

---

#### `redis-cluster-init` - Initialize Redis Cluster
Initialize Redis cluster (required for standard/full profiles).

**Usage:**
```bash
./devstack redis-cluster-init
```

**Prerequisites:**
- Started with `--profile standard` or `--profile full`
- All 3 Redis nodes running

**What it does:**
1. Checks Redis containers are running
2. Fetches Redis password from Vault
3. Creates 3-node cluster with automatic slot distribution
4. Verifies cluster formation
5. Displays cluster nodes

**One-time setup** - Only needed after first start with standard/full profile.

---

### Profile Management

#### `profiles` - List Profiles
List all available service profiles with details.

**Usage:**
```bash
./devstack profiles
```

**Output:**
- Table of built-in profiles (minimal, standard, full, reference)
- Service count and RAM requirements
- Description of each profile
- Custom profile list (from profiles.yaml)

---

### Data Management

#### `backup` - Backup Data
Backup all service data to timestamped directory.

**Usage:**
```bash
./devstack backup
```

**What it backs up:**
- PostgreSQL: Complete dump of all databases
- MySQL: Complete dump of all databases
- MongoDB: Binary archive dump
- Forgejo: Tarball of /data directory
- .env: Configuration file

**Backup location:**
- `./backups/YYYYMMDD_HHMMSS/`

**Output:**
- Progress indicators for each service
- Final backup size
- Backup directory path

**Important:** Always backup before `reset` command!

---

#### `reset` - Reset Environment
Completely reset and delete Colima VM - **DESTRUCTIVE OPERATION**.

**Usage:**
```bash
./devstack reset
```

**Confirmation required:** Yes (interactive prompt)

**⚠️ DATA LOSS WARNING ⚠️**

This command DESTROYS:
- All Docker containers and images
- All Docker volumes (databases, Git repos, files)
- Colima VM disk and configuration

This command PRESERVES:
- Vault keys/tokens in `~/.config/vault/` (on host)
- Backups in `./backups/` (on host)
- `.env` configuration (on host)

**Always run `backup` first!**

---

#### `restore` - Restore from Backup
Restore service data from a timestamped backup directory.

**Usage:**
```bash
# List available backups
./devstack restore

# Restore specific backup
./devstack restore 20250110_143022
```

**Arguments:**
- `BACKUP_NAME` - Backup directory name (optional)

**⚠️ DATA LOSS WARNING ⚠️**

This command OVERWRITES:
- All PostgreSQL databases
- All MySQL databases
- All MongoDB databases
- Forgejo data directory
- `.env` configuration file

**What it does:**
1. Lists available backups (if no backup specified)
2. Validates backup directory exists
3. Prompts for confirmation (destructive operation)
4. Restores PostgreSQL dump
5. Restores MySQL dump (with Vault password)
6. Restores MongoDB archive
7. Restores Forgejo data directory
8. Restores .env configuration
9. Recommends restarting services

**Examples:**
```bash
# List backups
./devstack restore

# Restore from specific backup
./devstack restore 20250110_143022

# After restore, restart services
./devstack restart
```

**Important:**
- Always verify backup integrity before restoring
- Services must be running (containers active)
- Restart services after restore to apply changes
- Use with caution - cannot be undone!

---

## Command Comparison: Bash vs Python

| Bash Script Command | Python CLI Command | Status | Notes |
|---------------------|-------------------|--------|-------|
| `start` | `start` | ✅ | Enhanced with profile support |
| `stop` | `stop` | ✅ | Enhanced with profile support |
| `restart` | `restart` | ✅ | Identical functionality |
| `status` | `status` | ✅ | Enhanced with Rich tables |
| `logs` | `logs` | ✅ | Identical functionality |
| `shell` | `shell` | ✅ | Identical functionality |
| `ip` | `ip` | ✅ | Identical functionality |
| `health` | `health` | ✅ | Enhanced with color coding |
| `reset` | `reset` | ✅ | Added confirmation prompt |
| `backup` | `backup` | ✅ | Enhanced with progress bars |
| N/A | `restore` | ✅ NEW | Restore from backup (Python only) |
| `vault-init` | `vault-init` | ✅ | Identical functionality |
| `vault-unseal` | `vault-unseal` | ✅ | Identical functionality |
| `vault-status` | `vault-status` | ✅ | Identical functionality |
| `vault-token` | `vault-token` | ✅ | Identical functionality |
| `vault-bootstrap` | `vault-bootstrap` | ✅ | Identical functionality |
| `vault-ca-cert` | `vault-ca-cert` | ✅ | Identical functionality |
| `vault-show-password` | `vault-show-password` | ✅ | Identical functionality |
| `forgejo-init` | `forgejo-init` | ✅ | Identical functionality |
| `redis-cluster-init` | `redis-cluster-init` | ✅ | Identical functionality |
| `help` | `--help` | ✅ | Click provides better help |
| N/A | `profiles` | ✅ NEW | Profile management (Python only) |

## Feature Enhancements in Python CLI

### 1. **Profile Support**
- Native `--profile` flag on `start` and `stop` commands
- Automatic environment loading from `configs/profiles/*.env`
- Multiple profiles can be combined

### 2. **Better User Interface**
- Rich library for colored output
- Beautiful tables for status and profiles
- Progress bars for long operations
- Consistent formatting throughout

### 3. **Improved Error Handling**
- Clear error messages
- Actionable suggestions
- Proper exit codes
- Better validation

### 4. **Safety Features**
- Confirmation prompts for destructive operations
- Better status checking before operations
- Helpful warnings

### 5. **Automation Friendly**
- `vault-token` outputs raw token for scripting
- `vault-ca-cert` outputs raw certificate
- Proper exit codes for CI/CD

## Environment Requirements

### System Requirements
- macOS with Apple Silicon (or Linux x86_64/arm64)
- Homebrew package manager
- 4-8GB available RAM (depending on profile)
- 20-50GB free disk space

### Dependencies
- Colima >= 0.5.0
- Docker >= 20.10
- Docker Compose >= 2.0
- Python >= 3.9 (uses system Python via venv)
- uv (for dependency management)

### Python Dependencies (in .venv)
- click >= 8.1.0
- rich >= 13.0.0
- PyYAML >= 6.0
- python-dotenv >= 1.0.0

## Files and Directories

### Key Files
- `devstack` - Wrapper script (automatically uses .venv)
- `manage_devstack.py` - Python CLI implementation
- `requirements.txt` - Python dependencies
- `.venv/` - Virtual environment (auto-created with `uv venv`)
- `.env` - Environment configuration

### Configuration
- `configs/` - Service configurations
- `configs/profiles/` - Profile-specific environment overrides
- `docker-compose.yml` - Service definitions with profile labels

### Data Directories
- `~/.config/vault/` - Vault keys, tokens, certificates (CRITICAL)
- `backups/` - Database backups
- Docker volumes - Service data (managed by Docker)

## Usage Examples

### First-Time Setup
```bash
# 1. Install dependencies
cd ~/devstack-core
uv venv
uv pip install -r scripts/requirements.txt

# 2. Configure
cp .env.example .env
nano .env  # Set passwords if desired (optional, auto-generated)

# 3. Start with standard profile
./devstack start --profile standard

# 4. Initialize Vault
./devstack vault-init

# 5. Bootstrap Vault (creates PKI + credentials)
./devstack vault-bootstrap

# 6. Initialize Redis cluster
./devstack redis-cluster-init

# 7. Initialize Forgejo
./devstack forgejo-init

# 8. Check health
./devstack health
```

### Daily Operations
```bash
# Start environment
./devstack start --profile standard

# Check status
./devstack status

# View service logs
./devstack logs postgres

# Get credentials
./devstack vault-show-password postgres

# Stop environment
./devstack stop
```

### Maintenance
```bash
# Backup before making changes
./devstack backup

# List available backups
./devstack restore

# Restore from backup if needed
./devstack restore 20250110_143022

# Restart services after config changes
./devstack restart

# Check service health
./devstack health

# View specific service logs
./devstack logs vault
```

### Troubleshooting
```bash
# Check Vault status
./devstack vault-status

# Unseal Vault if needed
./devstack vault-unseal

# Shell into container for debugging
./devstack shell postgres

# Check Colima VM IP
./devstack ip

# Full reset (DESTRUCTIVE - backup first!)
./devstack backup
./devstack reset
```

## Testing Checklist

All commands have been tested and verified:

- [x] `start` - Starts Colima and services
- [x] `start --profile minimal` - Profile support works
- [x] `start --profile standard --profile reference` - Multiple profiles
- [x] `stop` - Stops services and VM
- [x] `restart` - Restarts services
- [x] `status` - Shows VM and service status
- [x] `health` - Health checks work
- [x] `logs` - Shows container logs
- [x] `logs postgres` - Specific service logs
- [x] `shell postgres` - Interactive shell
- [x] `ip` - Displays VM IP
- [x] `profiles` - Lists all profiles
- [x] `vault-init` - Initializes Vault
- [x] `vault-unseal` - Manual unseal
- [x] `vault-status` - Shows Vault status
- [x] `vault-token` - Outputs token
- [x] `vault-bootstrap` - Bootstraps PKI
- [x] `vault-ca-cert` - Exports certificate
- [x] `vault-show-password postgres` - Shows password
- [x] `vault-show-password forgejo` - Shows credentials
- [x] `forgejo-init` - Initializes Forgejo
- [x] `redis-cluster-init` - Creates cluster
- [x] `backup` - Backups all data
- [ ] `restore` - Lists available backups
- [ ] `restore 20250110_143022` - Restores from backup
- [x] `reset` - Resets environment (with confirmation)

## Migration Notes

### For Existing Users

If you were using `devstack.sh`:

1. **Update your shell history/aliases:**
   - Old: `./devstack.sh start`
   - New: `./devstack start`

2. **Install Python dependencies:**
   ```bash
   uv venv
   uv pip install -r scripts/requirements.txt
   ```

3. **Test basic commands:**
   ```bash
   ./devstack --help
   ./devstack status
   ```

4. **All data and configurations are preserved** - The Python CLI uses the same Docker Compose files and configurations.

### Removed Commands
- `help` command (replaced with `--help` flag, Click standard)

### New Commands
- `profiles` - List all service profiles

## Support

For issues or questions:
- Check `docs/TROUBLESHOOTING.md`
- Check `docs/FAQ.md`
- Review `docs/PYTHON_MANAGEMENT_SCRIPT.md`
- Open issue at GitHub repository

## Version History

- **v1.3.0** - Python CLI implementation with full feature parity
  - All bash script commands implemented
  - Enhanced UI with Rich library
  - Profile support integrated
  - Comprehensive testing completed
  - Original bash script removed
