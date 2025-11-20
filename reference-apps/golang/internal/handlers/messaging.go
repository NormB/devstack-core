package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	amqp "github.com/rabbitmq/amqp091-go"

	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/config"
	"github.com/normbrandinger/devstack-core/reference-apps/golang/internal/services"
)

// MessagingHandler handles messaging-related endpoints
type MessagingHandler struct {
	cfg         *config.Config
	vaultClient *services.VaultClient
}

// NewMessagingHandler creates a new messaging handler
func NewMessagingHandler(cfg *config.Config, vaultClient *services.VaultClient) *MessagingHandler {
	return &MessagingHandler{
		cfg:         cfg,
		vaultClient: vaultClient,
	}
}

func (mh *MessagingHandler) getConnection(ctx context.Context) (*amqp.Connection, error) {
	creds, err := mh.vaultClient.GetSecret(ctx, "reference-api/rabbitmq")
	if err != nil {
		return nil, fmt.Errorf("failed to get Vault credentials: %w", err)
	}

	user, _ := creds["user"].(string)
	password, _ := creds["password"].(string)

	url := fmt.Sprintf("amqp://%s:%s@%s:%s/",
		user, password, mh.cfg.RabbitMQHost, mh.cfg.RabbitMQPort)

	return amqp.Dial(url)
}

// PublishMessage publishes a message to a queue
func (mh *MessagingHandler) PublishMessage(c *gin.Context) {
	queueName := c.Param("queue")

	var message map[string]interface{}
	if err := c.ShouldBindJSON(&message); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "invalid JSON payload",
		})
		return
	}

	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	conn, err := mh.getConnection(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer conn.Close()

	ch, err := conn.Channel()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer ch.Close()

	// Declare queue
	q, err := ch.QueueDeclare(
		queueName,
		true,  // durable
		false, // delete when unused
		false, // exclusive
		false, // no-wait
		nil,   // arguments
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	// Serialize message
	body, err := json.Marshal(message)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	// Publish message
	err = ch.PublishWithContext(
		ctx,
		"",     // exchange
		q.Name, // routing key
		false,  // mandatory
		false,  // immediate
		amqp.Publishing{
			ContentType: "application/json",
			Body:        body,
		},
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"queue":   queueName,
		"message": "published successfully",
	})
}

// QueueInfo returns information about a queue
func (mh *MessagingHandler) QueueInfo(c *gin.Context) {
	queueName := c.Param("queue_name")

	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	conn, err := mh.getConnection(ctx)
	if err != nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer conn.Close()

	ch, err := conn.Channel()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": err.Error(),
		})
		return
	}
	defer ch.Close()

	// Inspect queue
	q, err := ch.QueueInspect(queueName)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{
			"error": fmt.Sprintf("queue %s not found", queueName),
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"name":      q.Name,
		"messages":  q.Messages,
		"consumers": q.Consumers,
	})
}
