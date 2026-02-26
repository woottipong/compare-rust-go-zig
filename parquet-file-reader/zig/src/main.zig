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
    repeats: usize,
};

fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = std.process.args();
    _ = args.next();

    const input = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/sample.parquet");
    errdefer allocator.free(input);

    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 40;
    if (repeats == 0) return error.InvalidRepeats;

    return .{ .input = input, .repeats = repeats };
}

fn readUvarint(data: []const u8, idx: *usize) !u64 {
    var x: u64 = 0;
    var s: u6 = 0;
    var i: usize = 0;
    while (i < 10) : (i += 1) {
        if (idx.* >= data.len) return error.UnexpectedEof;
        const b = data[idx.*];
        idx.* += 1;
        if (b < 0x80) return x | (@as(u64, b) << s);
        x |= (@as(u64, b & 0x7f) << s);
        s += 7;
    }
    return error.VarintOverflow;
}

fn unpackBitpacked(src: []const u8, bit_width: usize, count: usize, out: *std.ArrayList(u32), allocator: std.mem.Allocator) !void {
    var bit_pos: usize = 0;
    for (0..count) |_| {
        var v: u32 = 0;
        for (0..bit_width) |b| {
            const byte_idx = (bit_pos + b) / 8;
            const bit_idx = (bit_pos + b) % 8;
            if (byte_idx < src.len and ((src[byte_idx] >> @as(u3, @intCast(bit_idx))) & 1) == 1) {
                v |= (@as(u32, 1) << @as(u5, @intCast(b)));
            }
        }
        try out.append(allocator, v);
        bit_pos += bit_width;
    }
}

fn decodeHybrid(allocator: std.mem.Allocator, encoded: []const u8, bit_width: usize, expected: usize) ![]u32 {
    var values = std.ArrayList(u32){};
    errdefer values.deinit(allocator);

    var idx: usize = 0;
    while (idx < encoded.len and values.items.len < expected) {
        const h = try readUvarint(encoded, &idx);
        if ((h & 1) == 0) {
            const run: usize = @intCast(h >> 1);
            const byte_width = (bit_width + 7) / 8;
            if (idx + byte_width > encoded.len) return error.InvalidRlePayload;

            var v: u32 = 0;
            for (0..byte_width) |i| {
                v |= (@as(u32, encoded[idx + i]) << @as(u5, @intCast(8 * i)));
            }
            idx += byte_width;

            var i: usize = 0;
            while (i < run and values.items.len < expected) : (i += 1) {
                try values.append(allocator, v);
            }
        } else {
            const groups: usize = @intCast(h >> 1);
            const n = groups * 8;
            const byte_count = groups * bit_width;
            if (idx + byte_count > encoded.len) return error.InvalidBitpackPayload;
            try unpackBitpacked(encoded[idx .. idx + byte_count], bit_width, n, &values, allocator);
            idx += byte_count;
        }
    }

    if (values.items.len > expected) values.items.len = expected;
    if (values.items.len != expected) return error.DecodedSizeMismatch;

    return values.toOwnedSlice(allocator);
}

fn processFile(allocator: std.mem.Allocator, path: []const u8) !usize {
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024 * 64);
    defer allocator.free(data);

    if (data.len < 17) return error.FileTooSmall;
    if (!std.mem.eql(u8, data[0..4], "PAR1") or !std.mem.eql(u8, data[data.len - 4 ..], "PAR1")) {
        return error.InvalidMagic;
    }

    const meta_len = std.mem.readInt(u32, data[data.len - 8 ..][0..4], .little);
    if (data.len < 8 + @as(usize, meta_len) + 13) return error.InvalidMetadataLength;

    const bit_width: usize = data[4];
    const num_values = std.mem.readInt(u32, data[5..][0..4], .little);
    const encoded_len = std.mem.readInt(u32, data[9..][0..4], .little);

    const payload_end = data.len - 8 - @as(usize, meta_len);
    if (13 + @as(usize, encoded_len) > payload_end) return error.InvalidEncodedSection;

    const decoded = try decodeHybrid(allocator, data[13 .. 13 + @as(usize, encoded_len)], bit_width, @as(usize, num_values));
    defer allocator.free(decoded);

    return @as(usize, num_values);
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
    var n: usize = 0;
    for (0..cfg.repeats) |_| {
        n = processFile(allocator, cfg.input) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
    }

    printStats(.{ .total_processed = @as(u64, @intCast(n * cfg.repeats)), .processing_ns = timer.read() });
}
