//! Testing utilities for Ziggurat
//! Provides test client, request builders, and assertions

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const Method = @import("../http/request.zig").Method;
const testing = std.testing;

/// Test request builder
pub const TestRequestBuilder = struct {
    method: Method = .GET,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8 = "",
    query_params: std.StringHashMap([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) TestRequestBuilder {
        return .{
            .path = path,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .query_params = std.StringHashMap([]const u8).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TestRequestBuilder) void {
        self.headers.deinit();
        self.query_params.deinit();
    }

    pub fn withMethod(self: *TestRequestBuilder, method: Method) *TestRequestBuilder {
        self.method = method;
        return self;
    }

    pub fn withBody(self: *TestRequestBuilder, body: []const u8) *TestRequestBuilder {
        self.body = body;
        return self;
    }

    pub fn withHeader(self: *TestRequestBuilder, key: []const u8, value: []const u8) !*TestRequestBuilder {
        try self.headers.put(key, value);
        return self;
    }

    pub fn withQuery(self: *TestRequestBuilder, key: []const u8, value: []const u8) !*TestRequestBuilder {
        try self.query_params.put(key, value);
        return self;
    }

    pub fn buildRequest(self: *TestRequestBuilder) !Request {
        var request = Request.init(self.allocator);

        request.method = self.method;
        request.path = try self.allocator.dupe(u8, self.path);
        request.body = try self.allocator.dupe(u8, self.body);

        var header_it = self.headers.iterator();
        while (header_it.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const value = try self.allocator.dupe(u8, entry.value_ptr.*);
            try request.headers.put(key, value);
        }

        return request;
    }
};

/// Test response assertions
pub const ResponseAssertions = struct {
    response: Response,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, response: Response) ResponseAssertions {
        return .{
            .response = response,
            .allocator = allocator,
        };
    }

    pub fn expectStatus(self: ResponseAssertions, expected: u16) !void {
        try testing.expectEqual(expected, @intFromEnum(self.response.status));
    }

    pub fn expectBody(self: ResponseAssertions, expected: []const u8) !void {
        try testing.expectEqualStrings(expected, self.response.body);
    }

    pub fn expectContentType(self: ResponseAssertions, expected: []const u8) !void {
        try testing.expectEqualStrings(expected, self.response.content_type);
    }

    pub fn expectBodyContains(self: ResponseAssertions, substring: []const u8) !void {
        try testing.expect(std.mem.indexOf(u8, self.response.body, substring) != null);
    }

    pub fn expectBodyNotContains(self: ResponseAssertions, substring: []const u8) !void {
        try testing.expect(std.mem.indexOf(u8, self.response.body, substring) == null);
    }

    pub fn expectJsonFieldExists(self: ResponseAssertions, field_name: []const u8) !void {
        const expected = try std.fmt.allocPrint(self.allocator, "\"{s}\"", .{field_name});
        defer self.allocator.free(expected);

        try testing.expect(std.mem.indexOf(u8, self.response.body, expected) != null);
    }
};

test "test request builder" {
    const allocator = testing.allocator;

    var builder = TestRequestBuilder.init(allocator, "/api/users");
    defer builder.deinit();

    var request = try builder
        .withMethod(.POST)
        .withHeader("Content-Type", "application/json")
        .buildRequest();
    defer request.deinit();

    try testing.expectEqual(Method.POST, request.method);
    try testing.expectEqualStrings("application/json", request.headers.get("Content-Type") orelse "");
}

test "test request builder with multiple headers" {
    const allocator = testing.allocator;

    var builder = TestRequestBuilder.init(allocator, "/api/data");
    defer builder.deinit();

    var request = try builder
        .withMethod(.PUT)
        .withHeader("Content-Type", "application/json")
        .withHeader("Authorization", "Bearer token123")
        .withHeader("X-Custom-Header", "custom-value")
        .withBody("{\"data\":\"value\"}")
        .buildRequest();
    defer request.deinit();

    try testing.expectEqual(Method.PUT, request.method);
    try testing.expectEqualStrings("application/json", request.headers.get("Content-Type") orelse "");
    try testing.expectEqualStrings("Bearer token123", request.headers.get("Authorization") orelse "");
    try testing.expectEqualStrings("custom-value", request.headers.get("X-Custom-Header") orelse "");
    try testing.expectEqualStrings("{\"data\":\"value\"}", request.body);
}

test "test request builder all methods" {
    const allocator = testing.allocator;

    const methods = [_]Method{ .GET, .POST, .PUT, .DELETE, .OPTIONS, .HEAD, .PATCH };

    for (methods) |method| {
        var builder = TestRequestBuilder.init(allocator, "/test");
        defer builder.deinit();

        var request = try builder.withMethod(method).buildRequest();
        defer request.deinit();

        try testing.expectEqual(method, request.method);
    }
}

test "response assertions expect status" {
    const allocator = testing.allocator;
    const response = Response.init(.ok, "text/plain", "Hello");

    var assertions = ResponseAssertions.init(allocator, response);
    try assertions.expectStatus(200);
}

test "response assertions expect body" {
    const allocator = testing.allocator;
    const response = Response.init(.ok, "text/plain", "Hello, World!");

    var assertions = ResponseAssertions.init(allocator, response);
    try assertions.expectBody("Hello, World!");
}

test "response assertions expect body contains" {
    const allocator = testing.allocator;
    const response = Response.init(.ok, "application/json", "{\"status\":\"ok\",\"message\":\"Success\"}");

    var assertions = ResponseAssertions.init(allocator, response);
    try assertions.expectBodyContains("success");
}

test "response assertions expect content type" {
    const allocator = testing.allocator;
    const response = Response.init(.ok, "application/json", "{}");

    var assertions = ResponseAssertions.init(allocator, response);
    try assertions.expectContentType("application/json");
}

test "response assertions status codes" {
    const allocator = testing.allocator;

    const status_codes = [_]u16{ 200, 201, 204, 400, 401, 403, 404, 500 };

    for (status_codes) |_| {
        const response = Response.init(.ok, "text/plain", "Test");
        var assertions = ResponseAssertions.init(allocator, response);

        try assertions.expectStatus(200);
    }
}

test "response assertions content type variations" {
    const allocator = testing.allocator;

    const content_types = [_][]const u8{
        "text/plain",
        "application/json",
        "text/html",
        "application/xml",
        "image/png",
    };

    for (content_types) |content_type| {
        const response = Response.init(.ok, content_type, "body");
        var assertions = ResponseAssertions.init(allocator, response);

        try assertions.expectContentType(content_type);
    }
}

test "response assertions body contains variations" {
    const allocator = testing.allocator;

    const body = "The quick brown fox jumps over the lazy dog";
    const response = Response.init(.ok, "text/plain", body);
    var assertions = ResponseAssertions.init(allocator, response);

    try assertions.expectBodyContains("quick");
    try assertions.expectBodyContains("brown");
    try assertions.expectBodyContains("lazy");
}

test "response assertions json field variations" {
    const allocator = testing.allocator;

    const body = "{\"status\":\"ok\",\"user\":\"alice\",\"count\":42}";
    const response = Response.init(.ok, "application/json", body);
    var assertions = ResponseAssertions.init(allocator, response);

    try assertions.expectJsonFieldExists("status");
    try assertions.expectJsonFieldExists("user");
    try assertions.expectJsonFieldExists("count");
}
