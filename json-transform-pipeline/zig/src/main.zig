const std = @import("std");

const Stats = struct {
    total_processed: u64,
    processing_ns: u64,
    score_sum: f64,

    fn avgLatencyMs(self: Stats) f64 {
        if (self.total_processed == 0) return 0.0;
        return @as(f64, @floatFromInt(self.processing_ns)) / 1_000_000.0 / @as(f64, @floatFromInt(self.total_processed));
    }

    fn throughput(self: Stats) f64 {
        if (self.processing_ns == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_processed)) * 1_000_000_000.0 / @as(f64, @floatFromInt(self.processing_ns));
    }
};

fn processFile(allocator: std.mem.Allocator, path: []const u8) !Stats {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 256 * 1024 * 1024);
    defer allocator.free(contents);

    var total_processed: u64 = 0;
    var score_sum: f64 = 0.0;

    var timer = try std.time.Timer.start();

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(
            struct { id: u64, name: []const u8, score: f64, active: bool },
            allocator,
            line,
            .{ .ignore_unknown_fields = true },
        ) catch continue;
        defer parsed.deinit();

        score_sum += parsed.value.score;
        total_processed += 1;
    }

    const elapsed_ns = timer.read();

    return Stats{
        .total_processed = total_processed,
        .processing_ns = elapsed_ns,
        .score_sum = score_sum,
    };
}

fn printStats(s: Stats) void {
    std.debug.print("--- Statistics ---\n", .{});
    std.debug.print("Total processed: {d}\n", .{s.total_processed});
    std.debug.print("Processing time: {d:.3}s\n", .{@as(f64, @floatFromInt(s.processing_ns)) / 1_000_000_000.0});
    std.debug.print("Average latency: {d:.6}ms\n", .{s.avgLatencyMs()});
    std.debug.print("Throughput: {d:.2} items/sec\n", .{s.throughput()});
    std.debug.print("Score sum: {d:.2}\n", .{s.score_sum});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next(); // skip program name

    const input_path = args.next() orelse "/data/records.jsonl";
    const repeats_str = args.next() orelse "1";
    const repeats = std.fmt.parseInt(usize, repeats_str, 10) catch 1;

    var best: ?Stats = null;

    for (0..repeats) |_| {
        const s = try processFile(allocator, input_path);
        if (best == null or s.processing_ns < best.?.processing_ns) {
            best = s;
        }
    }

    if (best) |s| {
        printStats(s);
    }
}
