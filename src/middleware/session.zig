//! Session middleware for Ziggurat
//! Provides automatic session loading and saving

const std = @import("std");
const Request = @import("../http/request.zig").Request;
const Response = @import("../http/response.zig").Response;
const Session = @import("../session/session.zig").Session;
const SessionManager = @import("../session/session.zig").SessionManager;
const Cookie = @import("../session/cookie.zig").Cookie;
const cookie = @import("../session/cookie.zig");

const SESSION_COOKIE_NAME = "SESSIONID";

/// Global session manager
var global_session_manager: ?*SessionManager = null;
var global_session_manager_allocator: ?std.mem.Allocator = null;

/// Initialize global session manager
pub fn initGlobalSessionManager(allocator: std.mem.Allocator, ttl_seconds: u32) !void {
    if (global_session_manager != null) return error.AlreadyInitialized;

    const manager = try allocator.create(SessionManager);
    manager.* = SessionManager.init(allocator, ttl_seconds);

    global_session_manager = manager;
    global_session_manager_allocator = allocator;
}

/// Get global session manager
pub fn getGlobalSessionManager() ?*SessionManager {
    return global_session_manager;
}

/// Deinitialize global session manager
pub fn deinitGlobalSessionManager() void {
    if (global_session_manager) |manager| {
        manager.deinit();
        if (global_session_manager_allocator) |alloc| {
            alloc.destroy(manager);
        }
    }
    global_session_manager = null;
    global_session_manager_allocator = null;
}

/// Session middleware - loads session from cookie
pub fn sessionMiddleware(request: *Request) ?Response {
    if (global_session_manager) |manager| {
        var session_id: ?[]const u8 = null;

        // Try to get session ID from cookie
        if (request.headers.get("Cookie")) |cookie_header| {
            session_id = cookie.getSessionCookie(request.allocator, cookie_header, SESSION_COOKIE_NAME);
        }

        if (session_id) |id| {
            if (manager.getSession(id)) |_| {
                // Store session reference in user_data
                request.setUserData("_session_id", id) catch {};
                request.setUserData("_session", id) catch {}; // Store session reference
                return null;
            }

            // Session not found or expired, create new one
            if (manager.createSession()) |new_id| {
                request.setUserData("_session_id", new_id) catch {};
                return null;
            } else |_| {}
        } else {
            // No session cookie, create new session
            if (manager.createSession()) |new_id| {
                request.setUserData("_session_id", new_id) catch {};
                return null;
            } else |_| {}
        }
    }

    return null;
}

/// Get session from request
pub fn getSession(request: *Request) ?*Session {
    if (global_session_manager) |manager| {
        if (request.getUserData("_session_id", []const u8)) |session_id| {
            return manager.getSession(session_id);
        }
    }
    return null;
}

/// Set session value in current session
pub fn setSessionValue(request: *Request, key: []const u8, value: []const u8) !void {
    if (getSession(request)) |session| {
        try session.setValue(key, value);
    }
}

/// Get session value from current session
pub fn getSessionValue(request: *Request, key: []const u8) ?[]const u8 {
    if (getSession(request)) |session| {
        return session.getValue(key);
    }
    return null;
}

/// Generate Set-Cookie header for session
pub fn getSetCookieHeader(request: *Request) !?[]const u8 {
    if (request.getUserData("_session_id", []const u8)) |session_id| {
        const cookie_obj = Cookie{
            .name = SESSION_COOKIE_NAME,
            .value = session_id,
            .path = "/",
            .http_only = true,
            .secure = false, // Should be true in production with HTTPS
            .same_site = .Strict,
        };

        return try cookie_obj.serialize(request.allocator);
    }

    return null;
}

test "session middleware initialization" {
    const allocator = std.testing.allocator;

    try initGlobalSessionManager(allocator, 3600);
    defer deinitGlobalSessionManager();

    try std.testing.expect(getGlobalSessionManager() != null);
}

test "session middleware create session" {
    const allocator = std.testing.allocator;

    try initGlobalSessionManager(allocator, 3600);
    defer deinitGlobalSessionManager();

    var request = Request.init(allocator);
    defer request.deinit();

    const result = sessionMiddleware(&request);
    try std.testing.expect(result == null);

    const session_id = request.getUserData("_session_id", []const u8);
    try std.testing.expect(session_id != null);
}

test "set and get session value" {
    const allocator = std.testing.allocator;

    try initGlobalSessionManager(allocator, 3600);
    defer deinitGlobalSessionManager();

    var request = Request.init(allocator);
    defer request.deinit();

    _ = sessionMiddleware(&request);

    try setSessionValue(&request, "user_id", "12345");

    const value = getSessionValue(&request, "user_id");
    try std.testing.expect(value != null);
    try std.testing.expectEqualStrings("12345", value.?);
}
