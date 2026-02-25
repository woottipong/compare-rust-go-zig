const std = @import("std");
const zap = @import("zap");

const RateLimiter = struct {
    clients: std.StringHashMap(ClientState),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,

    const ClientState = struct {
        count: u32,
        last_reset_ns: i128,
    };

    pub fn init(allocator: std.mem.Allocator) RateLimiter {
        return .{
            .clients = std.StringHashMap(ClientState).init(allocator),
            .mutex = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *RateLimiter) void {
        var it = self.clients.keyIterator();
        while (it.next()) |key| self.allocator.free(key.*);
        self.clients.deinit();
    }

    pub fn allow(self: *RateLimiter, client_ip: []const u8, limit: u32, window_ns: i128) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now_ns = std.time.nanoTimestamp();
        const result = self.clients.getOrPut(client_ip) catch return true;

        if (!result.found_existing) {
            const key = self.allocator.dupe(u8, client_ip) catch return true;
            result.key_ptr.* = key;
            result.value_ptr.* = .{ .count = 0, .last_reset_ns = now_ns };
        }

        const state = result.value_ptr;
        if (now_ns - state.last_reset_ns >= window_ns) {
            state.count = 0;
            state.last_reset_ns = now_ns;
        }

        if (state.count >= limit) return false;
        state.count += 1;
        return true;
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var target_url: []const u8 = undefined;
var rate_limiter: RateLimiter = undefined;

fn onRequest(r: zap.Request) anyerror!void {
    const path = r.path orelse "/";

    // Health check
    if (std.mem.eql(u8, path, "/health")) {
        r.setStatus(.ok);
        r.sendBody("{\"status\":\"OK\"}") catch return;
        return;
    }

    // Rate limiting
    const client_ip = r.getHeader("x-real-ip") orelse "127.0.0.1";
    if (!rate_limiter.allow(client_ip, 100, @as(i128, std.time.ns_per_s) * 60)) {
        r.setStatus(.too_many_requests);
        r.sendBody("{\"error\":\"Rate limit exceeded\"}") catch return;
        return;
    }

    // JWT validation (simplified)
    const auth_header = r.getHeader("authorization") orelse "";
    if (std.mem.startsWith(u8, path, "/api/") and 
        !std.mem.startsWith(u8, auth_header, "Bearer ")) {
        r.setStatus(.unauthorized);
        r.sendBody("{\"error\":\"Missing or invalid token\"}") catch return;
        return;
    }

    // Proxy response (mock)
    const method = r.method orelse "GET";
    const response = std.fmt.allocPrint(gpa.allocator(), 
        \\{{
        \\  "message": "Gateway received request",
        \\  "method": "{s}",
        \\  "path": "{s}",
        \\  "target": "{s}",
        \\  "timestamp": {d}
        \\}}
    , .{ method, path, target_url, std.time.timestamp() }) catch {
        r.setStatus(.internal_server_error);
        r.sendBody("{\"error\":\"Internal server error\"}") catch return;
        return;
    };
    defer gpa.allocator().free(response);

    r.setStatus(.ok);
    r.sendBody(response) catch return;
}

pub fn main() !void {
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.skip();

    const listen_arg = args.next() orelse {
        std.debug.print("Usage: lightweight-api-gateway <:port> <target_url>\n", .{});
        std.process.exit(1);
    };
    target_url = args.next() orelse {
        std.debug.print("Missing target URL\n", .{});
        std.process.exit(1);
    };

    // Parse port from ":8080" or "8080"
    const port_str = if (std.mem.startsWith(u8, listen_arg, ":")) listen_arg[1..] else listen_arg;
    const port = std.fmt.parseInt(u16, port_str, 10) catch 8080;

    rate_limiter = RateLimiter.init(allocator);
    defer rate_limiter.deinit();

    std.debug.print("Starting Zap gateway on :{d} -> {s}\n", .{ port, target_url });

    var listener = zap.HttpListener.init(.{
        .port = port,
        .on_request = onRequest,
        .log = false,
        .max_clients = 100000,
    });
    try listener.listen();

    zap.start(.{
        .threads = 4,
        .workers = 1,
    });
}
