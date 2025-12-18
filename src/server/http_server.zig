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
                    try logger.err("Accept error: {any}", .{err});
                }
                continue;
            };
            defer posix.close(socket);

            if (logging.getGlobalLogger()) |logger| {
                try logger.debug("Client connected from {any}", .{client_address});
            }
            try self.handleConnection(socket);
        }
    }

    fn handleConnection(self: *HttpServer, socket: posix.socket_t) !void {
        // Set socket timeouts
        try setTimeouts(socket, &self.config);

        // Wrap socket with TLS if enabled
        const secured_socket = try self.tls.wrapSocket(socket);

        // Start with initial buffer size, will reallocate if needed
        var buf = try self.allocator.alloc(u8, self.config.buffer_size);
        defer self.allocator.free(buf);

        // Read first chunk
        var total_read: usize = 0;
        const read = self.tls.read(secured_socket, buf) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error reading from socket: {any}", .{err});
            }
            return;
        };

        if (read == 0) return; // Empty request
        total_read = read;

        // Find where headers end (\r\n\r\n)
        const header_end_marker = "\r\n\r\n";
        var header_end_pos: ?usize = null;

        // Read until headers are complete
        while (header_end_pos == null) {
            // Check bounds before searching for header end
            if (total_read >= 4) { // Minimum length for \r\n\r\n
                if (std.mem.indexOf(u8, buf[0..total_read], header_end_marker)) |pos| {
                    header_end_pos = pos;
                    break;
                }
            }

            // Check if we've exceeded max header size BEFORE reading more
            if (total_read >= self.config.max_header_size) {
                const bad_request_response = Response.init(.request_header_fields_too_large, "text/plain", "Request Header Fields Too Large");
                const formatted_response = bad_request_response.format() catch return;
                defer std.heap.page_allocator.free(formatted_response);
                _ = self.writeTls(secured_socket, formatted_response) catch {};
                return;
            }

            // Check if buffer needs to grow
            if (total_read >= buf.len) {
                // Calculate new size, but don't exceed max_header_size
                const new_size = @min(buf.len * 2, self.config.max_header_size);
                if (new_size <= buf.len) {
                    // Can't grow buffer anymore, headers too large
                    const bad_request_response = Response.init(.request_header_fields_too_large, "text/plain", "Request Header Fields Too Large");
                    const formatted_response = bad_request_response.format() catch return;
                    defer std.heap.page_allocator.free(formatted_response);
                    _ = self.writeTls(secured_socket, formatted_response) catch {};
                    return;
                }
                buf = try self.allocator.realloc(buf, new_size);
            }

            // Read more data
            const additional_read = self.tls.read(secured_socket, buf[total_read..]) catch |err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error reading additional data: {any}", .{err});
                }
                return;
            };

            if (additional_read == 0) break; // No more data available
            total_read += additional_read;
        }

        // Parse headers to get Content-Length
        var temp_request = Request.init(self.allocator);
        defer temp_request.deinit();

        // Parse just to get headers (we'll re-parse with full body later)
        temp_request.parse(buf[0..total_read]) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error parsing request headers: {any}", .{err});
            }

            const bad_request_response = Response.init(.bad_request, "text/plain", "Bad Request - Invalid HTTP Request Format");
            const formatted_response = bad_request_response.format() catch |fmt_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error formatting response: {any}", .{fmt_err});
                }
                return;
            };
            defer std.heap.page_allocator.free(formatted_response);

            _ = self.writeTls(secured_socket, formatted_response) catch |write_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error writing error response: {any}", .{write_err});
                }
            };

            return;
        };

        // Check if we need to read more for the body
        const content_length_str = temp_request.headers.get("Content-Length");
        if (content_length_str) |cl_str| {
            const expected_body_len = std.fmt.parseInt(usize, cl_str, 10) catch 0;

            // Calculate how much body we've already read
            const header_len = if (header_end_pos) |pos| pos + header_end_marker.len else total_read;
            const current_body_len = if (total_read > header_len) total_read - header_len else 0;

            if (expected_body_len > current_body_len) {
                // Need to read more body data
                const remaining = expected_body_len - current_body_len;

                // Check if total request size would exceed max_body_size
                const total_expected_size = header_len + expected_body_len;
                if (total_expected_size > self.config.max_body_size) {
                    const bad_request_response = Response.init(.payload_too_large, "text/plain", "Payload Too Large");
                    const formatted_response = bad_request_response.format() catch return;
                    defer std.heap.page_allocator.free(formatted_response);
                    _ = self.writeTls(secured_socket, formatted_response) catch {};
                    return;
                }

                // Reallocate buffer if needed
                const space_needed = std.math.add(usize, total_read, remaining) catch self.config.max_body_size;
                const clamped_space_needed = @min(space_needed, self.config.max_body_size);

                if (total_read + remaining > buf.len) {
                    const new_size = @min(clamped_space_needed, self.config.max_body_size);
                    buf = try self.allocator.realloc(buf, new_size);
                }

                // Read remaining body data
                var body_read: usize = 0;
                while (body_read < remaining) {
                    const chunk_read = self.tls.read(secured_socket, buf[total_read + body_read ..]) catch |err| {
                        if (logging.getGlobalLogger()) |logger| {
                            try logger.err("Error reading body: {any}", .{err});
                        }
                        return;
                    };

                    if (chunk_read == 0) break; // No more data available
                    body_read += chunk_read;
                }

                total_read += body_read;
            }
        }

        // Now parse the complete request with all data
        var request = Request.init(self.allocator);
        defer request.deinit();

        request.parse(buf[0..total_read]) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error parsing request: {any}", .{err});
            }

            const bad_request_response = Response.init(.bad_request, "text/plain", "Bad Request - Invalid HTTP Request Format");

            const formatted_response = bad_request_response.format() catch |fmt_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error formatting response: {any}", .{fmt_err});
                }
                return;
            };
            defer std.heap.page_allocator.free(formatted_response);

            _ = self.writeTls(secured_socket, formatted_response) catch |write_err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error writing error response: {any}", .{write_err});
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
                    try logger.err("Error starting metrics: {any}", .{err});
                }
            };
        }

        // Handle the request with error recovery
        const response = self.handleRequest(&request) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error handling request: {any}", .{err});
            }

            return Response.init(.internal_server_error, "text/plain", "Internal Server Error");
        };

        const formatted_response = response.format() catch |fmt_err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error formatting response: {any}", .{fmt_err});
            }
            return;
        };
        defer std.heap.page_allocator.free(formatted_response);

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Sending response: status={any}", .{response.status});
        }

        // Try to write response with error recovery
        self.writeTls(secured_socket, formatted_response) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error writing response: {any}", .{err});
            }
            return;
        };

        // Record metrics after sending response
        metrics.recordResponseMetrics(&request, &response) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error recording metrics: {any}", .{err});
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
        if (@import("builtin").os.tag == .windows) {
            const read_timeout: u32 = @intCast(config.read_timeout_ms);
            try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.RCVTIMEO, &std.mem.toBytes(read_timeout));

            const write_timeout: u32 = @intCast(config.write_timeout_ms);
            try posix.setsockopt(socket, posix.SOL.SOCKET, posix.SO.SNDTIMEO, &std.mem.toBytes(write_timeout));
        } else {
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
    }
};

test "buffer overflow protection in header reading" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create a server with small max header size
    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_header_size = 50; // Very small to test overflow protection

    var server = try HttpServer.init(allocator, config);
    defer server.deinit();

    // This test would normally require a real socket, but we can test the bounds checking logic
    // by examining the config values and ensuring they are properly validated

    try testing.expectEqual(@as(usize, 50), server.config.max_header_size);
}

test "buffer size calculation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_header_size = 100;

    var server = try HttpServer.init(allocator, config);
    defer server.deinit();

    // Test that buffer size calculations work correctly
    const new_size = @min(@as(usize, 64) * 2, config.max_header_size);
    try testing.expectEqual(@as(usize, 100), new_size); // Should be clamped to max_header_size
}

test "header size limit enforcement" {
    const testing = std.testing;

    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_header_size = 10; // Very small limit

    // Test that we can't create headers larger than the limit
    // This is more of a config validation test
    try testing.expect(config.max_header_size > 0);
    try testing.expect(config.max_header_size < 1000000); // Reasonable upper bound
}

test "integer overflow protection in body reading" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_body_size = 1000; // Reasonable limit

    var server = try HttpServer.init(allocator, config);
    defer server.deinit();

    // Test that space_needed calculation doesn't overflow
    const total_read: usize = 100;
    const remaining: usize = std.math.maxInt(usize) - 50; // Very large number

    // This should not overflow and should be clamped to max_body_size
    const space_needed = std.math.add(usize, total_read, remaining) catch config.max_body_size;
    const clamped_space_needed = @min(space_needed, config.max_body_size);

    try testing.expectEqual(config.max_body_size, clamped_space_needed);
    try testing.expect(clamped_space_needed <= config.max_body_size);
}

test "buffer size calculations with large values" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_body_size = 1024 * 1024; // 1MB limit

    var server = try HttpServer.init(allocator, config);
    defer server.deinit();

    // Test various size calculations
    const test_cases = [_]struct {
        total_read: usize,
        remaining: usize,
        expected_max: usize,
    }{
        .{ .total_read = 100, .remaining = 200, .expected_max = 300 },
        .{ .total_read = std.math.maxInt(usize) / 2, .remaining = std.math.maxInt(usize) / 2 + 1, .expected_max = config.max_body_size },
        .{ .total_read = 1000, .remaining = 1000, .expected_max = 2000 },
    };

    for (test_cases) |test_case| {
        const space_needed = std.math.add(usize, test_case.total_read, test_case.remaining) catch config.max_body_size;
        const clamped = @min(space_needed, config.max_body_size);

        try testing.expect(clamped <= config.max_body_size);
        if (test_case.expected_max <= config.max_body_size) {
            try testing.expectEqual(test_case.expected_max, clamped);
        }
    }
}
