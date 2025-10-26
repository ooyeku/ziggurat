//! Static file server example using the NEW Ziggurat API
//! Demonstrates robust static file serving with logging, CORS, and live metrics

const std = @import("std");
const ziggurat = @import("ziggurat");

var PUBLIC_DIR: []const u8 = "public";

pub fn main() !void {
    // Initialize the server
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // NEW API: Initialize all features in one place
    try ziggurat.features.initialize(allocator, .{
        .logging = .{ .level = .info, .colors = true },
        .metrics = .{ .max_requests = 500 },
        .errors = .{ .debug = false },
        .cors = .{},
    });
    defer ziggurat.features.deinitialize();

    // Ensure public directory exists (contains your static assets)
    try std.fs.cwd().makePath(PUBLIC_DIR);

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8080)
        .readTimeout(30000)
        .writeTimeout(30000)
        .build();
    defer server.deinit();

    // Add middleware in order: logging -> CORS
    try server.middleware(ziggurat.request_logger.requestLoggingMiddleware);
    try server.middleware(ziggurat.cors.corsMiddleware);

    // Add routes
    try server.get("/", handleIndex);
    try server.get("/static/*", handleStaticFile);
    try server.get("/metrics", handleMetrics);

    // NEW API: Use simplified logging
    try ziggurat.log.info("Static file server v2.0 running at http://127.0.0.1:8080", .{});
    try ziggurat.log.info("Features: CORS, Security Headers, Caching, Metrics", .{});
    try server.start();
}

fn createExampleFiles() !void {
    // Create index.html
    const index_html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Ziggurat Static Server</title>
        \\  <link rel="stylesheet" href="/static/style.css">
        \\</head>
        \\<body>
        \\  <h1>Welcome to Ziggurat Static Server</h1>
        \\  <p>This is a static file server built with Ziggurat.</p>
        \\  <script src="/static/main.js"></script>
        \\</body>
        \\</html>
    ;

    try std.fs.cwd().writeFile(.{
        .sub_path = "public/index.html",
        .data = index_html,
    });

    // Create style.css
    const style_css =
        \\body {
        \\  font-family: Arial, sans-serif;
        \\  margin: 40px;
        \\  background-color: #f5f5f5;
        \\}
        \\h1 {
        \\  color: #333;
        \\}
    ;

    try std.fs.cwd().writeFile(.{
        .sub_path = "public/style.css",
        .data = style_css,
    });

    // Create main.js
    const main_js =
        \\console.log('Ziggurat Static Server');
        \\document.addEventListener('DOMContentLoaded', function() {
        \\  console.log('Page loaded');
        \\});
    ;

    try std.fs.cwd().writeFile(.{
        .sub_path = "public/main.js",
        .data = main_js,
    });

    try ziggurat.log.info("Example files created in {s}/", .{PUBLIC_DIR});
}


fn handleIndex(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;

    const index_html = std.fs.cwd().readFileAlloc(std.heap.page_allocator, "public/index.html", 65536) catch {
        return ziggurat.response.Response.errorResponse(.not_found, "index.html not found");
    };

    return ziggurat.response.Response.html(index_html);
}

fn handleStaticFile(request: *ziggurat.request.Request) ziggurat.response.Response {
    // Extract file path from route parameter
    const file_path = request.path;

    // Security: prevent directory traversal
    if (std.mem.indexOf(u8, file_path, "..") != null) {
        return ziggurat.response.Response.errorResponse(.forbidden, "Directory traversal not allowed");
    }

    // Load file from disk
    const full_path = std.fmt.allocPrint(
        std.heap.page_allocator,
        "public/{s}",
        .{file_path[8..]}, // Skip "/static/"
    ) catch {
        return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate path");
    };

    const content = std.fs.cwd().readFileAlloc(std.heap.page_allocator, full_path, 65536) catch {
        return ziggurat.response.Response.errorResponse(.not_found, "File not found");
    };

    // Determine content type
    const content_type = ziggurat.json_helpers.detectContentType(full_path);

    return ziggurat.response.Response.init(.ok, content_type, content);
}

fn handleMetrics(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;

    if (ziggurat.metrics.getGlobalMetrics()) |manager| {
        var buf: [2048]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        writer.writeAll("{\"metrics\":{\"recent_requests\":[") catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format metrics");

        const recent = manager.getRecentRequests();
        for (recent, 0..) |metric, i| {
            const comma = if (i == recent.len - 1) "" else ",";
            std.fmt.format(
                writer,
                "{{\"path\":\"{s}\",\"method\":\"{s}\",\"duration_ms\":{d},\"status\":{d}}}{s}",
                .{ metric.path, metric.method, metric.duration_ms, metric.status_code, comma },
            ) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format metrics");
        }

        writer.writeAll("]}}") catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format metrics");

        const metrics_str = std.heap.page_allocator.dupe(u8, fbs.getWritten()) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate metrics");

        return ziggurat.response.Response.json(metrics_str);
    }

    return ziggurat.response.Response.errorResponse(.internal_server_error, "Metrics not initialized");
}
