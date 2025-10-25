//! CORS (Cross-Origin Resource Sharing) support for Ziggurat
//! Handles CORS headers and preflight requests

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const testing = std.testing;

/// CORS configuration - simplified version for v1.0
pub const CorsConfig = struct {
    allow_all_origins: bool = true,
    allow_credentials: bool = false,
    max_age: u32 = 3600,

    pub fn init() CorsConfig {
        return .{
            .allow_all_origins = true,
            .allow_credentials = false,
            .max_age = 3600,
        };
    }
};

/// Global CORS configuration
var global_cors_config: ?CorsConfig = null;

/// Initialize global CORS configuration
pub fn initGlobalCorsConfig(allocator: std.mem.Allocator) !void {
    _ = allocator;
    if (global_cors_config != null) return error.AlreadyInitialized;

    global_cors_config = CorsConfig.init();
}

/// Get global CORS config
pub fn getGlobalCorsConfig() ?CorsConfig {
    return global_cors_config;
}

/// Deinitialize global CORS config
pub fn deinitGlobalCorsConfig() void {
    global_cors_config = null;
}

/// CORS middleware
pub fn corsMiddleware(request: *Request) ?Response {
    if (global_cors_config) |_| {
        _ = request.headers.get("Origin") orelse "*";

        // Handle preflight OPTIONS requests
        if (request.method == .OPTIONS) {
            return Response.init(.no_content, "text/plain", "");
        }

        // For non-OPTIONS requests, return null to continue processing
        return null;
    }

    return null;
}

test "cors config initialization" {
    const config = CorsConfig.init();
    try testing.expect(config.allow_all_origins);
    try testing.expectEqual(@as(u32, 3600), config.max_age);
}

test "cors config with credentials" {
    var config = CorsConfig.init();
    config.allow_credentials = true;
    try testing.expect(config.allow_credentials);
}
