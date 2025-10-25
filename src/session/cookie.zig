//! Cookie management for Ziggurat
//! Provides secure cookie handling with standard options

const std = @import("std");
const testing = std.testing;

/// Cookie configuration
pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    path: []const u8 = "/",
    domain: ?[]const u8 = null,
    secure: bool = false,
    http_only: bool = true,
    same_site: SameSite = .Strict,
    max_age: ?u32 = null,

    pub const SameSite = enum {
        Strict,
        Lax,
        None,

        pub fn toString(self: SameSite) []const u8 {
            return switch (self) {
                .Strict => "Strict",
                .Lax => "Lax",
                .None => "None",
            };
        }
    };

    /// Free allocated memory for cookie fields (path, domain)
    /// Only call this if the cookie was created with parse() or if you allocated the fields
    pub fn deinit(self: *Cookie, allocator: std.mem.Allocator) void {
        // Only free path if it's not the default "/"
        if (self.path.ptr != "/".ptr) {
            allocator.free(self.path);
        }
        if (self.domain) |domain| {
            allocator.free(domain);
        }
    }

    pub fn serialize(self: Cookie, allocator: std.mem.Allocator) ![]const u8 {
        var buffer: [512]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        // Basic cookie
        try std.fmt.format(writer, "{s}={s}", .{ self.name, self.value });

        // Path
        try std.fmt.format(writer, "; Path={s}", .{self.path});

        // Domain
        if (self.domain) |domain| {
            try std.fmt.format(writer, "; Domain={s}", .{domain});
        }

        // Secure
        if (self.secure) {
            try writer.writeAll("; Secure");
        }

        // HttpOnly
        if (self.http_only) {
            try writer.writeAll("; HttpOnly");
        }

        // SameSite
        try std.fmt.format(writer, "; SameSite={s}", .{self.same_site.toString()});

        // MaxAge
        if (self.max_age) |age| {
            try std.fmt.format(writer, "; Max-Age={d}", .{age});
        }

        return try allocator.dupe(u8, buffer[0..fbs.pos]);
    }

    /// Parse a cookie from Set-Cookie header format
    pub fn parse(allocator: std.mem.Allocator, cookie_str: []const u8) !Cookie {
        var parts = std.mem.splitScalar(u8, cookie_str, ';');

        // First part is name=value
        const first_part = parts.next() orelse return error.InvalidCookie;
        const equals_idx = std.mem.indexOf(u8, first_part, "=") orelse return error.InvalidCookie;

        const name = std.mem.trim(u8, first_part[0..equals_idx], " ");
        const value = std.mem.trim(u8, first_part[equals_idx + 1 ..], " ");

        var cookie = Cookie{
            .name = try allocator.dupe(u8, name),
            .value = try allocator.dupe(u8, value),
        };

        // Parse additional attributes
        while (parts.next()) |part| {
            const trimmed = std.mem.trim(u8, part, " ");
            if (std.mem.eql(u8, trimmed, "Secure")) {
                cookie.secure = true;
            } else if (std.mem.eql(u8, trimmed, "HttpOnly")) {
                cookie.http_only = true;
            } else if (std.mem.startsWith(u8, trimmed, "Path=")) {
                cookie.path = try allocator.dupe(u8, trimmed[5..]);
            } else if (std.mem.startsWith(u8, trimmed, "Domain=")) {
                cookie.domain = try allocator.dupe(u8, trimmed[7..]);
            }
        }

        return cookie;
    }
};

/// Extract session cookie from Cookie header
pub fn getSessionCookie(allocator: std.mem.Allocator, cookie_header: []const u8, session_cookie_name: []const u8) ?[]const u8 {
    var cookies = std.mem.splitScalar(u8, cookie_header, ';');

    while (cookies.next()) |cookie_str| {
        const trimmed = std.mem.trim(u8, cookie_str, " ");

        if (std.mem.startsWith(u8, trimmed, session_cookie_name)) {
            if (std.mem.indexOf(u8, trimmed, "=")) |eq_idx| {
                const value = trimmed[eq_idx + 1 ..];
                return allocator.dupe(u8, value) catch null;
            }
        }
    }

    return null;
}

test "cookie serialize" {
    const allocator = testing.allocator;
    const cookie = Cookie{
        .name = "session_id",
        .value = "abc123",
        .secure = true,
        .http_only = true,
        .same_site = .Strict,
    };

    const serialized = try cookie.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "session_id=abc123") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "Secure") != null);
    try testing.expect(std.mem.indexOf(u8, serialized, "HttpOnly") != null);
}

test "cookie parse" {
    const allocator = testing.allocator;
    const cookie_str = "session_id=abc123; Path=/; Secure; HttpOnly";

    var cookie = try Cookie.parse(allocator, cookie_str);
    defer allocator.free(cookie.name);
    defer allocator.free(cookie.value);
    defer cookie.deinit(allocator);

    try testing.expectEqualStrings("session_id", cookie.name);
    try testing.expectEqualStrings("abc123", cookie.value);
    try testing.expect(cookie.secure);
    try testing.expect(cookie.http_only);
}

test "get session cookie" {
    const allocator = testing.allocator;
    const cookie_header = "session_id=xyz789; other_cookie=value";

    const session_id = getSessionCookie(allocator, cookie_header, "session_id");
    defer if (session_id) |id| allocator.free(id);

    try testing.expect(session_id != null);
    try testing.expectEqualStrings("xyz789", session_id.?);
}

test "get session cookie not found" {
    const allocator = testing.allocator;
    const cookie_header = "other_cookie=value";

    const session_id = getSessionCookie(allocator, cookie_header, "session_id");

    try testing.expect(session_id == null);
}

test "cookie serialize with max age" {
    const allocator = testing.allocator;
    const cookie = Cookie{
        .name = "session",
        .value = "abc123",
        .max_age = 3600,
    };

    const serialized = try cookie.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "Max-Age=3600") != null);
}

test "cookie serialize with domain" {
    const allocator = testing.allocator;
    const cookie = Cookie{
        .name = "session",
        .value = "abc123",
        .domain = "example.com",
    };

    const serialized = try cookie.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "Domain=example.com") != null);
}

test "cookie serialize with custom path" {
    const allocator = testing.allocator;
    const cookie = Cookie{
        .name = "session",
        .value = "abc123",
        .path = "/admin",
    };

    const serialized = try cookie.serialize(allocator);
    defer allocator.free(serialized);

    try testing.expect(std.mem.indexOf(u8, serialized, "Path=/admin") != null);
}

test "cookie same site variants" {
    const allocator = testing.allocator;

    for ([_]Cookie.SameSite{ .Strict, .Lax, .None }) |same_site| {
        const cookie = Cookie{
            .name = "session",
            .value = "abc123",
            .same_site = same_site,
        };

        const serialized = try cookie.serialize(allocator);
        defer allocator.free(serialized);

        try testing.expect(std.mem.indexOf(u8, serialized, "SameSite=") != null);
    }
}

test "get session cookie with multiple cookies" {
    const allocator = testing.allocator;
    const cookie_header = "theme=dark; session_id=xyz789; lang=en";

    const session_id = getSessionCookie(allocator, cookie_header, "session_id");
    defer if (session_id) |id| allocator.free(id);

    try testing.expect(session_id != null);
    try testing.expectEqualStrings("xyz789", session_id.?);
}

test "get session cookie at different positions" {
    const allocator = testing.allocator;

    const scenarios = [_][]const u8{
        "session_id=first",
        "other=data; session_id=middle",
        "first=value; second=data; session_id=last; other=more",
    };

    for (scenarios) |scenario| {
        const session_id = getSessionCookie(allocator, scenario, "session_id");
        defer if (session_id) |id| allocator.free(id);
        try testing.expect(session_id != null);
    }
}

test "cookie parse with all attributes" {
    const allocator = testing.allocator;
    const cookie_str = "session_id=abc123def; Path=/; Domain=example.com; Secure; HttpOnly; Max-Age=3600";

    var cookie = try Cookie.parse(allocator, cookie_str);
    defer allocator.free(cookie.name);
    defer allocator.free(cookie.value);
    defer cookie.deinit(allocator);

    try testing.expectEqualStrings("session_id", cookie.name);
    try testing.expectEqualStrings("abc123def", cookie.value);
    try testing.expect(cookie.secure);
    try testing.expect(cookie.http_only);
}
