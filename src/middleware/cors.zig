//! CORS (Cross-Origin Resource Sharing) support for Ziggurat.
//! Adds the correct CORS response headers on preflight (OPTIONS) requests and
//! signals the server to inject CORS headers on non-preflight responses.

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const testing = std.testing;

pub const CorsConfig = struct {
    allow_all_origins: bool = true,
    allow_credentials: bool = false,
    max_age: u32 = 3600,
    allow_methods: []const u8 = "GET, POST, PUT, DELETE, PATCH, OPTIONS",
    allow_headers: []const u8 = "Content-Type, Authorization",

    pub fn init() CorsConfig {
        return .{};
    }
};

var global_cors_config: ?CorsConfig = null;

pub fn initGlobalCorsConfig(allocator: std.mem.Allocator) !void {
    _ = allocator;
    if (global_cors_config != null) return error.AlreadyInitialized;
    global_cors_config = CorsConfig.init();
}

pub fn getGlobalCorsConfig() ?CorsConfig {
    return global_cors_config;
}

pub fn deinitGlobalCorsConfig() void {
    global_cors_config = null;
}

/// CORS middleware.
///
/// - OPTIONS preflight: immediately returns 204 with all required CORS headers.
/// - All other requests: sets `_cors_enabled=1` in user_data so the server can
///   inject `Access-Control-Allow-Origin` into the final response, then
///   returns null to continue the pipeline.
pub fn corsMiddleware(request: *Request) ?Response {
    const cfg = global_cors_config orelse return null;

    if (request.method == .OPTIONS) {
        // Preflight — respond immediately with full CORS headers.
        // We allocate the header strings with page_allocator here because
        // the Response struct holds slices but does not own them; the strings
        // must outlive the send path.  For a static config this is acceptable.
        const alloc = std.heap.page_allocator;
        const allow_origin: []const u8 = if (cfg.allow_all_origins) "*" else "null";

        const h0 = std.fmt.allocPrint(alloc, "Access-Control-Allow-Origin: {s}", .{allow_origin}) catch "Access-Control-Allow-Origin: *";
        const h1 = std.fmt.allocPrint(alloc, "Access-Control-Allow-Methods: {s}", .{cfg.allow_methods}) catch "";
        const h2 = std.fmt.allocPrint(alloc, "Access-Control-Allow-Headers: {s}", .{cfg.allow_headers}) catch "";
        const h3 = std.fmt.allocPrint(alloc, "Access-Control-Max-Age: {d}", .{cfg.max_age}) catch "";
        const h4: []const u8 = if (cfg.allow_credentials) "Access-Control-Allow-Credentials: true" else "Access-Control-Allow-Credentials: false";

        const headers = alloc.alloc([]const u8, 5) catch return Response.init(.no_content, "text/plain", "");
        headers[0] = h0;
        headers[1] = h1;
        headers[2] = h2;
        headers[3] = h3;
        headers[4] = h4;

        return Response.init(.no_content, "text/plain", "").withHeaders(headers);
    }

    // Non-preflight: mark the request so the server injects the origin header.
    request.setUserData("_cors_enabled", "1") catch {};
    return null;
}

/// Build the minimal CORS headers slice for a non-preflight response.
/// Returns an empty slice if CORS is not configured.
/// The caller must free each string and the slice itself using `allocator`.
pub fn buildCorsHeaders(allocator: std.mem.Allocator) ![][]const u8 {
    const cfg = global_cors_config orelse return &.{};
    const allow_origin: []const u8 = if (cfg.allow_all_origins) "*" else "null";

    const headers = try allocator.alloc([]const u8, 1);
    headers[0] = try std.fmt.allocPrint(allocator, "Access-Control-Allow-Origin: {s}", .{allow_origin});
    return headers;
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

test "buildCorsHeaders returns empty slice when cors not configured" {
    global_cors_config = null;
    const headers = try buildCorsHeaders(testing.allocator);
    try testing.expectEqual(@as(usize, 0), headers.len);
}

test "buildCorsHeaders returns allow-origin header when configured" {
    global_cors_config = CorsConfig.init();
    defer global_cors_config = null;

    const headers = try buildCorsHeaders(testing.allocator);
    defer {
        for (headers) |h| testing.allocator.free(h);
        testing.allocator.free(headers);
    }

    try testing.expectEqual(@as(usize, 1), headers.len);
    try testing.expectEqualStrings("Access-Control-Allow-Origin: *", headers[0]);
}
