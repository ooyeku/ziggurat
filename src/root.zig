//! Ziggurat - A modern HTTP server framework for Zig
//!
//! This module provides the main public API for the Ziggurat HTTP server framework.
//! It is designed to be stable and easy to use while providing powerful features.
//!
//! ## New API (Recommended)
//!
//! ```zig
//! const ziggurat = @import("ziggurat");
//!
//! pub fn main() !void {
//!     var server = try ziggurat.server.Builder.init(allocator)
//!         .host("127.0.0.1")
//!         .port(8080)
//!         .features(.{
//!             .logging = .{ .level = .info },
//!             .metrics = .{ .max_requests = 1000 },
//!         })
//!         .route(.GET, "/", handleRoot)
//!         .use(ziggurat.middleware.logging)
//!         .build();
//!     defer server.deinit();
//!
//!     try server.start();
//! }
//!
//! fn handleRoot(ctx: *ziggurat.handler.Context) !ziggurat.handler.Response {
//!     return ziggurat.handler.Response.json("{\"status\":\"ok\"}");
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
// HIGH-LEVEL SERVER API (Backwards Compatible)
// ============================================================================

/// High-level Server type that wraps the implementation details
pub const Server = struct {
    inner: HttpServer,

    const Self = @This();

    /// Initialize a new server instance
    pub fn init(builder: ServerBuilder) !Self {
        return Self{
            .inner = try HttpServer.init(builder.allocator, builder.config),
        };
    }

    /// Clean up server resources
    pub fn deinit(self: *Self) void {
        self.inner.deinit();
    }

    /// Start the server and begin accepting connections
    pub fn start(self: *Self) !void {
        try self.inner.start();
    }

    /// Add a GET route handler
    pub fn get(self: *Self, path: []const u8, route_handler: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.GET, path, route_handler);
    }

    /// Add a POST route handler
    pub fn post(self: *Self, path: []const u8, route_handler: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.POST, path, route_handler);
    }

    /// Add a PUT route handler
    pub fn put(self: *Self, path: []const u8, route_handler: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.PUT, path, route_handler);
    }

    /// Add a DELETE route handler
    pub fn delete(self: *Self, path: []const u8, route_handler: fn (*Request) Response) !void {
        try self.inner.router.addRoute(.DELETE, path, route_handler);
    }

    /// Add middleware to the processing pipeline
    pub fn middleware(self: *Self, mw_handler: fn (*Request) ?Response) !void {
        try self.inner.middleware.add(mw_handler);
    }
};

/// Builder pattern for configuring and creating a new server
pub const ServerBuilder = struct {
    allocator: std.mem.Allocator,
    config: ServerConfig,

    const Self = @This();

    /// Initialize a new server builder
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .config = ServerConfig.init("127.0.0.1", 8080),
        };
    }

    /// Initialize a new server builder from environment variables
    pub fn fromEnv(allocator: std.mem.Allocator) !Self {
        const env_config = try ServerConfig.fromEnv(allocator);
        return Self{
            .allocator = allocator,
            .config = env_config,
        };
    }

    /// Set the host address
    pub fn host(self: *Self, host_addr: []const u8) *Self {
        self.config.host = host_addr;
        return self;
    }

    /// Set the port number
    pub fn port(self: *Self, port_num: u16) *Self {
        self.config.port = port_num;
        return self;
    }

    /// Set the read timeout in milliseconds
    pub fn readTimeout(self: *Self, timeout_ms: u32) *Self {
        self.config.read_timeout_ms = timeout_ms;
        return self;
    }

    /// Set the write timeout in milliseconds
    pub fn writeTimeout(self: *Self, timeout_ms: u32) *Self {
        self.config.write_timeout_ms = timeout_ms;
        return self;
    }

    /// Set the connection backlog size
    pub fn backlog(self: *Self, size: u31) *Self {
        self.config.backlog = size;
        return self;
    }

    /// Set the read buffer size
    pub fn bufferSize(self: *Self, size: usize) *Self {
        self.config.buffer_size = size;
        return self;
    }

    /// Enable TLS with certificate and key files
    pub fn enableTls(self: *Self, cert_file: []const u8, key_file: []const u8) *Self {
        self.config.tls = @import("config/tls_config.zig").TlsConfig.enableTls(self.allocator, cert_file, key_file);
        return self;
    }

    /// Build and return a new Server instance
    pub fn build(self: *Self) !Server {
        return Server.init(self.*);
    }
};

/// Common HTTP status codes for convenience
pub const Status = struct {
    pub const ok = StatusCode.ok;
    pub const created = StatusCode.created;
    pub const bad_request = StatusCode.bad_request;
    pub const unauthorized = StatusCode.unauthorized;
    pub const forbidden = StatusCode.forbidden;
    pub const not_found = StatusCode.not_found;
    pub const internal_server_error = StatusCode.internal_server_error;
    pub const unsupported_media_type = StatusCode.unsupported_media_type;
};

/// Create a successful JSON response
pub fn json(data: []const u8) Response {
    return Response.init(
        .ok,
        "application/json",
        data,
    );
}

/// Create a successful text response
pub fn text(data: []const u8) Response {
    return Response.init(
        .ok,
        "text/plain",
        data,
    );
}

/// Create an error response with custom status code
pub fn errorResponse(code: StatusCode, message: []const u8) Response {
    return Response.init(
        code,
        "text/plain",
        message,
    );
}

/// Serialize a Zig struct to JSON response
pub fn jsonStruct(allocator: std.mem.Allocator, status: StatusCode, value: anytype) !Response {
    const json_str = try json_helpers.jsonify(allocator, value);
    return Response.init(status, "application/json", json_str);
}

test "server builder pattern" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var builder = ServerBuilder.init(allocator);
    _ = builder.host("0.0.0.0").port(3000).readTimeout(5000);

    try testing.expectEqualStrings("0.0.0.0", builder.config.host);
    try testing.expectEqual(@as(u16, 3000), builder.config.port);
    try testing.expectEqual(@as(u32, 5000), builder.config.read_timeout_ms);
}

test "server builder with TLS" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var builder = ServerBuilder.init(allocator);
    _ = builder.host("0.0.0.0").port(3000).enableTls("cert.pem", "key.pem");

    try testing.expectEqualStrings("0.0.0.0", builder.config.host);
    try testing.expectEqual(@as(u16, 3000), builder.config.port);
    try testing.expect(builder.config.tls.enabled);
    try testing.expectEqualStrings("cert.pem", builder.config.tls.cert_file.?);
    try testing.expectEqualStrings("key.pem", builder.config.tls.key_file.?);
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
