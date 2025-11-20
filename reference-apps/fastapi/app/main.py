"""
FastAPI Reference Application for DevStack Core Infrastructure

This application demonstrates how to integrate with the infrastructure services:
- HashiCorp Vault for secrets management
- PostgreSQL, MySQL, MongoDB for data storage
- Redis cluster for caching
- RabbitMQ for messaging

This is a REFERENCE IMPLEMENTATION for learning and testing.
Not intended for production use.
"""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from fastapi.middleware.cors import CORSMiddleware
import logging
import sys
import time
import uuid
from pythonjsonlogger import jsonlogger
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST

from app.routers import health, vault_demo, database_demo, cache_demo, messaging_demo, redis_cluster
from app.config import settings
from app.middleware.cache import cache_manager
from app.middleware.exception_handlers import register_exception_handlers
from app.services.vault import vault_client

# Configuration
MAX_REQUEST_SIZE = 10 * 1024 * 1024  # 10MB
ALLOWED_CONTENT_TYPES = [
    "application/json",
    "application/x-www-form-urlencoded",
    "multipart/form-data",
    "text/plain"
]

# Configure structured JSON logging
logHandler = logging.StreamHandler(sys.stdout)
formatter = jsonlogger.JsonFormatter(
    '%(asctime)s %(name)s %(levelname)s %(message)s %(request_id)s %(method)s %(path)s %(status_code)s %(duration_ms)s'
)
logHandler.setFormatter(formatter)
logger = logging.getLogger(__name__)
logger.addHandler(logHandler)
logger.setLevel(logging.INFO)

# Disable default basicConfig
logging.getLogger().handlers.clear()
logging.getLogger().addHandler(logHandler)

# Prometheus metrics
http_requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

http_request_duration_seconds = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint']
)

http_requests_in_progress = Gauge(
    'http_requests_in_progress',
    'HTTP requests in progress',
    ['method', 'endpoint']
)

app_info = Gauge(
    'app_info',
    'Application information',
    ['version', 'name']
)

# Initialize rate limiter
limiter = Limiter(key_func=get_remote_address)

# Create FastAPI application
app = FastAPI(
    title="DevStack Core - Reference API",
    description="Reference implementation showing infrastructure integration patterns",
    version="1.1.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS Configuration
# In production, replace "*" with specific allowed origins
CORS_ORIGINS = [
    "http://localhost:3000",  # React/Next.js dev server
    "http://localhost:8000",  # FastAPI (same origin)
    "http://localhost:8080",  # Common dev port
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8000",
    "http://127.0.0.1:8080",
]

# For development/testing, you can also allow all origins with "*"
# NEVER use "*" in production with credentials=True
if settings.DEBUG:
    CORS_ORIGINS = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=not settings.DEBUG,  # Only allow credentials with explicit origins
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=[
        "Content-Type",
        "Authorization",
        "X-Request-ID",
        "X-API-Key",
        "Accept",
        "Origin",
        "User-Agent",
        "DNT",
        "Cache-Control",
        "X-Requested-With",
    ],
    expose_headers=[
        "X-Request-ID",
        "X-RateLimit-Limit",
        "X-RateLimit-Remaining",
        "X-RateLimit-Reset",
    ],
    max_age=600,  # Cache preflight requests for 10 minutes
)

# Add rate limiter to app state
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Register custom exception handlers
register_exception_handlers(app)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    """Middleware to collect metrics and add request tracking"""
    # Generate request ID for correlation
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id

    # Extract endpoint path template (e.g., /users/{id} instead of /users/123)
    endpoint = request.url.path
    method = request.method

    # Track in-progress requests
    http_requests_in_progress.labels(method=method, endpoint=endpoint).inc()

    # Time the request
    start_time = time.time()

    try:
        # Process request
        response = await call_next(request)

        # Calculate duration
        duration = time.time() - start_time

        # Record metrics
        http_requests_total.labels(
            method=method,
            endpoint=endpoint,
            status=response.status_code
        ).inc()

        http_request_duration_seconds.labels(
            method=method,
            endpoint=endpoint
        ).observe(duration)

        # Log request with structured data
        logger.info(
            "HTTP request completed",
            extra={
                "request_id": request_id,
                "method": method,
                "path": endpoint,
                "status_code": response.status_code,
                "duration_ms": round(duration * 1000, 2)
            }
        )

        # Add request ID to response headers
        response.headers["X-Request-ID"] = request_id

        return response

    except Exception as e:
        # Record error metrics
        duration = time.time() - start_time
        http_requests_total.labels(
            method=method,
            endpoint=endpoint,
            status=500
        ).inc()

        # Log error with structured data
        logger.error(
            f"Request failed: {str(e)}",
            extra={
                "request_id": request_id,
                "method": method,
                "path": endpoint,
                "status_code": 500,
                "duration_ms": round(duration * 1000, 2)
            },
            exc_info=True
        )
        raise

    finally:
        # Decrement in-progress counter
        http_requests_in_progress.labels(method=method, endpoint=endpoint).dec()


@app.middleware("http")
async def request_validation_middleware(request: Request, call_next):
    """Middleware to validate request size and content-type"""

    # Skip validation for certain endpoints (GET requests, metrics, health checks)
    if request.method in ["GET", "HEAD", "OPTIONS"]:
        return await call_next(request)

    if request.url.path in ["/metrics", "/docs", "/redoc", "/openapi.json"]:
        return await call_next(request)

    if request.url.path.startswith("/health"):
        return await call_next(request)

    # Validate content-type for POST/PUT/PATCH requests
    if request.method in ["POST", "PUT", "PATCH"]:
        content_type = request.headers.get("content-type", "").split(";")[0].strip()

        # Allow requests without content-type if there's no body
        content_length = request.headers.get("content-length")
        if content_length and int(content_length) > 0:
            if not content_type:
                return JSONResponse(
                    status_code=400,
                    content={
                        "error": "Missing Content-Type header",
                        "detail": "Content-Type header is required for requests with body"
                    }
                )

            # Check if content-type is allowed
            allowed = any(
                content_type.startswith(allowed_type)
                for allowed_type in ALLOWED_CONTENT_TYPES
            )

            if not allowed:
                return JSONResponse(
                    status_code=415,
                    content={
                        "error": "Unsupported Media Type",
                        "detail": f"Content-Type '{content_type}' is not supported",
                        "allowed_types": ALLOWED_CONTENT_TYPES
                    }
                )

    # Validate request size
    content_length = request.headers.get("content-length")
    if content_length and int(content_length) > MAX_REQUEST_SIZE:
        return JSONResponse(
            status_code=413,
            content={
                "error": "Request Entity Too Large",
                "detail": f"Request size ({content_length} bytes) exceeds maximum allowed size ({MAX_REQUEST_SIZE} bytes)",
                "max_size_mb": MAX_REQUEST_SIZE / (1024 * 1024)
            }
        )

    return await call_next(request)


# Include routers
app.include_router(health.router, prefix="/health", tags=["Health Checks"])
app.include_router(redis_cluster.router, prefix="/redis", tags=["Redis Cluster"])
app.include_router(vault_demo.router, prefix="/examples/vault", tags=["Vault Examples"])
app.include_router(database_demo.router, prefix="/examples/database", tags=["Database Examples"])
app.include_router(cache_demo.router, prefix="/examples/cache", tags=["Cache Examples"])
app.include_router(messaging_demo.router, prefix="/examples/messaging", tags=["Messaging Examples"])


@app.get("/metrics")
@limiter.limit("1000/minute")  # High limit for metrics scraping
async def metrics(request: Request):
    """Prometheus metrics endpoint"""
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/")
@limiter.limit("100/minute")  # General endpoint limit
async def root(request: Request):
    """Root endpoint with API information

    Rate Limit: 100 requests per minute per IP
    """
    return {
        "name": "DevStack Core Reference API",
        "version": "1.1.0",
        "description": "Reference implementation for infrastructure integration",
        "docs": "/docs",
        "health": "/health/all",
        "metrics": "/metrics",
        "security": {
            "cors": {
                "enabled": True,
                "allowed_origins": "localhost:3000, localhost:8000, localhost:8080" if not settings.DEBUG else "all (*)",
                "allowed_methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS",
                "credentials": not settings.DEBUG,
                "max_age": "600s"
            },
            "rate_limiting": {
                "general_endpoints": "100/minute",
                "metrics_endpoint": "1000/minute",
                "health_checks": "200/minute"
            },
            "request_validation": {
                "max_request_size": "10MB",
                "allowed_content_types": ["application/json", "application/x-www-form-urlencoded", "multipart/form-data", "text/plain"]
            },
            "circuit_breakers": {
                "enabled": True,
                "services": ["vault", "postgres", "mysql", "mongodb", "redis", "rabbitmq"],
                "failure_threshold": 5,
                "reset_timeout": "60s"
            }
        },
        "redis_cluster": {
            "nodes": "/redis/cluster/nodes",
            "slots": "/redis/cluster/slots",
            "info": "/redis/cluster/info",
            "node_info": "/redis/nodes/{node_name}/info"
        },
        "examples": {
            "vault": "/examples/vault",
            "databases": "/examples/database",
            "cache": "/examples/cache",
            "messaging": "/examples/messaging",
        },
        "note": "This is a reference implementation, not production code"
    }


@app.on_event("startup")
async def startup_event():
    """Initialize services on startup"""
    # Set application info metric
    app_info.labels(version="1.1.0", name="colima-reference-api").set(1)

    # Initialize response caching with Redis
    try:
        # Get Redis password from Vault
        redis_creds = await vault_client.get_secret("redis-1")
        redis_password = redis_creds.get("password", "")
        redis_url = f"redis://:{redis_password}@{settings.REDIS_HOST}:{settings.REDIS_PORT}"
        await cache_manager.init(redis_url, prefix="cache:")
    except Exception as e:
        logger.error(f"Failed to initialize cache: {e}")
        logger.warning("Application will continue without caching")

    logger.info(
        "Starting DevStack Core Reference API",
        extra={
            "vault_address": settings.VAULT_ADDR,
            "redis_cache_enabled": cache_manager.enabled,
            "version": "1.0.0"
        }
    )
    logger.info("Application ready")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    # Close cache connection
    await cache_manager.close()
    logger.info("Shutting down DevStack Core Reference API")
