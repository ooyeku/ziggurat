//! Security headers for Ziggurat
//! Provides configuration for security-related HTTP headers

const std = @import("std");
const testing = std.testing;

/// Security headers configuration
pub const SecurityHeadersConfig = struct {
    strict_transport_security: bool = true,
    x_frame_options: bool = true,
    x_content_type_options: bool = true,
    content_security_policy: bool = true,
    referrer_policy: bool = true,
    permissions_policy: bool = true,
    x_xss_protection: bool = true,

    pub fn getHeaders(self: SecurityHeadersConfig, allocator: std.mem.Allocator) ![]const u8 {
        var buffer: [1024]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        if (self.strict_transport_security) {
            try writer.writeAll("Strict-Transport-Security: max-age=31536000; includeSubDomains\r\n");
        }

        if (self.x_frame_options) {
            try writer.writeAll("X-Frame-Options: DENY\r\n");
        }

        if (self.x_content_type_options) {
            try writer.writeAll("X-Content-Type-Options: nosniff\r\n");
        }

        if (self.content_security_policy) {
            try writer.writeAll("Content-Security-Policy: default-src 'self'\r\n");
        }

        if (self.referrer_policy) {
            try writer.writeAll("Referrer-Policy: strict-origin-when-cross-origin\r\n");
        }

        if (self.permissions_policy) {
            try writer.writeAll("Permissions-Policy: accelerometer=(), camera=(), microphone=()\r\n");
        }

        if (self.x_xss_protection) {
            try writer.writeAll("X-XSS-Protection: 1; mode=block\r\n");
        }

        return try allocator.dupe(u8, buffer[0..fbs.pos]);
    }
};

/// Get production-ready security headers
pub fn getProductionHeaders(allocator: std.mem.Allocator) ![]const u8 {
    const config = SecurityHeadersConfig{
        .strict_transport_security = true,
        .x_frame_options = true,
        .x_content_type_options = true,
        .content_security_policy = true,
        .referrer_policy = true,
        .permissions_policy = true,
        .x_xss_protection = true,
    };

    return try config.getHeaders(allocator);
}

/// Get development security headers (more permissive)
pub fn getDevelopmentHeaders(allocator: std.mem.Allocator) ![]const u8 {
    const config = SecurityHeadersConfig{
        .strict_transport_security = false,
        .x_frame_options = true,
        .x_content_type_options = true,
        .content_security_policy = false,
        .referrer_policy = false,
        .permissions_policy = false,
        .x_xss_protection = false,
    };

    return try config.getHeaders(allocator);
}

test "security headers config" {
    const allocator = testing.allocator;
    const config = SecurityHeadersConfig{};
    const headers = try config.getHeaders(allocator);
    defer allocator.free(headers);

    try testing.expect(std.mem.indexOf(u8, headers, "X-Frame-Options") != null);
    try testing.expect(std.mem.indexOf(u8, headers, "X-Content-Type-Options") != null);
}

test "production headers" {
    const allocator = testing.allocator;
    const headers = try getProductionHeaders(allocator);
    defer allocator.free(headers);

    try testing.expect(std.mem.indexOf(u8, headers, "Strict-Transport-Security") != null);
    try testing.expect(std.mem.indexOf(u8, headers, "Content-Security-Policy") != null);
}

test "development headers" {
    const allocator = testing.allocator;
    const headers = try getDevelopmentHeaders(allocator);
    defer allocator.free(headers);

    try testing.expect(std.mem.indexOf(u8, headers, "X-Frame-Options") != null);
}

test "security headers selective config" {
    const allocator = testing.allocator;
    const config = SecurityHeadersConfig{
        .strict_transport_security = true,
        .x_frame_options = false,
        .x_content_type_options = true,
        .content_security_policy = false,
        .referrer_policy = false,
        .permissions_policy = false,
        .x_xss_protection = false,
    };

    const headers = try config.getHeaders(allocator);
    defer allocator.free(headers);

    try testing.expect(std.mem.indexOf(u8, headers, "Strict-Transport-Security") != null);
    try testing.expect(std.mem.indexOf(u8, headers, "X-Frame-Options") == null);
    try testing.expect(std.mem.indexOf(u8, headers, "X-Content-Type-Options") != null);
}

test "all security headers disabled" {
    const allocator = testing.allocator;
    const config = SecurityHeadersConfig{
        .strict_transport_security = false,
        .x_frame_options = false,
        .x_content_type_options = false,
        .content_security_policy = false,
        .referrer_policy = false,
        .permissions_policy = false,
        .x_xss_protection = false,
    };

    const headers = try config.getHeaders(allocator);
    defer allocator.free(headers);

    try testing.expectEqual(@as(usize, 0), headers.len);
}

test "production headers has strict csp" {
    const allocator = testing.allocator;
    const headers = try getProductionHeaders(allocator);
    defer allocator.free(headers);

    try testing.expect(std.mem.indexOf(u8, headers, "Content-Security-Policy") != null);
    try testing.expect(std.mem.indexOf(u8, headers, "default-src 'self'") != null);
}

test "development headers missing strict headers" {
    const allocator = testing.allocator;
    const headers = try getDevelopmentHeaders(allocator);
    defer allocator.free(headers);

    try testing.expect(std.mem.indexOf(u8, headers, "Strict-Transport-Security") == null);
    try testing.expect(std.mem.indexOf(u8, headers, "Content-Security-Policy") == null);
}
