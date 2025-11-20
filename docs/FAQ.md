# FAQ

## Service Profiles (NEW v1.3)

**Q: What are service profiles and why should I use them?**
A: Service profiles let you start only the services you need, saving resources and startup time:
- **minimal**: 5 services, 2GB RAM - Git hosting + basic database
- **standard**: 10 services, 4GB RAM - Full stack + Redis cluster (recommended)
- **full**: 18 services, 6GB RAM - Everything + observability
- **reference**: 5 API examples - Educational, combine with standard/full

See [SERVICE_PROFILES.md](./SERVICE_PROFILES.md) for complete details.

**Q: Which profile should I use?**
A: **Standard profile is recommended for most developers:**
```bash
./devstack.py start --profile standard
```
Use minimal if you have limited RAM (< 8GB), or full if you need Prometheus/Grafana.

**Q: How do I switch between profiles?**
A: Stop current services and start with new profile:
```bash
docker compose down
./devstack.py start --profile minimal  # or standard, full
```

**Q: Can I combine profiles?**
A: Yes! Combine standard/full with reference:
```bash
./devstack.py start --profile standard --profile reference
```
This gives you infrastructure + 5 educational API examples.

**Q: Do I need to initialize Redis cluster for all profiles?**
A: Only for standard and full profiles:
```bash
./devstack.py start --profile standard
./devstack.py redis-cluster-init  # Required for cluster
```
Minimal profile uses single Redis instance (no initialization needed).

**Q: Can I use the bash script with profiles?**
A: The bash script (`devstack.sh`) starts all services (no profile support). Use the Python script for profile control:
```bash
./devstack.py start --profile standard  # Profile-aware
./devstack.sh start                     # All services
```

**Q: How do I check which profile is running?**
A: Use status or health commands:
```bash
./devstack.py status   # Shows running containers
./devstack.py health   # Shows health status
docker compose ps             # Shows all running services
```

**Q: Can I create custom profiles?**
A: Yes! Create a custom environment file:
```bash
# Create custom profile
cat > configs/profiles/my-custom.env << 'EOF'
REDIS_CLUSTER_ENABLED=true
POSTGRES_MAX_CONNECTIONS=200
ENABLE_METRICS=false
EOF

# Load and use
set -a
source configs/profiles/my-custom.env
set +a
docker compose --profile standard up -d
```

**Q: Where are profile settings stored?**
A: Profile environment overrides are in `configs/profiles/`:
- `minimal.env` - Minimal profile settings
- `standard.env` - Standard profile settings
- `full.env` - Full profile settings
- `reference.env` - Reference profile settings

**Q: What's the difference between Python and Bash management scripts?**
A:
- **Python script** (`devstack.py`): Profile-aware, colored output, better UX, 850 lines
- **Bash script** (`devstack.sh`): Traditional, no profiles, starts everything, 1,622 lines

Both are maintained. Use Python for profiles, Bash for backwards compatibility.

## General Questions

**Q: Can I use this on Intel Mac?**
A: No, not without significant modifications. The project uses ARM64-specific Docker images (`platform: linux/arm64`) that are incompatible with Intel Macs.

**If you must run on Intel Mac:**
1. Use QEMU emulation: `colima start --vm-type qemu --arch aarch64`
2. Expect significant performance degradation (emulation overhead)
3. Some services may not work correctly under emulation
4. You may need to modify `docker-compose.yml` to remove ARM64 platform specifications

**Recommended:** Use an Apple Silicon Mac or run on a native ARM64 Linux server.

**Q: Can I run multiple Colima instances?**
A: Yes, use profiles:
```bash
export COLIMA_PROFILE=project1
./devstack.sh start

export COLIMA_PROFILE=project2
./devstack.sh start
```

**Q: How do I access services from libvirt VMs?**
A: Use Colima IP instead of localhost:
```bash
COLIMA_IP=$(./devstack.sh ip | grep "Colima IP:" | awk '{print $3}')
psql -h $COLIMA_IP -p 5432 -U $POSTGRES_USER
```

**Q: Can I use Docker Desktop instead of Colima?**
A: Yes, but remove `colima` commands from `devstack.sh`. Just use `docker compose up -d`.

**Q: How do I update service versions?**
A: Edit `docker-compose.yml`:
```yaml
# Change
image: postgres:18

# To (for example, a future version)
image: postgres:19

# Then
docker compose pull postgres
docker compose up -d postgres
```

**Q: What if I lose Vault unseal keys?**
A: Data is permanently inaccessible. You must:
1. Stop Vault
2. Delete vault_data volume
3. Re-initialize (creates new keys)
4. Re-enter all secrets

**ALWAYS BACKUP UNSEAL KEYS!**

**Q: Can I use this for production?**
A: No. Requires:
- TLS everywhere
- External secrets management
- High availability
- Monitoring/alerting
- Proper backup strategy
- Security hardening

**Q: How do I migrate data from old setup?**
A:
1. Backup old databases (pg_dump, mysqldump, etc.)
2. Start DevStack Core services
3. Restore backups
4. Test connectivity
5. Update application connection strings

**Q: Redis cluster vs single instance?**
A: Cluster provides:
- Horizontal scaling (distribute data)
- High availability (node failures)
- Production parity

Single instance is simpler but doesn't match production.

