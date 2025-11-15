# Reference API Service Policy
# This policy grants reference applications minimal required access to Vault
# - Read credentials for all infrastructure services (postgres, mysql, mongodb, redis, rabbitmq)
# - Read Vault connection info
# Note: Reference apps need broad access for demonstration purposes

# Allow reading PostgreSQL credentials
path "secret/data/postgres" {
  capabilities = ["read"]
}

# Allow reading MySQL credentials
path "secret/data/mysql" {
  capabilities = ["read"]
}

# Allow reading MongoDB credentials
path "secret/data/mongodb" {
  capabilities = ["read"]
}

# Allow reading Redis credentials
path "secret/data/redis-1" {
  capabilities = ["read"]
}

# Allow reading RabbitMQ credentials
path "secret/data/rabbitmq" {
  capabilities = ["read"]
}

# Allow reading Vault service info (for health checks)
path "secret/data/vault" {
  capabilities = ["read"]
}

# Allow reading CA chain for certificate validation
path "pki_int/ca_chain" {
  capabilities = ["read"]
}

# Allow reading PKI CA certificate
path "pki_int/cert/ca" {
  capabilities = ["read"]
}
