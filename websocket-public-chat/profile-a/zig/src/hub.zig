const std = @import("std");

pub const MAX_CLIENTS = 4096;

/// A connected client entry.
pub const ClientEntry = struct {
    id: u64,
    user: []const u8, // heap-allocated
};

/// Thread-safe client registry.
pub const Hub = struct {
    // Zig 0.15: ArrayList is unmanaged — pass allocator to every method
    entries: std.ArrayListUnmanaged(ClientEntry),
    mu: std.Thread.Mutex,
    next_id: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Hub {
        return .{
            .entries = .{},
            .mu = .{},
            .next_id = 1,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Hub) void {
        for (self.entries.items) |e| self.allocator.free(e.user);
        self.entries.deinit(self.allocator);
    }

    /// Register a new client, return its assigned ID.
    pub fn register(self: *Hub, user: []const u8) !u64 {
        self.mu.lock();
        defer self.mu.unlock();
        const id = self.next_id;
        self.next_id += 1;
        const owned = try self.allocator.dupe(u8, user);
        try self.entries.append(self.allocator, .{ .id = id, .user = owned });
        return id;
    }

    /// Remove client by ID.
    pub fn unregister(self: *Hub, id: u64) void {
        self.mu.lock();
        defer self.mu.unlock();
        for (self.entries.items, 0..) |e, i| {
            if (e.id == id) {
                self.allocator.free(e.user);
                _ = self.entries.swapRemove(i);
                return;
            }
        }
    }

    pub fn count(self: *Hub) usize {
        self.mu.lock();
        defer self.mu.unlock();
        return self.entries.items.len;
    }
};

// --- Tests ---

test "hub register unregister" {
    var hub = Hub.init(std.testing.allocator);
    defer hub.deinit();

    const id1 = try hub.register("alice");
    const id2 = try hub.register("bob");
    const id3 = try hub.register("carol");
    _ = id3;

    try std.testing.expectEqual(@as(usize, 3), hub.count());

    hub.unregister(id1);
    hub.unregister(id2);

    try std.testing.expectEqual(@as(usize, 1), hub.count());
}

test "hub unique ids" {
    var hub = Hub.init(std.testing.allocator);
    defer hub.deinit();

    const a = try hub.register("a");
    const b = try hub.register("b");
    try std.testing.expect(a != b);
}
