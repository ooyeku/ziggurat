# Ziggurat API Reference

Complete API documentation for Ziggurat v1.2.0.

## APIs Overview

Ziggurat provides **two API styles**:

### New API (Recommended)

```zig
const ziggurat = @import("ziggurat");

try ziggurat.features.initialize(allocator, .{
    .logging = .{ .level = .info },
    .metrics = .{ .max_requests = 1000 },
});
defer ziggurat.features.deinitialize();

var builder = ziggurat.ServerBuilder.init(allocator);
var server = try builder.host("0.0.0.0").port(3000).build();
defer server.deinit();

try server.get("/", handler);
try server.start();
```

### Classic API (Backwards Compatible)

```zig
try ziggurat.logger.initGlobalLogger(allocator);
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
defer ziggurat.metrics.deinitGlobalMetrics();
```

---

## Table of Contents

- [Server & Builder](#server--builder)
- [Request](#request)
- [Response](#response)
- [Routing](#routing)
- [Middleware](#middleware)
- [Features Configuration](#features-configuration)
- [Handler & Context](#handler--context)
- [Error Handling](#error-handling)
- [CORS](#cors)
- [Sessions & Cookies](#sessions--cookies)
- [Security](#security)
- [Configuration](#configuration)
- [Utilities](#utilities)
- [Testing](#testing)

---

## Server & Builder

### ServerBuilder

Builder pattern for server configuration.

```zig
pub const ServerBuilder = struct {
    pub fn init(allocator: std.mem.Allocator) ServerBuilder
    pub fn fromEnv(allocator: std.mem.Allocator) !ServerBuilder
    pub fn host(self: *Self, host_addr: []const u8) *Self
    pub fn port(self: *Self, port_num: u16) *Self
    pub fn readTimeout(self: *Self, timeout_ms: u32) *Self
    pub fn writeTimeout(self: *Self, timeout_ms: u32) *Self
    pub fn backlog(self: *Self, size: u31) *Self
    pub fn bufferSize(self: *Self, size: usize) *Self
    pub fn enableTls(self: *Self, cert_file: []const u8, key_file: []const u8) *Self
    pub fn build(self: *Self) !Server
};
```

**Important:** Builder methods mutate `self` and return `*ServerBuilder`. Keep the builder in a `var` binding until `.build()` is called.

### Server

```zig
pub const Server = struct {
    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !Server
    pub fn deinit(self: *Server) void
    pub fn start(self: *Server) !void
    pub fn stop(self: *Server) void
    pub fn get(self: *Server, path: []const u8, h: fn (*Request) Response) !void
    pub fn post(self: *Server, path: []const u8, h: fn (*Request) Response) !void
    pub fn put(self: *Server, path: []const u8, h: fn (*Request) Response) !void
    pub fn delete(self: *Server, path: []const u8, h: fn (*Request) Response) !void
    pub fn patch(self: *Server, path: []const u8, h: fn (*Request) Response) !void
    pub fn head(self: *Server, path: []const u8, h: fn (*Request) Response) !void
    pub fn useMiddleware(self: *Server, mw: fn (*Request) ?Response) !void
};
```

The server uses a thread-per-connection model with arena allocators per connection. Call `stop()` for graceful shutdown.

---

## Request

```zig
pub const Request = struct {
    method: Method,
    path: []const u8,                           // Path only (no query string)
    query_string: []const u8,                   // Raw query string (after '?')
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,
    user_data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Request
    pub fn deinit(self: *Request) void
    pub fn parse(self: *Request, raw_request: []const u8) !void
    pub fn getParam(self: *Request, key: []const u8) ?[]const u8
    pub fn getQuery(self: *Request, key: []const u8) ?[]const u8
    pub fn setUserData(self: *Request, key: []const u8, value: anytype) !void
    pub fn getUserData(self: *Request, key: []const u8, comptime T: type) ?T
};
```

### Method

```zig
pub const Method = enum {
    GET, POST, PUT, DELETE, OPTIONS, HEAD, PATCH, UNKNOWN,

    pub fn fromString(str: []const u8) Method
};
```

### setUserData

Accepts `[]const u8`, string literals, integers, floats, and bools. Values are stored as owned strings.

### getUserData

Returns `?T` where `T` can be `[]const u8`, any integer type, `f32`, `f64`, or `bool`. Returns `null` if the key is absent or the conversion fails.

---

## Response

```zig
pub const Response = struct {
    status: StatusCode,
    content_type: []const u8,
    body: []const u8,
    extra_headers: []const []const u8,          // Optional "Name: Value" strings

    pub fn init(status: StatusCode, content_type: []const u8, body: []const u8) Response
    pub fn json(body: []const u8) Response
    pub fn text(body: []const u8) Response
    pub fn html(body: []const u8) Response
    pub fn errorResponse(status: StatusCode, message: []const u8) Response
    pub fn withStatus(self: Response, status: StatusCode) Response
    pub fn withContentType(self: Response, content_type: []const u8) Response
    pub fn withHeaders(self: Response, headers: []const []const u8) Response
    pub fn format(self: *const Response, allocator: std.mem.Allocator) ![]const u8
};
```

### StatusCode

```zig
pub const StatusCode = enum(u16) {
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,
    moved_permanently = 301,
    found = 302,
    not_modified = 304,
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    request_timeout = 408,
    conflict = 409,
    payload_too_large = 413,
    unsupported_media_type = 415,
    unprocessable_entity = 422,
    too_many_requests = 429,
    request_header_fields_too_large = 431,
    internal_server_error = 500,
    service_unavailable = 503,

    pub fn toString(self: StatusCode) []const u8
};
```

### Convenience Helpers (root module)

```zig
pub fn json(data: []const u8) Response
pub fn text(data: []const u8) Response
pub fn errorResponse(code: StatusCode, message: []const u8) Response
pub fn jsonStruct(allocator: std.mem.Allocator, status: StatusCode, value: anytype) !Response
```

---

## Routing

Routes support dynamic path segments and wildcards:

```zig
try server.get("/users/:id", handleGetUser);
try server.get("/files/*", handleStaticFiles);
```

Path parameters are extracted via `request.getParam("id")`. If the path matches but the method does not, the router returns **405 Method Not Allowed**.

---

## Middleware

### Middleware Pipeline

```zig
pub const Middleware = struct {
    pub fn init(allocator: std.mem.Allocator) Middleware
    pub fn deinit(self: *Middleware) void
    pub fn add(self: *Middleware, handler: MiddlewareHandler) !void
    pub fn process(self: *const Middleware, request: *Request) ?Response
};
```

Return `null` to continue the pipeline. Return a `Response` to short-circuit.

### Built-in Middleware

| Module | Function | Description |
|--------|----------|-------------|
| `request_logger` | `requestLoggingMiddleware` | Logs method, path, request ID |
| `cors` | `corsMiddleware` | CORS headers and preflight handling |
| `session_middleware` | `sessionMiddleware` | Session management |
| `security.headers` | `securityMiddleware` | Security response headers |
| `security.rate_limiter` | `rateLimitMiddleware` | Token bucket rate limiting |

---

## Features Configuration

### Unified Initialization

```zig
try ziggurat.features.initialize(allocator, .{
    .logging = .{ .level = .info, .colors = true, .timestamp = true },
    .metrics = .{ .enabled = true, .max_requests = 1000 },
    .session = .{ .enabled = true, .ttl_seconds = 3600 },
    .cors = .{ .allow_all_origins = true, .max_age = 3600 },
    .rate_limit = .{ .requests_per_minute = 100 },
    .errors = .{ .debug = false },
    .security = .{ .strict_transport_security = true },
});
defer ziggurat.features.deinitialize();
```

### Simplified Logging

```zig
try ziggurat.log.info("message", .{});
try ziggurat.log.debug("value: {d}", .{42});
try ziggurat.log.warn("warning", .{});
try ziggurat.log.err("error", .{});
try ziggurat.log.critical("critical", .{});

ziggurat.log.setLevel(.debug);
ziggurat.log.setColors(false);
ziggurat.log.setTimestamp(true);
```

---

## Handler & Context

### Context

Wrapper around Request for cleaner handler interfaces:

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
};
```

### Handler Status Constants

```zig
pub const handler.status = struct {
    pub const ok = StatusCode.ok;
    pub const created = StatusCode.created;
    pub const no_content = StatusCode.no_content;
    pub const bad_request = StatusCode.bad_request;
    pub const unauthorized = StatusCode.unauthorized;
    pub const forbidden = StatusCode.forbidden;
    pub const not_found = StatusCode.not_found;
    pub const method_not_allowed = StatusCode.method_not_allowed;
    pub const conflict = StatusCode.conflict;
    pub const unsupported_media_type = StatusCode.unsupported_media_type;
    pub const unprocessable_entity = StatusCode.unprocessable_entity;
    pub const too_many_requests = StatusCode.too_many_requests;
    pub const internal_server_error = StatusCode.internal_server_error;
    pub const service_unavailable = StatusCode.service_unavailable;
};
```

---

## Error Handling

### HttpError

```zig
pub const HttpError = error{
    InvalidRequest,
    RequestTimeout,
    PayloadTooLarge,
    HeadersTooLarge,
    UnsupportedMediaType,
    InternalServerError,
    NotFound,
    MethodNotAllowed,
    TooManyRequests,
    ServiceUnavailable,
    UnprocessableEntity,
};

pub fn errorToResponse(err: HttpError) Response
```

### Global Error Handler

```zig
try ziggurat.error_handler.initGlobalErrorHandler(allocator, false);
defer ziggurat.error_handler.deinitGlobalErrorHandler();

const resp = try ziggurat.error_handler.createErrorResponse(
    allocator, .not_found, "RESOURCE_NOT_FOUND", "Not found"
);
```

---

## CORS

```zig
pub const CorsConfig = struct {
    allow_all_origins: bool = true,
    allow_credentials: bool = false,
    max_age: u32 = 3600,
    allow_methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, OPTIONS",
    allow_headers: []const u8 = "Content-Type, Authorization",
};

pub fn initGlobalCorsConfig(allocator: std.mem.Allocator) !void
pub fn deinitGlobalCorsConfig() void
pub fn corsMiddleware(request: *Request) ?Response
pub fn buildCorsHeaders(allocator: std.mem.Allocator) ![][]const u8
```

Preflight (OPTIONS) requests return 204 with full CORS headers. Non-preflight requests set `_cors_enabled=1` in user_data for the server to inject `Access-Control-Allow-Origin`.

---

## Sessions & Cookies

```zig
// Session middleware
try ziggurat.session_middleware.initGlobalSessionManager(allocator, 3600);
defer ziggurat.session_middleware.deinitGlobalSessionManager();
try server.useMiddleware(ziggurat.session_middleware.sessionMiddleware);

// Store/retrieve session data
try ziggurat.session_middleware.setSessionValue(request, "user_id", "123");
const user = ziggurat.session_middleware.getSessionValue(request, "user_id");

// Cookie
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

Token bucket algorithm, one bucket per IP:

```zig
pub fn initRateLimiter(allocator: std.mem.Allocator, requests_per_minute: u32) !void
pub fn deinitRateLimiter() void
pub fn rateLimitMiddleware(request: *Request) ?Response
```

### Security Headers

```zig
pub fn securityMiddleware(request: *Request) ?Response
pub fn getProductionHeaders(allocator: std.mem.Allocator) ![][]const u8
pub fn getDevelopmentHeaders(allocator: std.mem.Allocator) ![][]const u8
pub fn sanitizeHtmlInput(allocator: std.mem.Allocator, input: []const u8) ![]const u8
```

---

## Configuration

```zig
// From environment
var builder = try ziggurat.ServerBuilder.fromEnv(allocator);

// Manual config
const cfg = ziggurat.config.ServerConfig.init("127.0.0.1", 8080);

// TLS
const tls = ziggurat.config.TlsConfig.enableTls(allocator, "cert.pem", "key.pem");

// Environment helpers
const host = try ziggurat.config.EnvConfig.getEnvOr(allocator, "HOST", "127.0.0.1");
const port = try ziggurat.config.EnvConfig.getEnvIntOr(u16, allocator, "PORT", 8080);
const debug = try ziggurat.config.EnvConfig.getEnvBoolOr(allocator, "DEBUG", false);
```

---

## Utilities

### JSON Helpers

```zig
// Serialize Zig value to JSON string (caller owns memory)
const json_str = try ziggurat.json_helpers.jsonify(allocator, myStruct);
defer allocator.free(json_str);

// Parse JSON into Zig type (caller calls .deinit() on result)
const parsed = try ziggurat.json_helpers.parseJson(MyStruct, allocator, json_str);
defer parsed.deinit();
const value = parsed.value;

// Parse form data (application/x-www-form-urlencoded)
var fields = try ziggurat.json_helpers.parseFormData(allocator, body);

// URL decode
const decoded = try ziggurat.json_helpers.urlDecode(allocator, encoded);

// Content type detection from file extension
const ct = ziggurat.json_helpers.detectContentType("image.png"); // "image/png"
```

### Logging

```zig
try ziggurat.logger.initGlobalLogger(allocator);
const logger = ziggurat.logger.getGlobalLogger().?;
try logger.info("message", .{});
logger.setLogLevel(.debug);
logger.setEnableColors(false);
logger.setEnableTimestamp(false);
```

### Metrics

```zig
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
defer ziggurat.metrics.deinitGlobalMetrics();

if (ziggurat.metrics.getGlobalMetrics()) |manager| {
    const stats = try manager.getEndpointStats("GET", "/api/users");
    const recent = manager.getRecentRequests();
    _ = stats;
    _ = recent;
}
```

---

## Testing

### TestRequestBuilder

```zig
var builder = ziggurat.testing_utils.TestRequestBuilder.init(allocator, "/api/users");
defer builder.deinit();

_ = builder.withMethod(.POST);
_ = try builder.withHeader("Content-Type", "application/json");
_ = builder.withBody("{\"name\":\"test\"}");
var request = try builder.buildRequest();
defer request.deinit();
```

### ResponseAssertions

```zig
const response = ziggurat.response.Response.json("{\"status\":\"ok\"}");
var assertions = ziggurat.testing_utils.ResponseAssertions.init(allocator, response);

try assertions.expectStatus(200);
try assertions.expectBody("{\"status\":\"ok\"}");
try assertions.expectContentType("application/json");
try assertions.expectBodyContains("status");
try assertions.expectJsonFieldExists("status");
```
