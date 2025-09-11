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
        self.routes.deinit(self.allocator);
    }

    pub fn addRoute(self: *Router, method: Method, path: []const u8, handler: RouteHandler) !void {
        try self.routes.append(self.allocator, .{
            .method = method,
            .path = path,
            .handler = handler,
        });
    }

    pub fn matchRoute(self: *Router, request: *Request) ?Response {
        for (self.routes.items) |route| {
            if (route.method == request.method) {
                if (pathMatches(route.path, request.path)) {
                    // Extract parameters from path
                    extractParams(route.path, request.path, request) catch |err| {
                        if (@import("../utils/logging.zig").getGlobalLogger()) |logger| {
                            logger.err("Failed to extract params: {any}", .{err}) catch {};
                        }
                    };

                    return route.handler(request);
                }
            }
        }
        return null;
    }

    // Checks if a route pattern matches a request path
    fn pathMatches(pattern: []const u8, path: []const u8) bool {
        // Exact match
        if (std.mem.eql(u8, pattern, path)) {
            return true;
        }

        // Pattern contains parameters
        if (std.mem.indexOf(u8, pattern, ":") != null) {
            var pattern_segments = std.mem.splitScalar(u8, pattern, '/');
            var path_segments = std.mem.splitScalar(u8, path, '/');

            while (true) {
                const pattern_next = pattern_segments.next();
                const path_next = path_segments.next();

                if (pattern_next == null and path_next == null) {
                    return true; // Both iterators exhausted, match found
                }

                if (pattern_next == null or path_next == null) {
                    return false; // One iterator exhausted before the other, no match
                }

                const pattern_segment = pattern_next.?;
                const path_segment = path_next.?;

                // If segment starts with ':', it's a parameter - always matches
                if (pattern_segment.len > 0 and pattern_segment[0] == ':') {
                    continue;
                }

                // Otherwise, segments must match exactly
                if (!std.mem.eql(u8, pattern_segment, path_segment)) {
                    return false;
                }
            }
        }

        return false;
    }

    // Extracts path parameters and stores them in the request
    fn extractParams(pattern: []const u8, path: []const u8, request: *Request) !void {
        if (std.mem.indexOf(u8, pattern, ":") == null) {
            return; // No parameters in pattern
        }

        var pattern_segments = std.mem.splitScalar(u8, pattern, '/');
        var path_segments = std.mem.splitScalar(u8, path, '/');

        while (true) {
            const pattern_next = pattern_segments.next();
            const path_next = path_segments.next();

            if (pattern_next == null or path_next == null) {
                break;
            }

            const pattern_segment = pattern_next.?;
            const path_segment = path_next.?;

            // If segment starts with ':', it's a parameter
            if (pattern_segment.len > 0 and pattern_segment[0] == ':') {
                const param_name = pattern_segment[1..];
                try request.setUserData(param_name, path_segment);
            }
        }
    }
};
