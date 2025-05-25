//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const ziggurat = @import("ziggurat");

// Simple in-memory cache for static files
const CacheEntry = struct {
    content: []const u8,
    content_type: []const u8,
    last_modified: i64,
};

var file_cache = std.StringHashMap(CacheEntry).init(std.heap.page_allocator);
const public_dir = "public";

pub fn main() !void {
    // Initialize the server
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the logger
    try ziggurat.logger.initGlobalLogger(allocator);
    const logger = ziggurat.logger.getGlobalLogger().?;

    // Create public directory if it doesn't exist
    try std.fs.cwd().makePath(public_dir);

    // Create some example static files
    try createExampleFiles();

    // Set up TLS certificates
    const cert_path = "cert.pem";
    const key_path = "key.pem";

    // Create self-signed certificates for development if they don't exist
    try createSelfSignedCertificatesIfNeeded(cert_path, key_path);

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8443) // Changed to standard HTTPS port
        .readTimeout(30000) // Longer timeout for file transfers
        .writeTimeout(30000)
        .enableTls(cert_path, key_path)
        .build();
    defer server.deinit();

    // Add middleware
    try server.middleware(logRequests);
    try server.middleware(setCacheHeaders);

    // Add routes
    try server.get("/", handleIndex);
    try server.get("/static/*", handleStaticFile);

    try logger.info("Static file server running at https://127.0.0.1:8443", .{});
    try server.start();
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
        if (ziggurat.logger.getGlobalLogger()) |logger| {
            try logger.info("Using existing certificates: {s} and {s}", .{ cert_path, key_path });
        }
        return;
    }

    if (ziggurat.logger.getGlobalLogger()) |logger| {
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

    if (ziggurat.logger.getGlobalLogger()) |logger| {
        try logger.info("Created development certificates. Replace with real certificates in production.", .{});
    }
}

fn createExampleFiles() !void {
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        try logger.debug("Creating example files in {s}/", .{public_dir});
    }

    // Create index.html
    const index_content =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\    <title>Ziggurat Static Server</title>
        \\    <link rel="stylesheet" href="/static/style.css">
        \\</head>
        \\<body>
        \\    <h1>Welcome to Ziggurat Static Server</h1>
        \\    <p>This is a simple static file server example.</p>
        \\    <script src="/static/main.js"></script>
        \\</body>
        \\</html>
    ;
    try std.fs.cwd().writeFile(.{
        .sub_path = public_dir ++ "/index.html",
        .data = index_content,
    });
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        try logger.debug("Created {s}/index.html", .{public_dir});
    }

    // Create style.css
    const css_content =
        \\body {
        \\    font-family: Arial, sans-serif;
        \\    max-width: 800px;
        \\    margin: 0 auto;
        \\    padding: 2rem;
        \\    line-height: 1.6;
        \\}
        \\h1 { color: #2c3e50; }
    ;
    try std.fs.cwd().writeFile(.{
        .sub_path = public_dir ++ "/style.css",
        .data = css_content,
    });
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        try logger.debug("Created {s}/style.css", .{public_dir});
    }

    // Create main.js
    const js_content =
        \\console.log("Static server is running!");
    ;
    try std.fs.cwd().writeFile(.{
        .sub_path = public_dir ++ "/main.js",
        .data = js_content,
    });
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        try logger.debug("Created {s}/main.js", .{public_dir});
    }
}

fn logRequests(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        logger.info("[{s}] {?s}", .{ @tagName(request.method), request.path }) catch {};
    }
    return null;
}

fn setCacheHeaders(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    _ = request;
    // In a real app, set Cache-Control, ETag, etc.
    return null;
}

fn handleIndex(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    const index_path = public_dir ++ "/index.html";

    if (readFileFromCache(index_path)) |entry| {
        return ziggurat.response.Response.init(
            .ok,
            entry.content_type,
            entry.content,
        );
    }

    const content = std.fs.cwd().readFileAlloc(
        std.heap.page_allocator,
        index_path,
        1024 * 1024, // 1MB max
    ) catch return ziggurat.response.Response.init(
        .not_found,
        "text/plain",
        "Index file not found",
    );

    // Cache the file
    file_cache.put(index_path, .{
        .content = content,
        .content_type = "text/html",
        .last_modified = std.time.timestamp(),
    }) catch {};

    return ziggurat.response.Response.init(
        .ok,
        "text/html",
        content,
    );
}

fn handleStaticFile(request: *ziggurat.request.Request) ziggurat.response.Response {
    const actual_path = request.path orelse return ziggurat.response.Response.init(
        .not_found,
        "text/plain",
        "File not found",
    );

    if (!std.mem.startsWith(u8, actual_path, "/static/")) {
        return ziggurat.response.Response.init(
            .not_found,
            "text/plain",
            "File not found",
        );
    }

    // Get the file path relative to the public directory
    const relative_path = actual_path[8..]; // Remove "/static/" prefix (8 chars)

    // Validate the path to prevent directory traversal
    if (std.mem.indexOf(u8, relative_path, "..")) |_| {
        return ziggurat.response.Response.init(
            .bad_request,
            "text/plain",
            "Invalid path: directory traversal attempt",
        );
    }

    // Construct the full path
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const file_path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ public_dir, relative_path }) catch
        return ziggurat.response.Response.init(
            .internal_server_error,
            "text/plain",
            "Path too long",
        );

    if (ziggurat.logger.getGlobalLogger()) |logger| {
        logger.debug("Serving static file: {s}", .{file_path}) catch {};
    }

    if (readFileFromCache(file_path)) |entry| {
        return ziggurat.response.Response.init(
            .ok,
            entry.content_type,
            entry.content,
        );
    }

    const content = std.fs.cwd().readFileAlloc(
        std.heap.page_allocator,
        file_path,
        1024 * 1024, // 1MB max
    ) catch return ziggurat.response.Response.init(
        .not_found,
        "text/plain",
        "File not found",
    );

    const content_type = getContentType(file_path);

    // Cache the file
    file_cache.put(file_path, .{
        .content = content,
        .content_type = content_type,
        .last_modified = std.time.timestamp(),
    }) catch {};

    return ziggurat.response.Response.init(
        .ok,
        content_type,
        content,
    );
}

fn readFileFromCache(path: []const u8) ?CacheEntry {
    if (file_cache.get(path)) |entry| {
        // In a real app, check if cache is stale
        return entry;
    }
    return null;
}

fn getContentType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) return "image/jpeg";
    return "application/octet-stream";
}
