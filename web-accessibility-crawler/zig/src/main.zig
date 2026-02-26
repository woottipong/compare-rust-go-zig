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
    const input_path = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/pages.html");
    errdefer allocator.free(input_path);
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 100000;
    if (repeats == 0) return error.InvalidRepeats;
    return .{ .input_path = input_path, .repeats = repeats };
}

fn loadPages(allocator: std.mem.Allocator, input_path: []const u8) !std.ArrayList([]u8) {
    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(content);

    var pages = std.ArrayList([]u8){};
    errdefer pages.deinit(allocator);

    var split_it = std.mem.splitSequence(u8, content, "\n===\n");
    while (split_it.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \r\n\t");
        if (trimmed.len == 0) continue;
        try pages.append(allocator, try allocator.dupe(u8, trimmed));
    }

    if (pages.items.len == 0) return error.NoPages;
    return pages;
}

fn countIssues(page: []const u8) u64 {
    var issues: u64 = 0;
    if (std.mem.indexOf(u8, page, "<html") == null or std.mem.indexOf(u8, page, "lang=") == null) issues += 1;
    if (std.mem.indexOf(u8, page, "<title") == null) issues += 1;

    var img_count: u64 = 0;
    var alt_count: u64 = 0;
    var idx: usize = 0;
    while (std.mem.indexOfPos(u8, page, idx, "<img")) |pos| {
        img_count += 1;
        idx = pos + 4;
    }
    idx = 0;
    while (std.mem.indexOfPos(u8, page, idx, "alt=")) |pos| {
        alt_count += 1;
        idx = pos + 4;
    }
    if (alt_count < img_count) issues += img_count - alt_count;

    if (std.mem.indexOf(u8, page, "<a ") != null and std.mem.indexOf(u8, page, "aria-label=") == null) issues += 1;
    return issues;
}

fn runBenchmark(pages: []const []u8, repeats: usize) u64 {
    var processed: u64 = 0;
    for (0..repeats) |_| {
        for (pages) |p| {
            _ = countIssues(p);
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

    var pages = loadPages(allocator, cfg.input_path) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer {
        for (pages.items) |p| allocator.free(p);
        pages.deinit(allocator);
    }

    var timer = try std.time.Timer.start();
    const processed = runBenchmark(pages.items, cfg.repeats);
    printStats(.{ .total_processed = processed, .processing_ns = timer.read() });
}
