# PGBouncer Service Policy
# This policy grants PGBouncer minimal required access to Vault
# - Read PostgreSQL credentials only
# - PGBouncer needs PostgreSQL credentials to configure connection pooling

# Allow reading PostgreSQL credentials
path "secret/data/postgres" {
  capabilities = ["read"]
}
