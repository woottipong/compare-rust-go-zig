const std = @import("std");
const fs = std.fs;
const json = std.json;
const http = std.http;
const time = std.time;
const net = std.net;

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

const StatsResponse = struct {
    total_processed: u64,
    total_bytes: u64,
    processing_time: f64,
    throughput: f64,
};

const Stats = struct {
    total_processed: std.atomic.Value(u64),
    total_bytes: std.atomic.Value(u64),
    start_time: i64,

    fn init() Stats {
        return Stats{
            .total_processed = std.atomic.Value(u64).init(0),
            .total_bytes = std.atomic.Value(u64).init(0),
            .start_time = @intCast(std.time.nanoTimestamp()),
        };
    }

    fn addEntry(self: *Stats, bytes: usize) void {
        _ = self.total_processed.fetchAdd(1, .monotonic);
        _ = self.total_bytes.fetchAdd(bytes, .monotonic);
    }

    fn getStats(self: *Stats, allocator: std.mem.Allocator) ![]u8 {
        const total = self.total_processed.load(.monotonic);
        const bytes = self.total_bytes.load(.monotonic);
        const elapsed_ns = std.time.nanoTimestamp() - self.start_time;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;

        const throughput = if (elapsed_s > 0.0)
            @as(f64, @floatFromInt(total)) / elapsed_s
        else
            0.0;

        const response = StatsResponse{
            .total_processed = total,
            .total_bytes = bytes,
            .processing_time = elapsed_s,
            .throughput = throughput,
        };

        return json.stringifyAlloc(allocator, response, .{});
    }
};

// ============================================================================
// Configuration
// ============================================================================

const Config = struct {
    input_file: []const u8,
    output_url: []const u8,
    buffer_size: usize,
    workers: usize,

    fn parse(allocator: std.mem.Allocator) !Config {
        const args = try std.process.argsAlloc(allocator);
        defer std.process.argsFree(allocator, args);

        if (args.len < 5) {
            std.debug.print("Usage: log-aggregator --input <file> --output <url> [--buffer <size>] [--workers <count>]\n", .{});
            std.process.exit(1);
        }

        var config = Config{
            .input_file = "",
            .output_url = "",
            .buffer_size = 1000,
            .workers = 4,
        };

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--input")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Missing value for --input\n", .{});
                    std.process.exit(1);
                }
                config.input_file = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--output")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Missing value for --output\n", .{});
                    std.process.exit(1);
                }
                config.output_url = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--buffer")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Missing value for --buffer\n", .{});
                    std.process.exit(1);
                }
                config.buffer_size = try std.fmt.parseInt(usize, args[i + 1], 10);
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--workers")) {
                if (i + 1 >= args.len) {
                    std.debug.print("Missing value for --workers\n", .{});
                    std.process.exit(1);
                }
                config.workers = try std.fmt.parseInt(usize, args[i + 1], 10);
                i += 1;
            }
        }

        if (config.input_file.len == 0 or config.output_url.len == 0) {
            std.debug.print("Both --input and --output are required\n", .{});
            std.process.exit(1);
        }

        return config;
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
    var entry = LogEntry{
        .timestamp = "",
        .level = "UNKNOWN",
        .app = "raw",
        .pid = 0,
        .message = std.mem.trim(u8, line, &std.ascii.whitespace),
        .source = source,
    };

    // Fast path: check for pattern structure first
    if (std.mem.indexOf(u8, line, "]: ") == null) {
        // No structured pattern, return raw entry
        entry.timestamp = try std.fmt.allocPrint(allocator, "{s}", .{std.time.timestamp()});
        return entry;
    }

    var it = std.mem.tokenizeScalar(u8, line, ' ');
    var parts: [5][]const u8 = undefined;
    var part_count: usize = 0;

    while (it.next()) |part| {
        if (part_count < parts.len) {
            parts[part_count] = part;
            part_count += 1;
        }
    }

    if (part_count >= 5) {
        entry.timestamp = try std.fmt.allocPrint(allocator, "{s}", .{parts[0]});
        entry.level = try std.fmt.allocPrint(allocator, "{s}", .{parts[1]});
        
        // Parse app[pid]
        if (std.mem.indexOf(u8, parts[2], "[")) |bracket_pos| {
            entry.app = try std.fmt.allocPrint(allocator, "{s}", .{parts[2][0..bracket_pos]});
            
            if (std.mem.indexOf(u8, parts[2], "]")) |end_bracket_pos| {
                const pid_str = parts[2][bracket_pos + 1..end_bracket_pos];
                entry.pid = std.fmt.parseInt(u32, pid_str, 10) catch 0;
            }
        }
        
        // Extract message after ": "
        if (std.mem.indexOf(u8, line, ": ")) |colon_pos| {
            entry.message = try std.fmt.allocPrint(allocator, "{s}", .{std.mem.trim(u8, line[colon_pos + 2..], &std.ascii.whitespace)});
        }
    }

    return entry;
}

// ============================================================================
// Forwarder
// ============================================================================

const BATCH_SIZE = 100;
const FLUSH_INTERVAL_MS = 1000;

const Batch = struct {
    entries: []LogEntry,
    json_data: []u8,
};

const Forwarder = struct {
    allocator: std.mem.Allocator,
    client: http.Client,
    output_url: []const u8,
    batch: std.ArrayList(LogEntry),
    batch_mutex: std.Thread.Mutex,
    stats: *Stats,
    flush_thread: ?std.Thread,
    running: std.atomic.Value(bool),

    fn init(allocator: std.mem.Allocator, output_url: []const u8, stats: *Stats) Forwarder {
        return Forwarder{
            .allocator = allocator,
            .client = http.Client{ .allocator = allocator },
            .output_url = output_url,
            .batch = std.ArrayList(LogEntry).initCapacity(allocator, 1000) catch unreachable,
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
    }

    fn start(self: *Forwarder) !void {
        self.flush_thread = std.Thread.spawn(.{}, Forwarder.flushWorker, .{self}) catch |err| {
            std.debug.print("Failed to spawn flush thread: {}\n", .{err});
            return;
        };
    }

    fn send(self: *Forwarder, entry: LogEntry) !void {
        self.batch_mutex.lock();
        defer self.batch_mutex.unlock();

        try self.batch.append(entry);
        
        if (self.batch.items.len >= BATCH_SIZE) {
            try self.flushBatch();
        }
    }

    fn flushBatch(self: *Forwarder) !void {
        if (self.batch.items.len == 0) return;

        // Create JSON array batch
        var json_buffer = std.ArrayList(u8).initCapacity(self.allocator, 4096) catch unreachable;
        defer json_buffer.deinit();

        try json_buffer.append(self.allocator, '[');
        for (self.batch.items, 0..) |entry, i| {
            try json_buffer.append(self.allocator, ',');
            try json.stringify(entry, .{}, json_buffer.writer());
        }
        try json_buffer.append(self.allocator, ']');

        const json_data = try json_buffer.toOwnedSlice();
        defer self.allocator.free(json_data);

        self.stats.addEntry(json_data.len);

        // Send batch
        var req = try self.client.open(.POST, try std.Uri.parse(self.output_url), .{
            .server_header_buffer = try self.allocator.alloc(u8, 8192),
        });
        defer req.deinit();
        defer self.allocator.free(req.server_header_buffer);

        req.transfer_encoding = .{ .content = json_data.len };
        try req.send();
        try req.writeAll(json_data);
        try req.finish();

        try req.wait();
        _ = try req.reader().readAllAlloc(self.allocator, 1024 * 1024);

        self.batch.clearAndFree();
    }

    fn flushWorker(self: *Forwarder) void {
        const interval_ns = FLUSH_INTERVAL_MS * std.time.ns_per_ms;
        var last_flush = std.time.nanoTimestamp();

        while (self.running.load(.monotonic)) {
            const now = std.time.nanoTimestamp();
            if (now - last_flush >= interval_ns) {
                self.batch_mutex.lock();
                self.flushBatch() catch |err| {
                    std.debug.print("Flush error: {s}\n", .{err});
                };
                self.batch_mutex.unlock();
                last_flush = now;
            }
            std.time.sleep(100 * std.time.ns_per_ms); // Check every 100ms
        }
    }
};

// ============================================================================
// File Processing
// ============================================================================

fn processFile(filename: []const u8, forwarder: *Forwarder, allocator: std.mem.Allocator) !usize {
    const file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();
    var line_count: usize = 0;

    var line_buf: [1024]u8 = undefined;
    while (try reader.readUntilDelimiterOrEof(&line_buf, '\n')) |line| {
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
// File Watcher
// ============================================================================

fn watchFile(config: Config, forwarder: *Forwarder, stats: *Stats, allocator: std.mem.Allocator) !void {
    const dir = std.fs.path.dirname(config.input_file) orelse ".";
    var watcher = try std.fs.Watcher.init(allocator, .{
        .file_data = true,
    });
    defer watcher.deinit();

    try watcher.addDir(dir, .{ . recurse = false });

    // Process existing file first
    _ = try processFile(config.input_file, forwarder, stats, allocator);

    std.debug.print("Watching {s} for changes...\n", .{config.input_file});

    while (true) {
        const event = watcher.next() catch |err| {
            std.debug.print("Watch error: {}\n", .{err});
            continue;
        };

        if (event.kind == .modify and std.mem.eql(u8, event.path, config.input_file)) {
            _ = try processFile(config.input_file, forwarder, allocator);
        }
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
    var forwarder = Forwarder.init(allocator, config.output_url, &stats);
    defer forwarder.deinit();
    
    try forwarder.start();

    // Start file watcher (blocking)
    try watchFile(config, &forwarder, &stats, allocator);
}

fn httpServer(stats: *Stats) !void {
    const address = try std.net.Address.parseIp("0.0.0.0", 8080);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();
    
    while (true) {
        const connection = server.accept() catch |err| {
            std.debug.print("Accept error: {}\n", .{err});
            continue;
        };
        
        // Handle request in simple way
        handleConnection(connection, stats) catch |err| {
            std.debug.print("Connection error: {}\n", .{err});
        };
    }
}

fn handleConnection(connection: std.net.Server.Connection, stats: *Stats) !void {
    defer connection.stream.close();
    
    var buffer: [4096]u8 = undefined;
    const request_data = connection.stream.read(&buffer) catch |err| {
        std.debug.print("Read error: {}\n", .{err});
        return;
    };
    
    const request = buffer[0..request_data];
    
    // Simple routing
    if (std.mem.indexOf(u8, request, "GET /health")) |_| {
        const response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{\"status\":\"ok\"}";
        _ = connection.stream.writeAll(response) catch {};
    } else if (std.mem.indexOf(u8, request, "GET /stats")) |_| {
        const stats_json = stats.getStats(std.heap.page_allocator) catch "{}";
        defer std.heap.page_allocator.free(stats_json);
        
        var response_buffer: [4096]u8 = undefined;
        const response = try std.fmt.bufPrint(
            &response_buffer,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n{s}",
            .{stats_json}
        );
        _ = connection.stream.writeAll(response) catch {};
    } else {
        const response = "HTTP/1.1 404 Not Found\r\n\r\nNot Found";
        _ = connection.stream.writeAll(response) catch {};
    }
}
