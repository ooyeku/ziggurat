const std = @import("std");
const TlsConfig = @import("../config/tls_config.zig").TlsConfig;
const logging = @import("../utils/logging.zig");

/// TLS support stub. Configuration and socket wrapping are implemented,
/// but actual TLS encryption is not — all read/write calls pass through
/// to plain sockets. Terminate TLS at a reverse proxy for now.
pub const Tls = struct {
    ssl_ctx: usize = 0,
    is_initialized: bool = false,
    config: TlsConfig,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, config: TlsConfig) !Tls {
        var tls = Tls{
            .allocator = allocator,
            .config = config,
        };

        if (!config.enabled) return tls;

        try config.validate();
        tls.is_initialized = true;

        if (logging.getGlobalLogger()) |logger| {
            try logger.info("TLS initialized with certificate: {s}", .{config.cert_file.?});
        }

        return tls;
    }

    pub fn deinit(self: *Tls) void {
        if (!self.is_initialized) return;
        if (logging.getGlobalLogger()) |logger| {
            logger.debug("TLS resources cleaned up", .{}) catch {};
        }
        self.is_initialized = false;
    }

    pub fn wrapSocket(self: *Tls, socket: std.posix.socket_t) !std.posix.socket_t {
        if (!self.is_initialized) return socket;
        if (logging.getGlobalLogger()) |logger| {
            try logger.debug("TLS: Wrapped socket {any}", .{socket});
        }
        return socket;
    }

    pub fn read(self: *Tls, socket: std.posix.socket_t, buffer: []u8) !usize {
        _ = self;
        return std.posix.read(socket, buffer);
    }

    pub fn write(self: *Tls, socket: std.posix.socket_t, data: []const u8) !usize {
        _ = self;
        return std.posix.write(socket, data);
    }
};

test "Tls with disabled config" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const config = TlsConfig.disabled();
    var tls = try Tls.init(allocator, config);
    defer tls.deinit();

    try testing.expect(!tls.is_initialized);
    try testing.expect(!tls.config.enabled);

    const fake_socket: std.posix.socket_t = 42;
    const wrapped = try tls.wrapSocket(fake_socket);
    try testing.expectEqual(fake_socket, wrapped);
}
