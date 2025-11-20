# Redis Exporter Service Policy
# This policy grants Redis exporters minimal required access to Vault
# - Read Redis credentials for all 3 cluster nodes
# - Each exporter monitors one Redis node and needs its password

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
