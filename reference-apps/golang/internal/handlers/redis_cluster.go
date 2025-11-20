package handlers

import (
	"context"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"

	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/config"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/services"
)

// RedisClusterHandler handles Redis cluster-related endpoints
type RedisClusterHandler struct {
	cfg         *config.Config
	vaultClient *services.VaultClient
}

// NewRedisClusterHandler creates a new Redis cluster handler
func NewRedisClusterHandler(cfg *config.Config, vaultClient *services.VaultClient) *RedisClusterHandler {
	return &RedisClusterHandler{
		cfg:         cfg,
		vaultClient: vaultClient,
	}
}

func (rch *RedisClusterHandler) getRedisClient(ctx context.Context) (*redis.Client, error) {
	creds, err := rch.vaultClient.GetSecret(ctx, "reference-api/redis-1")
	if err != nil {
		return nil, fmt.Errorf("failed to get Vault credentials: %w", err)
	}

	password, _ := creds["password"].(string)

	return redis.NewClient(&redis.Options{
		Addr:     fmt.Sprintf("%s:%s", rch.cfg.RedisHost, rch.cfg.RedisPort),
		Password: password,
		DB:       0,
	}), nil
}

// ClusterNodes returns cluster nodes information
func (rch *RedisClusterHandler) ClusterNodes(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rdb, err := rch.getRedisClient(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer rdb.Close()

	nodesInfo, err := rdb.ClusterNodes(ctx).Result()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	// Parse nodes info
	nodes := []map[string]interface{}{}
	for _, line := range strings.Split(nodesInfo, "\n") {
		if line == "" {
			continue
		}
		parts := strings.Fields(line)
		if len(parts) >= 8 {
			node := map[string]interface{}{
				"id":      parts[0],
				"address": parts[1],
				"flags":   parts[2],
				"master":  parts[3],
				"ping":    parts[4],
				"pong":    parts[5],
				"epoch":   parts[6],
				"state":   parts[7],
			}
			if len(parts) > 8 {
				node["slots"] = parts[8:]
			}
			nodes = append(nodes, node)
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"nodes": nodes,
		"count": len(nodes),
	})
}

// ClusterSlots returns slot distribution
func (rch *RedisClusterHandler) ClusterSlots(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rdb, err := rch.getRedisClient(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer rdb.Close()

	slots, err := rdb.ClusterSlots(ctx).Result()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"total_slots": 16384,
		"slots":       slots,
	})
}

// ClusterInfo returns cluster information
func (rch *RedisClusterHandler) ClusterInfo(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rdb, err := rch.getRedisClient(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer rdb.Close()

	info, err := rdb.ClusterInfo(ctx).Result()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	// Parse cluster info
	infoMap := make(map[string]string)
	for _, line := range strings.Split(info, "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, ":", 2)
		if len(parts) == 2 {
			infoMap[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"cluster_info": infoMap,
	})
}

// NodeInfo returns information about a specific node
func (rch *RedisClusterHandler) NodeInfo(c *gin.Context) {
	nodeName := c.Param("node_name")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	rdb, err := rch.getRedisClient(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer rdb.Close()

	info, err := rdb.Info(ctx).Result()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"node": nodeName,
		"info": info,
	})
}
