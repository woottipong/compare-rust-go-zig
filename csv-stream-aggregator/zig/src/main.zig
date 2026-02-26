const std = @import("std");

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

const Aggregate = struct {
    count: u64 = 0,
    sum: f64 = 0.0,
};

const Config = struct {
    input: []const u8,
    repeats: usize,
};

fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = std.process.args();
    _ = args.next();

    const input = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/sales.csv");
    errdefer allocator.free(input);

    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 30;
    if (repeats == 0) return error.InvalidRepeats;

    return .{ .input = input, .repeats = repeats };
}

fn processFile(allocator: std.mem.Allocator, path: []const u8) !struct { rows: u64, groups: std.StringHashMap(Aggregate) } {
    const file_data = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 64);
    defer allocator.free(file_data);

    var groups = std.StringHashMap(Aggregate).init(allocator);
    var line_no: u64 = 0;
    var rows: u64 = 0;

    var lines = std.mem.splitScalar(u8, file_data, '\n');
    while (lines.next()) |raw_line| {
        line_no += 1;
        const line = std.mem.trimRight(u8, raw_line, "\r");
        if (line_no == 1 and std.mem.startsWith(u8, line, "category,")) continue;

        var it = std.mem.splitScalar(u8, line, ',');
        const category = it.next() orelse continue;
        const amount_str = it.next() orelse continue;
        const amount = std.fmt.parseFloat(f64, amount_str) catch continue;

        const entry = try groups.getOrPut(category);
        if (!entry.found_existing) {
            entry.key_ptr.* = try allocator.dupe(u8, category);
            entry.value_ptr.* = .{};
        }
        entry.value_ptr.count += 1;
        entry.value_ptr.sum += amount;
        rows += 1;
    }

    return .{ .rows = rows, .groups = groups };
}

fn freeGroups(allocator: std.mem.Allocator, groups: *std.StringHashMap(Aggregate)) void {
    var it = groups.iterator();
    while (it.next()) |entry| allocator.free(entry.key_ptr.*);
    groups.deinit();
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
    defer allocator.free(cfg.input);

    var timer = try std.time.Timer.start();
    var rows: u64 = 0;
    var groups = std.StringHashMap(Aggregate).init(allocator);
    defer groups.deinit();

    for (0..cfg.repeats) |_| {
        freeGroups(allocator, &groups);
        const result = processFile(allocator, cfg.input) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        rows = result.rows;
        groups = result.groups;
    }

    printStats(.{ .total_processed = rows * @as(u64, @intCast(cfg.repeats)), .processing_ns = timer.read() });
}
