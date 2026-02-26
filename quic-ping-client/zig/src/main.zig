const std = @import("std");
const c = @cImport({
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

fn parseArgs(allocator: std.mem.Allocator) !struct { host: []const u8, port: u16, repeats: usize } {
    var args = std.process.args();
    _ = args.next();
    const host = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "host.docker.internal");
    errdefer allocator.free(host);
    const port = if (args.next()) |v| try std.fmt.parseInt(u16, v, 10) else 56000;
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 3000;
    if (repeats == 0) return error.InvalidRepeats;
    return .{ .host = host, .port = port, .repeats = repeats };
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

    const sock = c.socket(c.AF_INET, c.SOCK_DGRAM, 0);
    if (sock < 0) {
        std.debug.print("Error: socket failed\n", .{});
        std.process.exit(1);
    }
    defer _ = c.close(sock);

    const host_z = try allocator.dupeZ(u8, cfg.host);
    defer allocator.free(host_z);
    const port_z = try std.fmt.allocPrintZ(allocator, "{d}", .{cfg.port});
    defer allocator.free(port_z);

    var hints: c.addrinfo = std.mem.zeroes(c.addrinfo);
    hints.ai_family = c.AF_INET;
    hints.ai_socktype = c.SOCK_DGRAM;
    var res: ?*c.addrinfo = null;
    if (c.getaddrinfo(host_z.ptr, port_z.ptr, &hints, &res) != 0 or res == null) {
        std.debug.print("Error: resolve host failed\n", .{});
        std.process.exit(1);
    }
    defer c.freeaddrinfo(res);

    const addr = res.?.*.ai_addr;
    const addrlen = res.?.*.ai_addrlen;

    var recv_buf: [64]u8 = undefined;
    var timer = try std.time.Timer.start();
    for (0..cfg.repeats) |_| {
        const sent = c.sendto(sock, "PING".ptr, 4, 0, addr, addrlen);
        if (sent < 0) {
            std.debug.print("Error: sendto failed\n", .{});
            std.process.exit(1);
        }
        const n = c.recvfrom(sock, &recv_buf, recv_buf.len, 0, null, null);
        if (n != 4 or !std.mem.eql(u8, recv_buf[0..4], "PONG")) {
            std.debug.print("Error: invalid response\n", .{});
            std.process.exit(1);
        }
    }

    printStats(.{ .total_processed = @intCast(cfg.repeats), .processing_ns = timer.read() });
}
