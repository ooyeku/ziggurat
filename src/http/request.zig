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
    /// The path component only — query string is stripped at parse time.
    path: []const u8,
    /// The raw query string (everything after '?'), or empty if absent.
    query_string: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,
    user_data: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Request {
        return .{
            .method = .UNKNOWN,
            .path = "",
            .query_string = "",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .allocator = allocator,
            .user_data = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Request) void {
        if (self.path.len > 0) {
            self.allocator.free(self.path);
        }
        if (self.query_string.len > 0) {
            self.allocator.free(self.query_string);
        }

        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.deinit();

        var user_it = self.user_data.iterator();
        while (user_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.user_data.deinit();

        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
    }

    /// Store arbitrary data on the request (used by middleware and router for
    /// path parameters, session data, etc.).
    pub fn setUserData(self: *Request, key: []const u8, value: anytype) !void {
        // Convert value to an owned string.
        const value_str: []u8 = blk: {
            const T = @TypeOf(value);
            const info = @typeInfo(T);
            // Accept []const u8, []u8, and string literals (*const [N:0]u8 / *const [N]u8)
            if (T == []const u8 or T == []u8) {
                break :blk try self.allocator.dupe(u8, value);
            }
            if (info == .pointer) {
                const child_info = @typeInfo(info.pointer.child);
                if (child_info == .array and child_info.array.child == u8) {
                    break :blk try self.allocator.dupe(u8, value);
                }
            }
            // Numeric, bool, and other types: format to string.
            var buf: [256]u8 = undefined;
            const s = try std.fmt.bufPrint(&buf, "{}", .{value});
            break :blk try self.allocator.dupe(u8, s);
        };
        errdefer self.allocator.free(value_str);

        // Reuse existing key slot if present; free old value. Otherwise dupe key.
        const gop = try self.user_data.getOrPut(key);
        if (gop.found_existing) {
            // Free old value (key memory is already owned).
            self.allocator.free(gop.value_ptr.*);
        } else {
            // New entry: we must own the key.
            errdefer _ = self.user_data.remove(key);
            gop.key_ptr.* = try self.allocator.dupe(u8, key);
        }
        gop.value_ptr.* = value_str;
    }

    pub fn getUserData(self: *Request, key: []const u8, comptime T: type) ?T {
        const value = self.user_data.get(key) orelse return null;

        if (T == []const u8) return value;

        if (T == bool) {
            if (std.mem.eql(u8, value, "true")) return true;
            if (std.mem.eql(u8, value, "false")) return false;
            return null;
        }

        const info = @typeInfo(T);
        if (info == .int) {
            return std.fmt.parseInt(T, value, 10) catch null;
        }
        if (info == .float) {
            return std.fmt.parseFloat(T, value) catch null;
        }

        return null;
    }

    /// Get a URL path parameter (e.g. `:id` from `/users/:id`).
    pub fn getParam(self: *Request, key: []const u8) ?[]const u8 {
        return self.user_data.get(key);
    }

    /// Get a URL query parameter (e.g. `page` from `?page=1`).
    /// Returns null if the key is absent; returns "" if the key has no value.
    pub fn getQuery(self: *Request, key: []const u8) ?[]const u8 {
        if (self.query_string.len == 0) return null;

        var pairs = std.mem.splitScalar(u8, self.query_string, '&');
        while (pairs.next()) |pair| {
            var kv = std.mem.splitScalar(u8, pair, '=');
            const k = kv.next() orelse continue;
            if (std.mem.eql(u8, k, key)) {
                return kv.next() orelse "";
            }
        }
        return null;
    }

    /// Parse a raw HTTP/1.1 request.
    pub fn parse(self: *Request, raw_request: []const u8) !void {
        self.clear();

        var lines = std.mem.splitSequence(u8, raw_request, "\r\n");

        // Request line
        if (lines.next()) |request_line| {
            var parts = std.mem.splitScalar(u8, request_line, ' ');
            const method_part = parts.next() orelse return error.MalformedRequest;
            const raw_path = parts.next() orelse return error.MalformedRequest;
            const version_part = parts.next() orelse return error.MalformedRequest;

            if (method_part.len == 0 or raw_path.len == 0) {
                return error.MalformedRequest;
            }
            if (!std.mem.startsWith(u8, version_part, "HTTP/")) {
                return error.MalformedRequest;
            }

            self.method = Method.fromString(method_part);

            // Split path and query string at parse time (#10 fix).
            if (std.mem.indexOfScalar(u8, raw_path, '?')) |q| {
                self.path = try self.allocator.dupe(u8, raw_path[0..q]);
                self.query_string = try self.allocator.dupe(u8, raw_path[q + 1 ..]);
            } else {
                self.path = try self.allocator.dupe(u8, raw_path);
            }
        } else {
            return error.MalformedRequest;
        }

        // Headers
        while (lines.next()) |line| {
            if (line.len == 0) break;
            if (std.mem.indexOf(u8, line, ": ")) |separator| {
                const key = try self.allocator.dupe(u8, line[0..separator]);
                const value = try self.allocator.dupe(u8, line[separator + 2 ..]);
                try self.headers.put(key, value);
            } else {
                return error.MalformedHeader;
            }
        }

        // Body
        const header_end_marker = "\r\n\r\n";
        if (std.mem.indexOf(u8, raw_request, header_end_marker)) |end_pos| {
            const body_start = end_pos + header_end_marker.len;
            if (body_start < raw_request.len) {
                self.body = try self.allocator.dupe(u8, raw_request[body_start..]);
            }
        }
    }

    fn clear(self: *Request) void {
        self.method = .UNKNOWN;
        if (self.path.len > 0) {
            self.allocator.free(self.path);
            self.path = "";
        }
        if (self.query_string.len > 0) {
            self.allocator.free(self.query_string);
            self.query_string = "";
        }

        var it = self.headers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.headers.clearRetainingCapacity();

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

// ─── Tests ───────────────────────────────────────────────────────────────────

test "parse request" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    try request.parse("GET /test HTTP/1.1\r\nHost: localhost:8080\r\n\r\n");
    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/test", request.path);
}

test "parse request with headers" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    try request.parse("GET /test HTTP/1.1\r\nHost: localhost:8080\r\nContent-Type: application/json\r\n\r\n");
    try testing.expectEqualStrings("/test", request.path);
    try testing.expectEqualStrings("application/json", request.headers.get("Content-Type") orelse "");
}

test "parse request with body" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    try request.parse("GET /test HTTP/1.1\r\nHost: localhost:8080\r\nContent-Type: application/json\r\n\r\n{\"name\": \"John\"}");
    try testing.expectEqualStrings("{\"name\": \"John\"}", request.body);
}

test "parse request with multi-line body" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    const raw = "POST /api/todos HTTP/1.1\r\nHost: localhost:8080\r\nContent-Type: application/json\r\nContent-Length: 57\r\n\r\n{\"title\":\"test\",\"description\":\"multi\nline\",\"priority\":\"high\"}";
    try request.parse(raw);
    try testing.expectEqual(Method.POST, request.method);
    try testing.expectEqualStrings("/api/todos", request.path);
    try testing.expectEqualStrings("{\"title\":\"test\",\"description\":\"multi\nline\",\"priority\":\"high\"}", request.body);
}

test "query string split from path at parse time" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    try request.parse("GET /users?page=2&limit=10 HTTP/1.1\r\nHost: localhost\r\n\r\n");
    // Path must not contain the query string.
    try testing.expectEqualStrings("/users", request.path);
    try testing.expectEqualStrings("page=2&limit=10", request.query_string);
    try testing.expectEqualStrings("2", request.getQuery("page").?);
    try testing.expectEqualStrings("10", request.getQuery("limit").?);
    try testing.expect(request.getQuery("missing") == null);
}

test "setUserData no memory leak on key update" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    try request.setUserData("user_id", "123");
    try testing.expectEqualStrings("123", request.getUserData("user_id", []const u8).?);

    // Overwrite — must not leak old value or duplicate the key.
    try request.setUserData("user_id", "456");
    try testing.expectEqualStrings("456", request.getUserData("user_id", []const u8).?);
    try testing.expectEqual(@as(usize, 1), request.user_data.count());
}

test "setUserData with different value types" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    try request.setUserData("name", @as([]const u8, "Alice"));
    try testing.expectEqualStrings("Alice", request.getUserData("name", []const u8).?);

    try request.setUserData("count", @as(u32, 42));
    try testing.expectEqualStrings("42", request.getUserData("count", []const u8).?);

    try request.setUserData("active", true);
    try testing.expectEqualStrings("true", request.getUserData("active", []const u8).?);
}

test "getUserData type casting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    try request.setUserData("user_id", @as(u32, 123));
    try testing.expectEqual(@as(u32, 123), request.getUserData("user_id", u32).?);

    try request.setUserData("score", @as(f32, 95.5));
    try testing.expectEqual(@as(f32, 95.5), request.getUserData("score", f32).?);

    try request.setUserData("is_admin", true);
    try testing.expectEqual(true, request.getUserData("is_admin", bool).?);

    try request.setUserData("is_active", false);
    try testing.expectEqual(false, request.getUserData("is_active", bool).?);

    // String retrieval of any stored value.
    try testing.expectEqualStrings("123", request.getUserData("user_id", []const u8).?);

    // Invalid conversions return null.
    try testing.expect(request.getUserData("score", u32) == null); // float stored as "95.5"
    try testing.expect(request.getUserData("nonexistent", u32) == null);
}

test "request parsing null checks" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var request = Request.init(allocator);
    defer request.deinit();

    try testing.expectError(error.MalformedRequest, request.parse(" /path HTTP/1.1\r\n\r\n"));
    try testing.expectError(error.MalformedRequest, request.parse("GET  HTTP/1.1\r\n\r\n"));
    try testing.expectError(error.MalformedRequest, request.parse("GET /path\r\n\r\n"));
    try testing.expectError(error.MalformedRequest, request.parse("GET /path INVALID/1.0\r\n\r\n"));
    try testing.expectError(error.MalformedHeader, request.parse("GET /path HTTP/1.1\r\ninvalid-header-no-colon\r\n\r\n"));

    try request.parse("GET / HTTP/1.1\r\nHost: localhost\r\n\r\n");
    try testing.expectEqual(Method.GET, request.method);
    try testing.expectEqualStrings("/", request.path);
    try testing.expectEqualStrings("localhost", request.headers.get("Host").?);
}
