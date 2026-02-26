const std = @import("std");

const size = 32;
const low_freq = 8;

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
    repeats: usize,
};

fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = std.process.args();
    _ = args.next();

    const input = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/sample.jpg");
    errdefer allocator.free(input);

    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 20;
    if (repeats == 0) return error.InvalidRepeats;

    return .{ .input = input, .repeats = repeats };
}

fn runFfmpeg(allocator: std.mem.Allocator, input: []const u8, output: []const u8) !void {
    const argv = [_][]const u8{
        "ffmpeg", "-loglevel", "error", "-y", "-i", input,
        "-vf", "scale=32:32,format=gray", "-frames:v", "1", output,
    };

    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    const term = try child.wait();
    switch (term) {
        .Exited => |code| if (code != 0) return error.FfmpegFailed,
        else => return error.FfmpegFailed,
    }
}

fn nextToken(data: []const u8, idx: *usize) ![]const u8 {
    while (idx.* < data.len) {
        if (data[idx.*] == '#') {
            while (idx.* < data.len and data[idx.*] != '\n') : (idx.* += 1) {}
        } else if (std.ascii.isWhitespace(data[idx.*])) {
            idx.* += 1;
        } else {
            break;
        }
    }
    if (idx.* >= data.len) return error.UnexpectedEof;
    const start = idx.*;
    while (idx.* < data.len and !std.ascii.isWhitespace(data[idx.*])) : (idx.* += 1) {}
    return data[start..idx.*];
}

fn parsePgm(data: []const u8) ![size][size]f64 {
    var matrix: [size][size]f64 = undefined;
    var idx: usize = 0;
    const magic = try nextToken(data, &idx);
    if (!std.mem.eql(u8, magic, "P5")) return error.InvalidFormat;

    const w = try std.fmt.parseInt(usize, try nextToken(data, &idx), 10);
    const h = try std.fmt.parseInt(usize, try nextToken(data, &idx), 10);
    const maxv = try std.fmt.parseInt(usize, try nextToken(data, &idx), 10);
    if (w != size or h != size or maxv != 255) return error.InvalidHeader;

    while (idx < data.len and std.ascii.isWhitespace(data[idx])) : (idx += 1) {}
    if (idx + size * size > data.len) return error.PayloadTooShort;

    for (0..size) |y| {
        for (0..size) |x| {
            matrix[y][x] = @floatFromInt(data[idx + y * size + x]);
        }
    }
    return matrix;
}

fn dct2d(input: [size][size]f64) [size][size]f64 {
    var out: [size][size]f64 = [_][size]f64{[_]f64{0} ** size} ** size;
    for (0..size) |u| {
        for (0..size) |v| {
            var sum: f64 = 0.0;
            for (0..size) |x| {
                for (0..size) |y| {
                    const a = @cos((@as(f64, @floatFromInt(2 * x + 1)) * @as(f64, @floatFromInt(u)) * std.math.pi) / 64.0);
                    const b = @cos((@as(f64, @floatFromInt(2 * y + 1)) * @as(f64, @floatFromInt(v)) * std.math.pi) / 64.0);
                    sum += input[y][x] * a * b;
                }
            }
            const cu = if (u == 0) 1.0 / @sqrt(@as(f64, 2.0)) else 1.0;
            const cv = if (v == 0) 1.0 / @sqrt(@as(f64, 2.0)) else 1.0;
            out[v][u] = 0.25 * cu * cv * sum;
        }
    }
    return out;
}

fn phash(matrix: [size][size]f64) u64 {
    const dct = dct2d(matrix);
    var vals: [low_freq * low_freq]f64 = undefined;
    var n: usize = 0;
    for (0..low_freq) |y| {
        for (0..low_freq) |x| {
            vals[n] = dct[y][x];
            n += 1;
        }
    }
    var sum: f64 = 0.0;
    for (vals) |v| sum += v;
    const avg = sum / @as(f64, @floatFromInt(vals.len));

    var hash: u64 = 0;
    for (vals, 0..) |v, i| {
        if (v > avg) hash |= (@as(u64, 1) << @as(u6, @intCast(i)));
    }
    return hash;
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

    _ = std.fs.cwd().access(cfg.input, .{}) catch {
        std.debug.print("Error: input not found\n", .{});
        std.process.exit(1);
    };

    const tmp = "/tmp/phash.pgm";
    var timer = try std.time.Timer.start();
    var hash: u64 = 0;

    for (0..cfg.repeats) |_| {
        runFfmpeg(allocator, cfg.input, tmp) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        const pgm = std.fs.cwd().readFileAlloc(allocator, tmp, 1024 * 1024) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer allocator.free(pgm);

        const matrix = parsePgm(pgm) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        hash = phash(matrix);
    }

    _ = std.fs.cwd().deleteFile(tmp) catch {};
    std.debug.print("pHash: {x:0>16}\n", .{hash});
    printStats(.{ .total_processed = @intCast(cfg.repeats), .processing_ns = timer.read() });
}
