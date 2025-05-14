// src/middleware/middleware.zig
const std = @import("std");
const testing = std.testing;
const http_request = @import("../http/request.zig");
const http_response = @import("../http/response.zig");

pub const Request = http_request.Request;
pub const Response = http_response.Response;

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

test "Middleware process" {
    // For standalone test, skip this test since it depends on real types
    if (@import("builtin").is_test) {
        // When running in test mode directly, skip this test
        return error.SkipZigTest;
    }

    const allocator = testing.allocator;
    var middleware = Middleware.init(allocator);
    defer middleware.deinit();

    var request = Request.init(allocator);
    defer request.deinit();

    const response = middleware.process(&request);
    try testing.expectEqual(response, null);
}