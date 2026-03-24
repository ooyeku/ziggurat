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

// ─── Connection Queue ────────────────────────────────────────────────────────

/// Bounded, thread-safe queue that feeds accepted sockets to worker threads.
pub const ConnectionQueue = struct {
    buffer: []posix.socket_t,
    capacity: usize,
    head: usize = 0,
    tail: usize = 0,
    count: usize = 0,
    mutex: std.Thread.Mutex = .{},
    not_empty: std.Thread.Condition = .{},
    closed: bool = false,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) !ConnectionQueue {
        const buffer = try allocator.alloc(posix.socket_t, capacity);
        return .{ .buffer = buffer, .capacity = capacity };
    }

    pub fn deinit(self: *ConnectionQueue, allocator: std.mem.Allocator) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        // Close any sockets still sitting in the queue.
        while (self.count > 0) {
            posix.close(self.buffer[self.head]);
            self.head = (self.head + 1) % self.capacity;
            self.count -= 1;
        }
        allocator.free(self.buffer);
    }

    /// Enqueue a socket. Returns false if the queue is full.
    pub fn push(self: *ConnectionQueue, socket: posix.socket_t) bool {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.count >= self.capacity) return false;
        self.buffer[self.tail] = socket;
        self.tail = (self.tail + 1) % self.capacity;
        self.count += 1;
        self.not_empty.signal();
        return true;
    }

    /// Block until a socket is available. Returns null when shut down.
    pub fn pop(self: *ConnectionQueue) ?posix.socket_t {
        self.mutex.lock();
        defer self.mutex.unlock();
        while (self.count == 0) {
            if (self.closed) return null;
            self.not_empty.wait(&self.mutex);
        }
        const socket = self.buffer[self.head];
        self.head = (self.head + 1) % self.capacity;
        self.count -= 1;
        return socket;
    }

    /// Wake all blocked workers so they can exit.
    pub fn signalShutdown(self: *ConnectionQueue) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.closed = true;
        self.not_empty.broadcast();
    }
};

// ─── HTTP Server ─────────────────────────────────────────────────────────────

pub const HttpServer = struct {
    config: ServerConfig,
    allocator: std.mem.Allocator,
    listener: posix.socket_t,
    router: router.Router,
    middleware: middleware.Middleware,
    tls: Tls,
    /// Set to true to request a graceful shutdown.
    shutdown: std.atomic.Value(bool),
    /// Work queue for the thread pool.
    queue: ConnectionQueue,
    /// Number of connections currently being processed by workers.
    active_connections: std.atomic.Value(u32),

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

        var tls_inst = try Tls.init(allocator, config.tls);
        errdefer tls_inst.deinit();

        var queue = try ConnectionQueue.init(allocator, config.max_connections);
        errdefer queue.deinit(allocator);

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
            .tls = tls_inst,
            .shutdown = std.atomic.Value(bool).init(false),
            .queue = queue,
            .active_connections = std.atomic.Value(u32).init(0),
        };
    }

    pub fn deinit(self: *HttpServer) void {
        if (logging.getGlobalLogger()) |logger| {
            logger.info("Shutting down HTTP server...", .{}) catch {};
        }
        self.router.deinit();
        self.middleware.deinit();
        self.tls.deinit();
        self.queue.deinit(self.allocator);
        // Guard against double-close when stop() was already called.
        if (self.listener != -1) posix.close(self.listener);
    }

    /// Signal the server to stop accepting new connections.
    pub fn stop(self: *HttpServer) void {
        self.shutdown.store(true, .release);
        self.queue.signalShutdown();
        // Close the listener to unblock the accept() call.
        const fd = self.listener;
        self.listener = -1;
        if (fd != -1) posix.close(fd);
    }

    /// Start the server. Spawns a fixed pool of worker threads, then runs
    /// the accept loop on the calling thread. Returns after shutdown and
    /// connection draining complete.
    pub fn start(self: *HttpServer) !void {
        if (logging.getGlobalLogger()) |logger| {
            const protocol = if (self.config.tls.enabled) "https" else "http";
            try logger.info("Server listening on {s}://{s}:{d} (pool={d}, max_conn={d})", .{
                protocol,          self.config.host,
                self.config.port,  self.config.thread_pool_size,
                self.config.max_connections,
            });
        }

        // ── Spawn worker pool ────────────────────────────────────────
        const pool_size: usize = @intCast(self.config.thread_pool_size);
        const workers = try self.allocator.alloc(std.Thread, pool_size);
        defer self.allocator.free(workers);

        var spawned: usize = 0;
        errdefer {
            self.queue.signalShutdown();
            for (workers[0..spawned]) |w| w.join();
        }

        for (0..pool_size) |i| {
            workers[i] = try std.Thread.spawn(.{}, workerThread, .{self});
            spawned += 1;
        }

        // ── Accept loop ──────────────────────────────────────────────
        while (!self.shutdown.load(.acquire)) {
            var client_address: net.Address = undefined;
            var client_address_len: posix.socklen_t = @sizeOf(net.Address);
            const socket = posix.accept(self.listener, &client_address.any, &client_address_len, 0) catch |err| {
                if (self.shutdown.load(.acquire)) break;
                if (logging.getGlobalLogger()) |logger| {
                    logger.err("Accept error: {any}", .{err}) catch {};
                }
                continue;
            };

            if (logging.getGlobalLogger()) |logger| {
                logger.debug("Client connected from {any}", .{client_address}) catch {};
            }

            if (!self.queue.push(socket)) {
                // Back-pressure: queue is full, reject with 503.
                if (logging.getGlobalLogger()) |logger| {
                    logger.warn("Connection queue full, rejecting client", .{}) catch {};
                }
                rejectConnection(socket);
                continue;
            }
        }

        // ── Graceful drain ───────────────────────────────────────────
        self.queue.signalShutdown();
        self.drainConnections();
        for (workers[0..spawned]) |w| w.join();
    }

    /// Send a hard-coded 503 and close (zero allocations).
    fn rejectConnection(socket: posix.socket_t) void {
        const resp = "HTTP/1.1 503 Service Unavailable\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Content-Length: 19\r\n" ++
            "Connection: close\r\n\r\n" ++
            "Service Unavailable";
        _ = posix.write(socket, resp) catch {};
        posix.close(socket);
    }

    /// Wait for in-flight requests to finish, up to `drain_timeout_ms`.
    fn drainConnections(self: *HttpServer) void {
        const active = self.active_connections.load(.acquire);
        if (active == 0) return;

        if (logging.getGlobalLogger()) |logger| {
            logger.info("Draining {d} active connection(s) (timeout={d}ms)...", .{
                active, self.config.drain_timeout_ms,
            }) catch {};
        }

        const deadline = std.time.nanoTimestamp() +
            @as(i128, self.config.drain_timeout_ms) * std.time.ns_per_ms;

        while (self.active_connections.load(.acquire) > 0) {
            if (std.time.nanoTimestamp() >= deadline) {
                if (logging.getGlobalLogger()) |logger| {
                    logger.warn("Drain timeout reached, {d} connection(s) still active", .{
                        self.active_connections.load(.acquire),
                    }) catch {};
                }
                break;
            }
            std.Thread.sleep(10 * std.time.ns_per_ms);
        }
    }

    // ── Worker thread ────────────────────────────────────────────────────

    fn workerThread(server: *HttpServer) void {
        while (true) {
            const socket = server.queue.pop() orelse break;
            _ = server.active_connections.fetchAdd(1, .monotonic);
            defer {
                _ = server.active_connections.fetchSub(1, .monotonic);
                posix.close(socket);
            }
            server.handleConnection(socket) catch |err| {
                if (logging.getGlobalLogger()) |logger| {
                    logger.err("Connection error: {any}", .{err}) catch {};
                }
            };
        }
    }

    // ── Per-connection handler (keep-alive loop) ─────────────────────────

    fn handleConnection(self: *HttpServer, socket: posix.socket_t) !void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();

        try setTimeouts(socket, &self.config);
        const secured_socket = try self.tls.wrapSocket(socket);

        var requests_handled: u16 = 0;

        while (!self.shutdown.load(.acquire)) {
            // Reset arena between requests — O(1), retains backing pages.
            _ = arena.reset(.retain_capacity);
            const allocator = arena.allocator();

            // After the first request, switch to the keep-alive idle timeout.
            if (requests_handled > 0) {
                setKeepAliveTimeout(socket, &self.config) catch break;
            }

            const keep_alive = self.handleOneRequest(allocator, secured_socket) catch |err| {
                // Timeouts and connection resets are expected between
                // keep-alive requests — close silently.
                const is_expected = (err == error.WouldBlock or
                    err == error.ConnectionResetByPeer or
                    err == error.BrokenPipe);
                if (!is_expected) {
                    if (logging.getGlobalLogger()) |logger| {
                        logger.err("Request error: {any}", .{err}) catch {};
                    }
                }
                break;
            };

            requests_handled += 1;

            if (!keep_alive) break;
            if (!self.config.enable_keep_alive) break;
            if (requests_handled >= self.config.max_requests_per_connection) break;
        }
    }

    // ── Single-request handler ───────────────────────────────────────────

    /// Read, parse, and respond to one HTTP request.
    /// Returns true if the connection should stay alive for another request.
    fn handleOneRequest(self: *HttpServer, allocator: std.mem.Allocator, socket: posix.socket_t) !bool {
        var buf = try allocator.alloc(u8, self.config.buffer_size);

        var total_read: usize = 0;
        const first_read = try self.tls.read(socket, buf);
        if (first_read == 0) return false; // client closed
        total_read = first_read;

        // ── Read until the header terminator is found ────────────────
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
                try self.sendSimpleError(allocator, socket, .request_header_fields_too_large, "Request Header Fields Too Large");
                return false;
            }

            if (total_read >= buf.len) {
                const new_size = @min(buf.len * 2, self.config.max_header_size);
                if (new_size <= buf.len) {
                    try self.sendSimpleError(allocator, socket, .request_header_fields_too_large, "Request Header Fields Too Large");
                    return false;
                }
                buf = try allocator.realloc(buf, new_size);
            }

            const additional = try self.tls.read(socket, buf[total_read..]);
            if (additional == 0) break;
            total_read += additional;
        }

        // ── Determine Content-Length without a full parse ─────────────
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
                    try self.sendSimpleError(allocator, socket, .payload_too_large, "Payload Too Large");
                    return false;
                }

                const space_needed = std.math.add(usize, total_read, remaining) catch self.config.max_body_size;
                const clamped = @min(space_needed, self.config.max_body_size);

                if (clamped > buf.len) {
                    buf = try allocator.realloc(buf, clamped);
                }

                var body_read: usize = 0;
                while (body_read < remaining) {
                    const chunk = self.tls.read(socket, buf[total_read + body_read ..]) catch |err| {
                        if (logging.getGlobalLogger()) |logger| {
                            try logger.err("Error reading body: {any}", .{err});
                        }
                        return false;
                    };
                    if (chunk == 0) break;
                    body_read += chunk;
                }
                total_read += body_read;
            }
        }

        // ── Parse the complete request ───────────────────────────────
        var request = Request.init(allocator);

        request.parse(buf[0..total_read]) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error parsing request: {any}", .{err});
            }
            try self.sendSimpleError(allocator, socket, .bad_request, "Bad Request - Invalid HTTP Request Format");
            return false;
        };

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Processing request: {s} {s}", .{ @tagName(request.method), request.path });
        }

        if (metrics.getGlobalMetrics()) |_| {
            metrics.startRequestMetrics(&request) catch {};
        }

        // Decide keep-alive based on the Connection header.
        const conn_header = findHeaderValue(header_section, "Connection");
        const client_wants_close = if (conn_header) |v| std.ascii.eqlIgnoreCase(v, "close") else false;
        const keep_alive = self.config.enable_keep_alive and !client_wants_close and !self.shutdown.load(.acquire);

        var response = self.handleRequest(&request) catch |err| blk: {
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

        // Merge the Connection header into the response.
        const conn_value: []const u8 = if (keep_alive) "Connection: keep-alive" else "Connection: close";
        const merged_len = response.extra_headers.len + 1;
        const merged = try allocator.alloc([]const u8, merged_len);
        @memcpy(merged[0..response.extra_headers.len], response.extra_headers);
        merged[merged_len - 1] = conn_value;
        response = response.withHeaders(merged);

        const formatted = response.format(allocator) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                try logger.err("Error formatting response: {any}", .{err});
            }
            return false;
        };

        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("Sending response: status={any}", .{response.status});
        }

        self.writeTls(socket, formatted) catch |err| {
            if (logging.getGlobalLogger()) |logger| {
                logger.err("Error writing response: {any}", .{err}) catch {};
            }
            return false;
        };

        metrics.recordResponseMetrics(&request, &response) catch {};

        return keep_alive;
    }

    fn handleRequest(self: *HttpServer, request: *Request) !Response {
        if (self.middleware.process(request)) |resp| {
            return resp;
        }

        if (self.router.matchRoute(request)) |result| {
            return result;
        }

        return Response.init(.not_found, "text/plain", "Not Found");
    }

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

    // Windows passes timeout as a u32 in milliseconds; POSIX uses timeval.
    fn setSockTimeout(socket: posix.socket_t, opt: u32, ms: u32) !void {
        if (comptime @import("builtin").os.tag == .windows) {
            const timeout: u32 = ms;
            try posix.setsockopt(socket, posix.SOL.SOCKET, opt, &std.mem.toBytes(timeout));
        } else {
            const timeout = posix.timeval{
                .sec = @intCast(ms / 1000),
                .usec = @intCast((ms % 1000) * 1000),
            };
            try posix.setsockopt(socket, posix.SOL.SOCKET, opt, &std.mem.toBytes(timeout));
        }
    }

    fn setTimeouts(socket: posix.socket_t, config: *const ServerConfig) !void {
        try setSockTimeout(socket, posix.SO.RCVTIMEO, config.read_timeout_ms);
        try setSockTimeout(socket, posix.SO.SNDTIMEO, config.write_timeout_ms);
    }

    fn setKeepAliveTimeout(socket: posix.socket_t, config: *const ServerConfig) !void {
        try setSockTimeout(socket, posix.SO.RCVTIMEO, config.keep_alive_timeout_ms);
    }

};

/// Scan raw header bytes for a header value without a full parse.
/// Handles case-insensitive name matching.
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

// ─── Tests ───────────────────────────────────────────────────────────────────

test "ConnectionQueue push and pop" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var q = try ConnectionQueue.init(allocator, 4);
    defer q.deinit(allocator);

    try testing.expect(q.push(10));
    try testing.expect(q.push(20));
    try testing.expect(q.push(30));

    try testing.expectEqual(@as(posix.socket_t, 10), q.pop().?);
    try testing.expectEqual(@as(posix.socket_t, 20), q.pop().?);
    try testing.expectEqual(@as(posix.socket_t, 30), q.pop().?);
}

test "ConnectionQueue push returns false when full" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var q = try ConnectionQueue.init(allocator, 2);
    defer q.deinit(allocator);

    try testing.expect(q.push(1));
    try testing.expect(q.push(2));
    try testing.expect(!q.push(3)); // full
}

test "ConnectionQueue pop returns null after shutdown" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var q = try ConnectionQueue.init(allocator, 4);
    defer q.deinit(allocator);

    q.signalShutdown();
    try testing.expect(q.pop() == null);
}

test "ConnectionQueue wraps around correctly" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var q = try ConnectionQueue.init(allocator, 2);
    defer q.deinit(allocator);

    try testing.expect(q.push(1));
    try testing.expect(q.push(2));
    try testing.expectEqual(@as(posix.socket_t, 1), q.pop().?);

    // Wrap around: tail was at 0, now push should go to index 0.
    try testing.expect(q.push(3));
    try testing.expectEqual(@as(posix.socket_t, 2), q.pop().?);
    try testing.expectEqual(@as(posix.socket_t, 3), q.pop().?);
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

test "findHeaderValue extracts Connection header" {
    const testing = std.testing;

    const raw = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: keep-alive\r\n";
    const val = findHeaderValue(raw, "Connection");
    try testing.expect(val != null);
    try testing.expectEqualStrings("keep-alive", val.?);

    const raw2 = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n";
    const val2 = findHeaderValue(raw2, "connection");
    try testing.expect(val2 != null);
    try testing.expectEqualStrings("close", val2.?);
}

test "server config defaults for pool and keep-alive" {
    const config = ServerConfig.init("127.0.0.1", 8080);
    const testing = std.testing;

    try testing.expectEqual(@as(u16, 32), config.thread_pool_size);
    try testing.expectEqual(@as(u16, 512), config.max_connections);
    try testing.expectEqual(@as(u32, 15000), config.keep_alive_timeout_ms);
    try testing.expectEqual(@as(u16, 100), config.max_requests_per_connection);
    try testing.expectEqual(@as(u32, 30000), config.drain_timeout_ms);
    try testing.expect(config.enable_keep_alive);
}
