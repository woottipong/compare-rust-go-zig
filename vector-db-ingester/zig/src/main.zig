const std = @import("std");

// Constants
const CHUNK_SIZE: usize = 512;
const CHUNK_OVERLAP: usize = 50;
const EMBEDDING_DIM: usize = 384;

fn printConfig(input_file: []const u8) void {
    std.debug.print("--- Configuration ---\n", .{});
    std.debug.print("Input file: {s}\n", .{input_file});
    std.debug.print("Batch size: 32\n", .{});
    std.debug.print("Embedding dimension: 384\n", .{});
}

fn printStats(total_docs: usize, total_chunks: usize, processing_ns: u64) void {
    const avg_latency = if (total_chunks > 0) @as(f64, @floatFromInt(processing_ns)) / @as(f64, @floatFromInt(total_chunks)) / 1e6 else 0.0;
    const throughput = if (processing_ns > 0) @as(f64, @floatFromInt(total_chunks)) / (@as(f64, @floatFromInt(processing_ns)) / 1e9) else 0.0;
    
    std.debug.print("--- Statistics ---\n", .{});
    std.debug.print("Total documents: {d}\n", .{total_docs});
    std.debug.print("Total chunks: {d}\n", .{total_chunks});
    std.debug.print("Processing time: {d:.3}s\n", .{@as(f64, @floatFromInt(processing_ns)) / 1e9});
    std.debug.print("Average latency: {d:.3}ms\n", .{avg_latency});
    std.debug.print("Throughput: {d:.2} chunks/sec\n", .{throughput});
}

// Simple FNV hash
fn hashString(s: []const u8) u64 {
    var h: u64 = 14695981039346656037;
    for (s) |byte| {
        h ^= @as(u64, byte);
        h *= 1099511628211;
    }
    return h;
}

// Simulate embedding generation
fn generateEmbedding(content: []const u8) [EMBEDDING_DIM]f32 {
    var embedding: [EMBEDDING_DIM]f32 = undefined;
    const hash = hashString(content);
    
    var i: usize = 0;
    while (i < EMBEDDING_DIM) : (i += 1) {
        // Generate pseudo-random values based on hash
        var seed = hash ^ @as(u64, @intCast(i));
        seed ^= seed >> 33;
        seed *= 0xff51afd7ed558ccd;
        seed ^= seed >> 33;
        seed *= 0xc4ceb9fe1a85ec53;
        seed ^= seed >> 33;
        
        // Convert to float between -1 and 1
        embedding[i] = (@as(f32, @floatFromInt(seed & 0x7fffffff)) / @as(f32, @floatFromInt(std.math.maxInt(u32)))) * 2.0 - 1.0;
    }
    
    return embedding;
}

// Process content into chunks
fn processContent(allocator: std.mem.Allocator, content: []const u8) !struct { count: usize } {
    var chunk_count: usize = 0;
    
    // Simple word-based chunking
    var words = std.mem.tokenizeScalar(u8, content, ' ');
    var word_idx: usize = 0;
    var chunk_words = std.ArrayList([]const u8).initCapacity(allocator, 1024) catch {
        std.debug.print("Error: Failed to initialize ArrayList\n", .{});
        return error.OutOfMemory;
    };
    defer chunk_words.deinit(allocator);
    
    while (words.next()) |word| {
        try chunk_words.append(allocator, word);
        word_idx += 1;
        
        // Create chunk when we reach CHUNK_SIZE
        if (chunk_words.items.len >= CHUNK_SIZE) {
            // Simulate embedding generation
            const chunk_content = std.mem.join(allocator, " ", chunk_words.items) catch {
                return error.OutOfMemory;
            };
            defer allocator.free(chunk_content);
            _ = generateEmbedding(chunk_content);
            
            chunk_count += 1;
            
            // Keep overlap for next chunk
            if (CHUNK_OVERLAP > 0 and chunk_words.items.len > CHUNK_OVERLAP) {
                const overlap_start = chunk_words.items.len - CHUNK_OVERLAP;
                for (0..CHUNK_OVERLAP) |i| {
                    chunk_words.items[i] = chunk_words.items[overlap_start + i];
                }
                chunk_words.shrinkRetainingCapacity(CHUNK_OVERLAP);
            } else {
                chunk_words.clearRetainingCapacity();
            }
        }
    }
    
    // Process remaining words
    if (chunk_words.items.len > 0) {
        const chunk_content = std.mem.join(allocator, " ", chunk_words.items) catch {
            return error.OutOfMemory;
        };
        defer allocator.free(chunk_content);
        _ = generateEmbedding(chunk_content);
        chunk_count += 1;
    }
    
    return .{ .count = chunk_count };
}

pub fn main() !void {
    var input_file: []const u8 = "test.json";
    var args = std.process.args();
    _ = args.next(); // skip program name
    
    // First positional argument is input file
    if (args.next()) |arg| {
        input_file = arg;
    }
    
    printConfig(input_file);
    
    var timer = try std.time.Timer.start();
    
    const file = try std.fs.openFileAbsolute(input_file, .{});
    defer file.close();
    
    const stat = try file.stat();
    const data = try file.readToEndAlloc(std.heap.page_allocator, stat.size);
    defer std.heap.page_allocator.free(data);
    
    var doc_count: usize = 0;
    var chunk_count: usize = 0;
    
    const trimmed = std.mem.trim(u8, data, &[_]u8{ ' ', '\n', '\r', '\t' });
    
    // Check for new format: {"metadata": {...}, "documents": [...]}
    var search_start: usize = 0;
    if (std.mem.startsWith(u8, trimmed, "{")) {
        // Look for "documents" array
        if (std.mem.indexOf(u8, data, "\"documents\"")) |docs_pos| {
            const after_docs = data[docs_pos+11..];
            const bracket = std.mem.indexOfScalar(u8, after_docs, '[') orelse {
                std.debug.print("Error: Invalid JSON format - missing documents array\n", .{});
                return;
            };
            const documents_start = docs_pos + 11 + bracket + 1;
            search_start = documents_start;
        }
    } else if (std.mem.startsWith(u8, trimmed, "[")) {
        search_start = 0;
    } else {
        std.debug.print("Error: Invalid JSON format\n", .{});
        return;
    }
    
    while (search_start < data.len) {
        const obj_start = std.mem.indexOfScalarPos(u8, data, search_start, '{') orelse break;
        const obj_end = std.mem.indexOfScalarPos(u8, data, obj_start, '}') orelse break;
        
        const obj_data = data[obj_start..obj_end+1];
        
        if (std.mem.indexOf(u8, obj_data, "\"content\"")) |content_pos| {
            const after_content = obj_data[content_pos+9..];
            const colon = std.mem.indexOfScalar(u8, after_content, ':') orelse {
                search_start = obj_end + 1;
                continue;
            };
            const after_colon = after_content[colon+1..];
            const quote = std.mem.indexOfScalar(u8, after_colon, '"') orelse {
                search_start = obj_end + 1;
                continue;
            };
            const after_quote = after_colon[quote+1..];
            const end_quote = std.mem.indexOfScalar(u8, after_quote, '"') orelse {
                search_start = obj_end + 1;
                continue;
            };
            const content = after_quote[0..end_quote];
            
            doc_count += 1;
            const result = try processContent(std.heap.page_allocator, content);
            chunk_count += result.count;
        }
        
        search_start = obj_end + 1;
    }
    
    const elapsed_ns = timer.read();
    printStats(doc_count, chunk_count, elapsed_ns);
}
