const std = @import("std");
const TlsConfig = @import("tls_config.zig").TlsConfig;

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
    keep_alive_timeout_ms: u32,
    max_requests_per_connection: u16,
    thread_pool_size: u16,
    max_connections: u16,
    drain_timeout_ms: u32,
    tls: TlsConfig,

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
            .keep_alive_timeout_ms = 15000,
            .max_requests_per_connection = 100,
            .thread_pool_size = 32,
            .max_connections = 512,
            .drain_timeout_ms = 30000,
            .tls = TlsConfig.disabled(),
        };
    }

    pub fn getAddress(self: *const ServerConfig) !std.net.Address {
        return try std.net.Address.parseIp(self.host, self.port);
    }

    pub fn fromEnv(allocator: std.mem.Allocator) !ServerConfig {
        const EnvConfig = @import("env_config.zig").EnvConfig;
        const env = try EnvConfig.fromEnv(allocator);

        return ServerConfig.init(env.host, env.port);
    }
};

test "ServerConfig initialization" {
    const testing = std.testing;
    const config = ServerConfig.init("127.0.0.1", 8080);

    try testing.expectEqualStrings("127.0.0.1", config.host);
    try testing.expectEqual(@as(u16, 8080), config.port);
    try testing.expect(!config.tls.enabled);
}
