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
            .handlers = std.ArrayList(MiddlewareHandler){},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Middleware) void {
        self.handlers.deinit(self.allocator);
    }

    pub fn add(self: *Middleware, handler: MiddlewareHandler) !void {
        try self.handlers.append(self.allocator, handler);
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

test "Middleware process empty pipeline returns null" {
    const allocator = testing.allocator;
    var mw = Middleware.init(allocator);
    defer mw.deinit();

    var request = Request.init(allocator);
    defer request.deinit();

    const response = mw.process(&request);
    try testing.expectEqual(@as(?Response, null), response);
}

test "Middleware short-circuits on first non-null response" {
    const allocator = testing.allocator;
    var mw = Middleware.init(allocator);
    defer mw.deinit();

    const first = struct {
        fn handler(_: *Request) ?Response {
            return Response.init(.unauthorized, "text/plain", "denied");
        }
    }.handler;

    const second = struct {
        fn handler(_: *Request) ?Response {
            // Should never be reached.
            return Response.init(.ok, "text/plain", "ok");
        }
    }.handler;

    try mw.add(first);
    try mw.add(second);

    var request = Request.init(allocator);
    defer request.deinit();

    const response = mw.process(&request);
    try testing.expect(response != null);
    try testing.expectEqual(@import("../http/response.zig").StatusCode.unauthorized, response.?.status);
}

test "Middleware continues when handler returns null" {
    const allocator = testing.allocator;
    var mw = Middleware.init(allocator);
    defer mw.deinit();

    const passthrough = struct {
        fn handler(_: *Request) ?Response {
            return null;
        }
    }.handler;

    const terminal = struct {
        fn handler(_: *Request) ?Response {
            return Response.init(.ok, "text/plain", "reached");
        }
    }.handler;

    try mw.add(passthrough);
    try mw.add(terminal);

    var request = Request.init(allocator);
    defer request.deinit();

    const response = mw.process(&request);
    try testing.expect(response != null);
    try testing.expectEqualStrings("reached", response.?.body);
}
