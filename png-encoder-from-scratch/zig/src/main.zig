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

const PpmImage = struct {
    width: usize,
    height: usize,
    rgb: []const u8,
};

const Config = struct {
    input: []const u8,
    output: []const u8,
    repeats: usize,
};

fn parseArgs(allocator: std.mem.Allocator) !Config {
    var args = std.process.args();
    _ = args.next();

    const input = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/sample.ppm");
    errdefer allocator.free(input);

    const output = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/tmp/output.png");
    errdefer allocator.free(output);

    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 30;
    if (repeats == 0) return error.InvalidRepeats;

    return .{ .input = input, .output = output, .repeats = repeats };
}

fn isSpace(b: u8) bool {
    return b == ' ' or b == '\n' or b == '\r' or b == '\t';
}

fn nextToken(data: []const u8, idx: *usize) ![]const u8 {
    while (idx.* < data.len) {
        if (data[idx.*] == '#') {
            while (idx.* < data.len and data[idx.*] != '\n') : (idx.* += 1) {}
        } else if (isSpace(data[idx.*])) {
            idx.* += 1;
        } else {
            break;
        }
    }

    if (idx.* >= data.len) return error.UnexpectedEof;

    const start = idx.*;
    while (idx.* < data.len and !isSpace(data[idx.*])) : (idx.* += 1) {}
    return data[start..idx.*];
}

fn parsePpm(data: []const u8) !PpmImage {
    var idx: usize = 0;
    const magic = try nextToken(data, &idx);
    if (!std.mem.eql(u8, magic, "P6")) return error.UnsupportedFormat;

    const w_tok = try nextToken(data, &idx);
    const h_tok = try nextToken(data, &idx);
    const max_tok = try nextToken(data, &idx);

    const width = try std.fmt.parseInt(usize, w_tok, 10);
    const height = try std.fmt.parseInt(usize, h_tok, 10);
    const maxv = try std.fmt.parseInt(u32, max_tok, 10);

    if (width == 0 or height == 0 or maxv != 255) return error.InvalidHeader;

    while (idx < data.len and isSpace(data[idx])) : (idx += 1) {}

    const expected = width * height * 3;
    if (idx + expected > data.len) return error.PayloadTooShort;

    return .{ .width = width, .height = height, .rgb = data[idx .. idx + expected] };
}

fn adler32(data: []const u8) u32 {
    const mod: u32 = 65521;
    var s1: u32 = 1;
    var s2: u32 = 0;
    for (data) |b| {
        s1 = (s1 + b) % mod;
        s2 = (s2 + s1) % mod;
    }
    return (s2 << 16) | s1;
}

fn crc32(data: []const u8) u32 {
    var crc: u32 = 0xffff_ffff;
    for (data) |b| {
        crc ^= @as(u32, b);
        var i: u8 = 0;
        while (i < 8) : (i += 1) {
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ 0xedb8_8320;
            } else {
                crc >>= 1;
            }
        }
    }
    return ~crc;
}

fn appendChunk(out: *std.ArrayList(u8), allocator: std.mem.Allocator, chunk_type: []const u8, payload: []const u8) !void {
    var len_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_buf, @intCast(payload.len), .big);
    try out.appendSlice(allocator, &len_buf);
    try out.appendSlice(allocator, chunk_type);
    try out.appendSlice(allocator, payload);

    var crc_data = std.ArrayList(u8){};
    defer crc_data.deinit(allocator);
    try crc_data.appendSlice(allocator, chunk_type);
    try crc_data.appendSlice(allocator, payload);

    var crc_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_buf, crc32(crc_data.items), .big);
    try out.appendSlice(allocator, &crc_buf);
}

fn zlibStored(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    try out.append(allocator, 0x78);
    try out.append(allocator, 0x01);

    var offset: usize = 0;
    while (offset < raw.len) {
        const remaining = raw.len - offset;
        const block = if (remaining > 65535) 65535 else remaining;
        const final_flag: u8 = if (offset + block == raw.len) 1 else 0;
        try out.append(allocator, final_flag);

        var len_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &len_buf, @intCast(block), .little);
        try out.appendSlice(allocator, &len_buf);

        var nlen_buf: [2]u8 = undefined;
        std.mem.writeInt(u16, &nlen_buf, ~@as(u16, @intCast(block)), .little);
        try out.appendSlice(allocator, &nlen_buf);

        try out.appendSlice(allocator, raw[offset .. offset + block]);
        offset += block;
    }

    var ad_buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &ad_buf, adler32(raw), .big);
    try out.appendSlice(allocator, &ad_buf);

    return out.toOwnedSlice(allocator);
}

fn encodePng(allocator: std.mem.Allocator, width: usize, height: usize, rgb: []const u8) ![]u8 {
    if (rgb.len != width * height * 3) return error.InvalidRgbPayload;

    const stride = width * 3;
    var raw = std.ArrayList(u8){};
    defer raw.deinit(allocator);
    try raw.ensureTotalCapacity(allocator, height * (stride + 1));

    for (0..height) |y| {
        try raw.append(allocator, 0);
        const start = y * stride;
        try raw.appendSlice(allocator, rgb[start .. start + stride]);
    }

    const idat = try zlibStored(allocator, raw.items);
    defer allocator.free(idat);

    var out = std.ArrayList(u8){};
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, &[_]u8{ 137, 80, 78, 71, 13, 10, 26, 10 });

    var ihdr: [13]u8 = [_]u8{0} ** 13;
    std.mem.writeInt(u32, ihdr[0..4], @intCast(width), .big);
    std.mem.writeInt(u32, ihdr[4..8], @intCast(height), .big);
    ihdr[8] = 8;
    ihdr[9] = 2;

    try appendChunk(&out, allocator, "IHDR", &ihdr);
    try appendChunk(&out, allocator, "IDAT", idat);
    try appendChunk(&out, allocator, "IEND", &[_]u8{});

    return out.toOwnedSlice(allocator);
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

    const data = std.fs.cwd().readFileAlloc(allocator, cfg.input, 1024 * 1024 * 64) catch |err| {
        std.debug.print("Error: read file: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer allocator.free(data);

    const image = parsePpm(data) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    var timer = try std.time.Timer.start();
    var png: []u8 = &[_]u8{};
    for (0..cfg.repeats) |_| {
        if (png.len > 0) allocator.free(png);
        png = encodePng(allocator, image.width, image.height, image.rgb) catch |err| {
            std.debug.print("Error: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
    }
    defer if (png.len > 0) allocator.free(png);

    std.fs.cwd().writeFile(.{ .sub_path = cfg.output, .data = png }) catch |err| {
        std.debug.print("Error: write file: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    const total = image.width * image.height * cfg.repeats;
    printStats(.{ .total_processed = @intCast(total), .processing_ns = timer.read() });
}
