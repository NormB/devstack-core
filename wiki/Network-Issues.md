# Network Issues

## Table of Contents

- [Overview](#overview)
- [Port Conflicts Resolution](#port-conflicts-resolution)
  - [Identifying Port Conflicts](#identifying-port-conflicts)
  - [Changing Service Ports](#changing-service-ports)
  - [Killing Processes](#killing-processes)
- [Services Can't Communicate](#services-cant-communicate)
  - [Network Connectivity Tests](#network-connectivity-tests)
  - [Container Network Inspection](#container-network-inspection)
  - [Service Discovery](#service-discovery)
- [DNS Resolution Problems](#dns-resolution-problems)
  - [Docker DNS](#docker-dns)
  - [Manual DNS Configuration](#manual-dns-configuration)
  - [Hosts File Workaround](#hosts-file-workaround)
- [Network Connectivity Issues](#network-connectivity-issues)
  - [Docker Network Driver](#docker-network-driver)
  - [Network Reachability](#network-reachability)
  - [Firewall Rules](#firewall-rules)
- [Colima Networking Problems](#colima-networking-problems)
  - [VM Network Configuration](#vm-network-configuration)
  - [Port Forwarding](#port-forwarding)
  - [Network Reset](#network-reset)
- [Firewall Blocking Connections](#firewall-blocking-connections)
  - [macOS Firewall](#macos-firewall)
  - [Little Snitch](#little-snitch)
  - [Allow Rules](#allow-rules)
- [Static IP Conflicts](#static-ip-conflicts)
  - [IP Address Ranges](#ip-address-ranges)
  - [Resolving Conflicts](#resolving-conflicts)
  - [Dynamic IP Assignment](#dynamic-ip-assignment)
- [Bridge Network Troubleshooting](#bridge-network-troubleshooting)
  - [Network Creation](#network-creation)
  - [Subnet Conflicts](#subnet-conflicts)
  - [Network Cleanup](#network-cleanup)
- [Related Pages](#related-pages)

## Overview

Network issues are common in Docker environments. This page provides troubleshooting guidance for network connectivity, DNS resolution, port conflicts, and Colima-specific networking issues.

**Common Network Issues:**
- Port already in use (conflicts with other services)
- Containers can't reach each other
- DNS resolution fails
- Firewall blocking connections
- IP address conflicts
- Colima network isolation

## Port Conflicts Resolution

### Identifying Port Conflicts

**Check if port is already in use:**

```bash
# Check specific port
lsof -i :8200  # Vault port
lsof -i :5432  # PostgreSQL port
lsof -i :6379  # Redis port

# Check all listening ports
lsof -i -P | grep LISTEN

# netstat alternative
netstat -an | grep LISTEN

# Find process using port
lsof -t -i :8200  # Returns PID
```

**Common port conflicts:**

```bash
# PostgreSQL (5432) conflicts with system PostgreSQL
lsof -i :5432

# MySQL (3306) conflicts with system MySQL
lsof -i :3306

# Redis (6379) conflicts with system Redis
lsof -i :6379

# Web ports (8000, 8001, etc.) conflict with other dev servers
lsof -i :8000
```

### Changing Service Ports

**Update .env file:**

```bash
# Edit .env
nano .env

# Change PostgreSQL port
POSTGRES_PORT=5433  # Instead of 5432

# Change Redis port
REDIS_1_PORT=6380

# Change web application port
REFERENCE_API_PORT=8080
```

**Update docker-compose.yml:**

```yaml
services:
  postgres:
    ports:
      - "${POSTGRES_PORT:-5432}:5432"  # Maps host:container

  reference-api:
    ports:
      - "${REFERENCE_API_PORT:-8000}:8000"
```

**Restart services:**

```bash
docker compose down
docker compose up -d
```

### Killing Processes

**Stop conflicting processes:**

```bash
# Kill process by port
lsof -t -i :5432 | xargs kill -9

# Stop system PostgreSQL
brew services stop postgresql

# Stop system MySQL
brew services stop mysql

# Stop system Redis
brew services stop redis

# Verify port is free
lsof -i :5432  # Should return nothing
```

## Services Can't Communicate

### Network Connectivity Tests

**Test connectivity between containers:**

```bash
# From one container to another
docker exec dev-postgres ping -c 3 vault
docker exec dev-postgres curl http://vault:8200/v1/sys/health

# Test from host to container
curl http://localhost:8200/v1/sys/health

# Test container to internet
docker exec dev-postgres ping -c 3 8.8.8.8
docker exec dev-postgres curl https://www.google.com
```

**Check if service is listening:**

```bash
# Inside container
docker exec dev-postgres netstat -tuln | grep LISTEN

# Check Vault is listening
docker exec dev-vault netstat -tuln | grep 8200

# Check PostgreSQL is listening
docker exec dev-postgres netstat -tuln | grep 5432
```

### Container Network Inspection

**Inspect network configuration:**

```bash
# List Docker networks
docker network ls

# Inspect specific network
docker network inspect dev-services

# Check which containers are connected
docker network inspect dev-services | jq '.[0].Containers'

# View container IP addresses
docker network inspect dev-services | jq '.[0].Containers | .[] | {Name, IPv4Address}'
```

**Example output:**

```json
{
  "Name": "dev-vault",
  "IPv4Address": "172.20.0.21/16"
},
{
  "Name": "dev-postgres",
  "IPv4Address": "172.20.0.10/16"
}
```

### Service Discovery

**Verify DNS-based service discovery:**

```bash
# From inside container, resolve service name
docker exec dev-postgres nslookup vault

# Expected output:
# Server: 127.0.0.11
# Address: 127.0.0.11:53
#
# Name: vault
# Address: 172.20.0.21

# Test all services
for service in vault postgres mysql redis-1 rabbitmq; do
  echo "Testing $service..."
  docker exec dev-postgres nslookup $service
done
```

## DNS Resolution Problems

### Docker DNS

**Docker provides automatic DNS for container names:**

```bash
# Check Docker DNS server
docker exec dev-postgres cat /etc/resolv.conf

# Should show:
# nameserver 127.0.0.11
# options ndots:0

# Test DNS resolution
docker exec dev-postgres nslookup vault

# If fails, check network configuration
docker network inspect dev-services | jq '.[0].Options'
```

**DNS not working:**

```bash
# Restart Docker daemon
# This may fix DNS issues

# On macOS with Colima
colima stop
colima start

# Recreate containers
docker compose down
docker compose up -d
```

### Manual DNS Configuration

**Add custom DNS servers:**

```yaml
# docker-compose.yml
services:
  postgres:
    dns:
      - 8.8.8.8
      - 8.8.4.4
    dns_search:
      - dev-services
```

**Or modify /etc/resolv.conf in container:**

```bash
docker exec dev-postgres sh -c 'echo "nameserver 8.8.8.8" >> /etc/resolv.conf'
```

### Hosts File Workaround

**If DNS fails, use /etc/hosts:**

```bash
# Add entries to container's /etc/hosts
docker exec dev-postgres sh -c 'echo "172.20.0.21 vault" >> /etc/hosts'

# Or in docker-compose.yml
services:
  postgres:
    extra_hosts:
      - "vault:172.20.0.21"
      - "redis-1:172.20.0.13"
```

## Network Connectivity Issues

### Docker Network Driver

**Check network driver:**

```bash
docker network inspect dev-services | jq '.[0].Driver'
# Should be: bridge

# If network doesn't exist, create it
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  --gateway 172.20.0.1 \
  dev-services
```

### Network Reachability

**Test network reachability:**

```bash
# From host to container
ping 172.20.0.21  # Vault IP

# May not work on macOS (Docker Desktop/Colima limitation)
# Use port mapping instead

# From container to host
docker exec dev-postgres ping host.docker.internal

# Test container-to-container
docker exec dev-postgres ping 172.20.0.21
```

### Firewall Rules

**Check iptables rules (if accessible):**

```bash
# Inside Colima VM
colima ssh

# Check iptables
sudo iptables -L -n -v

# Check Docker chain
sudo iptables -L DOCKER -n -v

# Check NAT rules
sudo iptables -t nat -L -n -v
```

## Colima Networking Problems

### VM Network Configuration

**Check Colima network setup:**

```bash
# View Colima status
colima status

# Check network configuration
colima ls

# View VM info
limactl list

# Inspect Lima VM
limactl info colima
```

**Colima network modes:**

```bash
# Default (socket-vmnet) - Best performance
colima start --network-address

# NAT mode - More compatible
colima start --network-driver nat

# Host mode - Direct access
colima start --network-driver host
```

### Port Forwarding

**Configure port forwarding:**

```bash
# Forward additional ports
colima start \
  --cpu 4 \
  --memory 8 \
  --disk 50 \
  --network-address \
  --vm-type vz \
  --vz-rosetta \
  --mount-type virtiofs \
  --forward-agent

# Manual port forward (if needed)
# On host
ssh -L 5432:localhost:5432 user@colima-vm

# Access via localhost:5432
```

**Check port forwarding:**

```bash
# From host
curl http://localhost:8200/v1/sys/health

# If fails, check Colima is forwarding
colima status | grep "Network Address"
```

### Network Reset

**Reset Colima network:**

```bash
# Stop Colima
colima stop

# Delete Colima instance
colima delete

# Start fresh
colima start \
  --cpu 4 \
  --memory 8 \
  --disk 50 \
  --network-address

# Recreate containers
cd ~/devstack-core
docker compose up -d
```

## Firewall Blocking Connections

### macOS Firewall

**Check macOS firewall:**

```bash
# Check firewall status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Check if blocking Docker
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps | grep -i docker

# Allow Docker
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /Applications/Docker.app
```

**Disable firewall temporarily for testing:**

```bash
# Disable (for testing only!)
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off

# Test connection
curl http://localhost:8200/v1/sys/health

# Re-enable firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

### Little Snitch

**If using Little Snitch:**

```bash
# Allow connections for:
# - Docker
# - Colima
# - com.docker.backend
# - qemu (if using qemu driver)

# Check Little Snitch rules in:
# System Preferences → Little Snitch → Rules
```

### Allow Rules

**Create allow rules for development:**

```bash
# In macOS Firewall settings:
# System Preferences → Security & Privacy → Firewall → Firewall Options

# Add applications:
# - Docker
# - Colima
# - Terminal (for local development)

# Or disable firewall for local networks only
```

## Static IP Conflicts

### IP Address Ranges

**Allocated IP ranges in devstack-core:**

```
172.20.0.0/16 - dev-services network

Core Services:
172.20.0.10 - PostgreSQL
172.20.0.11 - PgBouncer
172.20.0.12 - MySQL
172.20.0.13 - Redis-1
172.20.0.14 - RabbitMQ
172.20.0.15 - MongoDB
172.20.0.16 - Redis-2
172.20.0.17 - Redis-3
172.20.0.20 - Forgejo
172.20.0.21 - Vault

Observability:
172.20.0.101 - Prometheus
172.20.0.102 - Grafana
172.20.0.103 - Loki

Applications:
172.20.0.100 - FastAPI Reference
172.20.0.104 - Go API
172.20.0.105 - Node.js API
172.20.0.106 - Rust API
```

### Resolving Conflicts

**Check for IP conflicts:**

```bash
# List all container IPs
docker ps -q | xargs docker inspect | jq -r '.[] | "\(.Name): \(.NetworkSettings.Networks["dev-services"].IPAddress)"'

# Check for duplicate IPs
docker network inspect dev-services | jq '.[0].Containers | .[] | .IPv4Address' | sort | uniq -d
```

**Fix IP conflicts:**

```bash
# Stop all containers
docker compose down

# Remove network
docker network rm dev-services

# Recreate network
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  --gateway 172.20.0.1 \
  dev-services

# Start containers
docker compose up -d
```

### Dynamic IP Assignment

**Use dynamic IPs instead of static:**

```yaml
# docker-compose.yml
services:
  postgres:
    # Remove static IP
    networks:
      - dev-services
    # Docker will assign IP automatically

networks:
  dev-services:
    driver: bridge
    # No subnet specification needed
```

**Pros/Cons:**
- Pro: No IP conflicts
- Con: IPs may change on restart
- Con: Harder to troubleshoot

## Bridge Network Troubleshooting

### Network Creation

**Manually create network:**

```bash
# Create with specific subnet
docker network create \
  --driver bridge \
  --subnet 172.20.0.0/16 \
  --gateway 172.20.0.1 \
  --ip-range 172.20.0.0/24 \
  --opt com.docker.network.bridge.name=br-dev-services \
  dev-services

# Verify creation
docker network inspect dev-services
```

### Subnet Conflicts

**Check for subnet conflicts:**

```bash
# List all Docker networks and subnets
docker network ls
docker network inspect $(docker network ls -q) | jq -r '.[] | "\(.Name): \(.IPAM.Config[0].Subnet)"'

# Check host network subnets
ifconfig

# If conflict, use different subnet
docker network create \
  --subnet 172.21.0.0/16 \
  dev-services
```

**Update docker-compose.yml:**

```yaml
networks:
  dev-services:
    driver: bridge
    ipam:
      config:
        - subnet: 172.21.0.0/16  # Changed from 172.20.0.0/16
          gateway: 172.21.0.1

services:
  vault:
    networks:
      dev-services:
        ipv4_address: 172.21.0.21  # Update all IPs
```

### Network Cleanup

**Clean up unused networks:**

```bash
# List networks
docker network ls

# Remove unused networks
docker network prune

# Remove specific network
docker network rm dev-services

# Force remove (disconnect containers first)
docker network disconnect -f dev-services dev-vault
docker network rm dev-services
```

**Complete network reset:**

```bash
# Stop all containers
docker compose down

# Remove all custom networks
docker network ls | grep -v "bridge\|host\|none" | awk '{print $1}' | tail -n +2 | xargs docker network rm

# Recreate from docker-compose.yml
docker compose up -d
```

## Common Network Debugging Commands

**Quick reference:**

```bash
# Check if port is in use
lsof -i :<port>

# List all Docker networks
docker network ls

# Inspect network
docker network inspect <network-name>

# Test connectivity from container
docker exec <container> ping <host>
docker exec <container> curl <url>
docker exec <container> nslookup <host>

# Check container IP
docker inspect <container> | jq '.[0].NetworkSettings.Networks'

# View container network settings
docker exec <container> ip addr
docker exec <container> route -n

# Test DNS resolution
docker exec <container> cat /etc/resolv.conf
docker exec <container> nslookup <service-name>

# Check listening ports in container
docker exec <container> netstat -tuln

# View iptables (if accessible)
colima ssh
sudo iptables -L -n -v

# Reset Docker networking
docker compose down
docker network prune
docker compose up -d
```

## Advanced Network Debugging

**Enable Docker debug logging:**

```bash
# On Docker Desktop
# Preferences → Docker Engine → Add:
{
  "debug": true,
  "log-level": "debug"
}

# View Docker logs
cat ~/Library/Containers/com.docker.docker/Data/log/vm/docker.log
```

**Capture network traffic:**

```bash
# Install tcpdump in container
docker exec -u root dev-postgres apt-get update && apt-get install -y tcpdump

# Capture traffic
docker exec dev-postgres tcpdump -i eth0 -w /tmp/capture.pcap

# Download and analyze
docker cp dev-postgres:/tmp/capture.pcap ./
wireshark capture.pcap
```

**Test with netcat:**

```bash
# In one container, listen
docker exec -it dev-postgres nc -l -p 9999

# In another, connect
docker exec dev-vault nc postgres 9999

# Type messages to test connectivity
```

## Related Pages

- [Service-Configuration](Service-Configuration) - Network configuration
- [Colima-Configuration](Colima-Configuration) - Colima network setup
- [Health-Monitoring](Health-Monitoring) - Connectivity monitoring
- [Port-Reference](Port-Reference) - Port mappings
- [Vault-Troubleshooting](Vault-Troubleshooting) - Vault connectivity issues
