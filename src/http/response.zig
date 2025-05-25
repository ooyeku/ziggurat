const std = @import("std");
const testing = std.testing;

pub const StatusCode = enum(u16) {
    ok = 200,
    bad_request = 400,
    not_found = 404,
    method_not_allowed = 405,
    request_timeout = 408,
    payload_too_large = 413,
    request_header_fields_too_large = 431,
    unsupported_media_type = 415,
    internal_server_error = 500,

    pub fn toString(self: StatusCode) []const u8 {
        return switch (self) {
            .ok => "200 OK",
            .bad_request => "400 Bad Request",
            .not_found => "404 Not Found",
            .method_not_allowed => "405 Method Not Allowed",
            .request_timeout => "408 Request Timeout",
            .payload_too_large => "413 Payload Too Large",
            .request_header_fields_too_large => "431 Request Header Fields Too Large",
            .unsupported_media_type => "415 Unsupported Media Type",
            .internal_server_error => "500 Internal Server Error",
        };
    }
};

pub const Response = struct {
    status: StatusCode,
    content_type: []const u8,
    body: []const u8,

    pub fn init(status: StatusCode, content_type: []const u8, body: []const u8) Response {
        return .{
            .status = status,
            .content_type = content_type,
            .body = body,
        };
    }

    pub fn format(self: *const Response, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(
            allocator,
            "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n\r\n{s}",
            .{
                self.status.toString(),
                self.content_type,
                self.body.len,
                self.body,
            }
        );
    }
};


test "format response" {    
    var response = Response.init(.ok, "text/plain", "Hello, World!");

    const formatted = try response.format(testing.allocator);
    defer testing.allocator.free(formatted);
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!", formatted);
}

test "format response with body" {    
    var response = Response.init(.ok, "text/plain", "Hello, World!");

    const formatted = try response.format(testing.allocator);
    defer testing.allocator.free(formatted);
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!", formatted);
}

test "format response with body and content type" {    
    var response = Response.init(.ok, "text/html", "Hello, World!");

    const formatted = try response.format(testing.allocator);
    defer testing.allocator.free(formatted);
    try testing.expectEqualStrings("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\nHello, World!", formatted);
}