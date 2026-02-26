const std = @import("std");
const c = @cImport({
    @cInclude("arpa/inet.h");
    @cInclude("netdb.h");
    @cInclude("netinet/in.h");
    @cInclude("sys/socket.h");
    @cInclude("sys/types.h");
    @cInclude("unistd.h");
});

const protocol_name = "BitTorrent protocol";
const handshake_len = 68;

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
    const port = if (args.next()) |v| try std.fmt.parseInt(u16, v, 10) else 6881;
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 2000;
    if (repeats == 0) return error.InvalidRepeats;
    return .{ .host = host, .port = port, .repeats = repeats };
}

fn buildHandshake() [handshake_len]u8 {
    var hs: [handshake_len]u8 = [_]u8{0} ** handshake_len;
    hs[0] = protocol_name.len;
    @memcpy(hs[1..20], protocol_name);
    const info_hash = [_]u8{ 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x60 };
    @memcpy(hs[28..48], &info_hash);
    @memcpy(hs[48..68], "-ZG0001-123456789012");
    return hs;
}

fn connectSocket(host: []const u8, port: u16) !c_int {
    const host_z = try std.heap.c_allocator.dupeZ(u8, host);
    defer std.heap.c_allocator.free(host_z);
    var port_buf: [16]u8 = undefined;
    const port_z = try std.fmt.bufPrintZ(&port_buf, "{d}", .{port});

    var hints: c.addrinfo = std.mem.zeroes(c.addrinfo);
    hints.ai_family = c.AF_INET;
    hints.ai_socktype = c.SOCK_STREAM;

    var res: ?*c.addrinfo = null;
    if (c.getaddrinfo(host_z.ptr, port_z.ptr, &hints, &res) != 0 or res == null) return error.ResolveFailed;
    defer c.freeaddrinfo(res);

    const sock = c.socket(c.AF_INET, c.SOCK_STREAM, 0);
    if (sock < 0) return error.SocketFailed;

    var tv: c.timeval = .{ .tv_sec = 0, .tv_usec = 500 * 1000 };
    _ = c.setsockopt(sock, c.SOL_SOCKET, c.SO_RCVTIMEO, &tv, @sizeOf(c.timeval));
    _ = c.setsockopt(sock, c.SOL_SOCKET, c.SO_SNDTIMEO, &tv, @sizeOf(c.timeval));

    if (c.connect(sock, res.?.*.ai_addr, res.?.*.ai_addrlen) != 0) {
        _ = c.close(sock);
        return error.ConnectFailed;
    }

    return sock;
}

fn doHandshake(host: []const u8, port: u16, hs: [handshake_len]u8) !void {
    const sock = try connectSocket(host, port);
    defer _ = c.close(sock);

    if (c.send(sock, &hs, handshake_len, 0) != handshake_len) return error.SendFailed;

    var response: [handshake_len]u8 = undefined;
    if (c.recv(sock, &response, handshake_len, 0) != handshake_len) return error.ReceiveFailed;

    if (response[0] != protocol_name.len or !std.mem.eql(u8, response[1..20], protocol_name)) {
        return error.InvalidResponse;
    }
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

    const hs = buildHandshake();
    var timer = try std.time.Timer.start();

    for (0..cfg.repeats) |_| {
        doHandshake(cfg.host, cfg.port, hs) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
    }

    printStats(.{ .total_processed = @intCast(cfg.repeats), .processing_ns = timer.read() });
}
