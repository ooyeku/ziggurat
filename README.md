# Ziggurat 🏛️

A modern, lightweight HTTP server framework for Zig that prioritizes performance, safety, and developer experience.

[![Zig](https://img.shields.io/badge/Zig-0.14.0-orange.svg)](https://ziglang.org)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## Features

- 🚀 **Fast and Efficient**: Built with Zig's performance-first mindset
- 🛡️ **Type-Safe API**: Leverage Zig's compile-time features for robust applications
- 🧩 **Modular Design**: Easy-to-use middleware system
- 📝 **Built-in Logging**: Comprehensive logging system with multiple levels
- 🔄 **Request Routing**: Simple and flexible route handling
- 📦 **Static File Serving**: Efficient static file serving with caching
- ⚡ **Zero Dependencies**: Only requires Zig standard library

## Quick Start

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8080)
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

- Zig 0.14.0 or later

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

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. Make sure to read our [Contributing Guide](CONTRIBUTING.md) first.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.


