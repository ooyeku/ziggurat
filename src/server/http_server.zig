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
const Tls = @import("tls.zig").Tls;

pub const HttpServer = struct {
    config: ServerConfig,
    allocator: std.mem.Allocator,
    listener: posix.socket_t,
    router: router.Router,
    middleware: middleware.Middleware,
    tls: Tls,

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

        // Initialize TLS if configured
        var tls = try Tls.init(allocator, config.tls);
        errdefer tls.deinit();

        if (logging.getGlobalLogger()) |logger| {
            if (config.tls.enabled) {
                try logger.info("Server socket initialized with TLS support", .{});
            } else {
                try logger.info("Server socket initialized without TLS", .{});
            }
        }

        return HttpServer{
            .config = config,
            .allocator = allocator,
            .listener = listener,
            .router = router.Router.init(allocator),
            .middleware = middleware.Middleware.init(allocator),
            .tls = tls,
        };
    }

    pub fn deinit(self: *HttpServer) void {
        if (logging.getGlobalLogger()) |logger| {
            logger.info("Shutting down HTTP server...", .{}) catch {};
        }
        self.router.deinit();
        self.middleware.deinit();
        self.tls.deinit();
        posix.close(self.listener);
    }

    pub fn start(self: *HttpServer) !void {
        if (logging.getGlobalLogger()) |logger| {
            const protocol = if (self.config.tls.enabled) "https" else "http";
            try logger.info("Server listening on {s}://{s}:{d}", .{ protocol, self.config.host, self.config.port });
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

        // Wrap socket with TLS if enabled
        const secured_socket = try self.tls.wrapSocket(socket);

        // Initialize ArenaAllocator for this connection
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const req_allocator = arena.allocator();

        var buf = try req_allocator.alloc(u8, self.config.buffer_size);
        // defer self.allocator.free(buf); // Arena will handle this

        const read = self.tls.read(secured_socket, buf) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error reading from socket: {}", .{err});
            }
            return;
        };

        if (read == 0) return; // Empty request

        var request = Request.init(req_allocator);
        defer request.deinit();

        // Try to parse request, return 400 on failure
        request.parse(buf[0..read]) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error parsing request: {}", .{err});
            }

            const bad_request_response = Response.init(.bad_request, "text/plain", "Bad Request - Invalid HTTP Request Format");

            const formatted_response = bad_request_response.format(req_allocator) catch |fmt_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error formatting response: {}", .{fmt_err});
                }
                return;
            };

            _ = self.writeTls(secured_socket, formatted_response) catch |write_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error writing error response: {}", .{write_err});
                }
            };

            return;
        };

        // Early exit for unknown HTTP methods after successful parsing
        if (request.method == .UNKNOWN) {
            if (logging.getGlobalLogger()) |logger| {
                try logger.warn("Malformed request: HTTP method UNKNOWN. The request path could not be interpreted as valid text.", .{});
            }
            const bad_method_response = Response.init(.bad_request, "text/plain", "Bad Request - Unknown or Malformed HTTP Method");
            const formatted_bad_method_response = bad_method_response.format(req_allocator) catch |fmt_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error formatting bad_method_response: {}", .{fmt_err});
                }
                return; // Exit if we can't even format the error
            };
            _ = self.writeTls(secured_socket, formatted_bad_method_response) catch |write_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error writing bad_method_response: {}", .{write_err});
                }
            };
            return; // Stop processing this request
        }

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Processing request: {s} {?s}", .{ @tagName(request.method), request.path });
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
            // This response is short-lived, its body is a string literal.
            // It will be formatted using req_allocator in the next step.
            return Response.init(.internal_server_error, "text/plain", "Internal Server Error");
        };

        const formatted_response = response.format(req_allocator) catch |fmt_err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error formatting response: {}", .{fmt_err});
            }
            return;
        };

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Sending response: status={}", .{response.status});
        }

        // Try to write response with error recovery
        self.writeTls(secured_socket, formatted_response) catch |err| {
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

    fn writeTls(self: *HttpServer, socket: posix.socket_t, msg: []const u8) !void {
        var pos: usize = 0;
        while (pos < msg.len) {
            const written = try self.tls.write(socket, msg[pos..]);
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
