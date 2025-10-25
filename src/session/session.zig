//! Session management for Ziggurat
//! Provides in-memory session storage with automatic expiration

const std = @import("std");
const testing = std.testing;

/// Session data storage
pub const Session = struct {
    id: []const u8,
    data: std.StringHashMap([]const u8),
    created_at: i64,
    expires_at: i64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, id: []const u8, ttl_seconds: u32) Session {
        const now = std.time.timestamp();
        return .{
            .id = id,
            .data = std.StringHashMap([]const u8).init(allocator),
            .created_at = now,
            .expires_at = now + ttl_seconds,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Session) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    pub fn isExpired(self: *Session) bool {
        const now = std.time.timestamp();
        return now > self.expires_at;
    }

    pub fn setValue(self: *Session, key: []const u8, value: []const u8) !void {
        // Check if key already exists and remove old entry
        if (self.data.fetchRemove(key)) |old_entry| {
            self.allocator.free(old_entry.key);
            self.allocator.free(old_entry.value);
        }

        const key_copy = try self.allocator.dupe(u8, key);
        errdefer self.allocator.free(key_copy);

        const value_copy = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_copy);

        try self.data.put(key_copy, value_copy);
    }

    pub fn getValue(self: *Session, key: []const u8) ?[]const u8 {
        return self.data.get(key);
    }

    pub fn removeValue(self: *Session, key: []const u8) void {
        if (self.data.fetchRemove(key)) |entry| {
            self.allocator.free(entry.key);
            self.allocator.free(entry.value);
        }
    }
};

/// Session manager
pub const SessionManager = struct {
    sessions: std.StringHashMap(Session),
    allocator: std.mem.Allocator,
    ttl_seconds: u32,
    mutex: std.Thread.Mutex = .{},

    pub fn init(allocator: std.mem.Allocator, ttl_seconds: u32) SessionManager {
        return .{
            .sessions = std.StringHashMap(Session).init(allocator),
            .allocator = allocator,
            .ttl_seconds = ttl_seconds,
        };
    }

    pub fn deinit(self: *SessionManager) void {
        var it = self.sessions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.deinit();
        }
        self.sessions.deinit();
    }

    /// Create a new session with a random ID
    pub fn createSession(self: *SessionManager) ![]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const id = try generateSessionId(self.allocator);
        const session = Session.init(self.allocator, id, self.ttl_seconds);

        try self.sessions.put(id, session);
        return id;
    }

    /// Get an existing session
    pub fn getSession(self: *SessionManager, id: []const u8) ?*Session {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.getPtr(id)) |session| {
            if (!session.isExpired()) {
                return session;
            } else {
                // Clean up expired session
                if (self.sessions.fetchRemove(id)) |entry| {
                    self.allocator.free(entry.key);
                    var mutable_session = entry.value;
                    mutable_session.deinit();
                }
            }
        }

        return null;
    }

    /// Delete a session
    pub fn deleteSession(self: *SessionManager, id: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        if (self.sessions.fetchRemove(id)) |entry| {
            self.allocator.free(entry.key);
            var mutable_session = entry.value;
            mutable_session.deinit();
        }
    }

    /// Clean up all expired sessions
    pub fn cleanupExpired(self: *SessionManager) void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var keys_to_remove: [256][]const u8 = undefined;
        var remove_count: usize = 0;

        // First pass: identify expired sessions
        var it = self.sessions.keyIterator();
        while (it.next()) |key| {
            if (self.sessions.get(key.*)) |session| {
                if (std.time.timestamp() > session.expires_at) {
                    if (remove_count < 256) {
                        keys_to_remove[remove_count] = key.*;
                        remove_count += 1;
                    }
                }
            }
        }

        // Second pass: remove expired sessions
        for (keys_to_remove[0..remove_count]) |key| {
            if (self.sessions.fetchRemove(key)) |entry| {
                self.allocator.free(entry.key);
                var mutable_session = entry.value;
                mutable_session.deinit();
            }
        }
    }
};

/// Counter for generating unique session IDs
var session_id_counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

/// Generate a random session ID
fn generateSessionId(allocator: std.mem.Allocator) ![]const u8 {
    var buffer: [32]u8 = undefined;

    // Use timestamp + counter to ensure uniqueness even in rapid succession
    const timestamp = std.time.milliTimestamp();
    const counter = session_id_counter.fetchAdd(1, .monotonic);
    const seed: u64 = @as(u64, @bitCast(timestamp)) +% counter;
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    for (&buffer) |*byte| {
        byte.* = "0123456789abcdef"[rand.intRangeAtMost(u8, 0, 15)];
    }

    return try allocator.dupe(u8, &buffer);
}

test "session init and expiration" {
    const allocator = testing.allocator;
    var session = Session.init(allocator, "test-id", 1);
    defer session.deinit();

    try testing.expect(!session.isExpired());

    // Manually set expiration to past
    session.expires_at = std.time.timestamp() - 1;
    try testing.expect(session.isExpired());
}

test "session value storage" {
    const allocator = testing.allocator;
    var session = Session.init(allocator, "test-id", 3600);
    defer session.deinit();

    try session.setValue("key1", "value1");
    try testing.expectEqualStrings("value1", session.getValue("key1") orelse "");

    session.removeValue("key1");
    try testing.expect(session.getValue("key1") == null);
}

test "session manager create and get" {
    const allocator = testing.allocator;
    var manager = SessionManager.init(allocator, 3600);
    defer manager.deinit();

    const session_id = try manager.createSession();
    const session = manager.getSession(session_id);
    try testing.expect(session != null);
}

test "session manager cleanup" {
    const allocator = testing.allocator;
    var manager = SessionManager.init(allocator, 1);
    defer manager.deinit();

    const session_id = try manager.createSession();
    manager.cleanupExpired();

    // Session should still be there (not expired yet)
    try testing.expect(manager.getSession(session_id) != null);
}

test "session multiple values" {
    const allocator = testing.allocator;
    var session = Session.init(allocator, "test-id", 3600);
    defer session.deinit();

    try session.setValue("key1", "value1");
    try session.setValue("key2", "value2");
    try session.setValue("key3", "value3");

    try testing.expectEqualStrings("value1", session.getValue("key1") orelse "");
    try testing.expectEqualStrings("value2", session.getValue("key2") orelse "");
    try testing.expectEqualStrings("value3", session.getValue("key3") orelse "");
}

test "session update value" {
    const allocator = testing.allocator;
    var session = Session.init(allocator, "test-id", 3600);
    defer session.deinit();

    try session.setValue("key", "initial");
    try testing.expectEqualStrings("initial", session.getValue("key") orelse "");

    try session.setValue("key", "updated");
    try testing.expectEqualStrings("updated", session.getValue("key") orelse "");
}

test "session manager delete session" {
    const allocator = testing.allocator;
    var manager = SessionManager.init(allocator, 3600);
    defer manager.deinit();

    const session_id = try manager.createSession();
    try testing.expect(manager.getSession(session_id) != null);

    manager.deleteSession(session_id);
    try testing.expect(manager.getSession(session_id) == null);
}

test "session manager get nonexistent session" {
    const allocator = testing.allocator;
    var manager = SessionManager.init(allocator, 3600);
    defer manager.deinit();

    const session = manager.getSession("nonexistent-id");
    try testing.expect(session == null);
}

test "session manager multiple sessions" {
    const allocator = testing.allocator;
    var manager = SessionManager.init(allocator, 3600);
    defer manager.deinit();

    _ = try manager.createSession();
    _ = try manager.createSession();
    _ = try manager.createSession();

    // Sessions are stored in the manager and will be cleaned up by deinit
    try testing.expectEqual(@as(usize, 3), manager.sessions.count());
}

test "session data isolation between sessions" {
    const allocator = testing.allocator;
    var manager = SessionManager.init(allocator, 3600);
    defer manager.deinit();

    const id1 = try manager.createSession();
    const id2 = try manager.createSession();

    // Set values in each session
    {
        const sess1 = manager.getSession(id1) orelse return error.SessionNotFound;
        try sess1.setValue("user", "alice");
    }

    {
        const sess2 = manager.getSession(id2) orelse return error.SessionNotFound;
        try sess2.setValue("user", "bob");
    }

    // Verify values are isolated
    {
        const sess1 = manager.getSession(id1) orelse return error.SessionNotFound;
        const value1 = sess1.getValue("user") orelse return error.ValueNotFound;
        try testing.expectEqualStrings("alice", value1);
    }

    {
        const sess2 = manager.getSession(id2) orelse return error.SessionNotFound;
        const value2 = sess2.getValue("user") orelse return error.ValueNotFound;
        try testing.expectEqualStrings("bob", value2);
    }
}
