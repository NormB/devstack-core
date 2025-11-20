#!/usr/bin/env bash

get_db_credential() {
    local service=$1
    local field=$2
    # Always use localhost for host-based testing (not container DNS)
    local vault_addr="http://localhost:8200"
    local vault_token=${VAULT_TOKEN:-$(cat ~/.config/vault/root-token 2>/dev/null || echo "")}

    if [ -z "$vault_token" ]; then
        echo ""  # Return empty if no token
        return
    fi

    curl -sf -H "X-Vault-Token: $vault_token" \
        "$vault_addr/v1/secret/data/$service" \
        | jq -r ".data.data.$field // empty" 2>/dev/null || echo ""
}

echo "Testing credential retrieval..."
user=$(get_db_credential postgres user)
echo "User: [$user]"
password=$(get_db_credential postgres password)
echo "Password: [$password]"
database=$(get_db_credential postgres database)
echo "Database: [$database]"
