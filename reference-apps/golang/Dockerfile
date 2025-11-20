# Build stage
FROM golang:1.24rc1-alpine AS builder

WORKDIR /build

# Install build dependencies
RUN apk add --no-cache git

# Copy go mod files
COPY go.mod go.sum ./
RUN GOTOOLCHAIN=auto go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux GOTOOLCHAIN=auto go build -a -installsuffix cgo -o api ./cmd/api

# Runtime stage
FROM alpine:latest

WORKDIR /app

# Install runtime dependencies (wget and jq for Vault integration)
RUN apk --no-cache add ca-certificates wget jq

# Copy binary from builder
COPY --from=builder /build/api .

# Copy startup scripts
COPY start.sh init.sh ./
RUN chmod +x start.sh init.sh

# Create non-root user and set ownership
RUN addgroup -g 1001 -S appgroup && \
    adduser -S appuser -u 1001 -G appgroup && \
    chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose ports (HTTP and HTTPS)
EXPOSE 8002 8445

# Run initialization script
CMD ["/app/init.sh"]
