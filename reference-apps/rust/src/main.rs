use actix_web::{web, App, HttpResponse, HttpServer, Responder, middleware};
use actix_cors::Cors;
use serde::{Deserialize, Serialize};
use std::env;
use lazy_static::lazy_static;
use prometheus::{Encoder, TextEncoder, HistogramVec, CounterVec, Opts, Registry};
use mysql_async::prelude::Queryable;

// Response types
#[derive(Serialize, Deserialize)]
struct ApiInfo {
    name: String,
    version: String,
    language: String,
    framework: String,
    description: String,
    docs: String,
    health: String,
    metrics: String,
    redis_cluster: RedisClusterEndpoints,
    examples: ExampleEndpoints,
    note: String,
}

#[derive(Serialize, Deserialize)]
struct RedisClusterEndpoints {
    nodes: String,
    slots: String,
    info: String,
    node_info: String,
}

#[derive(Serialize, Deserialize)]
struct ExampleEndpoints {
    vault: String,
    databases: String,
    cache: String,
    messaging: String,
}

#[derive(Serialize, Deserialize)]
struct HealthResponse {
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    timestamp: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    version: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    details: Option<serde_json::Value>,
}

#[derive(Serialize, Deserialize)]
struct AllHealthResponse {
    status: String,
    services: serde_json::Map<String, serde_json::Value>,
}

#[derive(Serialize, Deserialize)]
struct VaultSecret {
    service: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    key: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct DatabaseQueryResponse {
    status: String,
    database: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct CacheResponse {
    status: String,
    key: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Deserialize)]
struct CacheSetRequest {
    value: String,
    #[serde(default)]
    ttl: Option<u64>,
}

#[derive(Serialize, Deserialize)]
struct MessagingResponse {
    status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    queue: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Deserialize)]
struct PublishMessageRequest {
    message: String,
}

// Prometheus metrics
lazy_static! {
    static ref REGISTRY: Registry = Registry::new();

    static ref HTTP_REQUESTS_TOTAL: CounterVec = CounterVec::new(
        Opts::new("http_requests_total", "Total HTTP requests"),
        &["method", "endpoint", "status"]
    ).expect("Failed to create HTTP_REQUESTS_TOTAL metric");

    static ref HTTP_REQUEST_DURATION: HistogramVec = HistogramVec::new(
        prometheus::HistogramOpts::new("http_request_duration_seconds", "HTTP request latency"),
        &["method", "endpoint"]
    ).expect("Failed to create HTTP_REQUEST_DURATION metric");
}

fn register_metrics() {
    REGISTRY.register(Box::new(HTTP_REQUESTS_TOTAL.clone())).ok();
    REGISTRY.register(Box::new(HTTP_REQUEST_DURATION.clone())).ok();
}

// Helper functions
fn get_env_or(key: &str, default: &str) -> String {
    env::var(key).unwrap_or_else(|_| default.to_string())
}

async fn get_vault_secret(service: &str) -> Result<serde_json::Value, String> {
    let vault_addr = get_env_or("VAULT_ADDR", "http://vault:8200");
    let vault_token = get_env_or("VAULT_TOKEN", "");

    let url = format!("{}/v1/secret/data/{}", vault_addr, service);

    let client = reqwest::Client::new();
    let response = client
        .get(&url)
        .header("X-Vault-Token", vault_token)
        .send()
        .await
        .map_err(|e| format!("Vault request failed: {}", e))?;

    if !response.status().is_success() {
        return Err(format!("Vault returned status: {}", response.status()));
    }

    let data: serde_json::Value = response
        .json()
        .await
        .map_err(|e| format!("Failed to parse Vault response: {}", e))?;

    Ok(data["data"]["data"].clone())
}

// Route handlers
async fn root() -> impl Responder {
    let info = ApiInfo {
        name: "DevStack Core Reference API".to_string(),
        version: "1.1.0".to_string(),
        language: "Rust".to_string(),
        framework: "Actix-web".to_string(),
        description: "Rust reference implementation for infrastructure integration".to_string(),
        docs: "/docs".to_string(),
        health: "/health/all".to_string(),
        metrics: "/metrics".to_string(),
        redis_cluster: RedisClusterEndpoints {
            nodes: "/redis/cluster/nodes".to_string(),
            slots: "/redis/cluster/slots".to_string(),
            info: "/redis/cluster/info".to_string(),
            node_info: "/redis/nodes/{node_name}/info".to_string(),
        },
        examples: ExampleEndpoints {
            vault: "/examples/vault".to_string(),
            databases: "/examples/database".to_string(),
            cache: "/examples/cache".to_string(),
            messaging: "/examples/messaging".to_string(),
        },
        note: "This is a reference implementation, not production code".to_string(),
    };
    HttpResponse::Ok().json(info)
}

// Health check handlers
async fn health_simple() -> impl Responder {
    let response = HealthResponse {
        status: "healthy".to_string(),
        timestamp: Some(chrono::Utc::now().to_rfc3339()),
        version: None,
        error: None,
        details: None,
    };
    HttpResponse::Ok().json(response)
}

async fn health_vault() -> impl Responder {
    let vault_addr = get_env_or("VAULT_ADDR", "http://vault:8200");

    match reqwest::get(format!("{}/v1/sys/health", vault_addr)).await {
        Ok(resp) if resp.status().is_success() => {
            HttpResponse::Ok().json(HealthResponse {
                status: "healthy".to_string(),
                timestamp: Some(chrono::Utc::now().to_rfc3339()),
                version: None,
                error: None,
                details: None,
            })
        }
        _ => {
            HttpResponse::ServiceUnavailable().json(HealthResponse {
                status: "unhealthy".to_string(),
                timestamp: Some(chrono::Utc::now().to_rfc3339()),
                version: None,
                error: Some("Vault unavailable".to_string()),
                details: None,
            })
        }
    }
}

async fn health_postgres() -> impl Responder {
    match check_postgres_health().await {
        Ok(response) => HttpResponse::Ok().json(response),
        Err(response) => HttpResponse::ServiceUnavailable().json(response),
    }
}

async fn check_postgres_health() -> Result<HealthResponse, HealthResponse> {
    // Get credentials from Vault
    let creds = get_vault_secret("postgres").await.map_err(|e| HealthResponse {
        status: "unhealthy".to_string(),
        timestamp: Some(chrono::Utc::now().to_rfc3339()),
        version: None,
        error: Some(format!("Failed to get credentials: {}", e)),
        details: None,
    })?;

    let host = get_env_or("POSTGRES_HOST", "postgres");
    let port = get_env_or("POSTGRES_PORT", "5432");
    // Fallback defaults match Vault bootstrap credentials
    let user = creds["user"].as_str().unwrap_or("dev_admin");
    let password = creds["password"].as_str().unwrap_or("changeme");
    let database = creds["database"].as_str().unwrap_or("dev_database");

    let conn_str = format!(
        "host={} port={} user={} password={} dbname={}",
        host, port, user, password, database
    );

    match tokio_postgres::connect(&conn_str, tokio_postgres::NoTls).await {
        Ok((client, connection)) => {
            tokio::spawn(async move {
                if let Err(e) = connection.await {
                    log::error!("PostgreSQL connection error: {}", e);
                }
            });

            match client.query_one("SELECT version()", &[]).await {
                Ok(row) => {
                    let version: String = row.get(0);
                    Ok(HealthResponse {
                        status: "healthy".to_string(),
                        timestamp: Some(chrono::Utc::now().to_rfc3339()),
                        version: Some(version.split(',').next().map(|s| s.to_string()).unwrap_or_else(|| "unknown".to_string())),
                        error: None,
                        details: None,
                    })
                }
                Err(e) => Err(HealthResponse {
                    status: "unhealthy".to_string(),
                    timestamp: Some(chrono::Utc::now().to_rfc3339()),
                    version: None,
                    error: Some(format!("Query failed: {}", e)),
                    details: None,
                }),
            }
        }
        Err(e) => Err(HealthResponse {
            status: "unhealthy".to_string(),
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            version: None,
            error: Some(format!("Connection failed: {}", e)),
            details: None,
        }),
    }
}

async fn health_mysql() -> impl Responder {
    match check_mysql_health().await {
        Ok(response) => HttpResponse::Ok().json(response),
        Err(response) => HttpResponse::ServiceUnavailable().json(response),
    }
}

async fn check_mysql_health() -> Result<HealthResponse, HealthResponse> {
    let creds = get_vault_secret("mysql").await.map_err(|e| HealthResponse {
        status: "unhealthy".to_string(),
        timestamp: Some(chrono::Utc::now().to_rfc3339()),
        version: None,
        error: Some(format!("Failed to get credentials: {}", e)),
        details: None,
    })?;

    let host = get_env_or("MYSQL_HOST", "mysql");
    let port: u16 = get_env_or("MYSQL_PORT", "3306").parse().unwrap_or(3306);
    // Fallback defaults match Vault bootstrap credentials
    let user = creds["user"].as_str().unwrap_or("dev_admin");
    let password = creds["password"].as_str().unwrap_or("changeme");
    let database = creds["database"].as_str().unwrap_or("dev_database");

    let opts = mysql_async::OptsBuilder::default()
        .ip_or_hostname(host)
        .tcp_port(port)
        .user(Some(user))
        .pass(Some(password))
        .db_name(Some(database));

    match mysql_async::Conn::new(opts).await {
        Ok(mut conn) => {
            match conn.query_first::<String, _>("SELECT VERSION()").await {
                Ok(Some(version)) => {
                    let _ = conn.disconnect().await;
                    Ok(HealthResponse {
                        status: "healthy".to_string(),
                        timestamp: Some(chrono::Utc::now().to_rfc3339()),
                        version: Some(version),
                        error: None,
                        details: None,
                    })
                }
                Ok(None) => {
                    let _ = conn.disconnect().await;
                    Err(HealthResponse {
                        status: "unhealthy".to_string(),
                        timestamp: Some(chrono::Utc::now().to_rfc3339()),
                        version: None,
                        error: Some("No version returned".to_string()),
                        details: None,
                    })
                }
                Err(e) => {
                    let _ = conn.disconnect().await;
                    Err(HealthResponse {
                        status: "unhealthy".to_string(),
                        timestamp: Some(chrono::Utc::now().to_rfc3339()),
                        version: None,
                        error: Some(format!("Query failed: {}", e)),
                        details: None,
                    })
                }
            }
        }
        Err(e) => Err(HealthResponse {
            status: "unhealthy".to_string(),
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            version: None,
            error: Some(format!("Connection failed: {}", e)),
            details: None,
        }),
    }
}

async fn health_mongodb() -> impl Responder {
    match check_mongodb_health().await {
        Ok(response) => HttpResponse::Ok().json(response),
        Err(response) => HttpResponse::ServiceUnavailable().json(response),
    }
}

async fn check_mongodb_health() -> Result<HealthResponse, HealthResponse> {
    let creds = get_vault_secret("mongodb").await.map_err(|e| HealthResponse {
        status: "unhealthy".to_string(),
        timestamp: Some(chrono::Utc::now().to_rfc3339()),
        version: None,
        error: Some(format!("Failed to get credentials: {}", e)),
        details: None,
    })?;

    let host = get_env_or("MONGODB_HOST", "mongodb");
    let port = get_env_or("MONGODB_PORT", "27017");
    // Fallback defaults match Vault bootstrap credentials
    let user = creds["user"].as_str().unwrap_or("dev_admin");
    let password = creds["password"].as_str().unwrap_or("changeme");

    let uri = format!("mongodb://{}:{}@{}:{}/?authSource=admin", user, password, host, port);

    match mongodb::Client::with_uri_str(&uri).await {
        Ok(client) => {
            match client.database("admin").run_command(mongodb::bson::doc! { "ping": 1 }).await {
                Ok(_) => {
                    Ok(HealthResponse {
                        status: "healthy".to_string(),
                        timestamp: Some(chrono::Utc::now().to_rfc3339()),
                        version: Some("MongoDB".to_string()),
                        error: None,
                        details: None,
                    })
                }
                Err(e) => Err(HealthResponse {
                    status: "unhealthy".to_string(),
                    timestamp: Some(chrono::Utc::now().to_rfc3339()),
                    version: None,
                    error: Some(format!("Ping failed: {}", e)),
                    details: None,
                }),
            }
        }
        Err(e) => Err(HealthResponse {
            status: "unhealthy".to_string(),
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            version: None,
            error: Some(format!("Connection failed: {}", e)),
            details: None,
        }),
    }
}

async fn health_redis() -> impl Responder {
    match check_redis_health().await {
        Ok(response) => HttpResponse::Ok().json(response),
        Err(response) => HttpResponse::ServiceUnavailable().json(response),
    }
}

async fn check_redis_health() -> Result<HealthResponse, HealthResponse> {
    let creds = get_vault_secret("redis-1").await.map_err(|e| HealthResponse {
        status: "unhealthy".to_string(),
        timestamp: Some(chrono::Utc::now().to_rfc3339()),
        version: None,
        error: Some(format!("Failed to get credentials: {}", e)),
        details: None,
    })?;

    let host = get_env_or("REDIS_HOST", "redis-1");
    let port = get_env_or("REDIS_PORT", "6379");
    let password = creds["password"].as_str().unwrap_or("");

    let url = format!("redis://:{}@{}:{}", password, host, port);

    match redis::Client::open(url) {
        Ok(client) => {
            match client.get_multiplexed_async_connection().await {
                Ok(mut conn) => {
                    match redis::cmd("PING").query_async::<String>(&mut conn).await {
                        Ok(_) => Ok(HealthResponse {
                            status: "healthy".to_string(),
                            timestamp: Some(chrono::Utc::now().to_rfc3339()),
                            version: None,
                            error: None,
                            details: None,
                        }),
                        Err(e) => Err(HealthResponse {
                            status: "unhealthy".to_string(),
                            timestamp: Some(chrono::Utc::now().to_rfc3339()),
                            version: None,
                            error: Some(format!("PING failed: {}", e)),
                            details: None,
                        }),
                    }
                }
                Err(e) => Err(HealthResponse {
                    status: "unhealthy".to_string(),
                    timestamp: Some(chrono::Utc::now().to_rfc3339()),
                    version: None,
                    error: Some(format!("Connection failed: {}", e)),
                    details: None,
                }),
            }
        }
        Err(e) => Err(HealthResponse {
            status: "unhealthy".to_string(),
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            version: None,
            error: Some(format!("Client creation failed: {}", e)),
            details: None,
        }),
    }
}

async fn health_rabbitmq() -> impl Responder {
    match check_rabbitmq_health().await {
        Ok(response) => HttpResponse::Ok().json(response),
        Err(response) => HttpResponse::ServiceUnavailable().json(response),
    }
}

async fn check_rabbitmq_health() -> Result<HealthResponse, HealthResponse> {
    let creds = get_vault_secret("rabbitmq").await.map_err(|e| HealthResponse {
        status: "unhealthy".to_string(),
        timestamp: Some(chrono::Utc::now().to_rfc3339()),
        version: None,
        error: Some(format!("Failed to get credentials: {}", e)),
        details: None,
    })?;

    let host = get_env_or("RABBITMQ_HOST", "rabbitmq");
    let port = get_env_or("RABBITMQ_PORT", "5672");
    let user = creds["user"].as_str().unwrap_or("devuser");
    let password = creds["password"].as_str().unwrap_or("");
    let vhost = creds["vhost"].as_str().unwrap_or("dev_vhost");

    let url = format!("amqp://{}:{}@{}:{}/{}", user, password, host, port, vhost);

    match lapin::Connection::connect(&url, lapin::ConnectionProperties::default()).await {
        Ok(conn) => {
            let _ = conn.close(0, "Health check complete").await;
            Ok(HealthResponse {
                status: "healthy".to_string(),
                timestamp: Some(chrono::Utc::now().to_rfc3339()),
                version: None,
                error: None,
                details: None,
            })
        }
        Err(e) => Err(HealthResponse {
            status: "unhealthy".to_string(),
            timestamp: Some(chrono::Utc::now().to_rfc3339()),
            version: None,
            error: Some(format!("Connection failed: {}", e)),
            details: None,
        }),
    }
}

async fn health_all() -> impl Responder {
    let mut services = serde_json::Map::new();

    // Check Vault
    match reqwest::get(format!("{}/v1/sys/health", get_env_or("VAULT_ADDR", "http://vault:8200"))).await {
        Ok(resp) if resp.status().is_success() => {
            services.insert("vault".to_string(), serde_json::json!({"status": "healthy"}));
        }
        _ => {
            services.insert("vault".to_string(), serde_json::json!({"status": "unhealthy"}));
        }
    }

    // Check PostgreSQL
    services.insert("postgres".to_string(), match check_postgres_health().await {
        Ok(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
        Err(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
    });

    // Check MySQL
    services.insert("mysql".to_string(), match check_mysql_health().await {
        Ok(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
        Err(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
    });

    // Check MongoDB
    services.insert("mongodb".to_string(), match check_mongodb_health().await {
        Ok(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
        Err(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
    });

    // Check Redis
    services.insert("redis".to_string(), match check_redis_health().await {
        Ok(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
        Err(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
    });

    // Check RabbitMQ
    services.insert("rabbitmq".to_string(), match check_rabbitmq_health().await {
        Ok(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
        Err(h) => serde_json::to_value(h).unwrap_or_else(|_| serde_json::json!({"status": "error", "error": "Serialization failed"})),
    });

    let all_healthy = services.values().all(|v| {
        v.get("status").and_then(|s| s.as_str()) == Some("healthy")
    });

    let response = AllHealthResponse {
        status: if all_healthy { "healthy" } else { "degraded" }.to_string(),
        services,
    };

    HttpResponse::Ok().json(response)
}

// Vault example handlers
async fn get_secret(path: web::Path<String>) -> impl Responder {
    let service_name = path.into_inner();

    match get_vault_secret(&service_name).await {
        Ok(data) => HttpResponse::Ok().json(VaultSecret {
            service: service_name,
            key: None,
            value: Some(data),
            error: None,
        }),
        Err(e) => HttpResponse::ServiceUnavailable().json(VaultSecret {
            service: service_name,
            key: None,
            value: None,
            error: Some(e),
        }),
    }
}

async fn get_secret_key(path: web::Path<(String, String)>) -> impl Responder {
    let (service_name, key) = path.into_inner();

    match get_vault_secret(&service_name).await {
        Ok(data) => {
            if let Some(value) = data.get(&key) {
                HttpResponse::Ok().json(VaultSecret {
                    service: service_name,
                    key: Some(key),
                    value: Some(value.clone()),
                    error: None,
                })
            } else {
                HttpResponse::NotFound().json(VaultSecret {
                    service: service_name,
                    key: Some(key),
                    value: None,
                    error: Some("Key not found".to_string()),
                })
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(VaultSecret {
            service: service_name,
            key: Some(key),
            value: None,
            error: Some(e),
        }),
    }
}

// Database example handlers
async fn postgres_query() -> impl Responder {
    match get_vault_secret("postgres").await {
        Ok(creds) => {
            let host = get_env_or("POSTGRES_HOST", "postgres");
            let port = get_env_or("POSTGRES_PORT", "5432");
            let user = creds["user"].as_str().unwrap_or("devuser");
            let password = creds["password"].as_str().unwrap_or("");
            let database = creds["database"].as_str().unwrap_or("devdb");

            let conn_str = format!("host={} port={} user={} password={} dbname={}", host, port, user, password, database);

            match tokio_postgres::connect(&conn_str, tokio_postgres::NoTls).await {
                Ok((client, connection)) => {
                    tokio::spawn(async move {
                        if let Err(e) = connection.await {
                            log::error!("PostgreSQL connection error: {}", e);
                        }
                    });

                    match client.query_one("SELECT NOW()::text, 'Hello from PostgreSQL!' as message", &[]).await {
                        Ok(row) => {
                            let timestamp: String = row.get(0);
                            let message: String = row.get(1);

                            HttpResponse::Ok().json(DatabaseQueryResponse {
                                status: "success".to_string(),
                                database: "PostgreSQL".to_string(),
                                result: Some(serde_json::json!({
                                    "timestamp": timestamp,
                                    "message": message
                                })),
                                error: None,
                            })
                        }
                        Err(e) => HttpResponse::InternalServerError().json(DatabaseQueryResponse {
                            status: "error".to_string(),
                            database: "PostgreSQL".to_string(),
                            result: None,
                            error: Some(format!("Query failed: {}", e)),
                        }),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(DatabaseQueryResponse {
                    status: "error".to_string(),
                    database: "PostgreSQL".to_string(),
                    result: None,
                    error: Some(format!("Connection failed: {}", e)),
                }),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(DatabaseQueryResponse {
            status: "error".to_string(),
            database: "PostgreSQL".to_string(),
            result: None,
            error: Some(e),
        }),
    }
}

async fn mysql_query() -> impl Responder {
    match get_vault_secret("mysql").await {
        Ok(creds) => {
            let host = get_env_or("MYSQL_HOST", "mysql");
            let port: u16 = get_env_or("MYSQL_PORT", "3306").parse().unwrap_or(3306);
            let user = creds["user"].as_str().unwrap_or("devuser");
            let password = creds["password"].as_str().unwrap_or("");
            let database = creds["database"].as_str().unwrap_or("devdb");

            let opts = mysql_async::OptsBuilder::default()
                .ip_or_hostname(host)
                .tcp_port(port)
                .user(Some(user))
                .pass(Some(password))
                .db_name(Some(database));

            match mysql_async::Conn::new(opts).await {
                Ok(mut conn) => {
                    match conn.query_first::<(String, String), _>("SELECT NOW(), 'Hello from MySQL!' as message").await {
                        Ok(Some((timestamp, message))) => {
                            let _ = conn.disconnect().await;
                            HttpResponse::Ok().json(DatabaseQueryResponse {
                                status: "success".to_string(),
                                database: "MySQL".to_string(),
                                result: Some(serde_json::json!({
                                    "timestamp": timestamp,
                                    "message": message
                                })),
                                error: None,
                            })
                        }
                        Ok(None) => {
                            let _ = conn.disconnect().await;
                            HttpResponse::InternalServerError().json(DatabaseQueryResponse {
                                status: "error".to_string(),
                                database: "MySQL".to_string(),
                                result: None,
                                error: Some("No result returned".to_string()),
                            })
                        }
                        Err(e) => {
                            let _ = conn.disconnect().await;
                            HttpResponse::InternalServerError().json(DatabaseQueryResponse {
                                status: "error".to_string(),
                                database: "MySQL".to_string(),
                                result: None,
                                error: Some(format!("Query failed: {}", e)),
                            })
                        }
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(DatabaseQueryResponse {
                    status: "error".to_string(),
                    database: "MySQL".to_string(),
                    result: None,
                    error: Some(format!("Connection failed: {}", e)),
                }),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(DatabaseQueryResponse {
            status: "error".to_string(),
            database: "MySQL".to_string(),
            result: None,
            error: Some(e),
        }),
    }
}

async fn mongodb_query() -> impl Responder {
    match get_vault_secret("mongodb").await {
        Ok(creds) => {
            let host = get_env_or("MONGODB_HOST", "mongodb");
            let port = get_env_or("MONGODB_PORT", "27017");
            let user = creds["user"].as_str().unwrap_or("devuser");
            let password = creds["password"].as_str().unwrap_or("");

            let uri = format!("mongodb://{}:{}@{}:{}/?authSource=admin", user, password, host, port);

            match mongodb::Client::with_uri_str(&uri).await {
                Ok(client) => {
                    let db = client.database("test");
                    let collection = db.collection::<mongodb::bson::Document>("test");

                    let doc = mongodb::bson::doc! {
                        "message": "Hello from MongoDB!",
                        "timestamp": chrono::Utc::now().to_rfc3339()
                    };

                    match collection.insert_one(doc.clone()).await {
                        Ok(_) => {
                            HttpResponse::Ok().json(DatabaseQueryResponse {
                                status: "success".to_string(),
                                database: "MongoDB".to_string(),
                                result: Some(serde_json::json!({
                                    "message": doc.get_str("message").unwrap_or("Unknown message"),
                                    "timestamp": doc.get_str("timestamp").unwrap_or("Unknown timestamp")
                                })),
                                error: None,
                            })
                        }
                        Err(e) => HttpResponse::InternalServerError().json(DatabaseQueryResponse {
                            status: "error".to_string(),
                            database: "MongoDB".to_string(),
                            result: None,
                            error: Some(format!("Insert failed: {}", e)),
                        }),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(DatabaseQueryResponse {
                    status: "error".to_string(),
                    database: "MongoDB".to_string(),
                    result: None,
                    error: Some(format!("Connection failed: {}", e)),
                }),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(DatabaseQueryResponse {
            status: "error".to_string(),
            database: "MongoDB".to_string(),
            result: None,
            error: Some(e),
        }),
    }
}

// Cache example handlers
async fn get_cache(path: web::Path<String>) -> impl Responder {
    let key = path.into_inner();

    match get_vault_secret("redis-1").await {
        Ok(creds) => {
            let host = get_env_or("REDIS_HOST", "redis-1");
            let port = get_env_or("REDIS_PORT", "6379");
            let password = creds["password"].as_str().unwrap_or("");

            let url = format!("redis://:{}@{}:{}", password, host, port);

            match redis::Client::open(url) {
                Ok(client) => {
                    match client.get_multiplexed_async_connection().await {
                        Ok(mut conn) => {
                            match redis::cmd("GET").arg(&key).query_async::<Option<String>>(&mut conn).await {
                                Ok(Some(value)) => HttpResponse::Ok().json(CacheResponse {
                                    status: "found".to_string(),
                                    key,
                                    value: Some(value),
                                    error: None,
                                }),
                                Ok(None) => HttpResponse::NotFound().json(CacheResponse {
                                    status: "not_found".to_string(),
                                    key,
                                    value: None,
                                    error: None,
                                }),
                                Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                                    status: "error".to_string(),
                                    key,
                                    value: None,
                                    error: Some(format!("GET failed: {}", e)),
                                }),
                            }
                        }
                        Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                            status: "error".to_string(),
                            key,
                            value: None,
                            error: Some(format!("Connection failed: {}", e)),
                        }),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                    status: "error".to_string(),
                    key,
                    value: None,
                    error: Some(format!("Client creation failed: {}", e)),
                }),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(CacheResponse {
            status: "error".to_string(),
            key,
            value: None,
            error: Some(e),
        }),
    }
}

async fn set_cache(path: web::Path<String>, req_body: web::Json<CacheSetRequest>) -> impl Responder {
    let key = path.into_inner();
    let value = &req_body.value;
    let ttl = req_body.ttl;

    match get_vault_secret("redis-1").await {
        Ok(creds) => {
            let host = get_env_or("REDIS_HOST", "redis-1");
            let port = get_env_or("REDIS_PORT", "6379");
            let password = creds["password"].as_str().unwrap_or("");

            let url = format!("redis://:{}@{}:{}", password, host, port);

            match redis::Client::open(url) {
                Ok(client) => {
                    match client.get_multiplexed_async_connection().await {
                        Ok(mut conn) => {
                            let result = if let Some(ttl_seconds) = ttl {
                                redis::cmd("SETEX").arg(&key).arg(ttl_seconds).arg(value).query_async::<String>(&mut conn).await
                            } else {
                                redis::cmd("SET").arg(&key).arg(value).query_async::<String>(&mut conn).await
                            };

                            match result {
                                Ok(_) => HttpResponse::Ok().json(CacheResponse {
                                    status: "stored".to_string(),
                                    key,
                                    value: Some(value.clone()),
                                    error: None,
                                }),
                                Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                                    status: "error".to_string(),
                                    key,
                                    value: None,
                                    error: Some(format!("SET failed: {}", e)),
                                }),
                            }
                        }
                        Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                            status: "error".to_string(),
                            key,
                            value: None,
                            error: Some(format!("Connection failed: {}", e)),
                        }),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                    status: "error".to_string(),
                    key,
                    value: None,
                    error: Some(format!("Client creation failed: {}", e)),
                }),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(CacheResponse {
            status: "error".to_string(),
            key,
            value: None,
            error: Some(e),
        }),
    }
}

async fn delete_cache(path: web::Path<String>) -> impl Responder {
    let key = path.into_inner();

    match get_vault_secret("redis-1").await {
        Ok(creds) => {
            let host = get_env_or("REDIS_HOST", "redis-1");
            let port = get_env_or("REDIS_PORT", "6379");
            let password = creds["password"].as_str().unwrap_or("");

            let url = format!("redis://:{}@{}:{}", password, host, port);

            match redis::Client::open(url) {
                Ok(client) => {
                    match client.get_multiplexed_async_connection().await {
                        Ok(mut conn) => {
                            match redis::cmd("DEL").arg(&key).query_async::<i32>(&mut conn).await {
                                Ok(count) => HttpResponse::Ok().json(CacheResponse {
                                    status: if count > 0 { "deleted" } else { "not_found" }.to_string(),
                                    key,
                                    value: None,
                                    error: None,
                                }),
                                Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                                    status: "error".to_string(),
                                    key,
                                    value: None,
                                    error: Some(format!("DEL failed: {}", e)),
                                }),
                            }
                        }
                        Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                            status: "error".to_string(),
                            key,
                            value: None,
                            error: Some(format!("Connection failed: {}", e)),
                        }),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(CacheResponse {
                    status: "error".to_string(),
                    key,
                    value: None,
                    error: Some(format!("Client creation failed: {}", e)),
                }),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(CacheResponse {
            status: "error".to_string(),
            key,
            value: None,
            error: Some(e),
        }),
    }
}

// Messaging example handlers
async fn publish_message(path: web::Path<String>, req_body: web::Json<PublishMessageRequest>) -> impl Responder {
    let queue = path.into_inner();
    let message = &req_body.message;

    match get_vault_secret("rabbitmq").await {
        Ok(creds) => {
            let host = get_env_or("RABBITMQ_HOST", "rabbitmq");
            let port = get_env_or("RABBITMQ_PORT", "5672");
            let user = creds["user"].as_str().unwrap_or("devuser");
            let password = creds["password"].as_str().unwrap_or("");
            let vhost = creds["vhost"].as_str().unwrap_or("dev_vhost");

            let url = format!("amqp://{}:{}@{}:{}/{}", user, password, host, port, vhost);

            match lapin::Connection::connect(&url, lapin::ConnectionProperties::default()).await {
                Ok(conn) => {
                    match conn.create_channel().await {
                        Ok(channel) => {
                            // Declare queue
                            match channel.queue_declare(
                                &queue,
                                lapin::options::QueueDeclareOptions::default(),
                                lapin::types::FieldTable::default(),
                            ).await {
                                Ok(_) => {
                                    // Publish message
                                    match channel.basic_publish(
                                        "",
                                        &queue,
                                        lapin::options::BasicPublishOptions::default(),
                                        message.as_bytes(),
                                        lapin::BasicProperties::default(),
                                    ).await {
                                        Ok(_) => {
                                            let _ = conn.close(0, "Done").await;
                                            HttpResponse::Ok().json(MessagingResponse {
                                                status: "published".to_string(),
                                                message: Some(message.clone()),
                                                queue: Some(queue),
                                                error: None,
                                            })
                                        }
                                        Err(e) => {
                                            let _ = conn.close(0, "Error").await;
                                            HttpResponse::InternalServerError().json(MessagingResponse {
                                                status: "error".to_string(),
                                                message: None,
                                                queue: Some(queue),
                                                error: Some(format!("Publish failed: {}", e)),
                                            })
                                        }
                                    }
                                }
                                Err(e) => {
                                    let _ = conn.close(0, "Error").await;
                                    HttpResponse::InternalServerError().json(MessagingResponse {
                                        status: "error".to_string(),
                                        message: None,
                                        queue: Some(queue),
                                        error: Some(format!("Queue declare failed: {}", e)),
                                    })
                                }
                            }
                        }
                        Err(e) => {
                            let _ = conn.close(0, "Error").await;
                            HttpResponse::InternalServerError().json(MessagingResponse {
                                status: "error".to_string(),
                                message: None,
                                queue: Some(queue),
                                error: Some(format!("Channel creation failed: {}", e)),
                            })
                        }
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(MessagingResponse {
                    status: "error".to_string(),
                    message: None,
                    queue: Some(queue),
                    error: Some(format!("Connection failed: {}", e)),
                }),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(MessagingResponse {
            status: "error".to_string(),
            message: None,
            queue: Some(queue),
            error: Some(e),
        }),
    }
}

async fn queue_info(path: web::Path<String>) -> impl Responder {
    let queue_name = path.into_inner();

    match get_vault_secret("rabbitmq").await {
        Ok(creds) => {
            let host = get_env_or("RABBITMQ_HOST", "rabbitmq");
            let port = get_env_or("RABBITMQ_PORT", "5672");
            let user = creds["user"].as_str().unwrap_or("devuser");
            let password = creds["password"].as_str().unwrap_or("");
            let vhost = creds["vhost"].as_str().unwrap_or("dev_vhost");

            let url = format!("amqp://{}:{}@{}:{}/{}", user, password, host, port, vhost);

            match lapin::Connection::connect(&url, lapin::ConnectionProperties::default()).await {
                Ok(conn) => {
                    match conn.create_channel().await {
                        Ok(channel) => {
                            // Use passive=true to check if queue exists without creating it
                            let mut options = lapin::options::QueueDeclareOptions::default();
                            options.passive = true;

                            match channel.queue_declare(
                                &queue_name,
                                options,
                                lapin::types::FieldTable::default(),
                            ).await {
                                Ok(queue) => {
                                    let message_count = queue.message_count();
                                    let consumer_count = queue.consumer_count();
                                    let _ = conn.close(0, "Done").await;
                                    HttpResponse::Ok().json(serde_json::json!({
                                        "queue": queue_name,
                                        "exists": true,
                                        "message_count": message_count,
                                        "consumer_count": consumer_count
                                    }))
                                }
                                Err(_) => {
                                    // Queue doesn't exist (passive declare failed)
                                    let _ = conn.close(0, "Done").await;
                                    HttpResponse::Ok().json(serde_json::json!({
                                        "queue": queue_name,
                                        "exists": false,
                                        "message_count": null,
                                        "consumer_count": null
                                    }))
                                }
                            }
                        }
                        Err(e) => {
                            let _ = conn.close(0, "Error").await;
                            HttpResponse::InternalServerError().json(serde_json::json!({
                                "error": format!("Channel creation failed: {}", e)
                            }))
                        }
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                    "error": format!("Connection failed: {}", e)
                })),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "error": e
        })),
    }
}

// Redis cluster handlers
async fn redis_cluster_nodes() -> impl Responder {
    match get_vault_secret("redis-1").await {
        Ok(creds) => {
            let host = get_env_or("REDIS_HOST", "redis-1");
            let port = get_env_or("REDIS_PORT", "6379");
            let password = creds["password"].as_str().unwrap_or("");

            let url = format!("redis://:{}@{}:{}", password, host, port);

            match redis::Client::open(url) {
                Ok(client) => {
                    match client.get_multiplexed_async_connection().await {
                        Ok(mut conn) => {
                            match redis::cmd("CLUSTER").arg("NODES").query_async::<String>(&mut conn).await {
                                Ok(nodes_raw) => {
                                    // Parse CLUSTER NODES output
                                    let mut nodes = Vec::new();
                                    for line in nodes_raw.trim().split('\n') {
                                        if line.is_empty() {
                                            continue;
                                        }
                                        let parts: Vec<&str> = line.split_whitespace().collect();
                                        if parts.len() < 8 {
                                            continue;
                                        }

                                        let node_id = parts[0];
                                        let address = parts[1];
                                        let flags = parts[2];
                                        let master_id = if parts[3] == "-" { None } else { Some(parts[3]) };
                                        let ping_sent = parts[4];
                                        let pong_recv = parts[5];
                                        let config_epoch = parts[6];
                                        let link_state = parts[7];

                                        // Parse slots (if any)
                                        let mut slot_ranges = Vec::new();
                                        let mut slots_count = 0;
                                        for i in 8..parts.len() {
                                            let slot_info = parts[i];
                                            if slot_info.starts_with('[') {
                                                continue; // Skip migrating slots
                                            }
                                            if slot_info.contains('-') {
                                                let range_parts: Vec<&str> = slot_info.split('-').collect();
                                                if range_parts.len() == 2 {
                                                    if let (Ok(start), Ok(end)) = (range_parts[0].parse::<i32>(), range_parts[1].parse::<i32>()) {
                                                        slot_ranges.push(serde_json::json!({"start": start, "end": end}));
                                                        slots_count += (end - start + 1) as usize;
                                                    }
                                                }
                                            } else if let Ok(slot) = slot_info.parse::<i32>() {
                                                slot_ranges.push(serde_json::json!({"start": slot, "end": slot}));
                                                slots_count += 1;
                                            }
                                        }

                                        // Parse address (remove cluster bus port)
                                        let host_port = address.split('@').next().unwrap_or(address);
                                        let addr_parts: Vec<&str> = host_port.rsplitn(2, ':').collect();
                                        let (port_str, host_str) = if addr_parts.len() == 2 {
                                            (addr_parts[0], addr_parts[1])
                                        } else {
                                            ("0", host_port)
                                        };

                                        // Determine role
                                        let role = if flags.contains("master") {
                                            "master"
                                        } else if flags.contains("slave") {
                                            "replica"
                                        } else {
                                            "unknown"
                                        };

                                        nodes.push(serde_json::json!({
                                            "node_id": node_id,
                                            "host": host_str,
                                            "port": port_str.parse::<i32>().unwrap_or(0),
                                            "role": role,
                                            "flags": flags.split(',').collect::<Vec<&str>>(),
                                            "master_id": master_id,
                                            "ping_sent": ping_sent,
                                            "pong_recv": pong_recv,
                                            "config_epoch": config_epoch.parse::<i32>().unwrap_or(0),
                                            "link_state": link_state,
                                            "slots_count": slots_count,
                                            "slot_ranges": slot_ranges
                                        }));
                                    }

                                    HttpResponse::Ok().json(serde_json::json!({
                                        "status": "success",
                                        "total_nodes": nodes.len(),
                                        "nodes": nodes
                                    }))
                                }
                                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                                    "status": "error",
                                    "error": format!("CLUSTER NODES failed: {}", e)
                                })),
                            }
                        }
                        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                            "status": "error",
                            "error": format!("Connection failed: {}", e)
                        })),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                    "status": "error",
                    "error": format!("Client creation failed: {}", e)
                })),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "error",
            "error": e
        })),
    }
}

async fn redis_cluster_slots() -> impl Responder {
    match get_vault_secret("redis-1").await {
        Ok(creds) => {
            let host = get_env_or("REDIS_HOST", "redis-1");
            let port = get_env_or("REDIS_PORT", "6379");
            let password = creds["password"].as_str().unwrap_or("");

            let url = format!("redis://:{}@{}:{}", password, host, port);

            match redis::Client::open(url) {
                Ok(client) => {
                    match client.get_multiplexed_async_connection().await {
                        Ok(mut conn) => {
                            match redis::cmd("CLUSTER").arg("SLOTS").query_async::<redis::Value>(&mut conn).await {
                                Ok(slots) => {
                                    // Parse CLUSTER SLOTS response
                                    let mut slot_distribution = Vec::new();
                                    let mut total_slots = 0i64;

                                    if let redis::Value::Array(slot_ranges) = slots {
                                        for slot_info in slot_ranges {
                                            if let redis::Value::Array(parts) = slot_info {
                                                if parts.len() >= 3 {
                                                    // Extract start and end slots
                                                    let start_slot = match &parts[0] {
                                                        redis::Value::Int(n) => *n,
                                                        _ => continue,
                                                    };
                                                    let end_slot = match &parts[1] {
                                                        redis::Value::Int(n) => *n,
                                                        _ => continue,
                                                    };

                                                    // Extract master info
                                                    let master = if let redis::Value::Array(master_info) = &parts[2] {
                                                        if master_info.len() >= 3 {
                                                            let host = match &master_info[0] {
                                                                redis::Value::BulkString(b) => String::from_utf8_lossy(b).to_string(),
                                                                redis::Value::SimpleString(s) => s.clone(),
                                                                _ => "".to_string(),
                                                            };
                                                            let port = match &master_info[1] {
                                                                redis::Value::Int(n) => *n,
                                                                _ => 0,
                                                            };
                                                            let node_id = match &master_info[2] {
                                                                redis::Value::BulkString(b) => String::from_utf8_lossy(b).to_string(),
                                                                redis::Value::SimpleString(s) => s.clone(),
                                                                _ => "".to_string(),
                                                            };
                                                            serde_json::json!({
                                                                "host": host,
                                                                "port": port,
                                                                "node_id": node_id
                                                            })
                                                        } else {
                                                            serde_json::json!({})
                                                        }
                                                    } else {
                                                        serde_json::json!({})
                                                    };

                                                    // Extract replicas (if any)
                                                    let mut replicas = Vec::new();
                                                    for i in 3..parts.len() {
                                                        if let redis::Value::Array(replica_info) = &parts[i] {
                                                            if replica_info.len() >= 3 {
                                                                let host = match &replica_info[0] {
                                                                    redis::Value::BulkString(b) => String::from_utf8_lossy(b).to_string(),
                                                                    redis::Value::SimpleString(s) => s.clone(),
                                                                    _ => "".to_string(),
                                                                };
                                                                let port = match &replica_info[1] {
                                                                    redis::Value::Int(n) => *n,
                                                                    _ => 0,
                                                                };
                                                                let node_id = match &replica_info[2] {
                                                                    redis::Value::BulkString(b) => String::from_utf8_lossy(b).to_string(),
                                                                    redis::Value::SimpleString(s) => s.clone(),
                                                                    _ => "".to_string(),
                                                                };
                                                                replicas.push(serde_json::json!({
                                                                    "host": host,
                                                                    "port": port,
                                                                    "node_id": node_id
                                                                }));
                                                            }
                                                        }
                                                    }

                                                    let slots_in_range = end_slot - start_slot + 1;
                                                    total_slots += slots_in_range;

                                                    slot_distribution.push(serde_json::json!({
                                                        "start_slot": start_slot,
                                                        "end_slot": end_slot,
                                                        "slots_count": slots_in_range,
                                                        "master": master,
                                                        "replicas": replicas
                                                    }));
                                                }
                                            }
                                        }
                                    }

                                    let coverage = if total_slots > 0 {
                                        ((total_slots as f64 / 16384.0) * 100.0 * 100.0).round() / 100.0
                                    } else {
                                        0.0
                                    };

                                    HttpResponse::Ok().json(serde_json::json!({
                                        "status": "success",
                                        "total_slots": total_slots,
                                        "max_slots": 16384,
                                        "coverage_percentage": coverage,
                                        "slot_distribution": slot_distribution
                                    }))
                                }
                                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                                    "status": "error",
                                    "error": format!("CLUSTER SLOTS failed: {}", e)
                                })),
                            }
                        }
                        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                            "status": "error",
                            "error": format!("Connection failed: {}", e)
                        })),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                    "status": "error",
                    "error": format!("Client creation failed: {}", e)
                })),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "error",
            "error": e
        })),
    }
}

async fn redis_cluster_info() -> impl Responder {
    match get_vault_secret("redis-1").await {
        Ok(creds) => {
            let host = get_env_or("REDIS_HOST", "redis-1");
            let port = get_env_or("REDIS_PORT", "6379");
            let password = creds["password"].as_str().unwrap_or("");

            let url = format!("redis://:{}@{}:{}", password, host, port);

            match redis::Client::open(url) {
                Ok(client) => {
                    match client.get_multiplexed_async_connection().await {
                        Ok(mut conn) => {
                            match redis::cmd("CLUSTER").arg("INFO").query_async::<String>(&mut conn).await {
                                Ok(info_raw) => {
                                    // Parse CLUSTER INFO output into key:value pairs
                                    let mut cluster_info = serde_json::Map::new();
                                    for line in info_raw.split('\n') {
                                        if let Some((key, value)) = line.trim().split_once(':') {
                                            // Try to parse as integer first
                                            if let Ok(int_val) = value.parse::<i64>() {
                                                cluster_info.insert(key.to_string(), serde_json::json!(int_val));
                                            } else {
                                                cluster_info.insert(key.to_string(), serde_json::json!(value));
                                            }
                                        }
                                    }
                                    HttpResponse::Ok().json(serde_json::json!({
                                        "status": "success",
                                        "cluster_info": cluster_info
                                    }))
                                }
                                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                                    "status": "error",
                                    "error": format!("CLUSTER INFO failed: {}", e)
                                })),
                            }
                        }
                        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                            "status": "error",
                            "error": format!("Connection failed: {}", e)
                        })),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                    "status": "error",
                    "error": format!("Client creation failed: {}", e)
                })),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "error",
            "error": e
        })),
    }
}

async fn redis_node_info(path: web::Path<String>) -> impl Responder {
    let node_name = path.into_inner();

    // Validate node name
    let valid_nodes = ["redis-1", "redis-2", "redis-3"];
    if !valid_nodes.contains(&node_name.as_str()) {
        return HttpResponse::BadRequest().json(serde_json::json!({
            "status": "error",
            "error": format!("Invalid node name. Must be one of: {}", valid_nodes.join(", "))
        }));
    }

    match get_vault_secret("redis-1").await {
        Ok(creds) => {
            let password = creds["password"].as_str().unwrap_or("");
            let url = format!("redis://:{}@{}:6379", password, node_name);

            match redis::Client::open(url) {
                Ok(client) => {
                    match client.get_multiplexed_async_connection().await {
                        Ok(mut conn) => {
                            match redis::cmd("INFO").query_async::<String>(&mut conn).await {
                                Ok(info_raw) => {
                                    // Parse INFO output into sections
                                    let mut info = serde_json::Map::new();
                                    let mut current_section = String::new();
                                    let mut section_data = serde_json::Map::new();

                                    for line in info_raw.split('\n') {
                                        let line = line.trim();
                                        if line.is_empty() {
                                            continue;
                                        }
                                        if line.starts_with('#') {
                                            // Save previous section if exists
                                            if !current_section.is_empty() && !section_data.is_empty() {
                                                info.insert(current_section.clone(), serde_json::Value::Object(section_data.clone()));
                                                section_data.clear();
                                            }
                                            // Start new section
                                            current_section = line.trim_start_matches('#').trim().to_lowercase();
                                        } else if let Some((key, value)) = line.split_once(':') {
                                            // Try to parse as integer or float
                                            let parsed_value = if let Ok(int_val) = value.parse::<i64>() {
                                                serde_json::json!(int_val)
                                            } else if let Ok(float_val) = value.parse::<f64>() {
                                                serde_json::json!(float_val)
                                            } else {
                                                serde_json::json!(value)
                                            };
                                            section_data.insert(key.to_string(), parsed_value);
                                        }
                                    }
                                    // Save last section
                                    if !current_section.is_empty() && !section_data.is_empty() {
                                        info.insert(current_section, serde_json::Value::Object(section_data));
                                    }

                                    HttpResponse::Ok().json(serde_json::json!({
                                        "status": "success",
                                        "node": node_name,
                                        "info": info
                                    }))
                                }
                                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                                    "status": "error",
                                    "error": format!("INFO failed: {}", e)
                                })),
                            }
                        }
                        Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                            "status": "error",
                            "error": format!("Connection failed: {}", e)
                        })),
                    }
                }
                Err(e) => HttpResponse::InternalServerError().json(serde_json::json!({
                    "status": "error",
                    "error": format!("Client creation failed: {}", e)
                })),
            }
        }
        Err(e) => HttpResponse::ServiceUnavailable().json(serde_json::json!({
            "status": "error",
            "error": e
        })),
    }
}

// Metrics handler
async fn metrics() -> impl Responder {
    let encoder = TextEncoder::new();
    let metric_families = REGISTRY.gather();
    let mut buffer = vec![];

    match encoder.encode(&metric_families, &mut buffer) {
        Ok(_) => HttpResponse::Ok()
            .content_type("text/plain; version=0.0.4")
            .body(buffer),
        Err(e) => HttpResponse::InternalServerError()
            .body(format!("Failed to encode metrics: {}", e))
    }
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::new().default_filter_or("info"));

    register_metrics();

    let port = env::var("HTTP_PORT")
        .unwrap_or_else(|_| "8004".to_string())
        .parse::<u16>()
        .unwrap_or(8004);

    log::info!("Starting Rust Reference API on port {}", port);

    HttpServer::new(|| {
        let cors = Cors::permissive();

        App::new()
            .wrap(cors)
            .wrap(middleware::Logger::default())
            .route("/", web::get().to(root))
            .route("/metrics", web::get().to(metrics))
            // Health check routes
            .service(
                web::scope("/health")
                    .route("/", web::get().to(health_simple))
                    .route("/vault", web::get().to(health_vault))
                    .route("/postgres", web::get().to(health_postgres))
                    .route("/mysql", web::get().to(health_mysql))
                    .route("/mongodb", web::get().to(health_mongodb))
                    .route("/redis", web::get().to(health_redis))
                    .route("/rabbitmq", web::get().to(health_rabbitmq))
                    .route("/all", web::get().to(health_all))
            )
            // Vault example routes
            .service(
                web::scope("/examples/vault")
                    .route("/secret/{service_name}", web::get().to(get_secret))
                    .route("/secret/{service_name}/{key}", web::get().to(get_secret_key))
            )
            // Database example routes
            .service(
                web::scope("/examples/database")
                    .route("/postgres/query", web::get().to(postgres_query))
                    .route("/mysql/query", web::get().to(mysql_query))
                    .route("/mongodb/query", web::get().to(mongodb_query))
            )
            // Cache example routes
            .service(
                web::scope("/examples/cache")
                    .route("/{key}", web::get().to(get_cache))
                    .route("/{key}", web::post().to(set_cache))
                    .route("/{key}", web::delete().to(delete_cache))
            )
            // Messaging example routes
            .service(
                web::scope("/examples/messaging")
                    .route("/publish/{queue}", web::post().to(publish_message))
                    .route("/queue/{queue_name}/info", web::get().to(queue_info))
            )
            // Redis cluster routes
            .service(
                web::scope("/redis")
                    .route("/cluster/nodes", web::get().to(redis_cluster_nodes))
                    .route("/cluster/slots", web::get().to(redis_cluster_slots))
                    .route("/cluster/info", web::get().to(redis_cluster_info))
                    .route("/nodes/{node_name}/info", web::get().to(redis_node_info))
            )
    })
    .bind(("0.0.0.0", port))?
    .run()
    .await
}

#[cfg(test)]
mod tests;  // Comprehensive test suite in tests.rs
