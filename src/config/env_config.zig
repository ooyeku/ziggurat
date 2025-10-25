//! Environment variable configuration for Ziggurat
//! Provides convenient access to environment variables with type conversion

const std = @import("std");
const testing = std.testing;

/// Get an environment variable as a string
pub fn getEnv(allocator: std.mem.Allocator, key: []const u8) !?[]const u8 {
    return try std.process.getEnvVarOwned(allocator, key);
}

/// Get an environment variable with a default value
pub fn getEnvOr(allocator: std.mem.Allocator, key: []const u8, default: []const u8) ![]const u8 {
    if (std.process.getEnvVarOwned(allocator, key)) |value| {
        return value;
    } else |_| {
        return try allocator.dupe(u8, default);
    }
}

/// Get an environment variable as an integer
pub fn getEnvInt(comptime T: type, allocator: std.mem.Allocator, key: []const u8) !?T {
    _ = allocator;
    if (std.process.getEnvVarOwned(std.heap.page_allocator, key)) |value| {
        defer std.heap.page_allocator.free(value);
        return try std.fmt.parseInt(T, value, 10);
    } else |_| {
        return null;
    }
}

/// Get an environment variable as an integer with a default value
pub fn getEnvIntOr(comptime T: type, allocator: std.mem.Allocator, key: []const u8, default: T) !T {
    if (try getEnvInt(T, allocator, key)) |value| {
        return value;
    }
    return default;
}

/// Get an environment variable as a boolean
pub fn getEnvBool(allocator: std.mem.Allocator, key: []const u8) !?bool {
    _ = allocator;
    if (std.process.getEnvVarOwned(std.heap.page_allocator, key)) |value| {
        defer std.heap.page_allocator.free(value);
        if (std.mem.eql(u8, value, "true") or std.mem.eql(u8, value, "1") or std.mem.eql(u8, value, "yes")) {
            return true;
        } else if (std.mem.eql(u8, value, "false") or std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "no")) {
            return false;
        }
    } else |_| {}
    return null;
}

/// Get an environment variable as a boolean with a default value
pub fn getEnvBoolOr(allocator: std.mem.Allocator, key: []const u8, default: bool) !bool {
    if (try getEnvBool(allocator, key)) |value| {
        return value;
    }
    return default;
}

/// Common environment variable names for Ziggurat
pub const EnvVars = struct {
    pub const HOST = "ZIGGURAT_HOST";
    pub const PORT = "ZIGGURAT_PORT";
    pub const READ_TIMEOUT = "ZIGGURAT_READ_TIMEOUT";
    pub const WRITE_TIMEOUT = "ZIGGURAT_WRITE_TIMEOUT";
    pub const BUFFER_SIZE = "ZIGGURAT_BUFFER_SIZE";
    pub const DEBUG_MODE = "ZIGGURAT_DEBUG";
    pub const TLS_CERT = "ZIGGURAT_TLS_CERT";
    pub const TLS_KEY = "ZIGGURAT_TLS_KEY";
};

/// Load server configuration from environment variables
pub const EnvConfig = struct {
    host: []const u8,
    port: u16,
    read_timeout_ms: u32,
    write_timeout_ms: u32,
    buffer_size: usize,
    debug_mode: bool,

    pub fn fromEnv(allocator: std.mem.Allocator) !EnvConfig {
        return .{
            .host = try getEnvOr(allocator, EnvVars.HOST, "127.0.0.1"),
            .port = try getEnvIntOr(u16, allocator, EnvVars.PORT, 8080),
            .read_timeout_ms = try getEnvIntOr(u32, allocator, EnvVars.READ_TIMEOUT, 5000),
            .write_timeout_ms = try getEnvIntOr(u32, allocator, EnvVars.WRITE_TIMEOUT, 5000),
            .buffer_size = try getEnvIntOr(usize, allocator, EnvVars.BUFFER_SIZE, 1024),
            .debug_mode = try getEnvBoolOr(allocator, EnvVars.DEBUG_MODE, false),
        };
    }
};

test "get env var or with default" {
    const allocator = testing.allocator;

    // This test assumes the env var doesn't exist
    const result = try getEnvOr(allocator, "NONEXISTENT_VAR_XYZ", "default_value");
    defer allocator.free(result);

    try testing.expectEqualStrings("default_value", result);
}

test "get env int or with default" {
    const allocator = testing.allocator;

    // This test assumes the env var doesn't exist
    const result = try getEnvIntOr(u32, allocator, "NONEXISTENT_INT_VAR_XYZ", 42);

    try testing.expectEqual(@as(u32, 42), result);
}

test "get env bool or with default" {
    const allocator = testing.allocator;

    // This test assumes the env var doesn't exist
    const result = try getEnvBoolOr(allocator, "NONEXISTENT_BOOL_VAR_XYZ", true);

    try testing.expectEqual(true, result);
}

test "get env with default for various strings" {
    const allocator = testing.allocator;

    const result1 = try getEnvOr(allocator, "NONEXISTENT_VAR_1", "default1");
    defer allocator.free(result1);
    try testing.expectEqualStrings("default1", result1);

    const result2 = try getEnvOr(allocator, "NONEXISTENT_VAR_2", "");
    defer allocator.free(result2);
    try testing.expectEqualStrings("", result2);
}

test "get env bool or various values" {
    const allocator = testing.allocator;

    const result_default = try getEnvBoolOr(allocator, "NONEXISTENT_BOOL", true);
    try testing.expect(result_default);

    const result_default_false = try getEnvBoolOr(allocator, "NONEXISTENT_BOOL_2", false);
    try testing.expect(!result_default_false);
}

test "get env int with different types" {
    const allocator = testing.allocator;

    const result_u32 = try getEnvIntOr(u32, allocator, "NONEXISTENT_INT_U32", 42);
    try testing.expectEqual(@as(u32, 42), result_u32);

    const result_u16 = try getEnvIntOr(u16, allocator, "NONEXISTENT_INT_U16", 1000);
    try testing.expectEqual(@as(u16, 1000), result_u16);

    const result_u64 = try getEnvIntOr(u64, allocator, "NONEXISTENT_INT_U64", 999999);
    try testing.expectEqual(@as(u64, 999999), result_u64);
}

test "env config structure defaults" {
    const allocator = testing.allocator;
    const config = try EnvConfig.fromEnv(allocator);
    defer allocator.free(config.host);

    try testing.expectEqualStrings("127.0.0.1", config.host);
    try testing.expectEqual(@as(u16, 8080), config.port);
    try testing.expectEqual(@as(u32, 5000), config.read_timeout_ms);
    try testing.expectEqual(@as(u32, 5000), config.write_timeout_ms);
    try testing.expectEqual(@as(usize, 1024), config.buffer_size);
}
