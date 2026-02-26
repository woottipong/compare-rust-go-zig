const std = @import("std");

const Target = struct {
    expected_up: bool,
    base_ms: usize,
    jitter_ms: usize,
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

    const input = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/targets.csv");
    const loops = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 5000;
    if (loops == 0) return error.InvalidLoops;

    return .{ .input = input, .loops = loops };
}

fn parseTarget(line: []const u8) !Target {
    var it = std.mem.splitScalar(u8, line, ',');
    _ = it.next() orelse return error.InvalidCsv;
    _ = it.next() orelse return error.InvalidCsv;

    const expected_up_text = std.mem.trim(u8, it.next() orelse return error.InvalidCsv, " \t\r\n");
    const base_ms_text = std.mem.trim(u8, it.next() orelse return error.InvalidCsv, " \t\r\n");
    const jitter_ms_text = std.mem.trim(u8, it.next() orelse return error.InvalidCsv, " \t\r\n");

    if (it.next() != null) return error.InvalidCsv;

    const expected_up = std.mem.eql(u8, expected_up_text, "true") or std.mem.eql(u8, expected_up_text, "1");
    if (!expected_up and !(std.mem.eql(u8, expected_up_text, "false") or std.mem.eql(u8, expected_up_text, "0"))) {
        return error.InvalidExpectedUp;
    }

    return .{
        .expected_up = expected_up,
        .base_ms = try std.fmt.parseInt(usize, base_ms_text, 10),
        .jitter_ms = try std.fmt.parseInt(usize, jitter_ms_text, 10),
    };
}

fn loadTargets(allocator: std.mem.Allocator, path: []const u8) ![]Target {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 32);
    defer allocator.free(data);

    var list = std.ArrayList(Target){};
    defer list.deinit(allocator);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const target = try parseTarget(trimmed);
        try list.append(allocator, target);
    }

    if (list.items.len == 0) return error.NoTargets;
    return try list.toOwnedSlice(allocator);
}

fn evaluateStatus(target: Target, iteration: usize, idx: usize) struct { up: bool, latency: usize } {
    const seed = (iteration + 1) * 31 + (idx + 1) * 17;
    const latency = target.base_ms + (seed % (target.jitter_ms + 1));
    const flap = seed % 97 == 0;
    var up = target.expected_up;
    if (flap) up = !up;
    return .{ .up = up, .latency = latency };
}

fn runChecks(allocator: std.mem.Allocator, targets: []const Target, loops: usize) !u64 {
    const fail_limit: usize = 3;
    const recover_limit: usize = 2;
    const alert_cooldown_ticks: usize = 8;

    var fail_streak = try allocator.alloc(usize, targets.len);
    defer allocator.free(fail_streak);
    var recover_streak = try allocator.alloc(usize, targets.len);
    defer allocator.free(recover_streak);
    var cooldown = try allocator.alloc(usize, targets.len);
    defer allocator.free(cooldown);

    @memset(fail_streak, 0);
    @memset(recover_streak, 0);
    @memset(cooldown, 0);

    var processed: u64 = 0;
    var alerts: u64 = 0;

    for (0..loops) |iteration| {
        for (targets, 0..) |target, idx| {
            processed += 1;
            cooldown[idx] = if (cooldown[idx] > 0) cooldown[idx] - 1 else 0;

            const s = evaluateStatus(target, iteration, idx);
            if (s.latency > 0 and !s.up) {
                fail_streak[idx] += 1;
                recover_streak[idx] = 0;
            } else {
                recover_streak[idx] += 1;
                fail_streak[idx] = 0;
            }

            if (fail_streak[idx] >= fail_limit and cooldown[idx] == 0) {
                alerts += 1;
                cooldown[idx] = alert_cooldown_ticks;
                continue;
            }
            if (recover_streak[idx] >= recover_limit and cooldown[idx] == 0) {
                alerts += 1;
            }
        }
    }

    return processed + alerts;
}

fn printStats(s: Stats) void {
    std.debug.print("--- Statistics ---\n", .{});
    std.debug.print("Total processed: {d}\n", .{s.total_processed});
    std.debug.print("Processing time: {d:.3}s\n", .{@as(f64, @floatFromInt(s.processing_ns)) / 1_000_000_000.0});
    std.debug.print("Average latency: {d:.6}ms\n", .{s.avgLatencyMs()});
    std.debug.print("Throughput: {d:.2} checks/sec\n", .{s.throughput()});
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

    const targets = loadTargets(allocator, cfg.input) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer allocator.free(targets);

    var timer = try std.time.Timer.start();
    const total = runChecks(allocator, targets, cfg.loops) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    printStats(.{ .total_processed = total, .processing_ns = timer.read() });
}
