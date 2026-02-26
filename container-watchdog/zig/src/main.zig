const std = @import("std");

const Sample = struct {
    cpu: f64,
    mem: f64,
};

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

fn parseArgs(allocator: std.mem.Allocator) !struct { input: []const u8, loops: usize } {
    var args = std.process.args();
    _ = args.next();

    const input = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/metrics.csv");
    const loops = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 200;
    if (loops == 0) return error.InvalidLoops;

    return .{ .input = input, .loops = loops };
}

fn parseLine(line: []const u8) !Sample {
    var it = std.mem.splitScalar(u8, line, ',');
    _ = it.next() orelse return error.InvalidCsv;
    const cpu_txt = it.next() orelse return error.InvalidCsv;
    const mem_txt = it.next() orelse return error.InvalidCsv;

    const cpu = try std.fmt.parseFloat(f64, std.mem.trim(u8, cpu_txt, " \t\r\n"));
    const mem = try std.fmt.parseFloat(f64, std.mem.trim(u8, mem_txt, " \t\r\n"));
    return .{ .cpu = cpu, .mem = mem };
}

fn loadSamples(allocator: std.mem.Allocator, path: []const u8) ![]Sample {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 32);
    defer allocator.free(data);

    var list = std.ArrayList(Sample){};
    defer list.deinit(allocator);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const s = try parseLine(trimmed);
        try list.append(allocator, s);
    }

    if (list.items.len == 0) return error.NoSamples;
    return try list.toOwnedSlice(allocator);
}

fn process(samples: []const Sample, loops: usize) u64 {
    const cpu_threshold = 85.0;
    const mem_threshold = 90.0;
    const streak_limit: usize = 3;
    const cooldown_ticks: usize = 20;

    var cpu_streak: usize = 0;
    var mem_streak: usize = 0;
    var cooldown: usize = 0;
    var actions: u64 = 0;
    var processed: u64 = 0;

    for (0..loops) |_| {
        for (samples) |sample| {
            processed += 1;
            if (cooldown > 0) cooldown -= 1;

            if (sample.cpu > cpu_threshold) cpu_streak += 1 else cpu_streak = 0;
            if (sample.mem > mem_threshold) mem_streak += 1 else mem_streak = 0;

            if (mem_streak >= streak_limit and cooldown == 0) {
                actions += 1;
                cooldown = cooldown_ticks;
                mem_streak = 0;
                cpu_streak = 0;
                continue;
            }
            if (cpu_streak >= streak_limit) {
                actions += 1;
                cpu_streak = 0;
            }
        }
    }

    return processed + actions;
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

    const samples = loadSamples(allocator, cfg.input) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer allocator.free(samples);

    var timer = try std.time.Timer.start();
    const total = process(samples, cfg.loops);
    printStats(.{ .total_processed = total, .processing_ns = timer.read() });
}
