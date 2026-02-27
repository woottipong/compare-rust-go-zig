const std = @import("std");

const KVStore = struct {
    data: std.StringHashMap([]const u8),
    mu: std.Thread.Mutex,

    fn init(allocator: std.mem.Allocator) KVStore {
        return KVStore{
            .data = std.StringHashMap([]const u8).init(allocator),
            .mu = std.Thread.Mutex{},
        };
    }

    fn deinit(self: *KVStore, allocator: std.mem.Allocator) void {
        var it = self.data.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        self.data.deinit();
    }

    fn set(self: *KVStore, allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
        self.mu.lock();
        defer self.mu.unlock();

        const value_copy = try allocator.dupe(u8, value);
        errdefer allocator.free(value_copy);

        const result = try self.data.getOrPut(key);
        if (result.found_existing) {
            allocator.free(result.value_ptr.*);
        }
        result.value_ptr.* = value_copy;
    }

    fn get(self: *KVStore, key: []const u8) ?[]const u8 {
        self.mu.lock();
        defer self.mu.unlock();
        return self.data.get(key);
    }

    fn delete(self: *KVStore, allocator: std.mem.Allocator, key: []const u8) bool {
        self.mu.lock();
        defer self.mu.unlock();

        if (self.data.fetchRemove(key)) |removed| {
            allocator.free(removed.value);
            return true;
        }
        return false;
    }
};

const Stats = struct {
    total_ops: usize,
    processing_ns: u64,

    fn avgLatencyMs(self: Stats) f64 {
        if (self.total_ops == 0) return 0.0;
        return @as(f64, @floatFromInt(self.processing_ns)) / 1_000_000.0 / @as(f64, @floatFromInt(self.total_ops));
    }

    fn throughput(self: Stats) f64 {
        if (self.processing_ns == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_ops)) * 1_000_000_000.0 / @as(f64, @floatFromInt(self.processing_ns));
    }
};

fn parseArgs() !usize {
    var args = std.process.args();
    _ = args.skip(); // skip program name

    const arg = args.next() orelse return 10000; // default

    return std.fmt.parseInt(usize, arg, 10) catch |err| switch (err) {
        error.InvalidCharacter => {
            std.debug.print("Error: invalid number of operations: {s}\n", .{arg});
            std.process.exit(1);
        },
        else => return err,
    };
}

fn printConfig(num_ops: usize) void {
    std.debug.print("Configuration:\n", .{});
    std.debug.print("  Operations: {d}\n", .{num_ops});
    std.debug.print("  Store type: In-memory KV Store\n\n", .{});
}

fn printStats(stats: Stats) void {
    std.debug.print("--- Statistics ---\n", .{});
    std.debug.print("Total processed: {d}\n", .{stats.total_ops});
    std.debug.print("Processing time: {d:.3}s\n", .{@as(f64, @floatFromInt(stats.processing_ns)) / 1_000_000_000.0});
    std.debug.print("Average latency: {d:.6}ms\n", .{stats.avgLatencyMs()});
    std.debug.print("Throughput: {d:.0} ops/sec\n", .{stats.throughput()});
}

fn generateTestData(allocator: std.mem.Allocator, num_ops: usize) !struct { keys: [][]const u8, values: [][]const u8 } {
    var keys = try allocator.alloc([]const u8, num_ops);
    var values = try allocator.alloc([]const u8, num_ops);

    for (0..num_ops) |i| {
        const key = try std.fmt.allocPrint(allocator, "key_{d}", .{i});
        const value = try std.fmt.allocPrint(allocator, "value_{d}", .{i});

        keys[i] = key;
        values[i] = value;
    }

    return .{ .keys = keys, .values = values };
}

fn runBenchmark(allocator: std.mem.Allocator, num_ops: usize) !Stats {
    const test_data = try generateTestData(allocator, num_ops);
    defer {
        for (test_data.keys) |key| allocator.free(key);
        for (test_data.values) |value| allocator.free(value);
        allocator.free(test_data.keys);
        allocator.free(test_data.values);
    }

    var timer = try std.time.Timer.start();
    var elapsed_ns: u64 = 0;

    // Inner block ensures kv.deinit() runs before test_data keys are freed
    {
        var kv = KVStore.init(allocator);
        defer kv.deinit(allocator);

        // SET operations
        for (0..num_ops) |i| {
            try kv.set(allocator, test_data.keys[i], test_data.values[i]);
        }

        // GET operations
        for (0..num_ops) |i| {
            _ = kv.get(test_data.keys[i]);
        }

        // DELETE operations (half of them)
        for (0..num_ops / 2) |i| {
            _ = kv.delete(allocator, test_data.keys[i]);
        }

        elapsed_ns = timer.read();
    }

    return Stats{
        .total_ops = num_ops * 2 + num_ops / 2, // SET + GET + DELETE
        .processing_ns = elapsed_ns,
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const num_ops = try parseArgs();

    printConfig(num_ops);
    const stats = try runBenchmark(allocator, num_ops);
    printStats(stats);
}
