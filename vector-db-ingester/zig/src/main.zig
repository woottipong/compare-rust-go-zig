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
        h ^= byte;
        h = h *% 1099511628211;
    }
    return h;
}

// Generate simple embedding
fn simpleEmbedding(text: []const u8) [EMBEDDING_DIM]f32 {
    const text_hash = hashString(text);
    var embedding: [EMBEDDING_DIM]f32 = undefined;
    
    for (0..EMBEDDING_DIM) |i| {
        embedding[i] = @as(f32, @floatFromInt(@as(u32, @truncate((text_hash >> @truncate(i % 32)) & 0xFF)))) / 255.0;
    }
    
    return embedding;
}

// Process content - count chunks and generate embeddings
fn processContent(_: std.mem.Allocator, content: []const u8) !struct { count: usize } {
    // Count words
    var word_count: usize = 0;
    var tokenizer = std.mem.tokenizeScalar(u8, content, ' ');
    while (tokenizer.next()) |_| {
        word_count += 1;
    }
    
    if (word_count == 0) {
        return .{ .count = 0 };
    }
    
    var chunk_count: usize = 0;
    
    // Process chunks
    var word_idx: usize = 0;
    while (word_idx < word_count) {
        // Find chunk end
        var chunk_word_end = word_idx + CHUNK_SIZE;
        if (chunk_word_end > word_count) {
            chunk_word_end = word_count;
        }
        
        // Generate embedding for this chunk
        _ = simpleEmbedding(content);
        
        chunk_count += 1;
        
        if (chunk_word_end >= word_count) break;
        word_idx += CHUNK_SIZE - CHUNK_OVERLAP;
    }
    
    return .{ .count = chunk_count };
}

pub fn main() !void {
    var input_file: []const u8 = "test.json";
    var args = std.process.args();
    _ = args.next();
    
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-input") or std.mem.eql(u8, arg, "--input")) {
            if (args.next()) |v| {
                input_file = v;
            }
        }
    }
    
    printConfig(input_file);
    
    var timer = try std.time.Timer.start();
    
    const file = try std.fs.cwd().openFile(input_file, .{});
    defer file.close();
    
    const stat = try file.stat();
    const data = try file.readToEndAlloc(std.heap.page_allocator, stat.size);
    defer std.heap.page_allocator.free(data);
    
    var doc_count: usize = 0;
    var chunk_count: usize = 0;
    
    const trimmed = std.mem.trim(u8, data, &[_]u8{ ' ', '\n', '\r', '\t' });
    if (std.mem.startsWith(u8, trimmed, "[")) {
        var search_idx: usize = 0;
        while (search_idx < data.len) {
            const obj_start = std.mem.indexOfScalarPos(u8, data, search_idx, '{') orelse break;
            const obj_end = std.mem.indexOfScalarPos(u8, data, obj_start, '}') orelse break;
            
            const obj_data = data[obj_start..obj_end+1];
            
            if (std.mem.indexOf(u8, obj_data, "\"content\"")) |content_pos| {
                const after_content = obj_data[content_pos+9..];
                const colon = std.mem.indexOfScalar(u8, after_content, ':') orelse {
                    search_idx = obj_end + 1;
                    continue;
                };
                const after_colon = after_content[colon+1..];
                const quote = std.mem.indexOfScalar(u8, after_colon, '"') orelse {
                    search_idx = obj_end + 1;
                    continue;
                };
                const after_quote = after_colon[quote+1..];
                const end_quote = std.mem.indexOfScalar(u8, after_quote, '"') orelse {
                    search_idx = obj_end + 1;
                    continue;
                };
                const content = after_quote[0..end_quote];
                
                doc_count += 1;
                const result = try processContent(std.heap.page_allocator, content);
                chunk_count += result.count;
            }
            
            search_idx = obj_end + 1;
        }
    } else if (std.mem.containsAtLeast(u8, data, 1, "\"content\"")) {
        if (std.mem.indexOf(u8, data, "\"content\"")) |content_pos| {
            const after_content = data[content_pos+9..];
            const colon = std.mem.indexOfScalar(u8, after_content, ':');
            const after_colon = if (colon) |c| after_content[c+1..] else data;
            const quote = std.mem.indexOfScalar(u8, after_colon, '"');
            const after_quote = if (quote) |q| after_colon[q+1..] else data;
            const end_quote = std.mem.indexOfScalar(u8, after_quote, '"');
            
            if (end_quote) |eq| {
                const content = after_quote[0..eq];
                doc_count = 1;
                const result = try processContent(std.heap.page_allocator, content);
                chunk_count = result.count;
                
                const elapsed_ns = timer.read();
                printStats(doc_count, chunk_count, elapsed_ns);
                return;
            }
        }
        
        doc_count = 1;
        const result = try processContent(std.heap.page_allocator, data);
        chunk_count = result.count;
    } else {
        doc_count = 1;
        const result = try processContent(std.heap.page_allocator, data);
        chunk_count = result.count;
    }
    
    const elapsed_ns = timer.read();
    printStats(doc_count, chunk_count, elapsed_ns);
}
