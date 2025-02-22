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
    path: []const u8,
    headers: std.StringHashMap([]const u8),
    body: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Request {
        return .{
            .method = .UNKNOWN,
            .path = "",
            .headers = std.StringHashMap([]const u8).init(allocator),
            .body = "",
            .allocator = allocator,
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

        // Free body if it was allocated
        if (self.body.len > 0) {
            self.allocator.free(self.body);
        }
    }

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
