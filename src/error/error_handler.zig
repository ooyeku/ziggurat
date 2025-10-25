//! Error handling and recovery for Ziggurat
//! Provides standardized error responses and error recovery middleware

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const StatusCode = @import("../http/response.zig").StatusCode;
const testing = std.testing;

/// Standard error response format
pub const ErrorResponse = struct {
    status: u16,
    code: []const u8,
    message: []const u8,
    details: ?[]const u8 = null,

    /// Convert error response to JSON string
    pub fn toJson(self: ErrorResponse, allocator: std.mem.Allocator) ![]const u8 {
        var buffer: [512]u8 = undefined;

        var fbs = std.io.fixedBufferStream(&buffer);
        const writer = fbs.writer();

        try std.fmt.format(writer, "{{\"status\":{d},\"code\":\"{s}\",\"message\":\"{s}\"", .{ self.status, self.code, self.message });

        if (self.details) |details| {
            try std.fmt.format(writer, ", \"details\": \"{s}\"", .{details});
        }

        try writer.writeAll("}");

        return try allocator.dupe(u8, fbs.getWritten());
    }
};

/// Configuration for error handling behavior
pub const ErrorHandlerConfig = struct {
    debug_mode: bool = false,
    show_stack_traces: bool = false,
    custom_error_pages: std.StringHashMap([]const u8) = undefined,

    pub fn init(allocator: std.mem.Allocator) ErrorHandlerConfig {
        return .{
            .debug_mode = false,
            .show_stack_traces = false,
            .custom_error_pages = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *ErrorHandlerConfig) void {
        self.custom_error_pages.deinit();
    }

    pub fn setDebugMode(self: *ErrorHandlerConfig, debug: bool) void {
        self.debug_mode = debug;
        self.show_stack_traces = debug;
    }
};

/// Global error handler
var global_error_config: ?*ErrorHandlerConfig = null;

/// Initialize global error handler
pub fn initGlobalErrorHandler(allocator: std.mem.Allocator, debug_mode: bool) !void {
    if (global_error_config != null) return error.AlreadyInitialized;

    const config = try allocator.create(ErrorHandlerConfig);
    config.* = ErrorHandlerConfig.init(allocator);
    config.setDebugMode(debug_mode);

    global_error_config = config;
}

/// Get global error config
pub fn getGlobalErrorConfig() ?*ErrorHandlerConfig {
    return global_error_config;
}

/// Deinitialize global error handler
pub fn deinitGlobalErrorHandler() void {
    if (global_error_config) |config| {
        config.deinit();
    }
    global_error_config = null;
}

/// Create a standardized error response
pub fn createErrorResponse(allocator: std.mem.Allocator, status: StatusCode, code: []const u8, message: []const u8) !Response {
    const err_response = ErrorResponse{
        .status = @intFromEnum(status),
        .code = code,
        .message = message,
    };

    const json_body = try err_response.toJson(allocator);

    return Response.init(status, "application/json", json_body);
}

/// Error recovery middleware - catches errors and returns safe responses
pub fn errorRecoveryMiddleware(request: *Request) ?Response {
    _ = request;
    // In a real implementation, this would be part of the server's request handling
    // and would catch panics/errors from handlers
    return null;
}

/// Convert HTTP status code to error code string
pub fn statusCodeToErrorCode(status: StatusCode) []const u8 {
    return switch (status) {
        .bad_request => "BAD_REQUEST",
        .unauthorized => "UNAUTHORIZED",
        .forbidden => "FORBIDDEN",
        .not_found => "NOT_FOUND",
        .conflict => "CONFLICT",
        .payload_too_large => "PAYLOAD_TOO_LARGE",
        .unsupported_media_type => "UNSUPPORTED_MEDIA_TYPE",
        .request_timeout => "REQUEST_TIMEOUT",
        .method_not_allowed => "METHOD_NOT_ALLOWED",
        .request_header_fields_too_large => "HEADER_FIELDS_TOO_LARGE",
        .internal_server_error => "INTERNAL_SERVER_ERROR",
        else => "ERROR",
    };
}

test "create error response" {
    const allocator = testing.allocator;

    const error_resp = try createErrorResponse(
        allocator,
        .bad_request,
        "INVALID_INPUT",
        "The request body is invalid",
    );
    defer allocator.free(error_resp.body);

    try testing.expectEqual(@as(u16, 400), @intFromEnum(error_resp.status));
    try testing.expectEqualStrings("application/json", error_resp.content_type);
    try testing.expect(std.mem.indexOf(u8, error_resp.body, "INVALID_INPUT") != null);
}

test "error response to json" {
    const allocator = testing.allocator;

    const error_resp = ErrorResponse{
        .status = 404,
        .code = "NOT_FOUND",
        .message = "Resource not found",
    };

    const json = try error_resp.toJson(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "NOT_FOUND") != null);
    try testing.expect(std.mem.indexOf(u8, json, "404") != null);
}

test "error response to json with details" {
    const allocator = testing.allocator;

    const error_resp = ErrorResponse{
        .status = 400,
        .code = "VALIDATION_ERROR",
        .message = "Invalid input",
        .details = "Missing required field: email",
    };

    const json = try error_resp.toJson(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "VALIDATION_ERROR") != null);
    try testing.expect(std.mem.indexOf(u8, json, "400") != null);
    try testing.expect(std.mem.indexOf(u8, json, "Missing required field") != null);
}

test "error response to json without details" {
    const allocator = testing.allocator;

    const error_resp = ErrorResponse{
        .status = 404,
        .code = "NOT_FOUND",
        .message = "Resource not found",
    };

    const json = try error_resp.toJson(allocator);
    defer allocator.free(json);

    try testing.expect(std.mem.indexOf(u8, json, "NOT_FOUND") != null);
    try testing.expect(std.mem.indexOf(u8, json, "404") != null);
    try testing.expect(std.mem.indexOf(u8, json, "details") == null);
}

test "create error response with different status codes" {
    const allocator = testing.allocator;

    const responses = [_]StatusCode{ .bad_request, .unauthorized, .forbidden, .not_found, .internal_server_error };

    for (responses) |status| {
        const resp = try createErrorResponse(allocator, status, "TEST_ERROR", "Test message");
        defer allocator.free(resp.body);

        try testing.expectEqual(status, resp.status);
        try testing.expectEqualStrings("application/json", resp.content_type);
    }
}

test "status code to error code" {
    try testing.expectEqualStrings("BAD_REQUEST", statusCodeToErrorCode(.bad_request));
    try testing.expectEqualStrings("NOT_FOUND", statusCodeToErrorCode(.not_found));
    try testing.expectEqualStrings("UNAUTHORIZED", statusCodeToErrorCode(.unauthorized));
    try testing.expectEqualStrings("INTERNAL_SERVER_ERROR", statusCodeToErrorCode(.internal_server_error));
}

test "status code to error code mapping" {
    try testing.expectEqualStrings("BAD_REQUEST", statusCodeToErrorCode(.bad_request));
    try testing.expectEqualStrings("UNAUTHORIZED", statusCodeToErrorCode(.unauthorized));
    try testing.expectEqualStrings("FORBIDDEN", statusCodeToErrorCode(.forbidden));
    try testing.expectEqualStrings("NOT_FOUND", statusCodeToErrorCode(.not_found));
    try testing.expectEqualStrings("CONFLICT", statusCodeToErrorCode(.conflict));
    try testing.expectEqualStrings("PAYLOAD_TOO_LARGE", statusCodeToErrorCode(.payload_too_large));
    try testing.expectEqualStrings("INTERNAL_SERVER_ERROR", statusCodeToErrorCode(.internal_server_error));
}
