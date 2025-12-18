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
        const value_str = blk: {
            const type_name = @typeName(@TypeOf(value));

            // Check if it's a string type by looking for array or slice syntax
            if (comptime std.mem.indexOf(u8, type_name, "[") != null and
                std.mem.indexOf(u8, type_name, "u8") != null)
            {
                // For string types, convert to slice and store directly
                const slice = std.mem.sliceTo(@as([]const u8, value), 0);
                const result = try self.allocator.dupe(u8, slice);
                break :blk result;
            } else {
                // For other types, format as string
                var buf: [256]u8 = undefined;
                const str = try std.fmt.bufPrint(&buf, "{any}", .{value});
                const result = try self.allocator.dupe(u8, str);
                break :blk result;
            }
        };
        errdefer self.allocator.free(value_str);

        // Put will handle freeing old value if key exists
        try self.user_data.put(key_owned, value_str);
    }

    pub fn getUserData(self: *Request, key: []const u8, comptime T: type) ?T {
        if (self.user_data.get(key)) |value| {
            // If T is []const u8, return the string directly
            if (comptime std.mem.eql(u8, @typeName(T), "[]const u8")) {
                return @as([]const u8, value);
            }

            // For other types, try to parse from string
            if (comptime std.mem.indexOf(u8, @typeName(T), "u32") != null or
                std.mem.indexOf(u8, @typeName(T), "u64") != null or
                std.mem.indexOf(u8, @typeName(T), "i32") != null or
                std.mem.indexOf(u8, @typeName(T), "i64") != null)
            {
                if (std.fmt.parseInt(T, value, 10)) |int| {
                    return int;
                } else |_| {}
            } else if (comptime std.mem.indexOf(u8, @typeName(T), "f32") != null or
                std.mem.indexOf(u8, @typeName(T), "f64") != null)
            {
                if (std.fmt.parseFloat(T, value)) |float| {
                    return float;
                } else |_| {}
            } else if (T == bool) {
                if (std.mem.eql(u8, value, "true")) {
                    return true;
                } else if (std.mem.eql(u8, value, "false")) {
                    return false;
                }
            }

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
        // Clear any previous state
        self.clear();

        var lines = std.mem.splitSequence(u8, raw_request, "\r\n");

        // Parse request line - must have method, path, and version
        if (lines.next()) |request_line| {
            var parts = std.mem.splitScalar(u8, request_line, ' ');
            const method_part = parts.next() orelse return error.MalformedRequest;
            const path_part = parts.next() orelse return error.MalformedRequest;
            const version_part = parts.next() orelse return error.MalformedRequest;

            // Validate that method and path are not empty
            if (method_part.len == 0 or path_part.len == 0) {
                return error.MalformedRequest;
            }

            self.method = Method.fromString(method_part);
            self.path = try self.allocator.dupe(u8, path_part);

            // Validate HTTP version (basic check)
            if (!std.mem.startsWith(u8, version_part, "HTTP/")) {
                return error.MalformedRequest;
            }
        } else {
            return error.MalformedRequest;
        }

        // Parse headers
        while (lines.next()) |line| {
            if (line.len == 0) break; // End of headers
            if (std.mem.indexOf(u8, line, ": ")) |separator| {
                const key = try self.allocator.dupe(u8, line[0..separator]);
                const value = try self.allocator.dupe(u8, line[separator + 2 ..]);
                try self.headers.put(key, value);
            } else {
                return error.MalformedHeader;
            }
        }

        // The rest is body - find where headers end and read everything after
        // Headers end with a blank line (CRLF CRLF), so find that position
        const header_end_marker = "\r\n\r\n";
        if (std.mem.indexOf(u8, raw_request, header_end_marker)) |end_pos| {
            const body_start = end_pos + header_end_marker.len;
            if (body_start < raw_request.len) {
                self.body = try self.allocator.dupe(u8, raw_request[body_start..]);
            }
        }
    }

    // Clear request state (used when re-parsing)
    fn clear(self: *Request) void {
        self.method = .UNKNOWN;
        if (self.path.len > 0) {
            self.allocator.free(self.path);
            self.path = "";
        }

        // Clear headers
        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.clearRetainingCapacity();

        // Clear user data
        var user_it = self.user_data.iterator();
        while (user_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.user_data.clearRetainingCapacity();

        if (self.body.len > 0) {
            self.allocator.free(self.body);
            self.body = "";
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

test "setUserData memory leak fix" {
    const testing = std.testing;
    const allocator = std.heap.page_allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    // Set initial value
    try request.setUserData("user_id", "123");
    try testing.expectEqualStrings("123", request.getUserData("user_id", []const u8).?);

    // Update the same key - should not leak memory
    try request.setUserData("user_id", "456");
    try testing.expectEqualStrings("456", request.getUserData("user_id", []const u8).?);

    // Verify only one entry exists for this key
    try testing.expectEqual(@as(usize, 1), request.user_data.count());

    // Set multiple different keys
    try request.setUserData("role", "admin");
    try request.setUserData("permissions", "read,write");

    try testing.expectEqual(@as(usize, 3), request.user_data.count());
    try testing.expectEqualStrings("456", request.getUserData("user_id", []const u8).?);
    try testing.expectEqualStrings("admin", request.getUserData("role", []const u8).?);
    try testing.expectEqualStrings("read,write", request.getUserData("permissions", []const u8).?);
}

test "setUserData with different value types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    // Test with string
    try request.setUserData("name", "Alice");
    try testing.expectEqualStrings("Alice", request.getUserData("name", []const u8).?);

    // Test with integer (converted to string)
    try request.setUserData("count", @as(u32, 42));
    try testing.expectEqualStrings("42", request.getUserData("count", []const u8).?);

    // Test with boolean (converted to string)
    try request.setUserData("active", true);
    try testing.expectEqualStrings("true", request.getUserData("active", []const u8).?);
}

test "getUserData type casting fix" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    // Test integer parsing
    try request.setUserData("user_id", @as(u32, 123));
    const user_id = request.getUserData("user_id", u32);
    try testing.expect(user_id != null);
    try testing.expectEqual(@as(u32, 123), user_id.?);

    // Test float parsing
    try request.setUserData("score", @as(f32, 95.5));
    const score = request.getUserData("score", f32);
    try testing.expect(score != null);
    try testing.expectEqual(@as(f32, 95.5), score.?);

    // Test boolean parsing
    try request.setUserData("is_admin", true);
    const is_admin = request.getUserData("is_admin", bool);
    try testing.expect(is_admin != null);
    try testing.expectEqual(true, is_admin.?);

    try request.setUserData("is_active", false);
    const is_active = request.getUserData("is_active", bool);
    try testing.expect(is_active != null);
    try testing.expectEqual(false, is_active.?);

    // Test string retrieval (should work for any stored value)
    const user_id_str = request.getUserData("user_id", []const u8);
    try testing.expect(user_id_str != null);
    try testing.expectEqualStrings("123", user_id_str.?);

    // Test invalid conversions (should return null)
    const invalid_int = request.getUserData("score", u32); // float as int
    try testing.expect(invalid_int == null);

    const invalid_bool = request.getUserData("user_id", bool); // int as bool
    try testing.expect(invalid_bool == null);

    // Test non-existent key
    const missing = request.getUserData("nonexistent", u32);
    try testing.expect(missing == null);
}

test "setUserData and deinit memory cleanup" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    // Test setting various types of user data
    try request.setUserData("string_key", "test_value");
    try request.setUserData("int_key", @as(u32, 42));
    try request.setUserData("bool_key", true);

    // Verify data is stored
    const str_val = request.getUserData("string_key", []const u8);
    try testing.expect(str_val != null);
    try testing.expectEqualStrings("test_value", str_val.?);

    const int_val = request.getUserData("int_key", u32);
    try testing.expect(int_val != null);
    try testing.expectEqual(@as(u32, 42), int_val.?);

    const bool_val = request.getUserData("bool_key", bool);
    try testing.expect(bool_val != null);
    try testing.expectEqual(true, bool_val.?);

    // The defer request.deinit() should clean up all allocations
    // If this test passes without leaks, the cleanup is working
}

test "request parsing null checks" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    // Test malformed request - missing method
    const malformed1 = " /path HTTP/1.1\r\n\r\n";
    const result1 = request.parse(malformed1);
    try testing.expectError(error.MalformedRequest, result1);

    // Test malformed request - missing path
    const malformed2 = "GET  HTTP/1.1\r\n\r\n";
    const result2 = request.parse(malformed2);
    try testing.expectError(error.MalformedRequest, result2);

    // Test malformed request - missing version
    const malformed3 = "GET /path\r\n\r\n";
    const result3 = request.parse(malformed3);
    try testing.expectError(error.MalformedRequest, result3);

    // Test invalid HTTP version
    const malformed4 = "GET /path INVALID/1.0\r\n\r\n";
    const result4 = request.parse(malformed4);
    try testing.expectError(error.MalformedRequest, result4);

    // Test malformed header
    const malformed5 = "GET /path HTTP/1.1\r\ninvalid-header-no-colon\r\n\r\n";
    const result5 = request.parse(malformed5);
    try testing.expectError(error.MalformedHeader, result5);

    // Test valid minimal request
    const valid = "GET / HTTP/1.1\r\nHost: localhost\r\n\r\n";
    try request.parse(valid);
    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/", request.path);
    try testing.expectEqualStrings("localhost", request.headers.get("Host").?);
}
