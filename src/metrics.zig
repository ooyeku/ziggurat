const std = @import("std");
const http = struct {
    pub const Request = @import("http/request.zig").Request;
    pub const Response = @import("http/response.zig").Response;
};
const logging = @import("utils/logging.zig");

/// Represents timing information for a single request
pub const RequestMetric = struct {
    path: []const u8,
    method: []const u8,
    start_time: i64,
    duration_ms: i64,
    status_code: u16,

    pub fn init(path: []const u8, method: []const u8, status_code: u16) RequestMetric {
        return .{
            .path = path,
            .method = method,
            .start_time = std.time.milliTimestamp(),
            .duration_ms = 0,
            .status_code = status_code,
        };
    }

    pub fn complete(self: *RequestMetric) void {
        const end_time = std.time.milliTimestamp();
        self.duration_ms = end_time - self.start_time;
    }
};

/// Stores aggregate statistics for a specific endpoint
pub const EndpointStats = struct {
    total_requests: u64 = 0,
    total_duration_ms: i64 = 0,
    min_duration_ms: i64 = std.math.maxInt(i64),
    max_duration_ms: i64 = 0,

    pub fn update(self: *EndpointStats, duration_ms: i64) void {
        self.total_requests += 1;
        self.total_duration_ms += duration_ms;
        self.min_duration_ms = @min(self.min_duration_ms, duration_ms);
        self.max_duration_ms = @max(self.max_duration_ms, duration_ms);
    }

    pub fn getAverageDuration(self: EndpointStats) f64 {
        if (self.total_requests == 0) return 0;
        return @as(f64, @floatFromInt(self.total_duration_ms)) / @as(f64, @floatFromInt(self.total_requests));
    }

    pub fn clone(self: EndpointStats) EndpointStats {
        return .{
            .total_requests = self.total_requests,
            .total_duration_ms = self.total_duration_ms,
            .min_duration_ms = self.min_duration_ms,
            .max_duration_ms = self.max_duration_ms,
        };
    }
};

/// Global metrics manager that tracks all request metrics
pub const MetricsManager = struct {
    allocator: std.mem.Allocator,
    metrics_mutex: std.Thread.Mutex,
    endpoint_stats: std.StringHashMap(EndpointStats),
    recent_requests: std.ArrayList(RequestMetric),
    max_recent_requests: usize,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, max_recent_requests: usize) !*Self {
        const self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .metrics_mutex = .{},
            .endpoint_stats = std.StringHashMap(EndpointStats).init(allocator),
            .recent_requests = std.ArrayList(RequestMetric).init(allocator),
            .max_recent_requests = max_recent_requests,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        var it = self.endpoint_stats.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.endpoint_stats.deinit();
        self.recent_requests.deinit();
        self.allocator.destroy(self);
    }

    pub fn recordMetric(self: *Self, metric: RequestMetric) !void {
        // Create a copy of the path and method strings
        const path_copy = try self.allocator.dupe(u8, metric.path);
        errdefer self.allocator.free(path_copy);
        const method_copy = try self.allocator.dupe(u8, metric.method);
        errdefer self.allocator.free(method_copy);

        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ method_copy, path_copy });
        errdefer self.allocator.free(key);

        self.metrics_mutex.lock();
        defer self.metrics_mutex.unlock();

        // Update endpoint stats
        if (self.endpoint_stats.getPtr(key)) |stats| {
            stats.update(metric.duration_ms);
        } else {
            var new_stats = EndpointStats{};
            new_stats.update(metric.duration_ms);
            try self.endpoint_stats.put(key, new_stats);
        }

        // Add to recent requests
        const metric_copy = RequestMetric{
            .path = path_copy,
            .method = method_copy,
            .start_time = metric.start_time,
            .duration_ms = metric.duration_ms,
            .status_code = metric.status_code,
        };
        try self.recent_requests.append(metric_copy);

        if (self.recent_requests.items.len > self.max_recent_requests) {
            const removed = self.recent_requests.orderedRemove(0);
            self.allocator.free(removed.path);
            self.allocator.free(removed.method);
        }
    }

    pub fn getEndpointStats(self: *Self, method: []const u8, path: []const u8) !?EndpointStats {
        const key = try std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ method, path });
        defer self.allocator.free(key);

        self.metrics_mutex.lock();
        defer self.metrics_mutex.unlock();

        if (self.endpoint_stats.get(key)) |stats| {
            return stats.clone();
        }
        return null;
    }

    pub fn getRecentRequests(self: *Self) []const RequestMetric {
        self.metrics_mutex.lock();
        defer self.metrics_mutex.unlock();

        return self.recent_requests.items;
    }

    pub fn printStats(self: *Self, writer: anytype) !void {
        self.metrics_mutex.lock();
        defer self.metrics_mutex.unlock();

        try writer.writeAll("\n=== Request Metrics ===\n");
        var it = self.endpoint_stats.iterator();
        while (it.next()) |entry| {
            const stats = entry.value_ptr.*;
            try writer.print("{s}:\n", .{entry.key_ptr.*});
            try writer.print("  Total Requests: {d}\n", .{stats.total_requests});
            try writer.print("  Avg Duration: {d:.2}ms\n", .{stats.getAverageDuration()});
            try writer.print("  Min Duration: {d}ms\n", .{stats.min_duration_ms});
            try writer.print("  Max Duration: {d}ms\n", .{stats.max_duration_ms});
            try writer.writeAll("\n");
        }
    }
};

/// Global metrics manager instance
var global_metrics_manager: ?*MetricsManager = null;

/// Initialize the global metrics manager
pub fn initGlobalMetrics(allocator: std.mem.Allocator, max_recent_requests: usize) !void {
    if (global_metrics_manager != null) return error.AlreadyInitialized;
    global_metrics_manager = try MetricsManager.init(allocator, max_recent_requests);
}

/// Get the global metrics manager
pub fn getGlobalMetrics() ?*MetricsManager {
    return global_metrics_manager;
}

/// Deinitialize the global metrics manager
pub fn deinitGlobalMetrics() void {
    if (global_metrics_manager) |manager| {
        manager.deinit();
        global_metrics_manager = null;
    }
}

/// Middleware function for recording request metrics
pub fn metricsMiddleware(request: *http.Request) ?http.Response {
    if (global_metrics_manager) |_| {
        const metric = RequestMetric.init(
            request.path,
            @tagName(request.method),
            200, // Status code will be updated after response
        );

        request.setUserData("metric_time", metric.start_time) catch {};
        request.setUserData("metric_path", request.path) catch {};
        request.setUserData("metric_method", @tagName(request.method)) catch {};
    }
    return null;
}

/// Function to be called at the start of request processing
pub fn startRequestMetrics(request: *http.Request) !void {
    if (global_metrics_manager) |_| {
        const metric = RequestMetric.init(
            request.path,
            @tagName(request.method),
            200, // Status code will be updated after response
        );

        try request.setUserData("metric_time", metric.start_time);
        try request.setUserData("metric_path", request.path);
        try request.setUserData("metric_method", @tagName(request.method));
    }
}

/// Function to be called after response is sent
pub fn recordResponseMetrics(request: *http.Request, response: *const http.Response) !void {
    if (global_metrics_manager) |manager| {
        // Extract stored metrics data
        const start_time = request.getUserData("metric_time", i64) orelse {
            // If missing, create a new metric with current time
            const metric = RequestMetric.init(request.path, @tagName(request.method), @intFromEnum(response.status));
            try manager.recordMetric(metric);
            return;
        };

        const path = request.getUserData("metric_path", []const u8) orelse request.path;
        const method = request.getUserData("metric_method", []const u8) orelse @tagName(request.method);

        var metric = RequestMetric{
            .path = path,
            .method = method,
            .start_time = start_time,
            .duration_ms = 0,
            .status_code = @intFromEnum(response.status),
        };

        // Calculate duration
        metric.complete();

        // Record the metric
        try manager.recordMetric(metric);
    }
}
