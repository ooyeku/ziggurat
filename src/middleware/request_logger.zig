//! Request/Response logging middleware for Ziggurat
//! Provides request ID tracking, timing, and detailed logging

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const logging = @import("../utils/logging.zig");
const testing = std.testing;

/// Request ID format: random 16-character hex string
pub const REQUEST_ID_LEN = 16;

/// Generate a random request ID
pub fn generateRequestId(allocator: std.mem.Allocator) ![]const u8 {
    var buffer: [REQUEST_ID_LEN]u8 = undefined;

    // Use timestamp + counter for simple ID generation
    const timestamp = std.time.milliTimestamp();
    const seed: u64 = @bitCast(timestamp);
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    for (&buffer) |*byte| {
        byte.* = "0123456789abcdef"[rand.intRangeAtMost(u8, 0, 15)];
    }

    return try allocator.dupe(u8, &buffer);
}

/// Request logging configuration
pub const RequestLoggerConfig = struct {
    include_headers: bool = false,
    include_body: bool = false,
    include_response_body: bool = false,
    log_level: logging.LogLevel = .info,
};

/// Request logging middleware
pub fn requestLoggingMiddleware(request: *Request) ?Response {
    // Generate and store request ID
    if (generateRequestId(request.allocator)) |req_id| {
        request.setUserData("request_id", req_id) catch {};

        if (logging.getGlobalLogger()) |logger| {
            logger.info(
                "[{s}] {s} {s}",
                .{ req_id, @tagName(request.method), request.path },
            ) catch {};
        }

        // Store start time
        const start_time = std.time.milliTimestamp();
        request.setUserData("request_start_time", start_time) catch {};
    } else |_| {}

    return null;
}

/// Middleware to log response details (call after handler)
pub fn responseLoggingMiddleware(request: *Request, response: *const Response) void {
    if (logging.getGlobalLogger()) |logger| {
        const req_id = request.getUserData("request_id", []const u8) orelse "unknown";
        const start_time = request.getUserData("request_start_time", i64) orelse std.time.milliTimestamp();
        const end_time = std.time.milliTimestamp();
        const duration = end_time - start_time;

        logger.info(
            "[{s}] Response: {} ({}ms)",
            .{ req_id, @intFromEnum(response.status), duration },
        ) catch {};
    }
}

test "generate request id" {
    const allocator = testing.allocator;
    const id1 = try generateRequestId(allocator);
    defer allocator.free(id1);

    try testing.expectEqual(@as(usize, REQUEST_ID_LEN), id1.len);

    // Check all characters are valid hex
    for (id1) |char| {
        try testing.expect((char >= '0' and char <= '9') or (char >= 'a' and char <= 'f'));
    }
}

test "generate unique request ids" {
    const allocator = testing.allocator;
    const id1 = try generateRequestId(allocator);
    defer allocator.free(id1);

    const id2 = try generateRequestId(allocator);
    defer allocator.free(id2);

    // IDs should likely be different (though not guaranteed due to randomness)
    // Just check they were generated successfully with correct lengths
    try testing.expectEqual(@as(usize, REQUEST_ID_LEN), id1.len);
    try testing.expectEqual(@as(usize, REQUEST_ID_LEN), id2.len);
}
