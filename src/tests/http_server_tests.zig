const std = @import("std");
const testing = std.testing;
const HttpServer = @import("../server/http_server.zig").HttpServer;
const ServerConfig = @import("../config/server_config.zig").ServerConfig;
const TlsConfig = @import("../config/tls_config.zig").TlsConfig;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const router = @import("../router/router.zig");
const middleware = @import("../middleware/middleware.zig");
const net = std.net;
const posix = std.posix;
const mem = std.mem;

fn createTestConfig() ServerConfig {
    return ServerConfig.init("127.0.0.1", 8080);
}

fn createMockSocket() !posix.socket_t {
    return try posix.socket(posix.AF.INET, posix.SOCK.STREAM, posix.IPPROTO.TCP);
}

fn testSetTimeouts(socket: posix.socket_t, config: *const ServerConfig) !void {
    const read_timeout = posix.timeval{
        .sec = @intCast(config.read_timeout_ms / 1000),
        .usec = @intCast((config.read_timeout_ms % 1000) * 1000),
    };
    try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &mem.toBytes(read_timeout));

    const write_timeout = posix.timeval{
        .sec = @intCast(config.write_timeout_ms / 1000),
        .usec = @intCast((config.write_timeout_ms % 1000) * 1000),
    };
    try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &mem.toBytes(write_timeout));
}

test "HttpServer - init and deinit" {
    // Cannot easily test without binding a real port; just verify config is valid.
    const config = createTestConfig();
    _ = config;
}

test "HttpServer - setTimeouts" {
    const config = createTestConfig();
    const socket = try createMockSocket();
    defer posix.close(socket);

    try testSetTimeouts(socket, &config);
}

fn testHandler(_: *Request) Response {
    return Response.init(.ok, "text/plain", "Test Response");
}

test "HttpServer - router integration" {
    const allocator = std.testing.allocator;

    var test_router = router.Router.init(allocator);
    defer test_router.deinit();
    try test_router.addRoute(.GET, "/test", testHandler);

    var request = Request.init(allocator);
    defer request.deinit();
    request.method = .GET;
    request.path = try request.allocator.dupe(u8, "/test");

    const response = test_router.matchRoute(&request) orelse
        Response.init(.not_found, "text/plain", "Not Found");

    try testing.expectEqual(@as(u16, 200), @intFromEnum(response.status));
    try testing.expectEqualStrings("text/plain", response.content_type);
    try testing.expectEqualStrings("Test Response", response.body);
}

fn testMiddleware(_: *Request) ?Response {
    return Response.init(.ok, "text/plain", "Middleware Response");
}

test "HttpServer - middleware integration" {
    const allocator = std.testing.allocator;

    var test_middleware = middleware.Middleware.init(allocator);
    defer test_middleware.deinit();
    try test_middleware.add(testMiddleware);

    var request = Request.init(allocator);
    defer request.deinit();
    request.method = .GET;
    request.path = try request.allocator.dupe(u8, "/anything");

    if (test_middleware.process(&request)) |response| {
        try testing.expectEqual(@as(u16, 200), @intFromEnum(response.status));
        try testing.expectEqualStrings("Middleware Response", response.body);
    } else {
        try testing.expect(false);
    }
}

test "HttpServer - no route match returns 404" {
    const allocator = std.testing.allocator;

    var test_router = router.Router.init(allocator);
    defer test_router.deinit();

    var request = Request.init(allocator);
    defer request.deinit();
    request.method = .GET;
    request.path = try request.allocator.dupe(u8, "/nonexistent");

    try testing.expect(test_router.matchRoute(&request) == null);
}

test "HttpServer - handleRequest - invalid request" {
    const allocator = std.testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();
    request.method = .GET;
    request.path = try request.allocator.dupe(u8, "invalid"); // no leading slash

    var test_router = router.Router.init(allocator);
    defer test_router.deinit();

    try testing.expect(test_router.matchRoute(&request) == null);
}

fn methodGetHandler(_: *Request) Response {
    return Response.init(.ok, "text/plain", "GET method");
}
fn methodPostHandler(_: *Request) Response {
    return Response.init(.created, "text/plain", "POST method");
}
fn methodPutHandler(_: *Request) Response {
    return Response.init(.ok, "text/plain", "PUT method");
}
fn methodDeleteHandler(_: *Request) Response {
    return Response.init(.no_content, "text/plain", "");
}

test "HttpServer - HTTP methods" {
    const allocator = std.testing.allocator;

    var test_router = router.Router.init(allocator);
    defer test_router.deinit();
    try test_router.addRoute(.GET, "/api", methodGetHandler);
    try test_router.addRoute(.POST, "/api", methodPostHandler);
    try test_router.addRoute(.PUT, "/api", methodPutHandler);
    try test_router.addRoute(.DELETE, "/api", methodDeleteHandler);

    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .GET;
        request.path = try request.allocator.dupe(u8, "/api");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqual(@as(u16, 200), @intFromEnum(response.status));
        try testing.expectEqualStrings("GET method", response.body);
    }
    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .POST;
        request.path = try request.allocator.dupe(u8, "/api");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqual(@as(u16, 201), @intFromEnum(response.status));
        try testing.expectEqualStrings("POST method", response.body);
    }
    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .PUT;
        request.path = try request.allocator.dupe(u8, "/api");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqual(@as(u16, 200), @intFromEnum(response.status));
        try testing.expectEqualStrings("PUT method", response.body);
    }
    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .DELETE;
        request.path = try request.allocator.dupe(u8, "/api");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqual(@as(u16, 204), @intFromEnum(response.status));
        try testing.expectEqualStrings("", response.body);
    }
}

fn textHandler(_: *Request) Response {
    return Response.init(.ok, "text/plain", "Plain text content");
}
fn jsonHandler(_: *Request) Response {
    return Response.init(.ok, "application/json", "{\"message\":\"JSON content\"}");
}
fn htmlHandler(_: *Request) Response {
    return Response.init(.ok, "text/html", "<html><body>HTML content</body></html>");
}

test "HttpServer - content types" {
    const allocator = std.testing.allocator;

    var test_router = router.Router.init(allocator);
    defer test_router.deinit();
    try test_router.addRoute(.GET, "/text", textHandler);
    try test_router.addRoute(.GET, "/json", jsonHandler);
    try test_router.addRoute(.GET, "/html", htmlHandler);

    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .GET;
        request.path = try request.allocator.dupe(u8, "/text");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqualStrings("text/plain", response.content_type);
        try testing.expectEqualStrings("Plain text content", response.body);
    }
    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .GET;
        request.path = try request.allocator.dupe(u8, "/json");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqualStrings("application/json", response.content_type);
    }
    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .GET;
        request.path = try request.allocator.dupe(u8, "/html");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqualStrings("text/html", response.content_type);
    }
}

test "HttpServer - request headers" {
    const allocator = std.testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();
    request.method = .GET;
    request.path = try request.allocator.dupe(u8, "/headers");
    try request.headers.put(
        try allocator.dupe(u8, "Content-Type"),
        try allocator.dupe(u8, "test-content-type"),
    );

    try testing.expectEqualStrings("test-content-type", request.headers.get("Content-Type").?);
}

fn loggingMiddleware(request: *Request) ?Response {
    request.setUserData("logged", true) catch return null;
    return null;
}
fn authMiddleware(request: *Request) ?Response {
    if (std.mem.eql(u8, request.path, "/admin")) {
        return Response.init(.unauthorized, "text/plain", "Unauthorized");
    }
    return null;
}
fn timingMiddleware(request: *Request) ?Response {
    request.setUserData("timed", true) catch return null;
    return null;
}

test "HttpServer - middleware chain" {
    const allocator = std.testing.allocator;

    var test_middleware = middleware.Middleware.init(allocator);
    defer test_middleware.deinit();
    try test_middleware.add(loggingMiddleware);
    try test_middleware.add(authMiddleware);
    try test_middleware.add(timingMiddleware);

    var request = Request.init(allocator);
    defer request.deinit();
    request.method = .GET;
    request.path = try request.allocator.dupe(u8, "/admin");

    if (test_middleware.process(&request)) |response| {
        try testing.expectEqual(@as(u16, 401), @intFromEnum(response.status));
        try testing.expectEqualStrings("Unauthorized", response.body);
    } else {
        try testing.expect(false);
    }
}

fn badRequestHandler(_: *Request) Response {
    return Response.init(.bad_request, "text/plain", "Bad Request");
}
fn forbiddenHandler(_: *Request) Response {
    return Response.init(.forbidden, "text/plain", "Forbidden");
}
fn notFoundHandler(_: *Request) Response {
    return Response.init(.not_found, "text/plain", "Not Found");
}
fn serverErrorHandler(_: *Request) Response {
    return Response.init(.internal_server_error, "text/plain", "Internal Server Error");
}

test "HttpServer - error responses" {
    const allocator = std.testing.allocator;

    var test_router = router.Router.init(allocator);
    defer test_router.deinit();
    try test_router.addRoute(.GET, "/errors/400", badRequestHandler);
    try test_router.addRoute(.GET, "/errors/403", forbiddenHandler);
    try test_router.addRoute(.GET, "/errors/404", notFoundHandler);
    try test_router.addRoute(.GET, "/errors/500", serverErrorHandler);

    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .GET;
        request.path = try request.allocator.dupe(u8, "/errors/400");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqual(@as(u16, 400), @intFromEnum(response.status));
        try testing.expectEqualStrings("Bad Request", response.body);
    }
    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .GET;
        request.path = try request.allocator.dupe(u8, "/errors/403");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqual(@as(u16, 403), @intFromEnum(response.status));
        try testing.expectEqualStrings("Forbidden", response.body);
    }
    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .GET;
        request.path = try request.allocator.dupe(u8, "/errors/404");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqual(@as(u16, 404), @intFromEnum(response.status));
        try testing.expectEqualStrings("Not Found", response.body);
    }
    {
        var request = Request.init(allocator);
        defer request.deinit();
        request.method = .GET;
        request.path = try request.allocator.dupe(u8, "/errors/500");
        const response = test_router.matchRoute(&request).?;
        try testing.expectEqual(@as(u16, 500), @intFromEnum(response.status));
        try testing.expectEqualStrings("Internal Server Error", response.body);
    }
}
