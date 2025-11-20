# HashiCorp Vault Configuration
# Development/Local Environment with File Storage Backend

# Storage backend - file storage for persistence
storage "file" {
  path = "/vault/data"
}

# Listener for HTTP API (TLS disabled for local dev)
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

# API address
api_addr = "http://127.0.0.1:8200"

# UI enabled
ui = true

# Default lease duration: 7 days
default_lease_ttl = "168h"

# Maximum lease duration: 30 days
max_lease_ttl = "720h"

# Disable mlock to avoid requiring IPC_LOCK capability in some environments
# Note: IPC_LOCK is still added in docker-compose for security, but this allows
# Vault to run without it if needed
disable_mlock = false

# Log level
log_level = "info"
