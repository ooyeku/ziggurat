# Ziggurat Usage Guide

**Version 1.3.0** | **Zig 0.15.1+** | A modern HTTP server framework for Zig

Welcome to the comprehensive guide for building web applications and APIs with Ziggurat. This guide covers everything from basic setup to advanced features like middleware, metrics, and TLS configuration.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
  - [Server Builder](#server-builder)
  - [Request Handling](#request-handling)
  - [Response Creation](#response-creation)
  - [Routing](#routing)
- [Advanced Features](#advanced-features)
  - [Middleware](#middleware)
  - [Path Parameters](#path-parameters)
  - [Query Parameters](#query-parameters)
  - [Request User Data](#request-user-data)
  - [Environment Configuration](#environment-configuration)
- [Security Features](#security-features)
  - [Rate Limiting](#rate-limiting)
  - [Security Headers](#security-headers)
  - [Sessions](#sessions)
  - [CORS Configuration](#cors-configuration)
  - [Error Handler](#error-handler)
- [Observability](#observability)
  - [Logging](#logging)
  - [Metrics](#metrics)
- [Security](#security)
  - [TLS/HTTPS](#tlshttps)
- [Configuration Reference](#configuration-reference)
- [Complete Examples](#complete-examples)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Installation

### Using Zig Package Manager

Add Ziggurat to your project using `zig fetch`:

```bash
zig fetch https://github.com/ooyeku/ziggurat/archive/refs/tags/v1.3.0.tar.gz
```

### Build Configuration

Add the dependency to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "1.0.0",
    .dependencies = .{
        .ziggurat = .{
            .url = "https://github.com/ooyeku/ziggurat/archive/refs/tags/v1.3.0.tar.gz",
            .hash = "<hash-from-zig-fetch>",
        },
    },
}
```

Configure your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Create main module
    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Get ziggurat dependency
    const ziggurat_dep = b.dependency("ziggurat", .{
        .target = target,
        .optimize = optimize,
    });

    const ziggurat_mod = b.createModule(.{
        .root_source_file = ziggurat_dep.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add import
    main_mod.addImport("ziggurat", ziggurat_mod);

    // Create executable
    const exe = b.addExecutable(.{
        .name = "my-server",
        .root_module = main_mod,
    });

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the server");
    run_step.dependOn(&run_cmd.step);
}
```

---

## Quick Start

Here's a minimal HTTP server in just a few lines:

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    try ziggurat.logger.initGlobalLogger(allocator);

    // Create and configure server
    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8080)
        .build();
    defer server.deinit();

    // Add a route
    try server.get("/", handleRoot);

    // Start the server
    try server.start();
}

fn handleRoot(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.text("Hello, World!");
}
```

Build and run:

```bash
zig build run
```

Test your server:

```bash
curl http://localhost:8080/
```

---

## Core Concepts

### Server Builder

Ziggurat uses the **Builder Pattern** for server configuration, providing a fluent API:

```zig
var builder = ziggurat.ServerBuilder.init(allocator);
var server = try builder
    .host("0.0.0.0")           // Listen on all interfaces
    .port(3000)                // Port number
    .readTimeout(10000)        // Read timeout in milliseconds
    .writeTimeout(10000)       // Write timeout in milliseconds
    .backlog(256)              // Connection backlog
    .bufferSize(4096)          // Read buffer size
    .build();
defer server.deinit();
```

#### Configuration Options

| Method | Type | Default | Description |
|--------|------|---------|-------------|
| `host()` | `[]const u8` | `"127.0.0.1"` | Server host address |
| `port()` | `u16` | `8080` | Server port |
| `readTimeout()` | `u32` | `5000` | Read timeout (ms) |
| `writeTimeout()` | `u32` | `5000` | Write timeout (ms) |
| `backlog()` | `u31` | `128` | Connection backlog |
| `bufferSize()` | `usize` | `1024` | Buffer size for reading requests |
| `enableTls()` | see below | disabled | Enable HTTPS with cert/key |

### Request Handling

Route handlers receive a pointer to the `Request` and return a `Response`:

```zig
fn myHandler(request: *ziggurat.request.Request) ziggurat.response.Response {
    // Access request properties
    const method = request.method;           // GET, POST, PUT, DELETE
    const path = request.path;               // Request path
    const body = request.body;               // Request body (empty if none)
    
    // Access headers
    if (request.headers.get("Content-Type")) |content_type| {
        // Use content_type
    }
    
    // Return response
    return ziggurat.json("{\"status\":\"ok\"}");
}
```

#### Request Properties

```zig
pub const Request = struct {
    method: Method,                              // HTTP method
    path: []const u8,                           // Request path
    headers: std.StringHashMap([]const u8),     // Headers map
    body: []const u8,                           // Request body
    allocator: std.mem.Allocator,              // Request allocator
    user_data: std.StringHashMap([]const u8),  // Custom data storage
};
```

#### Available Methods

```zig
pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    UNKNOWN,
};
```

### Response Creation

Ziggurat provides convenient helper functions for creating responses:

```zig
// JSON response (200 OK)
return ziggurat.json("{\"message\":\"Success\"}");

// Text response (200 OK)
return ziggurat.text("Plain text response");

// Error responses
return ziggurat.errorResponse(.not_found, "Resource not found");
return ziggurat.errorResponse(.bad_request, "Invalid input");
return ziggurat.errorResponse(.internal_server_error, "Server error");
```

#### Custom Response

For more control, create responses directly:

```zig
const ziggurat = @import("ziggurat");

fn customResponse(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.response.Response.init(
        .ok,                    // Status code
        "application/xml",      // Content type
        "<root>XML data</root>" // Body
    );
}
```

#### Status Codes

Available status codes via `ziggurat.Status`:

```zig
.ok                                    // 200
.created                               // 201
.bad_request                           // 400
.unauthorized                          // 401
.forbidden                             // 403
.not_found                             // 404
.method_not_allowed                    // 405
.request_timeout                       // 408
.payload_too_large                     // 413
.unsupported_media_type                // 415
.request_header_fields_too_large       // 431
.internal_server_error                 // 500
```

### Routing

Register routes using HTTP method-specific functions:

```zig
// GET requests
try server.get("/", handleIndex);
try server.get("/users", handleUsers);
try server.get("/users/:id", handleUserById);

// POST requests
try server.post("/users", handleCreateUser);
try server.post("/login", handleLogin);

// PUT requests
try server.put("/users/:id", handleUpdateUser);

// DELETE requests
try server.delete("/users/:id", handleDeleteUser);
```

#### Route Matching

Routes are matched in the order they're registered. The first matching route handles the request.

```zig
try server.get("/users", handleAllUsers);      // Matches: GET /users
try server.get("/users/:id", handleUserById);  // Matches: GET /users/123
try server.get("/users/:id/posts", handleUserPosts);  // Matches: GET /users/123/posts
```

---

## Advanced Features

### Middleware

Middleware functions process requests **before** they reach route handlers. They can:
- Log requests
- Authenticate users
- Add headers
- Short-circuit with early responses
- Store data in the request
- Rate limit requests
- Add security headers

#### Middleware Signature

```zig
fn middleware(request: *ziggurat.request.Request) ?ziggurat.response.Response
```

Return `null` to continue processing, or return a `Response` to short-circuit.

#### Built-in Middleware

Ziggurat includes several built-in middleware modules:

**Request Logging Middleware**
```zig
try server.middleware(ziggurat.request_logger.requestLoggingMiddleware);
```
Automatically logs incoming requests with method, path, and request ID.

**CORS Middleware**
```zig
try ziggurat.cors.initGlobalCorsConfig(allocator);
try server.middleware(ziggurat.cors.corsMiddleware);
```
Handles cross-origin requests and preflight OPTIONS.

**Session Middleware**
```zig
try ziggurat.session_middleware.initGlobalSessionManager(allocator, 3600);
try server.middleware(ziggurat.session_middleware.sessionMiddleware);
```
Manages user sessions with configurable TTL.

**Security Middleware**
```zig
try server.middleware(ziggurat.security.headers.securityMiddleware);
```
Adds essential security headers to responses (X-Frame-Options, X-Content-Type-Options, etc).

**Rate Limiting Middleware**
```zig
try ziggurat.security.rate_limiter.initRateLimiter(allocator, 100); // 100 requests/minute
try server.middleware(ziggurat.security.rate_limiter.rateLimitMiddleware);
```
Implements token bucket rate limiting.

#### Example: Request Logging

```zig
fn logRequests(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        logger.info("[{s}] {s}", .{ 
            @tagName(request.method), 
            request.path 
        }) catch {};
    }
    return null; // Continue processing
}

// Add to server
try server.middleware(logRequests);
```

#### Example: Authentication

```zig
fn requireAuth(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    const auth_header = request.headers.get("Authorization");
    
    if (auth_header == null) {
        return ziggurat.errorResponse(
            .unauthorized,
            "Missing Authorization header"
        );
    }
    
    // Validate token...
    if (!isValidToken(auth_header.?)) {
        return ziggurat.errorResponse(
            .unauthorized,
            "Invalid token"
        );
    }
    
    return null; // Continue to handler
}

try server.middleware(requireAuth);
```

#### Middleware Execution Order

Middleware executes in the order it's added:

```zig
try server.middleware(logRequests);                           // Runs first
try server.middleware(requireAuth);                          // Runs second
try server.middleware(ziggurat.security.headers.securityMiddleware);  // Runs third
// Then route handler runs
```

### Path Parameters

Extract dynamic values from URL paths using the `:parameter` syntax:

```zig
// Register route with parameter
try server.get("/users/:id", handleUserById);
try server.get("/posts/:post_id/comments/:comment_id", handleComment);

fn handleUserById(request: *ziggurat.request.Request) ziggurat.response.Response {
    // Extract parameter
    const user_id = request.getParam("id") orelse {
        return ziggurat.errorResponse(.bad_request, "Missing id parameter");
    };
    
    // Use the parameter
    const allocator = request.allocator;
    const response_json = std.fmt.allocPrint(
        allocator,
        "{{\"user_id\":\"{s}\"}}",
        .{user_id}
    ) catch {
        return ziggurat.errorResponse(.internal_server_error, "Failed to create response");
    };
    
    return ziggurat.json(response_json);
}
```

#### Multiple Parameters

```zig
try server.get("/api/:version/users/:user_id", handleVersionedUser);

fn handleVersionedUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    const version = request.getParam("version") orelse "v1";
    const user_id = request.getParam("user_id") orelse return ziggurat.errorResponse(
        .bad_request,
        "Missing user_id"
    );
    
    // Use both parameters
    // ...
}
```

### Query Parameters

Parse query strings from URLs like `/search?q=zig&page=2`:

```zig
try server.get("/search", handleSearch);

fn handleSearch(request: *ziggurat.request.Request) ziggurat.response.Response {
    // Extract query parameters
    const query = request.getQuery("q") orelse "";
    const page = request.getQuery("page") orelse "1";
    
    // Use the parameters
    const allocator = request.allocator;
    const response_json = std.fmt.allocPrint(
        allocator,
        "{{\"query\":\"{s}\",\"page\":\"{s}\"}}",
        .{ query, page }
    ) catch {
        return ziggurat.errorResponse(.internal_server_error, "Failed to create response");
    };
    
    return ziggurat.json(response_json);
}
```

### Request User Data

Store and retrieve custom data in requests (useful for middleware passing data to handlers):

```zig
// In middleware - store data
fn authMiddleware(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    // Validate user and store user_id
    try request.setUserData("user_id", "12345");
    try request.setUserData("role", "admin");
    return null;
}

// In handler - retrieve data
fn handleProfile(request: *ziggurat.request.Request) ziggurat.response.Response {
    const user_id = request.getUserData("user_id", []const u8) orelse {
        return ziggurat.errorResponse(.unauthorized, "Not authenticated");
    };
    
    const role = request.getUserData("role", []const u8) orelse "user";
    
    // Use the data...
}
```

---

## Environment Configuration

Configure your server using environment variables:

```zig
var builder = try ziggurat.ServerBuilder.fromEnv(allocator);
var server = try builder.build();
```

### Environment Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ZIGGURAT_HOST` | string | `127.0.0.1` | Server host address |
| `ZIGGURAT_PORT` | u16 | `8080` | Server port |
| `ZIGGURAT_READ_TIMEOUT_MS` | u32 | `5000` | Read timeout (ms) |
| `ZIGGURAT_WRITE_TIMEOUT_MS` | u32 | `5000` | Write timeout (ms) |
| `ZIGGURAT_BUFFER_SIZE` | usize | `1024` | Buffer size for reading requests |
| `ZIGGURAT_DEBUG` | bool | `false` | Enable debug mode |

### Environment Helper Functions

```zig
// Read a single environment variable
const value = try ziggurat.config.EnvConfig.getEnv(allocator, "MY_VAR");

// Read with default
const host = try ziggurat.config.EnvConfig.getEnvOr(allocator, "HOST", "127.0.0.1");

// Read integer with default
const port = try ziggurat.config.EnvConfig.getEnvIntOr(u16, allocator, "PORT", 8080);

// Read boolean with default
const debug = try ziggurat.config.EnvConfig.getEnvBoolOr(allocator, "DEBUG", false);
```

---

## Observability

### Logging

Ziggurat includes a built-in logging system with multiple log levels and colored output.

#### Initialize Logger

```zig
// Initialize the global logger
try ziggurat.logger.initGlobalLogger(allocator);

// Get logger instance
const logger = ziggurat.logger.getGlobalLogger().?;
```

#### Log Levels

```zig
// Debug - detailed diagnostic information
try logger.debug("Variable value: {d}", .{some_value});

// Info - general informational messages
try logger.info("Server started on port {d}", .{port});

// Warn - warning messages for potentially harmful situations
try logger.warn("Connection pool nearly full: {d}/{d}", .{current, max});

// Error - error events that might still allow operation
try logger.err("Failed to process request: {any}", .{err});

// Critical - severe errors that may prevent operation
try logger.critical("Database connection lost!", .{});
```

#### Configure Logger

```zig
const logger = ziggurat.logger.getGlobalLogger().?;

// Set minimum log level (default: info)
logger.setLogLevel(.debug);  // Show all logs
logger.setLogLevel(.warn);   // Only warnings and errors

// Disable colors
logger.setEnableColors(false);

// Disable timestamps
logger.setEnableTimestamp(false);
```

#### Log Output Format

```
[2024-01-15 14:32:45] [INFO] Server listening on http://127.0.0.1:8080
[2024-01-15 14:32:50] [DEBUG] Client connected from 127.0.0.1:54321
[2024-01-15 14:32:50] [INFO] [GET] /api/users
[2024-01-15 14:32:51] [ERROR] Database query failed: ConnectionLost
```

### Metrics

Track server performance with the built-in metrics system.

#### Initialize Metrics

```zig
// Initialize with capacity for recent requests
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
defer ziggurat.metrics.deinitGlobalMetrics();
```

#### Automatic Tracking

Metrics are automatically recorded for all requests when initialized:
- Request duration
- Status codes
- Endpoint-specific statistics
- Timestamps

#### Access Metrics

```zig
// Get metrics manager
if (ziggurat.metrics.getGlobalMetrics()) |manager| {
    // Get endpoint statistics
    const stats = try manager.getEndpointStats("GET", "/api/users");
    if (stats) |s| {
        const avg_ms = s.getAverageDuration();
        const total = s.total_requests;
        const min = s.min_duration_ms;
        const max = s.max_duration_ms;
    }
    
    // Get recent requests
    const recent = manager.getRecentRequests();
    for (recent) |metric| {
        // Access: metric.path, metric.method, metric.duration_ms, metric.status_code
    }
}
```

#### Create Metrics Endpoint

```zig
try server.get("/metrics", handleMetrics);

fn handleMetrics(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    
    const allocator = std.heap.page_allocator;
    var metrics_json = std.ArrayList(u8).init(allocator);
    defer metrics_json.deinit();
    
    const writer = metrics_json.writer();
    
    if (ziggurat.metrics.getGlobalMetrics()) |manager| {
        // Build JSON with metrics data
        try writer.writeAll("{\"endpoints\":[");
        
        // Iterate through endpoints and add stats
        // (Implementation details depend on your needs)
        
        try writer.writeAll("]}");
        
        return ziggurat.json(metrics_json.items);
    }
    
    return ziggurat.errorResponse(.internal_server_error, "Metrics not initialized");
}
```

#### Metrics Data Structure

```zig
pub const RequestMetric = struct {
    path: []const u8,
    method: []const u8,
    start_time: i64,
    duration_ms: i64,
    status_code: u16,
};

pub const EndpointStats = struct {
    total_requests: u64,
    total_duration_ms: i64,
    min_duration_ms: i64,
    max_duration_ms: i64,
    
    pub fn getAverageDuration(self: EndpointStats) f64;
};
```

---

## Security

### TLS/HTTPS

Enable HTTPS with TLS certificates:

```zig
var server = try builder
    .host("0.0.0.0")
    .port(443)
    .enableTls("path/to/cert.pem", "path/to/key.pem")
    .build();
```

#### Generate Self-Signed Certificates (Development Only)

```bash
# Generate private key
openssl genrsa -out key.pem 2048

# Generate certificate
openssl req -new -x509 -key key.pem -out cert.pem -days 365
```

**Warning:** Self-signed certificates are for development only. Use proper CA-signed certificates in production.

#### Production Setup Example

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try ziggurat.logger.initGlobalLogger(allocator);
    const logger = ziggurat.logger.getGlobalLogger().?;

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("0.0.0.0")
        .port(443)
        .readTimeout(30000)
        .writeTimeout(30000)
        .enableTls("/etc/ssl/certs/server.crt", "/etc/ssl/private/server.key")
        .build();
    defer server.deinit();

    try server.get("/", handleRoot);
    
    try logger.info("HTTPS server listening on port 443", .{});
    try server.start();
}
```

---

## Security Features

### Rate Limiting

Protect your API from abuse with token bucket rate limiting:

```zig
const allocator = std.heap.page_allocator;

// Initialize rate limiter (100 requests per minute per IP)
try ziggurat.security.rate_limiter.initRateLimiter(allocator, 100);
defer ziggurat.security.rate_limiter.deinitRateLimiter();

// Add to middleware
try server.middleware(ziggurat.security.rate_limiter.rateLimitMiddleware);
```

### Security Headers

Automatically add security headers to all responses:

```zig
// Enable security middleware
try server.middleware(ziggurat.security.headers.securityMiddleware);

// Get production headers
const prod_headers = try ziggurat.security.headers.getProductionHeaders(allocator);

// Get development headers (less strict)
const dev_headers = try ziggurat.security.headers.getDevelopmentHeaders(allocator);

// Sanitize HTML input
const safe_html = try ziggurat.security.headers.sanitizeHtmlInput(allocator, user_input);
```

### Sessions

Store user session data across requests:

```zig
// Initialize session manager with 1-hour TTL
try ziggurat.session_middleware.initGlobalSessionManager(allocator, 3600);
defer ziggurat.session_middleware.deinitGlobalSessionManager();

// Add session middleware
try server.middleware(ziggurat.session_middleware.sessionMiddleware);

// In handler - store session data
fn handleLogin(request: *ziggurat.request.Request) ziggurat.response.Response {
    const user_id = "user123";
    try ziggurat.session_middleware.setSessionValue(request, "user_id", user_id);
    return ziggurat.json("{\"status\":\"logged_in\"}");
}

// In handler - retrieve session data
fn handleProfile(request: *ziggurat.request.Request) ziggurat.response.Response {
    const user_id = ziggurat.session_middleware.getSessionValue(request, "user_id") orelse {
        return ziggurat.errorResponse(.unauthorized, "Not logged in");
    };
    
    return ziggurat.json("{\"user_id\":\"" ++ user_id ++ "\"}");
}
```

### CORS Configuration

Enable cross-origin requests:

```zig
// Initialize CORS
try ziggurat.cors.initGlobalCorsConfig(allocator);
defer ziggurat.cors.deinitGlobalCorsConfig();

// Add CORS middleware
try server.middleware(ziggurat.cors.corsMiddleware);
```

### Error Handler

Standardize error responses with the error handler:

```zig
// Initialize error handler (debug_mode: false for production)
try ziggurat.error_handler.initGlobalErrorHandler(allocator, false);
defer ziggurat.error_handler.deinitGlobalErrorHandler();

// Create standardized error response
fn handleNotFound(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    const error_response = try ziggurat.error_handler.createErrorResponse(
        allocator,
        .not_found,
        "RESOURCE_NOT_FOUND",
        "The requested resource does not exist"
    );
    return error_response;
}
```

---

## Configuration Reference

### ServerConfig Structure

```zig
pub const ServerConfig = struct {
    host: []const u8,              // Default: "127.0.0.1"
    port: u16,                     // Default: 8080
    backlog: u31,                  // Default: 128
    buffer_size: usize,            // Default: 1024
    read_timeout_ms: u32,          // Default: 5000
    write_timeout_ms: u32,         // Default: 5000
    max_header_size: usize,        // Default: 8192
    max_body_size: usize,          // Default: 1048576 (1MB)
    enable_keep_alive: bool,       // Default: true
    tls: TlsConfig,                // Default: disabled
};
```

### Timeouts

```zig
// Short timeouts for API endpoints
var server = try builder
    .readTimeout(5000)   // 5 seconds
    .writeTimeout(5000)
    .build();

// Longer timeouts for file uploads
var server = try builder
    .readTimeout(60000)  // 60 seconds
    .writeTimeout(60000)
    .build();
```

---

## Complete Examples

### REST API with JSON

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

const User = struct {
    id: u32,
    name: []const u8,
};

var users = std.ArrayList(User).init(std.heap.page_allocator);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try ziggurat.logger.initGlobalLogger(allocator);
    try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
    defer ziggurat.metrics.deinitGlobalMetrics();

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(3000)
        .build();
    defer server.deinit();

    // Middleware
    try server.middleware(logRequests);

    // Routes
    try server.get("/users", handleListUsers);
    try server.get("/users/:id", handleGetUser);
    try server.post("/users", handleCreateUser);
    try server.put("/users/:id", handleUpdateUser);
    try server.delete("/users/:id", handleDeleteUser);

    try server.start();
}

fn logRequests(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        logger.info("[{s}] {s}", .{ @tagName(request.method), request.path }) catch {};
    }
    return null;
}

fn handleListUsers(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    const json = "{\"users\":[{\"id\":1,\"name\":\"Alice\"},{\"id\":2,\"name\":\"Bob\"}]}";
    return ziggurat.json(json);
}

fn handleGetUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id = request.getParam("id") orelse {
        return ziggurat.errorResponse(.bad_request, "Missing id");
    };
    
    const allocator = request.allocator;
    const json = std.fmt.allocPrint(
        allocator,
        "{{\"id\":\"{s}\",\"name\":\"User {s}\"}}",
        .{ id, id }
    ) catch {
        return ziggurat.errorResponse(.internal_server_error, "Failed to create response");
    };
    
    return ziggurat.json(json);
}

fn handleCreateUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    if (request.body.len == 0) {
        return ziggurat.errorResponse(.bad_request, "Empty request body");
    }
    
    // Parse body and create user...
    return ziggurat.json("{\"id\":3,\"name\":\"New User\",\"created\":true}");
}

fn handleUpdateUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id = request.getParam("id") orelse {
        return ziggurat.errorResponse(.bad_request, "Missing id");
    };
    
    _ = id;
    // Update user logic...
    return ziggurat.json("{\"success\":true}");
}

fn handleDeleteUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id = request.getParam("id") orelse {
        return ziggurat.errorResponse(.bad_request, "Missing id");
    };
    
    _ = id;
    // Delete user logic...
    return ziggurat.json("{\"deleted\":true}");
}
```

### Static File Server

See [examples/ex2](../examples/ex2) for a complete static file server with:
- File caching
- Content type detection
- Path security (preventing directory traversal)
- HTTPS support

---

## Best Practices

### Memory Management

```zig
// Always use defer for cleanup
var server = try builder.build();
defer server.deinit();

// Use arena allocators for request-scoped allocations
var arena = std.heap.ArenaAllocator.init(allocator);
defer arena.deinit();
const request_allocator = arena.allocator();
```

### Error Handling

```zig
fn safeHandler(request: *ziggurat.request.Request) ziggurat.response.Response {
    const data = fetchData() catch {
        return ziggurat.errorResponse(
            .internal_server_error,
            "Failed to fetch data"
        );
    };
    
    // Use data...
}
```

### Logging Strategy

```zig
// Debug: Detailed diagnostics during development
try logger.debug("Processing request with params: {any}", .{params});

// Info: Important runtime events
try logger.info("User {s} logged in", .{username});

// Warn: Recoverable issues
try logger.warn("API rate limit approaching for user {s}", .{user_id});

// Error: Error conditions that need attention
try logger.err("Database query failed: {any}", .{err});

// Critical: System-threatening issues
try logger.critical("Out of memory!", .{});
```

### Performance Optimization

```zig
// Use appropriate buffer sizes
.bufferSize(4096)  // For typical requests
.bufferSize(8192)  // For larger payloads

// Set realistic timeouts
.readTimeout(5000)   // 5 seconds for APIs
.writeTimeout(5000)

// Initialize metrics for monitoring
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
```

---

## Troubleshooting

### Common Issues

#### Port Already in Use

```
Error: AddressInUse
```

**Solution:** Check if another process is using the port:
```bash
lsof -i :8080
```

Change to a different port:
```zig
.port(3000)
```

#### Request Timeout

```
Error: RequestTimeout
```

**Solution:** Increase timeout values:
```zig
.readTimeout(30000)  // 30 seconds
.writeTimeout(30000)
```

#### TLS Certificate Errors

```
Error: MissingCertificateFile
```

**Solution:** Verify certificate paths exist:
```zig
// Check if files exist before starting
try std.fs.cwd().access("cert.pem", .{});
try std.fs.cwd().access("key.pem", .{});
```

### Debug Mode

Enable debug logging to diagnose issues:

```zig
const logger = ziggurat.logger.getGlobalLogger().?;
logger.setLogLevel(.debug);
```

### Testing Your Server

```bash
# Basic connectivity
curl http://localhost:8080/

# With verbose output
curl -v http://localhost:8080/

# POST request with body
curl -X POST -H "Content-Type: application/json" \
  -d '{"name":"test"}' \
  http://localhost:8080/users

# Test HTTPS (accept self-signed cert)
curl -k https://localhost:443/
```

---

## Additional Resources

- [Examples Directory](../examples/) - Complete working examples
- [GitHub Repository](https://github.com/ooyeku/ziggurat)
- [Zig Documentation](https://ziglang.org/documentation/)

---

## Quick Reference Card

```zig
// Server setup
var server = try ziggurat.ServerBuilder.init(allocator)
    .host("127.0.0.1").port(8080).build();
defer server.deinit();

// Routes
try server.get("/path", handler);
try server.post("/path", handler);
try server.put("/path", handler);
try server.delete("/path", handler);

// Middleware
try server.middleware(myMiddleware);

// Responses
return ziggurat.json(json_string);
return ziggurat.text(text_string);
return ziggurat.errorResponse(.not_found, "Not found");

// Request data
const param = request.getParam("id");
const query = request.getQuery("search");
const header = request.headers.get("Authorization");
const body = request.body;

// Logging
try logger.info("message", .{});
try logger.debug("value: {d}", .{value});
try logger.err("error: {any}", .{err});

// Metrics
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
const stats = try manager.getEndpointStats("GET", "/api/users");
```

---

**Happy building with Ziggurat!**
