package config

import (
	"os"
	"strconv"
)

// Config holds all application configuration
type Config struct {
	// Application
	Environment string
	Debug       bool
	HTTPPort    string
	HTTPSPort   string
	EnableTLS   bool

	// Vault
	VaultAddr       string
	VaultToken      string
	VaultAppRoleDir string

	// PostgreSQL
	PostgresHost     string
	PostgresPort     string
	PostgresUser     string
	PostgresPassword string
	PostgresDB       string

	// MySQL
	MySQLHost     string
	MySQLPort     string
	MySQLUser     string
	MySQLPassword string
	MySQLDB       string

	// MongoDB
	MongoHost     string
	MongoPort     string
	MongoUser     string
	MongoPassword string
	MongoDB       string

	// Redis
	RedisHost     string
	RedisPort     string
	RedisPassword string

	// RabbitMQ
	RabbitMQHost     string
	RabbitMQPort     string
	RabbitMQUser     string
	RabbitMQPassword string
}

// Load reads configuration from environment variables
func Load() *Config {
	return &Config{
		// Application
		Environment: getEnv("ENVIRONMENT", "development"),
		Debug:       getEnvBool("DEBUG", true),
		HTTPPort:    getEnv("HTTP_PORT", "8002"),
		HTTPSPort:   getEnv("HTTPS_PORT", "8445"),
		EnableTLS:   getEnvBool("GOLANG_API_ENABLE_TLS", false),

		// Vault
		VaultAddr:       getEnv("VAULT_ADDR", "http://vault:8200"),
		VaultToken:      getEnv("VAULT_TOKEN", ""),
		VaultAppRoleDir: getEnv("VAULT_APPROLE_DIR", ""),

		// PostgreSQL
		PostgresHost:     getEnv("POSTGRES_HOST", "postgres"),
		PostgresPort:     getEnv("POSTGRES_PORT", "5432"),
		PostgresUser:     getEnv("POSTGRES_USER", "appuser"),
		PostgresPassword: getEnv("POSTGRES_PASSWORD", ""),
		PostgresDB:       getEnv("POSTGRES_DB", "appdb"),

		// MySQL
		MySQLHost:     getEnv("MYSQL_HOST", "mysql"),
		MySQLPort:     getEnv("MYSQL_PORT", "3306"),
		MySQLUser:     getEnv("MYSQL_USER", "appuser"),
		MySQLPassword: getEnv("MYSQL_PASSWORD", ""),
		MySQLDB:       getEnv("MYSQL_DATABASE", "appdb"),

		// MongoDB
		MongoHost:     getEnv("MONGODB_HOST", "mongodb"),
		MongoPort:     getEnv("MONGODB_PORT", "27017"),
		MongoUser:     getEnv("MONGODB_USER", "appuser"),
		MongoPassword: getEnv("MONGODB_PASSWORD", ""),
		MongoDB:       getEnv("MONGODB_DATABASE", "appdb"),

		// Redis
		RedisHost:     getEnv("REDIS_HOST", "redis-1"),
		RedisPort:     getEnv("REDIS_PORT", "6379"),
		RedisPassword: getEnv("REDIS_PASSWORD", ""),

		// RabbitMQ
		RabbitMQHost:     getEnv("RABBITMQ_HOST", "rabbitmq"),
		RabbitMQPort:     getEnv("RABBITMQ_PORT", "5672"),
		RabbitMQUser:     getEnv("RABBITMQ_USER", "guest"),
		RabbitMQPassword: getEnv("RABBITMQ_PASSWORD", ""),
	}
}

func getEnv(key, defaultValue string) string {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	return value
}

func getEnvBool(key string, defaultValue bool) bool {
	value := os.Getenv(key)
	if value == "" {
		return defaultValue
	}
	boolValue, err := strconv.ParseBool(value)
	if err != nil {
		return defaultValue
	}
	return boolValue
}
