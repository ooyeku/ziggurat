# Ziggurat API Reference

Complete API documentation for Ziggurat

## Table of Contents
- [Server](#server)
- [Routing](#routing)
- [Middleware](#middleware)
- [Request & Response](#request--response)
- [Error Handling](#error-handling)
- [CORS](#cors)
- [Sessions & Cookies](#sessions--cookies)
- [Security](#security)
- [Configuration](#configuration)
- [Utilities](#utilities)
- [Testing](#testing)

---

## Server

### ServerBuilder

Builder pattern for server configuration.

```zig
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
```

### Server

HTTP server instance.

```zig
pub fn deinit(self: *Server) void
pub fn start(self: *Server) !void
pub fn get(self: *Server, path: []const u8, handler: fn(*Request) Response) !void
pub fn post(self: *Server, path: []const u8, handler: fn(*Request) Response) !void
pub fn put(self: *Server, path: []const u8, handler: fn(*Request) Response) !void
pub fn delete(self: *Server, path: []const u8, handler: fn(*Request) Response) !void
pub fn middleware(self: *Server, handler: fn(*Request) ?Response) !void
```

---

## Routing

### Router

Manages HTTP route registration and matching.

```zig
pub fn addRoute(self: *Router, method: Method, path: []const u8, handler: RouteHandler) !void
pub fn matchRoute(self: *Router, request: *Request) ?Response
```

### Path Parameters

Routes support dynamic path segments:

```zig
try server.get("/users/:id", handleGetUser);
try server.get("/posts/:post_id/comments/:comment_id", handleComment);
```

Access in handler:
```zig
const user_id = request.getParam("id") orelse "unknown";
```

---

## Middleware

### Middleware System

Middleware processes requests before route handlers.

```zig
pub fn middleware(self: *Server, handler: fn(*Request) ?Response) !void
```

Return `null` to continue processing, or a `Response` to short-circuit.

### Request Logging Middleware

```zig
pub fn requestLoggingMiddleware(request: *Request) ?Response
pub fn generateRequestId(allocator: std.mem.Allocator) ![]const u8
```

Automatically logs incoming requests with method, path, and request ID.

### CORS Middleware

```zig
pub fn initGlobalCorsConfig(allocator: std.mem.Allocator) !void
pub fn corsMiddleware(request: *Request) ?Response
pub fn deinitGlobalCorsConfig() void

pub const CorsConfig = struct {
    allow_all_origins: bool,
    allow_credentials: bool,
    max_age: u32,
    pub fn init() CorsConfig
};
```

### Security Middleware

```zig
pub fn securityMiddleware(request: *Request) ?Response
```

Adds essential security headers to responses.

### Session Middleware

```zig
pub fn initGlobalSessionManager(allocator: std.mem.Allocator, ttl_seconds: u32) !void
pub fn sessionMiddleware(request: *Request) ?Response
pub fn deinitGlobalSessionManager() void
pub fn setSessionValue(request: *Request, key: []const u8, value: []const u8) !void
pub fn getSessionValue(request: *Request, key: []const u8) ?[]const u8
```

---

## Request & Response

### Request

HTTP request information.

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

### Response

HTTP response to send to client.

```zig
pub const Response = struct {
    status: StatusCode,
    content_type: []const u8,
    body: []const u8,
    pub fn init(status: StatusCode, content_type: []const u8, body: []const u8) Response
    pub fn format(self: *const Response) ![]const u8
};
```

### Convenience Functions

```zig
pub fn json(data: []const u8) Response
pub fn text(data: []const u8) Response
pub fn errorResponse(code: StatusCode, message: []const u8) Response
pub fn jsonStruct(allocator: std.mem.Allocator, status: StatusCode, value: anytype) !Response
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

### Error Handler

```zig
pub const ErrorResponse = struct {
    status: u16,
    code: []const u8,
    message: []const u8,
    details: ?[]const u8 = null,

    pub fn toJson(self: ErrorResponse, allocator: std.mem.Allocator) ![]const u8
};

pub fn createErrorResponse(allocator: std.mem.Allocator, status: StatusCode, code: []const u8, message: []const u8) !Response
pub fn initGlobalErrorHandler(allocator: std.mem.Allocator, debug_mode: bool) !void
pub fn deinitGlobalErrorHandler() void
pub fn statusCodeToErrorCode(status: StatusCode) []const u8
```

---

## CORS

See Middleware section above.

---

## Sessions & Cookies

### Session

```zig
pub const Session = struct {
    id: []const u8,
    data: std.StringHashMap([]const u8),
    pub fn setValue(self: *Session, key: []const u8, value: []const u8) !void
    pub fn getValue(self: *Session, key: []const u8) ?[]const u8
    pub fn removeValue(self: *Session, key: []const u8) void
};
```

### SessionManager

```zig
pub const SessionManager = struct {
    pub fn createSession(self: *SessionManager) ![]const u8
    pub fn getSession(self: *SessionManager, id: []const u8) ?*Session
    pub fn deleteSession(self: *SessionManager, id: []const u8) void
    pub fn cleanupExpired(self: *SessionManager) void
};

pub fn initGlobalSessionManager(allocator: std.mem.Allocator, ttl_seconds: u32) !void
pub fn sessionMiddleware(request: *Request) ?Response
pub fn setSessionValue(request: *Request, key: []const u8, value: []const u8) !void
pub fn getSessionValue(request: *Request, key: []const u8) ?[]const u8
```

### Cookie

```zig
pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    secure: bool = false,
    http_only: bool = true,
    same_site: SameSite = .Strict,
    pub fn serialize(self: Cookie, allocator: std.mem.Allocator) ![]const u8
    pub fn parse(allocator: std.mem.Allocator, cookie_str: []const u8) !Cookie
};

pub const SameSite = enum {
    Strict,
    Lax,
    None,
};
```

---

## Security

### Rate Limiting

```zig
pub const RateLimiter = struct {
    pub fn isAllowed(self: *RateLimiter, key: []const u8) bool
    pub fn getRemainingTokens(self: *RateLimiter, key: []const u8) f64
};

pub fn initRateLimiter(allocator: std.mem.Allocator, max_requests_per_minute: u32) !void
pub fn rateLimitMiddleware(request: *Request) ?Response
pub fn deinitRateLimiter() void
```

### Security Headers

```zig
pub fn getProductionHeaders(allocator: std.mem.Allocator) ![]const u8
pub fn getDevelopmentHeaders(allocator: std.mem.Allocator) ![]const u8
pub fn sanitizeHtmlInput(allocator: std.mem.Allocator, input: []const u8) ![]const u8
pub fn securityMiddleware(request: *Request) ?Response
```

---

## Configuration

### ServerConfig

```zig
pub const ServerConfig = struct {
    host: []const u8,
    port: u16,
    backlog: u31,
    buffer_size: usize,
    read_timeout_ms: u32,
    write_timeout_ms: u32,
    max_header_size: usize,
    max_body_size: usize,
    enable_keep_alive: bool,
    tls: TlsConfig,
    
    pub fn init(host: []const u8, port: u16) ServerConfig
    pub fn fromEnv(allocator: std.mem.Allocator) !ServerConfig
};
```

### TlsConfig

```zig
pub const TlsConfig = struct {
    enabled: bool,
    cert_file: ?[]const u8,
    key_file: ?[]const u8,
    
    pub fn enableTls(allocator: std.mem.Allocator, cert_file: []const u8, key_file: []const u8) TlsConfig
    pub fn disable() TlsConfig
};
```

### EnvConfig

```zig
pub const EnvConfig = struct {
    host: []const u8,
    port: u16,
    read_timeout_ms: u32,
    write_timeout_ms: u32,
    buffer_size: usize,
    debug_mode: bool,
};

pub fn fromEnv(allocator: std.mem.Allocator) !EnvConfig
pub fn getEnv(allocator: std.mem.Allocator, key: []const u8) !?[]const u8
pub fn getEnvOr(allocator: std.mem.Allocator, key: []const u8, default: []const u8) ![]const u8
pub fn getEnvIntOr(comptime T: type, allocator: std.mem.Allocator, key: []const u8, default: T) !T
pub fn getEnvBoolOr(allocator: std.mem.Allocator, key: []const u8, default: bool) !bool
```

---

## Utilities

### JSON Helpers

```zig
pub fn jsonify(allocator: std.mem.Allocator, value: anytype) ![]const u8
pub fn parseJson(comptime T: type, allocator: std.mem.Allocator, json_str: []const u8) !T
pub fn parseFormData(allocator: std.mem.Allocator, body: []const u8) !std.StringHashMap([]const u8)
pub fn detectContentType(path: []const u8) []const u8
```

### Logging

```zig
pub const Logger = struct {
    pub fn debug(self: *Self, comptime format: []const u8, args: anytype) !void
    pub fn info(self: *Self, comptime format: []const u8, args: anytype) !void
    pub fn warn(self: *Self, comptime format: []const u8, args: anytype) !void
    pub fn err(self: *Self, comptime format: []const u8, args: anytype) !void
    pub fn critical(self: *Self, comptime format: []const u8, args: anytype) !void
    pub fn setLogLevel(self: *Self, level: LogLevel) void
    pub fn setEnableColors(self: *Self, enable: bool) void
    pub fn setEnableTimestamp(self: *Self, enable: bool) void
};

pub fn initGlobalLogger(allocator: std.mem.Allocator) !void
pub fn getGlobalLogger() ?*Logger
pub fn deinitGlobalLogger() void
```

### Metrics

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
    
    pub fn getAverageDuration(self: EndpointStats) f64
};

pub fn initGlobalMetrics(allocator: std.mem.Allocator, max_recent_requests: usize) !void
pub fn getGlobalMetrics() ?*MetricsManager
pub fn deinitGlobalMetrics() void
```

---

## Testing

### TestRequestBuilder

```zig
pub const TestRequestBuilder = struct {
    pub fn init(allocator: std.mem.Allocator, path: []const u8) TestRequestBuilder
    pub fn withMethod(self: *Self, method: Method) *Self
    pub fn withBody(self: *Self, body: []const u8) *Self
    pub fn withHeader(self: *Self, key: []const u8, value: []const u8) !*Self
    pub fn buildRequest(self: *Self) !Request
};

pub const ResponseAssertions = struct {
    pub fn expectStatus(self: ResponseAssertions, expected: u16) !void
    pub fn expectBody(self: ResponseAssertions, expected: []const u8) !void
    pub fn expectContentType(self: ResponseAssertions, expected: []const u8) !void
    pub fn expectBodyContains(self: ResponseAssertions, substring: []const u8) !void
};
```

---

## Common Patterns

### Initialize Server

```zig
var builder = ziggurat.ServerBuilder.init(allocator);
var server = try builder
    .host("0.0.0.0")
    .port(3000)
    .readTimeout(10000)
    .writeTimeout(10000)
    .build();
defer server.deinit();
```

### Add Middleware

```zig
try server.middleware(ziggurat.cors.corsMiddleware);
try server.middleware(ziggurat.session_middleware.sessionMiddleware);
try server.middleware(ziggurat.request_logger.requestLoggingMiddleware);
try server.middleware(ziggurat.security.headers.securityMiddleware);
```

### Define Route

```zig
fn handleUsers(request: *ziggurat.request.Request) ziggurat.response.Response {
    return ziggurat.json("{\"users\":[]}");
}

try server.get("/api/users", handleUsers);
```

### Start Server

```zig
try server.start();
```
