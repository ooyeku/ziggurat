//! Example using the NEW Ziggurat API
//! This demonstrates the cleaner, more intuitive API design

const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // NEW API: Single unified initialization with features
    var server = try ziggurat.ServerBuilder.init(allocator)
        .host("127.0.0.1")
        .port(3000)
        .build();
    defer server.deinit();

    // Initialize all features at once
    try ziggurat.features.initialize(allocator, .{
        .logging = .{ .level = .info, .colors = true },
        .metrics = .{ .max_requests = 1000 },
        .errors = .{ .debug = false },
        .cors = .{},
        .session = .{ .ttl_seconds = 3600 },
        .rate_limit = .{ .requests_per_minute = 100 },
    });
    defer ziggurat.features.deinitialize();

    // Add routes
    try server.get("/", handleRoot);
    try server.get("/users/:id", handleGetUser);
    try server.post("/users", handleCreateUser);

    // Add built-in middleware
    try server.middleware(ziggurat.request_logger.requestLoggingMiddleware);
    try server.middleware(ziggurat.cors.corsMiddleware);
    try server.middleware(ziggurat.session_middleware.sessionMiddleware);
    try server.middleware(ziggurat.security.headers.securityMiddleware);

    try ziggurat.log.info("Server running on http://127.0.0.1:3000", .{});
    try server.start();
}

// NEW API: Handlers use the new Response builder methods
fn handleRoot(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.response.Response.json("{\"status\":\"ok\"}");
}

fn handleGetUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    const user_id = request.getParam("id") orelse {
        return ziggurat.response.Response.errorResponse(.bad_request, "Missing user id");
    };

    var buffer: [256]u8 = undefined;
    const response_str = std.fmt.bufPrint(&buffer, "{{\"user_id\":\"{s}\"}}", .{user_id}) catch |err| {
        _ = err;
        return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format response");
    };

    const response_copy = std.heap.page_allocator.dupe(u8, response_str) catch |err| {
        _ = err;
        return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate memory");
    };

    return ziggurat.response.Response.json(response_copy)
        .withStatus(.ok);
}

fn handleCreateUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    if (request.headers.get("Content-Type")) |ct| {
        if (!std.mem.eql(u8, ct, "application/json")) {
            return ziggurat.response.Response.errorResponse(.unsupported_media_type, "Only application/json is supported");
        }
    } else {
        return ziggurat.response.Response.errorResponse(.bad_request, "Missing Content-Type header");
    }

    // Parse body and create user...
    return ziggurat.response.Response.json("{\"id\":1,\"name\":\"New User\",\"created\":true}")
        .withStatus(.created);
}
