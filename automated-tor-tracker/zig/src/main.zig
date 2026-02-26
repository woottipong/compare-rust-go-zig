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

fn parseArgs(allocator: std.mem.Allocator) !struct { input_path: []const u8, repeats: usize } {
    var args = std.process.args();
    _ = args.next();
    const input_path = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/tor.txt");
    errdefer allocator.free(input_path);
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 20000;
    if (repeats == 0) return error.InvalidRepeats;
    return .{ .input_path = input_path, .repeats = repeats };
}

fn loadLines(allocator: std.mem.Allocator, input_path: []const u8) !std.ArrayList([]u8) {
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 8 * 1024 * 1024);
    defer allocator.free(content);

    var lines = std.ArrayList([]u8){};
    errdefer lines.deinit(allocator);

    var split_it = std.mem.splitScalar(u8, content, '\n');
    while (split_it.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \r\n\t");
        if (trimmed.len == 0) continue;
        try lines.append(allocator, try allocator.dupe(u8, trimmed));
    }

    if (lines.items.len == 0) return error.EmptyInput;
    return lines;
}

fn extractStatus(line: []const u8) []const u8 {
    if (std.mem.indexOf(u8, line, "done") != null or std.mem.indexOf(u8, line, "completed") != null) return "done";
    if (std.mem.indexOf(u8, line, "in progress") != null or std.mem.indexOf(u8, line, "ongoing") != null) return "in_progress";
    if (std.mem.indexOf(u8, line, "blocked") != null or std.mem.indexOf(u8, line, "risk") != null) return "blocked";
    return "todo";
}

fn runBenchmark(lines: []const []u8, repeats: usize) u64 {
    var processed: u64 = 0;
    for (0..repeats) |_| {
        for (lines) |line| {
            _ = extractStatus(line);
            processed += 1;
        }
    }
    return processed;
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
    defer allocator.free(cfg.input_path);

    var lines = loadLines(allocator, cfg.input_path) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    var timer = try std.time.Timer.start();
    const processed = runBenchmark(lines.items, cfg.repeats);
    printStats(.{ .total_processed = processed, .processing_ns = timer.read() });
}
