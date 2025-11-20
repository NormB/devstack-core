# Management Script Policy
# This policy grants the management script (manage_devstack.py) access to:
# - Read all service credentials for backup/restore operations
# - Read PKI certificates for verification
# - NO write access (read-only for operational safety)

# Allow reading all service credentials
path "secret/data/postgres" {
  capabilities = ["read"]
}

path "secret/data/mysql" {
  capabilities = ["read"]
}

path "secret/data/mongodb" {
  capabilities = ["read"]
}

path "secret/data/redis-1" {
  capabilities = ["read"]
}

path "secret/data/redis-2" {
  capabilities = ["read"]
}

path "secret/data/redis-3" {
  capabilities = ["read"]
}

path "secret/data/rabbitmq" {
  capabilities = ["read"]
}

path "secret/data/forgejo" {
  capabilities = ["read"]
}

path "secret/data/reference-api" {
  capabilities = ["read"]
}

# Allow reading PKI certificates for verification
path "pki_int/ca_chain" {
  capabilities = ["read"]
}

path "pki_int/cert/ca" {
  capabilities = ["read"]
}

# Allow listing secrets (useful for backup verification)
path "secret/metadata/*" {
  capabilities = ["list", "read"]
}
