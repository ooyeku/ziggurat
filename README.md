# Ziggurat

A modern, lightweight HTTP server framework for Zig that prioritizes performance, safety, and developer experience.

[Zig 0.15.1](https://ziglang.org) | [MIT License](LICENSE)


## Quick Start

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    try ziggurat.logging.initGlobalLogger(allocator);
    
    // Initialize metrics
    try ziggurat.metrics.initGlobalMetrics(allocator, 1000); // Keep last 1000 requests
    defer ziggurat.metrics.deinitGlobalMetrics();

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8080)
        .readTimeout(5000)
        .writeTimeout(5000)
        .build();
    defer server.deinit();

    try server.get("/", handleRoot);
    try server.start();
}

fn handleRoot(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.text("Hello, World!");
}
```

## HTTPS Example

To enable TLS/HTTPS in your server:

```zig
var server = try builder
    .host("127.0.0.1")
    .port(443)
    .enableTls("path/to/cert.pem", "path/to/key.pem")
    .build();
```

## Examples

1. Todo API - A RESTful API example with JSON handling

   ```bash
   zig build run-ex1
   ```

2. Static File Server - File serving with caching and security

   ```bash
   zig build run-ex2
   ```

## Documentation

- [Usage Guide](docs/usage.md): Comprehensive guide to using Ziggurat
- [API Reference](docs/usage.md#api-reference): Detailed API documentation
- [Examples](examples/): Example applications and use cases

## Requirements

- Zig 0.15.1 or later

## Installation

See [Usage Guide](docs/usage.md#installation) for more details.

## Contributing

Contributions are welcome. Please submit pull requests following the project's code style and including appropriate tests.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

