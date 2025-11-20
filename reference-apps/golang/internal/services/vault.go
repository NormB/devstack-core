package services

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

	vault "github.com/hashicorp/vault/api"
)

// VaultClient wraps the Vault API client
type VaultClient struct {
	client *vault.Client
}

// NewVaultClient creates a new Vault client
// Tries AppRole authentication first if appRoleDir is provided, falls back to token
func NewVaultClient(addr, token, appRoleDir string) (*VaultClient, error) {
	config := vault.DefaultConfig()
	config.Address = addr

	client, err := vault.NewClient(config)
	if err != nil {
		return nil, fmt.Errorf("failed to create Vault client: %w", err)
	}

	// Try AppRole authentication first
	if appRoleDir != "" {
		if _, err := os.Stat(appRoleDir); err == nil {
			clientToken, err := loginWithAppRole(client, appRoleDir)
			if err == nil {
				client.SetToken(clientToken)
				return &VaultClient{client: client}, nil
			}
			// If AppRole fails, fall back to token auth
			fmt.Printf("AppRole authentication failed: %v, falling back to token auth\n", err)
		}
	}

	// Use token-based authentication
	client.SetToken(token)

	return &VaultClient{client: client}, nil
}

// loginWithAppRole performs AppRole authentication
func loginWithAppRole(client *vault.Client, appRoleDir string) (string, error) {
	// Read role-id
	roleIDPath := filepath.Join(appRoleDir, "role-id")
	roleIDBytes, err := os.ReadFile(roleIDPath)
	if err != nil {
		return "", fmt.Errorf("failed to read role-id: %w", err)
	}
	roleID := string(roleIDBytes)

	// Read secret-id
	secretIDPath := filepath.Join(appRoleDir, "secret-id")
	secretIDBytes, err := os.ReadFile(secretIDPath)
	if err != nil {
		return "", fmt.Errorf("failed to read secret-id: %w", err)
	}
	secretID := string(secretIDBytes)

	// Login to Vault with AppRole
	data := map[string]interface{}{
		"role_id":   roleID,
		"secret_id": secretID,
	}

	secret, err := client.Logical().Write("auth/approle/login", data)
	if err != nil {
		return "", fmt.Errorf("AppRole login failed: %w", err)
	}

	if secret == nil || secret.Auth == nil || secret.Auth.ClientToken == "" {
		return "", fmt.Errorf("AppRole login returned no token")
	}

	return secret.Auth.ClientToken, nil
}

// GetSecret retrieves a secret from Vault KV v2
func (v *VaultClient) GetSecret(ctx context.Context, path string) (map[string]interface{}, error) {
	secret, err := v.client.KVv2("secret").Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("failed to read secret at %s: %w", path, err)
	}

	if secret == nil || secret.Data == nil {
		return nil, fmt.Errorf("no data found at %s", path)
	}

	return secret.Data, nil
}

// GetSecretKey retrieves a specific key from a secret
func (v *VaultClient) GetSecretKey(ctx context.Context, path, key string) (interface{}, error) {
	data, err := v.GetSecret(ctx, path)
	if err != nil {
		return nil, err
	}

	value, ok := data[key]
	if !ok {
		return nil, fmt.Errorf("key %s not found in secret %s", key, path)
	}

	return value, nil
}

// HealthCheck checks if Vault is accessible and unsealed
func (v *VaultClient) HealthCheck(ctx context.Context) (map[string]interface{}, error) {
	health, err := v.client.Sys().Health()
	if err != nil {
		return nil, fmt.Errorf("failed to check Vault health: %w", err)
	}

	return map[string]interface{}{
		"initialized": health.Initialized,
		"sealed":      health.Sealed,
		"standby":     health.Standby,
		"version":     health.Version,
	}, nil
}
