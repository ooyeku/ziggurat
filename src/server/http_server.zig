const std = @import("std");
const net = std.net;
const posix = std.posix;
const ServerConfig = @import("../config/server_config.zig").ServerConfig;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const StatusCode = @import("../http/response.zig").StatusCode;
const router = @import("../router/router.zig");
const middleware = @import("../middleware/middleware.zig");
const logging = @import("../utils/logging.zig");
const metrics = @import("../metrics.zig");

pub const HttpServer = struct {
    config: ServerConfig,
    allocator: std.mem.Allocator,
    listener: posix.socket_t,
    router: router.Router,
    middleware: middleware.Middleware,

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !HttpServer {
        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Initializing HTTP server...", .{});
        }

        const address = try config.getAddress();
        const tpe: u32 = posix.SOCK.STREAM;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);
        errdefer posix.close(listener);

        // Enable address reuse
        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, config.backlog);

        if (logging.getGlobalLogger()) |logger| {
            try logger.info("Server socket initialized and bound", .{});
        }

        return HttpServer{
            .config = config,
            .allocator = allocator,
            .listener = listener,
            .router = router.Router.init(allocator),
            .middleware = middleware.Middleware.init(allocator),
        };
    }

    pub fn deinit(self: *HttpServer) void {
        if (logging.getGlobalLogger()) |logger| {
            logger.info("Shutting down HTTP server...", .{}) catch {};
        }
        self.router.deinit();
        self.middleware.deinit();
        posix.close(self.listener);
    }

    pub fn start(self: *HttpServer) !void {
        if (logging.getGlobalLogger()) |logger| {
            try logger.info("Server listening on http://{s}:{d}", .{ self.config.host, self.config.port });
        }

        while (true) {
            var client_address: net.Address = undefined;
            var client_address_len: posix.socklen_t = @sizeOf(net.Address);
            const socket = posix.accept(self.listener, &client_address.any, &client_address_len, 0) catch |err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Accept error: {}", .{err});
                }
                continue;
            };
            defer posix.close(socket);

            if (logging.getGlobalLogger()) |logger| {
                try logger.debug("Client connected from {}", .{client_address});
            }
            try self.handleConnection(socket);
        }
    }

    fn handleConnection(self: *HttpServer, socket: posix.socket_t) !void {
        // Set socket timeouts
        try setTimeouts(socket, &self.config);

        var buf = try self.allocator.alloc(u8, self.config.buffer_size);
        defer self.allocator.free(buf);

        const read = posix.read(socket, buf) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error reading from socket: {}", .{err});
            }
            return;
        };

        if (read == 0) return; // Empty request

        var request = Request.init(self.allocator);
        defer request.deinit();

        // Try to parse request, return 400 on failure
        request.parse(buf[0..read]) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error parsing request: {}", .{err});
            }

            const bad_request_response = Response.init(.bad_request, "text/plain", "Bad Request - Invalid HTTP Request Format");

            const formatted_response = bad_request_response.format();
            defer std.heap.page_allocator.free(formatted_response);

            _ = self.write(socket, formatted_response) catch |write_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error writing error response: {}", .{write_err});
                }
            };

            return;
        };

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Processing request: {s} {s}", .{ @tagName(request.method), request.path });
        }

        // Store metrics start time
        if (metrics.getGlobalMetrics()) |_| {
            metrics.startRequestMetrics(&request) catch |err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error starting metrics: {}", .{err});
                }
            };
        }

        // Handle the request with error recovery
        const response = self.handleRequest(&request) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error handling request: {}", .{err});
            }

            return Response.init(.internal_server_error, "text/plain", "Internal Server Error");
        };

        const formatted_response = response.format();
        defer std.heap.page_allocator.free(formatted_response);

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Sending response: status={}", .{response.status});
        }

        // Try to write response with error recovery
        self.write(socket, formatted_response) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error writing response: {}", .{err});
            }
            return;
        };

        // Record metrics after sending response
        metrics.recordResponseMetrics(&request, &response) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error recording metrics: {}", .{err});
            }
        };
    }

    fn handleRequest(self: *HttpServer, request: *Request) !Response {
        // Process middleware
        if (self.middleware.process(request)) |response| {
            return response;
        }

        // Match route
        if (self.router.matchRoute(request)) |response| {
            return response;
        }

        return Response.init(
            .not_found,
            "text/plain",
            "Not Found",
        );
    }

    fn write(self: *HttpServer, socket: posix.socket_t, msg: []const u8) !void {
        _ = self;
        var pos: usize = 0;
        while (pos < msg.len) {
            const written = try posix.write(socket, msg[pos..]);
            if (written == 0) {
                return error.Closed;
            }
            pos += written;
        }
    }

    // Add timeout handling
    fn setTimeouts(socket: posix.socket_t, config: *const ServerConfig) !void {
        const read_timeout = posix.timeval{
            .sec = @intCast(config.read_timeout_ms / 1000),
            .usec = @intCast((config.read_timeout_ms % 1000) * 1000),
        };
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(read_timeout));

        const write_timeout = posix.timeval{
            .sec = @intCast(config.write_timeout_ms / 1000),
            .usec = @intCast((config.write_timeout_ms % 1000) * 1000),
        };
        try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(write_timeout));
    }
};
