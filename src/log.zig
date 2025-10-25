//! Simplified logging interface
//! Provides direct functions for logging without needing to get the global logger

const std = @import("std");
const logging = @import("utils/logging.zig");

pub const LogLevel = logging.LogLevel;

pub fn debug(comptime format: []const u8, args: anytype) !void {
    if (logging.getGlobalLogger()) |logger| {
        try logger.debug(format, args);
    }
}

pub fn info(comptime format: []const u8, args: anytype) !void {
    if (logging.getGlobalLogger()) |logger| {
        try logger.info(format, args);
    }
}

pub fn warn(comptime format: []const u8, args: anytype) !void {
    if (logging.getGlobalLogger()) |logger| {
        try logger.warn(format, args);
    }
}

pub fn err(comptime format: []const u8, args: anytype) !void {
    if (logging.getGlobalLogger()) |logger| {
        try logger.err(format, args);
    }
}

pub fn critical(comptime format: []const u8, args: anytype) !void {
    if (logging.getGlobalLogger()) |logger| {
        try logger.critical(format, args);
    }
}

pub fn setLevel(level: LogLevel) void {
    if (logging.getGlobalLogger()) |logger| {
        logger.setLogLevel(level);
    }
}

pub fn setColors(enable: bool) void {
    if (logging.getGlobalLogger()) |logger| {
        logger.setEnableColors(enable);
    }
}

pub fn setTimestamp(enable: bool) void {
    if (logging.getGlobalLogger()) |logger| {
        logger.setEnableTimestamp(enable);
    }
}

test "logger should be initialized" {
    try logging.initGlobalLogger(std.testing.allocator);
    const logger = logging.getGlobalLogger();
    try std.testing.expect(logger != null);
    try std.testing.expectEqual(logger.?.level, .info);
    try std.testing.expectEqual(logger.?.enable_colors, true);
    try std.testing.expectEqual(logger.?.enable_timestamp, true);
}

test "log levels" {
    try logging.initGlobalLogger(std.testing.allocator);
    const logger = logging.getGlobalLogger().?;
    logger.setLogLevel(.debug);
    try logger.debug("Hello, world!", .{});
    logger.setLogLevel(.info);
    try logger.info("Hello, world!", .{});
    logger.setLogLevel(.warn);
    try logger.warn("Hello, world!", .{});
    logger.setLogLevel(.err);
    try logger.err("Hello, world!", .{});
    logger.setLogLevel(.critical);
    try logger.critical("Hello, world!", .{});
}

test "simplified logging interface - debug" {
    try logging.initGlobalLogger(std.testing.allocator);
    try debug("debug message", .{});
}

test "simplified logging interface - info" {
    try logging.initGlobalLogger(std.testing.allocator);
    try info("info message", .{});
}

test "simplified logging interface - warn" {
    try logging.initGlobalLogger(std.testing.allocator);
    try warn("warning message", .{});
}

test "simplified logging interface - error" {
    try logging.initGlobalLogger(std.testing.allocator);
    try err("error message", .{});
}

test "simplified logging interface - critical" {
    try logging.initGlobalLogger(std.testing.allocator);
    try critical("critical message", .{});
}

test "simplified logging with format arguments" {
    try logging.initGlobalLogger(std.testing.allocator);
    try info("User {s} logged in from {s}", .{ "alice", "192.168.1.1" });
    try warn("Request took {d}ms", .{500});
    try err("Failed to process item {d}", .{42});
}

test "setLevel function" {
    try logging.initGlobalLogger(std.testing.allocator);
    setLevel(.debug);
    const logger = logging.getGlobalLogger().?;
    try std.testing.expectEqual(logger.level, .debug);

    setLevel(.info);
    try std.testing.expectEqual(logger.level, .info);

    setLevel(.critical);
    try std.testing.expectEqual(logger.level, .critical);
}

test "setColors function" {
    try logging.initGlobalLogger(std.testing.allocator);
    const logger = logging.getGlobalLogger().?;

    setColors(true);
    try std.testing.expectEqual(logger.enable_colors, true);

    setColors(false);
    try std.testing.expectEqual(logger.enable_colors, false);
}

test "setTimestamp function" {
    try logging.initGlobalLogger(std.testing.allocator);
    const logger = logging.getGlobalLogger().?;

    setTimestamp(true);
    try std.testing.expectEqual(logger.enable_timestamp, true);

    setTimestamp(false);
    try std.testing.expectEqual(logger.enable_timestamp, false);
}


test "all log levels produce output" {
    try logging.initGlobalLogger(std.testing.allocator);

    setLevel(.debug);
    try debug("Debug level", .{});
    try info("Info level", .{});
    try warn("Warn level", .{});
    try err("Error level", .{});
    try critical("Critical level", .{});
}

test "log level filtering" {
    try logging.initGlobalLogger(std.testing.allocator);
    const logger = logging.getGlobalLogger().?;

    // Set to warn level - should skip debug and info
    setLevel(.warn);
    try std.testing.expectEqual(logger.level, .warn);

    // These won't show due to level filtering
    try debug("Should not appear", .{});
    try info("Should not appear", .{});

    // These will show
    try warn("Should appear", .{});
    try err("Should appear", .{});
}

test "log level values" {
    try logging.initGlobalLogger(std.testing.allocator);

    const debug_level = LogLevel.debug;
    const info_level = LogLevel.info;
    const warn_level = LogLevel.warn;
    const err_level = LogLevel.err;
    const critical_level = LogLevel.critical;

    // Verify log levels exist and can be used
    setLevel(debug_level);
    setLevel(info_level);
    setLevel(warn_level);
    setLevel(err_level);
    setLevel(critical_level);

    const logger = logging.getGlobalLogger().?;
    try std.testing.expectEqual(logger.level, critical_level);
}

test "multiple configuration changes" {
    try logging.initGlobalLogger(std.testing.allocator);
    const logger = logging.getGlobalLogger().?;

    // Change multiple settings
    setLevel(.debug);
    setColors(false);
    setTimestamp(true);

    try std.testing.expectEqual(logger.level, .debug);
    try std.testing.expectEqual(logger.enable_colors, false);
    try std.testing.expectEqual(logger.enable_timestamp, true);

    // Change them back
    setLevel(.warn);
    setColors(true);
    setTimestamp(false);

    try std.testing.expectEqual(logger.level, .warn);
    try std.testing.expectEqual(logger.enable_colors, true);
    try std.testing.expectEqual(logger.enable_timestamp, false);
}
