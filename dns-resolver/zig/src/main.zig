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

fn putU16BE(buf: []u8, offset: usize, value: u16) void {
    buf[offset] = @intCast(value >> 8);
    buf[offset + 1] = @intCast(value & 0x00FF);
}

fn readU16BE(buf: []const u8, offset: usize) !u16 {
    if (offset + 1 >= buf.len) return error.ShortDnsMessage;
    return (@as(u16, buf[offset]) << 8) | @as(u16, buf[offset + 1]);
}

fn parseArgs(allocator: std.mem.Allocator) !struct { host: []const u8, port: u16, repeats: usize } {
    var args = std.process.args();
    _ = args.next();

    const host = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "host.docker.internal");
    errdefer allocator.free(host);

    const port = if (args.next()) |v| try std.fmt.parseInt(u16, v, 10) else 53535;
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 2000;
    if (repeats == 0) return error.InvalidRepeats;

    return .{ .host = host, .port = port, .repeats = repeats };
}

fn splitLabels(name: []const u8, out: *std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    var start: usize = 0;
    for (0..name.len + 1) |i| {
        if (i == name.len or name[i] == '.') {
            if (i > start) try out.append(allocator, name[start..i]);
            start = i + 1;
        }
    }
}

fn buildQuery(allocator: std.mem.Allocator, id: u16, name: []const u8) ![]u8 {
    var q = std.ArrayList(u8){};
    errdefer q.deinit(allocator);

    try q.appendNTimes(allocator, 0, 12);
    putU16BE(q.items, 0, id);
    putU16BE(q.items, 2, 0x0100);
    putU16BE(q.items, 4, 1);

    var labels = std.ArrayList([]const u8){};
    defer labels.deinit(allocator);
    try splitLabels(name, &labels, allocator);
    for (labels.items) |label| {
        try q.append(allocator, @intCast(label.len));
        try q.appendSlice(allocator, label);
    }
    try q.append(allocator, 0);
    try q.appendSlice(allocator, &[_]u8{ 0, 1, 0, 1 });

    return q.toOwnedSlice(allocator);
}

fn readName(msg: []const u8, off: usize) !usize {
    var pos = off;
    while (true) {
        if (pos >= msg.len) return error.InvalidNameOffset;
        const l = msg[pos];
        pos += 1;
        if (l == 0) return pos;
        if ((l & 0xC0) == 0xC0) {
            if (pos >= msg.len) return error.InvalidCompressedName;
            return pos + 1;
        }
        pos += l;
    }
}

fn parseARecordCount(msg: []const u8) !usize {
    if (msg.len < 12) return error.ShortDnsMessage;
    const qd = try readU16BE(msg, 4);
    const an = try readU16BE(msg, 6);

    var off: usize = 12;
    for (0..qd) |_| {
        off = try readName(msg, off);
        off += 4;
    }

    var count: usize = 0;
    for (0..an) |_| {
        off = try readName(msg, off);
        if (off + 10 > msg.len) return error.InvalidRr;
        const type_code = try readU16BE(msg, off);
        const rdlen = try readU16BE(msg, off + 8);
        off += 10;
        if (off + rdlen > msg.len) return error.InvalidRdata;
        if (type_code == 1 and rdlen == 4) count += 1;
        off += rdlen;
    }
    return count;
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
    var port_buf: [16]u8 = undefined;
    const port_z = try std.fmt.bufPrintZ(&port_buf, "{d}", .{cfg.port});

    var hints: c.addrinfo = std.mem.zeroes(c.addrinfo);
    hints.ai_family = c.AF_INET;
    hints.ai_socktype = c.SOCK_DGRAM;
    var res: ?*c.addrinfo = null;
    if (c.getaddrinfo(host_z.ptr, port_z.ptr, &hints, &res) != 0 or res == null) {
        std.debug.print("Error: resolve host failed\n", .{});
        std.process.exit(1);
    }
    defer c.freeaddrinfo(res);

    const addr_ptr = @as(*c.sockaddr_in, @ptrCast(@alignCast(res.?.*.ai_addr)));
    const addr = addr_ptr.*;

    var recv_buf: [512]u8 = undefined;
    var timer = try std.time.Timer.start();

    for (0..cfg.repeats) |i| {
        const q = try buildQuery(allocator, @intCast(i + 1), "example.com");
        defer allocator.free(q);

        const sent = c.sendto(
            sock,
            q.ptr,
            q.len,
            0,
            @ptrCast(&addr),
            res.?.*.ai_addrlen,
        );
        if (sent < 0) {
            std.debug.print("Error: sendto failed\n", .{});
            std.process.exit(1);
        }

        const n = c.recvfrom(sock, &recv_buf, recv_buf.len, 0, null, null);
        if (n <= 0) {
            std.debug.print("Error: recvfrom failed\n", .{});
            std.process.exit(1);
        }
        _ = parseARecordCount(recv_buf[0..@intCast(n)]) catch {
            std.debug.print("Error: parse dns response failed\n", .{});
            std.process.exit(1);
        };
    }

    printStats(.{ .total_processed = @intCast(cfg.repeats), .processing_ns = timer.read() });
}
