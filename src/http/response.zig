const std = @import("std");
const testing = std.testing;

pub const StatusCode = enum(u16) {
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,
    moved_permanently = 301,
    found = 302,
    not_modified = 304,
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,
    request_timeout = 408,
    conflict = 409,
    payload_too_large = 413,
    unsupported_media_type = 415,
    unprocessable_entity = 422,
    too_many_requests = 429,
    request_header_fields_too_large = 431,
    internal_server_error = 500,
    service_unavailable = 503,

    pub fn toString(self: StatusCode) []const u8 {
        return switch (self) {
            .ok => "200 OK",
            .created => "201 Created",
            .accepted => "202 Accepted",
            .no_content => "204 No Content",
            .moved_permanently => "301 Moved Permanently",
            .found => "302 Found",
            .not_modified => "304 Not Modified",
            .bad_request => "400 Bad Request",
            .unauthorized => "401 Unauthorized",
            .forbidden => "403 Forbidden",
            .not_found => "404 Not Found",
            .method_not_allowed => "405 Method Not Allowed",
            .request_timeout => "408 Request Timeout",
            .conflict => "409 Conflict",
            .payload_too_large => "413 Payload Too Large",
            .unsupported_media_type => "415 Unsupported Media Type",
            .unprocessable_entity => "422 Unprocessable Entity",
            .too_many_requests => "429 Too Many Requests",
            .request_header_fields_too_large => "431 Request Header Fields Too Large",
            .internal_server_error => "500 Internal Server Error",
            .service_unavailable => "503 Service Unavailable",
        };
    }
};

pub const Response = struct {
    status: StatusCode,
    content_type: []const u8,
    body: []const u8,
    /// Optional extra headers sent after Content-Type/Content-Length.
    /// Each entry is a "Name: Value" string owned by the caller.
    extra_headers: []const []const u8 = &.{},

    pub fn init(status: StatusCode, content_type: []const u8, body: []const u8) Response {
        return .{
            .status = status,
            .content_type = content_type,
            .body = body,
        };
    }

    /// Create a JSON response
    pub fn json(body: []const u8) Response {
        return Response.init(.ok, "application/json", body);
    }

    /// Create a text response
    pub fn text(body: []const u8) Response {
        return Response.init(.ok, "text/plain", body);
    }

    /// Create an HTML response
    pub fn html(body: []const u8) Response {
        return Response.init(.ok, "text/html", body);
    }

    /// Create an error response
    pub fn errorResponse(status: StatusCode, message: []const u8) Response {
        return Response.init(status, "text/plain", message);
    }

    /// Set custom status code
    pub fn withStatus(self: Response, status: StatusCode) Response {
        var r = self;
        r.status = status;
        return r;
    }

    /// Set custom content type
    pub fn withContentType(self: Response, content_type: []const u8) Response {
        var r = self;
        r.content_type = content_type;
        return r;
    }

    /// Attach extra headers. Each entry must be a "Name: Value" string.
    pub fn withHeaders(self: Response, headers: []const []const u8) Response {
        var r = self;
        r.extra_headers = headers;
        return r;
    }

    /// Serialize the response to an HTTP/1.1 wire format string.
    /// The caller is responsible for freeing the returned slice using `allocator`.
    pub fn format(self: *const Response, allocator: std.mem.Allocator) ![]const u8 {
        // Build the extra headers block first so we know its length.
        var extra_buf: std.ArrayList(u8) = .{};
        defer extra_buf.deinit(allocator);
        for (self.extra_headers) |h| {
            try extra_buf.appendSlice(allocator, h);
            try extra_buf.appendSlice(allocator, "\r\n");
        }

        return std.fmt.allocPrint(
            allocator,
            "HTTP/1.1 {s}\r\nContent-Type: {s}\r\nContent-Length: {d}\r\n{s}\r\n{s}",
            .{
                self.status.toString(),
                self.content_type,
                self.body.len,
                extra_buf.items,
                self.body,
            },
        );
    }
};

test "format response" {
    const allocator = testing.allocator;
    const response = Response.init(.ok, "text/plain", "Hello, World!");
    const formatted = try response.format(allocator);
    defer allocator.free(formatted);
    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 13\r\n\r\nHello, World!",
        formatted,
    );
}

test "format response with body and content type" {
    const allocator = testing.allocator;
    const response = Response.init(.ok, "text/html", "Hello, World!");
    const formatted = try response.format(allocator);
    defer allocator.free(formatted);
    try testing.expectEqualStrings(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 13\r\n\r\nHello, World!",
        formatted,
    );
}

test "format response with extra headers" {
    const allocator = testing.allocator;
    const extra = [_][]const u8{
        "X-Custom: yes",
        "Cache-Control: no-cache",
    };
    const response = Response.init(.ok, "text/plain", "hi").withHeaders(&extra);
    const formatted = try response.format(allocator);
    defer allocator.free(formatted);
    try testing.expect(std.mem.indexOf(u8, formatted, "X-Custom: yes\r\n") != null);
    try testing.expect(std.mem.indexOf(u8, formatted, "Cache-Control: no-cache\r\n") != null);
}

test "missing status codes present" {
    try testing.expectEqualStrings("301 Moved Permanently", StatusCode.moved_permanently.toString());
    try testing.expectEqualStrings("302 Found", StatusCode.found.toString());
    try testing.expectEqualStrings("304 Not Modified", StatusCode.not_modified.toString());
    try testing.expectEqualStrings("422 Unprocessable Entity", StatusCode.unprocessable_entity.toString());
    try testing.expectEqualStrings("429 Too Many Requests", StatusCode.too_many_requests.toString());
    try testing.expectEqualStrings("503 Service Unavailable", StatusCode.service_unavailable.toString());
}
