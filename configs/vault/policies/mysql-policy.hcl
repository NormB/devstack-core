# MySQL Service Policy
# This policy grants the MySQL service minimal required access to Vault
# - Read MySQL credentials from secret/data/mysql
# - Issue MySQL TLS certificates from PKI

# Allow reading MySQL credentials
path "secret/data/mysql" {
  capabilities = ["read"]
}

# Allow issuing MySQL certificates
path "pki_int/issue/mysql-role" {
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
