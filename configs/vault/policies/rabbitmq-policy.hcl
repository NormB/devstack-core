# RabbitMQ Service Policy
# This policy grants the RabbitMQ service minimal required access to Vault
# - Read RabbitMQ credentials from secret/data/rabbitmq
# - Issue RabbitMQ TLS certificates from PKI

# Allow reading RabbitMQ credentials
path "secret/data/rabbitmq" {
  capabilities = ["read"]
}

# Allow issuing RabbitMQ certificates
path "pki_int/issue/rabbitmq-role" {
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
