# Complete Installation Guide

## Table of Contents

  - [Step 1: Pre-Flight Checks](#step-1-pre-flight-checks)
  - [Step 2: Install Required Software](#step-2-install-required-software)
  - [Step 3: Clone the Repository](#step-3-clone-the-repository)
  - [Step 4: Configure Environment](#step-4-configure-environment)
  - [Step 4.5: Choose Your Service Profile](#step-45-choose-your-service-profile-optional-but-recommended)
  - [Step 5: Start Colima and Services](#step-5-start-colima-and-services)
    - [Option A: Python Script (Recommended)](#option-a-start-with-python-script-recommended)
    - [Option B: Bash Script (Traditional)](#option-b-start-with-bash-script-traditional)
  - [Step 6: Initialize Vault](#step-6-initialize-vault)
  - [Step 7: Bootstrap Vault and Generate Credentials](#step-7-bootstrap-vault-and-generate-credentials)
  - [Step 7.5: Initialize Redis Cluster (For Standard/Full Profiles Only)](#step-75-initialize-redis-cluster-for-standardfull-profiles-only)
  - [Step 8: Verify Everything Works](#step-8-verify-everything-works)
  - [Step 9: Access Your Services](#step-9-access-your-services)
  - [What to Do If Something Goes Wrong](#what-to-do-if-something-goes-wrong)
- [Prerequisites](#prerequisites)
  - [System Requirements](#system-requirements)
  - [Required Software](#required-software)
  - [Understanding Colima](#understanding-colima)
- [Installation](#installation)
  - [First Time Setup](#first-time-setup)
  - [Configuration](#configuration)
  - [Starting Services](#starting-services)

---

> **For Complete Beginners**: This section walks you through the entire installation process from scratch, with detailed explanations, expected outputs, and troubleshooting tips. Estimated time: 30-45 minutes.

**What You'll Accomplish:**
- ✅ Install Colima (lightweight Docker alternative)
- ✅ Choose your service profile (minimal, standard, full, or reference)
- ✅ Set up a complete development infrastructure
- ✅ Configure HashiCorp Vault for secrets management
- ✅ Launch 5-23 services based on your chosen profile
- ✅ Access web UIs and verify everything works

**New in v1.3:** Service Profiles let you start only the services you need. See [SERVICE_PROFILES.md](./SERVICE_PROFILES.md) for complete details.

**Before You Begin:**
- This guide assumes macOS (tested on Apple M Series Processors)
- You'll need at least 16GB RAM and 60GB free disk space
- Basic terminal/command line familiarity is helpful but not required
- The entire process is reversible (you can uninstall everything cleanly)

---

### Step 1: Pre-Flight Checks

**1.1 Check Your System:**

```bash
# Check macOS version (should be 12.0 or later)
sw_vers

# Expected output:
# ProductName:        macOS
# ProductVersion:     14.x.x (or higher)
# BuildVersion:       ...
```

**1.2 Check Available Resources:**

```bash
# Check free disk space (need at least 60GB)
df -h ~

# Expected output:
# Filesystem      Size   Used  Avail Capacity  Mounted on
# /dev/disk3s1   500Gi  100Gi  400Gi    21%    /System/Volumes/Data

# Check RAM (need at least 16GB)
sysctl hw.memsize | awk '{print $2/1073741824" GB"}'

# Expected output: 16 GB (or higher)
```

**What This Means:**
- If you have less than 60GB free, you'll need to free up space before proceeding
- If you have less than 16GB RAM, the system may run slowly or fail to start all services

**1.3 Check if Docker Desktop is Running:**

```bash
# Check if Docker Desktop is running
pgrep -f "Docker Desktop"

# If you see output (process IDs), Docker Desktop is running
# You should stop it to avoid conflicts:
# - Click Docker icon in menu bar → Quit Docker Desktop
```

**Why:** Colima and Docker Desktop can conflict. It's best to use one or the other.

---

### Step 2: Install Required Software

**2.1 Install Homebrew (if not already installed):**

```bash
# Check if Homebrew is installed
which brew

# If you see: /opt/homebrew/bin/brew (or /usr/local/bin/brew)
# → Homebrew is installed, skip to 2.2

# If you see: brew not found
# → Install Homebrew:
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Follow the on-screen instructions
# This may take 5-10 minutes
```

**Expected Output:**
```
==> Installation successful!
==> Next steps:
- Run these commands in your terminal to add Homebrew to your PATH:
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
```

**Action:** Run the commands shown in "Next steps" if prompted.

**2.2 Install Colima, Docker, and Docker Compose:**

```bash
# Install all three tools at once
brew install colima docker docker-compose

# This may take 5-15 minutes depending on your internet speed
```

**Expected Output:**
```
==> Downloading colima...
==> Downloading docker...
==> Downloading docker-compose...
...
==> Installing colima
==> Installing docker
==> Installing docker-compose
🍺  colima was successfully installed!
🍺  docker was successfully installed!
🍺  docker-compose was successfully installed!
```

**2.3 Verify Installation:**

```bash
# Check Colima version
colima version

# Expected output: colima version 0.6.x (or higher)

# Check Docker version
docker --version

# Expected output: Docker version 24.x.x (or higher)

# Check Docker Compose version
docker-compose --version

# Expected output: Docker Compose version 2.x.x (or higher)
```

**What If It Fails?**
- If `colima version` shows "command not found", restart your terminal
- If still not working, run: `brew doctor` to check for issues

**2.4 Optional: Modern Rust-based CLI Tools**

The repository scripts are compatible with modern Rust-based alternatives to traditional Unix tools. These tools are **optional** and provide enhanced performance and features:

```bash
# Optional: Install Rust-based CLI alternatives
brew install ripgrep fd-find bat eza

# ripgrep (rg) - Faster grep alternative
# fd - Faster find alternative
# bat - cat with syntax highlighting
# eza - Modern ls replacement
```

**Important Note:**
- All DevStack Core scripts use standard Unix tools (`/usr/bin/grep`, `awk`, `sed`) explicitly
- Scripts are designed to work regardless of aliases (e.g., if `grep` is aliased to `rg`)
- These Rust tools are **not required** - scripts will work with standard macOS/Linux tools
- If installed, they provide better performance for interactive terminal use

**Compatibility:**
- The link checker (`scripts/check-markdown-links.sh`) explicitly uses `/usr/bin/grep`
- Other scripts that require GNU tool behavior use full paths to avoid alias conflicts
- Your shell can safely alias `grep→rg`, `find→fd`, `ls→eza`, `cat→bat` without affecting scripts

---

### Step 3: Clone the Repository

**3.1 Choose Installation Location:**

```bash
# Navigate to your home directory
cd ~

# Check current location
pwd

# Expected output: /Users/yourusername
```

**3.2 Clone the Repository:**

```bash
# Clone into ~/devstack-core directory
git clone https://github.com/NormB/devstack-core.git ~/devstack-core

# Expected output:
# Cloning into '/Users/yourusername/devstack-core'...
# remote: Enumerating objects: ...
# Receiving objects: 100% (...), done.
```

**3.3 Navigate to Project Directory:**

```bash
# Change into the project directory
cd ~/devstack-core

# Verify you're in the right place
ls -la

# Expected output: You should see files like:
# .env.example
# docker-compose.yml
# manage-devstack
# README.md
# configs/
# scripts/
```

**What If It Fails?**
- If `git clone` fails with "command not found", install git: `brew install git`
- If clone fails with permission errors, check your GitHub access

---

### Step 4: Configure Environment

**4.1 Create Your Environment File:**

```bash
# Copy the example file to create your own .env
cp .env.example .env

# Verify it was created
ls -la .env

# Expected output:
# -rw-r--r--  1 yourusername  staff  xxxxx Nov 23 10:00 .env
```

**What This Does:** The `.env` file stores configuration settings. It's not tracked by git (your passwords stay private).

**4.2 Make Management Script Executable:**

```bash
# Add execute permissions
chmod +x manage-devstack

# Verify permissions
ls -l manage-devstack

# Expected output (note the 'x'):
# -rwxr-xr-x  1 yourusername  staff  xxxxx Nov 23 10:00 manage-devstack
```

**4.3 Review Configuration (Optional but Recommended):**

```bash
# View the .env file
cat .env | head -30

# You'll see settings like:
# VAULT_ADDR=http://vault:8200
# VAULT_TOKEN=
# POSTGRES_PASSWORD=
```

**Important:** You'll notice many password fields are empty. This is intentional! They'll be auto-generated by Vault in Step 7.

---

### Step 4.5: Choose Your Service Profile (Optional but Recommended)

**What are Service Profiles?** DevStack Core offers flexible profiles that let you start only the services you need. This saves resources and speeds up startup times.

**Available Profiles:**

| Profile | Services | RAM | Best For |
|---------|----------|-----|----------|
| **minimal** | 5 services | 2GB | Git hosting + basic development (single Redis) |
| **standard** | 10 services | 4GB | **Full development stack + Redis cluster (RECOMMENDED)** |
| **full** | 18 services | 6GB | Complete suite + observability (Prometheus, Grafana, Loki) |
| **reference** | +5 services | +1GB | Educational API examples (combine with standard/full) |

**Which Profile Should You Choose?**

- **Choose `minimal`** if you:
  - Only need Git hosting (Forgejo) and basic database
  - Have limited RAM (< 8GB)
  - Want fastest startup time

- **Choose `standard`** if you:
  - Need Redis cluster for development (3 nodes)
  - Want all databases (PostgreSQL, MySQL, MongoDB)
  - Need RabbitMQ messaging
  - **This is the recommended profile for most developers**

- **Choose `full`** if you:
  - Need metrics and monitoring (Prometheus, Grafana)
  - Want log aggregation (Loki)
  - Are doing performance testing
  - Have 16GB+ RAM

**4.5.1 Install Python Dependencies (for Profile Support):**

```bash
# Install Python management script dependencies
uv venv
uv pip install -r scripts/requirements.txt

# Expected output:
# Successfully installed click-8.1.7 rich-13.7.0 PyYAML-6.0.1 python-dotenv-1.0.0
```

**Note:** The wrapper script (`devstack`) automatically uses the virtual environment. No need to activate it manually!

**4.5.2 Make Python Script Executable:**

```bash
# Add execute permissions
chmod +x manage-devstack

# Verify permissions
ls -l manage-devstack

# Expected output (note the 'x'):
# -rwxr-xr-x  1 yourusername  staff  xxxxx Nov 23 10:00 manage-devstack
```

**Skip This Section If:** You want to use the traditional bash script and start all services. Continue to Step 5.

---

### Step 5: Start Colima and Services

You can now start services using either:
- **Python script** (recommended, with profile support)
- **Bash script** (traditional, starts all services)

#### Option A: Start with Python Script (Recommended)

**5.1 Start with Your Chosen Profile:**

```bash
# Start with standard profile (recommended for most developers)
./devstack start --profile standard

# OR start with minimal profile (lightweight)
# ./devstack start --profile minimal

# OR start with full profile (includes observability)
# ./devstack start --profile full

# OR combine profiles (standard + reference apps)
# ./devstack start --profile standard --profile reference
```

**Expected Output (takes 2-3 minutes on first run):**

```
═══ DevStack Core - Start Services ═══

Profile Configuration
  Selected Profiles: standard
  Services to Start: 10

Step 1/3: Check Colima Status
  ✓ Colima is not running

Step 2/3: Start Colima VM
  INFO[0000] starting colima
  INFO[0000] runtime: docker
  INFO[0001] creating and starting colima VM...
  INFO[0002] provisioning docker runtime
  INFO[0150] starting ... context=docker
  INFO[0155] done
  ✓ Colima started successfully
     Profile: default
     Colima IP: 192.168.106.2

Step 3/3: Start Docker Services
  [+] Running 10/10
   ✔ Container dev-vault             Started
   ✔ Container dev-postgres          Started
   ✔ Container dev-pgbouncer         Started
   ✔ Container dev-mysql             Started
   ✔ Container dev-mongodb           Started
   ✔ Container dev-redis-1           Started
   ✔ Container dev-redis-2           Started
   ✔ Container dev-redis-3           Started
   ✔ Container dev-rabbitmq          Started
   ✔ Container dev-forgejo           Started

Services Started Successfully!

Next Steps:
  1. Wait 2-3 minutes for services to become healthy
  2. Check health: ./devstack health
  3. Initialize Vault: ./devstack vault-init
  4. Bootstrap Vault: ./devstack vault-bootstrap
  5. Initialize Redis cluster: ./devstack redis-cluster-init
```

**5.2 Check Service Health:**

```bash
# Check health status of all running services
./devstack health

# Expected output:
# ┏━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━┳━━━━━━━━━━━━━━━━┓
# ┃ Service              ┃ Status  ┃ Health         ┃
# ┡━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━╇━━━━━━━━━━━━━━━━┩
# │ dev-vault            │ running │ healthy        │
# │ dev-postgres         │ running │ healthy        │
# │ dev-pgbouncer        │ running │ healthy        │
# │ dev-redis-1          │ running │ healthy        │
# ...
```

**What's Happening:**
1. **Colima VM Creation** (0-60 seconds): Creates a Linux virtual machine
2. **Docker Installation** (60-150 seconds): Installs Docker inside the VM
3. **Container Start** (150-180 seconds): Launches your selected services
4. **Health Checks** (180+ seconds): Services report as "healthy" once ready

#### Option B: Start with Bash Script (Traditional)

**5.1 Start Colima VM:**

```bash
# Start Colima with the management script
./devstack start
```

**Expected Output (this takes 2-3 minutes on first run):**

```
============================================
  DevStack Core - Management Script
============================================

[✓] Checking environment file...
[✓] Environment file found: .env

[*] Starting Colima...
INFO[0000] starting colima
INFO[0000] runtime: docker
INFO[0001] creating and starting colima VM...
INFO[0002] provisioning docker runtime
INFO[0150] starting ... context=docker
INFO[0155] done

[✓] Colima started successfully
    Profile: default
    Colima IP: 192.168.106.2

[*] Starting Docker services...
[+] Running 13/13
 ✔ Container dev-postgres          Started
 ✔ Container dev-mysql             Started
 ✔ Container dev-redis-1           Started
 ✔ Container dev-redis-2           Started
 ✔ Container dev-redis-3           Started
 ✔ Container dev-rabbitmq          Started
 ✔ Container dev-mongodb           Started
 ✔ Container dev-vault             Started
 ✔ Container dev-forgejo           Started
 ✔ Container dev-prometheus        Started
 ✔ Container dev-grafana           Started
 ✔ Container dev-loki              Started
 ✔ Container dev-reference-api     Started

[✓] All services started

[*] Service Status:
NAME                    STATUS          HEALTH
dev-postgres            Up 30 seconds   starting (0/1)
dev-vault               Up 28 seconds   starting (0/1)
...

[!] Note: Vault needs to be initialized on first run
    Run: ./devstack vault-init
```

**What's Happening:**
1. **Colima VM Creation** (0-60 seconds): Creates a Linux virtual machine
2. **Docker Installation** (60-150 seconds): Installs Docker inside the VM
3. **Container Start** (150-180 seconds): Launches all 12+ services
4. **Health Checks** (180+ seconds): Services report as "healthy" once ready

**What If It Fails?**

```bash
# If you see "cannot connect to Docker daemon":
colima status
# If stopped, run: colima start

# If you see "port already in use":
lsof -i :5432  # Check what's using the port
# Stop that process or change the port in docker-compose.yml

# If Colima fails to start:
# Check logs: colima logs
# Try stopping and restarting: colima stop && colima start
```

**5.2 Wait for Services to Become Healthy:**

```bash
# Check status every 30 seconds
watch -n 30 'docker compose ps'

# Wait until HEALTH column shows "healthy" for all services
# This typically takes 2-3 minutes

# Press Ctrl+C to exit watch command
```

**Expected Final State:**
```
NAME                    STATUS          HEALTH
dev-postgres            Up 2 minutes    healthy
dev-mysql               Up 2 minutes    healthy
dev-redis-1             Up 2 minutes    healthy
dev-vault               Up 2 minutes    healthy (will show "unhealthy" until initialized)
dev-forgejo             Up 2 minutes    healthy
...
```

**Note:** Vault will show as "unhealthy" until initialized in Step 6. This is normal!

---

### Step 6: Initialize Vault

**What is Vault?** HashiCorp Vault securely stores passwords, API keys, and certificates. We'll initialize it now.

**6.1 Initialize Vault:**

```bash
# Run the initialization script
./devstack vault-init
```

**Expected Output:**

```
============================================
  Initializing HashiCorp Vault
============================================

[*] Checking Vault status...
[!] Vault is not initialized. Initializing now...

[*] Initializing Vault with 5 key shares and threshold of 3...

Unseal Key 1: AbCdEfGhIjKlMnOpQrStUvWxYz0123456789AbCdEfGh==
Unseal Key 2: BcDeFgHiJkLmNoPqRsTuVwXyZ1234567890BcDeFgHi==
Unseal Key 3: CdEfGhIjKlMnOpQrStUvWxYz234567890CdEfGhIjK==
Unseal Key 4: DeFgHiJkLmNoPqRsTuVwXyZ34567890DeFgHiJkLmNo==
Unseal Key 5: EfGhIjKlMnOpQrStUvWxYz4567890EfGhIjKlMnOpQr==

Initial Root Token: hvs.CAESIAbCdEfGhIjKlMnOpQrStUvWxYz

[*] Saving Vault keys and root token to ~/.config/vault/
[✓] Keys saved to: /Users/yourusername/.config/vault/keys.json
[✓] Root token saved to: /Users/yourusername/.config/vault/root-token

[*] Auto-unsealing Vault...
[✓] Vault unsealed successfully

[*] Root token saved to: /Users/yourusername/.config/vault/root-token

[!] IMPORTANT: Backup your unseal keys!
    Location: ~/.config/vault/keys.json
    These keys CANNOT be recovered if lost!

[✓] Vault initialization complete
```

**CRITICAL: Save Your Unseal Keys!**

```bash
# Backup your Vault keys to a safe location
# Option 1: Copy to USB drive
cp ~/.config/vault/keys.json /Volumes/YOUR_USB_DRIVE/vault-backup/

# Option 2: Print them out
cat ~/.config/vault/keys.json

# Option 3: Store in password manager (recommended)
# Manually copy the contents to your password manager
```

**Why This Matters:**
- Without these keys, you CANNOT access Vault if it seals (locks)
- You need 3 of 5 keys to unseal Vault
- The root token is like a master password
- If you lose both, all passwords in Vault are permanently inaccessible

**6.2 Update Your .env File:**

```bash
# Copy the root token to your .env file
echo "VAULT_TOKEN=$(cat ~/.config/vault/root-token)" >> .env

# Verify it was added
tail -5 .env

# Expected output (at the end of file):
# VAULT_TOKEN=hvs.CAESIAbCdEfGhIjKlMnOpQrStUvWxYz
```

**What This Does:** Sets the Vault token so scripts can authenticate with Vault.

**6.3 Verify Vault is Working:**

```bash
# Check Vault status
./devstack vault-status

# Expected output:
# Key             Value
# ---             -----
# Seal Type       shamir
# Initialized     true
# Sealed          false
# Total Shares    5
# Threshold       3
# Version         1.x.x
# Cluster Name    vault-cluster-xxxxxx
```

**What to Look For:**
- `Initialized: true` ✅
- `Sealed: false` ✅
- If `Sealed: true`, run: `./devstack vault-unseal`

---

### Step 7: Bootstrap Vault and Generate Credentials

**What This Does:** Generates strong random passwords for all databases and stores them securely in Vault.

**7.1 Bootstrap Vault:**

```bash
# Run the bootstrap script
./devstack vault-bootstrap
```

**Expected Output (takes 1-2 minutes):**

```
============================================
  Bootstrapping Vault with Service Credentials
============================================

[*] Enabling KV secrets engine at secret/...
[✓] Secrets engine enabled

[*] Enabling PKI secrets engine for TLS certificates...
[✓] PKI enabled at: pki/

[*] Configuring Root CA...
[✓] Root CA configured
    Certificate: pki/cert/ca
    Valid for: 10 years

[*] Configuring Intermediate CA...
[✓] Intermediate CA configured

[*] Creating PKI role for service certificates...
[✓] PKI role created: service-cert

[*] Generating credentials for PostgreSQL...
[✓] Generated: secret/postgres
    User: dev_admin
    Password: [25 character random string]

[*] Generating credentials for MySQL...
[✓] Generated: secret/mysql
    User: dev_admin
    Root Password: [25 character random string]
    User Password: [25 character random string]

[*] Generating credentials for Redis...
[✓] Generated: secret/redis-1
    Password: [25 character random string]
    (shared across redis-1, redis-2, redis-3)

[*] Generating credentials for RabbitMQ...
[✓] Generated: secret/rabbitmq
    User: dev_admin
    Password: [25 character random string]

[*] Generating credentials for MongoDB...
[✓] Generated: secret/mongodb
    User: dev_admin
    Password: [25 character random string]

[✓] Vault bootstrap complete!
[*] All service credentials have been generated and stored in Vault

[!] To view any service password:
    ./devstack vault-show-password <service>

    Example: ./devstack vault-show-password postgres
```

**What Just Happened:**
1. **Vault configured** a secrets storage system
2. **AppRole authentication enabled** - Each service gets its own role-id and secret-id
3. **Service policies created** - PostgreSQL, MySQL, MongoDB, Redis, RabbitMQ, Forgejo
4. **AppRole credentials stored** in `~/.config/vault/approles/<service>/role-id` and `secret-id`
5. **25-character random passwords** generated for each service
6. **Passwords stored securely** in Vault (not in plain text files)
7. **TLS certificate system** set up (for HTTPS connections)

**AppRole Authentication:**
- **role-id**: Identifies which service is connecting (like a username)
- **secret-id**: Proves the service is authorized (like a password)
- **Service tokens**: Short-lived (1 hour) tokens generated from AppRole login
- **Least privilege**: Each service can only access its own credentials

**Where Credentials Are Stored:**
```
~/.config/vault/
├── approles/
│   ├── postgres/role-id    # PostgreSQL AppRole credentials
│   ├── postgres/secret-id
│   ├── mysql/role-id       # MySQL AppRole credentials
│   ├── mysql/secret-id
│   └── ...                 # (7 services total with AppRole)
├── ca/                     # TLS certificates
└── root-token              # Vault root token (for management)
```

**7.2 Restart Services to Load Credentials:**

```bash
# Restart all services so they fetch passwords from Vault
./devstack restart
```

**Expected Output:**

```
[*] Restarting DevStack Core services...
[+] Running 13/13
 ✔ Container dev-postgres          Started
 ✔ Container dev-mysql             Started
 ✔ Container dev-redis-1           Started
 ...

[✓] All services restarted successfully
```

**7.3 Verify Credentials Were Loaded:**

```bash
# Check PostgreSQL logs to see if it loaded credentials
docker logs dev-postgres 2>&1 | grep -i "vault"

# Expected output:
# [✓] Successfully retrieved credentials from Vault
# [✓] User: dev_admin
# [✓] Database: dev_db

# View any service password
./devstack vault-show-password postgres

# Expected output:
# PostgreSQL Credentials:
# User: dev_admin
# Password: aB1cD2eF3gH4iJ5kL6mN7oP8qR9sT0u
# Database: dev_db
```

---

### Step 7.5: Initialize Redis Cluster (For Standard/Full Profiles Only)

**Skip This Step If:** You started with the `minimal` profile (single Redis instance).

**Required For:** `standard` and `full` profiles (3-node Redis cluster).

**What This Does:** Creates a Redis cluster by connecting the 3 Redis nodes together and distributing hash slots.

**7.5.1 Initialize Redis Cluster:**

```bash
# Using Python script (recommended)
./devstack redis-cluster-init

# OR using bash script
./devstack redis-cluster-init
```

**Expected Output:**

```
═══ Redis Cluster Initialization ═══

Step 1/3: Verify Redis Nodes Are Running
  ✓ dev-redis-1 is running
  ✓ dev-redis-2 is running
  ✓ dev-redis-3 is running

Step 2/3: Create Redis Cluster
  >>> Creating cluster with 3 master nodes
  >>> Performing hash slots allocation on 3 nodes...
  >>> Distributing 16384 slots across 3 nodes
  Master[0] -> Slots 0 - 5460
  Master[1] -> Slots 5461 - 10922
  Master[2] -> Slots 10923 - 16383
  >>> Sending CLUSTER MEET messages to join cluster
  >>> Waiting for cluster to join...
  >>> Performing Cluster Check (using node 172.20.0.13:6379)
  [OK] All nodes agree about slots configuration.
  [OK] All 16384 slots covered.

Step 3/3: Verify Cluster Health
  ✓ Cluster is healthy
  ✓ All slots assigned
  ✓ 3 master nodes active

Redis cluster created successfully!

Next Steps:
  1. Test cluster: redis-cli -c -h localhost -p 6379
  2. Check cluster info: redis-cli cluster info
  3. View cluster nodes: redis-cli cluster nodes
```

**7.5.2 Verify Redis Cluster:**

```bash
# Connect to cluster (note the -c flag for cluster mode)
docker exec -it dev-redis-1 redis-cli -c -a "$(./devstack vault-show-password redis-1 | grep Password | awk '{print $2}')"

# Inside redis-cli:
> CLUSTER INFO
# Expected output:
# cluster_state:ok
# cluster_slots_assigned:16384
# cluster_slots_ok:16384
# cluster_known_nodes:3

> CLUSTER NODES
# Expected output (3 nodes):
# abc123... 172.20.0.13:6379@16379 myself,master - 0 1234567890000 1 connected 0-5460
# def456... 172.20.0.16:6379@16379 master - 0 1234567890000 2 connected 5461-10922
# ghi789... 172.20.0.17:6379@16379 master - 0 1234567890000 3 connected 10923-16383

> exit
```

**What This Means:**
- `cluster_state:ok` - Cluster is healthy ✅
- `cluster_slots_assigned:16384` - All hash slots are assigned ✅
- `cluster_known_nodes:3` - All 3 nodes are in the cluster ✅

**7.5.3 Test Cluster Operations:**

```bash
# Set a key (will be routed to appropriate node)
docker exec -it dev-redis-1 redis-cli -c -a "$(./devstack vault-show-password redis-1 | grep Password | awk '{print $2}')" SET mykey "hello"

# Get the key (cluster will redirect to correct node)
docker exec -it dev-redis-1 redis-cli -c -a "$(./devstack vault-show-password redis-1 | grep Password | awk '{print $2}')" GET mykey

# Expected output: "hello"
```

**What If It Fails?**

```bash
# Check if all Redis nodes are running
docker ps | grep redis

# Expected: 3 containers (dev-redis-1, dev-redis-2, dev-redis-3)

# Check Redis logs
docker logs dev-redis-1 2>&1 | tail -20
docker logs dev-redis-2 2>&1 | tail -20
docker logs dev-redis-3 2>&1 | tail -20

# Destroy and recreate cluster
docker exec dev-redis-1 redis-cli -a "$REDIS_PASSWORD" CLUSTER RESET HARD
docker exec dev-redis-2 redis-cli -a "$REDIS_PASSWORD" CLUSTER RESET HARD
docker exec dev-redis-3 redis-cli -a "$REDIS_PASSWORD" CLUSTER RESET HARD
./devstack redis-cluster-init
```

---

### Step 8: Verify Everything Works

**8.1 Check Overall Status:**

```bash
# Run comprehensive status check
./devstack status
```

**Expected Output:**

```
============================================
  DevStack Core - Status
============================================

[✓] Colima Status:
    Profile: default
    Status: Running
    Arch: aarch64
    Runtime: docker
    Colima IP: 192.168.106.2

[✓] Docker Services:
NAME                    STATUS          HEALTH
dev-postgres            Up 5 minutes    healthy
dev-pgbouncer           Up 5 minutes    healthy
dev-mysql               Up 5 minutes    healthy
dev-redis-1             Up 5 minutes    healthy
dev-redis-2             Up 5 minutes    healthy
dev-redis-3             Up 5 minutes    healthy
dev-rabbitmq            Up 5 minutes    healthy
dev-mongodb             Up 5 minutes    healthy
dev-vault               Up 5 minutes    healthy
dev-forgejo             Up 5 minutes    healthy
dev-prometheus          Up 5 minutes    healthy
dev-grafana             Up 5 minutes    healthy
dev-loki                Up 5 minutes    healthy
dev-reference-api       Up 5 minutes    healthy

[✓] All services are healthy!
```

**What to Look For:**
- All services show `healthy` ✅
- If any show `starting`, wait 30 seconds and check again
- If any show `unhealthy`, see troubleshooting below

**8.2 Test Database Connections:**

```bash
# Test PostgreSQL
docker exec dev-postgres pg_isready -U dev_admin

# Expected output: accepting connections

# Test MySQL
docker exec dev-mysql mysqladmin ping -h localhost

# Expected output: mysqld is alive

# Test Redis
docker exec dev-redis-1 redis-cli -a $(./devstack vault-show-password redis-1 | grep "Password:" | awk '{print $2}') ping

# Expected output: PONG

# Test MongoDB
docker exec dev-mongodb mongosh --quiet --eval "db.adminCommand('ping')"

# Expected output: { ok: 1 }
```

**8.3 Run Health Check Script:**

```bash
# Run built-in health checks
./devstack health
```

**Expected Output:**

```
============================================
  Health Check
============================================

[✓] PostgreSQL: healthy (response time: 5ms)
[✓] MySQL: healthy (response time: 8ms)
[✓] Redis Cluster: healthy (3/3 nodes up)
[✓] RabbitMQ: healthy (management API responding)
[✓] MongoDB: healthy (accepting connections)
[✓] Vault: healthy (unsealed)
[✓] Forgejo: healthy (API responding)
[✓] Prometheus: healthy (metrics available)
[✓] Grafana: healthy (UI responding)
[✓] Loki: healthy (ready endpoint responding)

[✓] All health checks passed!
```

---

### Step 9: Access Your Services

**9.1 Web-Based Services:**

Open these URLs in your browser:

| Service | URL | Default Login |
|---------|-----|---------------|
| **Forgejo (Git Server)** | http://localhost:3000 | (create account on first visit) |
| **Vault UI** | http://localhost:8200/ui | Token from `~/.config/vault/root-token` |
| **RabbitMQ Management** | http://localhost:15672 | Get from: `./devstack vault-show-password rabbitmq` |
| **Grafana Dashboards** | http://localhost:3001 | admin / admin |
| **Prometheus Metrics** | http://localhost:9090 | (no login required) |
| **FastAPI Code-First** | http://localhost:8000/docs | (no login required) |
| **FastAPI API-First** | http://localhost:8001/docs | (no login required) |
| **Go API** | http://localhost:8002/health | (no login required) |
| **Node.js API** | http://localhost:8003/health | (no login required) |
| **Rust API** | http://localhost:8004/health | (no login required) |

**9.2 Test Forgejo (Git Server):**

```bash
# Open Forgejo in browser
open http://localhost:3000

# You should see the Forgejo welcome page
# Click "Register" to create your first admin account
```

**First-Time Setup Steps:**
1. Click **"Register"** in top-right
2. Fill in: Username, Email, Password
3. Click **"Register Account"**
4. You're now logged in as admin!

**9.3 Test Vault UI:**

```bash
# Get your Vault token
cat ~/.config/vault/root-token

# Open Vault UI
open http://localhost:8200/ui

# Login:
# 1. Method: Token
# 2. Token: [paste token from above]
# 3. Click "Sign In"

# Browse secrets:
# 1. Click "secret/" in left sidebar
# 2. You'll see: postgres, mysql, redis-1, rabbitmq, mongodb
# 3. Click any to view the stored credentials
```

**9.4 Test Grafana:**

```bash
# Open Grafana
open http://localhost:3001

# Login:
# Username: admin
# Password: admin

# You'll be prompted to change password (do this!)

# Explore dashboards:
# 1. Click "Dashboards" (left sidebar)
# 2. You'll see pre-configured dashboards:
#    - Container Metrics
#    - FastAPI Overview
#    - Forgejo Overview
```

**9.5 Connect to Databases from Command Line:**

```bash
# PostgreSQL
PGPASSWORD=$(./devstack vault-show-password postgres | grep "Password:" | awk '{print $2}') \
  psql -h localhost -p 5432 -U dev_admin -d dev_db

# MySQL
mysql -h 127.0.0.1 -P 3306 -u dev_admin -p
# (paste password from: ./devstack vault-show-password mysql)

# Redis
redis-cli -h localhost -p 6379 -a $(./devstack vault-show-password redis-1 | grep "Password:" | awk '{print $2}')

# MongoDB
mongosh "mongodb://dev_admin:$(./devstack vault-show-password mongodb | grep "Password:" | awk '{print $2}')@localhost:27017/dev_db"
```

**9.6 Test with FastAPI Reference Application:**

```bash
# Open API documentation
open http://localhost:8000/docs

# Try the health endpoint:
curl http://localhost:8000/health

# Expected output:
# {"status":"healthy","timestamp":"2025-10-23T..."}

# Test database connection:
curl http://localhost:8000/api/v1/databases/test

# Expected output: Database connection test results
```

---

### What to Do If Something Goes Wrong

**Problem: "Cannot connect to Docker daemon"**

```bash
# Solution 1: Check Colima status
colima status

# If stopped, start it:
./devstack start

# Solution 2: Set Docker context
docker context use colima
```

---

**Problem: "Vault is sealed"**

```bash
# Check status
./devstack vault-status

# If sealed:
./devstack vault-unseal

# Auto-unseal should happen automatically on restart
# If it doesn't, check logs:
docker logs dev-vault | tail -50
```

---

**Problem: "Port already in use"**

```bash
# Find what's using the port (example: 5432)
lsof -i :5432

# Solution 1: Stop the conflicting service
# (if it's another PostgreSQL instance, stop it)

# Solution 2: Change the port in docker-compose.yml
# Edit: ports: - "5433:5432"  # Changed host port to 5433
```

---

**Problem: Service shows "unhealthy" status**

```bash
# Check service logs
docker logs dev-<service-name>

# Example for PostgreSQL:
docker logs dev-postgres --tail 50

# Common fixes:
# 1. Restart the service:
docker compose restart <service-name>

# 2. Check if Vault is unsealed:
./devstack vault-status

# 3. Verify credentials were generated:
./devstack vault-show-password <service>
```

---

**Problem: "Cannot access Forgejo at localhost:3000"**

```bash
# Check if Forgejo is running
docker ps | grep forgejo

# Check Forgejo logs
docker logs dev-forgejo --tail 50

# Try accessing via Colima IP instead:
COLIMA_IP=$(./devstack ip | grep "Colima IP:" | awk '{print $3}')
open http://$COLIMA_IP:3000
```

---

**Problem: Redis Cluster shows "CLUSTERDOWN"**

```bash
# Check cluster status
docker exec dev-redis-1 redis-cli -a $(./devstack vault-show-password redis-1 | grep "Password:" | awk '{print $2}') cluster info

# Re-initialize cluster:
./configs/redis/scripts/redis-cluster-init.sh

# Verify:
docker exec dev-redis-1 redis-cli -a $(./devstack vault-show-password redis-1 | grep "Password:" | awk '{print $2}') cluster nodes
```

---

**Problem: Out of disk space**

```bash
# Check Docker disk usage
docker system df

# Clean up unused images/containers/volumes:
docker system prune -a --volumes

# WARNING: This removes ALL unused Docker data
# Your devstack-core volumes are safe (they're in use)

# Verify space freed:
docker system df
```

---

**Problem: Services are slow/unresponsive**

```bash
# Check resource usage
docker stats

# Increase Colima resources:
colima stop
colima start --cpu 6 --memory 12  # 6 CPUs, 12GB RAM

# Restart services:
./devstack restart
```

---

**Problem: Need to start completely fresh**

```bash
# WARNING: This deletes ALL data and containers!

# Stop everything
./devstack stop

# Delete Colima VM
colima delete

# Remove volumes (optional - deletes all data!)
docker volume rm $(docker volume ls -q)

# Start fresh:
./devstack start
./devstack vault-init
./devstack vault-bootstrap
```

---

**Still Having Issues?**

1. **Check the main Troubleshooting section** below for service-specific issues
2. **Review logs** for the failing service: `docker logs dev-<service>`
3. **Check Colima logs**: `colima logs`
4. **Verify environment**: `cat .env | grep -v "^#" | grep -v "^$"`
5. **Ask for help** with relevant log output

---

**Next Steps After Successful Installation:**

1. **Read the Service Configuration sections** to learn about each service
2. **Explore the Vault PKI Integration** section to enable TLS/HTTPS
3. **Check out the Testing Infrastructure** section to run comprehensive tests
4. **Review Best Practices** for development workflows
5. **Set up Forgejo** as your local Git server (push your projects!)

**Congratulations!** You now have a complete, production-like development environment running locally. 🎉

## Prerequisites

### System Requirements

- **Hardware:** Apple Silicon Mac (M Series Processors) or Intel Mac
- **RAM:** Minimum 16GB (32GB recommended for heavy usage)
- **Disk:** 60GB free space for Colima VM + volumes
- **macOS:** 12.0 (Monterey) or later for VZ support

### Required Software

```bash
# Install Homebrew (if not installed)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install required tools
brew install colima docker docker-compose

# Verify installation
colima version
docker --version
docker-compose --version
```

### Understanding Colima

**What happens when you run Colima:**

1. **VM Creation**: Colima creates a Lima-based Linux VM
   ```
   ~/.lima/colima/  # VM configuration and disk images
   ```

2. **Docker Installation**: Installs Docker Engine inside the VM
   ```
   docker context use colima  # Automatically configured
   ```

3. **Socket Exposure**: Exposes Docker socket to your Mac
   ```
   /var/run/docker.sock  # Symlinked to Lima VM socket
   ```

4. **Volume Mounting**: Mounts your home directory into the VM
   ```
   ~/  →  /Users/<username>/ inside VM
   ```

**Colima Profiles:**
- Multiple Colima instances can run simultaneously
- Each profile has its own VM, network, and volumes
- Default profile: `default`
- Custom profiles: `colima start --profile myproject`

## Installation

### First Time Setup

**1. Install Dependencies**
```bash
brew install colima docker docker-compose
```

**2. Clone Repository**
```bash
git clone https://github.com/NormB/devstack-core.git ~/devstack-core
cd ~/devstack-core
```

**3. Configure Environment**
```bash
cp .env.example .env
nano .env  # or vim, code, etc.
```

**Important:** Passwords are auto-generated by Vault during bootstrap:
- Run `./devstack vault-bootstrap` to generate all service credentials
- Passwords are 25-character random strings (base64, URL-safe)
- Stored securely in Vault, fetched at container startup
- No plaintext passwords in configuration files

**4. Make Management Script Executable**
```bash
chmod +x manage-devstack
```

### Configuration

**Environment Variables** (`.env`):

```bash
# HashiCorp Vault Configuration
VAULT_ADDR=http://vault:8200
VAULT_TOKEN=<from ~/.config/vault/root-token after initialization>

# Service Credentials - ALL MANAGED BY VAULT
# Credentials are automatically loaded from Vault at container startup
# To view credentials: ./devstack vault-show-password <service>
#
# Services with Vault integration:
#   - PostgreSQL: secret/postgres (user, password, database)
#   - MySQL: secret/mysql (root_password, user, password, database)
#   - Redis: secret/redis-1 (password - shared across all 3 nodes)
#   - RabbitMQ: secret/rabbitmq (user, password, vhost)
#   - MongoDB: secret/mongodb (user, password, database)

# PostgreSQL - Credentials from Vault (empty to suppress docker-compose warnings)
POSTGRES_PASSWORD=

# TLS Configuration (Optional - Disabled by Default)
POSTGRES_ENABLE_TLS=false
MYSQL_ENABLE_TLS=false
REDIS_ENABLE_TLS=false
RABBITMQ_ENABLE_TLS=false
MONGODB_ENABLE_TLS=false
REFERENCE_API_ENABLE_TLS=false  # FastAPI HTTPS support (port 8443)

# Forgejo (Git Server)
FORGEJO_DOMAIN=localhost  # Or Colima IP for network access
```

**⚠️ IMPORTANT: NO PLAINTEXT PASSWORDS**

All service credentials are managed by HashiCorp Vault. After running `vault-bootstrap`, credentials are:
- Generated automatically with strong random passwords
- Stored securely in Vault at `secret/<service>`
- Fetched by services at startup via init scripts
- Never stored in plaintext in `.env` files

**Retrieving Credentials:**

```bash
# View any service password
./devstack vault-show-password postgres
./devstack vault-show-password mysql
./devstack vault-show-password redis-1
./devstack vault-show-password rabbitmq
./devstack vault-show-password mongodb

# Or using Vault CLI
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=$(cat ~/.config/vault/root-token)
vault kv get -field=password secret/postgres
```

**Colima VM Configuration** (environment variables):

```bash
export COLIMA_PROFILE=default    # Profile name
export COLIMA_CPU=4              # CPU cores
export COLIMA_MEMORY=8           # Memory in GB
export COLIMA_DISK=60            # Disk size in GB
```

### Starting Services

**Option 1: Using Management Script (Recommended)**
```bash
./devstack start
```

This will:
1. Check/create `.env` file
2. Start Colima VM (if not running)
3. Start all Docker services
4. Initialize Vault (if first run)
5. Display service status and access URLs

**Option 2: Manual Start**
```bash
# Start Colima VM
colima start --cpu 4 --memory 8 --disk 60 --network-address --arch aarch64 --vm-type vz

# Start services
docker compose up -d

# Initialize Vault
./configs/vault/scripts/vault-init.sh

# Check status
docker compose ps
```

**Verify Everything is Running:**
```bash
./devstack status
./devstack health
```

