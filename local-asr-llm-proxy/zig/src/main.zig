const std = @import("std");
const zap = @import("zap");

const Allocator = std.mem.Allocator;

// ============================================================================
// Data Structures
// ============================================================================

const TranscriptionRequest = struct {
    audio_data: []const u8,
    format: []const u8,
    language: []const u8,
};

const TranscriptionResponse = struct {
    job_id: []const u8,
    status: []const u8,
    transcription: []const u8,
    processing_time_ms: u64,
};

const BackendResponse = struct {
    transcription: []const u8,
    confidence: f64,
    processing_time_ms: u64,
};

const Stats = struct {
    total_processed: std.atomic.Value(usize),
    total_latency_ns: std.atomic.Value(usize),
    start_time: i128,

    fn init() Stats {
        return .{
            .total_processed = std.atomic.Value(usize).init(0),
            .total_latency_ns = std.atomic.Value(usize).init(0),
            .start_time = std.time.nanoTimestamp(),
        };
    }

    fn addRequest(self: *Stats, latency_ns: usize) void {
        _ = self.total_processed.fetchAdd(1, .monotonic);
        _ = self.total_latency_ns.fetchAdd(latency_ns, .monotonic);
    }

    fn getStats(self: *Stats, allocator: Allocator) ![]u8 {
        const total = self.total_processed.load(.monotonic);
        const latency_ns = self.total_latency_ns.load(.monotonic);
        const elapsed_ns = std.time.nanoTimestamp() - self.start_time;
        const elapsed_s = @as(f64, @floatFromInt(@as(u64, @intCast(elapsed_ns)))) / 1_000_000_000.0;

        const avg_latency_ms: f64 = if (total > 0)
            @as(f64, @floatFromInt(latency_ns / total)) / 1_000_000.0
        else
            0.0;

        const throughput: f64 = if (elapsed_s > 0)
            @as(f64, @floatFromInt(total)) / elapsed_s
        else
            0.0;

        return std.fmt.allocPrint(allocator,
            \\{{"total_processed":{},"processing_time_s":{d:.3},"average_latency_ms":{d:.3},"throughput":{d:.2}}}
        , .{ total, elapsed_s, avg_latency_ms, throughput });
    }
};

const Job = struct {
    id: []const u8,
    audio_data: []const u8,
    format: []const u8,
    language: []const u8,
    response: *Response,
};

const Response = struct {
    mutex: std.Thread.Mutex,
    cond: std.Thread.Condition,
    done: bool,
    data: ?[]const u8,

    fn init() Response {
        return .{
            .mutex = .{},
            .cond = .{},
            .done = false,
            .data = null,
        };
    }

    fn set(self: *Response, data: []const u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.data = data;
        self.done = true;
        self.cond.signal();
    }

    fn wait(self: *Response, timeout_ms: u64) ?[]const u8 {
        self.mutex.lock();
        defer self.mutex.unlock();

        const deadline = std.time.nanoTimestamp() + @as(i128, @intCast(timeout_ms * 1_000_000));
        while (!self.done) {
            const now = std.time.nanoTimestamp();
            if (now >= deadline) return null;
            self.cond.timedWait(&self.mutex, @intCast(timeout_ms * 1_000_000)) catch {};
        }
        return self.data;
    }
};

// ============================================================================
// Global State
// ============================================================================

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var allocator: Allocator = undefined;
var stats: Stats = undefined;
var job_queue: std.atomic.Value(?*JobNode) = undefined;
var backend_url: []const u8 = undefined;

const JobNode = struct {
    job: Job,
    next: ?*JobNode,
};

var job_pool: std.atomic.Value(?*JobNode) = undefined;

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    defer _ = gpa.deinit();
    allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const listen_addr = if (args.len > 1) args[1] else "0.0.0.0:8080";
    backend_url = if (args.len > 2) args[2] else "http://localhost:3000";

    const worker_count = std.Thread.getCpuCount() catch 4;
    const queue_size: usize = 1000;

    printConfig(listen_addr, backend_url, worker_count, queue_size);

    stats = Stats.init();
    job_queue = std.atomic.Value(?*JobNode).init(null);
    job_pool = std.atomic.Value(?*JobNode).init(null);

    // Start workers
    var workers = try allocator.alloc(std.Thread, worker_count);
    defer allocator.free(workers);

    for (workers) |*worker| {
        worker.* = try std.Thread.spawn(.{}, workerFn, .{});
    }

    // Setup HTTP server
    var listener = zap.HttpListener.init(.{
        .port = parsePort(listen_addr),
        .on_request = handleRequest,
        .public_folder = null,
        .log = false,
    });
    try listener.listen();

    std.debug.print("Server listening on {s}\n", .{listen_addr});
    zap.start(.{
        .threads = 2,
        .workers = 2,
    });
}

fn parsePort(addr: []const u8) u16 {
    var it = std.mem.splitScalar(u8, addr, ':');
    _ = it.next();
    const port_str = it.next() orelse return 8080;
    return std.fmt.parseInt(u16, port_str, 10) catch 8080;
}

fn printConfig(listen_addr: []const u8, url: []const u8, workers: usize, queue: usize) void {
    std.debug.print("-- Configuration -------------------------\n", .{});
    std.debug.print("  Listen Addr : {s}\n", .{listen_addr});
    std.debug.print("  Backend URL : {s}\n", .{url});
    std.debug.print("  Workers     : {}\n", .{workers});
    std.debug.print("  Queue Size  : {}\n", .{queue});
    std.debug.print("\n", .{});
}

// ============================================================================
// Worker
// ============================================================================

fn workerFn() void {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    while (true) {
        const job_node = popJob() orelse {
            std.time.sleep(1_000_000); // 1ms
            continue;
        };
        const job = &job_node.job;

        const start = std.time.nanoTimestamp();

        // Forward to backend
        const result = forwardToBackend(&client, job) catch |err| blk: {
            break :blk std.fmt.allocPrint(allocator, "{{\"error\":\"{s}\"}}", .{@errorName(err)}) catch "{}";
        };

        const latency_ns = std.time.nanoTimestamp() - start;
        stats.addRequest(@intCast(latency_ns));

        job.response.set(result);
    }
}

fn pushJob(node: *JobNode) void {
    var current = job_queue.load(.monotonic);
    while (true) {
        node.next = current;
        if (job_queue.cmpxchgWeak(current, node, .release, .monotonic)) |new| {
            current = new;
        } else {
            break;
        }
    }
}

fn popJob() ?*JobNode {
    var current = job_queue.load(.acquire);
    while (current) |node| {
        if (job_queue.cmpxchgWeak(current, node.next, .release, .monotonic)) |new| {
            current = new;
        } else {
            return node;
        }
    }
    return null;
}

fn forwardToBackend(client: *std.http.Client, job: *Job) ![]const u8 {
    const req_body = try std.fmt.allocPrint(allocator,
        \\{{"audio_data":"{s}","format":"{s}","language":"{s}"}}
    , .{ job.audio_data, job.format, job.language });
    defer allocator.free(req_body);

    const url = try std.fmt.allocPrint(allocator, "{s}/transcribe", .{backend_url});
    defer allocator.free(url);

    var req = try client.open(.POST, try std.Uri.parse(url), .{
        .server_header_buffer = try allocator.alloc(u8, 8192),
    });
    defer req.deinit();
    defer allocator.free(req.server_header_buffer);

    req.transfer_encoding = .{ .content = req_body.len };
    try req.send();
    try req.writeAll(req_body);
    try req.finish();

    try req.wait();

    const body = try req.reader().readAllAlloc(allocator, 1024 * 1024);

    var parsed = try std.json.parseFromSlice(BackendResponse, allocator, body, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    const resp = TranscriptionResponse{
        .job_id = job.id,
        .status = "completed",
        .transcription = parsed.value.transcription,
        .processing_time_ms = parsed.value.processing_time_ms,
    };

    return std.json.stringifyAlloc(allocator, resp, .{});
}

// ============================================================================
// HTTP Handler
// ============================================================================

fn handleRequest(r: zap.Request) void {
    const path = r.path orelse {
        r.setStatus(.not_found);
        r.sendBody("Not found") catch {};
        return;
    };

    if (std.mem.eql(u8, path, "/health")) {
        handleHealth(r);
    } else if (std.mem.eql(u8, path, "/stats")) {
        handleStats(r);
    } else if (std.mem.eql(u8, path, "/transcribe")) {
        handleTranscribe(r);
    } else {
        r.setStatus(.not_found);
        r.sendBody("Not found") catch {};
    }
}

fn handleHealth(r: zap.Request) void {
    r.setHeader("Content-Type", "application/json") catch {};
    r.sendBody("{\"status\":\"ok\"}") catch {};
}

fn handleStats(r: zap.Request) void {
    const stats_json = stats.getStats(allocator) catch {
        r.setStatus(.internal_server_error);
        r.sendBody("Error") catch {};
        return;
    };
    defer allocator.free(stats_json);

    r.setHeader("Content-Type", "application/json") catch {};
    r.sendBody(stats_json) catch {};
}

fn handleTranscribe(r: zap.Request) void {
    if (r.method != .POST) {
        r.setStatus(.method_not_allowed);
        r.sendBody("Method not allowed") catch {};
        return;
    }

    const body = r.body orelse {
        r.setStatus(.bad_request);
        r.sendBody("Missing body") catch {};
        return;
    };

    var parsed = std.json.parseFromSlice(TranscriptionRequest, allocator, body, .{
        .allocate = .alloc_always,
    }) catch {
        r.setStatus(.bad_request);
        r.sendBody("Invalid JSON") catch {};
        return;
    };
    defer parsed.deinit();

    const req = parsed.value;

    // Generate job ID
    const job_id = std.fmt.allocPrint(allocator, "{}", .{std.time.nanoTimestamp()}) catch return;
    defer allocator.free(job_id);

    // Create response holder
    var response = Response.init();

    // Create job
    const job_node = allocator.create(JobNode) catch {
        r.setStatus(.internal_server_error);
        r.sendBody("Out of memory") catch {};
        return;
    };
    job_node.* = .{
        .job = .{
            .id = allocator.dupe(u8, job_id) catch return,
            .audio_data = allocator.dupe(u8, req.audio_data) catch return,
            .format = allocator.dupe(u8, req.format) catch return,
            .language = allocator.dupe(u8, req.language) catch return,
            .response = &response,
        },
        .next = null,
    };

    // Push job to queue
    pushJob(job_node);

    // Wait for response
    if (response.wait(5000)) |result| {
        defer allocator.free(result);
        r.setHeader("Content-Type", "application/json") catch {};
        r.sendBody(result) catch {};
    } else {
        r.setStatus(.gateway_timeout);
        r.sendBody("Request timeout") catch {};
    }

    // Cleanup
    allocator.free(job_node.job.id);
    allocator.free(job_node.job.audio_data);
    allocator.free(job_node.job.format);
    allocator.free(job_node.job.language);
    allocator.destroy(job_node);
}
