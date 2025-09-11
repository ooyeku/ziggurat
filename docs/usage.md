# Ziggurat - A Modern HTTP Server Framework for Zig

Ziggurat is a lightweight, performant HTTP server framework for Zig that makes it easy to build web applications and APIs. This guide will walk you through setting up and using Ziggurat in your projects.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Concepts](#core-concepts)
- [Performance Metrics](#performance-metrics)
- [Examples](#examples)
- [API Reference](#api-reference)

## Installation

Run the `zig fetch` command to download and verify the dependency:

```bash
zig fetch https://github.com/ooyeku/ziggurat/archive/refs/tags/v0.1.1.tar.gz
```

**Optional Method I found to work:**
Create a `src/ziggurat.zig` file and add the following:

```zig
pub const ServerBuilder = @import("ziggurat").ServerBuilder;
pub const Server = @import("ziggurat").Server;
pub const config = @import("ziggurat").config;
pub const request = @import("ziggurat").request;
pub const response = @import("ziggurat").response;
pub const middleware = @import("ziggurat").middleware;
pub const logger = @import("ziggurat").logger;
pub const metrics = @import("ziggurat").metrics;
pub const router = @import("ziggurat").router;
pub const json = @import("ziggurat").json;
pub const text = @import("ziggurat").text;
pub const errorResponse = @import("ziggurat").errorResponse;
pub const Status = @import("ziggurat").Status;
```

Then, integrate it into your `build.zig` file:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const main_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ziggurat_src_path = b.dependency("ziggurat", .{
        .target = target,
        .optimize = optimize,
    }).path("src/root.zig");

    const ziggurat_mod = b.createModule(.{
        .root_source_file = ziggurat_src_path,
        .target = target,
        .optimize = optimize,
    });

    main_mod.addImport("ziggurat", ziggurat_mod);

    const exe = b.addExecutable(.{
        .name = "ziggurat_test",
        .root_module = main_mod,
    });


    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
```

## Quick Start

Here's a minimal example to get a server up and running:

```zig
const std = @import("std");
const ziggurat = @import("ziggurat");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger
    try ziggurat.logger.initGlobalLogger(allocator);
    
    // Initialize metrics
    try ziggurat.metrics.initGlobalMetrics(allocator, 1000); // Keep last 1000 requests
    defer ziggurat.metrics.deinitGlobalMetrics();

    // Initialize the server
    var builder = ziggurat.ServerBuilder.init(allocator);
    var server = try builder
        .host("127.0.0.1")
        .port(8080)
        .readTimeout(5000)
        .writeTimeout(5000)
        .build();
    defer server.deinit();

    // Add a route
    try server.get("/", handleRoot);

    // Start the server
    try server.start();
}

fn handleRoot(request: *ziggurat.request.Request) ziggurat.response.Response {
    _ = request;
    return ziggurat.text("Hello, World!");
}
```

## Core Concepts

### Server Builder

The `ServerBuilder` provides a fluent API for configuring your server:

```zig
var builder = ziggurat.ServerBuilder.init(allocator);
var server = try builder
    .host("127.0.0.1")    // Set host address
    .port(8080)           // Set port number
    .readTimeout(5000)    // Set read timeout in milliseconds
    .writeTimeout(5000)   // Set write timeout in milliseconds
    .enableTls("cert.pem", "key.pem")  // Optional: Enable HTTPS
    .build();
```

### Request Handling

Route handlers receive a `Request` pointer and return a `Response`:

```zig
fn handleRequest(request: *ziggurat.request.Request) ziggurat.response.Response {
    // Access request properties
    const method = request.method;        // HTTP method
    const path = request.path;            // Request path
    const headers = request.headers;      // Request headers
    const body = request.body;            // Request body

    // Return a response
    return ziggurat.json("{ \"status\": \"success\" }");
}
```

### Middleware

Middleware functions can process requests before they reach route handlers:

```zig
fn logRequests(request: *ziggurat.request.Request) ?ziggurat.response.Response {
    if (ziggurat.logger.getGlobalLogger()) |logger| {
        logger.info("[{s}] {s}", .{ @tagName(request.method), request.path }) catch {};
    }
    return null; // Continue to next handler
}

// Add middleware to server
try server.middleware(logRequests);
```

### Response Helpers

Ziggurat provides helper functions for common response types:

```zig
// JSON response
return ziggurat.json(json_string);

// Text response
return ziggurat.text("Hello, World!");

// Error response
return ziggurat.errorResponse(.not_found, "Resource not found");
```

## Performance Metrics

Ziggurat includes a built-in metrics system for monitoring server performance.

### Initialization

```zig
// Initialize metrics with capacity for 1000 recent requests
try ziggurat.metrics.initGlobalMetrics(allocator, 1000);
defer ziggurat.metrics.deinitGlobalMetrics();
```

### Tracking Request Metrics

The metrics system automatically tracks:

- Request duration
- Status codes
- Endpoint-specific statistics
- Request timestamps

### Accessing Metrics

```zig
// Get aggregate stats for a specific endpoint
if (ziggurat.metrics.getGlobalMetrics()) |manager| {
    const stats = try manager.getEndpointStats("GET", "/api/users");
    if (stats) |s| {
        // Get the average response time for an endpoint
        const avg_ms = s.getAverageDuration();
    }
}

// Access recent request data
if (ziggurat.metrics.getGlobalMetrics()) |manager| {
    const recent_requests = manager.getRecentRequests(); // Get all recent requests
}
```

### Metrics Endpoints

You can add a built-in metrics endpoint to your server:

```zig
// Add metrics endpoint (you would need to implement this handler)
// try server.get("/metrics", handleMetricsRequest);
```

## Examples

### 1. Todo API Server

See [examples/ex1](examples/ex1) for a complete example of building a RESTful Todo API.

Key features demonstrated:

- Route handling
- JSON responses
- Request logging
- Error handling
- In-memory data storage

Run with:

```bash
zig build run-ex1
```

### 2. Static File Server

See [examples/ex2](examples/ex2) for a complete example of serving static files.

Key features demonstrated:

- Static file serving
- Content type detection
- File caching
- Path security
- Custom middleware

Run with:

```bash
zig build run-ex2
```

## API Reference

### Server Configuration

```zig
const ServerConfig = struct {
    host: []const u8,
    port: u16,
    read_timeout_ms: u32,
    write_timeout_ms: u32,
    backlog: u31,
    buffer_size: usize,
    enable_tls: bool,
    cert_path: ?[]const u8,
    key_path: ?[]const u8,
};
```

### HTTP Methods

Available HTTP methods:

- GET
- POST
- PUT
- DELETE

### Status Codes

Common status codes available via `ziggurat.Status`:

- `.ok` (200)
- `.created` (201)
- `.bad_request` (400)
- `.unauthorized` (401)
- `.forbidden` (403)
- `.not_found` (404)
- `.internal_server_error` (500)
- `.unsupported_media_type` (415)

### Logging

Ziggurat provides a built-in logging system with multiple levels:

- debug
- info
- warn
- err
- critical

```zig
// Initialize logger
try ziggurat.logger.initGlobalLogger(allocator);
const logger = ziggurat.logger.getGlobalLogger().?;

// Log messages
try logger.info("Server starting...", .{});
try logger.debug("Debug message: {s}", .{some_value});
```