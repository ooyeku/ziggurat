const Response = @import("../http/response.zig").Response;
const StatusCode = @import("../http/response.zig").StatusCode;

pub const HttpError = error{
    InvalidRequest,
    RequestTimeout,
    PayloadTooLarge,
    HeadersTooLarge,
    UnsupportedMediaType,
    InternalServerError,
    NotFound,
    MethodNotAllowed,
    // Add more specific error types
};

pub fn errorToResponse(err: HttpError) Response {
    return switch (err) {
        .InvalidRequest => Response.init(
            StatusCode.bad_request,
            "text/plain",
            "Invalid Request",
        ),
        .RequestTimeout => Response.init(
            StatusCode.request_timeout,
            "text/plain",
            "Request Timeout",
        ),
        .PayloadTooLarge => Response.init(
            StatusCode.payload_too_large,
            "text/plain",
            "Payload Too Large",
        ),
        .HeadersTooLarge => Response.init(
            StatusCode.request_header_fields_too_large,
            "text/plain",
            "Headers Too Large",
        ),
        .UnsupportedMediaType => Response.init(
            StatusCode.unsupported_media_type,
            "text/plain",
            "Unsupported Media Type",
        ),
        .InternalServerError => Response.init(
            StatusCode.internal_server_error,
            "text/plain",
            "Internal Server Error",
        ),
        .NotFound => Response.init(
            StatusCode.not_found,
            "text/plain",
            "Not Found",
        ),
        .MethodNotAllowed => Response.init(
            StatusCode.method_not_allowed,
            "text/plain",
            "Method Not Allowed",
        ),
    };
}
