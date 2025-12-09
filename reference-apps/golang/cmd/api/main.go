// Package main provides the entry point for the DevStack Core Go reference API.
//
// This application demonstrates integration patterns with the DevStack Core
// infrastructure stack including Vault secrets management, database connections,
// Redis clustering, and RabbitMQ messaging.
//
// Architecture:
//   - Gin web framework for HTTP routing
//   - HashiCorp Vault for secrets management
//   - PostgreSQL, MySQL, MongoDB for database operations
//   - Redis cluster for distributed caching
//   - RabbitMQ for message queuing
//   - Prometheus for metrics collection
//   - Structured logging with Logrus
//
// This is a reference implementation for learning purposes only.
// Not intended for production use.
package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"github.com/sirupsen/logrus"

	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/config"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/handlers"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/middleware"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/services"
)

var (
	httpRequestsTotal = prometheus.NewCounterVec(
		prometheus.CounterOpts{
			Name: "http_requests_total",
			Help: "Total number of HTTP requests",
		},
		[]string{"method", "endpoint", "status"},
	)

	httpRequestDuration = prometheus.NewHistogramVec(
		prometheus.HistogramOpts{
			Name:    "http_request_duration_seconds",
			Help:    "HTTP request latency",
			Buckets: prometheus.DefBuckets,
		},
		[]string{"method", "endpoint"},
	)
)

// init registers Prometheus metrics collectors at package initialization time.
// These metrics are used to track HTTP request counts and latency.
func init() {
	prometheus.MustRegister(httpRequestsTotal)
	prometheus.MustRegister(httpRequestDuration)
}

// main is the application entry point.
//
// It performs the following initialization steps:
//  1. Loads configuration from environment variables
//  2. Configures structured logging with JSON format
//  3. Initializes Vault client and verifies connectivity
//  4. Sets up Gin router with middleware (logging, CORS, recovery)
//  5. Registers all API route handlers
//  6. Starts HTTP server in a goroutine
//  7. Waits for interrupt signal (SIGINT/SIGTERM)
//  8. Performs graceful shutdown with 5-second timeout
//
// The application exits cleanly on receiving termination signals.
func main() {
	// Load configuration
	cfg := config.Load()

	// Setup logger
	logger := logrus.New()
	logger.SetFormatter(&logrus.JSONFormatter{})
	if cfg.Debug {
		logger.SetLevel(logrus.DebugLevel)
	} else {
		logger.SetLevel(logrus.InfoLevel)
	}

	logger.Info("Starting Golang reference API")
	logger.Infof("Environment: %s", cfg.Environment)
	logger.Infof("Vault address: %s", cfg.VaultAddr)

	// Initialize Vault client
	vaultClient, err := services.NewVaultClient(cfg.VaultAddr, cfg.VaultToken, cfg.VaultAppRoleDir)
	if err != nil {
		logger.Fatalf("Failed to initialize Vault client: %v", err)
	}

	// Test Vault connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	_, err = vaultClient.HealthCheck(ctx)
	cancel()
	if err != nil {
		logger.Warnf("Vault health check failed: %v", err)
	} else {
		logger.Info("Vault connection successful")
	}

	// Setup Gin
	if !cfg.Debug {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(middleware.LoggingMiddleware(logger))
	router.Use(middleware.CORSMiddleware())

	// Initialize handlers
	healthHandler := handlers.NewHealthHandler(cfg, vaultClient)
	vaultHandler := handlers.NewVaultHandler(vaultClient)
	databaseHandler := handlers.NewDatabaseHandler(cfg, vaultClient)
	cacheHandler := handlers.NewCacheHandler(cfg, vaultClient)
	redisClusterHandler := handlers.NewRedisClusterHandler(cfg, vaultClient)
	messagingHandler := handlers.NewMessagingHandler(cfg, vaultClient)

	// Root endpoint
	router.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"name":        "DevStack Core Reference API",
			"version":     "1.1.0",
			"language":    "Go",
			"description": "Reference implementation for infrastructure integration",
			"docs":        "/docs",
			"health":      "/health/all",
			"metrics":     "/metrics",
			"security": gin.H{
				"cors": gin.H{
					"enabled":         true,
					"allowed_origins": "localhost:3000, localhost:8000, localhost:8002",
					"allowed_methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS",
					"credentials":     true,
					"max_age":         "600s",
				},
				"request_validation": gin.H{
					"max_request_size": "10MB",
					"allowed_content_types": []string{
						"application/json",
						"application/x-www-form-urlencoded",
						"multipart/form-data",
						"text/plain",
					},
				},
			},
			"redis_cluster": gin.H{
				"nodes":     "/redis/cluster/nodes",
				"slots":     "/redis/cluster/slots",
				"info":      "/redis/cluster/info",
				"node_info": "/redis/nodes/{node_name}/info",
			},
			"examples": gin.H{
				"vault":     "/examples/vault",
				"databases": "/examples/database",
				"cache":     "/examples/cache",
				"messaging": "/examples/messaging",
			},
			"note": "This is a reference implementation, not production code",
		})
	})

	// Health check routes
	health := router.Group("/health")
	{
		health.GET("/", healthHandler.SimpleHealth)
		health.GET("/vault", healthHandler.VaultHealth)
		health.GET("/postgres", healthHandler.PostgresHealth)
		health.GET("/mysql", healthHandler.MySQLHealth)
		health.GET("/mongodb", healthHandler.MongoDBHealth)
		health.GET("/redis", healthHandler.RedisHealth)
		health.GET("/rabbitmq", healthHandler.RabbitMQHealth)
		health.GET("/all", healthHandler.AllHealth)
	}

	// Vault example routes
	vault := router.Group("/examples/vault")
	{
		vault.GET("/secret/:service_name", vaultHandler.GetSecret)
		vault.GET("/secret/:service_name/:key", vaultHandler.GetSecretKey)
	}

	// Database example routes
	database := router.Group("/examples/database")
	{
		database.GET("/postgres/query", databaseHandler.PostgresQuery)
		database.GET("/mysql/query", databaseHandler.MySQLQuery)
		database.GET("/mongodb/query", databaseHandler.MongoDBQuery)
	}

	// Cache example routes
	cache := router.Group("/examples/cache")
	{
		cache.GET("/:key", cacheHandler.GetCache)
		cache.POST("/:key", cacheHandler.SetCache)
		cache.DELETE("/:key", cacheHandler.DeleteCache)
	}

	// Redis cluster routes
	redisGroup := router.Group("/redis")
	{
		redisGroup.GET("/cluster/nodes", redisClusterHandler.ClusterNodes)
		redisGroup.GET("/cluster/slots", redisClusterHandler.ClusterSlots)
		redisGroup.GET("/cluster/info", redisClusterHandler.ClusterInfo)
		redisGroup.GET("/nodes/:node_name/info", redisClusterHandler.NodeInfo)
	}

	// Messaging example routes
	messaging := router.Group("/examples/messaging")
	{
		messaging.POST("/publish/:queue", messagingHandler.PublishMessage)
		messaging.GET("/queue/:queue_name/info", messagingHandler.QueueInfo)
	}

	// Metrics endpoint
	router.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Create HTTP server
	addr := fmt.Sprintf(":%s", cfg.HTTPPort)
	srv := &http.Server{
		Addr:    addr,
		Handler: router,
	}

	// Start server in goroutine
	go func() {
		logger.Infof("Starting HTTP server on port %s", cfg.HTTPPort)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	logger.Info("Shutting down server...")

	// Graceful shutdown with 5 second timeout
	ctx, cancel = context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		logger.Fatalf("Server forced to shutdown: %v", err)
	}

	logger.Info("Server exited")
}
