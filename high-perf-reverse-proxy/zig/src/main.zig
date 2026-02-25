const std = @import("std");

const DEFAULT_PORT: u16 = 8080;
const DEFAULT_BACKENDS: []const u8 = "localhost:3001,localhost:3002,localhost:3003";

const LoadBalancer = struct {
    backends: []const []const u8,
    index: usize,

    fn init(allocator: std.mem.Allocator, urls: []const []const u8) !LoadBalancer {
        const copy = try allocator.alloc([]const u8, urls.len);
        for (urls, 0..) |u, i| copy[i] = try allocator.dupe(u8, u);
        return .{ .backends = copy, .index = 0 };
    }

    fn deinit(self: *LoadBalancer, allocator: std.mem.Allocator) void {
        for (self.backends) |b| allocator.free(b);
        allocator.free(self.backends);
    }

    fn getBackend(self: *LoadBalancer) ?[]const u8 {
        if (self.backends.len == 0) return null;
        const idx = self.index % self.backends.len;
        self.index += 1;
        return self.backends[idx];
    }
};

fn parseBackends(allocator: std.mem.Allocator, s: []const u8) ![]const []const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .{};
    defer list.deinit(allocator);
    var start: usize = 0;
    for (s, 0..) |c, i| {
        if (c == ',') {
            if (i > start) try list.append(allocator, try allocator.dupe(u8, s[start..i]));
            start = i + 1;
        }
    }
    if (s.len > start) try list.append(allocator, try allocator.dupe(u8, s[start..]));
    return list.toOwnedSlice(allocator);
}

fn parseBackendAddr(backend: []const u8) !struct { host: []const u8, port: u16 } {
    const colon = std.mem.lastIndexOfScalar(u8, backend, ':') orelse return error.InvalidBackend;
    const host = backend[0..colon];
    const port = try std.fmt.parseInt(u16, backend[colon + 1 ..], 10);
    return .{ .host = host, .port = port };
}

fn proxyRequest(allocator: std.mem.Allocator, client_fd: std.posix.fd_t, backend: []const u8, request: []const u8) void {
    const parsed = parseBackendAddr(backend) catch return;

    const host_z = allocator.dupeZ(u8, parsed.host) catch return;
    defer allocator.free(host_z);

    const addr_list = std.net.getAddressList(allocator, host_z, parsed.port) catch return;
    defer addr_list.deinit();

    if (addr_list.addrs.len == 0) return;
    const addr = addr_list.addrs[0];

    const backend_fd = std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, 0) catch return;
    defer std.posix.close(backend_fd);

    std.posix.connect(backend_fd, &addr.any, addr.getOsSockLen()) catch return;

    _ = std.posix.write(backend_fd, request) catch return;
    std.posix.shutdown(backend_fd, .send) catch {};

    var buf: [65536]u8 = undefined;
    while (true) {
        const n = std.posix.read(backend_fd, &buf) catch break;
        if (n == 0) break;
        _ = std.posix.write(client_fd, buf[0..n]) catch break;
    }
}

const ClientArgs = struct {
    client_fd: std.posix.fd_t,
    lb: *LoadBalancer,
};

fn handleClient(args: ClientArgs) void {
    const client_fd = args.client_fd;
    const lb = args.lb;
    defer std.posix.close(client_fd);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var buf: [8192]u8 = undefined;
    const n = std.posix.read(client_fd, &buf) catch return;
    if (n == 0) return;

    const backend = lb.getBackend() orelse {
        _ = std.posix.write(client_fd,
            "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 19\r\n\r\nNo healthy backends") catch {};
        return;
    };

    proxyRequest(allocator, client_fd, backend, buf[0..n]);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.skip();

    var port: u16 = DEFAULT_PORT;
    var backends_str: []u8 = try allocator.dupe(u8, DEFAULT_BACKENDS);
    defer allocator.free(backends_str);

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--port=")) {
            port = try std.fmt.parseInt(u16, arg[7..], 10);
        } else if (std.mem.eql(u8, arg, "--port")) {
            const val = args.next() orelse continue;
            port = try std.fmt.parseInt(u16, val, 10);
        } else if (std.mem.startsWith(u8, arg, "--backends=")) {
            allocator.free(backends_str);
            backends_str = try allocator.dupe(u8, arg[11..]);
        } else if (std.mem.eql(u8, arg, "--backends")) {
            const val = args.next() orelse continue;
            allocator.free(backends_str);
            backends_str = try allocator.dupe(u8, val);
        }
    }

    const urls = try parseBackends(allocator, backends_str);
    defer {
        for (urls) |u| allocator.free(u);
        allocator.free(urls);
    }

    var lb = try LoadBalancer.init(allocator, urls);
    defer lb.deinit(allocator);

    std.debug.print("Reverse Proxy starting on :{d}\n", .{port});
    std.debug.print("Backends: {s}\n", .{backends_str});

    const server_fd = try std.posix.socket(std.posix.AF.INET, std.posix.SOCK.STREAM, 0);
    defer std.posix.close(server_fd);

    try std.posix.setsockopt(server_fd, std.posix.SOL.SOCKET, std.posix.SO.REUSEADDR,
        &std.mem.toBytes(@as(c_int, 1)));

    const bind_addr = std.net.Address.initIp4(.{ 0, 0, 0, 0 }, port);
    try std.posix.bind(server_fd, &bind_addr.any, bind_addr.getOsSockLen());
    try std.posix.listen(server_fd, 128);

    std.debug.print("Listening...\n", .{});

    while (true) {
        var client_addr: std.posix.sockaddr = undefined;
        var client_len: std.posix.socklen_t = @sizeOf(std.posix.sockaddr);
        const client_fd = std.posix.accept(server_fd, &client_addr, &client_len, 0) catch continue;
        const client_args = ClientArgs{ .client_fd = client_fd, .lb = &lb };
        _ = std.Thread.spawn(.{}, handleClient, .{client_args}) catch {
            std.posix.close(client_fd);
        };
    }
}
