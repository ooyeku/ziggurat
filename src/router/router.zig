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
            .routes = std.ArrayList(Route).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit();
    }

    pub fn addRoute(self: *Router, method: Method, path: []const u8, handler: RouteHandler) !void {
        try self.routes.append(.{
            .method = method,
            .path = path,
            .handler = handler,
        });
    }

    pub fn matchRoute(self: *Router, request: *Request) ?Response {
        for (self.routes.items) |route| {
            if (route.method == request.method and std.mem.eql(u8, route.path, request.path)) {
                return route.handler(request);
            }
        }
        return null;
    }
};
