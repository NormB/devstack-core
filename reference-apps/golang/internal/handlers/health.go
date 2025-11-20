package handlers

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
	"github.com/jackc/pgx/v5"
	amqp "github.com/rabbitmq/amqp091-go"
	"github.com/redis/go-redis/v9"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/config"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/services"
)

// HealthHandler handles all health check endpoints
type HealthHandler struct {
	cfg         *config.Config
	vaultClient *services.VaultClient
}

// NewHealthHandler creates a new health handler
func NewHealthHandler(cfg *config.Config, vaultClient *services.VaultClient) *HealthHandler {
	return &HealthHandler{
		cfg:         cfg,
		vaultClient: vaultClient,
	}
}

// SimpleHealth returns a simple OK status
func (h *HealthHandler) SimpleHealth(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status": "ok",
	})
}

// VaultHealth checks Vault health
func (h *HealthHandler) VaultHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	health, err := h.vaultClient.HealthCheck(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}

	status := "healthy"
	if sealed, ok := health["sealed"].(bool); ok && sealed {
		status = "unhealthy"
	}

	c.JSON(http.StatusOK, gin.H{
		"status": status,
		"vault":  health,
	})
}

// PostgresHealth checks PostgreSQL health
func (h *HealthHandler) PostgresHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Get credentials from Vault
	creds, err := h.vaultClient.GetSecret(ctx, "reference-api/postgres")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to get Vault credentials: %v", err),
		})
		return
	}

	user, _ := creds["user"].(string)
	password, _ := creds["password"].(string)
	database, _ := creds["database"].(string)

	connStr := fmt.Sprintf("postgres://%s:%s@%s:%s/%s",
		user, password, h.cfg.PostgresHost, h.cfg.PostgresPort, database)

	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}
	defer conn.Close(ctx)

	var version string
	err = conn.QueryRow(ctx, "SELECT version()").Scan(&version)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  "healthy",
		"version": version,
	})
}

// MySQLHealth checks MySQL health
func (h *HealthHandler) MySQLHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Get credentials from Vault
	creds, err := h.vaultClient.GetSecret(ctx, "reference-api/mysql")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to get Vault credentials: %v", err),
		})
		return
	}

	user, _ := creds["user"].(string)
	password, _ := creds["password"].(string)
	database, _ := creds["database"].(string)

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s",
		user, password, h.cfg.MySQLHost, h.cfg.MySQLPort, database)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}
	defer db.Close()

	var version string
	err = db.QueryRowContext(ctx, "SELECT VERSION()").Scan(&version)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status":  "healthy",
		"version": version,
	})
}

// MongoDBHealth checks MongoDB health
func (h *HealthHandler) MongoDBHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Get credentials from Vault
	creds, err := h.vaultClient.GetSecret(ctx, "reference-api/mongodb")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to get Vault credentials: %v", err),
		})
		return
	}

	user, _ := creds["user"].(string)
	password, _ := creds["password"].(string)

	uri := fmt.Sprintf("mongodb://%s:%s@%s:%s",
		user, password, h.cfg.MongoHost, h.cfg.MongoPort)

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}
	defer client.Disconnect(ctx)

	err = client.Ping(ctx, nil)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"status": "healthy",
	})
}

// RedisHealth checks Redis health
func (h *HealthHandler) RedisHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Get credentials from Vault
	creds, err := h.vaultClient.GetSecret(ctx, "reference-api/redis-1")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to get Vault credentials: %v", err),
		})
		return
	}

	password, _ := creds["password"].(string)

	rdb := redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", h.cfg.RedisHost, h.cfg.RedisPort),
		Password: password,
		DB:       0,
	})
	defer rdb.Close()

	pong, err := rdb.Ping(ctx).Result()
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}

	// Check cluster info
	clusterInfo, _ := rdb.ClusterInfo(ctx).Result()

	c.JSON(http.StatusOK, gin.H{
		"status":        "healthy",
		"ping":          pong,
		"cluster_state": clusterInfo,
	})
}

// RabbitMQHealth checks RabbitMQ health
func (h *HealthHandler) RabbitMQHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Get credentials from Vault
	creds, err := h.vaultClient.GetSecret(ctx, "reference-api/rabbitmq")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  fmt.Sprintf("failed to get Vault credentials: %v", err),
		})
		return
	}

	user, _ := creds["user"].(string)
	password, _ := creds["password"].(string)

	url := fmt.Sprintf("amqp://%s:%s@%s:%s/",
		user, password, h.cfg.RabbitMQHost, h.cfg.RabbitMQPort)

	conn, err := amqp.Dial(url)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"status": "unhealthy",
			"error":  err.Error(),
		})
		return
	}
	defer conn.Close()

	c.JSON(http.StatusOK, gin.H{
		"status": "healthy",
	})
}

// AllHealth checks all services
func (h *HealthHandler) AllHealth(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	services := make(map[string]interface{})

	// Check Vault
	vaultHealth, err := h.vaultClient.HealthCheck(ctx)
	if err != nil {
		services["vault"] = map[string]interface{}{"status": "unhealthy", "error": err.Error()}
	} else {
		services["vault"] = map[string]interface{}{"status": "healthy", "details": vaultHealth}
	}

	// Overall status
	overallStatus := "healthy"
	for _, service := range services {
		if serviceMap, ok := service.(map[string]interface{}); ok {
			if status, ok := serviceMap["status"].(string); ok && status == "unhealthy" {
				overallStatus = "degraded"
			}
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"status":   overallStatus,
		"services": services,
	})
}
