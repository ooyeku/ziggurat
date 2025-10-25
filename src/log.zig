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
