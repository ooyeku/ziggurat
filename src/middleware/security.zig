//! Security middleware for Ziggurat
//! Provides rate limiting, request size limits, and security headers

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const RateLimiter = @import("../security/rate_limiter.zig").RateLimiter;
const SecurityHeaders = @import("../security/headers.zig");

/// Global rate limiter
var global_rate_limiter: ?*RateLimiter = null;
var global_rate_limiter_allocator: ?std.mem.Allocator = null;

/// Initialize global rate limiter
pub fn initRateLimiter(allocator: std.mem.Allocator, max_requests_per_minute: u32) !void {
    if (global_rate_limiter != null) return error.AlreadyInitialized;

    const limiter = try allocator.create(RateLimiter);
    limiter.* = RateLimiter.init(allocator, @as(f64, @floatFromInt(max_requests_per_minute)), @as(f64, @floatFromInt(max_requests_per_minute)) / 60.0);

    global_rate_limiter = limiter;
    global_rate_limiter_allocator = allocator;
}

/// Get global rate limiter
pub fn getGlobalRateLimiter() ?*RateLimiter {
    return global_rate_limiter;
}

/// Deinitialize global rate limiter
pub fn deinitRateLimiter() void {
    if (global_rate_limiter) |limiter| {
        limiter.deinit();
        if (global_rate_limiter_allocator) |alloc| {
            alloc.destroy(limiter);
        }
    }
    global_rate_limiter = null;
    global_rate_limiter_allocator = null;
}

/// Rate limiting middleware - uses IP address as key
pub fn rateLimitMiddleware(request: *Request) ?Response {
    _ = request; // Unused for now, will be used to extract client IP
    if (global_rate_limiter) |limiter| {
        // In a real implementation, extract client IP from connection
        // For now, use a placeholder
        const client_id = "127.0.0.1";

        if (!limiter.isAllowed(client_id)) {
            return Response.init(.request_timeout, "application/json", "{\"error\":\"rate_limited\"}");
        }
    }

    return null;
}

/// Request size limit middleware
pub fn requestSizeLimitMiddleware(max_body_size: usize) fn (*Request) ?Response {
    return struct {
        fn middleware(request: *Request) ?Response {
            if (request.body.len > max_body_size) {
                return Response.init(.payload_too_large, "application/json", "{\"error\":\"request_body_too_large\"}");
            }
            return null;
        }
    }.middleware;
}

/// Security headers middleware
pub fn securityHeadersMiddleware(production: bool) fn (*Request) ?Response {
    return struct {
        fn middleware(request: *Request) ?Response {
            const allocator = request.allocator;
            const headers = if (production)
                SecurityHeaders.getProductionHeaders(allocator) catch return null
            else
                SecurityHeaders.getDevelopmentHeaders(allocator) catch return null;

            request.setUserData("security_headers", headers) catch {};

            return null;
        }
    }.middleware;
}

/// Input sanitization - basic HTML escaping
pub fn sanitizeHtmlInput(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var buffer = try std.ArrayList(u8).initCapacity(allocator, input.len);
    defer buffer.deinit(allocator);

    for (input) |char| {
        switch (char) {
            '<' => try buffer.appendSlice(allocator, "&lt;"),
            '>' => try buffer.appendSlice(allocator, "&gt;"),
            '"' => try buffer.appendSlice(allocator, "&quot;"),
            '\'' => try buffer.appendSlice(allocator, "&#39;"),
            '&' => try buffer.appendSlice(allocator, "&amp;"),
            else => try buffer.append(allocator, char),
        }
    }

    return try allocator.dupe(u8, buffer.items);
}

test "rate limit middleware" {
    const allocator = std.testing.allocator;

    try initRateLimiter(allocator, 10);
    defer deinitRateLimiter();

    var request = Request.init(allocator);
    defer request.deinit();

    const result = rateLimitMiddleware(&request);
    // Should allow first request
    try std.testing.expect(result == null);
}

test "request size limit" {
    const allocator = std.testing.allocator;
    const middleware = requestSizeLimitMiddleware(100);

    var request = Request.init(allocator);
    defer request.deinit();

    const small_body = try allocator.dupe(u8, "small");
    // Don't free small_body here - request.deinit() will free it
    request.body = small_body;

    const result = middleware(&request);
    try std.testing.expect(result == null);
}

test "sanitize html input" {
    const allocator = std.testing.allocator;

    const input = "<script>alert('xss')</script>";
    const sanitized = try sanitizeHtmlInput(allocator, input);
    defer allocator.free(sanitized);

    try std.testing.expect(std.mem.indexOf(u8, sanitized, "&lt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, sanitized, "&gt;") != null);
}
