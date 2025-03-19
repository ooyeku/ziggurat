const std = @import("std");
const testing = std.testing;
const TlsConfig = @import("../config/tls_config.zig").TlsConfig;
const Tls = @import("tls.zig").Tls;

test "TLS initialization and deinitialization" {
    // Test with TLS disabled
    {
        const allocator = testing.allocator;
        const config = TlsConfig.disabled();
        var tls = try Tls.init(allocator, config);
        defer tls.deinit();

        try testing.expect(!tls.is_initialized);
    }

    // Test with TLS enabled
    {
        const allocator = testing.allocator;
        const config = TlsConfig.enableTls(allocator, "test_cert.pem", "test_key.pem");
        var tls = try Tls.init(allocator, config);
        defer tls.deinit();

        try testing.expect(tls.is_initialized);
        try testing.expectEqualStrings("test_cert.pem", tls.config.cert_file.?);
    }
}

test "TLS socket operations" {
    const allocator = testing.allocator;

    // Test with TLS disabled
    {
        const config = TlsConfig.disabled();
        var tls = try Tls.init(allocator, config);
        defer tls.deinit();

        // Create a fake socket for testing
        const fake_socket: std.posix.socket_t = 42;

        // Test wrapping - should return the same socket when TLS is disabled
        const wrapped_socket = try tls.wrapSocket(fake_socket);
        try testing.expectEqual(fake_socket, wrapped_socket);

        // Test the read and write operations with TLS disabled
        // These will fall back to the standard socket operations
        var test_buf = [_]u8{0} ** 10;
        _ = tls.read(fake_socket, &test_buf) catch {};
        _ = tls.write(fake_socket, &test_buf) catch {};
    }

    // Test with TLS enabled
    {
        const config = TlsConfig.enableTls(allocator, "test_cert.pem", "test_key.pem");
        var tls = try Tls.init(allocator, config);
        defer tls.deinit();

        // Create a fake socket for testing
        const fake_socket: std.posix.socket_t = 42;

        // Test wrapping - in our mock implementation, this just returns the socket
        const wrapped_socket = try tls.wrapSocket(fake_socket);
        try testing.expectEqual(fake_socket, wrapped_socket);

        // Test read/write operations
        // These are mocked and just call the standard operations in our test
        var test_buf = [_]u8{0} ** 10;
        _ = tls.read(fake_socket, &test_buf) catch {};
        _ = tls.write(fake_socket, &test_buf) catch {};
    }
}
