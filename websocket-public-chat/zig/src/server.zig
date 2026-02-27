const std = @import("std");
const zap = @import("zap");
const hub_mod = @import("hub.zig");
const protocol = @import("protocol.zig");
const stats_mod = @import("stats.zig");

const TOKEN_MAX: u32 = protocol.rate_limit_msg_per_sec;
const PING_INTERVAL_NS: u64 = protocol.ping_interval_sec * std.time.ns_per_s;
const PONG_TIMEOUT_NS: u64 = PING_INTERVAL_NS * 2;

/// Per-connection context — stored on the heap.
pub const Context = struct {
    id: u64,
    user: []u8, // heap-allocated, owned
    tokens: u32,
    last_refill_ns: u64,
    last_pong_ns: u64,
    subscribe_args: WebsocketHandler.SubscribeArgs,
    settings: WebsocketHandler.WebSocketSettings,
    allocator: std.mem.Allocator,
};

pub const WebsocketHandler = zap.WebSockets.Handler(Context);

// Global state — set during server init before any connections arrive.
var g_hub: *hub_mod.Hub = undefined;
var g_stats: *stats_mod.Stats = undefined;
var g_allocator: std.mem.Allocator = undefined;

pub fn init(hub: *hub_mod.Hub, stats: *stats_mod.Stats, allocator: std.mem.Allocator) void {
    g_hub = hub;
    g_stats = stats;
    g_allocator = allocator;
}

fn nowNs() u64 {
    return @intCast(std.time.nanoTimestamp());
}

fn allowToken(ctx: *Context) bool {
    const now = nowNs();
    const elapsed_ns = now -| ctx.last_refill_ns;
    const refill: u32 = @intCast(@min(TOKEN_MAX, elapsed_ns * TOKEN_MAX / std.time.ns_per_s));
    if (refill > 0) {
        ctx.tokens = @min(TOKEN_MAX, ctx.tokens + refill);
        ctx.last_refill_ns = now;
    }
    if (ctx.tokens == 0) return false;
    ctx.tokens -= 1;
    return true;
}

fn onOpen(ctx: ?*Context, handle: zap.WebSockets.WsHandle) anyerror!void {
    const c = ctx orelse return;
    c.last_pong_ns = nowNs();

    // Subscribe to the public room channel
    c.subscribe_args = .{
        .channel = protocol.room,
        .force_text = true,
        .context = c,
        .on_message = onChannelMessage,
    };
    _ = try WebsocketHandler.subscribe(handle, &c.subscribe_args);
    g_stats.addConnection();
}

fn onClose(ctx: ?*Context, _: isize) anyerror!void {
    const c = ctx orelse return;
    g_hub.unregister(c.id);
    g_stats.removeConnection();
    // Free context memory
    g_allocator.free(c.user);
    g_allocator.destroy(c);
}

fn onMessage(
    ctx: ?*Context,
    handle: zap.WebSockets.WsHandle,
    message: []const u8,
    _: bool,
) anyerror!void {
    const c = ctx orelse return;

    // Parse JSON — use a stack buffer for small messages
    var arena = std.heap.ArenaAllocator.init(g_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const parsed = std.json.parseFromSlice(
        protocol.Message,
        alloc,
        message,
        .{ .ignore_unknown_fields = true },
    ) catch return; // ignore malformed JSON
    defer parsed.deinit();

    const msg = parsed.value;

    if (std.mem.eql(u8, msg.type, protocol.msg_join)) {
        const user = msg.user orelse "";
        g_allocator.free(c.user);
        c.user = try g_allocator.dupe(u8, user);
        c.id = try g_hub.register(c.user);
    } else if (std.mem.eql(u8, msg.type, protocol.msg_chat)) {
        if (!allowToken(c)) {
            g_stats.addDropped();
            return;
        }
        g_stats.addMessage();
        // Broadcast via channel (all subscribers except sender get it via facil.io)
        WebsocketHandler.publish(.{ .channel = protocol.room, .message = message });
    } else if (std.mem.eql(u8, msg.type, protocol.msg_pong)) {
        c.last_pong_ns = nowNs();
    } else if (std.mem.eql(u8, msg.type, protocol.msg_leave)) {
        WebsocketHandler.close(handle);
    }
    // unknown type → ignore
}

fn onChannelMessage(
    _: ?*Context,
    _: zap.WebSockets.WsHandle,
    _: []const u8,
    _: []const u8,
) anyerror!void {
    // zap pub/sub delivers to all subscribers — no extra routing needed
}

/// HTTP upgrade handler — called by zap HTTP listener on /ws route.
pub fn onUpgrade(r: zap.Request, target_protocol: []const u8) anyerror!void {
    if (!std.mem.eql(u8, target_protocol, "websocket")) {
        r.setStatus(.bad_request);
        r.sendBody("expected websocket") catch {};
        return;
    }

    const ctx = g_allocator.create(Context) catch return;
    ctx.* = .{
        .id = 0,
        .user = g_allocator.dupe(u8, "") catch {
            g_allocator.destroy(ctx);
            return;
        },
        .tokens = TOKEN_MAX,
        .last_refill_ns = nowNs(),
        .last_pong_ns = nowNs(),
        .subscribe_args = undefined,
        .settings = undefined,
        .allocator = g_allocator,
    };

    ctx.settings = .{
        .on_open = onOpen,
        .on_close = onClose,
        .on_message = onMessage,
        .context = ctx,
    };

    WebsocketHandler.upgrade(r.h, &ctx.settings) catch {
        g_allocator.free(ctx.user);
        g_allocator.destroy(ctx);
    };
}
