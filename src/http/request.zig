const std = @import("std");

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    UNKNOWN,

    pub fn fromString(str: []const u8) Method {
        if (std.mem.eql(u8, str, "GET")) return .GET;
        if (std.mem.eql(u8, str, "POST")) return .POST;
        if (std.mem.eql(u8, str, "PUT")) return .PUT;
        if (std.mem.eql(u8, str, "DELETE")) return .DELETE;
        return .UNKNOWN;
    }
};

pub const Request = struct {
    method: Method,
    path: ?[]const u8 = null,
    headers: std.StringHashMap([]const u8),
    body: ?[]const u8 = null,
    allocator: std.mem.Allocator,
    user_data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Request {
        return .{
            .method = .UNKNOWN,
            .path = null,
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = null,
            .allocator = allocator,
            .user_data = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Request) void {
        // Free path if it was allocated
        if (self.path) |p| {
            self.allocator.free(p);
        }

        // Free headers
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();

        // Free user data
        var user_it = self.user_data.iterator();
        while (user_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.user_data.deinit();

        // Free body if it was allocated
        if (self.body) |b| {
            self.allocator.free(b);
        }
    }

    // Set user data for request - used for middleware
    pub fn setUserData(self: *Request, key: []const u8, value: anytype) !void {
        var key_owned = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_owned); // Freed if subsequent operations fail

        var value_str_owned = switch (@TypeOf(value)) {
            []const u8 => try self.allocator.dupe(u8, value),
            else => blk: {
                // Max buffer size for stringifying anytype, adjust if necessary
                var buf: [1024]u8 = undefined; 
                const str_slice = try std.fmt.bufPrint(&buf, "{any}", .{value});
                break :blk try self.allocator.dupe(u8, str_slice);
            },
        };
        errdefer self.allocator.free(value_str_owned); // Freed if put() fails

        // self.user_data.put will take ownership of key_owned and value_str_owned.
        // If an old entry was replaced, put() handles freeing it internally.
        try self.user_data.put(key_owned, value_str_owned);

        // If put() succeeded, key_owned and value_str_owned are now owned by the map.
        // The errdefers for them are disarmed by the successful completion of this block.
        // To be absolutely explicit about transfer of ownership and disarming errdefer:
        key_owned = undefined;
        value_str_owned = undefined;
    }

    pub fn getUserData(self: *Request, key: []const u8, comptime T: type) ?T {
        if (self.user_data.get(key)) |value| {
            // If T is a string slice, return it directly
            if (T == []const u8) {
                return value;
            }
            // Otherwise try to parse it
            if (std.fmt.parseFloat(f64, value)) |float| {
                return @intFromFloat(float);
            } else |_| {}
            if (std.fmt.parseInt(T, value, 10)) |int| {
                return int;
            } else |_| {}
            return null;
        }
        return null;
    }

    // Get a URL parameter (from path params like /users/:id)
    pub fn getParam(self: *Request, key: []const u8) ?[]const u8 {
        return self.user_data.get(key);
    }

    // Get a query parameter (from URL query string like ?page=1)
    pub fn getQuery(self: *Request, key: []const u8) ?[]const u8 {
        // Find the query string portion
        if (self.path) |path| {
            if (std.mem.indexOf(u8, path, "?")) |query_start| {
                const query_string = path[query_start + 1 ..];
                var pairs = std.mem.splitScalar(u8, query_string, '&');

                while (pairs.next()) |pair| {
                    var kv = std.mem.splitScalar(u8, pair, '=');
                    if (kv.next()) |k| {
                        if (std.mem.eql(u8, k, key)) {
                            if (kv.next()) |v| {
                                return v;
                            }
                            return "";
                        }
                    }
                }
            }
        }

        return null;
    }

    // Parse raw HTTP request
    pub fn parse(self: *Request, raw_request: []const u8) !void {
        var lines = std.mem.splitSequence(u8, raw_request, "\r\n");

        // Parse request line
        if (lines.next()) |request_line| {
            var parts = std.mem.splitScalar(u8, request_line, ' ');
            if (parts.next()) |method_str| {
                self.method = Method.fromString(method_str);
            } else {
                return error.InvalidRequestLine;
            }
            if (parts.next()) |path_str| {
                self.path = try self.allocator.dupe(u8, path_str);
            } else {
                return error.InvalidRequestLine;
            }
            // Ignoring HTTP version part for now
        } else {
            return error.InvalidRequestLine;
        }

        // Parse headers
        var body_start_index: usize = 0;
        const line_ptr = lines.peek() orelse ""; // For calculating body_start_index before first iteration
        if (line_ptr.len > 0) { // Ensure there are header lines to process
             body_start_index = @intFromPtr(line_ptr.ptr) - @intFromPtr(raw_request.ptr);
        } else { // No headers, body starts immediately after request line if it exists
            // This case needs careful handling of body_start_index based on request_line's end
            // For now, assuming request_line + \r\n, then potentially empty line for headers, then body
            // The loop below correctly finds the empty line or end of headers.
        }

        while (lines.next()) |line| {
            // body_start_index should point to the start of the line *after* the current line's \r\n
            body_start_index = (@intFromPtr(line.ptr) - @intFromPtr(raw_request.ptr)) + line.len + 2; // +2 for \r\n

            if (line.len == 0) break; // Empty line indicates end of headers

            if (std.mem.indexOf(u8, line, ": ")) |separator| {
                const key_slice = line[0..separator];
                const value_slice = line[separator + 2 ..];
                
                var temp_key = try self.allocator.dupe(u8, key_slice);
                errdefer self.allocator.free(temp_key);

                var temp_value = try self.allocator.dupe(u8, value_slice);
                errdefer self.allocator.free(temp_value);

                try self.headers.put(temp_key, temp_value);

                // Disarm errdefers for temp_key and temp_value as put succeeded
                _ = &temp_key;
                _ = &temp_value;
            } else {
                // Malformed header line
                return error.InvalidHeaderFormat;
            }
        }

        // The rest is body, if any content exists after headers
        if (body_start_index < raw_request.len) {
            self.body = try self.allocator.dupe(u8, raw_request[body_start_index..]);
        } else {
            self.body = null; // No body content or empty body
        }
    }
};

test "parse request" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost:8080\r\n\r\n";
    try request.parse(raw_request);

    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/test", request.path orelse "");
}

test "parse request with headers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost:8080\r\nContent-Type: application/json\r\n\r\n";
    try request.parse(raw_request);

    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/test", request.path orelse "");
    try testing.expectEqualStrings("application/json", request.headers.get("Content-Type") orelse "");
}

test "parse request with body" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw_request_body = "GET /test HTTP/1.1\r\nHost: localhost:8080\r\nContent-Length: 10\r\n\r\n{\"key\":\"val\"}";
    try request.parse(raw_request_body);

    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/test", request.path orelse "");
    try testing.expectEqualStrings("{\"key\":\"val\"}", request.body orelse "");
}

test "parse request no body" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw_request_no_body = "GET /test HTTP/1.1\r\nHost: localhost:8080\r\n\r\n";
    try request.parse(raw_request_no_body);

    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/test", request.path orelse "");
    try testing.expectEqual(null, request.body);
}

test "parse request with path and query" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw_request_query = "GET /path?query=value HTTP/1.1\r\nHost: localhost:8080\r\n\r\n";
    try request.parse(raw_request_query);
    try testing.expectEqualStrings("/path?query=value", request.path orelse "");
    const query_val = request.getQuery("query");
    try testing.expectEqualStrings("value", query_val orelse "");
}
