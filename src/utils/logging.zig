const std = @import("std");

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
    critical,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .critical => "CRITICAL",
        };
    }

    pub fn getColor(self: LogLevel) []const u8 {
        return switch (self) {
            .debug => "\x1b[36m", // Cyan
            .info => "\x1b[32m", // Green
            .warn => "\x1b[33m", // Yellow
            .err => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    level: LogLevel = .info,
    enable_colors: bool = true,
    enable_timestamp: bool = true,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        return Self{
            .allocator = allocator,
        };
    }

    pub fn setLogLevel(self: *Self, level: LogLevel) void {
        self.level = level;
    }

    pub fn setEnableColors(self: *Self, enable: bool) void {
        self.enable_colors = enable;
    }

    pub fn setEnableTimestamp(self: *Self, enable: bool) void {
        self.enable_timestamp = enable;
    }

    fn getTimestamp(self: *Self) ![]const u8 {
        var buffer: [64]u8 = undefined;
        const timestamp = std.time.timestamp();
        const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @intCast(timestamp) };
        const epoch_day = epoch_seconds.getEpochDay();
        const year_day = epoch_day.calculateYearDay();
        const day_seconds = epoch_seconds.getDaySeconds();
        const month_day = year_day.calculateMonthDay();

        const formatted = try std.fmt.bufPrint(&buffer, "[{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}]", .{
            year_day.year,
            @as(u8, @intCast(@intFromEnum(month_day.month))) + 1, // month is 0-based
            @as(u8, @intCast(month_day.day_index)) + 1, // day is 0-based
            day_seconds.getHoursIntoDay(),
            day_seconds.getMinutesIntoHour(),
            day_seconds.getSecondsIntoMinute(),
        });
        return self.allocator.dupe(u8, formatted);
    }

    fn log(self: *Self, level: LogLevel, comptime format: []const u8, args: anytype) !void {
        if (@intFromEnum(level) < @intFromEnum(self.level)) return;

        const reset_color = "\x1b[0m";
        const level_str = level.toString();
        const color = if (self.enable_colors) level.getColor() else "";
        const reset = if (self.enable_colors) reset_color else "";

        if (self.enable_timestamp) {
            const timestamp = try self.getTimestamp();
            defer self.allocator.free(timestamp);
            std.debug.print("{s} ", .{timestamp});
        }

        std.debug.print("{s}[{s}]{s} ", .{ color, level_str, reset });
        std.debug.print(format ++ "\n", args);
    }

    pub fn debug(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.debug, format, args);
    }

    pub fn info(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.info, format, args);
    }

    pub fn warn(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.warn, format, args);
    }

    pub fn err(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.err, format, args);
    }

    pub fn critical(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.log(.critical, format, args);
    }
};

// Global logger instance and mutex for thread safety
var global_logger: ?Logger = null;
var global_logger_mutex: std.Thread.Mutex = .{};

pub fn getGlobalLogger() ?*Logger {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();

    if (global_logger == null) return null;
    return &global_logger.?;
}

pub fn initGlobalLogger(allocator: std.mem.Allocator) !void {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();

    if (global_logger != null) return;
    global_logger = try Logger.init(allocator);
}

/// Thread-safe logger configuration functions
pub fn setGlobalLogLevel(level: LogLevel) void {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();

    if (global_logger) |*logger| {
        logger.setLogLevel(level);
    }
}

pub fn setGlobalEnableColors(enable: bool) void {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();

    if (global_logger) |*logger| {
        logger.setEnableColors(enable);
    }
}

pub fn setGlobalEnableTimestamp(enable: bool) void {
    global_logger_mutex.lock();
    defer global_logger_mutex.unlock();

    if (global_logger) |*logger| {
        logger.setEnableTimestamp(enable);
    }
}

/// Convenience functions that use the global logger
pub fn debug(comptime format: []const u8, args: anytype) !void {
    if (getGlobalLogger()) |logger| {
        try logger.debug(format, args);
    }
}

pub fn info(comptime format: []const u8, args: anytype) !void {
    if (getGlobalLogger()) |logger| {
        try logger.info(format, args);
    }
}

pub fn warn(comptime format: []const u8, args: anytype) !void {
    if (getGlobalLogger()) |logger| {
        try logger.warn(format, args);
    }
}

pub fn err(comptime format: []const u8, args: anytype) !void {
    if (getGlobalLogger()) |logger| {
        try logger.err(format, args);
    }
}

pub fn critical(comptime format: []const u8, args: anytype) !void {
    if (getGlobalLogger()) |logger| {
        try logger.critical(format, args);
    }
}

test "logger thread safety" {
    const allocator = std.testing.allocator;

    // Initialize global logger
    try initGlobalLogger(allocator);
    defer {
        global_logger_mutex.lock();
        global_logger = null;
        global_logger_mutex.unlock();
    }

    // Test thread-safe configuration changes
    setGlobalLogLevel(.debug);
    setGlobalEnableColors(false);
    setGlobalEnableTimestamp(false);

    const logger = getGlobalLogger();
    try std.testing.expect(logger != null);
    try std.testing.expectEqual(LogLevel.debug, logger.?.level);
    try std.testing.expectEqual(false, logger.?.enable_colors);
    try std.testing.expectEqual(false, logger.?.enable_timestamp);

    // Test convenience functions
    try info("Test info message", .{});
    try debug("Test debug message", .{});
    try warn("Test warning message", .{});
    try err("Test error message", .{});
    try critical("Test critical message", .{});
}

test "global logger functions" {
    const allocator = std.testing.allocator;

    // Initialize global logger
    try initGlobalLogger(allocator);
    defer {
        global_logger_mutex.lock();
        global_logger = null;
        global_logger_mutex.unlock();
    }

    // Test global logger functions
    setGlobalLogLevel(.debug);
    setGlobalEnableColors(true);
    setGlobalEnableTimestamp(true);

    const logger = getGlobalLogger();
    try std.testing.expect(logger != null);
    try std.testing.expectEqual(LogLevel.debug, logger.?.level);
    try std.testing.expectEqual(true, logger.?.enable_colors);
    try std.testing.expectEqual(true, logger.?.enable_timestamp);
}
