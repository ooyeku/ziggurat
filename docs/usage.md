# Ziggurat Usage Guide

**Version 1.2.0** | **Zig 0.15.1+** | A modern HTTP server framework for Zig

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
  - [Custom Response Headers](#custom-response-headers)
  - [Graceful Shutdown](#graceful-shutdown)
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
zig fetch https://github.com/ooyeku/ziggurat/archive/refs/tags/v1.2.0.tar.gz
```

### Build Configuration

Add the dependency to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "1.0.0",
    .dependencies = .{
        .ziggurat = .{
            .url = "https://github.com/ooyeku/ziggurat/archive/refs/tags/v1.2.0.tar.gz",
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

### New API (Recommended)

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize all features in one call
    try ziggurat.features.initialize(allocator, .{
        .logging = .{ .level = .info },
        .metrics = .{ .max_requests = 1000 },
    });
    defer ziggurat.features.deinitialize();

    // Create and configure server
    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8080)
        .build();
    defer server.deinit();

    try server.get("/", handleRoot);
    try server.start();
}

fn handleRoot(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.json("{\"status\":\"ok\"}");
}
```

### Classic API

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger and metrics separately
    try ziggurat.logger.initGlobalLogger(allocator);
    try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
    defer ziggurat.metrics.deinitGlobalMetrics();

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8080)
        .build();
    defer server.deinit();

    try server.get("/", handleRoot);
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

Ziggurat uses the **Builder Pattern** for server configuration:

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

**Important:** Keep the builder alive until `.build()` is called. Do not chain from a temporary:

```zig
// CORRECT
var b = ziggurat.ServerBuilder.init(allocator);
var srv = try b.port(3000).build();

// WRONG — undefined behaviour
// var srv = try ziggurat.ServerBuilder.init(allocator).port(3000).build();
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
    const method = request.method;           // GET, POST, PUT, DELETE, etc.
    const path = request.path;               // Request path (without query string)
    const body = request.body;               // Request body (empty if none)
    const qs = request.query_string;         // Raw query string (after '?')

    // Access headers
    if (request.headers.get("Content-Type")) |content_type| {
        _ = content_type;
    }

    // Access query parameters
    if (request.getQuery("page")) |page| {
        _ = page;
    }

    _ = method;
    _ = path;
    _ = body;
    _ = qs;

    return ziggurat.json("{\"status\":\"ok\"}");
}
```

#### Request Properties

```zig
pub const Request = struct {
    method: Method,                              // HTTP method
    path: []const u8,                           // Request path (no query string)
    query_string: []const u8,                   // Raw query string
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
    OPTIONS,
    HEAD,
    PATCH,
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

// HTML response (200 OK)
return ziggurat.response.Response.html("<h1>Hello</h1>");

// Error responses
return ziggurat.errorResponse(.not_found, "Resource not found");
return ziggurat.errorResponse(.bad_request, "Invalid input");
return ziggurat.errorResponse(.internal_server_error, "Server error");
```

#### Response Builder Pattern

```zig
// Custom status
return ziggurat.response.Response.json(data).withStatus(.created);

// Custom headers
const extra = [_][]const u8{"X-Request-Id: abc123"};
return ziggurat.response.Response.json(data).withHeaders(&extra);
```

#### Status Codes

Available via `ziggurat.response.StatusCode` or `ziggurat.Status`:

```zig
.ok                          // 200
.created                     // 201
.accepted                    // 202
.no_content                  // 204
.moved_permanently           // 301
.found                       // 302
.not_modified                // 304
.bad_request                 // 400
.unauthorized                // 401
.forbidden                   // 403
.not_found                   // 404
.method_not_allowed          // 405
.request_timeout             // 408
.conflict                    // 409
.payload_too_large           // 413
.unsupported_media_type      // 415
.unprocessable_entity        // 422
.too_many_requests           // 429
.request_header_fields_too_large  // 431
.internal_server_error       // 500
.service_unavailable         // 503
```

### Routing

Register routes using HTTP method-specific functions:

```zig
try server.get("/", handleIndex);
try server.get("/users", handleUsers);
try server.get("/users/:id", handleUserById);
try server.post("/users", handleCreateUser);
try server.put("/users/:id", handleUpdateUser);
try server.delete("/users/:id", handleDeleteUser);
try server.patch("/users/:id", handlePatchUser);
try server.head("/users/:id", handleHeadUser);
```

Routes are matched in the order they're registered. If the path matches but the method does not, a **405 Method Not Allowed** response is returned automatically.

---

## Advanced Features

### Middleware

Middleware functions process requests **before** they reach route handlers.

#### Middleware Signature

```zig
fn middleware(request: *ziggurat.request.Request) ?ziggurat.response.Response
```

Return `null` to continue processing, or return a `Response` to short-circuit.

#### Built-in Middleware

```zig
// Request logging
try server.useMiddleware(ziggurat.request_logger.requestLoggingMiddleware);

// CORS
try ziggurat.cors.initGlobalCorsConfig(allocator);
try server.useMiddleware(ziggurat.cors.corsMiddleware);

// Sessions
try ziggurat.session_middleware.initGlobalSessionManager(allocator, 3600);
try server.useMiddleware(ziggurat.session_middleware.sessionMiddleware);

// Security headers
try server.useMiddleware(ziggurat.security.headers.securityMiddleware);

// Rate limiting
try ziggurat.security.rate_limiter.initRateLimiter(allocator, 100);
try server.useMiddleware(ziggurat.security.rate_limiter.rateLimitMiddleware);
```

#### Custom Middleware

```zig
fn requireAuth(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (request.headers.get("Authorization") == null) {
        return ziggurat.errorResponse(.unauthorized, "Missing Authorization header");
    }
    return null;
}

try server.useMiddleware(requireAuth);
```

#### Middleware Execution Order

Middleware executes in the order it's added:

```zig
try server.useMiddleware(logRequests);      // Runs first
try server.useMiddleware(requireAuth);      // Runs second
// Then route handler runs
```

### Path Parameters

Extract dynamic values from URL paths using the `:parameter` syntax:

```zig
try server.get("/users/:id", handleUserById);

fn handleUserById(request: *ziggurat.request.Request) ziggurat.response.Response {
    const user_id = request.getParam("id") orelse {
        return ziggurat.errorResponse(.bad_request, "Missing id parameter");
    };
    _ = user_id;
    return ziggurat.json("{\"user\":\"found\"}");
}
```

### Query Parameters

Query strings are parsed at request time. Access individual parameters with `getQuery`:

```zig
fn handleSearch(request: *ziggurat.request.Request) ziggurat.response.Response {
    const query = request.getQuery("q") orelse "";
    const page = request.getQuery("page") orelse "1";
    _ = query;
    _ = page;
    return ziggurat.json("{\"results\":[]}");
}
```

The raw query string is available via `request.query_string`.

### Request User Data

Store and retrieve custom data in requests (useful for middleware passing data to handlers):

```zig
// In middleware — store data
fn authMiddleware(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    request.setUserData("user_id", "12345") catch {};
    return null;
}

// In handler — retrieve data
fn handleProfile(request: *ziggurat.request.Request) ziggurat.response.Response {
    const user_id = request.getUserData("user_id", []const u8) orelse {
        return ziggurat.errorResponse(.unauthorized, "Not authenticated");
    };
    _ = user_id;
    return ziggurat.json("{\"profile\":\"ok\"}");
}
```

`setUserData` accepts `[]const u8`, numeric, and `bool` values. `getUserData` can cast values back to `[]const u8`, integer types, `f32`/`f64`, or `bool`.

### Custom Response Headers

Attach extra headers to any response:

```zig
const extra = [_][]const u8{
    "X-Request-Id: abc123",
    "Cache-Control: no-cache",
};
return ziggurat.json("{\"ok\":true}").withHeaders(&extra);
```

### Graceful Shutdown

The server supports graceful shutdown:

```zig
server.stop();
```

This sets an atomic shutdown flag and closes the listener socket.

---

## Environment Configuration

Configure your server using environment variables:

```zig
var builder = try ziggurat.ServerBuilder.fromEnv(allocator);
var server = try builder.build();
```

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ZIGGURAT_HOST` | string | `127.0.0.1` | Server host address |
| `ZIGGURAT_PORT` | u16 | `8080` | Server port |
| `ZIGGURAT_READ_TIMEOUT_MS` | u32 | `5000` | Read timeout (ms) |
| `ZIGGURAT_WRITE_TIMEOUT_MS` | u32 | `5000` | Write timeout (ms) |
| `ZIGGURAT_BUFFER_SIZE` | usize | `1024` | Buffer size |
| `ZIGGURAT_DEBUG` | bool | `false` | Enable debug mode |

---

## Observability

### Logging

#### Initialize Logger

```zig
// New API
try ziggurat.features.initialize(allocator, .{
    .logging = .{ .level = .info },
});

// Classic API
try ziggurat.logger.initGlobalLogger(allocator);
```

#### Log Levels

```zig
const logger = ziggurat.logger.getGlobalLogger().?;
try logger.debug("Variable: {d}", .{some_value});
try logger.info("Server started on port {d}", .{port});
try logger.warn("Connection pool nearly full", .{});
try logger.err("Failed to process request", .{});
try logger.critical("Database connection lost!", .{});
```

#### Simplified Logging (New API)

```zig
try ziggurat.log.info("Server started", .{});
try ziggurat.log.debug("Value: {d}", .{42});
```

### Metrics

#### Initialize Metrics

```zig
// New API
try ziggurat.features.initialize(allocator, .{
    .metrics = .{ .max_requests = 1000 },
});

// Classic API
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
defer ziggurat.metrics.deinitGlobalMetrics();
```

Metrics are automatically recorded for all requests: duration, status codes, endpoint statistics, and timestamps.

#### Access Metrics

```zig
if (ziggurat.metrics.getGlobalMetrics()) |manager| {
    const stats = try manager.getEndpointStats("GET", "/api/users");
    if (stats) |s| {
        const avg_ms = s.getAverageDuration();
        _ = avg_ms;
    }
}
```

---

## Security

### TLS/HTTPS

```zig
var builder = ziggurat.ServerBuilder.init(allocator);
var server = try builder
    .host("0.0.0.0")
    .port(443)
    .enableTls("cert.pem", "key.pem")
    .build();
```

Generate self-signed certificates for development:

```bash
openssl genrsa -out key.pem 2048
openssl req -new -x509 -key key.pem -out cert.pem -days 365
```

---

## Security Features

### Rate Limiting

```zig
try ziggurat.security.rate_limiter.initRateLimiter(allocator, 100);
defer ziggurat.security.rate_limiter.deinitRateLimiter();
try server.useMiddleware(ziggurat.security.rate_limiter.rateLimitMiddleware);
```

### Security Headers

```zig
try server.useMiddleware(ziggurat.security.headers.securityMiddleware);
```

### Sessions

```zig
try ziggurat.session_middleware.initGlobalSessionManager(allocator, 3600);
defer ziggurat.session_middleware.deinitGlobalSessionManager();
try server.useMiddleware(ziggurat.session_middleware.sessionMiddleware);
```

### CORS Configuration

```zig
try ziggurat.cors.initGlobalCorsConfig(allocator);
defer ziggurat.cors.deinitGlobalCorsConfig();
try server.useMiddleware(ziggurat.cors.corsMiddleware);
```

CORS handles preflight OPTIONS requests automatically and injects `Access-Control-Allow-Origin` headers on non-preflight responses.

### Error Handler

```zig
try ziggurat.error_handler.initGlobalErrorHandler(allocator, false);
defer ziggurat.error_handler.deinitGlobalErrorHandler();
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

---

## Complete Examples

### REST API with JSON

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    try ziggurat.features.initialize(allocator, .{
        .logging = .{ .level = .info },
        .metrics = .{ .max_requests = 1000 },
    });
    defer ziggurat.features.deinitialize();

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder.host("127.0.0.1").port(3000).build();
    defer server.deinit();

    try server.useMiddleware(ziggurat.request_logger.requestLoggingMiddleware);

    try server.get("/users", handleListUsers);
    try server.get("/users/:id", handleGetUser);
    try server.post("/users", handleCreateUser);

    try server.start();
}

fn handleListUsers(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.json("{\"users\":[]}");
}

fn handleGetUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id = request.getParam("id") orelse {
        return ziggurat.errorResponse(.bad_request, "Missing id");
    };
    _ = id;
    return ziggurat.json("{\"user\":\"found\"}");
}

fn handleCreateUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    if (request.body.len == 0) {
        return ziggurat.errorResponse(.bad_request, "Empty body");
    }
    return ziggurat.response.Response.json("{\"created\":true}").withStatus(.created);
}
```

### Static File Server

See [examples/ex2](../examples/ex2) for a complete static file server.

---

## Best Practices

- **Memory**: Pass allocators explicitly. Use `defer deinit()`. The server uses arena allocators per connection automatically.
- **Middleware**: Return `null` to continue, `Response` to short-circuit. Add in order of priority.
- **Error Handling**: Use `catch` in handlers to convert errors to responses.
- **Logging**: Use `.debug` for development, `.info` for production.
- **Shutdown**: Call `server.stop()` for graceful shutdown.

---

## Troubleshooting

### Port Already in Use

```bash
lsof -i :8080
```

### Request Timeout

```zig
.readTimeout(30000).writeTimeout(30000)
```

### Debug Logging

```zig
const logger = ziggurat.logger.getGlobalLogger().?;
logger.setLogLevel(.debug);
```

### Testing Your Server

```bash
curl http://localhost:8080/
curl -v http://localhost:8080/
curl -X POST -H "Content-Type: application/json" -d '{"name":"test"}' http://localhost:8080/users
```

---

## Quick Reference Card

```zig
// Server setup
var builder = ziggurat.ServerBuilder.init(allocator);
var server = try builder.host("127.0.0.1").port(8080).build();
defer server.deinit();

// Routes
try server.get("/path", handler);
try server.post("/path", handler);
try server.put("/path", handler);
try server.delete("/path", handler);
try server.patch("/path", handler);
try server.head("/path", handler);

// Middleware
try server.useMiddleware(myMiddleware);

// Responses
return ziggurat.json(json_string);
return ziggurat.text(text_string);
return ziggurat.errorResponse(.not_found, "Not found");
return ziggurat.response.Response.json(data).withStatus(.created);

// Request data
const param = request.getParam("id");
const query = request.getQuery("search");
const header = request.headers.get("Authorization");
const body = request.body;
const qs = request.query_string;

// User data (middleware → handler)
try request.setUserData("key", "value");
const val = request.getUserData("key", []const u8);

// Shutdown
server.stop();
```
