const std = @import("std");
const c = @cImport({
    @cInclude("zstd.h");
});

const Stats = struct {
    input_bytes: u64,
    compress_ns: u64,
    decompress_ns: u64,
    compressed_bytes: u64,

    fn compressThroughputMBs(self: Stats) f64 {
        if (self.compress_ns == 0) return 0.0;
        return @as(f64, @floatFromInt(self.input_bytes)) / 1e6 /
            (@as(f64, @floatFromInt(self.compress_ns)) / 1e9);
    }

    fn decompressThroughputMBs(self: Stats) f64 {
        if (self.decompress_ns == 0) return 0.0;
        return @as(f64, @floatFromInt(self.input_bytes)) / 1e6 /
            (@as(f64, @floatFromInt(self.decompress_ns)) / 1e9);
    }

    fn compressionRatio(self: Stats) f64 {
        if (self.compressed_bytes == 0) return 0.0;
        return @as(f64, @floatFromInt(self.input_bytes)) /
            @as(f64, @floatFromInt(self.compressed_bytes));
    }
};

fn processFile(allocator: std.mem.Allocator, path: []const u8) !Stats {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 512 * 1024 * 1024);
    defer allocator.free(data);

    const input_bytes = data.len;

    // Allocate compress buffer (zstd bound)
    const compress_bound = c.ZSTD_compressBound(input_bytes);
    const compress_buf = try allocator.alloc(u8, compress_bound);
    defer allocator.free(compress_buf);

    // Compress
    var compress_timer = try std.time.Timer.start();
    const compressed_size = c.ZSTD_compress(
        compress_buf.ptr,
        compress_bound,
        data.ptr,
        input_bytes,
        3, // level 3
    );
    const compress_ns = compress_timer.read();

    if (c.ZSTD_isError(compressed_size) != 0) {
        return error.CompressionFailed;
    }

    // Allocate decompress buffer
    const decompress_buf = try allocator.alloc(u8, input_bytes);
    defer allocator.free(decompress_buf);

    // Decompress
    var decompress_timer = try std.time.Timer.start();
    const decompressed_size = c.ZSTD_decompress(
        decompress_buf.ptr,
        input_bytes,
        compress_buf.ptr,
        compressed_size,
    );
    const decompress_ns = decompress_timer.read();

    if (c.ZSTD_isError(decompressed_size) != 0) {
        return error.DecompressionFailed;
    }

    // Verify round-trip
    if (decompressed_size != input_bytes) {
        return error.RoundTripMismatch;
    }

    return Stats{
        .input_bytes = @intCast(input_bytes),
        .compress_ns = compress_ns,
        .decompress_ns = decompress_ns,
        .compressed_bytes = @intCast(compressed_size),
    };
}

fn printStats(s: Stats) void {
    std.debug.print("--- Statistics ---\n", .{});
    std.debug.print("Total processed: {d}\n", .{s.input_bytes});
    std.debug.print("Processing time: {d:.3}s\n", .{
        @as(f64, @floatFromInt(s.compress_ns + s.decompress_ns)) / 1_000_000_000.0,
    });
    std.debug.print("Average latency: {d:.6}ms\n", .{
        @as(f64, @floatFromInt(s.compress_ns + s.decompress_ns)) / 1_000_000.0,
    });
    std.debug.print("Throughput: {d:.2} items/sec\n", .{s.compressThroughputMBs()});
    std.debug.print("Input size: {d:.2} MB\n", .{@as(f64, @floatFromInt(s.input_bytes)) / 1e6});
    std.debug.print("Compressed size: {d:.2} MB\n", .{@as(f64, @floatFromInt(s.compressed_bytes)) / 1e6});
    std.debug.print("Compression ratio: {d:.2}x\n", .{s.compressionRatio()});
    std.debug.print("Compress speed: {d:.2} MB/s\n", .{s.compressThroughputMBs()});
    std.debug.print("Decompress speed: {d:.2} MB/s\n", .{s.decompressThroughputMBs()});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next();

    const input_path = args.next() orelse "/data/logs.txt";
    const repeats_str = args.next() orelse "1";
    const repeats = std.fmt.parseInt(usize, repeats_str, 10) catch 1;

    var best: ?Stats = null;

    for (0..repeats) |_| {
        const s = try processFile(allocator, input_path);
        if (best == null or (s.compress_ns + s.decompress_ns) < (best.?.compress_ns + best.?.decompress_ns)) {
            best = s;
        }
    }

    if (best) |s| {
        printStats(s);
    }
}
