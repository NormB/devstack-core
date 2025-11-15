# Forgejo Service Policy
# This policy grants the Forgejo service minimal required access to Vault
# - Read Forgejo credentials from secret/data/forgejo
# - Read PostgreSQL credentials from secret/data/postgres (Forgejo uses PostgreSQL as database)
# - Issue Forgejo TLS certificates from PKI

# Allow reading Forgejo credentials
path "secret/data/forgejo" {
  capabilities = ["read"]
}

# Allow reading PostgreSQL credentials (Forgejo uses PostgreSQL as database)
path "secret/data/postgres" {
  capabilities = ["read"]
}

# Allow issuing Forgejo certificates
path "pki_int/issue/forgejo-role" {
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
