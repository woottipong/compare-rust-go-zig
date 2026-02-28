const std = @import("std");
const ws = @import("websocket");
const hub_mod = @import("hub.zig");
const server_mod = @import("server.zig");
const stats_mod = @import("stats.zig");

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

    // Write global state pointers before starting the server.
    server_mod.g_hub = &hub;
    server_mod.g_stats = &stats;
    server_mod.g_allocator = allocator;

    var app = server_mod.App.init(allocator);
    defer app.deinit();

    std.debug.print("websocket-public-chat (profile-b): listening on :{d}\n", .{port});

    if (duration_sec > 0) {
        // Run server in a background thread; main thread sleeps then shuts down.
        const t = try std.Thread.spawn(.{}, runServer, .{ &app, allocator, port });
        std.Thread.sleep(duration_sec * std.time.ns_per_s);
        // websocket.zig Server has no stop() — detach and let process exit clean up.
        t.detach();
    } else {
        try runServer(&app, allocator, port);
    }

    stats.printStats();
}

fn runServer(app: *server_mod.App, allocator: std.mem.Allocator, port: u16) !void {
    var server = try ws.Server(server_mod.Handler).init(allocator, .{
        .port = port,
        .address = "0.0.0.0",
        .handshake = .{
            .timeout = 3,
        },
    });
    defer server.deinit();
    try server.listen(app);
}
