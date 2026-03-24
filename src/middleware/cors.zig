//! CORS (Cross-Origin Resource Sharing) support for Ziggurat.
//! Adds the correct CORS response headers on preflight (OPTIONS) requests and
//! signals the server to inject CORS headers on non-preflight responses.
//!
//! Header strings are pre-built once at init time so the middleware path
//! performs zero allocations.

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

// ── Global state ─────────────────────────────────────────────────────────────

var global_cors_config: ?CorsConfig = null;
var global_cors_allocator: ?std.mem.Allocator = null;

/// Pre-built header strings (indices 0-3 are heap-allocated; 4 is a literal).
var preflight_strs: [5][]const u8 = .{ "", "", "", "", "" };

pub fn initGlobalCorsConfig(allocator: std.mem.Allocator, cfg: CorsConfig) !void {
    if (global_cors_config != null) return error.AlreadyInitialized;
    global_cors_config = cfg;
    global_cors_allocator = allocator;

    const allow_origin: []const u8 = if (cfg.allow_all_origins) "*" else "null";

    preflight_strs[0] = try std.fmt.allocPrint(allocator, "Access-Control-Allow-Origin: {s}", .{allow_origin});
    errdefer allocator.free(preflight_strs[0]);

    preflight_strs[1] = try std.fmt.allocPrint(allocator, "Access-Control-Allow-Methods: {s}", .{cfg.allow_methods});
    errdefer allocator.free(preflight_strs[1]);

    preflight_strs[2] = try std.fmt.allocPrint(allocator, "Access-Control-Allow-Headers: {s}", .{cfg.allow_headers});
    errdefer allocator.free(preflight_strs[2]);

    preflight_strs[3] = try std.fmt.allocPrint(allocator, "Access-Control-Max-Age: {d}", .{cfg.max_age});
    errdefer allocator.free(preflight_strs[3]);

    preflight_strs[4] = if (cfg.allow_credentials)
        "Access-Control-Allow-Credentials: true"
    else
        "Access-Control-Allow-Credentials: false";
}

pub fn getGlobalCorsConfig() ?CorsConfig {
    return global_cors_config;
}

pub fn deinitGlobalCorsConfig() void {
    if (global_cors_allocator) |allocator| {
        for (preflight_strs[0..4]) |s| {
            if (s.len > 0) allocator.free(s);
        }
    }
    global_cors_config = null;
    global_cors_allocator = null;
    preflight_strs = .{ "", "", "", "", "" };
}

/// CORS middleware.
///
/// - OPTIONS preflight: immediately returns 204 with all required CORS headers.
/// - All other requests: sets `_cors_enabled=1` in user_data so the server can
///   inject `Access-Control-Allow-Origin` into the final response, then
///   returns null to continue the pipeline.
pub fn corsMiddleware(request: *Request) ?Response {
    if (global_cors_config == null) return null;

    if (request.method == .OPTIONS) {
        // Preflight — respond immediately with pre-built headers (zero allocs).
        return Response.init(.no_content, "text/plain", "").withHeaders(&preflight_strs);
    }

    // Non-preflight: mark the request so the server injects the origin header.
    request.setUserData("_cors_enabled", "1") catch {};
    return null;
}

/// Build the minimal CORS headers slice for a non-preflight response.
/// The returned slice is allocated from `allocator`; the string it points
/// to is owned by the CORS module (do not free it individually).
pub fn buildCorsHeaders(allocator: std.mem.Allocator) ![][]const u8 {
    if (global_cors_config == null) return &.{};
    if (preflight_strs[0].len == 0) return &.{};
    const headers = try allocator.alloc([]const u8, 1);
    headers[0] = preflight_strs[0];
    return headers;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

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
    try initGlobalCorsConfig(testing.allocator, CorsConfig.init());
    defer deinitGlobalCorsConfig();

    const headers = try buildCorsHeaders(testing.allocator);
    defer testing.allocator.free(headers);
    // headers[0] is a reference to the pre-built origin header — do not free.

    try testing.expectEqual(@as(usize, 1), headers.len);
    try testing.expectEqualStrings("Access-Control-Allow-Origin: *", headers[0]);
}

test "preflight headers are pre-built at init" {
    try initGlobalCorsConfig(testing.allocator, .{
        .allow_all_origins = true,
        .allow_credentials = true,
        .max_age = 7200,
        .allow_methods = "GET, POST",
        .allow_headers = "X-Custom",
    });
    defer deinitGlobalCorsConfig();

    try testing.expectEqualStrings("Access-Control-Allow-Origin: *", preflight_strs[0]);
    try testing.expectEqualStrings("Access-Control-Allow-Methods: GET, POST", preflight_strs[1]);
    try testing.expectEqualStrings("Access-Control-Allow-Headers: X-Custom", preflight_strs[2]);
    try testing.expectEqualStrings("Access-Control-Max-Age: 7200", preflight_strs[3]);
    try testing.expectEqualStrings("Access-Control-Allow-Credentials: true", preflight_strs[4]);
}

test "deinit resets all cors state" {
    try initGlobalCorsConfig(testing.allocator, CorsConfig.init());
    deinitGlobalCorsConfig();

    try testing.expect(global_cors_config == null);
    try testing.expect(global_cors_allocator == null);
    try testing.expectEqual(@as(usize, 0), preflight_strs[0].len);
}
