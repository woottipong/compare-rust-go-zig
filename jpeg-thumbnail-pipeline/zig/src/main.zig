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

const Config = struct {
    input: []const u8,
    output: []const u8,
    width: usize,
    height: usize,
    repeats: usize,
};

fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = std.process.args();
    _ = args.next();

    const input = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/sample.jpg");
    errdefer allocator.free(input);

    const output = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/tmp/output.jpg");
    errdefer allocator.free(output);

    const width = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 160;
    const height = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 90;
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 20;

    if (width == 0 or height == 0 or repeats == 0) return error.InvalidArgs;

    return .{ .input = input, .output = output, .width = width, .height = height, .repeats = repeats };
}

fn runFfmpeg(allocator: std.mem.Allocator, input: []const u8, output: []const u8, width: usize, height: usize) !void {
    const scale = try std.fmt.allocPrint(allocator, "scale={d}:{d}:flags=bilinear", .{ width, height });
    defer allocator.free(scale);

    const argv = [_][]const u8{ "ffmpeg", "-loglevel", "error", "-y", "-i", input, "-vf", scale, "-frames:v", "1", output };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    const term = try child.wait();

    switch (term) {
        .Exited => |code| {
            if (code != 0) return error.FfmpegFailed;
        },
        else => return error.FfmpegFailed,
    }
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
    defer allocator.free(cfg.output);

    _ = std.fs.cwd().access(cfg.input, .{}) catch {
        std.debug.print("Error: input not found: {s}\n", .{cfg.input});
        std.process.exit(1);
    };

    var timer = try std.time.Timer.start();
    for (0..cfg.repeats) |_| {
        runFfmpeg(allocator, cfg.input, cfg.output, cfg.width, cfg.height) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
    }

    const total = cfg.width * cfg.height * cfg.repeats;
    printStats(.{ .total_processed = @intCast(total), .processing_ns = timer.read() });
}
