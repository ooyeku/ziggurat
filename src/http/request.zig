const std = @import("std");

pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    OPTIONS,
    HEAD,
    PATCH,
    UNKNOWN,

    pub fn fromString(str: []const u8) Method {
        if (std.mem.eql(u8, str, "GET")) return .GET;
        if (std.mem.eql(u8, str, "POST")) return .POST;
        if (std.mem.eql(u8, str, "PUT")) return .PUT;
        if (std.mem.eql(u8, str, "DELETE")) return .DELETE;
        if (std.mem.eql(u8, str, "OPTIONS")) return .OPTIONS;
        if (std.mem.eql(u8, str, "HEAD")) return .HEAD;
        if (std.mem.eql(u8, str, "PATCH")) return .PATCH;
        return .UNKNOWN;
    }
};

pub const Request = struct {
    method: Method,
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,
    user_data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Request {
        return .{
            .method = .UNKNOWN,
            .path = "",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .allocator = allocator,
            .user_data = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Request) void {
        // Free path if it was allocated
        if (self.path.len > 0) {
            self.allocator.free(self.path);
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
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
    }
    // Set user data for request - used for middleware
    pub fn setUserData(self: *Request, key: []const u8, value: anytype) !void {
        const key_owned = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_owned);

        // Convert value to string if it's not already a string
        const value_str = switch (@TypeOf(value)) {
            []const u8 => try self.allocator.dupe(u8, value),
            else => blk: {
                var buf: [256]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "{any}", .{value});
                break :blk try self.allocator.dupe(u8, str);
            },
        };
        errdefer self.allocator.free(value_str);

        // Remove old value if it exists
        if (self.user_data.get(key)) |old_value| {
            self.allocator.free(old_value);
        }

        try self.user_data.put(key_owned, value_str);
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
        if (std.mem.indexOf(u8, self.path, "?")) |query_start| {
            const query_string = self.path[query_start + 1 ..];
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

        return null;
    }

    // Parse raw HTTP request
    pub fn parse(self: *Request, raw_request: []const u8) !void {
        var lines = std.mem.splitSequence(u8, raw_request, "\r\n");

        // Parse request line
        if (lines.next()) |request_line| {
            var parts = std.mem.splitScalar(u8, request_line, ' ');
            if (parts.next()) |method| {
                self.method = Method.fromString(method);
            }
            if (parts.next()) |path| {
                self.path = try self.allocator.dupe(u8, path);
            }
        }

        // Parse headers
        while (lines.next()) |line| {
            if (line.len == 0) break;
            if (std.mem.indexOf(u8, line, ": ")) |separator| {
                const key = try self.allocator.dupe(u8, line[0..separator]);
                const value = try self.allocator.dupe(u8, line[separator + 2 ..]);
                try self.headers.put(key, value);
            }
        }

        // The rest is body
        if (lines.next()) |body| {
            self.body = try self.allocator.dupe(u8, body);
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
    try testing.expectEqualStrings("/test", request.path);
}

test "parse request with headers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost:8080\r\nContent-Type: application/json\r\n\r\n";
    try request.parse(raw_request);

    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/test", request.path);
    try testing.expectEqualStrings("application/json", request.headers.get("Content-Type") orelse "");
}

test "parse request with body" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw_request = "GET /test HTTP/1.1\r\nHost: localhost:8080\r\nContent-Type: application/json\r\n\r\n{\"name\": \"John\"}";
    try request.parse(raw_request);

    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/test", request.path);
    try testing.expectEqualStrings("application/json", request.headers.get("Content-Type") orelse "");
    try testing.expectEqualStrings("{\"name\": \"John\"}", request.body);
}

test "parse request with multi-line body" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw_request = "POST /api/todos HTTP/1.1\r\nHost: localhost:8080\r\nContent-Type: application/json\r\nContent-Length: 57\r\n\r\n{\"title\":\"test\",\"description\":\"multi\nline\",\"priority\":\"high\"}";
    try request.parse(raw_request);

    try testing.expectEqual(Method.POST, request.method);
    try testing.expectEqualStrings("/api/todos", request.path);
    try testing.expectEqualStrings("application/json", request.headers.get("Content-Type") orelse "");
    try testing.expectEqualStrings("{\"title\":\"test\",\"description\":\"multi\nline\",\"priority\":\"high\"}", request.body);
}
