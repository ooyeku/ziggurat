# Ziggurat

A lightweight HTTP server framework for Zig. Version is defined in `build.zig.zon` (single source of truth) and exposed as `ziggurat.version` at compile time. No external dependencies — pure Zig standard library.

## Build Commands

```bash
zig build              # Build library and examples
zig build run          # Run todo-api example (ex1)
zig build run-ex1      # Run todo-api example
zig build run-ex2      # Run static-server example
zig build test         # Run all tests (156 tests)
```

**Zig version required:** 0.15.1 or later

## Project Structure

```
src/
  root.zig              # Public API entry point (Server, ServerBuilder, helpers)
  log.zig               # Simplified logging interface
  metrics.zig           # Request metrics and performance tracking
  test_main.zig         # Test suite entry point (imports all test modules)
  server/
    http_server.zig     # Core HTTP server (thread pool, keep-alive, graceful shutdown)
    tls.zig             # TLS stub (config only, no encryption — use a reverse proxy)
    tls_test.zig        # TLS tests
  router/
    router.zig          # Route matching, path params, 405 support
  http/
    request.zig         # HTTP request (parse, query string, user data)
    response.zig        # HTTP response (status codes, extra headers, format)
  handler/
    mod.zig             # Handler module re-exports and status constants
    context.zig         # Handler context wrapper
  middleware/
    middleware.zig      # Middleware pipeline system
    request_logger.zig  # Built-in request logging
    cors.zig            # CORS preflight + header injection (zero-alloc middleware)
    session.zig         # Session management middleware
    security.zig        # Security headers middleware
  config/
    server_config.zig   # Server configuration
    tls_config.zig      # TLS configuration
    env_config.zig      # Environment variable parsing
  security/
    rate_limiter.zig    # Token bucket rate limiting
    headers.zig         # Security header utilities
  session/
    session.zig         # Session storage
    cookie.zig          # Cookie management
  error/
    error_handler.zig   # Global error handling
    http_error.zig      # HTTP error types and response mapping
  features/
    mod.zig             # Unified feature config
  utils/
    logging.zig         # Global logger (thread-safe, colored output)
    json_helpers.zig    # JSON serialization, form parsing, URL decode, content type
  testing/
    test_client.zig     # TestRequestBuilder and ResponseAssertions
  tests/
    http_server_tests.zig # Integration tests
examples/
  ex1/                  # Todo REST API example
  ex2/                  # Static file server example
docs/
  usage.md              # Usage guide
  api-reference.md      # API documentation
```

## Server Setup Pattern

```zig
const ziggurat = @import("ziggurat");

try ziggurat.features.initialize(allocator, .{
    .logging = .{ .level = .info },
    .metrics = .{ .max_requests = 1000 },
});
defer ziggurat.features.deinitialize();

var builder = ziggurat.ServerBuilder.init(allocator);
var server = try builder
    .host("0.0.0.0")
    .port(3000)
    .threadPoolSize(16)
    .maxConnections(256)
    .keepAliveTimeout(15000)
    .build();
defer server.deinit();

try server.useMiddleware(ziggurat.request_logger.requestLoggingMiddleware);
try server.useMiddleware(ziggurat.cors.corsMiddleware);
try server.get("/users/:id", handleGetUser);
try server.post("/users", handleCreateUser);
try server.start();
```

**Note:** Builder methods mutate `self` and return `*ServerBuilder`. Keep the builder in a `var` binding — do not chain from `ServerBuilder.init(allocator)` directly.

## Key Conventions

- **Memory**: Pass allocators explicitly. Use `defer deinit()` for cleanup. The server uses arena allocators per connection, reset between keep-alive requests.
- **Threading**: Fixed thread pool (default 32 workers) with a bounded connection queue (default 512). Rejects with 503 when full.
- **Keep-alive**: Enabled by default. Connections are reused for up to 100 requests or 15s idle. Respects `Connection: close` from clients.
- **Shutdown**: Call `server.stop()` from another thread. Active connections drain for up to 30s before `start()` returns.
- **Middleware**: Return `null` to continue the pipeline; return a `Response` to short-circuit.
- **Routing**: Path params use `:param` syntax. Wildcards use `/prefix/*`. Unmatched methods return 405.
- **CORS**: Headers are pre-built at init time. The middleware path allocates nothing.
- **Global state**: Logger, metrics, session manager, CORS config, and rate limiter are global singletons initialized once at startup.
- **TLS**: Stub only — config is validated but no encryption is applied. Terminate TLS at a reverse proxy.
- **Response headers**: Use `.withHeaders(&.{"Name: Value"})` to attach extra headers.
- **Query strings**: Parsed at request time; access via `request.getQuery("key")`.
- **User data**: `setUserData` accepts strings, integers, bools. `getUserData` casts back to the requested type.
- **Version**: Sourced from `build.zig.zon`, piped via build options, accessible as `ziggurat.version`.
- **Zig 0.15 patterns**: ArrayList is unmanaged (allocator passed to each method). JSON uses `std.json.parseFromSlice` for deserialization.

## Testing

Tests are in `src/test_main.zig` which imports all test modules (156 tests). Run with `zig build test`.

If you get stale cache errors, clear with `rm -rf .zig-cache` before building.
