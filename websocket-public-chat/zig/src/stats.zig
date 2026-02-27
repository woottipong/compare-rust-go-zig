const std = @import("std");

pub const Stats = struct {
    total_messages: u64,
    dropped_messages: u64,
    total_connections: u64,
    active_conns: u64,
    start_ns: u64,
    mu: std.Thread.Mutex,

    pub fn init() Stats {
        return .{
            .total_messages = 0,
            .dropped_messages = 0,
            .total_connections = 0,
            .active_conns = 0,
            .start_ns = @intCast(std.time.nanoTimestamp()),
            .mu = .{},
        };
    }

    pub fn addMessage(self: *Stats) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.total_messages += 1;
    }

    pub fn addDropped(self: *Stats) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.dropped_messages += 1;
    }

    pub fn addConnection(self: *Stats) void {
        self.mu.lock();
        defer self.mu.unlock();
        self.total_connections += 1;
        self.active_conns += 1;
    }

    pub fn removeConnection(self: *Stats) void {
        self.mu.lock();
        defer self.mu.unlock();
        if (self.active_conns > 0) self.active_conns -= 1;
    }

    pub fn elapsedSec(self: *Stats) f64 {
        const now: u64 = @intCast(std.time.nanoTimestamp());
        const ns = now -| self.start_ns;
        return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
    }

    pub fn avgLatencyMs(self: *Stats) f64 {
        self.mu.lock();
        const msgs = self.total_messages;
        self.mu.unlock();
        if (msgs == 0) return 0.0;
        return self.elapsedSec() * 1000.0 / @as(f64, @floatFromInt(msgs));
    }

    pub fn throughput(self: *Stats) f64 {
        self.mu.lock();
        const msgs = self.total_messages;
        self.mu.unlock();
        const elapsed = self.elapsedSec();
        if (elapsed == 0.0) return 0.0;
        return @as(f64, @floatFromInt(msgs)) / elapsed;
    }

    pub fn dropRate(self: *Stats) f64 {
        self.mu.lock();
        const msgs = self.total_messages;
        const dropped = self.dropped_messages;
        self.mu.unlock();
        const total = msgs + dropped;
        if (total == 0) return 0.0;
        return @as(f64, @floatFromInt(dropped)) / @as(f64, @floatFromInt(total)) * 100.0;
    }

    pub fn printStats(self: *Stats) void {
        self.mu.lock();
        const msgs = self.total_messages;
        const conns = self.total_connections;
        self.mu.unlock();
        const elapsed = self.elapsedSec();
        const avg_lat = self.avgLatencyMs();
        const tput = self.throughput();
        const dr = self.dropRate();

        std.debug.print("--- Statistics ---\n", .{});
        std.debug.print("Total messages: {d}\n", .{msgs});
        std.debug.print("Processing time: {d:.3}s\n", .{elapsed});
        std.debug.print("Average latency: {d:.3}ms\n", .{avg_lat});
        std.debug.print("Throughput: {d:.2} messages/sec\n", .{tput});
        std.debug.print("Total connections: {d}\n", .{conns});
        std.debug.print("Message drop rate: {d:.2}%\n", .{dr});
    }
};
