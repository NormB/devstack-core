# Redis Service Policy
# This policy grants Redis services minimal required access to Vault
# - Read Redis credentials from secret/data/redis-1
# - Issue Redis TLS certificates from PKI
# Note: All 3 Redis nodes share the same credentials and policy

# Allow reading Redis credentials
path "secret/data/redis-1" {
  capabilities = ["read"]
}

# Allow issuing Redis certificates
path "pki_int/issue/redis-role" {
  capabilities = ["create", "update"]
}

# Allow reading CA chain for certificate validation
path "pki_int/ca_chain" {
  capabilities = ["read"]
}

# Allow reading PKI CA certificate
path "pki_int/cert/ca" {
  capabilities = ["read"]
}
