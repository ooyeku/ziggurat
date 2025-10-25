//! HandlerContext - Unified context for route handlers
//! Provides a cleaner interface wrapping Request with session, params, and cookies

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;

pub const Context = struct {
    request: *Request,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Create a new context from a request
    pub fn init(allocator: std.mem.Allocator, request: *Request) Self {
        return .{
            .allocator = allocator,
            .request = request,
        };
    }

    /// Get a path parameter
    pub fn param(self: *Self, name: []const u8) ?[]const u8 {
        return self.request.getParam(name);
    }

    /// Get a query parameter
    pub fn query(self: *Self, name: []const u8) ?[]const u8 {
        return self.request.getQuery(name);
    }

    /// Get a header value
    pub fn header(self: *Self, name: []const u8) ?[]const u8 {
        return self.request.headers.get(name);
    }

    /// Get the request method
    pub fn method(self: *Self) @import("../http/request.zig").Method {
        return self.request.method;
    }

    /// Get the request path
    pub fn path(self: *Self) []const u8 {
        return self.request.path;
    }

    /// Get the request body
    pub fn body(self: *Self) []const u8 {
        return self.request.body;
    }

    /// Session management
    pub const session = struct {
        /// Set a session value (requires session middleware to be initialized)
        pub fn set(ctx: *Self, key: []const u8, value: []const u8) !void {
            try ctx.request.setUserData(key, value);
        }

        /// Get a session value (requires session middleware to be initialized)
        pub fn get(ctx: *Self, key: []const u8) ?[]const u8 {
            return ctx.request.getUserData(key, []const u8);
        }

        /// Remove a session value
        pub fn remove(ctx: *Self, key: []const u8) void {
            // In future: implement session value removal
            _ = ctx;
            _ = key;
        }
    };

    /// Deinit the context
    pub fn deinit(self: *Self) void {
        self.request.deinit();
    }
};

// Make session methods accessible at context level
pub fn sessionSet(ctx: *Context, key: []const u8, value: []const u8) !void {
    try ctx.session.set(key, value);
}

pub fn sessionGet(ctx: *Context, key: []const u8) ?[]const u8 {
    return ctx.session.get(key);
}
