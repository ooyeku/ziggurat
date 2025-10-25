//! Handler - Core types for request/response handling
//! Re-exports Request, Response, and provides Context wrapper

pub const Request = @import("../http/request.zig").Request;
pub const Response = @import("../http/response.zig").Response;
pub const StatusCode = @import("../http/response.zig").StatusCode;
pub const Method = @import("../http/request.zig").Method;
pub const Context = @import("context.zig").Context;

// Common status code constants for convenience
pub const status = struct {
    pub const ok = StatusCode.ok;
    pub const created = StatusCode.created;
    pub const bad_request = StatusCode.bad_request;
    pub const unauthorized = StatusCode.unauthorized;
    pub const forbidden = StatusCode.forbidden;
    pub const not_found = StatusCode.not_found;
    pub const conflict = StatusCode.conflict;
    pub const internal_server_error = StatusCode.internal_server_error;
    pub const unsupported_media_type = StatusCode.unsupported_media_type;
};

// Handler function type
pub const Handler = fn (*Context) Response;

// Middleware handler type
pub const Middleware = fn (*Context) ?Response;
