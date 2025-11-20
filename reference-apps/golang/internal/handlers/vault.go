package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/services"
)

// VaultHandler handles Vault-related endpoints
type VaultHandler struct {
	vaultClient *services.VaultClient
}

// NewVaultHandler creates a new Vault handler
func NewVaultHandler(vaultClient *services.VaultClient) *VaultHandler {
	return &VaultHandler{
		vaultClient: vaultClient,
	}
}

// GetSecret retrieves a secret from Vault
func (v *VaultHandler) GetSecret(c *gin.Context) {
	serviceName := c.Param("service_name")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	secret, err := v.vaultClient.GetSecret(ctx, "reference-api/"+serviceName)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"path":   "reference-api/" + serviceName,
		"secret": secret,
	})
}

// GetSecretKey retrieves a specific key from a secret
func (v *VaultHandler) GetSecretKey(c *gin.Context) {
	serviceName := c.Param("service_name")
	key := c.Param("key")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	value, err := v.vaultClient.GetSecretKey(ctx, "reference-api/"+serviceName, key)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"path":  "reference-api/" + serviceName,
		"key":   key,
		"value": value,
	})
}
