# Ziggurat

A modern, lightweight HTTP server framework for Zig that prioritizes performance, safety, and developer experience. Version 1.2.0.

[Zig 0.15.1](https://ziglang.org) | [MIT License](LICENSE)

## Features

- **Thread-per-connection** concurrency with arena allocators per request
- **Router** with path parameters (`:id`) and wildcard matching (`/*`)
- **Middleware pipeline** with short-circuit support
- **CORS**, **rate limiting**, **session management**, and **security headers** built in
- **TLS/HTTPS** support
- **JSON serialization** helpers
- **Metrics** and **logging** subsystems
- **Query string** parsing at request time
- **Custom response headers** via builder pattern
- **Graceful shutdown** with `server.stop()`
- No external dependencies — pure Zig standard library

## Quick Start

### New API (Recommended)

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize features in one call
    try ziggurat.features.initialize(allocator, .{
        .logging = .{ .level = .info },
        .metrics = .{ .max_requests = 1000 },
    });
    defer ziggurat.features.deinitialize();

    // Build and start server
    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("0.0.0.0")
        .port(3000)
        .readTimeout(5000)
        .writeTimeout(5000)
        .build();
    defer server.deinit();

    try server.get("/", handleRoot);
    try server.get("/users/:id", handleUser);
    try server.start();
}

fn handleRoot(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.json("{\"status\":\"ok\"}");
}

fn handleUser(request: *ziggurat.request.Request) ziggurat.response.Response {
    const id = request.getParam("id") orelse "unknown";
    _ = id;
    return ziggurat.json("{\"user\":\"found\"}");
}
```

### Classic API

```zig
// Initialize logger and metrics separately
try ziggurat.logger.initGlobalLogger(allocator);
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
defer ziggurat.metrics.deinitGlobalMetrics();
```

## HTTPS

```zig
var builder = ziggurat.ServerBuilder.init(allocator);
var server = try builder
    .host("0.0.0.0")
    .port(443)
    .enableTls("cert.pem", "key.pem")
    .build();
```

## HTTP Methods

```zig
try server.get("/path", handler);
try server.post("/path", handler);
try server.put("/path", handler);
try server.delete("/path", handler);
try server.patch("/path", handler);
try server.head("/path", handler);
```

## Middleware

```zig
try server.useMiddleware(ziggurat.request_logger.requestLoggingMiddleware);
try server.useMiddleware(ziggurat.cors.corsMiddleware);
try server.useMiddleware(ziggurat.security.rate_limiter.rateLimitMiddleware);
```

Middleware returns `null` to continue the pipeline or a `Response` to short-circuit.

## Response Helpers

```zig
return ziggurat.json("{\"key\":\"value\"}");
return ziggurat.text("Hello, World!");
return ziggurat.errorResponse(.not_found, "Not found");

// Builder pattern
return ziggurat.response.Response.json(data)
    .withStatus(.created)
    .withHeaders(&.{"X-Custom: value"});
```

## Examples

1. **Todo API** — RESTful API with JSON handling
   ```bash
   zig build run-ex1
   ```

2. **Static File Server** — File serving with caching and security
   ```bash
   zig build run-ex2
   ```

## Building & Testing

```bash
zig build              # Build library and examples
zig build test         # Run all tests (153 tests)
zig build run-ex1      # Run todo-api example
zig build run-ex2      # Run static-server example
```

## Requirements

- Zig 0.15.1 or later

## Installation

See [Usage Guide](docs/usage.md#installation) for details.

## Documentation

- [Usage Guide](docs/usage.md) — Comprehensive guide to using Ziggurat
- [API Reference](docs/api-reference.md) — Detailed API documentation
- [Examples](examples/) — Example applications and use cases

## Contributing

Contributions are welcome. Please submit pull requests following the project's code style and including appropriate tests.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
