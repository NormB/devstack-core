# MongoDB Service Policy
# This policy grants the MongoDB service minimal required access to Vault
# - Read MongoDB credentials from secret/data/mongodb
# - Issue MongoDB TLS certificates from PKI

# Allow reading MongoDB credentials
path "secret/data/mongodb" {
  capabilities = ["read"]
}

# Allow issuing MongoDB certificates
path "pki_int/issue/mongodb-role" {
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
