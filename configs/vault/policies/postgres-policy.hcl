# PostgreSQL Service Policy
# This policy grants the PostgreSQL service minimal required access to Vault
# - Read PostgreSQL credentials from secret/data/postgres
# - Issue PostgreSQL TLS certificates from PKI

# Allow reading PostgreSQL credentials
path "secret/data/postgres" {
  capabilities = ["read"]
}

# Allow issuing PostgreSQL certificates
path "pki_int/issue/postgres-role" {
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
