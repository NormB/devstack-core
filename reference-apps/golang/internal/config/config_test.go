package config

import (
	"os"
	"testing"
)

func TestLoad(t *testing.T) {
	tests := []struct {
		name     string
		envVars  map[string]string
		validate func(*testing.T, *Config)
	}{
		{
			name: "default values",
			envVars: map[string]string{
				"VAULT_ADDR":  "http://vault:8200",
				"VAULT_TOKEN": "test-token",
			},
			validate: func(t *testing.T, cfg *Config) {
				if cfg.HTTPPort != "8002" {
					t.Errorf("Expected HTTPPort 8002, got %s", cfg.HTTPPort)
				}
				if cfg.HTTPSPort != "8445" {
					t.Errorf("Expected HTTPSPort 8445, got %s", cfg.HTTPSPort)
				}
				if cfg.Environment != "development" {
					t.Errorf("Expected Environment development, got %s", cfg.Environment)
				}
				if cfg.Debug != true {
					t.Errorf("Expected Debug true (default), got %v", cfg.Debug)
				}
			},
		},
		{
			name: "custom http port",
			envVars: map[string]string{
				"HTTP_PORT":   "9000",
				"VAULT_ADDR":  "http://vault:8200",
				"VAULT_TOKEN": "test-token",
			},
			validate: func(t *testing.T, cfg *Config) {
				if cfg.HTTPPort != "9000" {
					t.Errorf("Expected HTTPPort 9000, got %s", cfg.HTTPPort)
				}
			},
		},
		{
			name: "custom vault address",
			envVars: map[string]string{
				"VAULT_ADDR":  "https://custom-vault:8200",
				"VAULT_TOKEN": "custom-token",
			},
			validate: func(t *testing.T, cfg *Config) {
				if cfg.VaultAddr != "https://custom-vault:8200" {
					t.Errorf("Expected VaultAddr https://custom-vault:8200, got %s", cfg.VaultAddr)
				}
				if cfg.VaultToken != "custom-token" {
					t.Errorf("Expected VaultToken custom-token, got %s", cfg.VaultToken)
				}
			},
		},
		{
			name: "debug mode enabled",
			envVars: map[string]string{
				"DEBUG":       "true",
				"VAULT_ADDR":  "http://vault:8200",
				"VAULT_TOKEN": "test-token",
			},
			validate: func(t *testing.T, cfg *Config) {
				if cfg.Debug != true {
					t.Errorf("Expected Debug true, got %v", cfg.Debug)
				}
			},
		},
		{
			name: "production environment",
			envVars: map[string]string{
				"ENVIRONMENT": "production",
				"VAULT_ADDR":  "http://vault:8200",
				"VAULT_TOKEN": "test-token",
			},
			validate: func(t *testing.T, cfg *Config) {
				if cfg.Environment != "production" {
					t.Errorf("Expected Environment production, got %s", cfg.Environment)
				}
			},
		},
		{
			name: "database configuration",
			envVars: map[string]string{
				"POSTGRES_HOST": "custom-pg",
				"POSTGRES_PORT": "5433",
				"MYSQL_HOST":    "custom-mysql",
				"MYSQL_PORT":    "3307",
				"MONGODB_HOST":  "custom-mongo",
				"MONGODB_PORT":  "27018",
				"VAULT_ADDR":    "http://vault:8200",
				"VAULT_TOKEN":   "test-token",
			},
			validate: func(t *testing.T, cfg *Config) {
				if cfg.PostgresHost != "custom-pg" {
					t.Errorf("Expected PostgresHost custom-pg, got %s", cfg.PostgresHost)
				}
				if cfg.PostgresPort != "5433" {
					t.Errorf("Expected PostgresPort 5433, got %s", cfg.PostgresPort)
				}
				if cfg.MySQLHost != "custom-mysql" {
					t.Errorf("Expected MySQLHost custom-mysql, got %s", cfg.MySQLHost)
				}
				if cfg.MySQLPort != "3307" {
					t.Errorf("Expected MySQLPort 3307, got %s", cfg.MySQLPort)
				}
				if cfg.MongoHost != "custom-mongo" {
					t.Errorf("Expected MongoHost custom-mongo, got %s", cfg.MongoHost)
				}
				if cfg.MongoPort != "27018" {
					t.Errorf("Expected MongoPort 27018, got %s", cfg.MongoPort)
				}
			},
		},
		{
			name: "redis configuration",
			envVars: map[string]string{
				"REDIS_HOST":  "custom-redis",
				"REDIS_PORT":  "6380",
				"VAULT_ADDR":  "http://vault:8200",
				"VAULT_TOKEN": "test-token",
			},
			validate: func(t *testing.T, cfg *Config) {
				if cfg.RedisHost != "custom-redis" {
					t.Errorf("Expected RedisHost custom-redis, got %s", cfg.RedisHost)
				}
				if cfg.RedisPort != "6380" {
					t.Errorf("Expected RedisPort 6380, got %s", cfg.RedisPort)
				}
			},
		},
		{
			name: "rabbitmq configuration",
			envVars: map[string]string{
				"RABBITMQ_HOST": "custom-rabbit",
				"RABBITMQ_PORT": "5673",
				"VAULT_ADDR":    "http://vault:8200",
				"VAULT_TOKEN":   "test-token",
			},
			validate: func(t *testing.T, cfg *Config) {
				if cfg.RabbitMQHost != "custom-rabbit" {
					t.Errorf("Expected RabbitMQHost custom-rabbit, got %s", cfg.RabbitMQHost)
				}
				if cfg.RabbitMQPort != "5673" {
					t.Errorf("Expected RabbitMQPort 5673, got %s", cfg.RabbitMQPort)
				}
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clear environment
			os.Clearenv()

			// Set test environment variables
			for k, v := range tt.envVars {
				os.Setenv(k, v)
			}

			// Load config
			cfg := Load()

			// Validate
			tt.validate(t, cfg)
		})
	}
}

func TestGetEnv(t *testing.T) {
	tests := []struct {
		name         string
		key          string
		defaultValue string
		envValue     string
		expected     string
	}{
		{
			name:         "environment variable exists",
			key:          "TEST_VAR",
			defaultValue: "default",
			envValue:     "custom",
			expected:     "custom",
		},
		{
			name:         "environment variable missing - use default",
			key:          "MISSING_VAR",
			defaultValue: "default_value",
			envValue:     "",
			expected:     "default_value",
		},
		{
			name:         "empty default value",
			key:          "ANOTHER_VAR",
			defaultValue: "",
			envValue:     "",
			expected:     "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Clear and set environment
			os.Unsetenv(tt.key)
			if tt.envValue != "" {
				os.Setenv(tt.key, tt.envValue)
			}

			result := getEnv(tt.key, tt.defaultValue)

			if result != tt.expected {
				t.Errorf("Expected %s, got %s", tt.expected, result)
			}

			// Cleanup
			os.Unsetenv(tt.key)
		})
	}
}

func TestConfigCompleteness(t *testing.T) {
	// Test that all required fields are populated
	os.Clearenv()
	os.Setenv("VAULT_ADDR", "http://vault:8200")
	os.Setenv("VAULT_TOKEN", "test-token")

	cfg := Load()

	// Verify all fields are set (even if to defaults)
	if cfg.Environment == "" {
		t.Error("Environment should not be empty")
	}
	if cfg.HTTPPort == "" {
		t.Error("HTTPPort should not be empty")
	}
	if cfg.HTTPSPort == "" {
		t.Error("HTTPSPort should not be empty")
	}
	if cfg.VaultAddr == "" {
		t.Error("VaultAddr should not be empty")
	}
	if cfg.VaultToken == "" {
		t.Error("VaultToken should not be empty")
	}
	if cfg.PostgresHost == "" {
		t.Error("PostgresHost should not be empty")
	}
	if cfg.PostgresPort == "" {
		t.Error("PostgresPort should not be empty")
	}
	if cfg.MySQLHost == "" {
		t.Error("MySQLHost should not be empty")
	}
	if cfg.MySQLPort == "" {
		t.Error("MySQLPort should not be empty")
	}
	if cfg.MongoHost == "" {
		t.Error("MongoHost should not be empty")
	}
	if cfg.MongoPort == "" {
		t.Error("MongoPort should not be empty")
	}
	if cfg.RedisHost == "" {
		t.Error("RedisHost should not be empty")
	}
	if cfg.RedisPort == "" {
		t.Error("RedisPort should not be empty")
	}
	if cfg.RabbitMQHost == "" {
		t.Error("RabbitMQHost should not be empty")
	}
	if cfg.RabbitMQPort == "" {
		t.Error("RabbitMQPort should not be empty")
	}
}
