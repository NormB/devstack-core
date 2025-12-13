# Use Cases

Step-by-step walkthroughs for common development tasks. Each use case shows exactly what you need to accomplish a specific goal.

---

## Quick Links

| Task | Time |
|------|------|
| [Connect a Python app to PostgreSQL](#use-case-1-connect-python-app-to-postgresql) | 5 min |
| [Connect a Go app to Redis](#use-case-2-connect-go-app-to-redis) | 5 min |
| [Connect a Node.js app to RabbitMQ](#use-case-3-connect-nodejs-app-to-rabbitmq) | 5 min |
| [Set up local development database](#use-case-4-set-up-local-development-database) | 10 min |
| [Use Vault secrets in your app](#use-case-5-use-vault-secrets-in-your-app) | 10 min |
| [Monitor your app with Grafana](#use-case-6-monitor-your-app-with-grafana) | 15 min |

---

## Use Case 1: Connect Python App to PostgreSQL

**Goal:** Connect a Python (FastAPI/Flask) application to the PostgreSQL database.

### What You're Building

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Your App    │────▶│   DevStack   │────▶│  PostgreSQL  │
│  (Python)    │     │  localhost   │     │    :5432     │
└──────────────┘     └──────────────┘     └──────────────┘
```

### Step 1: Start DevStack

```bash
cd ~/devstack-core
./devstack start
./devstack health  # Verify postgres is healthy
```

### Step 2: Get Credentials

```bash
./devstack vault-show-password postgres
```

**Output:**
```
Username: devuser
Password: Hx7kL9mNpQr2sTuVwXyZ12345
Database: devdb
Host: localhost
Port: 5432
```

### Step 3: Install Python Dependencies

```bash
pip install psycopg2-binary sqlalchemy
```

### Step 4: Connect in Your Code

**Option A: Direct Connection (psycopg2)**
```python
import psycopg2

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    database="devdb",
    user="devuser",
    password="Hx7kL9mNpQr2sTuVwXyZ12345"  # From vault-show-password
)

cursor = conn.cursor()
cursor.execute("SELECT version();")
print(cursor.fetchone())
conn.close()
```

**Option B: SQLAlchemy**
```python
from sqlalchemy import create_engine

DATABASE_URL = "postgresql://devuser:Hx7kL9mNpQr2sTuVwXyZ12345@localhost:5432/devdb"
engine = create_engine(DATABASE_URL)

with engine.connect() as conn:
    result = conn.execute("SELECT 1")
    print(result.fetchone())
```

**Option C: FastAPI with Environment Variables**
```python
import os
from sqlalchemy import create_engine

# Load from environment (set via: source scripts/load-vault-env.sh)
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    f"postgresql://{os.environ['POSTGRES_USER']}:{os.environ['POSTGRES_PASSWORD']}@localhost:5432/{os.environ['POSTGRES_DB']}"
)

engine = create_engine(DATABASE_URL)
```

### Step 5: Test Connection

```bash
python -c "
import psycopg2
conn = psycopg2.connect(host='localhost', port=5432, database='devdb', user='devuser', password='YOUR_PASSWORD')
print('Connected successfully!')
conn.close()
"
```

---

## Use Case 2: Connect Go App to Redis

**Goal:** Connect a Go application to the Redis cluster.

### What You're Building

```
┌──────────────┐     ┌──────────────┐
│  Your App    │────▶│ Redis Cluster│
│    (Go)      │     │ :6379-6381   │
└──────────────┘     └──────────────┘
                     3 nodes, auto-sharding
```

### Step 1: Ensure Redis Cluster is Running

```bash
./devstack start --profile standard
./devstack redis-cluster-init  # Only needed once
./devstack health | grep redis
```

### Step 2: Get Redis Password

```bash
./devstack vault-show-password redis
```

### Step 3: Install Go Redis Client

```bash
go get github.com/redis/go-redis/v9
```

### Step 4: Connect in Your Code

**Single Node Connection**
```go
package main

import (
    "context"
    "fmt"
    "github.com/redis/go-redis/v9"
)

func main() {
    ctx := context.Background()

    rdb := redis.NewClient(&redis.Options{
        Addr:     "localhost:6379",
        Password: "YOUR_REDIS_PASSWORD",  // From vault-show-password
    })

    // Test connection
    pong, err := rdb.Ping(ctx).Result()
    if err != nil {
        panic(err)
    }
    fmt.Println("Connected:", pong)

    // Set and get
    rdb.Set(ctx, "key", "value", 0)
    val, _ := rdb.Get(ctx, "key").Result()
    fmt.Println("key:", val)
}
```

**Cluster Connection**
```go
package main

import (
    "context"
    "github.com/redis/go-redis/v9"
)

func main() {
    ctx := context.Background()

    rdb := redis.NewClusterClient(&redis.ClusterOptions{
        Addrs: []string{
            "localhost:6379",
            "localhost:6380",
            "localhost:6381",
        },
        Password: "YOUR_REDIS_PASSWORD",
    })

    // Cluster automatically routes keys to correct node
    rdb.Set(ctx, "user:1", "Alice", 0)
    rdb.Set(ctx, "user:2", "Bob", 0)  // May go to different node
}
```

---

## Use Case 3: Connect Node.js App to RabbitMQ

**Goal:** Connect a Node.js application to RabbitMQ for message queuing.

### What You're Building

```
┌──────────────┐              ┌──────────────┐              ┌──────────────┐
│   Producer   │──── send ───▶│   RabbitMQ   │◀── receive ──│   Consumer   │
│  (Your App)  │              │    :5672     │              │  (Your App)  │
└──────────────┘              └──────────────┘              └──────────────┘
```

### Step 1: Get RabbitMQ Credentials

```bash
./devstack vault-show-password rabbitmq
```

### Step 2: Install amqplib

```bash
npm install amqplib
```

### Step 3: Producer Code

```javascript
const amqp = require('amqplib');

async function sendMessage() {
    // Connect to RabbitMQ
    const connection = await amqp.connect({
        hostname: 'localhost',
        port: 5672,
        username: 'devuser',
        password: 'YOUR_RABBITMQ_PASSWORD',  // From vault-show-password
        vhost: 'dev_vhost'
    });

    const channel = await connection.createChannel();
    const queue = 'my_queue';

    // Create queue if it doesn't exist
    await channel.assertQueue(queue, { durable: true });

    // Send message
    const message = { task: 'process_order', orderId: 123 };
    channel.sendToQueue(queue, Buffer.from(JSON.stringify(message)));
    console.log('Sent:', message);

    await channel.close();
    await connection.close();
}

sendMessage();
```

### Step 4: Consumer Code

```javascript
const amqp = require('amqplib');

async function consumeMessages() {
    const connection = await amqp.connect({
        hostname: 'localhost',
        port: 5672,
        username: 'devuser',
        password: 'YOUR_RABBITMQ_PASSWORD',
        vhost: 'dev_vhost'
    });

    const channel = await connection.createChannel();
    const queue = 'my_queue';

    await channel.assertQueue(queue, { durable: true });
    console.log('Waiting for messages...');

    channel.consume(queue, (msg) => {
        const content = JSON.parse(msg.content.toString());
        console.log('Received:', content);
        channel.ack(msg);  // Acknowledge message
    });
}

consumeMessages();
```

### Step 5: Monitor in RabbitMQ UI

Open http://localhost:15672 and login with the credentials from `vault-show-password rabbitmq`.

---

## Use Case 4: Set Up Local Development Database

**Goal:** Create a fresh database for your project with proper isolation.

### The Setup

```
┌─────────────────────────────────────────────────┐
│              DevStack PostgreSQL                │
│                                                 │
│  ┌─────────────┐  ┌─────────────┐              │
│  │   devdb     │  │  myproject  │  ◀── New DB  │
│  │  (default)  │  │   (yours)   │              │
│  └─────────────┘  └─────────────┘              │
└─────────────────────────────────────────────────┘
```

### Step 1: Connect to PostgreSQL

```bash
./devstack shell postgres
```

### Step 2: Create Your Database

```sql
-- Inside postgres container
psql -U devuser devdb

-- Create new database
CREATE DATABASE myproject;

-- Create project-specific user (optional)
CREATE USER myproject_user WITH PASSWORD 'mypassword';
GRANT ALL PRIVILEGES ON DATABASE myproject TO myproject_user;

-- Verify
\l  -- List databases
```

### Step 3: Connect from Your App

```
postgresql://myproject_user:mypassword@localhost:5432/myproject
```

### Alternative: Use the Default Database

For simpler setups, just use the default `devdb` database:

```bash
# Get default credentials
./devstack vault-show-password postgres

# Connection string
postgresql://devuser:PASSWORD@localhost:5432/devdb
```

---

## Use Case 5: Use Vault Secrets in Your App

**Goal:** Fetch secrets from Vault at runtime instead of hardcoding.

### The Pattern

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Your App    │────▶│    Vault     │────▶│   Secrets    │
│   starts     │     │   :8200      │     │ (passwords)  │
└──────────────┘     └──────────────┘     └──────────────┘
        │                                        │
        └─────────────── uses ──────────────────┘
```

### Option A: Environment Variables (Simplest)

```bash
# Load all secrets into shell environment
source scripts/load-vault-env.sh

# Now use in your app
echo $POSTGRES_PASSWORD
echo $MYSQL_PASSWORD
echo $REDIS_PASSWORD
```

### Option B: Fetch at Runtime (Python)

```python
import hvac  # pip install hvac

# Initialize Vault client
client = hvac.Client(url='http://localhost:8200')

# Read token (for development)
with open('/Users/YOU/.config/vault/root-token') as f:
    client.token = f.read().strip()

# Fetch PostgreSQL credentials
secret = client.secrets.kv.v2.read_secret_version(path='postgres')
credentials = secret['data']['data']

print(f"Username: {credentials['user']}")
print(f"Password: {credentials['password']}")
print(f"Database: {credentials['database']}")
```

### Option C: Fetch at Runtime (Go)

```go
package main

import (
    "fmt"
    vault "github.com/hashicorp/vault/api"
    "io/ioutil"
    "strings"
)

func main() {
    // Create Vault client
    client, _ := vault.NewClient(&vault.Config{
        Address: "http://localhost:8200",
    })

    // Read token
    token, _ := ioutil.ReadFile("/Users/YOU/.config/vault/root-token")
    client.SetToken(strings.TrimSpace(string(token)))

    // Fetch secret
    secret, _ := client.KVv2("secret").Get(nil, "postgres")
    data := secret.Data

    fmt.Printf("User: %s\n", data["user"])
    fmt.Printf("Password: %s\n", data["password"])
}
```

### Option D: Docker Container with Vault

For apps running in Docker alongside DevStack:

```yaml
# docker-compose.yml for your app
services:
  myapp:
    build: .
    environment:
      VAULT_ADDR: http://vault:8200
      VAULT_TOKEN: ${VAULT_TOKEN}
    networks:
      - devstack-core_vault-network
    depends_on:
      vault:
        condition: service_healthy

networks:
  devstack-core_vault-network:
    external: true
```

---

## Use Case 6: Monitor Your App with Grafana

**Goal:** Add custom metrics to your app and visualize them in Grafana.

### The Monitoring Stack

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Your App    │────▶│  Prometheus  │────▶│   Grafana    │
│  /metrics    │     │   :9090      │     │    :3001     │
└──────────────┘     └──────────────┘     └──────────────┘
     exposes           scrapes              visualizes
```

### Step 1: Start Full Profile

```bash
./devstack start --profile full
./devstack health | grep -E "(prometheus|grafana)"
```

### Step 2: Add Metrics to Your Python App

```python
from prometheus_client import Counter, Histogram, generate_latest
from flask import Flask, Response

app = Flask(__name__)

# Define metrics
REQUEST_COUNT = Counter(
    'myapp_requests_total',
    'Total requests',
    ['method', 'endpoint']
)

REQUEST_LATENCY = Histogram(
    'myapp_request_latency_seconds',
    'Request latency',
    ['endpoint']
)

@app.route('/api/users')
def get_users():
    REQUEST_COUNT.labels(method='GET', endpoint='/api/users').inc()
    with REQUEST_LATENCY.labels(endpoint='/api/users').time():
        # Your logic here
        return {"users": []}

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype='text/plain')
```

### Step 3: Configure Prometheus to Scrape Your App

Add to `configs/prometheus/prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'myapp'
    static_configs:
      - targets: ['host.docker.internal:5000']  # Your app port
```

Restart Prometheus:
```bash
docker compose restart prometheus
```

### Step 4: Create Grafana Dashboard

1. Open http://localhost:3001 (admin/admin)
2. Go to Dashboards → New Dashboard
3. Add a panel
4. Use these PromQL queries:

**Request Rate:**
```promql
rate(myapp_requests_total[5m])
```

**Latency (p95):**
```promql
histogram_quantile(0.95, rate(myapp_request_latency_seconds_bucket[5m]))
```

**Request Count by Endpoint:**
```promql
sum by (endpoint) (rate(myapp_requests_total[5m]))
```

### Step 5: View in Grafana

```
┌─────────────────────────────────────────────────────────┐
│  My Application Metrics                                 │
├─────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐               │
│  │ Request Rate    │  │ Latency (p95)   │               │
│  │     ▄▄▄▄        │  │    ▁▂▃▄         │               │
│  │   ▄█████▄       │  │  ▁▂███▃▁        │               │
│  │ 50 req/s        │  │ 120ms           │               │
│  └─────────────────┘  └─────────────────┘               │
└─────────────────────────────────────────────────────────┘
```

---

## Use Case 7: Run Integration Tests Against DevStack

**Goal:** Use DevStack as the backend for your integration tests.

### Test Setup Pattern

```
┌──────────────────────────────────────────────────────────┐
│                    Test Execution                        │
│  ┌────────────┐     ┌────────────┐     ┌────────────┐   │
│  │   Setup    │────▶│    Test    │────▶│  Teardown  │   │
│  │ (DevStack) │     │   (Your    │     │  (cleanup) │   │
│  │            │     │   tests)   │     │            │   │
│  └────────────┘     └────────────┘     └────────────┘   │
└──────────────────────────────────────────────────────────┘
```

### Step 1: Test Setup Script

```bash
#!/bin/bash
# test-setup.sh

# Start DevStack if not running
./devstack start --profile standard

# Wait for healthy
./devstack health || exit 1

# Get credentials
source scripts/load-vault-env.sh

# Export for tests
export TEST_POSTGRES_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:5432/${POSTGRES_DB}"
export TEST_REDIS_URL="redis://:${REDIS_PASSWORD}@localhost:6379"
```

### Step 2: Python pytest Example

```python
# conftest.py
import pytest
import os
import psycopg2

@pytest.fixture(scope="session")
def db_connection():
    """Provide database connection for tests."""
    conn = psycopg2.connect(os.environ['TEST_POSTGRES_URL'])
    yield conn
    conn.close()

@pytest.fixture(scope="function")
def clean_db(db_connection):
    """Clean database before each test."""
    cursor = db_connection.cursor()
    cursor.execute("TRUNCATE TABLE users CASCADE")
    db_connection.commit()
    yield
    db_connection.rollback()

# test_users.py
def test_create_user(db_connection, clean_db):
    cursor = db_connection.cursor()
    cursor.execute("INSERT INTO users (name) VALUES ('Alice')")
    db_connection.commit()

    cursor.execute("SELECT name FROM users")
    assert cursor.fetchone()[0] == 'Alice'
```

### Step 3: Run Tests

```bash
# Setup and run
source test-setup.sh
pytest tests/ -v

# Or in CI
./devstack start --profile standard
./devstack health
source scripts/load-vault-env.sh
pytest tests/ -v
./devstack stop
```

---

## Common Patterns

### Loading Credentials Pattern

```bash
# Best practice: Use environment variables
source scripts/load-vault-env.sh

# Access in any language:
# Python: os.environ['POSTGRES_PASSWORD']
# Go:     os.Getenv("POSTGRES_PASSWORD")
# Node:   process.env.POSTGRES_PASSWORD
# Rust:   std::env::var("POSTGRES_PASSWORD")
```

### Connection String Pattern

| Database | Connection String |
|----------|-------------------|
| PostgreSQL | `postgresql://USER:PASS@localhost:5432/DB` |
| MySQL | `mysql://USER:PASS@localhost:3306/DB` |
| MongoDB | `mongodb://USER:PASS@localhost:27017/DB` |
| Redis | `redis://:PASS@localhost:6379` |
| RabbitMQ | `amqp://USER:PASS@localhost:5672/vhost` |

### Health Check Pattern

```python
# Check all services before starting app
import requests

services = {
    'vault': 'http://localhost:8200/v1/sys/health',
    'postgres': None,  # Use connection test
    'redis': None,     # Use ping
}

for name, url in services.items():
    if url:
        resp = requests.get(url)
        assert resp.status_code == 200, f"{name} unhealthy"
```

---

## See Also

- [Getting Started](GETTING_STARTED.md) - Initial setup
- [CLI Reference](CLI_REFERENCE.md) - All commands
- [Glossary](GLOSSARY.md) - Term definitions
- [Learning Paths](LEARNING_PATHS.md) - Guided learning
