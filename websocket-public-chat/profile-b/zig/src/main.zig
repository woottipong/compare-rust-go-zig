const std = @import("std");
const zap = @import("zap");
const hub_mod = @import("hub.zig");
const server_mod = @import("server.zig");
const stats_mod = @import("stats.zig");

/// Fallback HTTP handler — only WebSocket upgrades are expected on this server.
fn onRequest(r: zap.Request) anyerror!void {
    r.setStatus(.not_found);
    r.sendBody("use WebSocket") catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse args: port duration
    var args = std.process.args();
    _ = args.next(); // skip program name

    const port_str = args.next() orelse "8080";
    const duration_str = args.next() orelse "0";

    const port = std.fmt.parseInt(u16, port_str, 10) catch 8080;
    const duration_sec = std.fmt.parseInt(u64, duration_str, 10) catch 0;

    var hub = hub_mod.Hub.init(allocator);
    defer hub.deinit();

    var stats = stats_mod.Stats.init();

    server_mod.init(&hub, &stats, allocator);

    var listener = zap.HttpListener.init(.{
        .port = port,
        .on_request = onRequest,
        .on_upgrade = server_mod.onUpgrade,
        .log = false,
        .max_clients = 4096,
        .max_body_size = 1024,
    });
    try listener.listen();

    std.debug.print("websocket-public-chat: listening on :{d}\n", .{port});

    if (duration_sec > 0) {
        // Run zap in background thread, stop after duration
        const t = try std.Thread.spawn(.{}, runZap, .{});
        std.Thread.sleep(duration_sec * std.time.ns_per_s);
        zap.stop();
        t.join();
    } else {
        zap.start(.{ .threads = 2, .workers = 1 });
    }

    stats.printStats();
}

fn runZap() void {
    zap.start(.{ .threads = 2, .workers = 1 });
}
