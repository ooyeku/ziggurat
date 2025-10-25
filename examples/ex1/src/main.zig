//! Todo API example using the NEW Ziggurat API
//! Demonstrates cleaner, more intuitive API design

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

    todos = .{};

    // NEW API: Initialize all features in one place
    try ziggurat.features.initialize(global_allocator, .{
        .logging = .{ .level = .info, .colors = true },
        .metrics = .{ .max_requests = 1000 },
        .errors = .{ .debug = false },
        .cors = .{},
        .session = .{ .ttl_seconds = 3600 },
    });
    defer ziggurat.features.deinitialize();

    // NEW API: Use simplified logging
    var builder = ziggurat.ServerBuilder.init(global_allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(3000)
        .build();
    defer server.deinit();

    // Add middleware in order: logging -> sessions -> CORS -> security
    try server.middleware(ziggurat.request_logger.requestLoggingMiddleware);
    try server.middleware(ziggurat.session_middleware.sessionMiddleware);
    try server.middleware(ziggurat.cors.corsMiddleware);

    // Add routes
    try server.get("/todos", handleListTodos);
    try server.post("/todos", handleCreateTodo);
    try server.get("/todos/:id", handleGetTodo);
    try server.put("/todos/:id", handleUpdateTodo);
    try server.delete("/todos/:id", handleDeleteTodo);
    try server.get("/metrics", handleMetrics);

    // NEW API: Use simplified logging
    try ziggurat.log.info("Todo API server v2.0 running at http://127.0.0.1:3000", .{});
    try ziggurat.log.info("Features: Sessions, CORS, Metrics, Rate Limiting, Security Headers", .{});
    try server.start();
}

fn handleListTodos(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;

    // Use a fixed buffer for JSON response
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    writer.writeAll("[") catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to generate response");

    for (todos.items, 0..) |todo, i| {
        const comma = if (i == todos.items.len - 1) "" else ",";
        std.fmt.format(writer,
            \\{{"id": {d}, "title": "{s}", "completed": {}}}{s}
        , .{ todo.id, todo.title, todo.completed, comma }) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to generate response");
    }

    writer.writeAll("]") catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to generate response");

    // Create a duplicated string that will persist after this function returns
    const result = arena.allocator().dupe(u8, fbs.getWritten()) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate response memory");

    // NEW API: Use Response builder
    return ziggurat.response.Response.json(result);
}

fn handleCreateTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    if (request.headers.get("Content-Type")) |content_type| {
        if (!std.mem.eql(u8, content_type, "application/json")) {
            return ziggurat.response.Response.errorResponse(.unsupported_media_type, "Only application/json is supported");
        }
    }

    // Try to parse title from request body
    var title: []const u8 = "New Todo";
    if (request.body.len > 0) {
        if (std.mem.indexOf(u8, request.body, "\"title\"")) |title_pos| {
            const after_title = title_pos + 7;
            if (after_title < request.body.len) {
                var start_idx: usize = after_title;
                while (start_idx < request.body.len) : (start_idx += 1) {
                    if (request.body[start_idx] == '"') {
                        start_idx += 1;
                        break;
                    }
                }

                var end_idx: usize = start_idx;
                while (end_idx < request.body.len) : (end_idx += 1) {
                    if (request.body[end_idx] == '"') {
                        break;
                    }
                }

                if (end_idx > start_idx and end_idx < request.body.len) {
                    const title_slice = request.body[start_idx..end_idx];
                    title = title_slice;
                }
            }
        }
    }

    const title_copy = arena.allocator().dupe(u8, title) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate memory for todo");

    const new_todo = Todo{
        .id = next_id,
        .title = title_copy,
        .completed = false,
    };

    todos.append(arena.allocator(), new_todo) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to add todo");
    next_id += 1;

    var buf: [256]u8 = undefined;
    const response_str = std.fmt.bufPrint(&buf, "{{\"id\":{d},\"title\":\"{s}\",\"completed\":false}}", .{ new_todo.id, new_todo.title }) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format response");
    const response_copy = arena.allocator().dupe(u8, response_str) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate response memory");

    return ziggurat.response.Response.json(response_copy).withStatus(.created);
}

fn handleGetTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id_str = request.getParam("id") orelse return ziggurat.response.Response.errorResponse(.bad_request, "Missing id parameter");

    const id = std.fmt.parseInt(u32, id_str, 10) catch return ziggurat.response.Response.errorResponse(.bad_request, "Invalid id format");

    for (todos.items) |todo| {
        if (todo.id == id) {
            var buf: [256]u8 = undefined;
            const response_str = std.fmt.bufPrint(&buf, "{{\"id\":{d},\"title\":\"{s}\",\"completed\":{}}}", .{ todo.id, todo.title, todo.completed }) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format response");
            const response_copy = arena.allocator().dupe(u8, response_str) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate response memory");
            return ziggurat.response.Response.json(response_copy);
        }
    }

    return ziggurat.response.Response.errorResponse(.not_found, "Todo not found");
}

fn handleUpdateTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id_str = request.getParam("id") orelse return ziggurat.response.Response.errorResponse(.bad_request, "Missing id parameter");

    const id = std.fmt.parseInt(u32, id_str, 10) catch return ziggurat.response.Response.errorResponse(.bad_request, "Invalid id format");

    for (todos.items) |*todo| {
        if (todo.id == id) {
            // Parse completed status from body
            if (request.body.len > 0) {
                if (std.mem.indexOf(u8, request.body, "\"completed\"")) |completed_pos| {
                    const after_completed = completed_pos + 11;
                    var colon_idx = after_completed;
                    while (colon_idx < request.body.len and request.body[colon_idx] != ':') : (colon_idx += 1) {}
                    colon_idx += 1;
                    while (colon_idx < request.body.len and (request.body[colon_idx] == ' ' or request.body[colon_idx] == '\t')) : (colon_idx += 1) {}

                    if (colon_idx < request.body.len) {
                        todo.completed = request.body[colon_idx] == 't';
                    }
                }
            }

            var buf: [256]u8 = undefined;
            const response_str = std.fmt.bufPrint(&buf, "{{\"id\":{d},\"title\":\"{s}\",\"completed\":{}}}", .{ todo.id, todo.title, todo.completed }) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format response");
            const response_copy = arena.allocator().dupe(u8, response_str) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate response memory");
            return ziggurat.response.Response.json(response_copy);
        }
    }

    return ziggurat.response.Response.errorResponse(.not_found, "Todo not found");
}

fn handleDeleteTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id_str = request.getParam("id") orelse return ziggurat.response.Response.errorResponse(.bad_request, "Missing id parameter");

    const id = std.fmt.parseInt(u32, id_str, 10) catch return ziggurat.response.Response.errorResponse(.bad_request, "Invalid id format");

    for (todos.items, 0..) |todo, i| {
        if (todo.id == id) {
            _ = todos.swapRemove(i);
            return ziggurat.response.Response.json("{\"deleted\":true}");
        }
    }

    return ziggurat.response.Response.errorResponse(.not_found, "Todo not found");
}

fn handleMetrics(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;

    if (ziggurat.metrics.getGlobalMetrics()) |manager| {
        var buf: [2048]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&buf);
        const writer = fbs.writer();

        writer.writeAll("{\"endpoints\":[") catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format metrics");

        const recent = manager.getRecentRequests();
        for (recent, 0..) |metric, i| {
            const comma = if (i == recent.len - 1) "" else ",";
            std.fmt.format(writer, "{{\"path\":\"{s}\",\"method\":\"{s}\",\"duration_ms\":{d},\"status\":{d}}}{s}", .{ metric.path, metric.method, metric.duration_ms, metric.status_code, comma }) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format metrics");
        }

        writer.writeAll("]}") catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to format metrics");

        const metrics_copy = arena.allocator().dupe(u8, fbs.getWritten()) catch return ziggurat.response.Response.errorResponse(.internal_server_error, "Failed to allocate metrics response");

        return ziggurat.response.Response.json(metrics_copy);
    }

    return ziggurat.response.Response.errorResponse(.internal_server_error, "Metrics not initialized");
}
