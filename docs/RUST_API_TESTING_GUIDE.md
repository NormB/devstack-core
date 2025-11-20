# Rust HTTP API Testing Guide

Comprehensive guide for testing Actix-web HTTP APIs using Rust testing best practices.

## Table of Contents

1. [Testing Fundamentals](#testing-fundamentals)
2. [Test Organization](#test-organization)
3. [Actix-web Testing Patterns](#actix-web-testing-patterns)
4. [Testing Best Practices](#testing-best-practices)
5. [Common Testing Crates](#common-testing-crates)
6. [Complete Examples](#complete-examples)

---

## Testing Fundamentals

### Unit Tests vs Integration Tests

**Unit Tests:**
- Small and focused, testing one module in isolation
- Can test private interfaces
- Located in the same file as the code (`src/` directory)
- Use `#[cfg(test)]` annotation
- Compile only when running `cargo test`

**Integration Tests:**
- Entirely external to your library
- Use only the public interface
- Test multiple modules working together
- Located in `tests/` directory at project root
- Each file compiles as a separate crate
- No `#[cfg(test)]` annotation needed

### Test Attributes

```rust
// Standard synchronous test
#[test]
fn test_something() {
    assert_eq!(2 + 2, 4);
}

// Async test with actix_web
#[actix_web::test]
async fn test_async_handler() {
    // Async test code
}

// Async test with tokio
#[tokio::test]
async fn test_async_function() {
    // Async test code
}

// Test that should panic
#[test]
#[should_panic(expected = "panic message")]
fn test_panic() {
    panic!("panic message");
}

// Ignore test (skip during normal runs)
#[test]
#[ignore]
fn expensive_test() {
    // Only runs with: cargo test -- --ignored
}
```

---

## Test Organization

### Unit Test Structure

Place unit tests in the same file as the code, within a `tests` module:

```rust
// src/handlers.rs
use actix_web::{web, HttpResponse, Responder};

pub async fn health_check() -> impl Responder {
    HttpResponse::Ok().json(serde_json::json!({
        "status": "healthy"
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use actix_web::{test, App};

    #[actix_web::test]
    async fn test_health_check() {
        let app = test::init_service(
            App::new().route("/health", web::get().to(health_check))
        ).await;

        let req = test::TestRequest::get().uri("/health").to_request();
        let resp = test::call_service(&app, req).await;

        assert!(resp.status().is_success());
    }
}
```

### Integration Test Structure

Create integration tests in `tests/` directory:

```
project/
├── Cargo.toml
├── src/
│   ├── main.rs
│   └── lib.rs
└── tests/
    ├── common/
    │   └── mod.rs          # Shared test utilities
    ├── api_tests.rs        # API endpoint tests
    └── integration_test.rs # Integration tests
```

Example integration test:

```rust
// tests/api_tests.rs
use your_crate::*;  // Import public items
use actix_web::{test, web, App};

#[actix_web::test]
async fn test_full_api_flow() {
    // Test using only public interfaces
}
```

### Shared Test Utilities

Use `tests/common/mod.rs` for shared helpers:

```rust
// tests/common/mod.rs
use actix_web::{test, web, App};

pub async fn create_test_app() -> impl actix_web::dev::Service<
    actix_web::dev::ServiceRequest,
    Response = actix_web::dev::ServiceResponse,
    Error = actix_web::Error,
> {
    test::init_service(
        App::new()
            .route("/health", web::get().to(health_check))
            // ... other routes
    ).await
}

// tests/api_tests.rs
mod common;

#[actix_web::test]
async fn test_with_shared_app() {
    let app = common::create_test_app().await;
    // ... test code
}
```

---

## Actix-web Testing Patterns

### Basic Endpoint Testing

```rust
use actix_web::{test, web, App, HttpResponse, Responder};

async fn hello() -> impl Responder {
    HttpResponse::Ok().body("Hello world!")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_web::test]
    async fn test_hello_endpoint() {
        // Initialize the test service
        let app = test::init_service(
            App::new().route("/hello", web::get().to(hello))
        ).await;

        // Create a test request
        let req = test::TestRequest::get()
            .uri("/hello")
            .to_request();

        // Call the service and get response
        let resp = test::call_service(&app, req).await;

        // Assert response status
        assert!(resp.status().is_success());

        // Read response body
        let body = test::read_body(resp).await;
        assert_eq!(body, "Hello world!");
    }
}
```

### Testing JSON Responses

```rust
use actix_web::{test, web, App, HttpResponse};
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, PartialEq, Debug)]
struct ApiResponse {
    status: String,
    message: String,
}

async fn json_endpoint() -> actix_web::Result<HttpResponse> {
    Ok(HttpResponse::Ok().json(ApiResponse {
        status: "success".to_string(),
        message: "API is working".to_string(),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_web::test]
    async fn test_json_response() {
        let app = test::init_service(
            App::new().route("/api", web::get().to(json_endpoint))
        ).await;

        let req = test::TestRequest::get().uri("/api").to_request();
        let resp = test::call_service(&app, req).await;

        assert!(resp.status().is_success());

        // Deserialize JSON response
        let body: ApiResponse = test::read_body_json(resp).await;
        assert_eq!(body.status, "success");
        assert_eq!(body.message, "API is working");
    }
}
```

### Testing POST Requests with Body

```rust
use actix_web::{test, web, App, HttpResponse};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct CreateRequest {
    name: String,
    value: i32,
}

#[derive(Serialize, Deserialize, Debug, PartialEq)]
struct CreateResponse {
    id: i32,
    name: String,
    value: i32,
}

async fn create_item(data: web::Json<CreateRequest>) -> actix_web::Result<HttpResponse> {
    Ok(HttpResponse::Ok().json(CreateResponse {
        id: 1,
        name: data.name.clone(),
        value: data.value,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_web::test]
    async fn test_create_item() {
        let app = test::init_service(
            App::new().route("/items", web::post().to(create_item))
        ).await;

        let payload = CreateRequest {
            name: "Test Item".to_string(),
            value: 42,
        };

        let req = test::TestRequest::post()
            .uri("/items")
            .set_json(&payload)
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert!(resp.status().is_success());

        let body: CreateResponse = test::read_body_json(resp).await;
        assert_eq!(body.name, "Test Item");
        assert_eq!(body.value, 42);
    }
}
```

### Testing with Headers

```rust
#[actix_web::test]
async fn test_with_custom_headers() {
    let app = test::init_service(
        App::new().route("/api", web::get().to(json_endpoint))
    ).await;

    let req = test::TestRequest::get()
        .uri("/api")
        .insert_header(("Authorization", "Bearer token123"))
        .insert_header(("Content-Type", "application/json"))
        .to_request();

    let resp = test::call_service(&app, req).await;
    assert!(resp.status().is_success());
}
```

### Testing with Path Parameters

```rust
async fn get_user(path: web::Path<i32>) -> actix_web::Result<HttpResponse> {
    let user_id = path.into_inner();
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "user_id": user_id,
        "name": "Test User"
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_web::test]
    async fn test_path_parameters() {
        let app = test::init_service(
            App::new().route("/users/{id}", web::get().to(get_user))
        ).await;

        let req = test::TestRequest::get()
            .uri("/users/123")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: serde_json::Value = test::read_body_json(resp).await;
        assert_eq!(body["user_id"], 123);
    }
}
```

### Testing with Query Parameters

```rust
use actix_web::web::Query;

#[derive(Deserialize)]
struct SearchParams {
    q: String,
    limit: Option<i32>,
}

async fn search(params: Query<SearchParams>) -> actix_web::Result<HttpResponse> {
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "query": params.q,
        "limit": params.limit.unwrap_or(10)
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_web::test]
    async fn test_query_parameters() {
        let app = test::init_service(
            App::new().route("/search", web::get().to(search))
        ).await;

        let req = test::TestRequest::get()
            .uri("/search?q=rust&limit=20")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert!(resp.status().is_success());

        let body: serde_json::Value = test::read_body_json(resp).await;
        assert_eq!(body["query"], "rust");
        assert_eq!(body["limit"], 20);
    }
}
```

### Testing Application State

```rust
use actix_web::{web, App, HttpResponse};
use std::sync::Mutex;

struct AppState {
    counter: Mutex<i32>,
}

async fn increment(data: web::Data<AppState>) -> actix_web::Result<HttpResponse> {
    let mut counter = data.counter.lock().unwrap();
    *counter += 1;
    Ok(HttpResponse::Ok().json(serde_json::json!({
        "count": *counter
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_web::test]
    async fn test_with_state() {
        let state = web::Data::new(AppState {
            counter: Mutex::new(0),
        });

        let app = test::init_service(
            App::new()
                .app_data(state.clone())
                .route("/increment", web::post().to(increment))
        ).await;

        // First request
        let req = test::TestRequest::post().uri("/increment").to_request();
        let resp = test::call_service(&app, req).await;
        let body: serde_json::Value = test::read_body_json(resp).await;
        assert_eq!(body["count"], 1);

        // Second request
        let req = test::TestRequest::post().uri("/increment").to_request();
        let resp = test::call_service(&app, req).await;
        let body: serde_json::Value = test::read_body_json(resp).await;
        assert_eq!(body["count"], 2);
    }
}
```

### Testing Error Responses

```rust
async fn may_fail(path: web::Path<i32>) -> actix_web::Result<HttpResponse> {
    let id = path.into_inner();

    if id == 0 {
        return Ok(HttpResponse::BadRequest().json(serde_json::json!({
            "error": "ID cannot be zero"
        })));
    }

    if id == 404 {
        return Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "Not found"
        })));
    }

    Ok(HttpResponse::Ok().json(serde_json::json!({
        "id": id,
        "status": "success"
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_web::test]
    async fn test_success_case() {
        let app = test::init_service(
            App::new().route("/item/{id}", web::get().to(may_fail))
        ).await;

        let req = test::TestRequest::get().uri("/item/1").to_request();
        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 200);
    }

    #[actix_web::test]
    async fn test_bad_request() {
        let app = test::init_service(
            App::new().route("/item/{id}", web::get().to(may_fail))
        ).await;

        let req = test::TestRequest::get().uri("/item/0").to_request();
        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 400);

        let body: serde_json::Value = test::read_body_json(resp).await;
        assert_eq!(body["error"], "ID cannot be zero");
    }

    #[actix_web::test]
    async fn test_not_found() {
        let app = test::init_service(
            App::new().route("/item/{id}", web::get().to(may_fail))
        ).await;

        let req = test::TestRequest::get().uri("/item/404").to_request();
        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 404);

        let body: serde_json::Value = test::read_body_json(resp).await;
        assert_eq!(body["error"], "Not found");
    }
}
```

---

## Testing Best Practices

### 1. Positive and Negative Test Cases

**Positive Tests (Happy Path):**
- Valid inputs with expected outputs
- Normal operation flow
- Successful responses

**Negative Tests (Error Cases):**
- Invalid inputs
- Missing required fields
- Edge cases and boundary conditions
- Unauthorized access
- Resource not found
- Server errors

Example:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    // Positive tests
    #[actix_web::test]
    async fn test_create_user_success() {
        // Test with valid data
    }

    #[actix_web::test]
    async fn test_get_existing_user() {
        // Test retrieving existing resource
    }

    // Negative tests
    #[actix_web::test]
    async fn test_create_user_missing_field() {
        // Test with missing required field
    }

    #[actix_web::test]
    async fn test_create_user_invalid_email() {
        // Test with invalid email format
    }

    #[actix_web::test]
    async fn test_get_nonexistent_user() {
        // Test 404 response
    }

    #[actix_web::test]
    async fn test_create_user_duplicate() {
        // Test conflict/duplicate error
    }

    // Edge cases
    #[actix_web::test]
    async fn test_create_user_empty_name() {
        // Test with empty string
    }

    #[actix_web::test]
    async fn test_create_user_very_long_name() {
        // Test with extremely long input
    }
}
```

### 2. Test Organization by Feature

Group tests by feature or endpoint:

```rust
#[cfg(test)]
mod health_tests {
    use super::*;

    #[actix_web::test]
    async fn test_health_check() { /* ... */ }

    #[actix_web::test]
    async fn test_health_vault() { /* ... */ }
}

#[cfg(test)]
mod user_tests {
    use super::*;

    #[actix_web::test]
    async fn test_create_user() { /* ... */ }

    #[actix_web::test]
    async fn test_get_user() { /* ... */ }

    #[actix_web::test]
    async fn test_update_user() { /* ... */ }
}
```

### 3. Setup and Teardown Patterns

**Using test-context crate:**

```rust
use test_context::{test_context, AsyncTestContext};

struct TestContext {
    app: /* your app type */,
}

#[async_trait::async_trait]
impl AsyncTestContext for TestContext {
    async fn setup() -> TestContext {
        // Setup code
        let app = create_test_app().await;
        TestContext { app }
    }

    async fn teardown(self) {
        // Cleanup code
        // Database cleanup, etc.
    }
}

#[test_context(TestContext)]
#[actix_web::test]
async fn test_with_context(ctx: &mut TestContext) {
    // Test using ctx.app
}
```

**Manual setup/teardown:**

```rust
async fn setup() -> TestApp {
    // Initialize test database
    // Create test fixtures
    TestApp::new().await
}

async fn teardown(app: TestApp) {
    // Clean up test data
    app.cleanup().await;
}

#[actix_web::test]
async fn test_with_manual_setup() {
    let app = setup().await;

    // Test code

    teardown(app).await;
}
```

### 4. Testing Async Operations

```rust
use tokio::time::{sleep, Duration};

async fn delayed_response() -> HttpResponse {
    sleep(Duration::from_millis(100)).await;
    HttpResponse::Ok().body("Done")
}

#[actix_web::test]
async fn test_async_operation() {
    let start = std::time::Instant::now();

    let app = test::init_service(
        App::new().route("/delayed", web::get().to(delayed_response))
    ).await;

    let req = test::TestRequest::get().uri("/delayed").to_request();
    let resp = test::call_service(&app, req).await;

    assert!(resp.status().is_success());
    assert!(start.elapsed() >= Duration::from_millis(100));
}
```

### 5. Test Data Builders

Create builders for test data:

```rust
struct UserBuilder {
    name: String,
    email: String,
    age: Option<i32>,
}

impl UserBuilder {
    fn new() -> Self {
        Self {
            name: "Test User".to_string(),
            email: "test@example.com".to_string(),
            age: None,
        }
    }

    fn name(mut self, name: &str) -> Self {
        self.name = name.to_string();
        self
    }

    fn email(mut self, email: &str) -> Self {
        self.email = email.to_string();
        self
    }

    fn age(mut self, age: i32) -> Self {
        self.age = Some(age);
        self
    }

    fn build(self) -> CreateUserRequest {
        CreateUserRequest {
            name: self.name,
            email: self.email,
            age: self.age,
        }
    }
}

#[actix_web::test]
async fn test_with_builder() {
    let user = UserBuilder::new()
        .name("Alice")
        .email("alice@example.com")
        .age(30)
        .build();

    // Use user in test
}
```

---

## Common Testing Crates

### Essential Crates for API Testing

Add to `Cargo.toml`:

```toml
[dev-dependencies]
actix-web = "4.4"
tokio = { version = "1.35", features = ["macros", "rt-multi-thread"] }
serde_json = "1.0"

# For JSON assertions
assert-json-diff = "2.0"

# For test context (setup/teardown)
test-context = "0.1"

# For HTTP mocking
mockito = "1.2"

# For async traits
async-trait = "0.1"
```

### 1. assert-json-diff

Provides helpful macros for comparing JSON values:

```rust
use assert_json_diff::{assert_json_eq, assert_json_include};
use serde_json::json;

#[test]
fn test_json_equality() {
    let expected = json!({
        "status": "success",
        "count": 42
    });

    let actual = json!({
        "status": "success",
        "count": 42
    });

    // Exact match
    assert_json_eq!(expected, actual);
}

#[test]
fn test_json_partial_match() {
    let expected = json!({
        "status": "success"
    });

    let actual = json!({
        "status": "success",
        "count": 42,
        "timestamp": "2024-01-01T00:00:00Z"
    });

    // Partial match - actual can have extra fields
    assert_json_include!(actual: actual, expected: expected);
}
```

### 2. test-context

Setup and teardown for tests:

```rust
use test_context::{test_context, AsyncTestContext};

struct DatabaseContext {
    connection: DatabaseConnection,
}

#[async_trait::async_trait]
impl AsyncTestContext for DatabaseContext {
    async fn setup() -> Self {
        let connection = setup_test_database().await;
        DatabaseContext { connection }
    }

    async fn teardown(self) {
        cleanup_database(self.connection).await;
    }
}

#[test_context(DatabaseContext)]
#[tokio::test]
async fn test_database_operation(ctx: &mut DatabaseContext) {
    // Use ctx.connection in test
}
```

### 3. mockito

HTTP mocking for external API calls:

```rust
use mockito::{mock, server_url};

#[actix_web::test]
async fn test_external_api_call() {
    let _m = mock("GET", "/api/users/1")
        .with_status(200)
        .with_header("content-type", "application/json")
        .with_body(r#"{"id": 1, "name": "John"}"#)
        .create();

    // Your code that calls the mocked endpoint
    let response = reqwest::get(&format!("{}/api/users/1", server_url()))
        .await
        .unwrap();

    assert_eq!(response.status(), 200);
}
```

---

## Complete Examples

### Example 1: Testing a CRUD API

```rust
use actix_web::{test, web, App, HttpResponse, Responder};
use serde::{Deserialize, Serialize};
use std::sync::Mutex;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
struct Item {
    id: i32,
    name: String,
    description: String,
}

#[derive(Deserialize)]
struct CreateItemRequest {
    name: String,
    description: String,
}

struct AppState {
    items: Mutex<Vec<Item>>,
    next_id: Mutex<i32>,
}

// Handlers
async fn create_item(
    data: web::Data<AppState>,
    req: web::Json<CreateItemRequest>,
) -> impl Responder {
    let mut next_id = data.next_id.lock().unwrap();
    let id = *next_id;
    *next_id += 1;

    let item = Item {
        id,
        name: req.name.clone(),
        description: req.description.clone(),
    };

    data.items.lock().unwrap().push(item.clone());

    HttpResponse::Created().json(item)
}

async fn get_item(data: web::Data<AppState>, path: web::Path<i32>) -> impl Responder {
    let id = path.into_inner();
    let items = data.items.lock().unwrap();

    match items.iter().find(|item| item.id == id) {
        Some(item) => HttpResponse::Ok().json(item.clone()),
        None => HttpResponse::NotFound().json(serde_json::json!({
            "error": "Item not found"
        })),
    }
}

async fn list_items(data: web::Data<AppState>) -> impl Responder {
    let items = data.items.lock().unwrap();
    HttpResponse::Ok().json(items.clone())
}

async fn update_item(
    data: web::Data<AppState>,
    path: web::Path<i32>,
    req: web::Json<CreateItemRequest>,
) -> impl Responder {
    let id = path.into_inner();
    let mut items = data.items.lock().unwrap();

    match items.iter_mut().find(|item| item.id == id) {
        Some(item) => {
            item.name = req.name.clone();
            item.description = req.description.clone();
            HttpResponse::Ok().json(item.clone())
        }
        None => HttpResponse::NotFound().json(serde_json::json!({
            "error": "Item not found"
        })),
    }
}

async fn delete_item(data: web::Data<AppState>, path: web::Path<i32>) -> impl Responder {
    let id = path.into_inner();
    let mut items = data.items.lock().unwrap();

    if let Some(pos) = items.iter().position(|item| item.id == id) {
        items.remove(pos);
        HttpResponse::NoContent().finish()
    } else {
        HttpResponse::NotFound().json(serde_json::json!({
            "error": "Item not found"
        }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_state() -> web::Data<AppState> {
        web::Data::new(AppState {
            items: Mutex::new(Vec::new()),
            next_id: Mutex::new(1),
        })
    }

    async fn create_test_app() -> impl actix_web::dev::Service<
        actix_web::dev::ServiceRequest,
        Response = actix_web::dev::ServiceResponse,
        Error = actix_web::Error,
    > {
        let state = create_test_state();
        test::init_service(
            App::new()
                .app_data(state)
                .route("/items", web::post().to(create_item))
                .route("/items", web::get().to(list_items))
                .route("/items/{id}", web::get().to(get_item))
                .route("/items/{id}", web::put().to(update_item))
                .route("/items/{id}", web::delete().to(delete_item))
        ).await
    }

    // Positive Tests
    #[actix_web::test]
    async fn test_create_item_success() {
        let app = create_test_app().await;

        let payload = CreateItemRequest {
            name: "Test Item".to_string(),
            description: "A test item".to_string(),
        };

        let req = test::TestRequest::post()
            .uri("/items")
            .set_json(&payload)
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 201);

        let item: Item = test::read_body_json(resp).await;
        assert_eq!(item.id, 1);
        assert_eq!(item.name, "Test Item");
        assert_eq!(item.description, "A test item");
    }

    #[actix_web::test]
    async fn test_get_item_success() {
        let app = create_test_app().await;

        // Create an item first
        let create_payload = CreateItemRequest {
            name: "Test Item".to_string(),
            description: "A test item".to_string(),
        };

        let req = test::TestRequest::post()
            .uri("/items")
            .set_json(&create_payload)
            .to_request();
        test::call_service(&app, req).await;

        // Get the item
        let req = test::TestRequest::get()
            .uri("/items/1")
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 200);

        let item: Item = test::read_body_json(resp).await;
        assert_eq!(item.id, 1);
        assert_eq!(item.name, "Test Item");
    }

    #[actix_web::test]
    async fn test_list_items() {
        let app = create_test_app().await;

        // Create multiple items
        for i in 1..=3 {
            let payload = CreateItemRequest {
                name: format!("Item {}", i),
                description: format!("Description {}", i),
            };

            let req = test::TestRequest::post()
                .uri("/items")
                .set_json(&payload)
                .to_request();
            test::call_service(&app, req).await;
        }

        // List items
        let req = test::TestRequest::get()
            .uri("/items")
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 200);

        let items: Vec<Item> = test::read_body_json(resp).await;
        assert_eq!(items.len(), 3);
        assert_eq!(items[0].name, "Item 1");
        assert_eq!(items[2].name, "Item 3");
    }

    #[actix_web::test]
    async fn test_update_item_success() {
        let app = create_test_app().await;

        // Create an item
        let create_payload = CreateItemRequest {
            name: "Original".to_string(),
            description: "Original description".to_string(),
        };

        let req = test::TestRequest::post()
            .uri("/items")
            .set_json(&create_payload)
            .to_request();
        test::call_service(&app, req).await;

        // Update the item
        let update_payload = CreateItemRequest {
            name: "Updated".to_string(),
            description: "Updated description".to_string(),
        };

        let req = test::TestRequest::put()
            .uri("/items/1")
            .set_json(&update_payload)
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 200);

        let item: Item = test::read_body_json(resp).await;
        assert_eq!(item.name, "Updated");
        assert_eq!(item.description, "Updated description");
    }

    #[actix_web::test]
    async fn test_delete_item_success() {
        let app = create_test_app().await;

        // Create an item
        let payload = CreateItemRequest {
            name: "To Delete".to_string(),
            description: "Will be deleted".to_string(),
        };

        let req = test::TestRequest::post()
            .uri("/items")
            .set_json(&payload)
            .to_request();
        test::call_service(&app, req).await;

        // Delete the item
        let req = test::TestRequest::delete()
            .uri("/items/1")
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 204);

        // Verify item is deleted
        let req = test::TestRequest::get()
            .uri("/items/1")
            .to_request();

        let resp = test::call_service(&app, req).await;
        assert_eq!(resp.status(), 404);
    }

    // Negative Tests
    #[actix_web::test]
    async fn test_get_nonexistent_item() {
        let app = create_test_app().await;

        let req = test::TestRequest::get()
            .uri("/items/999")
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 404);

        let body: serde_json::Value = test::read_body_json(resp).await;
        assert_eq!(body["error"], "Item not found");
    }

    #[actix_web::test]
    async fn test_update_nonexistent_item() {
        let app = create_test_app().await;

        let payload = CreateItemRequest {
            name: "Updated".to_string(),
            description: "Updated description".to_string(),
        };

        let req = test::TestRequest::put()
            .uri("/items/999")
            .set_json(&payload)
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 404);
    }

    #[actix_web::test]
    async fn test_delete_nonexistent_item() {
        let app = create_test_app().await;

        let req = test::TestRequest::delete()
            .uri("/items/999")
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 404);
    }

    // Edge Cases
    #[actix_web::test]
    async fn test_list_empty_items() {
        let app = create_test_app().await;

        let req = test::TestRequest::get()
            .uri("/items")
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 200);

        let items: Vec<Item> = test::read_body_json(resp).await;
        assert_eq!(items.len(), 0);
    }

    #[actix_web::test]
    async fn test_create_item_with_empty_name() {
        let app = create_test_app().await;

        let payload = CreateItemRequest {
            name: "".to_string(),
            description: "Description".to_string(),
        };

        let req = test::TestRequest::post()
            .uri("/items")
            .set_json(&payload)
            .to_request();

        let resp = test::call_service(&app, req).await;

        // This should ideally return 400, but our simple implementation
        // accepts it. In production, add validation.
        assert_eq!(resp.status(), 201);
    }
}
```

### Example 2: Testing with External Dependencies (Database Mock)

```rust
use actix_web::{test, web, App, HttpResponse};
use async_trait::async_trait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct User {
    id: i32,
    name: String,
    email: String,
}

// Trait for database operations
#[async_trait]
trait UserRepository: Send + Sync {
    async fn find_by_id(&self, id: i32) -> Option<User>;
    async fn create(&self, name: String, email: String) -> User;
}

// Mock implementation for testing
struct MockUserRepository {
    users: std::sync::Mutex<Vec<User>>,
}

#[async_trait]
impl UserRepository for MockUserRepository {
    async fn find_by_id(&self, id: i32) -> Option<User> {
        self.users
            .lock()
            .unwrap()
            .iter()
            .find(|u| u.id == id)
            .cloned()
    }

    async fn create(&self, name: String, email: String) -> User {
        let mut users = self.users.lock().unwrap();
        let id = users.len() as i32 + 1;
        let user = User { id, name, email };
        users.push(user.clone());
        user
    }
}

// Handler
async fn get_user(
    repo: web::Data<Box<dyn UserRepository>>,
    path: web::Path<i32>,
) -> actix_web::Result<HttpResponse> {
    let user_id = path.into_inner();

    match repo.find_by_id(user_id).await {
        Some(user) => Ok(HttpResponse::Ok().json(user)),
        None => Ok(HttpResponse::NotFound().json(serde_json::json!({
            "error": "User not found"
        }))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[actix_web::test]
    async fn test_get_user_with_mock() {
        // Create mock repository with test data
        let mock_repo: Box<dyn UserRepository> = Box::new(MockUserRepository {
            users: std::sync::Mutex::new(vec![
                User {
                    id: 1,
                    name: "Alice".to_string(),
                    email: "alice@example.com".to_string(),
                },
            ]),
        });

        let app = test::init_service(
            App::new()
                .app_data(web::Data::new(mock_repo))
                .route("/users/{id}", web::get().to(get_user))
        ).await;

        let req = test::TestRequest::get()
            .uri("/users/1")
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 200);

        let user: User = test::read_body_json(resp).await;
        assert_eq!(user.id, 1);
        assert_eq!(user.name, "Alice");
    }

    #[actix_web::test]
    async fn test_get_nonexistent_user_with_mock() {
        let mock_repo: Box<dyn UserRepository> = Box::new(MockUserRepository {
            users: std::sync::Mutex::new(vec![]),
        });

        let app = test::init_service(
            App::new()
                .app_data(web::Data::new(mock_repo))
                .route("/users/{id}", web::get().to(get_user))
        ).await;

        let req = test::TestRequest::get()
            .uri("/users/999")
            .to_request();

        let resp = test::call_service(&app, req).await;

        assert_eq!(resp.status(), 404);
    }
}
```

---

## Summary

This guide provides comprehensive patterns for testing Rust Actix-web APIs:

1. **Test Organization**: Unit tests in `src/` with `#[cfg(test)]`, integration tests in `tests/`
2. **Actix-web Testing**: Use `test::init_service()`, `TestRequest`, and `call_service()`
3. **Best Practices**: Test positive, negative, and edge cases; organize by feature; use setup/teardown
4. **Common Crates**: `assert-json-diff`, `test-context`, `mockito` for comprehensive testing
5. **Complete Examples**: CRUD API testing and mocking external dependencies

### Key Takeaways

- Always test both success and failure paths
- Use async test attributes (`#[actix_web::test]` or `#[tokio::test]`)
- Organize tests by feature or endpoint
- Mock external dependencies using traits
- Validate status codes, headers, and response bodies
- Test edge cases and boundary conditions

### Running Tests

```bash
# Run all tests
cargo test

# Run tests with output
cargo test -- --nocapture

# Run specific test
cargo test test_name

# Run tests in parallel (default)
cargo test

# Run tests serially
cargo test -- --test-threads=1

# Run ignored tests
cargo test -- --ignored

# Run integration tests only
cargo test --test integration_test
```

---

## Additional Resources

- [Actix-web Testing Documentation](https://actix.rs/docs/testing/)
- [Rust Book - Testing](https://doc.rust-lang.org/book/ch11-00-testing.html)
- [Tokio Testing Documentation](https://tokio.rs/tokio/topics/testing)
- [assert-json-diff crate](https://docs.rs/assert-json-diff/)
- [test-context crate](https://docs.rs/test-context/)
