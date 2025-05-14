const std = @import("std");

/// TLS configuration for server
pub const TlsConfig = struct {
    /// Whether TLS is enabled
    enabled: bool = false,
    /// Path to the certificate file
    cert_file: ?[]const u8 = null,
    /// Path to the private key file
    key_file: ?[]const u8 = null,
    /// Allocator used to manage TLS resources
    allocator: ?std.mem.Allocator = null,

    /// Initialize with TLS disabled
    pub fn disabled() TlsConfig {
        return .{
            .enabled = false,
            .cert_file = null,
            .key_file = null,
        };
    }

    /// Initialize with TLS enabled
    pub fn enableTls(allocator: std.mem.Allocator, cert_path: []const u8, key_path: []const u8) TlsConfig {
        return .{
            .enabled = true,
            .cert_file = cert_path,
            .key_file = key_path,
            .allocator = allocator,
        };
    }

    /// Check if this is a valid TLS configuration
    pub fn validate(self: *const TlsConfig) !void {
        if (!self.enabled) return;

        // When TLS is enabled, both cert and key files are required
        if (self.cert_file == null) return error.MissingCertificateFile;
        if (self.key_file == null) return error.MissingKeyFile;
        if (self.allocator == null) return error.MissingAllocator;
    }
};

test "TlsConfig validation" {
    const testing = std.testing;

    // Test disabled TLS
    const disabled_config = TlsConfig.disabled();
    try testing.expect(!disabled_config.enabled);
    try disabled_config.validate();

    // Test enabled TLS with proper config
    const allocator = testing.allocator;
    const enabled_config = TlsConfig.enableTls(allocator, "cert.pem", "key.pem");
    try testing.expect(enabled_config.enabled);
    try testing.expectEqualStrings("cert.pem", enabled_config.cert_file.?);
    try testing.expectEqualStrings("key.pem", enabled_config.key_file.?);
    try enabled_config.validate();
}
