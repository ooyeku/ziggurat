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
        HttpError.InvalidRequest => Response.init(
            .bad_request,
            "text/plain",
            "Invalid Request",
        ),
        HttpError.RequestTimeout => Response.init(
            .request_timeout,
            "text/plain",
            "Request Timeout",
        ),
        HttpError.PayloadTooLarge => Response.init(
            .payload_too_large,
            "text/plain",
            "Payload Too Large",
        ),
        HttpError.HeadersTooLarge => Response.init(
            .request_header_fields_too_large,
            "text/plain",
            "Headers Too Large",
        ),
        HttpError.UnsupportedMediaType => Response.init(
            .unsupported_media_type,
            "text/plain",
            "Unsupported Media Type",
        ),
        HttpError.InternalServerError => Response.init(
            .internal_server_error,
            "text/plain",
            "Internal Server Error",
        ),
        HttpError.NotFound => Response.init(
            .not_found,
            "text/plain",
            "Not Found",
        ),
        HttpError.MethodNotAllowed => Response.init(
            .method_not_allowed,
            "text/plain",
            "Method Not Allowed",
        ),
    };
}
