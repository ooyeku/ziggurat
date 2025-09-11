// Main entry point for all ziggurat tests
const std = @import("std");

// Import tests from various modules
const http_server_tests = @import("tests/http_server_tests.zig");

// Add more test imports here as the project grows
// const other_tests = @import("tests/other_tests.zig");

test {
    // Reference all tests from imported modules
    std.testing.refAllDeclsRecursive(http_server_tests);
}
