# Vector Service Policy
# This policy grants Vector minimal required access to Vault
# - Read credentials for PostgreSQL, MongoDB, and all 3 Redis nodes
# - Vector needs these credentials to monitor and collect logs from databases

# Allow reading PostgreSQL credentials
path "secret/data/postgres" {
  capabilities = ["read"]
}

# Allow reading MongoDB credentials
path "secret/data/mongodb" {
  capabilities = ["read"]
}

# Allow reading Redis node 1 credentials
path "secret/data/redis-1" {
  capabilities = ["read"]
}

# Allow reading Redis node 2 credentials
path "secret/data/redis-2" {
  capabilities = ["read"]
}

# Allow reading Redis node 3 credentials
path "secret/data/redis-3" {
  capabilities = ["read"]
}
