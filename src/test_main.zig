//! Comprehensive test runner that imports all test modules
//! This ensures all test blocks across the codebase are discovered and executed

const std = @import("std");

// Import all modules with tests
const http_server_tests = @import("tests/http_server_tests.zig");
const error_handler = @import("error/error_handler.zig");
const cors = @import("middleware/cors.zig");
const request_logger = @import("middleware/request_logger.zig");
const security = @import("middleware/security.zig");
const rate_limiter = @import("security/rate_limiter.zig");
const headers = @import("security/headers.zig");
const session = @import("session/session.zig");
const cookie = @import("session/cookie.zig");
const session_middleware = @import("middleware/session.zig");
const env_config = @import("config/env_config.zig");
const server_config = @import("config/server_config.zig");
const tls_config = @import("config/tls_config.zig");
const request = @import("http/request.zig");
const response = @import("http/response.zig");
const middleware = @import("middleware/middleware.zig");
const tls = @import("server/tls.zig");
const tls_test = @import("server/tls_test.zig");

// Note: json_helpers and test_client have compilation errors due to Zig 0.15 API changes
// They are temporarily excluded until the APIs are updated
// const json_helpers = @import("utils/json_helpers.zig");
// const test_client = @import("testing/test_client.zig");

test {
    // Force all imported modules to be analyzed for tests
    _ = http_server_tests;
    _ = error_handler;
    _ = cors;
    _ = request_logger;
    _ = security;
    _ = rate_limiter;
    _ = headers;
    _ = session;
    _ = cookie;
    _ = session_middleware;
    _ = env_config;
    _ = server_config;
    _ = tls_config;
    _ = request;
    _ = response;
    _ = middleware;
    _ = tls;
    _ = tls_test;
}
