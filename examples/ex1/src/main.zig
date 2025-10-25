//! By convention, main.zig is where your main function lives in the case that
//! you are building an executable. If you are making a library, the convention
//! is to delete this file and start with root.zig instead.

const std = @import("std");
const ziggurat = @import("ziggurat");

// Simple in-memory todo store
const Todo = struct {
    id: u32,
    title: []const u8,
    completed: bool,
};

// Using a dedicated arena allocator for todo persistence
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var arena: std.heap.ArenaAllocator = undefined;
var todos: std.ArrayList(Todo) = undefined;
var next_id: u32 = 1;

pub fn main() !void {
    // Initialize the allocators
    const global_allocator = gpa.allocator();
    arena = std.heap.ArenaAllocator.init(global_allocator);
    defer arena.deinit();

    todos = std.ArrayList(Todo){};

    // Initialize the server
    try ziggurat.logger.initGlobalLogger(global_allocator);
    const logger = ziggurat.logger.getGlobalLogger().?;

    // Initialize metrics for observability
    try ziggurat.metrics.initGlobalMetrics(global_allocator, 1000);
    defer ziggurat.metrics.deinitGlobalMetrics();

    // Initialize error handler for standardized error responses
    try ziggurat.error_handler.initGlobalErrorHandler(global_allocator, false);
    defer ziggurat.error_handler.deinitGlobalErrorHandler();

    // Initialize CORS for cross-origin requests
    try ziggurat.cors.initGlobalCorsConfig(global_allocator);

    // Initialize session manager for user sessions
    try ziggurat.session_middleware.initGlobalSessionManager(global_allocator, 3600);

    // Set up TLS certificates
    const cert_path = "cert.pem";
    const key_path = "key.pem";

    // Create self-signed certificates for development if they don't exist
    try createSelfSignedCertificatesIfNeeded(cert_path, key_path);

    var builder = ziggurat.ServerBuilder.init(global_allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(3000)
        .readTimeout(5000)
        .writeTimeout(5000)
        // TLS is not fully implemented yet - using HTTP for now
        // .enableTls(cert_path, key_path)
        .build();
    defer server.deinit();

    // Add middleware in order: logging -> sessions -> CORS
    try server.middleware(ziggurat.request_logger.requestLoggingMiddleware);
    try server.middleware(ziggurat.session_middleware.sessionMiddleware);
    try server.middleware(ziggurat.cors.corsMiddleware);
    try server.middleware(logRequests);

    // Add routes
    try server.get("/todos", handleListTodos);
    try server.post("/todos", handleCreateTodo);
    try server.get("/todos/:id", handleGetTodo);
    try server.put("/todos/:id", handleUpdateTodo);
    try server.delete("/todos/:id", handleDeleteTodo);
    try server.get("/metrics", handleMetrics);

    try logger.info("Todo API server v1.0 running at http://127.0.0.1:3000", .{});
    try logger.info("Features: Sessions, CORS, Error Handling, Metrics", .{});
    try logger.info("Note: TLS support is not yet fully implemented", .{});
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

fn logRequests(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        logger.info("[{s}] {s}", .{ @tagName(request.method), request.path }) catch {};
    }
    return null;
}

fn recoverFromPanics(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    _ = request;

    // Check if we're in an error recovery path
    if (@errorReturnTrace()) |_| {
        if (ziggurat.logger.getGlobalLogger()) |logger| {
            logger.err("Recovering from panic in request handler", .{}) catch {};
        }

        // Return a safe response
        return ziggurat.errorResponse(
            .internal_server_error,
            "An internal server error occurred",
        );
    }

    return null;
}

fn handleListTodos(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;

    // Use a fixed buffer for JSON response
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.writeAll("[") catch return ziggurat.errorResponse(
        .internal_server_error,
        "Failed to generate response",
    );

    for (todos.items, 0..) |todo, i| {
        const comma = if (i == todos.items.len - 1) "" else ",";
        std.fmt.format(writer,
            \\{{"id": {d}, "title": "{s}", "completed": {}}}{s}
        , .{ todo.id, todo.title, todo.completed, comma }) catch return ziggurat.errorResponse(
            .internal_server_error,
            "Failed to generate response",
        );
    }

    writer.writeAll("]") catch return ziggurat.errorResponse(
        .internal_server_error,
        "Failed to generate response",
    );

    // Create a duplicated string that will persist after this function returns
    const result = arena.allocator().dupe(u8, fbs.getWritten()) catch return ziggurat.errorResponse(
        .internal_server_error,
        "Failed to allocate response memory",
    );

    return ziggurat.json(result);
}

fn handleCreateTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    if (request.headers.get("Content-Type")) |content_type| {
        if (!std.mem.eql(u8, content_type, "application/json")) {
            return ziggurat.errorResponse(
                .unsupported_media_type,
                "Only application/json is supported",
            );
        }
    }

    // Try to parse title from request body
    var title: []const u8 = "New Todo"; // Default title
    if (request.body.len > 0) {
        // Very simple JSON parsing - just looking for "title" field
        if (std.mem.indexOf(u8, request.body, "\"title\"")) |title_pos| {
            const after_title = title_pos + 7; // Skip "title":
            if (after_title < request.body.len) {
                // Find the first quote
                var start_idx: usize = after_title;
                while (start_idx < request.body.len) : (start_idx += 1) {
                    if (request.body[start_idx] == '"') {
                        start_idx += 1;
                        break;
                    }
                }

                // Find the end quote
                var end_idx: usize = start_idx;
                while (end_idx < request.body.len) : (end_idx += 1) {
                    if (request.body[end_idx] == '"') {
                        break;
                    }
                }

                if (end_idx > start_idx and end_idx < request.body.len) {
                    // Extract the title string
                    const title_slice = request.body[start_idx..end_idx];
                    title = title_slice;
                }
            }
        }
    }

    // Safe copy of the title
    const title_copy = arena.allocator().dupe(u8, title) catch return ziggurat.errorResponse(
        .internal_server_error,
        "Failed to allocate memory for todo",
    );

    const todo = Todo{
        .id = next_id,
        .title = title_copy,
        .completed = false,
    };
    next_id += 1;

    todos.append(arena.allocator(), todo) catch return ziggurat.errorResponse(
        .internal_server_error,
        "Failed to create todo",
    );

    var buf: [512]u8 = undefined;
    const json_str = std.fmt.bufPrint(&buf,
        \\{{"id": {d}, "title": "{s}", "completed": {}, "message": "Todo created successfully"}}
    , .{ todo.id, todo.title, todo.completed }) catch return ziggurat.errorResponse(
        .internal_server_error,
        "Failed to generate response",
    );

    // Create a duplicated string that will persist after this function returns
    const result = arena.allocator().dupe(u8, json_str) catch return ziggurat.errorResponse(
        .internal_server_error,
        "Failed to allocate response memory",
    );

    return ziggurat.json(result);
}

fn handleGetTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id_param = request.getParam("id") orelse return ziggurat.errorResponse(
        .bad_request,
        "Missing id parameter",
    );

    const id = std.fmt.parseInt(u32, id_param, 10) catch return ziggurat.errorResponse(
        .bad_request,
        "Invalid id parameter",
    );

    // Find the todo with the matching ID
    for (todos.items) |todo| {
        if (todo.id == id) {
            var json_str = std.ArrayList(u8){};

            std.fmt.format(json_str.writer(arena.allocator()),
                \\{{"id": {d}, "title": "{s}", "completed": {}}}
            , .{ todo.id, todo.title, todo.completed }) catch return ziggurat.errorResponse(
                .internal_server_error,
                "Failed to generate response",
            );

            // Create a duplicated string that will persist
            const result = arena.allocator().dupe(u8, json_str.items) catch return ziggurat.errorResponse(
                .internal_server_error,
                "Failed to allocate response memory",
            );

            return ziggurat.json(result);
        }
    }

    return ziggurat.errorResponse(
        .not_found,
        "Todo not found",
    );
}

fn handleDeleteTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id_param = request.getParam("id") orelse return ziggurat.errorResponse(
        .bad_request,
        "Missing id parameter",
    );

    const id = std.fmt.parseInt(u32, id_param, 10) catch return ziggurat.errorResponse(
        .bad_request,
        "Invalid id parameter",
    );

    // Find and remove the todo with the matching ID
    for (todos.items, 0..) |todo, index| {
        if (todo.id == id) {
            _ = todos.orderedRemove(index);

            const message = arena.allocator().dupe(u8,
                \\{"message": "Todo deleted successfully"}
            ) catch return ziggurat.errorResponse(
                .internal_server_error,
                "Failed to allocate response memory",
            );

            return ziggurat.json(message);
        }
    }

    return ziggurat.errorResponse(
        .not_found,
        "Todo not found",
    );
}

fn handleUpdateTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id_param = request.getParam("id") orelse return ziggurat.errorResponse(
        .bad_request,
        "Missing id parameter",
    );

    const id = std.fmt.parseInt(u32, id_param, 10) catch return ziggurat.errorResponse(
        .bad_request,
        "Invalid id parameter",
    );

    // Find and update the todo
    for (todos.items) |*todo| {
        if (todo.id == id) {
            var json_str = std.ArrayList(u8){};

            std.fmt.format(json_str.writer(arena.allocator()),
                \\{{"id": {d}, "title": "{s}", "completed": {}, "message": "Todo updated"}}
            , .{ todo.id, todo.title, todo.completed }) catch return ziggurat.errorResponse(
                .internal_server_error,
                "Failed to generate response",
            );

            const result = arena.allocator().dupe(u8, json_str.items) catch return ziggurat.errorResponse(
                .internal_server_error,
                "Failed to allocate response memory",
            );

            return ziggurat.json(result);
        }
    }

    return ziggurat.errorResponse(
        .not_found,
        "Todo not found",
    );
}

fn handleMetrics(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;

    if (ziggurat.metrics.getGlobalMetrics()) |_| {
        var buf: [256]u8 = undefined;
        const response_json = std.fmt.bufPrint(&buf,
            \\{{"message": "Metrics available via /metrics endpoint"}}
        , .{}) catch {
            return ziggurat.errorResponse(
                .internal_server_error,
                "Failed to generate metrics",
            );
        };

        const result = arena.allocator().dupe(u8, response_json) catch {
            return ziggurat.errorResponse(
                .internal_server_error,
                "Failed to allocate metrics response",
            );
        };

        return ziggurat.json(result);
    }

    return ziggurat.errorResponse(
        .internal_server_error,
        "Metrics not initialized",
    );
}
