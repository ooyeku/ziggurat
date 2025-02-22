const std = @import("std");

pub const ServerConfig = struct {
    host: []const u8,
    port: u16,
    backlog: u31,
    buffer_size: usize,
    read_timeout_ms: u32,
    write_timeout_ms: u32,
    max_header_size: usize,
    max_body_size: usize,
    enable_keep_alive: bool,

    pub fn init(host: []const u8, port: u16) ServerConfig {
        return .{
            .host = host,
            .port = port,
            .backlog = 128,
            .buffer_size = 1024,
            .read_timeout_ms = 5000,
            .write_timeout_ms = 5000,
            .max_header_size = 8192,
            .max_body_size = 1024 * 1024, // 1MB
            .enable_keep_alive = true,
        };
    }

    pub fn getAddress(self: *const ServerConfig) !std.net.Address {
        return try std.net.Address.parseIp(self.host, self.port);
    }
};
