// Main entry point for all ziggurat tests
const std = @import("std");

// Import tests from various modules
pub usingnamespace @import("tests/http_server_tests.zig");

// Add more test imports here as the project grows
// pub usingnamespace @import("tests/other_tests.zig");

test {
    // Reference all tests from imported modules
    std.testing.refAllDeclsRecursive(@This());
}
