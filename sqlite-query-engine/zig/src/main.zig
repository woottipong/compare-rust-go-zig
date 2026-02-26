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

fn parseArgs(allocator: std.mem.Allocator) !struct { input: []const u8, repeats: usize } {
    var args = std.process.args();
    _ = args.next();

    const input = if (args.next()) |v| try allocator.dupe(u8, v) else try allocator.dupe(u8, "/data/metrics.db");
    const repeats = if (args.next()) |v| try std.fmt.parseInt(usize, v, 10) else 1000;
    if (repeats == 0) return error.InvalidRepeats;

    return .{ .input = input, .repeats = repeats };
}

/// Decode a SQLite varint from data[off..]. Returns .{ .value, .consumed }.
fn readVarint(data: []const u8, off: usize) struct { value: u64, consumed: usize } {
    var n: u64 = 0;
    for (0..9) |i| {
        const b = data[off + i];
        if (i == 8) {
            return .{ .value = (n << 8) | @as(u64, b), .consumed = 9 };
        }
        n = (n << 7) | @as(u64, b & 0x7f);
        if (b & 0x80 == 0) {
            return .{ .value = n, .consumed = i + 1 };
        }
    }
    return .{ .value = n, .consumed = 9 };
}

/// Byte size of a SQLite record column given its serial type.
fn colSize(t: u64) usize {
    return switch (t) {
        0 => 0,
        1 => 1,
        2 => 2,
        3 => 3,
        4 => 4,
        5 => 6,
        6 => 8,
        7 => 8,
        8, 9 => 0,
        else => blk: {
            if (t >= 12 and t % 2 == 0) break :blk @intCast((t - 12) / 2);
            if (t >= 13 and t % 2 == 1) break :blk @intCast((t - 13) / 2);
            break :blk 0;
        },
    };
}

/// Read a SQLite integer column value of the given serial type.
fn readIntCol(data: []const u8, off: usize, t: u64) i64 {
    return switch (t) {
        1 => @as(i64, @as(i8, @bitCast(data[off]))),
        2 => @as(i64, std.mem.readInt(i16, data[off..][0..2], .big)),
        3 => blk: {
            const v: u32 = @as(u32, data[off]) << 16 | @as(u32, data[off + 1]) << 8 | @as(u32, data[off + 2]);
            const sv: i32 = if (v & 0x800000 != 0) @bitCast(v | 0xff000000) else @bitCast(v);
            break :blk @as(i64, sv);
        },
        4 => @as(i64, std.mem.readInt(i32, data[off..][0..4], .big)),
        5 => blk: {
            const v: u64 = @as(u64, data[off]) << 40 | @as(u64, data[off + 1]) << 32 |
                @as(u64, data[off + 2]) << 24 | @as(u64, data[off + 3]) << 16 |
                @as(u64, data[off + 4]) << 8 | @as(u64, data[off + 5]);
            const sv: i64 = if (v & (1 << 47) != 0) @bitCast(v | 0xffff000000000000) else @bitCast(v);
            break :blk sv;
        },
        6 => std.mem.readInt(i64, data[off..][0..8], .big),
        8 => 0,
        9 => 1,
        else => 0,
    };
}

fn pageBase(page_num: u32, page_size: u32) usize {
    return (@as(usize, page_num) - 1) * @as(usize, page_size);
}

fn pageHeaderOff(page_num: u32, page_size: u32) usize {
    const base = pageBase(page_num, page_size);
    return if (page_num == 1) base + 100 else base;
}

/// DFS from page_num, appending all leaf page numbers to leaf_pages.
fn collectLeafPages(
    allocator: std.mem.Allocator,
    data: []const u8,
    page_size: u32,
    page_num: u32,
    leaf_pages: *std.ArrayList(u32),
) !void {
    const h_off = pageHeaderOff(page_num, page_size);
    const p_base = pageBase(page_num, page_size);
    const page_type = data[h_off];
    const num_cells = std.mem.readInt(u16, data[h_off + 3 ..][0..2], .big);

    switch (page_type) {
        0x0d => { // leaf table
            try leaf_pages.append(allocator, page_num);
        },
        0x05 => { // interior table — cell ptr array starts at h_off+12
            for (0..num_cells) |i| {
                const ptr_off = h_off + 12 + i * 2;
                const cell_off = p_base + @as(usize, std.mem.readInt(u16, data[ptr_off..][0..2], .big));
                const child = std.mem.readInt(u32, data[cell_off..][0..4], .big);
                try collectLeafPages(allocator, data, page_size, child, leaf_pages);
            }
            // rightmost child at h_off+8
            const right = std.mem.readInt(u32, data[h_off + 8 ..][0..4], .big);
            try collectLeafPages(allocator, data, page_size, right, leaf_pages);
        },
        else => {},
    }
}

/// Scan sqlite_schema (page 1) to find the root page of table_name.
fn findTableRoot(data: []const u8, table_name: []const u8) !u32 {
    const h_off: usize = 100; // B-tree header after 100-byte file header
    const num_cells = std.mem.readInt(u16, data[h_off + 3 ..][0..2], .big);

    for (0..num_cells) |i| {
        const ptr_off = h_off + 8 + i * 2;
        // page 1 cell offsets are from file start (page base = 0)
        var cell_off = @as(usize, std.mem.readInt(u16, data[ptr_off..][0..2], .big));

        // skip payload_size varint
        var vr = readVarint(data, cell_off);
        cell_off += vr.consumed;
        // skip rowid varint
        vr = readVarint(data, cell_off);
        cell_off += vr.consumed;

        // record header
        const h_start = cell_off;
        vr = readVarint(data, cell_off);
        const h_len = vr.value;
        cell_off += vr.consumed;
        const h_end = h_start + @as(usize, h_len);

        // sqlite_schema: type, name, tbl_name, rootpage, sql
        var types = [_]u64{0} ** 5;
        var tmp = cell_off;
        for (0..5) |j| {
            if (tmp >= h_end) break;
            vr = readVarint(data, tmp);
            types[j] = vr.value;
            tmp += vr.consumed;
        }

        var val_off = h_end;
        val_off += colSize(types[0]); // skip col[0]: type TEXT

        // col[1]: name TEXT
        const name_len = colSize(types[1]);
        const name = data[val_off .. val_off + name_len];
        val_off += name_len;

        if (std.mem.eql(u8, name, table_name)) {
            val_off += colSize(types[2]); // skip col[2]: tbl_name TEXT
            const root = readIntCol(data, val_off, types[3]);
            return @intCast(root);
        }
    }
    return error.TableNotFound;
}

/// Scan all leaf_pages repeats times, counting rows where cpu_pct > 80.0.
/// Returns rows_scanned + matching_rows.
fn query(data: []const u8, page_size: u32, leaf_pages: []const u32, repeats: usize) u64 {
    var rows_scanned: u64 = 0;
    var matching_rows: u64 = 0;

    for (0..repeats) |_| {
        for (leaf_pages) |page_num| {
            const h_off = pageHeaderOff(page_num, page_size);
            const p_base = pageBase(page_num, page_size);
            const num_cells = std.mem.readInt(u16, data[h_off + 3 ..][0..2], .big);

            for (0..num_cells) |i| {
                const ptr_off = h_off + 8 + i * 2;
                var cell_off = p_base + @as(usize, std.mem.readInt(u16, data[ptr_off..][0..2], .big));

                // skip payload_size varint
                var vr = readVarint(data, cell_off);
                cell_off += vr.consumed;
                // skip rowid varint
                vr = readVarint(data, cell_off);
                cell_off += vr.consumed;

                // record header
                const h_start = cell_off;
                vr = readVarint(data, cell_off);
                const h_len = vr.value;
                cell_off += vr.consumed;
                const h_end = h_start + @as(usize, h_len);

                // col[0] type (hostname TEXT)
                vr = readVarint(data, cell_off);
                const t0 = vr.value;

                // cpu_pct is immediately after hostname in the value area
                const cpu_off = h_end + colSize(t0);
                const cpu_bits = std.mem.readInt(u64, data[cpu_off..][0..8], .big);
                const cpu: f64 = @bitCast(cpu_bits);

                rows_scanned += 1;
                if (cpu > 80.0) {
                    matching_rows += 1;
                }
            }
        }
    }

    return rows_scanned + matching_rows;
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

    const data = std.fs.cwd().readFileAlloc(allocator, cfg.input, 1024 * 1024 * 64) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer allocator.free(data);

    if (data.len < 100) {
        std.debug.print("Error: file too small\n", .{});
        std.process.exit(1);
    }

    const raw_page_size = std.mem.readInt(u16, data[16..][0..2], .big);
    const page_size: u32 = if (raw_page_size == 1) 65536 else @as(u32, raw_page_size);

    const root_page = findTableRoot(data, "metrics") catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    var leaf_pages = std.ArrayList(u32){};
    defer leaf_pages.deinit(allocator);
    collectLeafPages(allocator, data, page_size, root_page, &leaf_pages) catch |err| {
        std.debug.print("Error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };

    if (leaf_pages.items.len == 0) {
        std.debug.print("Error: no leaf pages found\n", .{});
        std.process.exit(1);
    }

    var timer = try std.time.Timer.start();
    const total = query(data, page_size, leaf_pages.items, cfg.repeats);
    printStats(.{ .total_processed = total, .processing_ns = timer.read() });
}
