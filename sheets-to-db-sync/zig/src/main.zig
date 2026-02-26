const std = @import("std");

const Record = struct {
    id: []const u8,
    name: []const u8,
    email: []const u8,
    updated_at: []const u8,
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

fn parseArgs(allocator: std.mem.Allocator) !struct { sheet_path: []const u8, db_path: []const u8, repeats: usize } {
    var args = std.process.args();
    _ = args.next();
    const sheet_path = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/sheet.csv");
    errdefer allocator.free(sheet_path);
    const db_path = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/db.csv");
    errdefer allocator.free(db_path);
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 1000;
    if (repeats == 0) return error.InvalidRepeats;
    return .{ .sheet_path = sheet_path, .db_path = db_path, .repeats = repeats };
}

fn parseCsv(allocator: std.mem.Allocator, path: []const u8) !std.ArrayList(Record) {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(data);

    var rows = std.ArrayList(Record){};
    errdefer rows.deinit(allocator);

    var it = std.mem.splitScalar(u8, data, '\n');
    var line_no: usize = 0;
    while (it.next()) |raw_line| {
        line_no += 1;
        const line = std.mem.trim(u8, raw_line, " \r\t");
        if (line.len == 0) continue;
        if (line_no == 1 and std.mem.startsWith(u8, line, "id,")) continue;

        var parts_it = std.mem.splitScalar(u8, line, ',');
        const id = parts_it.next() orelse return error.InvalidCsv;
        const name = parts_it.next() orelse return error.InvalidCsv;
        const email = parts_it.next() orelse return error.InvalidCsv;
        const updated_at = parts_it.next() orelse return error.InvalidCsv;
        if (parts_it.next() != null) return error.InvalidCsv;

        try rows.append(allocator, .{
            .id = try allocator.dupe(u8, id),
            .name = try allocator.dupe(u8, name),
            .email = try allocator.dupe(u8, email),
            .updated_at = try allocator.dupe(u8, updated_at),
        });
    }

    return rows;
}

fn freeRows(allocator: std.mem.Allocator, rows: *std.ArrayList(Record)) void {
    for (rows.items) |r| {
        allocator.free(r.id);
        allocator.free(r.name);
        allocator.free(r.email);
        allocator.free(r.updated_at);
    }
    rows.deinit(allocator);
}

fn syncRows(sheet_rows: []const Record, db_map: *std.StringHashMap(Record)) !void {
    for (sheet_rows) |r| {
        try db_map.put(r.id, r);
    }
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
    defer allocator.free(cfg.sheet_path);
    defer allocator.free(cfg.db_path);

    var sheet_rows = parseCsv(allocator, cfg.sheet_path) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer freeRows(allocator, &sheet_rows);

    var db_rows = parseCsv(allocator, cfg.db_path) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer freeRows(allocator, &db_rows);

    var db_map = std.StringHashMap(Record).init(allocator);
    defer db_map.deinit();
    for (db_rows.items) |r| {
        try db_map.put(r.id, r);
    }

    var timer = try std.time.Timer.start();
    for (0..cfg.repeats) |_| {
        try syncRows(sheet_rows.items, &db_map);
    }

    printStats(.{ .total_processed = @intCast(sheet_rows.items.len * cfg.repeats), .processing_ns = timer.read() });
}
