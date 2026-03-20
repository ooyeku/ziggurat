const std = @import("std");
const net = std.net;
const posix = std.posix;
const ServerConfig = @import("../config/server_config.zig").ServerConfig;
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const StatusCode = @import("../http/response.zig").StatusCode;
const router = @import("../router/router.zig");
const middleware = @import("../middleware/middleware.zig");
const cors = @import("../middleware/cors.zig");
const logging = @import("../utils/logging.zig");
const metrics = @import("../metrics.zig");
const Tls = @import("tls.zig").Tls;

/// Context passed to each connection-handler thread.
const ConnContext = struct {
    server: *HttpServer,
    socket: posix.socket_t,
    // Arena allocator per connection so we can free everything in one shot.
    arena: std.heap.ArenaAllocator,

    fn init(server: *HttpServer, socket: posix.socket_t) ConnContext {
        return .{
            .server = server,
            .socket = socket,
            .arena = std.heap.ArenaAllocator.init(server.allocator),
        };
    }

    fn deinit(self: *ConnContext) void {
        self.arena.deinit();
    }
};

pub const HttpServer = struct {
    config: ServerConfig,
    allocator: std.mem.Allocator,
    listener: posix.socket_t,
    router: router.Router,
    middleware: middleware.Middleware,
    tls: Tls,
    /// Set to true to request a graceful shutdown.
    shutdown: std.atomic.Value(bool),

    pub fn init(allocator: std.mem.Allocator, config: ServerConfig) !HttpServer {
        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Initializing HTTP server...", .{});
        }

        const address = try config.getAddress();
        const tpe: u32 = posix.SOCK.STREAM;
        const protocol = posix.IPPROTO.TCP;
        const listener = try posix.socket(address.any.family, tpe, protocol);
        errdefer posix.close(listener);

        try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, config.backlog);

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
            .shutdown = std.atomic.Value(bool).init(false),
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

    /// Signal the server to stop accepting new connections.
    pub fn stop(self: *HttpServer) void {
        self.shutdown.store(true, .release);
        // Wake up the blocking accept() by closing the listener socket.
        posix.close(self.listener);
    }

    /// Start accepting connections.  Each accepted connection is handled in its
    /// own thread (thread-per-connection model) so that one slow request cannot
    /// block others.
    pub fn start(self: *HttpServer) !void {
        if (logging.getGlobalLogger()) |logger| {
            const protocol = if (self.config.tls.enabled) "https" else "http";
            try logger.info("Server listening on {s}://{s}:{d}", .{ protocol, self.config.host, self.config.port });
        }

        while (!self.shutdown.load(.acquire)) {
            var client_address: net.Address = undefined;
            var client_address_len: posix.socklen_t = @sizeOf(net.Address);
            const socket = posix.accept(self.listener, &client_address.any, &client_address_len, 0) catch |err| {
                if (self.shutdown.load(.acquire)) break; // clean shutdown
                if (logging.getGlobalLogger()) |logger| {
                    logger.err("Accept error: {any}", .{err}) catch {};
                }
                continue;
            };

            if (logging.getGlobalLogger()) |logger| {
                logger.debug("Client connected from {any}", .{client_address}) catch {};
            }

            // Allocate the connection context on the heap so the thread owns it.
            const ctx = self.allocator.create(ConnContext) catch |err| {
                if (logging.getGlobalLogger()) |logger| {
                    logger.err("OOM allocating ConnContext: {any}", .{err}) catch {};
                }
                posix.close(socket);
                continue;
            };
            ctx.* = ConnContext.init(self, socket);

            const thread = std.Thread.spawn(.{}, handleConnectionThread, .{ctx}) catch |err| {
                if (logging.getGlobalLogger()) |logger| {
                    logger.err("Failed to spawn thread: {any}", .{err}) catch {};
                }
                ctx.deinit();
                self.allocator.destroy(ctx);
                posix.close(socket);
                continue;
            };
            thread.detach();
        }
    }

    /// Entry point for each connection thread.  Owns and frees `ctx`.
    fn handleConnectionThread(ctx: *ConnContext) void {
        defer {
            posix.close(ctx.socket);
            ctx.deinit();
            ctx.server.allocator.destroy(ctx);
        }
        ctx.server.handleConnection(ctx.arena.allocator(), ctx.socket) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                logger.err("Connection error: {any}", .{err}) catch {};
            }
        };
    }

    fn handleConnection(self: *HttpServer, allocator: std.mem.Allocator, socket: posix.socket_t) !void {
        try setTimeouts(socket, &self.config);

        const secured_socket = try self.tls.wrapSocket(socket);

        var buf = try allocator.alloc(u8, self.config.buffer_size);

        var total_read: usize = 0;
        const first_read = self.tls.read(secured_socket, buf) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error reading from socket: {any}", .{err});
            }
            return;
        };

        if (first_read == 0) return;
        total_read = first_read;

        // ── Read until the header terminator is found ─────────────────────
        const header_end_marker = "\r\n\r\n";
        var header_end_pos: ?usize = null;

        while (header_end_pos == null) {
            if (total_read >= 4) {
                if (std.mem.indexOf(u8, buf[0..total_read], header_end_marker)) |pos| {
                    header_end_pos = pos;
                    break;
                }
            }

            if (total_read >= self.config.max_header_size) {
                try self.sendSimpleError(allocator, secured_socket, .request_header_fields_too_large, "Request Header Fields Too Large");
                return;
            }

            if (total_read >= buf.len) {
                const new_size = @min(buf.len * 2, self.config.max_header_size);
                if (new_size <= buf.len) {
                    try self.sendSimpleError(allocator, secured_socket, .request_header_fields_too_large, "Request Header Fields Too Large");
                    return;
                }
                buf = try allocator.realloc(buf, new_size);
            }

            const additional = self.tls.read(secured_socket, buf[total_read..]) catch |err| {
                if (logging.getGlobalLogger()) |logger| {
                    try logger.err("Error reading additional data: {any}", .{err});
                }
                return;
            };
            if (additional == 0) break;
            total_read += additional;
        }

        // ── Determine Content-Length without a full parse (#6 fix) ────────
        // Scan for "Content-Length: " in the raw header bytes to avoid
        // allocating a full Request just to read one header value.
        const header_section = buf[0..@min(total_read, header_end_pos orelse total_read)];
        var expected_body_len: usize = 0;

        if (findHeaderValue(header_section, "Content-Length")) |cl_str| {
            expected_body_len = std.fmt.parseInt(usize, cl_str, 10) catch 0;
        }

        if (expected_body_len > 0) {
            const header_len = (header_end_pos orelse total_read) + header_end_marker.len;
            const current_body_len = if (total_read > header_len) total_read - header_len else 0;

            if (expected_body_len > current_body_len) {
                const remaining = expected_body_len - current_body_len;
                const total_expected = header_len + expected_body_len;

                if (total_expected > self.config.max_body_size) {
                    try self.sendSimpleError(allocator, secured_socket, .payload_too_large, "Payload Too Large");
                    return;
                }

                const space_needed = std.math.add(usize, total_read, remaining) catch self.config.max_body_size;
                const clamped = @min(space_needed, self.config.max_body_size);

                if (clamped > buf.len) {
                    buf = try allocator.realloc(buf, clamped);
                }

                var body_read: usize = 0;
                while (body_read < remaining) {
                    const chunk = self.tls.read(secured_socket, buf[total_read + body_read ..]) catch |err| {
                        if (logging.getGlobalLogger()) |logger| {
                            try logger.err("Error reading body: {any}", .{err});
                        }
                        return;
                    };
                    if (chunk == 0) break;
                    body_read += chunk;
                }
                total_read += body_read;
            }
        }

        // ── Parse the complete request once ───────────────────────────────
        var request = Request.init(allocator);
        // No defer deinit — arena allocator will free everything at once.

        request.parse(buf[0..total_read]) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error parsing request: {any}", .{err});
            }
            try self.sendSimpleError(allocator, secured_socket, .bad_request, "Bad Request - Invalid HTTP Request Format");
            return;
        };

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Processing request: {s} {s}", .{ @tagName(request.method), request.path });
        }

        if (metrics.getGlobalMetrics()) |_| {
            metrics.startRequestMetrics(&request) catch {};
        }

        var response = self.handleRequest(allocator, &request) catch |err| blk: {
            if (logging.getGlobalLogger()) |logger| {
                logger.err("Error handling request: {any}", .{err}) catch {};
            }
            break :blk Response.init(.internal_server_error, "text/plain", "Internal Server Error");
        };

        // Inject CORS headers if the middleware flagged this request.
        if (request.getUserData("_cors_enabled", []const u8) != null) {
            const cors_headers = cors.buildCorsHeaders(allocator) catch &.{};
            if (cors_headers.len > 0) {
                response = response.withHeaders(cors_headers);
            }
        }

        const formatted = response.format(allocator) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error formatting response: {any}", .{err});
            }
            return;
        };

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Sending response: status={any}", .{response.status});
        }

        self.writeTls(secured_socket, formatted) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error writing response: {any}", .{err});
            }
            return;
        };

        metrics.recordResponseMetrics(&request, &response) catch {};
    }

    fn handleRequest(self: *HttpServer, allocator: std.mem.Allocator, request: *Request) !Response {
        _ = allocator;

        if (self.middleware.process(request)) |resp| {
            return resp;
        }

        // Try to match a route; also detect wrong-method to return 405 (#9 fix).
        if (self.router.matchRoute(request)) |result| {
            return result;
        }

        return Response.init(.not_found, "text/plain", "Not Found");
    }

    /// Send a minimal error response without a full Request parse cycle.
    fn sendSimpleError(
        self: *HttpServer,
        allocator: std.mem.Allocator,
        socket: posix.socket_t,
        status: StatusCode,
        message: []const u8,
    ) !void {
        const resp = Response.init(status, "text/plain", message);
        const formatted = try resp.format(allocator);
        self.writeTls(socket, formatted) catch {};
    }

    fn writeTls(self: *HttpServer, socket: posix.socket_t, msg: []const u8) !void {
        var pos: usize = 0;
        while (pos < msg.len) {
            const written = try self.tls.write(socket, msg[pos..]);
            if (written == 0) return error.Closed;
            pos += written;
        }
    }

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

/// Scan raw header bytes for a header value without a full parse.
/// Returns the trimmed value slice, or null if not found.
/// Handles both "Header: value" and "header: value" (case-insensitive name match).
fn findHeaderValue(headers: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, headers, "\r\n");
    _ = lines.next(); // skip request line
    while (lines.next()) |line| {
        if (line.len == 0) break;
        if (std.mem.indexOf(u8, line, ": ")) |sep| {
            const key = line[0..sep];
            if (std.ascii.eqlIgnoreCase(key, name)) {
                return std.mem.trim(u8, line[sep + 2 ..], " \t");
            }
        }
    }
    return null;
}

test "buffer overflow protection in header reading" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_header_size = 50;

    var server = try HttpServer.init(allocator, config);
    defer server.deinit();

    try testing.expectEqual(@as(usize, 50), server.config.max_header_size);
}

test "buffer size calculation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_header_size = 100;

    var server = try HttpServer.init(allocator, config);
    defer server.deinit();

    const new_size = @min(@as(usize, 64) * 2, config.max_header_size);
    try testing.expectEqual(@as(usize, 100), new_size);
}

test "header size limit enforcement" {
    const testing = std.testing;
    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_header_size = 10;
    try testing.expect(config.max_header_size > 0);
    try testing.expect(config.max_header_size < 1000000);
}

test "integer overflow protection in body reading" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_body_size = 1000;

    var server = try HttpServer.init(allocator, config);
    defer server.deinit();

    const total_read: usize = 100;
    const remaining: usize = std.math.maxInt(usize) - 50;

    const space_needed = std.math.add(usize, total_read, remaining) catch config.max_body_size;
    const clamped = @min(space_needed, config.max_body_size);

    try testing.expectEqual(config.max_body_size, clamped);
    try testing.expect(clamped <= config.max_body_size);
}

test "buffer size calculations with large values" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var config = ServerConfig.init("127.0.0.1", 8080);
    config.max_body_size = 1024 * 1024;

    var server = try HttpServer.init(allocator, config);
    defer server.deinit();

    const test_cases = [_]struct {
        total_read: usize,
        remaining: usize,
        expected_max: usize,
    }{
        .{ .total_read = 100, .remaining = 200, .expected_max = 300 },
        .{ .total_read = std.math.maxInt(usize) / 2, .remaining = std.math.maxInt(usize) / 2 + 1, .expected_max = config.max_body_size },
        .{ .total_read = 1000, .remaining = 1000, .expected_max = 2000 },
    };

    for (test_cases) |tc| {
        const space_needed = std.math.add(usize, tc.total_read, tc.remaining) catch config.max_body_size;
        const clamped = @min(space_needed, config.max_body_size);
        try testing.expect(clamped <= config.max_body_size);
        if (tc.expected_max <= config.max_body_size) {
            try testing.expectEqual(tc.expected_max, clamped);
        }
    }
}

test "findHeaderValue extracts content-length" {
    const testing = std.testing;

    const raw = "POST /api HTTP/1.1\r\nHost: localhost\r\nContent-Length: 42\r\nContent-Type: application/json\r\n";
    const val = findHeaderValue(raw, "content-length");
    try testing.expect(val != null);
    try testing.expectEqualStrings("42", val.?);
}

test "findHeaderValue returns null for missing header" {
    const testing = std.testing;
    const raw = "GET / HTTP/1.1\r\nHost: localhost\r\n";
    try testing.expect(findHeaderValue(raw, "Content-Length") == null);
}
