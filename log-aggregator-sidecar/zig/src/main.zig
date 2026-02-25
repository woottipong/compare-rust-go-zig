const std = @import("std");

// ============================================================================
// Data Structures
// ============================================================================

const LogEntry = struct {
    timestamp: []const u8,
    level: []const u8,
    app: []const u8,
    pid: u32,
    message: []const u8,
    source: []const u8,
};

const StatsSnapshot = struct {
    total_processed: u64,
    total_bytes: u64,
    processing_time: f64,
    throughput: f64,
};

const Stats = struct {
    total_processed: std.atomic.Value(u64),
    total_bytes: std.atomic.Value(u64),
    start_time: i128,

    fn init() Stats {
        return Stats{
            .total_processed = std.atomic.Value(u64).init(0),
            .total_bytes = std.atomic.Value(u64).init(0),
            .start_time = std.time.nanoTimestamp(),
        };
    }

    fn addEntry(self: *Stats, bytes: usize) void {
        _ = self.total_processed.fetchAdd(1, .monotonic);
        _ = self.total_bytes.fetchAdd(@intCast(bytes), .monotonic);
    }

    fn snapshot(self: *Stats) StatsSnapshot {
        const total = self.total_processed.load(.monotonic);
        const bytes = self.total_bytes.load(.monotonic);
        const elapsed_ns = std.time.nanoTimestamp() - self.start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        const throughput = if (elapsed_s > 0.0) @as(f64, @floatFromInt(total)) / elapsed_s else 0.0;
        return StatsSnapshot{
            .total_processed = total,
            .total_bytes = bytes,
            .processing_time = elapsed_s,
            .throughput = throughput,
        };
    }

    fn toJson(self: *Stats, allocator: std.mem.Allocator) ![]u8 {
        return std.json.Stringify.valueAlloc(allocator, self.snapshot(), .{});
    }

    fn printStats(self: *Stats) void {
        const s = self.snapshot();
        std.debug.print("--- Statistics ---\n", .{});
        std.debug.print("Total processed: {d}\n", .{s.total_processed});
        std.debug.print("Processing time: {d:.3}s\n", .{s.processing_time});
        std.debug.print("Throughput: {d:.2} lines/sec\n", .{s.throughput});
    }
};

// ============================================================================
// Configuration
// ============================================================================

const Config = struct {
    input_file: []u8,
    output_url: []u8,
    buffer_size: usize,
    workers: usize,
    one_shot: bool,

    fn parse(allocator: std.mem.Allocator) !Config {
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        var input_file: []u8 = &[_]u8{};
        var output_url: []u8 = &[_]u8{};
        var buffer_size: usize = 1000;
        var workers: usize = 4;
        var one_shot: bool = false;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--input") and i + 1 < args.len) {
                input_file = try allocator.dupe(u8, args[i + 1]);
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--output") and i + 1 < args.len) {
                output_url = try allocator.dupe(u8, args[i + 1]);
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--buffer") and i + 1 < args.len) {
                buffer_size = try std.fmt.parseInt(usize, args[i + 1], 10);
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--workers") and i + 1 < args.len) {
                workers = try std.fmt.parseInt(usize, args[i + 1], 10);
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--one-shot")) {
                one_shot = true;
            }
        }

        if (input_file.len == 0 or output_url.len == 0) {
            std.debug.print("Usage: log-aggregator --input <file> --output <url> [--buffer <size>] [--workers <count>] [--one-shot]\n", .{});
            std.process.exit(1);
        }

        return Config{
            .input_file = input_file,
            .output_url = output_url,
            .buffer_size = buffer_size,
            .workers = workers,
            .one_shot = one_shot,
        };
    }

    fn print(self: Config) void {
        std.debug.print("── Configuration ─────────────────────\n", .{});
        std.debug.print("  Input File : {s}\n", .{self.input_file});
        std.debug.print("  Output URL : {s}\n", .{self.output_url});
        std.debug.print("  Buffer     : {d}\n", .{self.buffer_size});
        std.debug.print("  Workers    : {d}\n", .{self.workers});
        std.debug.print("\n", .{});
    }
};

// ============================================================================
// Log Parser
// ============================================================================

// Parse log format: "2023-03-15 10:30:45 INFO auth[5]: User 1234 login from 192.168.1.100"
fn parseLogLine(line: []const u8, source: []const u8, allocator: std.mem.Allocator) !LogEntry {
    const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

    const colon_seq = "]: ";
    if (std.mem.indexOf(u8, trimmed, colon_seq) == null or trimmed.len < 20) {
        return LogEntry{
            .timestamp = try allocator.dupe(u8, "unknown"),
            .level = try allocator.dupe(u8, "UNKNOWN"),
            .app = try allocator.dupe(u8, "raw"),
            .pid = 0,
            .message = try allocator.dupe(u8, trimmed),
            .source = source,
        };
    }

    const timestamp = try allocator.dupe(u8, trimmed[0..19]);
    const rest = if (trimmed.len > 20) trimmed[20..] else "";

    const space_pos = std.mem.indexOf(u8, rest, " ") orelse rest.len;
    const level = try allocator.dupe(u8, rest[0..space_pos]);

    const after_level = if (space_pos + 1 < rest.len) rest[space_pos + 1 ..] else "";

    var app: []u8 = try allocator.dupe(u8, "raw");
    var pid: u32 = 0;

    if (std.mem.indexOf(u8, after_level, "[")) |bracket_open| {
        allocator.free(app);
        app = try allocator.dupe(u8, after_level[0..bracket_open]);
        if (std.mem.indexOf(u8, after_level, "]")) |bracket_close| {
            if (bracket_close > bracket_open) {
                pid = std.fmt.parseInt(u32, after_level[bracket_open + 1 .. bracket_close], 10) catch 0;
            }
        }
    }

    const colon_pos = std.mem.indexOf(u8, trimmed, colon_seq).?;
    const message = try allocator.dupe(u8, std.mem.trim(u8, trimmed[colon_pos + colon_seq.len ..], &std.ascii.whitespace));

    return LogEntry{
        .timestamp = timestamp,
        .level = level,
        .app = app,
        .pid = pid,
        .message = message,
        .source = source,
    };
}

fn freeLogEntry(entry: LogEntry, allocator: std.mem.Allocator) void {
    allocator.free(entry.timestamp);
    allocator.free(entry.level);
    allocator.free(entry.app);
    allocator.free(entry.message);
}

// ============================================================================
// Forwarder
// ============================================================================

const BATCH_SIZE: usize = 100;
const FLUSH_INTERVAL_NS: u64 = 1000 * std.time.ns_per_ms;

const Forwarder = struct {
    allocator: std.mem.Allocator,
    client: std.http.Client,
    output_url: []const u8,
    batch: std.ArrayList(LogEntry),
    batch_mutex: std.Thread.Mutex,
    stats: *Stats,
    flush_thread: ?std.Thread,
    running: std.atomic.Value(bool),

    fn init(allocator: std.mem.Allocator, output_url: []const u8, stats: *Stats) !Forwarder {
        return Forwarder{
            .allocator = allocator,
            .client = std.http.Client{ .allocator = allocator },
            .output_url = output_url,
            .batch = try std.ArrayList(LogEntry).initCapacity(allocator, BATCH_SIZE),
            .batch_mutex = std.Thread.Mutex{},
            .stats = stats,
            .flush_thread = null,
            .running = std.atomic.Value(bool).init(true),
        };
    }

    fn deinit(self: *Forwarder) void {
        self.running.store(false, .monotonic);
        if (self.flush_thread) |thread| {
            thread.join();
        }
        self.batch.deinit(self.allocator);
        self.client.deinit();
    }

    fn start(self: *Forwarder) !void {
        self.flush_thread = try std.Thread.spawn(.{}, Forwarder.flushWorker, .{self});
    }

    fn send(self: *Forwarder, entry: LogEntry) !void {
        self.batch_mutex.lock();
        defer self.batch_mutex.unlock();

        try self.batch.append(self.allocator, entry);

        if (self.batch.items.len >= BATCH_SIZE) {
            self.flushBatch() catch |err| {
                std.debug.print("Flush error: {}\n", .{err});
            };
        }
    }

    fn buildJsonBatch(self: *Forwarder) ![]u8 {
        var buf = std.ArrayList(u8){};
        errdefer buf.deinit(self.allocator);

        try buf.append(self.allocator, '[');
        for (self.batch.items, 0..) |entry, i| {
            if (i > 0) try buf.append(self.allocator, ',');
            const entry_json = try std.json.Stringify.valueAlloc(self.allocator, entry, .{});
            defer self.allocator.free(entry_json);
            try buf.appendSlice(self.allocator, entry_json);
        }
        try buf.append(self.allocator, ']');

        return buf.toOwnedSlice(self.allocator);
    }

    fn flushBatch(self: *Forwarder) !void {
        if (self.batch.items.len == 0) return;

        const json_data = try self.buildJsonBatch();
        defer self.allocator.free(json_data);

        const batch_count = self.batch.items.len;
        for (0..batch_count) |_| {
            self.stats.addEntry(json_data.len / batch_count);
        }

        for (self.batch.items) |entry| {
            freeLogEntry(entry, self.allocator);
        }
        self.batch.clearRetainingCapacity();

        // Send batch over HTTP
        const result = self.client.fetch(.{
            .location = .{ .url = self.output_url },
            .method = .POST,
            .payload = json_data,
            .extra_headers = &.{.{ .name = "Content-Type", .value = "application/json" }},
        }) catch |err| {
            std.debug.print("HTTP fetch error: {}\n", .{err});
            return;
        };
        _ = result;
    }

    fn flushWorker(self: *Forwarder) void {
        var last_flush = std.time.nanoTimestamp();

        while (self.running.load(.monotonic)) {
            const now = std.time.nanoTimestamp();
            if (@as(u64, @intCast(now - last_flush)) >= FLUSH_INTERVAL_NS) {
                self.batch_mutex.lock();
                self.flushBatch() catch |err| {
                    std.debug.print("Flush error: {}\n", .{err});
                };
                self.batch_mutex.unlock();
                last_flush = now;
            }
            std.Thread.sleep(100 * std.time.ns_per_ms);
        }

        self.batch_mutex.lock();
        self.flushBatch() catch {};
        self.batch_mutex.unlock();
    }
};

// ============================================================================
// File Processing
// ============================================================================

fn processFile(filename: []const u8, forwarder: *Forwarder, allocator: std.mem.Allocator) !usize {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 512 * 1024 * 1024);
    defer allocator.free(content);

    var line_count: usize = 0;
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        if (std.mem.trim(u8, line, &std.ascii.whitespace).len == 0) continue;
        const entry = try parseLogLine(line, filename, allocator);
        try forwarder.send(entry);
        line_count += 1;
    }

    if (line_count > 0) {
        std.debug.print("Processed {d} lines from {s}\n", .{ line_count, filename });
    }

    return line_count;
}

// ============================================================================
// File Watcher (polling — Zig 0.15 std has no inotify watcher)
// ============================================================================

fn watchFile(config: Config, forwarder: *Forwarder, allocator: std.mem.Allocator) !void {
    _ = processFile(config.input_file, forwarder, allocator) catch |err| {
        std.debug.print("Error processing initial file: {}\n", .{err});
    };

    std.debug.print("Watching {s} for changes (polling every 500ms)...\n", .{config.input_file});

    var last_mtime: i128 = 0;
    while (true) {
        const stat = std.fs.cwd().statFile(config.input_file) catch |err| {
            std.debug.print("Stat error: {}\n", .{err});
            std.Thread.sleep(500 * std.time.ns_per_ms);
            continue;
        };

        const mtime: i128 = stat.mtime;
        if (last_mtime != 0 and mtime != last_mtime) {
            _ = processFile(config.input_file, forwarder, allocator) catch |err| {
                std.debug.print("Error processing file: {}\n", .{err});
            };
        }
        last_mtime = mtime;
        std.Thread.sleep(500 * std.time.ns_per_ms);
    }
}

// ============================================================================
// HTTP Server
// ============================================================================

fn httpServer(stats: *Stats, allocator: std.mem.Allocator) !void {
    const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        const connection = server.accept() catch |err| {
            std.debug.print("Accept error: {}\n", .{err});
            continue;
        };
        handleConnection(connection, stats, allocator) catch |err| {
            std.debug.print("Connection error: {}\n", .{err});
        };
    }
}

fn handleConnection(connection: std.net.Server.Connection, stats: *Stats, allocator: std.mem.Allocator) !void {
    defer connection.stream.close();

    var buffer: [4096]u8 = undefined;
    const n = connection.stream.read(&buffer) catch return;
    const request = buffer[0..n];

    if (std.mem.indexOf(u8, request, "GET /health") != null) {
        _ = try connection.stream.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}");
    } else if (std.mem.indexOf(u8, request, "GET /stats") != null) {
        const stats_json = try stats.toJson(allocator);
        defer allocator.free(stats_json);
        var hdr_buf: [256]u8 = undefined;
        const header = try std.fmt.bufPrint(&hdr_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\n\r\n", .{stats_json.len});
        _ = try connection.stream.write(header);
        _ = try connection.stream.write(stats_json);
    } else {
        _ = try connection.stream.write("HTTP/1.1 404 Not Found\r\n\r\nNot Found");
    }
}

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try Config.parse(allocator);
    config.print();

    var stats = Stats.init();
    var forwarder = try Forwarder.init(allocator, config.output_url, &stats);
    defer forwarder.deinit();

    try forwarder.start();

    if (config.one_shot) {
        _ = try processFile(config.input_file, &forwarder, allocator);
        // Signal flush thread to stop and wait for it to drain remaining batch
        forwarder.running.store(false, .monotonic);
        if (forwarder.flush_thread) |thread| {
            thread.join();
            forwarder.flush_thread = null;
        }
        stats.printStats();
        return;
    }

    const http_thread = try std.Thread.spawn(.{}, httpServer, .{ &stats, allocator });
    _ = http_thread;

    try watchFile(config, &forwarder, allocator);
}
