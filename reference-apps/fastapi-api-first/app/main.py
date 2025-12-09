"""
Main FastAPI Application (API-First Implementation)

Auto-generated from OpenAPI specification.
This implementation is generated from the OpenAPI spec and enhanced
with business logic to match the code-first implementation.
"""

from fastapi import FastAPI, Request
from fastapi.responses import Response
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import logging
import sys
import time
import uuid
from pythonjsonlogger import jsonlogger

from app.routers import (
    health_checks,
    vault_examples,
    database_examples,
    cache_examples,
    messaging_examples,
    redis_cluster
)
from app.config import settings
from app.middleware.exception_handlers import register_exception_handlers
from app.middleware.cache import cache_manager
from app.services.vault import vault_client

# Configure structured JSON logging (matches code-first implementation)
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

# Create FastAPI app
app = FastAPI(
    title="DevStack Core - Reference API (API-First)",
    version="1.1.0",
    description="API-First implementation generated from OpenAPI specification",
    docs_url="/docs",
    redoc_url="/redoc",
)

# Configure CORS
# In production, replace "*" with specific allowed origins
CORS_ORIGINS = [
    "http://localhost:3000",   # React/Next.js dev server
    "http://localhost:8000",   # FastAPI code-first
    "http://localhost:8001",   # FastAPI API-first
    "http://localhost:8080",   # Common dev port
    "http://127.0.0.1:3000",
    "http://127.0.0.1:8000",
    "http://127.0.0.1:8001",
    "http://127.0.0.1:8080",
]

if settings.DEBUG:
    CORS_ORIGINS = ["*"]

app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=not settings.DEBUG,
    allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization", "X-Request-ID", "X-API-Key"],
    expose_headers=["X-Request-ID", "X-RateLimit-Limit", "X-RateLimit-Remaining"],
    max_age=600,
)

# Add rate limiter to app state
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# Register custom exception handlers
register_exception_handlers(app)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    """Middleware to collect metrics and add request tracking"""
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id

    method = request.method
    endpoint = request.url.path

    # Track in-progress requests
    http_requests_in_progress.labels(method=method, endpoint=endpoint).inc()

    start_time = time.time()

    try:
        response = await call_next(request)
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

        # Log request with structured data (matches code-first implementation)
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

        # Add headers
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Response-Time"] = f"{duration:.3f}s"

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
        http_requests_in_progress.labels(method=method, endpoint=endpoint).dec()


# Include routers
app.include_router(health_checks.router)
app.include_router(vault_examples.router)
app.include_router(database_examples.router)
app.include_router(cache_examples.router)
app.include_router(messaging_examples.router)
app.include_router(redis_cluster.router)


@app.on_event("startup")
async def startup_event():
    """Application startup event handler."""
    # Set app info metric
    app_info.labels(version="1.1.0", name="api-first").set(1)

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
        "Starting DevStack Core Reference API (API-First)",
        extra={
            "vault_address": settings.VAULT_ADDR,
            "redis_cache_enabled": cache_manager.enabled,
            "version": "1.1.0"
        }
    )
    logger.info("Application ready")


@app.on_event("shutdown")
async def shutdown_event():
    """Application shutdown event handler."""
    # Close cache connection
    await cache_manager.close()
    logger.info("Shutting down API-First FastAPI application...")


@app.get("/")
@limiter.limit("100/minute")
async def root(request: Request):
    """Root endpoint with API information.

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
                "allowed_origins": "localhost:3000, localhost:8000, localhost:8080",
                "allowed_methods": "GET, POST, PUT, DELETE, PATCH, OPTIONS",
                "credentials": True,
                "max_age": "600s"
            },
            "rate_limiting": {
                "general_endpoints": "100/minute",
                "metrics_endpoint": "1000/minute",
                "health_checks": "200/minute"
            },
            "request_validation": {
                "max_request_size": "10MB",
                "allowed_content_types": [
                    "application/json",
                    "application/x-www-form-urlencoded",
                    "multipart/form-data",
                    "text/plain"
                ]
            },
            "circuit_breakers": {
                "enabled": True,
                "services": [
                    "vault",
                    "postgres",
                    "mysql",
                    "mongodb",
                    "redis",
                    "rabbitmq"
                ],
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
            "messaging": "/examples/messaging"
        },
        "note": "This is a reference implementation, not production code"
    }


@app.get("/metrics")
@limiter.limit("1000/minute")  # High limit for metrics scraping
async def metrics(request: Request):
    """Prometheus metrics endpoint"""
    return Response(
        content=generate_latest(),
        media_type=CONTENT_TYPE_LATEST
    )
