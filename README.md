# Ziggurat

A modern, lightweight HTTP server framework for Zig that prioritizes performance, safety, and developer experience.

[![Zig](https://img.shields.io/badge/Zig-0.14.0-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- **Fast and Efficient**: Built with Zig's performance-first mindset
- **Type-Safe API**: Leverage Zig's compile-time features for robust applications
- **Modular Design**: Easy-to-use middleware system
- **Built-in Logging**: Comprehensive logging system with multiple levels
- **Request Routing**: Simple and flexible route handling
- **Static File Serving**: Efficient static file serving with caching
- **TLS Support**: Secure your applications with HTTPS
- **Zero Dependencies**: Only requires Zig standard library
- **Performance Metrics**: Built-in request and endpoint performance tracking

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

1. **Todo API** - A RESTful API example with JSON handling
   ```bash
   zig build run-ex1
   ```

2. **Static File Server** - File serving with caching and security
   ```bash
   zig build run-ex2
   ```

## Documentation

- [Usage Guide](docs/usage.md) - Comprehensive guide to using Ziggurat
- [API Reference](docs/usage.md#api-reference) - Detailed API documentation
- [Examples](examples/) - Example applications and use cases

## Requirements

- Zig 0.14.0-dev.2577 or later

## Installation

Add to your `build.zig.zon`:
```zig
.{
    .dependencies = .{
        .ziggurat = .{
            .url = "https://github.com/yourusername/ziggurat/archive/refs/tags/v0.1.0.tar.gz",
            .hash = "...", // Add appropriate hash
        },
    },
}
```

Then in your `build.zig`, add Ziggurat as a module:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get the Ziggurat dependency
    const ziggurat_dep = b.dependency("ziggurat", .{
        .target = target,
        .optimize = optimize,
    });

    // Create your executable
    const exe = b.addExecutable(.{
        .name = "your-app",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // Add Ziggurat module
    exe.addModule("ziggurat", ziggurat_dep.module("ziggurat"));
    b.installArtifact(exe);
}
```

## Contributing

Contributions are welcome. Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


