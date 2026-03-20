//! Ziggurat - A modern HTTP server framework for Zig
//!
//! This module provides the main public API for the Ziggurat HTTP server framework.
//!
//! ## New API (Recommended)
//!
//! ```zig
//! const ziggurat = @import("ziggurat");
//!
//! pub fn main() !void {
//!     try ziggurat.features.initialize(allocator, .{
//!         .logging = .{ .level = .info },
//!         .metrics  = .{ .max_requests = 1000 },
//!     });
//!     defer ziggurat.features.deinitialize();
//!
//!     var builder = ziggurat.ServerBuilder.init(allocator);
//!     var server = try builder.host("0.0.0.0").port(3000).build();
//!     defer server.deinit();
//!
//!     try server.get("/", handleRoot);
//!     try server.start();
//! }
//!
//! fn handleRoot(req: *ziggurat.request.Request) ziggurat.response.Response {
//!     _ = req;
//!     return ziggurat.response.Response.json("{\"status\":\"ok\"}");
//! }
//! ```

const std = @import("std");
const ServerConfig = @import("config/server_config.zig").ServerConfig;
const HttpServer = @import("server/http_server.zig").HttpServer;
const Request = @import("http/request.zig").Request;
const Method = @import("http/request.zig").Method;
const Response = @import("http/response.zig").Response;
const StatusCode = @import("http/response.zig").StatusCode;

// ============================================================================
// NEW API - Recommended for new projects
// ============================================================================

pub const handler = @import("handler/mod.zig");
pub const features = @import("features/mod.zig");
pub const log = @import("log.zig");

// ============================================================================
// CORE MODULES
// ============================================================================

pub const request = @import("http/request.zig");
pub const response = @import("http/response.zig");
pub const config = struct {
    pub const ServerConfig = @import("config/server_config.zig").ServerConfig;
    pub const TlsConfig = @import("config/tls_config.zig").TlsConfig;
    pub const EnvConfig = @import("config/env_config.zig").EnvConfig;
};

// ============================================================================
// FEATURES & UTILITIES
// ============================================================================

pub const logger = @import("utils/logging.zig");
pub const metrics = @import("metrics.zig");
pub const json_helpers = @import("utils/json_helpers.zig");

// ============================================================================
// MIDDLEWARE & ROUTING
// ============================================================================

pub const middleware = @import("middleware/middleware.zig");
pub const router = @import("router/router.zig");
pub const request_logger = @import("middleware/request_logger.zig");
pub const cors = @import("middleware/cors.zig");
pub const session_middleware = @import("middleware/session.zig");
pub const session = @import("session/session.zig");
pub const cookie = @import("session/cookie.zig");

// ============================================================================
// SECURITY
// ============================================================================

pub const security = struct {
    pub const rate_limiter = @import("security/rate_limiter.zig");
    pub const headers = @import("security/headers.zig");
};
pub const http_error = @import("error/http_error.zig");
pub const error_handler = @import("error/error_handler.zig");

// ============================================================================
// TESTING
// ============================================================================

pub const testing_utils = @import("testing/test_client.zig");

// ============================================================================
// HIGH-LEVEL SERVER API
// ============================================================================

/// High-level Server type that wraps the implementation details.
pub const Server = struct {
    inner: HttpServer,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config_val: ServerConfig) !Self {
        return Self{
            .inner = try HttpServer.init(allocator, config_val),
        };
    }

    pub fn deinit(self: *Self) void {
        self.inner.deinit();
    }

    pub fn start(self: *Self) !void {
        try self.inner.start();
    }

    /// Signal the server to stop accepting new connections.
    pub fn stop(self: *Self) void {
        self.inner.stop();
    }

    pub fn get(self: *Self, path: []const u8, h: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.GET, path, h);
    }

    pub fn post(self: *Self, path: []const u8, h: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.POST, path, h);
    }

    pub fn put(self: *Self, path: []const u8, h: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.PUT, path, h);
    }

    pub fn delete(self: *Self, path: []const u8, h: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.DELETE, path, h);
    }

    /// Register a PATCH route handler (#22 fix).
    pub fn patch(self: *Self, path: []const u8, h: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.PATCH, path, h);
    }

    /// Register a HEAD route handler (#22 fix).
    pub fn head(self: *Self, path: []const u8, h: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.HEAD, path, h);
    }

    pub fn useMiddleware(self: *Self, mw: fn (*Request) ?Response) !void {
        try self.inner.middleware.add(mw);
    }

    /// Backwards-compatible alias for useMiddleware.
    pub fn middleware_fn(self: *Self, mw: fn (*Request) ?Response) !void {
        try self.useMiddleware(mw);
    }
};

/// Builder pattern for configuring and creating a Server.
///
/// ## Usage
///
/// ```zig
/// var builder = ServerBuilder.init(allocator);
/// var server = try builder
///     .host("0.0.0.0")
///     .port(3000)
///     .readTimeout(5000)
///     .build();
/// ```
///
/// Note: builder methods mutate `self` and return `*ServerBuilder`.  Keep the
/// builder alive until `.build()` is called — do not chain from a temporary:
///
/// ```zig
/// // CORRECT
/// var b = ServerBuilder.init(alloc);
/// var srv = try b.port(3000).build();
///
/// // WRONG — undefined behaviour: b is destroyed before build() runs
/// // var srv = try ServerBuilder.init(alloc).port(3000).build();
/// ```
pub const ServerBuilder = struct {
    allocator: std.mem.Allocator,
    server_config: ServerConfig,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .server_config = ServerConfig.init("127.0.0.1", 8080),
        };
    }

    pub fn fromEnv(allocator: std.mem.Allocator) !Self {
        const env_config = try ServerConfig.fromEnv(allocator);
        return Self{
            .allocator = allocator,
            .server_config = env_config,
        };
    }

    pub fn host(self: *Self, host_addr: []const u8) *Self {
        self.server_config.host = host_addr;
        return self;
    }

    pub fn port(self: *Self, port_num: u16) *Self {
        self.server_config.port = port_num;
        return self;
    }

    pub fn readTimeout(self: *Self, timeout_ms: u32) *Self {
        self.server_config.read_timeout_ms = timeout_ms;
        return self;
    }

    pub fn writeTimeout(self: *Self, timeout_ms: u32) *Self {
        self.server_config.write_timeout_ms = timeout_ms;
        return self;
    }

    pub fn backlog(self: *Self, size: u31) *Self {
        self.server_config.backlog = size;
        return self;
    }

    pub fn bufferSize(self: *Self, size: usize) *Self {
        self.server_config.buffer_size = size;
        return self;
    }

    pub fn enableTls(self: *Self, cert_file: []const u8, key_file: []const u8) *Self {
        self.server_config.tls = @import("config/tls_config.zig").TlsConfig.enableTls(self.allocator, cert_file, key_file);
        return self;
    }

    pub fn build(self: *Self) !Server {
        return Server.init(self.allocator, self.server_config);
    }
};

/// Common HTTP status codes for convenience.
pub const Status = struct {
    pub const ok = StatusCode.ok;
    pub const created = StatusCode.created;
    pub const bad_request = StatusCode.bad_request;
    pub const unauthorized = StatusCode.unauthorized;
    pub const forbidden = StatusCode.forbidden;
    pub const not_found = StatusCode.not_found;
    pub const method_not_allowed = StatusCode.method_not_allowed;
    pub const too_many_requests = StatusCode.too_many_requests;
    pub const internal_server_error = StatusCode.internal_server_error;
    pub const service_unavailable = StatusCode.service_unavailable;
    pub const unsupported_media_type = StatusCode.unsupported_media_type;
};

// ── Convenience helpers (thin wrappers; canonical implementations live in
//    response.zig to avoid duplication — #21 fix) ───────────────────────────

/// Create a successful JSON response.
pub fn json(data: []const u8) Response {
    return Response.json(data);
}

/// Create a successful text response.
pub fn text(data: []const u8) Response {
    return Response.text(data);
}

/// Create an error response with a custom status code.
pub fn errorResponse(code: StatusCode, message: []const u8) Response {
    return Response.errorResponse(code, message);
}

/// Serialize a Zig struct to a JSON response.
pub fn jsonStruct(allocator: std.mem.Allocator, status: StatusCode, value: anytype) !Response {
    const json_str = try json_helpers.jsonify(allocator, value);
    return Response.init(status, "application/json", json_str);
}

// ── Tests ─────────────────────────────────────────────────────────────────

test "server builder pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var builder = ServerBuilder.init(allocator);
    _ = builder.host("0.0.0.0").port(3000).readTimeout(5000);

    try testing.expectEqualStrings("0.0.0.0", builder.server_config.host);
    try testing.expectEqual(@as(u16, 3000), builder.server_config.port);
    try testing.expectEqual(@as(u32, 5000), builder.server_config.read_timeout_ms);
}

test "server builder with TLS" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var builder = ServerBuilder.init(allocator);
    _ = builder.host("0.0.0.0").port(3000).enableTls("cert.pem", "key.pem");

    try testing.expectEqualStrings("0.0.0.0", builder.server_config.host);
    try testing.expectEqual(@as(u16, 3000), builder.server_config.port);
    try testing.expect(builder.server_config.tls.enabled);
    try testing.expectEqualStrings("cert.pem", builder.server_config.tls.cert_file.?);
    try testing.expectEqualStrings("key.pem", builder.server_config.tls.key_file.?);
}

test "response helpers" {
    const testing = std.testing;

    const json_response = json("{}");
    try testing.expectEqualStrings("application/json", json_response.content_type);

    const text_response = text("Hello");
    try testing.expectEqualStrings("text/plain", text_response.content_type);

    const error_response = errorResponse(.bad_request, "Invalid input");
    try testing.expectEqual(StatusCode.bad_request, error_response.status);
}
