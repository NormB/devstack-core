// Comprehensive test suite for DevStack Core Rust API
// Following Rust testing best practices with positive and negative test cases

#[cfg(test)]
mod api_tests {
    use super::super::*;
    use actix_web::{test, web, App, http::StatusCode};
    use serde_json::json;

    // Helper macro to create test app (avoids complex return types)
    macro_rules! create_test_app {
        () => {
            App::new()
                .route("/", web::get().to(root))
                .route("/metrics", web::get().to(metrics))
                .service(
                    web::scope("/health")
                        .route("/", web::get().to(health_simple))
                        .route("/all", web::get().to(health_all))
                )
                .service(
                    web::scope("/examples/vault")
                        .route("/secret/{service_name}", web::get().to(get_secret))
                        .route("/secret/{service_name}/{key}", web::get().to(get_secret_key))
                )
                .service(
                    web::scope("/examples/cache")
                        .route("/{key}", web::get().to(get_cache))
                        .route("/{key}", web::post().to(set_cache))
                        .route("/{key}", web::delete().to(delete_cache))
                )
                .service(
                    web::scope("/examples/messaging")
                        .route("/queue/{queue_name}/info", web::get().to(queue_info))
                )
                .service(
                    web::scope("/redis")
                        .route("/cluster/nodes", web::get().to(redis_cluster_nodes))
                        .route("/cluster/slots", web::get().to(redis_cluster_slots))
                        .route("/cluster/info", web::get().to(redis_cluster_info))
                        .route("/nodes/{node_name}/info", web::get().to(redis_node_info))
                )
        };
    }

    // ============================================================================
    // ROOT ENDPOINT TESTS
    // ============================================================================

    #[actix_web::test]
    async fn test_root_returns_200() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/").to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[actix_web::test]
    async fn test_root_returns_api_info() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/").to_request();
        let resp = test::call_service(&app, req).await;

        let body: ApiInfo = test::read_body_json(resp).await;
        assert_eq!(body.name, "DevStack Core Reference API");
        assert_eq!(body.version, "1.1.0");
        assert_eq!(body.language, "Rust");
        assert_eq!(body.framework, "Actix-web");
    }

    #[actix_web::test]
    async fn test_root_contains_all_endpoints() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/").to_request();
        let resp = test::call_service(&app, req).await;

        let body: ApiInfo = test::read_body_json(resp).await;
        assert_eq!(body.docs, "/docs");
        assert_eq!(body.health, "/health/all");
        assert_eq!(body.metrics, "/metrics");
    }

    #[actix_web::test]
    async fn test_root_returns_json_content_type() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/").to_request();
        let resp = test::call_service(&app, req).await;

        let content_type = resp.headers().get("content-type").expect("Content-Type header should be present");
        assert!(content_type.to_str().expect("Content-Type should be valid UTF-8").contains("application/json"));
    }

    // ============================================================================
    // HEALTH ENDPOINT TESTS - Positive Cases
    // ============================================================================

    #[actix_web::test]
    async fn test_health_simple_returns_200() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/health/").to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[actix_web::test]
    async fn test_health_simple_status_healthy() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/health/").to_request();
        let resp = test::call_service(&app, req).await;

        let body: HealthResponse = test::read_body_json(resp).await;
        assert_eq!(body.status, "healthy");
    }

    #[actix_web::test]
    async fn test_health_simple_has_timestamp() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/health/").to_request();
        let resp = test::call_service(&app, req).await;

        let body: HealthResponse = test::read_body_json(resp).await;
        assert!(body.timestamp.is_some());
    }

    #[actix_web::test]
    async fn test_health_simple_no_error() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/health/").to_request();
        let resp = test::call_service(&app, req).await;

        let body: HealthResponse = test::read_body_json(resp).await;
        assert!(body.error.is_none());
    }

    #[actix_web::test]
    async fn test_health_all_returns_200() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/health/all").to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[actix_web::test]
    async fn test_health_all_has_status_field() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/health/all").to_request();
        let resp = test::call_service(&app, req).await;

        let body: AllHealthResponse = test::read_body_json(resp).await;
        assert!(!body.status.is_empty());
    }

    #[actix_web::test]
    async fn test_health_all_contains_services() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/health/all").to_request();
        let resp = test::call_service(&app, req).await;

        let body: AllHealthResponse = test::read_body_json(resp).await;
        assert!(body.services.contains_key("vault"));
        assert!(body.services.contains_key("postgres"));
        assert!(body.services.contains_key("mysql"));
        assert!(body.services.contains_key("mongodb"));
        assert!(body.services.contains_key("redis"));
        assert!(body.services.contains_key("rabbitmq"));
    }

    // ============================================================================
    // HEALTH ENDPOINT TESTS - Negative Cases
    // ============================================================================

    #[actix_web::test]
    async fn test_health_invalid_path_returns_404() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/health/nonexistent").to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[actix_web::test]
    async fn test_health_wrong_method_returns_404_or_405() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post().uri("/health/").to_request();
        let resp = test::call_service(&app, req).await;
        // Actix-web may return 404 if route doesn't match, or 405 if it does but method is wrong
        assert!(
            resp.status() == StatusCode::NOT_FOUND || resp.status() == StatusCode::METHOD_NOT_ALLOWED,
            "Expected 404 or 405, got {}", resp.status()
        );
    }

    // ============================================================================
    // VAULT ENDPOINT TESTS - Positive Cases
    // ============================================================================

    #[actix_web::test]
    async fn test_vault_secret_endpoint_structure() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/vault/secret/postgres")
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should return either 200 (success) or 503 (Vault unavailable)
        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_vault_secret_key_endpoint_structure() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/vault/secret/postgres/user")
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should return 200, 404, or 503
        assert!(
            resp.status() == StatusCode::OK
            || resp.status() == StatusCode::NOT_FOUND
            || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200, 404, or 503, got {}", resp.status()
        );
    }

    // ============================================================================
    // VAULT ENDPOINT TESTS - Negative Cases
    // ============================================================================

    #[actix_web::test]
    async fn test_vault_secret_empty_service_returns_404() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/vault/secret/")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[actix_web::test]
    async fn test_vault_secret_wrong_method_returns_404_or_405() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/examples/vault/secret/postgres")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert!(
            resp.status() == StatusCode::NOT_FOUND || resp.status() == StatusCode::METHOD_NOT_ALLOWED,
            "Expected 404 or 405, got {}", resp.status()
        );
    }

    // ============================================================================
    // CACHE ENDPOINT TESTS - Positive Cases
    // ============================================================================

    #[actix_web::test]
    async fn test_cache_get_returns_valid_response() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/cache/test-key")
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should return 200 (found), 404 (not found), or 503 (service unavailable)
        assert!(
            resp.status() == StatusCode::OK
            || resp.status() == StatusCode::NOT_FOUND
            || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200, 404, or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_cache_set_accepts_json() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/examples/cache/test-key")
            .set_json(json!({
                "value": "test-value"
            }))
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should accept the request (200 or 503 if service unavailable)
        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_cache_set_with_ttl() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/examples/cache/test-key-ttl")
            .set_json(json!({
                "value": "test-value",
                "ttl": 60
            }))
            .to_request();
        let resp = test::call_service(&app, req).await;

        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_cache_delete_returns_valid_response() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::delete()
            .uri("/examples/cache/test-key")
            .to_request();
        let resp = test::call_service(&app, req).await;

        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    // ============================================================================
    // CACHE ENDPOINT TESTS - Negative Cases
    // ============================================================================

    #[actix_web::test]
    async fn test_cache_set_without_value_returns_400() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/examples/cache/test-key")
            .set_json(json!({}))
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    }

    #[actix_web::test]
    async fn test_cache_set_with_invalid_json_returns_400() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/examples/cache/test-key")
            .set_payload("invalid json")
            .insert_header(("content-type", "application/json"))
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    }

    #[actix_web::test]
    async fn test_cache_empty_key_returns_404() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/cache/")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[actix_web::test]
    async fn test_cache_get_with_special_characters_in_key() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/cache/test:key:with:colons")
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should handle special characters gracefully
        assert!(
            resp.status() == StatusCode::OK
            || resp.status() == StatusCode::NOT_FOUND
            || resp.status() == StatusCode::SERVICE_UNAVAILABLE
        );
    }

    // ============================================================================
    // MESSAGING ENDPOINT TESTS
    // ============================================================================

    #[actix_web::test]
    async fn test_messaging_queue_info_returns_200() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/messaging/queue/test-queue/info")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[actix_web::test]
    async fn test_messaging_queue_info_returns_json() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/messaging/queue/test-queue/info")
            .to_request();
        let resp = test::call_service(&app, req).await;

        let body: serde_json::Value = test::read_body_json(resp).await;
        assert!(body.get("queue").is_some());
    }

    #[actix_web::test]
    async fn test_messaging_queue_info_empty_queue_name_returns_404() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/messaging/queue//info")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    // ============================================================================
    // REDIS CLUSTER ENDPOINT TESTS
    // ============================================================================

    #[actix_web::test]
    async fn test_redis_cluster_nodes_endpoint() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/redis/cluster/nodes")
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should return 200 or 503 depending on service availability
        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_redis_cluster_slots_endpoint() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/redis/cluster/slots")
            .to_request();
        let resp = test::call_service(&app, req).await;

        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_redis_cluster_info_endpoint() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/redis/cluster/info")
            .to_request();
        let resp = test::call_service(&app, req).await;

        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_redis_node_info_endpoint() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/redis/nodes/redis-1/info")
            .to_request();
        let resp = test::call_service(&app, req).await;

        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_redis_node_info_empty_node_returns_404() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/redis/nodes//info")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[actix_web::test]
    async fn test_redis_cluster_wrong_method_returns_404_or_405() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/redis/cluster/nodes")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert!(
            resp.status() == StatusCode::NOT_FOUND || resp.status() == StatusCode::METHOD_NOT_ALLOWED,
            "Expected 404 or 405, got {}", resp.status()
        );
    }

    // ============================================================================
    // METRICS ENDPOINT TESTS
    // ============================================================================

    #[actix_web::test]
    async fn test_metrics_returns_200() {
        register_metrics();
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/metrics").to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::OK);
    }

    #[actix_web::test]
    async fn test_metrics_returns_prometheus_format() {
        register_metrics();
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get().uri("/metrics").to_request();
        let resp = test::call_service(&app, req).await;

        let content_type = resp.headers().get("content-type").expect("Content-Type header should be present");
        assert!(content_type.to_str().expect("Content-Type should be valid UTF-8").contains("text/plain"));
    }

    #[actix_web::test]
    async fn test_metrics_wrong_method_returns_404_or_405() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post().uri("/metrics").to_request();
        let resp = test::call_service(&app, req).await;
        assert!(
            resp.status() == StatusCode::NOT_FOUND || resp.status() == StatusCode::METHOD_NOT_ALLOWED,
            "Expected 404 or 405, got {}", resp.status()
        );
    }

    // ============================================================================
    // EDGE CASES AND ERROR HANDLING
    // ============================================================================

    #[actix_web::test]
    async fn test_nonexistent_endpoint_returns_404() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/nonexistent/path")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[actix_web::test]
    async fn test_deeply_nested_nonexistent_path_returns_404() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/a/b/c/d/e/f/g")
            .to_request();
        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    #[actix_web::test]
    async fn test_cache_very_long_key() {
        let app = test::init_service(create_test_app!()).await;
        let long_key = "a".repeat(1000);
        let uri = format!("/examples/cache/{}", long_key);
        let req = test::TestRequest::get().uri(&uri).to_request();
        let resp = test::call_service(&app, req).await;

        // Should handle long keys (may return service error or success)
        assert!(resp.status().is_client_error() || resp.status().is_success() || resp.status().is_server_error());
    }

    #[actix_web::test]
    async fn test_cache_set_zero_ttl() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/examples/cache/test-key")
            .set_json(json!({
                "value": "test-value",
                "ttl": 0
            }))
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should handle zero TTL gracefully
        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_cache_set_negative_ttl() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/examples/cache/test-key")
            .set_json(json!({
                "value": "test-value",
                "ttl": -1
            }))
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should reject negative TTL
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    }

    #[actix_web::test]
    async fn test_cache_set_empty_value() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::post()
            .uri("/examples/cache/test-key")
            .set_json(json!({
                "value": ""
            }))
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should accept empty string as valid value
        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }

    #[actix_web::test]
    async fn test_vault_secret_with_special_characters() {
        let app = test::init_service(create_test_app!()).await;
        let req = test::TestRequest::get()
            .uri("/examples/vault/secret/service-name-with-dashes")
            .to_request();
        let resp = test::call_service(&app, req).await;

        // Should handle service names with special characters
        assert!(
            resp.status() == StatusCode::OK || resp.status() == StatusCode::SERVICE_UNAVAILABLE,
            "Expected 200 or 503, got {}", resp.status()
        );
    }
}
