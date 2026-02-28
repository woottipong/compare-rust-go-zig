const std = @import("std");
const ws = @import("websocket");
const hub_mod = @import("hub.zig");
const protocol = @import("protocol.zig");
const stats_mod = @import("stats.zig");

const TOKEN_MAX: u32 = @intCast(protocol.rate_limit_msg_per_sec);

// Global state — written once at startup, read-only during serve.
pub var g_hub: *hub_mod.Hub = undefined;
pub var g_stats: *stats_mod.Stats = undefined;
pub var g_allocator: std.mem.Allocator = undefined;

// Per-connection handler for websocket.zig.
pub const Handler = struct {
    conn: *ws.Conn,
    app: *App,
    id: u64,
    user: []u8,          // heap-allocated username (duped)
    tokens: u32,
    last_refill_ns: u64,

    // websocket.zig: init is called after HTTP upgrade, before handshake ACK.
    pub fn init(_: *ws.Handshake, conn: *ws.Conn, app: *App) !Handler {
        const user = try g_allocator.dupe(u8, "");
        return .{
            .conn = conn,
            .app = app,
            .id = 0,
            .user = user,
            .tokens = TOKEN_MAX,
            .last_refill_ns = nowNs(),
        };
    }

    // afterInit — called after handshake ACK sent; safe to record connection.
    pub fn afterInit(self: *Handler) !void {
        g_stats.addConnection();
        try self.app.addConn(self.conn);
    }

    // close — called when connection closes (client disconnect or server close).
    pub fn close(self: *Handler) void {
        self.app.removeConn(self.conn);
        g_hub.unregister(self.id);
        g_stats.removeConnection();
        g_allocator.free(self.user);
    }

    // clientMessage — called for each text/binary frame received.
    pub fn clientMessage(self: *Handler, data: []const u8) !void {
        var arena = std.heap.ArenaAllocator.init(g_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();

        const parsed = std.json.parseFromSlice(
            protocol.Message,
            alloc,
            data,
            .{ .ignore_unknown_fields = true },
        ) catch return; // ignore malformed JSON
        defer parsed.deinit();

        const msg = parsed.value;

        if (std.mem.eql(u8, msg.type, protocol.msg_join)) {
            const user = msg.user orelse "";
            g_allocator.free(self.user);
            self.user = try g_allocator.dupe(u8, user);
            self.id = try g_hub.register(self.user);
        } else if (std.mem.eql(u8, msg.type, protocol.msg_chat)) {
            if (!self.allowToken()) {
                g_stats.addDropped();
                return;
            }
            g_stats.addMessage();
            // Broadcast to all connected clients.
            try self.app.broadcast(data);
        } else if (std.mem.eql(u8, msg.type, protocol.msg_pong)) {
            // keepalive — nothing to do
        } else if (std.mem.eql(u8, msg.type, protocol.msg_leave)) {
            try self.conn.close(.{});
        }
        // unknown type → ignore
    }

    fn allowToken(self: *Handler) bool {
        const now = nowNs();
        const elapsed_ns = now -| self.last_refill_ns;
        const refill: u32 = @intCast(@min(TOKEN_MAX, elapsed_ns * TOKEN_MAX / std.time.ns_per_s));
        if (refill > 0) {
            self.tokens = @min(TOKEN_MAX, self.tokens + refill);
            self.last_refill_ns = now;
        }
        if (self.tokens == 0) return false;
        self.tokens -= 1;
        return true;
    }
};

fn nowNs() u64 {
    return @intCast(std.time.nanoTimestamp());
}

// App holds the shared connection list for broadcasting.
pub const App = struct {
    mu: std.Thread.Mutex,
    conns: std.ArrayListUnmanaged(*ws.Conn),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) App {
        return .{
            .mu = .{},
            .conns = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *App) void {
        self.conns.deinit(self.allocator);
    }

    pub fn addConn(self: *App, conn: *ws.Conn) !void {
        self.mu.lock();
        defer self.mu.unlock();
        try self.conns.append(self.allocator, conn);
    }

    pub fn removeConn(self: *App, conn: *ws.Conn) void {
        self.mu.lock();
        defer self.mu.unlock();
        for (self.conns.items, 0..) |c, i| {
            if (c == conn) {
                _ = self.conns.swapRemove(i);
                return;
            }
        }
    }

    // broadcast sends message to all active connections (best-effort).
    pub fn broadcast(self: *App, data: []const u8) !void {
        self.mu.lock();
        // Snapshot the list to avoid holding lock during write.
        const snap = try self.allocator.dupe(*ws.Conn, self.conns.items);
        self.mu.unlock();
        defer self.allocator.free(snap);

        for (snap) |conn| {
            conn.write(data) catch {}; // ignore slow/closed connections
        }
    }
};
