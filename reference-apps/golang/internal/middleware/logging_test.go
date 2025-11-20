package middleware

import (
	"bytes"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/sirupsen/logrus"
)

func init() {
	// Set Gin to test mode
	gin.SetMode(gin.TestMode)
}

func TestLoggingMiddleware(t *testing.T) {
	t.Run("adds request ID to context and headers", func(t *testing.T) {
		logger := logrus.New()
		logger.SetOutput(&bytes.Buffer{}) // Discard logs for test

		router := gin.New()
		router.Use(LoggingMiddleware(logger))
		router.GET("/test", func(c *gin.Context) {
			requestID, exists := c.Get("request_id")
			if !exists {
				t.Error("request_id should exist in context")
			}
			if requestID == "" {
				t.Error("request_id should not be empty")
			}
			c.String(200, "OK")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		// Check response header
		requestID := w.Header().Get("X-Request-ID")
		if requestID == "" {
			t.Error("X-Request-ID header should be set")
		}

		// Verify UUID format (basic check)
		if len(requestID) < 32 {
			t.Errorf("Request ID seems too short: %s", requestID)
		}
	})

	t.Run("logs request information", func(t *testing.T) {
		var logBuffer bytes.Buffer
		logger := logrus.New()
		logger.SetOutput(&logBuffer)
		logger.SetFormatter(&logrus.JSONFormatter{})

		router := gin.New()
		router.Use(LoggingMiddleware(logger))
		router.GET("/test/path", func(c *gin.Context) {
			c.String(200, "OK")
		})

		req := httptest.NewRequest("GET", "/test/path", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		logOutput := logBuffer.String()

		// Verify log contains expected fields
		if !strings.Contains(logOutput, "request_id") {
			t.Error("Log should contain request_id field")
		}
		if !strings.Contains(logOutput, "method") {
			t.Error("Log should contain method field")
		}
		if !strings.Contains(logOutput, "path") {
			t.Error("Log should contain path field")
		}
		if !strings.Contains(logOutput, "status") {
			t.Error("Log should contain status field")
		}
		if !strings.Contains(logOutput, "duration") {
			t.Error("Log should contain duration field")
		}
	})

	t.Run("logs different HTTP methods", func(t *testing.T) {
		methods := []string{"GET", "POST", "PUT", "DELETE", "PATCH"}

		for _, method := range methods {
			t.Run(method, func(t *testing.T) {
				var logBuffer bytes.Buffer
				logger := logrus.New()
				logger.SetOutput(&logBuffer)

				router := gin.New()
				router.Use(LoggingMiddleware(logger))
				router.Handle(method, "/test", func(c *gin.Context) {
					c.String(200, "OK")
				})

				req := httptest.NewRequest(method, "/test", nil)
				w := httptest.NewRecorder()

				router.ServeHTTP(w, req)

				logOutput := logBuffer.String()
				if !strings.Contains(logOutput, method) {
					t.Errorf("Log should contain method %s", method)
				}
			})
		}
	})

	t.Run("logs different status codes", func(t *testing.T) {
		statusCodes := []int{200, 201, 400, 404, 500}

		for _, code := range statusCodes {
			t.Run(http.StatusText(code), func(t *testing.T) {
				var logBuffer bytes.Buffer
				logger := logrus.New()
				logger.SetOutput(&logBuffer)

				router := gin.New()
				router.Use(LoggingMiddleware(logger))
				router.GET("/test", func(c *gin.Context) {
					c.String(code, "Response")
				})

				req := httptest.NewRequest("GET", "/test", nil)
				w := httptest.NewRecorder()

				router.ServeHTTP(w, req)

				if w.Code != code {
					t.Errorf("Expected status %d, got %d", code, w.Code)
				}

				logOutput := logBuffer.String()
				if logOutput == "" {
					t.Error("Should have logged the request")
				}
			})
		}
	})

	t.Run("measures request duration", func(t *testing.T) {
		var logBuffer bytes.Buffer
		logger := logrus.New()
		logger.SetOutput(&logBuffer)
		logger.SetFormatter(&logrus.JSONFormatter{})

		router := gin.New()
		router.Use(LoggingMiddleware(logger))
		router.GET("/test", func(c *gin.Context) {
			// Add small delay
			c.String(200, "OK")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		logOutput := logBuffer.String()
		if !strings.Contains(logOutput, "duration") {
			t.Error("Log should contain duration measurement")
		}
	})
}

func TestCORSMiddleware(t *testing.T) {
	t.Run("sets CORS headers", func(t *testing.T) {
		router := gin.New()
		router.Use(CORSMiddleware())
		router.GET("/test", func(c *gin.Context) {
			c.String(200, "OK")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		headers := w.Header()

		// Check required CORS headers
		if headers.Get("Access-Control-Allow-Origin") == "" {
			t.Error("Access-Control-Allow-Origin header should be set")
		}
		if headers.Get("Access-Control-Allow-Methods") == "" {
			t.Error("Access-Control-Allow-Methods header should be set")
		}
		if headers.Get("Access-Control-Allow-Headers") == "" {
			t.Error("Access-Control-Allow-Headers header should be set")
		}
	})

	t.Run("handles OPTIONS preflight request", func(t *testing.T) {
		router := gin.New()
		router.Use(CORSMiddleware())
		router.POST("/test", func(c *gin.Context) {
			c.String(200, "OK")
		})

		req := httptest.NewRequest("OPTIONS", "/test", nil)
		req.Header.Set("Access-Control-Request-Method", "POST")
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		if w.Code != 204 {
			t.Errorf("Expected status 204 for OPTIONS, got %d", w.Code)
		}

		headers := w.Header()
		if headers.Get("Access-Control-Allow-Methods") == "" {
			t.Error("OPTIONS response should include allowed methods")
		}
	})

	t.Run("allows credentials", func(t *testing.T) {
		router := gin.New()
		router.Use(CORSMiddleware())
		router.GET("/test", func(c *gin.Context) {
			c.String(200, "OK")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		credentials := w.Header().Get("Access-Control-Allow-Credentials")
		if credentials != "true" {
			t.Error("Access-Control-Allow-Credentials should be true")
		}
	})

	t.Run("sets max age for preflight cache", func(t *testing.T) {
		router := gin.New()
		router.Use(CORSMiddleware())
		router.GET("/test", func(c *gin.Context) {
			c.String(200, "OK")
		})

		req := httptest.NewRequest("OPTIONS", "/test", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		maxAge := w.Header().Get("Access-Control-Max-Age")
		if maxAge != "600" {
			t.Errorf("Expected Max-Age 600, got %s", maxAge)
		}
	})

	t.Run("allows standard headers", func(t *testing.T) {
		router := gin.New()
		router.Use(CORSMiddleware())
		router.GET("/test", func(c *gin.Context) {
			c.String(200, "OK")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		allowedHeaders := w.Header().Get("Access-Control-Allow-Headers")

		// Check for essential headers
		expectedHeaders := []string{"Content-Type", "Authorization", "X-Request-ID"}
		for _, header := range expectedHeaders {
			if !strings.Contains(allowedHeaders, header) {
				t.Errorf("Allowed headers should include %s", header)
			}
		}
	})

	t.Run("passes through to next handler", func(t *testing.T) {
		handlerCalled := false

		router := gin.New()
		router.Use(CORSMiddleware())
		router.GET("/test", func(c *gin.Context) {
			handlerCalled = true
			c.String(200, "OK")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		if !handlerCalled {
			t.Error("CORS middleware should call next handler")
		}
	})
}

func TestMiddlewareIntegration(t *testing.T) {
	t.Run("logging and CORS work together", func(t *testing.T) {
		logger := logrus.New()
		logger.SetOutput(&bytes.Buffer{})

		router := gin.New()
		router.Use(LoggingMiddleware(logger))
		router.Use(CORSMiddleware())
		router.GET("/test", func(c *gin.Context) {
			c.String(200, "OK")
		})

		req := httptest.NewRequest("GET", "/test", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		// Should have both request ID and CORS headers
		if w.Header().Get("X-Request-ID") == "" {
			t.Error("Should have request ID from logging middleware")
		}
		if w.Header().Get("Access-Control-Allow-Origin") == "" {
			t.Error("Should have CORS headers from CORS middleware")
		}
	})
}
