const std = @import("std");
const c = @cImport({
    @cInclude("arpa/inet.h");
    @cInclude("netdb.h");
    @cInclude("netinet/in.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/types.h");
    @cInclude("unistd.h");
});

const Stats = struct {
    total_processed: u64,
    processing_ns: u64,

    fn avgLatencyMs(self: Stats) f64 {
        if (self.total_processed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.processing_ns)) / 1_000_000.0 / @as(f64, @floatFromInt(self.total_processed));
    }

    fn throughput(self: Stats) f64 {
        if (self.processing_ns == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_processed)) * 1_000_000_000.0 / @as(f64, @floatFromInt(self.processing_ns));
    }
};

fn parseArgs(allocator: std.mem.Allocator) !struct { host: []const u8, start_port: u16, end_port: u16, repeats: usize } {
    var args = std.process.args();
    _ = args.next();
    const host = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "host.docker.internal");
    errdefer allocator.free(host);
    const start_port = if (args.next()) |v| try std.fmt.parseInt(u16, v, 10) else 54000;
    const end_port = if (args.next()) |v| try std.fmt.parseInt(u16, v, 10) else 54009;
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 200;
    if (end_port < start_port or repeats == 0) return error.InvalidArgs;
    return .{ .host = host, .start_port = start_port, .end_port = end_port, .repeats = repeats };
}

fn canConnect(host: []const u8, port: u16) bool {
    const host_z = std.heap.c_allocator.dupeZ(u8, host) catch return false;
    defer std.heap.c_allocator.free(host_z);
    var port_buf: [16]u8 = undefined;
    const port_z = std.fmt.bufPrintZ(&port_buf, "{d}", .{port}) catch return false;

    var hints: c.addrinfo = std.mem.zeroes(c.addrinfo);
    hints.ai_family = c.AF_INET;
    hints.ai_socktype = c.SOCK_STREAM;

    var res: ?*c.addrinfo = null;
    if (c.getaddrinfo(host_z.ptr, port_z.ptr, &hints, &res) != 0 or res == null) return false;
    defer c.freeaddrinfo(res);

    const sock = c.socket(c.AF_INET, c.SOCK_STREAM, 0);
    if (sock < 0) return false;
    defer _ = c.close(sock);

    var tv: c.timeval = .{ .tv_sec = 0, .tv_usec = 50 * 1000 };
    _ = c.setsockopt(sock, c.SOL_SOCKET, c.SO_RCVTIMEO, &tv, @sizeOf(c.timeval));
    _ = c.setsockopt(sock, c.SOL_SOCKET, c.SO_SNDTIMEO, &tv, @sizeOf(c.timeval));

    return c.connect(sock, res.?.*.ai_addr, res.?.*.ai_addrlen) == 0;
}

fn scan(host: []const u8, start_port: u16, end_port: u16) usize {
    var open: usize = 0;
    var p: u16 = start_port;
    while (p <= end_port) : (p += 1) {
        if (canConnect(host, p)) open += 1;
        if (p == std.math.maxInt(u16)) break;
    }
    return open;
}

fn printStats(s: Stats) void {
    std.debug.print("--- Statistics ---\n", .{});
    std.debug.print("Total processed: {d}\n", .{s.total_processed});
    std.debug.print("Processing time: {d:.3}s\n", .{@as(f64, @floatFromInt(s.processing_ns)) / 1_000_000_000.0});
    std.debug.print("Average latency: {d:.6}ms\n", .{s.avgLatencyMs()});
    std.debug.print("Throughput: {d:.2} items/sec\n", .{s.throughput()});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cfg = parseArgs(allocator) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer allocator.free(cfg.host);

    var timer = try std.time.Timer.start();
    var open: usize = 0;
    for (0..cfg.repeats) |_| {
        open = scan(cfg.host, cfg.start_port, cfg.end_port);
    }
    std.debug.print("Open ports: {d}\n", .{open});
    const ports_per_run = @as(usize, cfg.end_port - cfg.start_port + 1);
    printStats(.{ .total_processed = @intCast(ports_per_run * cfg.repeats), .processing_ns = timer.read() });
}
