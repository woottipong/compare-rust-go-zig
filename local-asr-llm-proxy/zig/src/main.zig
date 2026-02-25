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

    fn getStats(self: *Stats, alloc: Allocator) ![]u8 {
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

        // JSON with format specifiers - use {{ to escape braces
        return std.fmt.allocPrint(alloc,
            "{{\"total_processed\":{},\"processing_time_s\":{d:.3},\"average_latency_ms\":{d:.3},\"throughput\":{d:.2}}}",
            .{ total, elapsed_s, avg_latency_ms, throughput }
        );
    }
};

// ============================================================================
// Global State
// ============================================================================

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var g_allocator: Allocator = undefined;
var g_stats: Stats = undefined;

// ============================================================================
// Main
// ============================================================================

pub fn main() !void {
    defer _ = gpa.deinit();
    g_allocator = gpa.allocator();

    const args = try std.process.argsAlloc(g_allocator);
    defer std.process.argsFree(g_allocator, args);

    const listen_addr = if (args.len > 1) args[1] else "0.0.0.0:8080";
    _ = if (args.len > 2) args[2] else "http://localhost:3000"; // backend_url - unused in simulation mode

    const worker_count = std.Thread.getCpuCount() catch 4;

    printConfig(listen_addr, worker_count);

    g_stats = Stats.init();

    // Setup HTTP server
    var listener = zap.HttpListener.init(.{
        .port = parsePort(listen_addr),
        .on_request = onRequest,
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

fn printConfig(listen_addr: []const u8, workers: usize) void {
    std.debug.print("-- Configuration -------------------------\n", .{});
    std.debug.print("  Listen Addr : {s}\n", .{listen_addr});
    std.debug.print("  Workers     : {}\n", .{workers});
    std.debug.print("  Mode        : Simulation (mock backend delay)\n", .{});
    std.debug.print("\n", .{});
}

// ============================================================================
// HTTP Handler
// ============================================================================

fn onRequest(r: zap.Request) anyerror!void {
    const path = r.path orelse {
        r.setStatus(.not_found);
        r.sendBody("Not found") catch {};
        return;
    };

    if (std.mem.eql(u8, path, "/health")) {
        try handleHealth(r);
    } else if (std.mem.eql(u8, path, "/stats")) {
        try handleStats(r);
    } else if (std.mem.eql(u8, path, "/transcribe")) {
        try handleTranscribe(r);
    } else {
        r.setStatus(.not_found);
        r.sendBody("Not found") catch {};
    }
}

fn handleHealth(r: zap.Request) !void {
    r.setHeader("Content-Type", "application/json") catch {};
    try r.sendBody("{\"status\":\"ok\"}");
}

fn handleStats(r: zap.Request) !void {
    const stats_json = try g_stats.getStats(g_allocator);
    defer g_allocator.free(stats_json);

    r.setHeader("Content-Type", "application/json") catch {};
    try r.sendBody(stats_json);
}

fn handleTranscribe(r: zap.Request) !void {
    const method = r.method orelse "";
    if (!std.mem.eql(u8, method, "POST")) {
        r.setStatus(.method_not_allowed);
        try r.sendBody("Method not allowed");
        return;
    }

    const body = r.body orelse {
        r.setStatus(.bad_request);
        try r.sendBody("Missing body");
        return;
    };

    // Parse but ignore the actual content - just simulate backend delay
    var parsed = std.json.parseFromSlice(TranscriptionRequest, g_allocator, body, .{
        .allocate = .alloc_always,
    }) catch {
        r.setStatus(.bad_request);
        try r.sendBody("Invalid JSON");
        return;
    };
    defer parsed.deinit();

    // Generate job ID
    const job_id = try std.fmt.allocPrint(g_allocator, "{}", .{std.time.nanoTimestamp()});
    defer g_allocator.free(job_id);

    // Simulate backend processing (10-50ms delay like mock backend)
    const start = std.time.nanoTimestamp();
    const delay_ns = 10_000_000 + (@as(u64, @intCast(std.time.nanoTimestamp())) % 40_000_000);
    std.Thread.sleep(delay_ns);
    const latency_ns = std.time.nanoTimestamp() - start;
    
    g_stats.addRequest(@intCast(latency_ns));
    const latency_ms = @divTrunc(latency_ns, 1_000_000);

    // Create response
    const resp_json = try std.fmt.allocPrint(g_allocator,
        "{{\"job_id\":\"{s}\",\"status\":\"completed\",\"transcription\":\"mock transcription from ASR proxy\",\"processing_time_ms\":{}}}",
        .{ job_id, latency_ms }
    );

    r.setHeader("Content-Type", "application/json") catch {};
    try r.sendBody(resp_json);
    g_allocator.free(resp_json);
}
