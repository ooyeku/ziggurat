//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const ziggurat = @import("ziggurat_lib");
const logging = ziggurat.logging;

pub fn main() !void {
    // Get an allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    try logging.initGlobalLogger(allocator);
    if (logging.getGlobalLogger()) |logger| {
        logger.setLogLevel(.debug);
        try logger.info("Initializing server...", .{});
    }

    // Initialize metrics
    try ziggurat.metrics.initGlobalMetrics(allocator, 1000); // Keep last 1000 requests
    defer ziggurat.metrics.deinitGlobalMetrics();

    // Set up TLS certificates
    const cert_path = "cert.pem";
    const key_path = "key.pem";

    // Create self-signed certificates for development if they don't exist
    try createSelfSignedCertificatesIfNeeded(cert_path, key_path);

    // Create and configure server
    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8443) // Changed to standard HTTPS port
        .readTimeout(5000)
        .writeTimeout(5000)
        .enableTls(cert_path, key_path)
        .build();
    defer server.deinit();

    if (logging.getGlobalLogger()) |logger| {
        try logger.info("Server configured with host={s}, port={d}, TLS enabled", .{ "127.0.0.1", 8443 });
    }

    // Add middleware
    try server.middleware(logRequests);
    try server.middleware(validateContentType);
    try server.middleware(ziggurat.metrics.metricsMiddleware);
    if (logging.getGlobalLogger()) |logger| {
        try logger.debug("Middleware configured", .{});
    }

    // Add routes
    try server.get("/", handleRoot);
    try server.post("/api/data", handleData);
    if (logging.getGlobalLogger()) |logger| {
        try logger.debug("Routes configured", .{});
    }

    if (logging.getGlobalLogger()) |logger| {
        try logger.info("Starting server...", .{});
    }
    try server.start();

    // Print all stats
    if (ziggurat.metrics.getGlobalMetrics()) |manager| {
        try manager.printStats(std.io.getStdOut().writer());
    }

    // Get stats for specific endpoint
    if (ziggurat.metrics.getGlobalMetrics()) |manager| {
        if (try manager.getEndpointStats("GET", "/api/users")) |stats| {
            std.debug.print("Average response time: {d:.2}ms\n", .{stats.getAverageDuration()});
        }
    }
}

// Create self-signed certificates for development purposes if they don't exist
fn createSelfSignedCertificatesIfNeeded(cert_path: []const u8, key_path: []const u8) !void {
    // Check if files already exist
    const cert_exists = blk: {
        std.fs.cwd().access(cert_path, .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        break :blk true;
    };

    const key_exists = blk: {
        std.fs.cwd().access(key_path, .{}) catch |err| {
            if (err == error.FileNotFound) break :blk false;
            return err;
        };
        break :blk true;
    };

    if (cert_exists and key_exists) {
        if (logging.getGlobalLogger()) |logger| {
            try logger.info("Using existing certificates: {s} and {s}", .{ cert_path, key_path });
        }
        return;
    }

    if (logging.getGlobalLogger()) |logger| {
        try logger.info("Creating self-signed certificates for development use", .{});
    }

    // This would generate self-signed certificates
    // For now, just create dummy files with a warning
    const warning_text =
        \\-----BEGIN CERTIFICATE-----
        \\DEVELOPMENT USE ONLY - NOT SECURE
        \\Replace with real certificates in production
        \\-----END CERTIFICATE-----
    ;

    try std.fs.cwd().writeFile(.{
        .sub_path = cert_path,
        .data = warning_text,
    });
    try std.fs.cwd().writeFile(.{
        .sub_path = key_path,
        .data = warning_text,
    });

    if (logging.getGlobalLogger()) |logger| {
        try logger.info("Created development certificates. Replace with real certificates in production.", .{});
    }
}

fn logRequests(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (logging.getGlobalLogger()) |logger| {
        logger.info("{s} {s}", .{ @tagName(request.method), request.path }) catch {};
    }
    return null;
}

fn validateContentType(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (request.method == .POST) {
        if (request.headers.get("Content-Type")) |content_type| {
            if (!std.mem.eql(u8, content_type, "application/json")) {
                return ziggurat.errorResponse(
                    ziggurat.Status.unsupported_media_type,
                    "Only application/json is supported",
                );
            }
        }
    }
    return null;
}

fn handleRoot(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.text("Welcome to Zig HTTP Server!");
}

fn handleData(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.json("{\n  \"status\": \"success\"\n}");
}

test "server configuration" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8080)
        .build();
    defer server.deinit();

    try testing.expectEqual(@as(u16, 8080), server.inner.config.port);
    try testing.expectEqualStrings("127.0.0.1", server.inner.config.host);
}

test "HTTP request handling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = ziggurat.request.Request.init(allocator);
    defer request.deinit();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost:8080\r\n\r\n";
    try request.parse(raw_request);

    const response = handleRoot(&request);
    try testing.expectEqual(ziggurat.Status.ok, response.status);
}
