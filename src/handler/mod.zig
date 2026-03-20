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
    pub const no_content = StatusCode.no_content;
    pub const bad_request = StatusCode.bad_request;
    pub const unauthorized = StatusCode.unauthorized;
    pub const forbidden = StatusCode.forbidden;
    pub const not_found = StatusCode.not_found;
    pub const method_not_allowed = StatusCode.method_not_allowed;
    pub const conflict = StatusCode.conflict;
    pub const unsupported_media_type = StatusCode.unsupported_media_type;
    pub const unprocessable_entity = StatusCode.unprocessable_entity;
    pub const too_many_requests = StatusCode.too_many_requests;
    pub const internal_server_error = StatusCode.internal_server_error;
    pub const service_unavailable = StatusCode.service_unavailable;
};

// Handler function type
pub const Handler = fn (*Context) Response;

// Middleware handler type
pub const Middleware = fn (*Context) ?Response;
