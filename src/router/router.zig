const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const Method = @import("../http/request.zig").Method;

pub const RouteHandler = *const fn (*Request) Response;

pub const Route = struct {
    method: Method,
    path: []const u8,
    handler: RouteHandler,
};

pub const Router = struct {
    routes: std.ArrayList(Route),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Router {
        return .{
            .routes = std.ArrayList(Route){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Router) void {
        // Free the duped path strings.
        for (self.routes.items) |route| {
            self.allocator.free(route.path);
        }
        self.routes.deinit(self.allocator);
    }

    /// Register a route. The path is duplicated internally.
    pub fn addRoute(self: *Router, method: Method, path: []const u8, handler: RouteHandler) !void {
        const path_owned = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(path_owned);
        try self.routes.append(self.allocator, .{
            .method = method,
            .path = path_owned,
            .handler = handler,
        });
    }

    /// Match a route and return the handler's response.
    /// Returns 405 when the path matches but the method does not.
    /// Returns null when no route matches the path.
    pub fn matchRoute(self: *Router, request: *Request) ?Response {
        var path_matched = false;

        for (self.routes.items) |route| {
            if (pathMatches(route.path, request.path)) {
                path_matched = true;
                if (route.method == request.method) {
                    extractParams(route.path, request.path, request) catch |err| {
                        if (@import("../utils/logging.zig").getGlobalLogger()) |logger| {
                            logger.err("Failed to extract params: {any}", .{err}) catch {};
                        }
                    };
                    return route.handler(request);
                }
            }
        }

        if (path_matched) {
            // At least one route matched the path but not the method.
            return Response.init(.method_not_allowed, "text/plain", "Method Not Allowed");
        }

        return null;
    }

    fn pathMatches(pattern: []const u8, path: []const u8) bool {
        if (std.mem.eql(u8, pattern, path)) return true;

        // Wildcard suffix: "/prefix/*" matches any path under "/prefix/"
        if (pattern.len >= 2 and std.mem.endsWith(u8, pattern, "/*")) {
            const prefix = pattern[0 .. pattern.len - 1];
            if (std.mem.startsWith(u8, path, prefix)) return true;
        }

        if (std.mem.indexOf(u8, pattern, ":") != null) {
            var pattern_segments = std.mem.splitScalar(u8, pattern, '/');
            var path_segments = std.mem.splitScalar(u8, path, '/');

            while (true) {
                const pattern_next = pattern_segments.next();
                const path_next = path_segments.next();

                if (pattern_next == null and path_next == null) return true;
                if (pattern_next == null or path_next == null) return false;

                const pattern_segment = pattern_next.?;
                const path_segment = path_next.?;

                if (pattern_segment.len > 0 and pattern_segment[0] == ':') continue;
                if (!std.mem.eql(u8, pattern_segment, path_segment)) return false;
            }
        }

        return false;
    }

    pub fn extractParams(pattern: []const u8, path: []const u8, request: *Request) !void {
        if (std.mem.indexOf(u8, pattern, ":") == null) return;

        var pattern_segments = std.mem.splitScalar(u8, pattern, '/');
        var path_segments = std.mem.splitScalar(u8, path, '/');

        while (true) {
            const pattern_next = pattern_segments.next();
            const path_next = path_segments.next();

            if (pattern_next == null or path_next == null) break;

            const pattern_segment = pattern_next.?;
            const path_segment = path_next.?;

            if (pattern_segment.len > 0 and pattern_segment[0] == ':') {
                try request.setUserData(pattern_segment[1..], path_segment);
            }
        }
    }
};

test "router returns 405 when path matches but method does not" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var r = Router.init(allocator);
    defer r.deinit();

    const handler = struct {
        fn h(_: *Request) Response {
            return Response.init(.ok, "text/plain", "ok");
        }
    }.h;

    try r.addRoute(.GET, "/users", handler);

    var request = @import("../http/request.zig").Request.init(allocator);
    defer request.deinit();
    request.method = .POST;
    request.path = try allocator.dupe(u8, "/users");

    const result = r.matchRoute(&request);
    try testing.expect(result != null);
    try testing.expectEqual(@import("../http/response.zig").StatusCode.method_not_allowed, result.?.status);
}

test "router returns null when path does not match" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var r = Router.init(allocator);
    defer r.deinit();

    const handler = struct {
        fn h(_: *Request) Response {
            return Response.init(.ok, "text/plain", "ok");
        }
    }.h;

    try r.addRoute(.GET, "/users", handler);

    var request = @import("../http/request.zig").Request.init(allocator);
    defer request.deinit();
    request.method = .GET;
    request.path = try allocator.dupe(u8, "/posts");

    const result = r.matchRoute(&request);
    try testing.expect(result == null);
}

test "router parameter extraction error handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    // Test successful parameter extraction
    var request = @import("../http/request.zig").Request.init(allocator);
    defer request.deinit();

    try request.setUserData("existing_key", "value");

    // Test extractParams with valid parameters
    Router.extractParams("/users/:id/posts/:post_id", "/users/123/posts/456", &request) catch {
        try testing.expect(false); // Should not fail
    };

    const id_param = request.getParam("id");
    try testing.expect(id_param != null);
    try testing.expectEqualStrings("123", id_param.?);

    const post_id_param = request.getParam("post_id");
    try testing.expect(post_id_param != null);
    try testing.expectEqualStrings("456", post_id_param.?);
}

test "router parameter extraction with no parameters" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var request = @import("../http/request.zig").Request.init(allocator);
    defer request.deinit();

    // Test extractParams with no parameters in pattern
    Router.extractParams("/users/profile", "/users/profile", &request) catch {
        try testing.expect(false); // Should not fail
    };

    // Should have no parameters
    const param = request.getParam("id");
    try testing.expect(param == null);
}

test "router parameter extraction edge cases" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var router = Router.init(allocator);
    defer router.deinit();

    var request = @import("../http/request.zig").Request.init(allocator);
    defer request.deinit();

    // Test with empty parameter name (should be handled gracefully)
    Router.extractParams("/users/:/posts/:post_id", "/users/123/posts/456", &request) catch {
        // This should fail because empty parameter names aren't valid
        // but the error should be caught by matchRoute
    };

    // Valid parameters should still work
    Router.extractParams("/api/:version/users/:id", "/api/v1/users/789", &request) catch {
        try testing.expect(false); // Should not fail
    };

    const version = request.getParam("version");
    try testing.expect(version != null);
    try testing.expectEqualStrings("v1", version.?);

    const user_id = request.getParam("id");
    try testing.expect(user_id != null);
    try testing.expectEqualStrings("789", user_id.?);
}
