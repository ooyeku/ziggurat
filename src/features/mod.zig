//! Features - Unified configuration for all server features
//! Allows configuring logging, metrics, sessions, CORS, rate limiting, and error handling

const std = @import("std");

/// Logging configuration
pub const LoggingConfig = struct {
    enabled: bool = true,
    level: enum { debug, info, warn, err, critical } = .info,
    colors: bool = true,
    timestamp: bool = true,
};

/// Metrics configuration
pub const MetricsConfig = struct {
    enabled: bool = true,
    max_requests: usize = 1000,
};

/// Session configuration
pub const SessionConfig = struct {
    enabled: bool = true,
    ttl_seconds: u32 = 3600,
};

/// CORS configuration
pub const CorsConfig = struct {
    enabled: bool = true,
    allow_all_origins: bool = true,
    allow_credentials: bool = false,
    max_age: u32 = 3600,
};

/// Rate limiting configuration
pub const RateLimitConfig = struct {
    enabled: bool = true,
    requests_per_minute: u32 = 1000,
};

/// Error handling configuration
pub const ErrorConfig = struct {
    enabled: bool = true,
    debug: bool = false,
    show_stack_traces: bool = false,
};

/// Security headers configuration
pub const SecurityConfig = struct {
    enabled: bool = true,
    strict_transport_security: bool = true,
    content_security_policy: bool = true,
    x_frame_options: bool = true,
    x_content_type_options: bool = true,
};

/// Complete features configuration
pub const Config = struct {
    logging: LoggingConfig = .{},
    metrics: MetricsConfig = .{},
    session: SessionConfig = .{},
    cors: CorsConfig = .{},
    rate_limit: RateLimitConfig = .{},
    errors: ErrorConfig = .{},
    security: SecurityConfig = .{},

    pub fn init() Config {
        return .{};
    }

    pub fn withLogging(self: *Config, cfg: LoggingConfig) *Config {
        self.logging = cfg;
        return self;
    }

    pub fn withMetrics(self: *Config, cfg: MetricsConfig) *Config {
        self.metrics = cfg;
        return self;
    }

    pub fn withSession(self: *Config, cfg: SessionConfig) *Config {
        self.session = cfg;
        return self;
    }

    pub fn withCors(self: *Config, cfg: CorsConfig) *Config {
        self.cors = cfg;
        return self;
    }

    pub fn withRateLimit(self: *Config, cfg: RateLimitConfig) *Config {
        self.rate_limit = cfg;
        return self;
    }

    pub fn withErrors(self: *Config, cfg: ErrorConfig) *Config {
        self.errors = cfg;
        return self;
    }

    pub fn withSecurity(self: *Config, cfg: SecurityConfig) *Config {
        self.security = cfg;
        return self;
    }
};

/// Initialize all enabled features
pub fn initialize(allocator: std.mem.Allocator, config: Config) !void {
    const logger_mod = @import("../utils/logging.zig");
    const metrics_mod = @import("../metrics.zig");
    const error_handler_mod = @import("../error/error_handler.zig");
    const cors_mod = @import("../middleware/cors.zig");
    const session_mod = @import("../middleware/session.zig");

    // Initialize logging
    if (config.logging.enabled) {
        try logger_mod.initGlobalLogger(allocator);
        if (logger_mod.getGlobalLogger()) |logger| {
            logger.setLogLevel(switch (config.logging.level) {
                .debug => .debug,
                .info => .info,
                .warn => .warn,
                .err => .err,
                .critical => .critical,
            });
            logger.setEnableColors(config.logging.colors);
            logger.setEnableTimestamp(config.logging.timestamp);
        }
    }

    // Initialize metrics
    if (config.metrics.enabled) {
        try metrics_mod.initGlobalMetrics(allocator, config.metrics.max_requests);
    }

    // Initialize error handler
    if (config.errors.enabled) {
        try error_handler_mod.initGlobalErrorHandler(allocator, config.errors.debug);
    }

    // Initialize CORS
    if (config.cors.enabled) {
        try cors_mod.initGlobalCorsConfig(allocator);
    }

    // Initialize sessions
    if (config.session.enabled) {
        try session_mod.initGlobalSessionManager(allocator, config.session.ttl_seconds);
    }

    // Note: Rate limiter requires manual initialization per instance
    // See security.rate_limiter module for details
}

/// Deinitialize all features
pub fn deinitialize() void {
    const metrics_mod = @import("../metrics.zig");
    const error_handler_mod = @import("../error/error_handler.zig");
    const cors_mod = @import("../middleware/cors.zig");
    const session_mod = @import("../middleware/session.zig");

    metrics_mod.deinitGlobalMetrics();
    error_handler_mod.deinitGlobalErrorHandler();
    cors_mod.deinitGlobalCorsConfig();
    session_mod.deinitGlobalSessionManager();
}
