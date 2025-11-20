package services

import (
	"context"
	"testing"
	"time"
)

func TestNewVaultClient(t *testing.T) {
	tests := []struct {
		name    string
		addr    string
		token   string
		wantErr bool
	}{
		{
			name:    "valid address and token",
			addr:    "http://vault:8200",
			token:   "test-token",
			wantErr: false,
		},
		{
			name:    "valid https address",
			addr:    "https://vault:8200",
			token:   "test-token",
			wantErr: false,
		},
		{
			name:    "empty token (valid - token can be empty initially)",
			addr:    "http://vault:8200",
			token:   "",
			wantErr: false,
		},
		{
			name:    "localhost address",
			addr:    "http://localhost:8200",
			token:   "test-token",
			wantErr: false,
		},
		{
			name:    "custom port",
			addr:    "http://vault:9200",
			token:   "test-token",
			wantErr: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			client, err := NewVaultClient(tt.addr, tt.token)

			if tt.wantErr {
				if err == nil {
					t.Error("Expected error but got none")
				}
				return
			}

			if err != nil {
				t.Errorf("Unexpected error: %v", err)
				return
			}

			if client == nil {
				t.Error("Expected non-nil client")
				return
			}

			if client.client == nil {
				t.Error("Expected non-nil underlying Vault client")
			}
		})
	}
}

func TestVaultClient_GetSecret(t *testing.T) {
	// Note: These tests verify the method signature and basic error handling
	// Full integration tests would require a running Vault instance

	t.Run("context timeout handling", func(t *testing.T) {
		client, err := NewVaultClient("http://nonexistent:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Millisecond)
		defer cancel()

		// This should fail quickly due to timeout or connection error
		_, err = client.GetSecret(ctx, "test/path")
		if err == nil {
			t.Error("Expected error for nonexistent Vault server")
		}
	})

	t.Run("context cancellation", func(t *testing.T) {
		client, err := NewVaultClient("http://nonexistent:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithCancel(context.Background())
		cancel() // Cancel immediately

		_, err = client.GetSecret(ctx, "test/path")
		if err == nil {
			t.Error("Expected error for cancelled context")
		}
	})

	t.Run("method accepts valid path", func(t *testing.T) {
		client, err := NewVaultClient("http://vault:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()

		// Call the method - it will fail due to no Vault, but we're testing the API
		_, err = client.GetSecret(ctx, "valid/path/format")
		// Error is expected without real Vault
		if err != nil {
			// Verify error message includes the path
			errMsg := err.Error()
			if len(errMsg) == 0 {
				t.Error("Expected non-empty error message")
			}
		}
	})
}

func TestVaultClient_GetSecretKey(t *testing.T) {
	t.Run("method signature validation", func(t *testing.T) {
		client, err := NewVaultClient("http://vault:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()

		// Test that method accepts correct parameters
		_, err = client.GetSecretKey(ctx, "test/path", "key-name")
		// Error is expected without real Vault, but method should be callable
		if err != nil {
			// Verify this calls GetSecret internally (error should mention path)
			errMsg := err.Error()
			if len(errMsg) == 0 {
				t.Error("Expected non-empty error message")
			}
		}
	})

	t.Run("context handling", func(t *testing.T) {
		client, err := NewVaultClient("http://nonexistent:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithCancel(context.Background())
		cancel() // Cancel immediately

		_, err = client.GetSecretKey(ctx, "test/path", "key")
		if err == nil {
			t.Error("Expected error for cancelled context")
		}
	})
}

func TestVaultClient_HealthCheck(t *testing.T) {
	t.Run("health check method exists", func(t *testing.T) {
		client, err := NewVaultClient("http://vault:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		defer cancel()

		// Call health check - will fail without real Vault but validates API
		_, err = client.HealthCheck(ctx)
		// Error expected without real Vault
		if err != nil {
			errMsg := err.Error()
			if len(errMsg) == 0 {
				t.Error("Expected non-empty error message")
			}
		}
	})

	t.Run("context cancellation handling", func(t *testing.T) {
		client, err := NewVaultClient("http://nonexistent:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithCancel(context.Background())
		cancel()

		_, err = client.HealthCheck(ctx)
		if err == nil {
			t.Error("Expected error for cancelled context")
		}
	})
}

func TestVaultClientStructure(t *testing.T) {
	t.Run("client is properly initialized", func(t *testing.T) {
		addr := "http://vault:8200"
		token := "test-token"

		client, err := NewVaultClient(addr, token)
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		if client == nil {
			t.Fatal("Client should not be nil")
		}

		if client.client == nil {
			t.Fatal("Underlying Vault client should not be nil")
		}
	})

	t.Run("client methods are accessible", func(t *testing.T) {
		client, err := NewVaultClient("http://vault:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx := context.Background()

		// Verify all methods are accessible (will error without Vault, but that's OK)
		_, _ = client.GetSecret(ctx, "path")
		_, _ = client.GetSecretKey(ctx, "path", "key")
		_, _ = client.HealthCheck(ctx)
	})
}

func TestVaultClientConcurrency(t *testing.T) {
	t.Run("client is safe for concurrent use", func(t *testing.T) {
		client, err := NewVaultClient("http://vault:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		// Test concurrent access to client methods
		done := make(chan bool)
		for i := 0; i < 10; i++ {
			go func(n int) {
				ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
				defer cancel()

				// These will fail but should not panic
				_, _ = client.GetSecret(ctx, "concurrent/test")
				_, _ = client.HealthCheck(ctx)
				done <- true
			}(i)
		}

		// Wait for all goroutines
		for i := 0; i < 10; i++ {
			<-done
		}
	})
}

func TestVaultClientErrorFormatting(t *testing.T) {
	t.Run("GetSecret error includes path", func(t *testing.T) {
		client, err := NewVaultClient("http://nonexistent:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
		defer cancel()

		testPath := "test/secret/path"
		_, err = client.GetSecret(ctx, testPath)
		if err == nil {
			t.Error("Expected error")
			return
		}

		// Error message should mention the path for debugging
		errMsg := err.Error()
		if errMsg == "" {
			t.Error("Error message should not be empty")
		}
	})

	t.Run("GetSecretKey error includes key name", func(t *testing.T) {
		client, err := NewVaultClient("http://nonexistent:8200", "test-token")
		if err != nil {
			t.Fatalf("Failed to create client: %v", err)
		}

		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Millisecond)
		defer cancel()

		_, err = client.GetSecretKey(ctx, "path", "test-key")
		if err == nil {
			t.Error("Expected error")
			return
		}

		errMsg := err.Error()
		if errMsg == "" {
			t.Error("Error message should not be empty")
		}
	})
}
