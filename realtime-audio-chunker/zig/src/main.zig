const std = @import("std");

const SAMPLE_RATE = 16000;
const CHANNELS = 1;
const BYTES_PER_SAMPLE = 2; // 16-bit PCM
const CHUNK_DURATION_MS = 25;
const OVERLAP_DURATION_MS = 10;
const INPUT_INTERVAL_MS = 10;
const INPUT_INTERVAL_NS = INPUT_INTERVAL_MS * std.time.ns_per_ms;

fn bytesForMs(duration_ms: usize) usize {
    return SAMPLE_RATE * duration_ms / 1000 * CHANNELS * BYTES_PER_SAMPLE;
}

const AudioChunk = struct {
    data: []const u8,
    timestamp: std.time.Instant,
    index: usize,
};

const Stats = struct {
    total_latency_ns: u64 = 0,
    chunk_count: usize = 0,

    fn avgLatencyMs(self: Stats) f64 {
        if (self.chunk_count == 0) return 0.0;
        return @as(f64, @floatFromInt(self.total_latency_ns / self.chunk_count)) / 1_000_000.0;
    }

    fn throughput(self: Stats, processing_ns: u64) f64 {
        if (processing_ns == 0) return 0.0;
        return @as(f64, @floatFromInt(self.chunk_count)) / (@as(f64, @floatFromInt(processing_ns)) / 1_000_000_000.0);
    }
};

const AudioChunker = struct {
    chunk_size: usize,
    overlap_size: usize,
    buffer: []u8,
    buffer_pos: usize,
    chunk_index: usize,
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) !AudioChunker {
        const chunk_size = bytesForMs(CHUNK_DURATION_MS);
        return AudioChunker{
            .chunk_size = chunk_size,
            .overlap_size = bytesForMs(OVERLAP_DURATION_MS),
            .buffer = try allocator.alloc(u8, chunk_size * 2),
            .buffer_pos = 0,
            .chunk_index = 0,
            .allocator = allocator,
        };
    }

    fn deinit(self: *AudioChunker) void {
        self.allocator.free(self.buffer);
    }

    fn processAudio(self: *AudioChunker, data: []const u8, stats: *Stats) !void {
        if (self.buffer_pos + data.len > self.buffer.len) {
            self.buffer = try self.allocator.realloc(self.buffer, (self.buffer_pos + data.len) * 2);
        }
        @memcpy(self.buffer[self.buffer_pos..self.buffer_pos + data.len], data);
        self.buffer_pos += data.len;

        while (self.buffer_pos >= self.chunk_size) {
            const chunk = AudioChunk{
                .data = self.buffer[0..self.chunk_size],
                .timestamp = try std.time.Instant.now(),
                .index = self.chunk_index,
            };
            onAudioChunk(chunk, stats);
            self.chunk_index += 1;

            const remaining = self.buffer_pos - self.chunk_size;
            const shift_start = self.chunk_size - self.overlap_size;
            const keep_len = remaining + self.overlap_size;
            std.mem.copyForwards(u8, self.buffer[0..keep_len], self.buffer[shift_start..shift_start + keep_len]);
            self.buffer_pos = keep_len;
        }
    }
};

fn onAudioChunk(chunk: AudioChunk, stats: *Stats) void {
    const latency = (std.time.Instant.now() catch return).since(chunk.timestamp);
    stats.total_latency_ns += latency;
    stats.chunk_count += 1;
    if (chunk.index < 5 or chunk.index % 20 == 0) {
        std.debug.print("Chunk {d}: {d} bytes, latency: {d:.3}ms\n", .{
            chunk.index, chunk.data.len, @as(f64, @floatFromInt(latency)) / 1_000_000.0,
        });
    }
}

fn readWavFile(filename: []const u8, allocator: std.mem.Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    try file.seekTo(44);
    return file.readToEndAlloc(allocator, 10 * 1024 * 1024);
}

fn printConfig(audio_data_len: usize) void {
    std.debug.print("Audio data size: {d} bytes\n", .{audio_data_len});
    std.debug.print("Chunk size: {d} bytes ({d}ms)\n", .{ bytesForMs(CHUNK_DURATION_MS), CHUNK_DURATION_MS });
    std.debug.print("Overlap size: {d} bytes ({d}ms)\n", .{ bytesForMs(OVERLAP_DURATION_MS), OVERLAP_DURATION_MS });
}

fn simulateRealtimeInput(audio_data: []const u8, chunker: *AudioChunker, stats: *Stats) !void {
    const bytes_per_interval = bytesForMs(INPUT_INTERVAL_MS);
    var i: usize = 0;
    while (i < audio_data.len) {
        const end = @min(i + bytes_per_interval, audio_data.len);
        try chunker.processAudio(audio_data[i..end], stats);
        std.Thread.sleep(INPUT_INTERVAL_NS);
        i = end;
    }
}

fn printStats(stats: Stats, processing_ns: u64) void {
    std.debug.print("\n--- Statistics ---\n", .{});
    std.debug.print("Total chunks: {d}\n", .{stats.chunk_count});
    std.debug.print("Processing time: {d:.3}s\n", .{@as(f64, @floatFromInt(processing_ns)) / 1_000_000_000.0});
    std.debug.print("Average latency: {d:.3}ms\n", .{stats.avgLatencyMs()});
    std.debug.print("Throughput: {d:.2} chunks/sec\n", .{stats.throughput(processing_ns)});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.skip();
    const input_file = args.next() orelse {
        std.debug.print("Usage: realtime-audio-chunker <input.wav>\n", .{});
        std.process.exit(1);
    };

    const audio_data = try readWavFile(input_file, allocator);
    defer allocator.free(audio_data);

    std.debug.print("Processing audio file: {s}\n", .{input_file});
    printConfig(audio_data.len);

    var chunker = try AudioChunker.init(allocator);
    defer chunker.deinit();

    var stats = Stats{};
    const start_time = try std.time.Instant.now();
    try simulateRealtimeInput(audio_data, &chunker, &stats);
    const processing_ns = (try std.time.Instant.now()).since(start_time);

    if (stats.chunk_count > 0) {
        printStats(stats, processing_ns);
    }
}
