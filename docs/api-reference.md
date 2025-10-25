# Ziggurat API Reference

Complete API documentation for Ziggurat

## APIs Overview

Ziggurat provides **two API styles**:

### New API (Recommended) - Cleaner & More Intuitive
Introduced in v2.0, this API is simpler and more discoverable. Use this for new projects.

```zig
const ziggurat = @import("ziggurat");

var server = try ziggurat.ServerBuilder.init(allocator)
    .host("127.0.0.1")
    .port(8080)
    .build();

// Features configured in one place
try ziggurat.features.initialize(allocator, .{
    .logging = .{ .level = .info },
    .metrics = .{ .max_requests = 1000 },
});

// Simplified logging
try ziggurat.log.info("Server started", .{});

// Response builder
return ziggurat.response.Response.json(data)
    .withStatus(.ok);
```

### Classic API (Backwards Compatible) - Fully Functional
Original API that continues to work. Existing projects can migrate gradually.

---

## Table of Contents

- [New API Features](#new-api-features)
- [Server & Builder](#server--builder)
- [Handler & Context](#handler--context)
- [Routing](#routing)
- [Middleware](#middleware)
- [Features Configuration](#features-configuration)
- [Request & Response](#request--response)
- [Error Handling](#error-handling)
- [CORS](#cors)
- [Sessions & Cookies](#sessions--cookies)
- [Security](#security)
- [Configuration](#configuration)
- [Utilities](#utilities)
- [Testing](#testing)

---

## New API Features

### Unified Features Initialization

Initialize all features with a single configuration:

```zig
try ziggurat.features.initialize(allocator, .{
    .logging = .{
        .level = .info,
        .colors = true,
        .timestamp = true,
    },
    .metrics = .{
        .enabled = true,
        .max_requests = 1000,
    },
    .session = .{
        .enabled = true,
        .ttl_seconds = 3600,
    },
    .cors = .{
        .allow_all_origins = true,
        .max_age = 3600,
    },
    .rate_limit = .{
        .requests_per_minute = 100,
    },
    .errors = .{
        .debug = false,
    },
    .security = .{
        .strict_transport_security = true,
    },
});
defer ziggurat.features.deinitialize();
```

### Simplified Logging

Direct logging without getting the global logger:

```zig
try ziggurat.log.debug("Debug: {d}", .{value});
try ziggurat.log.info("Info message", .{});
try ziggurat.log.warn("Warning", .{});
try ziggurat.log.err("Error occurred", .{});
try ziggurat.log.critical("Critical!", .{});

ziggurat.log.setLevel(.debug);
ziggurat.log.setColors(false);
ziggurat.log.setTimestamp(true);
```

### Response Builder Pattern

Fluent response creation:

```zig
// JSON response
return ziggurat.response.Response.json(data);

// Text response  
return ziggurat.response.Response.text("Hello");

// HTML response
return ziggurat.response.Response.html("<h1>Title</h1>");

// Error response
return ziggurat.response.Response.errorResponse(.bad_request, "Invalid");

// With chaining
return ziggurat.response.Response.json(data)
    .withStatus(.created)
    .withContentType("application/json");
```

### Handler Context

Cleaner handler interface (planned future enhancement):

```zig
fn handleUser(ctx: *ziggurat.handler.Context) ziggurat.handler.Response {
    const user_id = ctx.param("id") orelse {
        return ziggurat.handler.Response.errorResponse(.bad_request, "Missing id");
    };
    
    const query_limit = ctx.query("limit") orelse "10";
    const auth_header = ctx.header("Authorization");
    
    // Session management
    try ctx.session.set("user_id", user_id);
    const stored_user = ctx.session.get("user_id");
    
    return ziggurat.handler.Response.json("{...}");
}
```

---

## Server & Builder

### ServerBuilder

Builder pattern for server configuration:

```zig
var server = try ziggurat.ServerBuilder.init(allocator)
    .host("0.0.0.0")
    .port(3000)
    .readTimeout(10000)
    .writeTimeout(10000)
    .backlog(256)
    .bufferSize(4096)
    .enableTls("cert.pem", "key.pem")
    .build();
```

### Server

HTTP server instance:

```zig
pub fn deinit(self: *Server) void
pub fn start(self: *Server) !void
pub fn get(self: *Server, path: []const u8, route_handler: fn(*Request) Response) !void
pub fn post(self: *Server, path: []const u8, route_handler: fn(*Request) Response) !void
pub fn put(self: *Server, path: []const u8, route_handler: fn(*Request) Response) !void
pub fn delete(self: *Server, path: []const u8, route_handler: fn(*Request) Response) !void
pub fn middleware(self: *Server, mw_handler: fn(*Request) ?Response) !void
```

---

## Handler & Context

### Handler Response Types

```zig
pub const Context = struct {
    request: *Request,
    allocator: std.mem.Allocator,
    
    pub fn param(self: *Self, name: []const u8) ?[]const u8
    pub fn query(self: *Self, name: []const u8) ?[]const u8
    pub fn header(self: *Self, name: []const u8) ?[]const u8
    pub fn method(self: *Self) Method
    pub fn path(self: *Self) []const u8
    pub fn body(self: *Self) []const u8
    pub fn session.set(self: *Self, key: []const u8, value: []const u8) !void
    pub fn session.get(self: *Self, key: []const u8) ?[]const u8
};
```

### Response Helpers

```zig
pub const Response = struct {
    pub fn init(status: StatusCode, content_type: []const u8, body: []const u8) Response
    pub fn json(body: []const u8) Response
    pub fn text(body: []const u8) Response
    pub fn html(body: []const u8) Response
    pub fn errorResponse(status: StatusCode, message: []const u8) Response
    pub fn withStatus(self: Response, status: StatusCode) Response
    pub fn withContentType(self: Response, content_type: []const u8) Response
    pub fn format(self: *const Response) ![]const u8
};
```

---

## Routing

Routes support dynamic path segments:

```zig
try server.get("/users/:id", handleGetUser);
try server.post("/posts/:post_id/comments/:comment_id", handleComment);

fn handleGetUser(request: *Request) Response {
    const user_id = request.getParam("id") orelse "unknown";
    // ...
}
```

---

## Middleware

### Middleware System

```zig
fn myMiddleware(request: *Request) ?Response {
    // Return null to continue, Response to short-circuit
    if (shouldBlock) {
        return Response.errorResponse(.unauthorized, "Blocked");
    }
    return null;
}

try server.middleware(myMiddleware);
```

### Built-in Middleware

```zig
try server.middleware(ziggurat.request_logger.requestLoggingMiddleware);
try server.middleware(ziggurat.cors.corsMiddleware);
try server.middleware(ziggurat.session_middleware.sessionMiddleware);
try server.middleware(ziggurat.security.headers.securityMiddleware);
try server.middleware(ziggurat.security.rate_limiter.rateLimitMiddleware);
```

---

## Features Configuration

### Features Module

Unified configuration for all server features:

```zig
pub const LoggingConfig = struct {
    enabled: bool = true,
    level: enum { debug, info, warn, err, critical } = .info,
    colors: bool = true,
    timestamp: bool = true,
};

pub const MetricsConfig = struct {
    enabled: bool = true,
    max_requests: usize = 1000,
};

pub const SessionConfig = struct {
    enabled: bool = true,
    ttl_seconds: u32 = 3600,
};

pub const CorsConfig = struct {
    enabled: bool = true,
    allow_all_origins: bool = true,
    allow_credentials: bool = false,
    max_age: u32 = 3600,
};

pub const RateLimitConfig = struct {
    enabled: bool = true,
    requests_per_minute: u32 = 1000,
};

pub const ErrorConfig = struct {
    enabled: bool = true,
    debug: bool = false,
    show_stack_traces: bool = false,
};

pub const SecurityConfig = struct {
    enabled: bool = true,
    strict_transport_security: bool = true,
    content_security_policy: bool = true,
    x_frame_options: bool = true,
    x_content_type_options: bool = true,
};
```

---

## Request & Response

### Request

```zig
pub const Request = struct {
    method: Method,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,
    user_data: std.StringHashMap([]const u8),
    
    pub fn getParam(self: *Request, name: []const u8) ?[]const u8
    pub fn getQuery(self: *Request, name: []const u8) ?[]const u8
    pub fn setUserData(self: *Request, key: []const u8, value: anytype) !void
    pub fn getUserData(self: *Request, key: []const u8, comptime T: type) ?T
};
```

### StatusCode

```zig
pub const StatusCode = enum(u16) {
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    conflict = 409,
    method_not_allowed = 405,
    request_timeout = 408,
    payload_too_large = 413,
    request_header_fields_too_large = 431,
    unsupported_media_type = 415,
    internal_server_error = 500,
};
```

---

## Error Handling

```zig
try ziggurat.error_handler.initGlobalErrorHandler(allocator, false);
defer ziggurat.error_handler.deinitGlobalErrorHandler();

const error_resp = try ziggurat.error_handler.createErrorResponse(
    allocator,
    .not_found,
    "RESOURCE_NOT_FOUND",
    "The resource does not exist"
);
```

---

## CORS

```zig
try ziggurat.cors.initGlobalCorsConfig(allocator);
try server.middleware(ziggurat.cors.corsMiddleware);
```

---

## Sessions & Cookies

```zig
try ziggurat.session_middleware.initGlobalSessionManager(allocator, 3600);
try ziggurat.session_middleware.setSessionValue(request, "user_id", "123");
const user = ziggurat.session_middleware.getSessionValue(request, "user_id");

const cookie = ziggurat.cookie.Cookie{
    .name = "session",
    .value = "abc123",
    .secure = true,
    .http_only = true,
    .same_site = .Strict,
};
```

---

## Security

### Rate Limiting

```zig
try ziggurat.security.rate_limiter.initRateLimiter(allocator, 100);
try server.middleware(ziggurat.security.rate_limiter.rateLimitMiddleware);
```

### Security Headers

```zig
try server.middleware(ziggurat.security.headers.securityMiddleware);
```

---

## Configuration

```zig
// From environment
var builder = try ziggurat.ServerBuilder.fromEnv(allocator);

// Manual config
const config = ziggurat.config.ServerConfig.init("127.0.0.1", 8080);

// TLS
const tls = ziggurat.config.TlsConfig.enableTls(allocator, "cert.pem", "key.pem");

// Environment helpers
const host = try ziggurat.config.EnvConfig.getEnvOr(allocator, "HOST", "127.0.0.1");
const port = try ziggurat.config.EnvConfig.getEnvIntOr(u16, allocator, "PORT", 8080);
```

---

## Utilities

### JSON Helpers

```zig
const json_str = try ziggurat.json_helpers.jsonify(allocator, myStruct);
const parsed = try ziggurat.json_helpers.parseJson(MyStruct, allocator, json_str);
```

### Logging

```zig
try ziggurat.logger.initGlobalLogger(allocator);
const logger = ziggurat.logger.getGlobalLogger().?;
try logger.info("message", .{});
```

### Metrics

```zig
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
if (ziggurat.metrics.getGlobalMetrics()) |manager| {
    const stats = try manager.getEndpointStats("GET", "/api/users");
}
```

---

## Testing

```zig
var builder = ziggurat.testing_utils.TestRequestBuilder.init(allocator, "/api/users");
var test_request = try builder
    .withMethod(.POST)
    .withHeader("Content-Type", "application/json")
    .buildRequest();
```
