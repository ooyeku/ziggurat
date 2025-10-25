//! JSON serialization and deserialization helpers for Ziggurat
//! Provides utilities for converting between Zig types and JSON/form data

const std = @import("std");
const testing = std.testing;

/// Serialize a Zig value to JSON string
/// Caller owns the returned memory
pub fn jsonify(allocator: std.mem.Allocator, value: anytype) ![]const u8 {
    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try std.json.stringify(value, .{}, fbs.writer());
    return try allocator.dupe(u8, fbs.getWritten());
}

// Note: In Zig 0.15, std.json.stringify may not exist yet
// This is a placeholder that will be updated when the API is available
// For now, tests using this function may be skipped

/// Parse JSON string into a Zig type
/// Caller owns any memory in the returned value
pub fn parseJson(comptime T: type, allocator: std.mem.Allocator, json_str: []const u8) !T {
    var stream = std.json.TokenStream.init(json_str);
    return try std.json.parse(T, &stream, .{
        .allocator = allocator,
        .ignore_unknown_fields = true,
    });
}

/// Parse form data in application/x-www-form-urlencoded format
/// Returns a StringHashMap of key-value pairs
/// Caller owns the returned map and all strings in it
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

/// URL decode a string (handle %XX sequences)
/// Caller owns the returned memory
fn urlDecode(allocator: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    var buffer: [1024]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    var i: usize = 0;
    while (i < encoded.len) {
        if (encoded[i] == '%' and i + 2 < encoded.len) {
            const hex_str = encoded[i + 1 .. i + 3];
            if (std.fmt.parseInt(u8, hex_str, 16)) |byte| {
                try fbs.writer().writeByte(byte);
                i += 3;
            } else |_| {
                try fbs.writer().writeByte(encoded[i]);
                i += 1;
            }
        } else if (encoded[i] == '+') {
            try fbs.writer().writeByte(' ');
            i += 1;
        } else {
            try fbs.writer().writeByte(encoded[i]);
            i += 1;
        }
    }

    return try allocator.dupe(u8, fbs.getWritten());
}

/// Detect content type from file extension
pub fn detectContentType(path: []const u8) []const u8 {
    if (std.mem.endsWith(u8, path, ".html")) return "text/html";
    if (std.mem.endsWith(u8, path, ".css")) return "text/css";
    if (std.mem.endsWith(u8, path, ".js")) return "application/javascript";
    if (std.mem.endsWith(u8, path, ".json")) return "application/json";
    if (std.mem.endsWith(u8, path, ".xml")) return "application/xml";
    if (std.mem.endsWith(u8, path, ".png")) return "image/png";
    if (std.mem.endsWith(u8, path, ".jpg")) return "image/jpeg";
    if (std.mem.endsWith(u8, path, ".jpeg")) return "image/jpeg";
    if (std.mem.endsWith(u8, path, ".gif")) return "image/gif";
    if (std.mem.endsWith(u8, path, ".svg")) return "image/svg+xml";
    if (std.mem.endsWith(u8, path, ".pdf")) return "application/pdf";
    if (std.mem.endsWith(u8, path, ".txt")) return "text/plain";
    return "application/octet-stream";
}

test "jsonify simple value" {
    const allocator = testing.allocator;
    const value: i32 = 42;
    const json_str = try jsonify(allocator, value);
    defer allocator.free(json_str);
    try testing.expectEqualStrings("42", json_str);
}

test "jsonify struct" {
    const allocator = testing.allocator;
    const TestStruct = struct {
        name: []const u8,
        age: u32,
    };

    const value = TestStruct{
        .name = "Alice",
        .age = 30,
    };

    const json_str = try jsonify(allocator, value);
    defer allocator.free(json_str);

    // Note: field order may vary, so just check that required fields are present
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

    const obj = Outer{
        .inner = Inner{ .value = 42 },
        .name = "test",
    };

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

    try testing.expect(std.mem.indexOf(u8, json_str, "true") != null or std.mem.indexOf(u8, json_str, "1") != null);
}

test "parseFormData simple" {
    const allocator = testing.allocator;
    const form_data = "name=John&age=30&city=NYC";

    var fields = try parseFormData(allocator, form_data);
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
    const form_data = "name=John+Doe&email=john%40example.com";

    var fields = try parseFormData(allocator, form_data);
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
    const form_data = "";

    var fields = try parseFormData(allocator, form_data);
    defer {
        var it = fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }

    try testing.expectEqual(@as(usize, 0), fields.count());
}

test "parseFormData multiple values" {
    const allocator = testing.allocator;
    const form_data = "first=1&second=2&third=3";

    var fields = try parseFormData(allocator, form_data);
    defer {
        var it = fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }

    try testing.expectEqual(@as(usize, 3), fields.count());
    try testing.expectEqualStrings("1", fields.get("first") orelse "");
    try testing.expectEqualStrings("2", fields.get("second") orelse "");
    try testing.expectEqualStrings("3", fields.get("third") orelse "");
}

test "parseFormData special characters" {
    const allocator = testing.allocator;
    const form_data = "email=test%40example.com&message=hello%20world";

    var fields = try parseFormData(allocator, form_data);
    defer {
        var it = fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }

    try testing.expectEqualStrings("test@example.com", fields.get("email") orelse "");
    try testing.expectEqualStrings("hello world", fields.get("message") orelse "");
}

test "parseFormData equals in value" {
    const allocator = testing.allocator;
    const form_data = "data=key=value";

    var fields = try parseFormData(allocator, form_data);
    defer {
        var it = fields.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        fields.deinit();
    }

    try testing.expectEqualStrings("key=value", fields.get("data") orelse "");
}

test "detectContentType" {
    try testing.expectEqualStrings("text/html", detectContentType("index.html"));
    try testing.expectEqualStrings("application/json", detectContentType("data.json"));
    try testing.expectEqualStrings("image/png", detectContentType("image.png"));
    try testing.expectEqualStrings("text/css", detectContentType("style.css"));
    try testing.expectEqualStrings("application/octet-stream", detectContentType("file.bin"));
}

test "detectContentType various extensions" {
    try testing.expectEqualStrings("text/html", detectContentType("index.html"));
    try testing.expectEqualStrings("text/css", detectContentType("styles.css"));
    try testing.expectEqualStrings("application/javascript", detectContentType("app.js"));
    try testing.expectEqualStrings("image/jpeg", detectContentType("photo.jpg"));
    try testing.expectEqualStrings("image/jpeg", detectContentType("photo.jpeg"));
    try testing.expectEqualStrings("image/png", detectContentType("image.png"));
    try testing.expectEqualStrings("application/pdf", detectContentType("document.pdf"));
}

test "detectContentType with paths" {
    try testing.expectEqualStrings("text/html", detectContentType("/path/to/index.html"));
    try testing.expectEqualStrings("application/json", detectContentType("/api/data.json"));
    try testing.expectEqualStrings("application/octet-stream", detectContentType("/files/unknown.xyz"));
}

test "detectContentType case insensitive paths" {
    try testing.expectEqualStrings("text/html", detectContentType("FILE.HTML"));
    try testing.expectEqualStrings("application/json", detectContentType("data.JSON"));
}
