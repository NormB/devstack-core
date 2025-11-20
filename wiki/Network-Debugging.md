# Network Debugging

Advanced network troubleshooting techniques for DevStack Core environment.

## Table of Contents

- [Overview](#overview)
- [Network Architecture Review](#network-architecture-review)
- [Connectivity Testing](#connectivity-testing)
- [DNS Troubleshooting](#dns-troubleshooting)
- [Port Testing](#port-testing)
- [Packet Inspection](#packet-inspection)
- [Firewall Issues](#firewall-issues)
- [Common Issues](#common-issues)
- [Service Connectivity](#service-connectivity)
- [Network Performance](#network-performance)
- [Related Documentation](#related-documentation)

## Overview

Network issues are common in containerized environments. This guide provides systematic approaches to diagnose and resolve network problems in DevStack Core.

**Network Setup:**
- **Network**: dev-services (172.20.0.0/16)
- **Type**: Bridge network
- **DNS**: Docker internal DNS
- **Services**: Static IP assignments

## Network Architecture Review

### Network Configuration

```bash
# View network details
docker network inspect dev-services

# List all networks
docker network ls

# Show containers in network
docker network inspect dev-services | jq '.[0].Containers'

# View IP addresses
docker network inspect dev-services | jq '.[0].Containers | to_entries[] | {name: .value.Name, ip: .value.IPv4Address}'
```

### Service IP Addresses

```
Vault:          172.20.0.21:8200
PostgreSQL:     172.20.0.10:5432
PgBouncer:      172.20.0.11:6432
MySQL:          172.20.0.12:3306
Redis-1:        172.20.0.13:6379
Redis-2:        172.20.0.16:6379
Redis-3:        172.20.0.17:6379
RabbitMQ:       172.20.0.14:5672
MongoDB:        172.20.0.15:27017
Forgejo:        172.20.0.20:3000
Reference-API:  172.20.0.100:8000
```

### Network Routes

```bash
# View routing table (from container)
docker exec postgres ip route

# View routing table (from host)
docker run --rm --network dev-services alpine ip route

# Check default gateway
docker exec postgres ip route | grep default
```

## Connectivity Testing

### Basic Ping Tests

```bash
# Ping from host to container
ping -c 3 172.20.0.10  # PostgreSQL IP

# Ping from container to container (by IP)
docker exec postgres ping -c 3 172.20.0.21  # Vault IP

# Ping from container to container (by name)
docker exec postgres ping -c 3 vault

# Ping external (test internet)
docker exec postgres ping -c 3 8.8.8.8
docker exec postgres ping -c 3 google.com

# Continuous ping
docker exec postgres ping vault
```

### TCP Connectivity

```bash
# Test port with nc (netcat)
docker exec postgres nc -zv vault 8200
docker exec postgres nc -zv mysql 3306
docker exec postgres nc -zv redis-1 6379

# Test from host
nc -zv localhost 5432
nc -zv localhost 8200

# Telnet test
docker exec postgres telnet vault 8200

# Timeout test
docker exec postgres timeout 5 nc -zv vault 8200
```

### HTTP Connectivity

```bash
# Test HTTP endpoint
docker exec postgres curl -v http://vault:8200/v1/sys/health

# Test with timeout
docker exec postgres curl --max-time 5 http://vault:8200/v1/sys/health

# Test HTTPS
docker exec postgres curl -k https://reference-api:8443/health

# Follow redirects
docker exec postgres curl -L http://vault:8200

# Show only headers
docker exec postgres curl -I http://vault:8200/v1/sys/health
```

## DNS Troubleshooting

### DNS Resolution

```bash
# Resolve hostname with nslookup
docker exec postgres nslookup vault
docker exec postgres nslookup postgres
docker exec postgres nslookup google.com

# Resolve with dig
docker exec postgres dig vault
docker exec postgres dig vault +short
docker exec postgres dig @8.8.8.8 google.com

# Resolve with host
docker exec postgres host vault
docker exec postgres host google.com

# Use getent (more reliable for Docker DNS)
docker exec postgres getent hosts vault
docker exec postgres getent hosts postgres
```

### DNS Configuration

```bash
# Check DNS resolver configuration
docker exec postgres cat /etc/resolv.conf

# Check /etc/hosts
docker exec postgres cat /etc/hosts

# Check nsswitch configuration
docker exec postgres cat /etc/nsswitch.conf

# Flush DNS cache (if needed)
docker restart <container>
```

### DNS Issues

```bash
# DNS not resolving container names
# 1. Check container is in same network
docker network inspect dev-services | grep postgres

# 2. Verify DNS is working
docker exec postgres nslookup vault

# 3. Try IP address instead
docker exec postgres ping 172.20.0.21

# 4. Check for name conflicts
docker ps --format "{{.Names}}" | sort | uniq -d

# 5. Restart Docker DNS
docker compose restart
```

## Port Testing

### Check Listening Ports

```bash
# Using netstat
docker exec postgres netstat -tlnp
docker exec postgres netstat -tlnp | grep 5432

# Using ss (modern alternative)
docker exec postgres ss -tlnp
docker exec postgres ss -tlnp | grep 5432

# Using lsof
docker exec postgres lsof -i :5432
docker exec postgres lsof -i TCP

# Check all listening ports
docker exec postgres netstat -tlnp | awk '{print $4}' | grep -o '[0-9]*$' | sort -u
```

### Port Conflicts

```bash
# Check if port is already in use (host)
lsof -i :5432
netstat -an | grep 5432

# Find process using port
lsof -i :5432 -t
ps aux | grep $(lsof -i :5432 -t)

# Kill process using port
kill $(lsof -i :5432 -t)

# Change port in docker-compose.yml
ports:
  - "5433:5432"  # Use different host port
```

### Port Mapping Verification

```bash
# List port mappings
docker port postgres

# Get specific port mapping
docker port postgres 5432

# Check all service ports
docker compose ps --format "table {{.Name}}\t{{.Ports}}"

# Verify port is accessible from host
nc -zv localhost 5432
telnet localhost 5432
```

## Packet Inspection

### Install tcpdump

```bash
# Install in container (temporary)
docker exec -u root postgres apt-get update
docker exec -u root postgres apt-get install -y tcpdump

# Or use Dockerfile
FROM postgres:16
RUN apt-get update && apt-get install -y tcpdump
```

### Capture Traffic

```bash
# Capture all traffic on interface
docker exec postgres tcpdump -i any

# Capture specific port
docker exec postgres tcpdump -i any port 5432

# Capture to file
docker exec postgres tcpdump -i any port 5432 -w /tmp/capture.pcap

# Capture with filter
docker exec postgres tcpdump -i any 'port 5432 and host 172.20.0.21'

# View captured packets
docker exec postgres tcpdump -r /tmp/capture.pcap

# Copy capture to host
docker cp postgres:/tmp/capture.pcap ./postgres-capture.pcap

# Analyze with Wireshark
wireshark postgres-capture.pcap
```

### Live Traffic Analysis

```bash
# Monitor HTTP traffic
docker exec postgres tcpdump -i any -A 'tcp port 8200'

# Monitor DNS queries
docker exec postgres tcpdump -i any port 53

# Monitor specific connection
docker exec postgres tcpdump -i any 'host 172.20.0.21 and port 8200'

# Count packets
docker exec postgres tcpdump -i any port 5432 -c 100
```

### Network Statistics

```bash
# Interface statistics
docker exec postgres ip -s link

# TCP statistics
docker exec postgres netstat -st

# Connection states
docker exec postgres netstat -ant | awk '{print $6}' | sort | uniq -c
```

## Firewall Issues

### macOS Firewall

```bash
# Check firewall status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# List firewall rules
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --listapps

# Allow Docker
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /Applications/Docker.app
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblock /Applications/Docker.app
```

### Colima VM Firewall

```bash
# Access Colima VM
colima ssh

# Check iptables
sudo iptables -L -n -v

# Check Docker chain
sudo iptables -L DOCKER -n -v

# Check NAT table
sudo iptables -t nat -L -n -v

# View forwarding rules
sudo iptables -L FORWARD -n -v
```

### Docker Network Rules

```bash
# View Docker network rules
docker run --rm --privileged --net=host nicolaka/netshoot iptables -L DOCKER -n

# Check Docker0 bridge
docker run --rm --net=host nicolaka/netshoot ip addr show docker0

# Test from privileged container
docker run -it --rm --privileged --net=host nicolaka/netshoot
# Then run diagnostics
```

## Common Issues

### Connection Refused

**Symptom:** `Connection refused` when connecting to service

```bash
# Step 1: Check if service is running
docker ps | grep <service>

# Step 2: Check if port is listening
docker exec <service> netstat -tlnp | grep <port>

# Step 3: Check from same network
docker exec <another-container> nc -zv <service> <port>

# Step 4: Check logs
docker logs <service> | tail -50

# Step 5: Check service binding
docker exec <service> netstat -tlnp | grep <port>
# Should show 0.0.0.0:<port> not 127.0.0.1:<port>

# Fix: Ensure service binds to 0.0.0.0
# PostgreSQL: listen_addresses = '*'
# Redis: bind 0.0.0.0
```

### Connection Timeout

**Symptom:** Connection times out

```bash
# Step 1: Test basic connectivity
docker exec <container> ping -c 3 <target>

# Step 2: Check for network latency
docker exec <container> ping -c 10 <target>
# Look for high latency or packet loss

# Step 3: Test port with timeout
docker exec <container> timeout 5 nc -zv <target> <port>

# Step 4: Check resource constraints
docker stats <container> --no-stream

# Step 5: Increase timeout in application
# Update connection_timeout settings
```

### DNS Failure

**Symptom:** Cannot resolve hostnames

```bash
# Step 1: Test DNS resolution
docker exec <container> nslookup <target>

# Step 2: Check /etc/resolv.conf
docker exec <container> cat /etc/resolv.conf

# Step 3: Test with IP address
docker exec <container> ping -c 3 172.20.0.21

# Step 4: Verify container in network
docker network inspect dev-services | grep <container>

# Step 5: Restart for DNS refresh
docker compose restart <service>

# Fix: Ensure containers in same network
docker-compose.yml:
  services:
    myapp:
      networks:
        - dev-services
```

### Routing Issues

**Symptom:** Cannot reach external services or specific subnets

```bash
# Step 1: Check routing table
docker exec <container> ip route

# Step 2: Test gateway
docker exec <container> ping -c 3 $(ip route | grep default | awk '{print $3}')

# Step 3: Check external connectivity
docker exec <container> ping -c 3 8.8.8.8

# Step 4: Check network configuration
docker network inspect dev-services

# Step 5: Recreate network if needed
docker compose down
docker network rm dev-services
docker compose up -d
```

## Service Connectivity

### PostgreSQL Connectivity

```bash
# Test connection
docker exec postgres pg_isready -U postgres

# Test from another container
docker exec dev-reference-api psql -h postgres -U postgres -c "SELECT 1;"

# Check listening address
docker exec postgres netstat -tlnp | grep 5432
# Should show: 0.0.0.0:5432 or :::5432

# Check pg_hba.conf
docker exec postgres cat /var/lib/postgresql/data/pg_hba.conf | grep -v "^#"

# Test with psql
docker exec -it postgres psql -h localhost -U postgres
```

### MySQL Connectivity

```bash
# Test connection
docker exec mysql mysqladmin -u root -p ping

# Test from another container
docker exec dev-reference-api mysql -h mysql -u root -p -e "SELECT 1;"

# Check binding
docker exec mysql netstat -tlnp | grep 3306

# Check user hosts
docker exec mysql mysql -u root -p -e "SELECT user, host FROM mysql.user;"

# Ensure remote access allowed
docker exec mysql mysql -u root -p -e "GRANT ALL ON *.* TO 'root'@'%';"
```

### MongoDB Connectivity

```bash
# Test connection
docker exec mongodb mongosh --eval "db.serverStatus().ok"

# Test from another container
docker exec dev-reference-api mongosh mongodb://mongodb:27017 --eval "db.version()"

# Check binding
docker exec mongodb netstat -tlnp | grep 27017

# Check bindIp setting
docker exec mongodb cat /etc/mongod.conf | grep bindIp
```

### Redis Connectivity

```bash
# Test connection
docker exec redis-1 redis-cli ping

# Test from another container
docker exec dev-reference-api redis-cli -h redis-1 ping

# Check binding
docker exec redis-1 netstat -tlnp | grep 6379

# Test cluster connectivity
docker exec redis-1 redis-cli -c CLUSTER NODES
```

## Network Performance

### Latency Testing

```bash
# Measure ping latency
docker exec postgres ping -c 100 vault | tail -3

# HTTP latency
docker exec postgres time curl -s http://vault:8200/v1/sys/health > /dev/null

# Database query latency
docker exec postgres psql -U postgres -c "\timing" -c "SELECT 1;"

# Redis latency
docker exec redis-1 redis-cli --latency
docker exec redis-1 redis-cli --latency-history
```

### Bandwidth Testing

```bash
# Install iperf3
docker exec -u root postgres apt-get install -y iperf3

# Start server
docker exec postgres iperf3 -s

# Run client from another container
docker exec mysql iperf3 -c postgres

# UDP bandwidth test
docker exec postgres iperf3 -s -u
docker exec mysql iperf3 -c postgres -u
```

### Throughput Testing

```bash
# HTTP throughput
docker exec postgres curl -o /dev/null http://vault:8200/v1/sys/health

# Large file transfer
docker exec postgres dd if=/dev/zero bs=1M count=100 | docker exec -i mysql dd of=/dev/null
```

### Network Bottlenecks

```bash
# Monitor network I/O
docker stats --format "table {{.Name}}\t{{.NetIO}}"

# Check for packet loss
docker exec postgres ping -c 100 vault | grep loss

# Check for errors
docker exec postgres ip -s link

# Monitor connections
watch -n 1 'docker exec postgres netstat -ant | wc -l'
```

## Related Documentation

- [Network Architecture](Network-Architecture) - Network design and configuration
- [Network Issues](Network-Issues) - Common network problems
- [Debugging Techniques](Debugging-Techniques) - General debugging
- [Common Issues](Common-Issues) - Known issues and solutions
- [Service Configuration](Service-Configuration) - Service setup
- [Container Management](Container-Management) - Container operations

---

**Quick Reference Card:**

```bash
# Connectivity
ping -c 3 <host>
nc -zv <host> <port>
telnet <host> <port>
curl http://<host>:<port>

# DNS
nslookup <hostname>
dig <hostname>
getent hosts <hostname>

# Port Testing
netstat -tlnp | grep <port>
ss -tlnp | grep <port>
lsof -i :<port>

# Packet Capture
tcpdump -i any port <port>
tcpdump -i any -w capture.pcap
tcpdump -r capture.pcap

# From Container
docker exec <container> ping <target>
docker exec <container> nc -zv <target> <port>
docker exec <container> curl http://<target>
```
