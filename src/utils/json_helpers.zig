//! JSON serialization and deserialization helpers for Ziggurat
//! Provides utilities for converting between Zig types and JSON/form data

const std = @import("std");
const testing = std.testing;

/// Serialize a Zig value to a JSON string.
/// Caller owns the returned memory.
pub fn jsonify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(value, .{})});
}

/// Parse a JSON string into a Zig type.
/// Returns a `Parsed(T)` whose `.value` contains the result.
/// Caller must call `.deinit()` on the returned value when done.
pub fn parseJson(comptime T: type, allocator: std.mem.Allocator, json_str: []const u8) !std.json.Parsed(T) {
    return try std.json.parseFromSlice(T, allocator, json_str, .{
        .ignore_unknown_fields = true,
    });
}

/// Parse form data in application/x-www-form-urlencoded format.
/// Returns a StringHashMap of key-value pairs.
/// Caller owns the returned map and all strings in it.
pub fn parseFormData(allocator: std.mem.Allocator, body: []const u8) !std.StringHashMap([]const u8) {
    var fields = std.StringHashMap([]const u8).init(allocator);
    errdefer {
        var it = fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }

    if (body.len == 0) return fields;

    var pairs = std.mem.splitScalar(u8, body, '&');
    while (pairs.next()) |pair| {
        if (std.mem.indexOf(u8, pair, "=")) |eq_pos| {
            const key = pair[0..eq_pos];
            const value = pair[eq_pos + 1 ..];

            const decoded_key = try urlDecode(allocator, key);
            const decoded_value = try urlDecode(allocator, value);

            try fields.put(decoded_key, decoded_value);
        }
    }

    return fields;
}

/// URL decode a string (handle %XX sequences and '+' as space).
/// Caller owns the returned memory.
pub fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .{};
    defer result.deinit(allocator);

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            const hex_str = encoded[i + 1 .. i + 3];
            if (std.fmt.parseInt(u8, hex_str, 16)) |byte| {
                try result.append(allocator, byte);
                i += 3;
            } else |_| {
                try result.append(allocator, encoded[i]);
                i += 1;
            }
        } else if (encoded[i] == '+') {
            try result.append(allocator, ' ');
            i += 1;
        } else {
            try result.append(allocator, encoded[i]);
            i += 1;
        }
    }

    return try allocator.dupe(u8, result.items);
}

/// Detect content type from file extension.
pub fn detectContentType(path: []const u8) []const u8 {
    const lower = struct {
        fn endsWith(haystack: []const u8, needle: []const u8) bool {
            if (haystack.len < needle.len) return false;
            const tail = haystack[haystack.len - needle.len ..];
            return std.ascii.eqlIgnoreCase(tail, needle);
        }
    };

    if (lower.endsWith(path, ".html")) return "text/html";
    if (lower.endsWith(path, ".css")) return "text/css";
    if (lower.endsWith(path, ".js")) return "application/javascript";
    if (lower.endsWith(path, ".json")) return "application/json";
    if (lower.endsWith(path, ".xml")) return "application/xml";
    if (lower.endsWith(path, ".png")) return "image/png";
    if (lower.endsWith(path, ".jpg")) return "image/jpeg";
    if (lower.endsWith(path, ".jpeg")) return "image/jpeg";
    if (lower.endsWith(path, ".gif")) return "image/gif";
    if (lower.endsWith(path, ".svg")) return "image/svg+xml";
    if (lower.endsWith(path, ".pdf")) return "application/pdf";
    if (lower.endsWith(path, ".txt")) return "text/plain";
    return "application/octet-stream";
}

// ─── Tests ───────────────────────────────────────────────────────────────────

test "jsonify simple value" {
    const allocator = testing.allocator;
    const json_str = try jsonify(allocator, @as(i32, 42));
    defer allocator.free(json_str);
    try testing.expectEqualStrings("42", json_str);
}

test "jsonify struct" {
    const allocator = testing.allocator;
    const TestStruct = struct { name: []const u8, age: u32 };
    const value = TestStruct{ .name = "Alice", .age = 30 };

    const json_str = try jsonify(allocator, value);
    defer allocator.free(json_str);

    try testing.expect(std.mem.indexOf(u8, json_str, "Alice") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "30") != null);
}

test "jsonify array" {
    const allocator = testing.allocator;
    const values = [_]i32{ 1, 2, 3, 4, 5 };
    const json_str = try jsonify(allocator, values);
    defer allocator.free(json_str);

    try testing.expect(std.mem.indexOf(u8, json_str, "1") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "5") != null);
}

test "jsonify nested struct" {
    const allocator = testing.allocator;
    const Inner = struct { value: u32 };
    const Outer = struct { inner: Inner, name: []const u8 };

    const obj = Outer{ .inner = Inner{ .value = 42 }, .name = "test" };
    const json_str = try jsonify(allocator, obj);
    defer allocator.free(json_str);

    try testing.expect(std.mem.indexOf(u8, json_str, "42") != null);
    try testing.expect(std.mem.indexOf(u8, json_str, "test") != null);
}

test "jsonify boolean values" {
    const allocator = testing.allocator;
    const TestStruct = struct { enabled: bool };

    const obj = TestStruct{ .enabled = true };
    const json_str = try jsonify(allocator, obj);
    defer allocator.free(json_str);

    try testing.expect(std.mem.indexOf(u8, json_str, "true") != null);
}

test "parseFormData simple" {
    const allocator = testing.allocator;
    var fields = try parseFormData(allocator, "name=John&age=30&city=NYC");
    defer {
        var it = fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }

    try testing.expectEqualStrings("John", fields.get("name") orelse "");
    try testing.expectEqualStrings("30", fields.get("age") orelse "");
    try testing.expectEqualStrings("NYC", fields.get("city") orelse "");
}

test "parseFormData with URL encoding" {
    const allocator = testing.allocator;
    var fields = try parseFormData(allocator, "name=John+Doe&email=john%40example.com");
    defer {
        var it = fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }

    try testing.expectEqualStrings("John Doe", fields.get("name") orelse "");
    try testing.expectEqualStrings("john@example.com", fields.get("email") orelse "");
}

test "parseFormData empty body" {
    const allocator = testing.allocator;
    var fields = try parseFormData(allocator, "");
    defer fields.deinit();
    try testing.expectEqual(@as(usize, 0), fields.count());
}

test "detectContentType" {
    try testing.expectEqualStrings("text/html", detectContentType("index.html"));
    try testing.expectEqualStrings("application/json", detectContentType("data.json"));
    try testing.expectEqualStrings("image/png", detectContentType("image.png"));
    try testing.expectEqualStrings("text/css", detectContentType("style.css"));
    try testing.expectEqualStrings("application/octet-stream", detectContentType("file.bin"));
}

test "detectContentType case insensitive" {
    try testing.expectEqualStrings("text/html", detectContentType("FILE.HTML"));
    try testing.expectEqualStrings("application/json", detectContentType("data.JSON"));
}

test "detectContentType with paths" {
    try testing.expectEqualStrings("text/html", detectContentType("/path/to/index.html"));
    try testing.expectEqualStrings("application/json", detectContentType("/api/data.json"));
    try testing.expectEqualStrings("application/octet-stream", detectContentType("/files/unknown.xyz"));
}
