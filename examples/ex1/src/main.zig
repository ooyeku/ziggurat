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

var todos = std.ArrayList(Todo).init(std.heap.page_allocator);
var next_id: u32 = 1;

pub fn main() !void {
    // Initialize the server
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize the logger
    try ziggurat.logging.initGlobalLogger(allocator);
    const logger = ziggurat.logging.getGlobalLogger().?;

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(3000)
        .readTimeout(5000)
        .writeTimeout(5000)
        .build();
    defer server.deinit();

    // Add middleware for logging
    try server.middleware(logRequests);

    // Add routes
    try server.get("/todos", handleListTodos);
    try server.post("/todos", handleCreateTodo);
    try server.get("/todos/:id", handleGetTodo);
    try server.delete("/todos/:id", handleDeleteTodo);

    try logger.info("Todo API server running at http://127.0.0.1:3000", .{});
    try server.start();
}

fn logRequests(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (ziggurat.logging.getGlobalLogger()) |logger| {
        logger.info("[{s}] {s}", .{ @tagName(request.method), request.path }) catch {};
    }
    return null;
}

fn handleListTodos(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    var json_str = std.ArrayList(u8).init(std.heap.page_allocator);
    defer json_str.deinit();

    json_str.appendSlice("[") catch return ziggurat.errorResponse(
        ziggurat.Status.internal_server_error,
        "Failed to generate response",
    );

    for (todos.items, 0..) |todo, i| {
        const comma = if (i == todos.items.len - 1) "" else ",";
        std.fmt.format(json_str.writer(),
            \\{{"id": {d}, "title": "{s}", "completed": {}}}{s}
        , .{ todo.id, todo.title, todo.completed, comma }) catch return ziggurat.errorResponse(
            ziggurat.Status.internal_server_error,
            "Failed to generate response",
        );
    }

    json_str.appendSlice("]") catch return ziggurat.errorResponse(
        ziggurat.Status.internal_server_error,
        "Failed to generate response",
    );

    return ziggurat.json(json_str.items);
}

fn handleCreateTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    if (request.headers.get("Content-Type")) |content_type| {
        if (!std.mem.eql(u8, content_type, "application/json")) {
            return ziggurat.errorResponse(
                ziggurat.Status.unsupported_media_type,
                "Only application/json is supported",
            );
        }
    }

    const todo = Todo{
        .id = next_id,
        .title = "New Todo", // In a real app, parse this from request body
        .completed = false,
    };
    next_id += 1;

    todos.append(todo) catch return ziggurat.errorResponse(
        ziggurat.Status.internal_server_error,
        "Failed to create todo",
    );

    var json_str = std.ArrayList(u8).init(std.heap.page_allocator);
    defer json_str.deinit();

    std.fmt.format(json_str.writer(),
        \\{{"id": {d}, "title": "{s}", "completed": {}, "message": "Todo created successfully"}}
    , .{ todo.id, todo.title, todo.completed }) catch return ziggurat.errorResponse(
        ziggurat.Status.internal_server_error,
        "Failed to generate response",
    );

    return ziggurat.json(json_str.items);
}

fn handleGetTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    // In a real app, parse the ID from request.path and find the todo
    return ziggurat.json(
        \\{"id": 1, "title": "Example Todo", "completed": false}
    );
}

fn handleDeleteTodo(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    // In a real app, parse the ID from request.path and delete the todo
    return ziggurat.json(
        \\{"message": "Todo deleted successfully"}
    );
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // Try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
