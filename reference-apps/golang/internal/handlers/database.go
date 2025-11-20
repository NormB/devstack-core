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
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"

	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/config"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/services"
)

// DatabaseHandler handles database-related endpoints
type DatabaseHandler struct {
	cfg         *config.Config
	vaultClient *services.VaultClient
}

// NewDatabaseHandler creates a new database handler
func NewDatabaseHandler(cfg *config.Config, vaultClient *services.VaultClient) *DatabaseHandler {
	return &DatabaseHandler{
		cfg:         cfg,
		vaultClient: vaultClient,
	}
}

// PostgresQuery executes a PostgreSQL query
func (d *DatabaseHandler) PostgresQuery(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Get credentials from Vault
	creds, err := d.vaultClient.GetSecret(ctx, "reference-api/postgres")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": fmt.Sprintf("failed to get Vault credentials: %v", err),
		})
		return
	}

	user, _ := creds["user"].(string)
	password, _ := creds["password"].(string)
	database, _ := creds["database"].(string)

	connStr := fmt.Sprintf("postgres://%s:%s@%s:%s/%s",
		user, password, d.cfg.PostgresHost, d.cfg.PostgresPort, database)

	conn, err := pgx.Connect(ctx, connStr)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer conn.Close(ctx)

	var result string
	err = conn.QueryRow(ctx, "SELECT 'PostgreSQL connection successful' AS message").Scan(&result)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"database": "PostgreSQL",
		"message":  result,
		"host":     d.cfg.PostgresHost,
	})
}

// MySQLQuery executes a MySQL query
func (d *DatabaseHandler) MySQLQuery(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Get credentials from Vault
	creds, err := d.vaultClient.GetSecret(ctx, "reference-api/mysql")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": fmt.Sprintf("failed to get Vault credentials: %v", err),
		})
		return
	}

	user, _ := creds["user"].(string)
	password, _ := creds["password"].(string)
	database, _ := creds["database"].(string)

	dsn := fmt.Sprintf("%s:%s@tcp(%s:%s)/%s",
		user, password, d.cfg.MySQLHost, d.cfg.MySQLPort, database)

	db, err := sql.Open("mysql", dsn)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer db.Close()

	var result string
	err = db.QueryRowContext(ctx, "SELECT 'MySQL connection successful' AS message").Scan(&result)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"database": "MySQL",
		"message":  result,
		"host":     d.cfg.MySQLHost,
	})
}

// MongoDBQuery executes a MongoDB query
func (d *DatabaseHandler) MongoDBQuery(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	// Get credentials from Vault
	creds, err := d.vaultClient.GetSecret(ctx, "reference-api/mongodb")
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": fmt.Sprintf("failed to get Vault credentials: %v", err),
		})
		return
	}

	user, _ := creds["user"].(string)
	password, _ := creds["password"].(string)

	uri := fmt.Sprintf("mongodb://%s:%s@%s:%s",
		user, password, d.cfg.MongoHost, d.cfg.MongoPort)

	client, err := mongo.Connect(ctx, options.Client().ApplyURI(uri))
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer client.Disconnect(ctx)

	// Test query
	database := client.Database("test")
	collection := database.Collection("test")

	var result bson.M
	err = collection.FindOne(ctx, bson.M{}).Decode(&result)
	if err != nil && err != mongo.ErrNoDocuments {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"database": "MongoDB",
		"message":  "MongoDB connection successful",
		"host":     d.cfg.MongoHost,
	})
}
