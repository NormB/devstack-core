package handlers

import (
	"context"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"

	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/config"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/services"
)

// CacheHandler handles cache-related endpoints
type CacheHandler struct {
	cfg         *config.Config
	vaultClient *services.VaultClient
}

// NewCacheHandler creates a new cache handler
func NewCacheHandler(cfg *config.Config, vaultClient *services.VaultClient) *CacheHandler {
	return &CacheHandler{
		cfg:         cfg,
		vaultClient: vaultClient,
	}
}

func (ch *CacheHandler) getRedisClient(ctx context.Context) (*redis.Client, error) {
	// Get credentials from Vault
	creds, err := ch.vaultClient.GetSecret(ctx, "reference-api/redis-1")
	if err != nil {
		return nil, fmt.Errorf("failed to get Vault credentials: %w", err)
	}

	password, _ := creds["password"].(string)

	return redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", ch.cfg.RedisHost, ch.cfg.RedisPort),
		Password: password,
		DB:       0,
	}), nil
}

// GetCache retrieves a value from cache
func (ch *CacheHandler) GetCache(c *gin.Context) {
	key := c.Param("key")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rdb, err := ch.getRedisClient(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer rdb.Close()

	val, err := rdb.Get(ctx, key).Result()
	if err == redis.Nil {
		c.JSON(http.StatusOK, gin.H{
			"key":   key,
			"value": nil,
			"found": false,
		})
		return
	} else if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"key":   key,
		"value": val,
		"found": true,
	})
}

// SetCache sets a value in cache
func (ch *CacheHandler) SetCache(c *gin.Context) {
	key := c.Param("key")
	value := c.Query("value")
	ttlStr := c.DefaultQuery("ttl", "3600")

	ttl, err := strconv.Atoi(ttlStr)
	if err != nil {
		ttl = 3600
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rdb, err := ch.getRedisClient(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer rdb.Close()

	err = rdb.Set(ctx, key, value, time.Duration(ttl)*time.Second).Err()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"key":   key,
		"value": value,
		"ttl":   ttl,
	})
}

// DeleteCache deletes a value from cache
func (ch *CacheHandler) DeleteCache(c *gin.Context) {
	key := c.Param("key")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rdb, err := ch.getRedisClient(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer rdb.Close()

	deleted, err := rdb.Del(ctx, key).Result()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"key":     key,
		"deleted": deleted > 0,
	})
}
