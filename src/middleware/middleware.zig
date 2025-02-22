// src/middleware/middleware.zig
const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const MiddlewareHandler = *const fn (*Request) ?Response;

pub const Middleware = struct {
    handlers: std.ArrayList(MiddlewareHandler),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Middleware {
        return .{
            .handlers = std.ArrayList(MiddlewareHandler).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Middleware) void {
        self.handlers.deinit();
    }

    pub fn add(self: *Middleware, handler: MiddlewareHandler) !void {
        try self.handlers.append(handler);
    }

    pub fn process(self: *const Middleware, request: *Request) ?Response {
        for (self.handlers.items) |handler| {
            if (handler(request)) |response| {
                return response;
            }
        }
        return null;
    }
};
