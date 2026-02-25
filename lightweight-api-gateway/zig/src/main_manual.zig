const std = @import("std");
const net = std.net;
const http = std.http;

const RateLimiter = struct {
    clients: std.hash_map.StringHashMap(ClientState),
    mutex: std.Thread.Mutex,

    const ClientState = struct {
        count: u32,
        last_reset: std.time.Instant,
    };

    pub fn init() RateLimiter {
        return RateLimiter{
            .clients = std.hash_map.StringHashMap(ClientState).init(std.heap.c_allocator),
            .mutex = std.Thread.Mutex{},
        };
    }

    pub fn allow(self: *RateLimiter, client_ip: []const u8, limit: u32, window: u64) bool {
        self.mutex.lock();
        defer self.mutex.unlock();

        const now = std.time.Instant.now() catch return false;
        const key = std.heap.c_allocator.dupe(u8, client_ip) catch return false;
        defer std.heap.c_allocator.free(key);

        const entry = self.clients.getOrPut(key) catch return false;
        if (!entry.found_existing) {
            entry.value_ptr.* = ClientState{
                .count = 0,
                .last_reset = now,
            };
        }

        const state = entry.value_ptr.*;
        const elapsed = now.since(state.last_reset);

        if (elapsed >= window) {
            entry.value_ptr.* = ClientState{
                .count = 0,
                .last_reset = now,
            };
        }

        if (entry.value_ptr.count >= limit) {
            return false;
        }

        entry.value_ptr.count += 1;
        return true;
    }
};

const Gateway = struct {
    allocator: std.mem.Allocator,
    target_url: []const u8,
    rate_limiter: RateLimiter,

    pub fn init(allocator: std.mem.Allocator, target_url: []const u8) Gateway {
        return Gateway{
            .allocator = allocator,
            .target_url = target_url,
            .rate_limiter = RateLimiter.init(),
        };
    }

    pub fn run(self: *Gateway, listen_addr: []const u8) !void {
        // Simple TCP server implementation
        const port = 8080;
        const address = try std.net.Address.parseIp("0.0.0.0", port);
        
        var server = try address.listen(.{ .reuse_address = true });
        defer server.deinit();

        std.debug.print("Starting gateway on {s} -> {s}\n", .{ listen_addr, self.target_url });

        while (true) {
            const connection = server.accept() catch |err| {
                std.debug.print("Accept error: {}\n", .{err});
                continue;
            };

            // Handle connection in a simple way (single-threaded for now)
            self.handleConnection(connection) catch |err| {
                std.debug.print("Connection error: {}\n", .{err});
            };
        }
    }

    fn handleConnection(self: *Gateway, connection: net.Server.Connection) !void {
        defer connection.stream.close();

        var buffer: [4096]u8 = undefined;
        const request_data = connection.stream.read(&buffer) catch return;
        if (request_data == 0) return;

        const request_text = buffer[0..request_data];
        
        // Simple HTTP request parsing
        var lines = std.mem.tokenizeScalar(u8, request_text, '\n');
        const request_line = lines.next() orelse return;
        
        var parts = std.mem.tokenizeScalar(u8, request_line, ' ');
        const method = parts.next() orelse return;
        const path = parts.next() orelse return;
        
        // Get client IP (simplified)
        const client_ip = "127.0.0.1"; // Simplified for demo

        // Check rate limit
        if (!self.rate_limiter.allow(client_ip, 100, 60_000_000_000)) { // 60 seconds in nanoseconds
            try self.sendErrorResponse(connection.stream, 429, "Rate limit exceeded");
            return;
        }

        // Simple JWT check for protected endpoints
        if (!std.mem.startsWith(u8, path, "/public/") and !std.mem.eql(u8, path, "/health")) {
            // For demo, just check if request contains "Bearer" token
            if (std.mem.indexOf(u8, request_text, "Bearer") == null) {
                try self.sendErrorResponse(connection.stream, 401, "Missing authorization header");
                return;
            }
            
            if (std.mem.indexOf(u8, request_text, "valid-test-token") == null) {
                try self.sendErrorResponse(connection.stream, 401, "Invalid token");
                return;
            }
        }

        // Handle health check
        if (std.mem.eql(u8, path, "/health")) {
            try self.sendResponse(connection.stream, 200, "OK");
            return;
        }

        // For other endpoints, send a simple response
        const response = try std.fmt.allocPrint(
            self.allocator,
            "Gateway received: {s} {s}\nTarget: {s}\n",
            .{ method, path, self.target_url }
        );
        defer self.allocator.free(response);

        try self.sendResponse(connection.stream, 200, response);
    }

    fn sendResponse(self: Gateway, stream: net.Stream, status: u16, body: []const u8) !void {
        const response = try std.fmt.allocPrint(
            self.allocator,
            "HTTP/1.1 {d} OK\r\nContent-Length: {d}\r\n\r\n{s}",
            .{ status, body.len, body }
        );
        defer self.allocator.free(response);

        _ = try stream.write(response);
    }

    fn sendErrorResponse(self: Gateway, stream: net.Stream, status: u16, message: []const u8) !void {
        try self.sendResponse(stream, status, message);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.skip(); // skip program name

    const listen_addr = args.next() orelse {
        std.debug.print("Usage: lightweight-api-gateway <listen_addr> <target_url>\n", .{});
        std.debug.print("Example: lightweight-api-gateway :8080 http://localhost:3000\n", .{});
        std.process.exit(1);
    };

    const target_url = args.next() orelse {
        std.debug.print("Missing target URL\n", .{});
        std.process.exit(1);
    };

    var gateway = Gateway.init(allocator, target_url);
    try gateway.run(listen_addr);
}
