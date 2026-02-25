const std = @import("std");

const MaskingRule = struct {
    name: []const u8,
    pattern: []const u8,
    replacement: []const u8,
    match_fn: *const fn ([]const u8, usize) ?usize,
};

const Stats = struct {
    lines_processed: usize = 0,
    bytes_read: u64 = 0,
    bytes_written: u64 = 0,
    matches_found: usize = 0,
    start_time_ms: ?i64 = null,

    fn throughputMBps(self: Stats) f64 {
        if (self.start_time_ms == null) return 0.0;
        const elapsed_ms = std.time.milliTimestamp() - self.start_time_ms.?;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
        if (elapsed_s == 0.0) return 0.0;
        return @as(f64, @floatFromInt(self.bytes_read)) / 1024.0 / 1024.0 / elapsed_s;
    }

    fn linesPerSec(self: Stats) f64 {
        if (self.start_time_ms == null) return 0.0;
        const elapsed_ms = std.time.milliTimestamp() - self.start_time_ms.?;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;
        if (elapsed_s == 0.0) return 0.0;
        return @as(f64, @floatFromInt(self.lines_processed)) / elapsed_s;
    }
};

// Check if character is valid for email local part
fn isEmailChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '%' or c == '+' or c == '-';
}

// Check if character is valid for domain
fn isDomainChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '.' or c == '-';
}

// Match email pattern: local@domain.tld
fn matchEmail(line: []const u8, start: usize) ?usize {
    if (start >= line.len) return null;
    var i = start;

    // Local part
    var local_len: usize = 0;
    while (i < line.len and isEmailChar(line[i])) {
        i += 1;
        local_len += 1;
    }
    if (local_len == 0 or i >= line.len or line[i] != '@') return null;
    i += 1; // skip @

    // Domain part
    var domain_len: usize = 0;
    while (i < line.len and isDomainChar(line[i])) {
        i += 1;
        domain_len += 1;
    }
    if (domain_len == 0) return null;

    // Must have at least one dot and TLD (2+ chars after last dot)
    const domain_part = line[start + local_len + 1 .. i];
    const last_dot = std.mem.lastIndexOfScalar(u8, domain_part, '.');
    if (last_dot == null) return null;
    const tld_len = domain_part.len - last_dot.? - 1;
    if (tld_len < 2) return null;

    return i - start;
}

// Match phone pattern: (XXX) XXX-XXXX or XXX-XXX-XXXX or variations
fn matchPhone(line: []const u8, start: usize) ?usize {
    if (start >= line.len) return null;
    var i = start;

    // Optional +1 country code
    if (i + 2 < line.len and line[i] == '+' and line[i + 1] == '1') {
        i += 2;
        if (i < line.len and (line[i] == '-' or line[i] == '.')) {
            i += 1;
        }
    }

    // Optional opening parenthesis
    if (i < line.len and line[i] == '(') {
        i += 1;
    }

    // First 3 digits (area code)
    var digits: usize = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) {
        i += 1;
        digits += 1;
    }
    if (digits != 3) return null;

    // Optional separator and closing parenthesis
    if (i < line.len and (line[i] == ')' or line[i] == '-' or line[i] == '.')) {
        i += 1;
    }

    // Second 3 digits
    digits = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) {
        i += 1;
        digits += 1;
    }
    if (digits != 3) return null;

    // Separator
    if (i < line.len and (line[i] == '-' or line[i] == '.')) {
        i += 1;
    }

    // Last 4 digits
    digits = 0;
    while (i < line.len and std.ascii.isDigit(line[i])) {
        i += 1;
        digits += 1;
    }
    if (digits != 4) return null;

    // Check word boundary
    if (i < line.len and std.ascii.isAlphanumeric(line[i])) return null;

    return i - start;
}

// Match SSN pattern: XXX-XX-XXXX
fn matchSSN(line: []const u8, start: usize) ?usize {
    if (start + 11 > line.len) return null;

    // Check pattern: DDD-DD-DDDD
    var valid = true;
    var i: usize = 0;
    while (i < 3) : (i += 1) {
        if (!std.ascii.isDigit(line[start + i])) valid = false;
    }
    if (line[start + 3] != '-') valid = false;
    i = 4;
    while (i < 6) : (i += 1) {
        if (!std.ascii.isDigit(line[start + i])) valid = false;
    }
    if (line[start + 6] != '-') valid = false;
    i = 7;
    while (i < 11) : (i += 1) {
        if (!std.ascii.isDigit(line[start + i])) valid = false;
    }

    if (!valid) return null;

    // Check word boundaries
    if (start > 0 and std.ascii.isDigit(line[start - 1])) return null;
    if (start + 11 < line.len and std.ascii.isDigit(line[start + 11])) return null;

    return 11;
}

// Match IP address pattern: XXX.XXX.XXX.XXX
fn matchIP(line: []const u8, start: usize) ?usize {
    if (start >= line.len) return null;
    var i = start;
    var octets: usize = 0;

    while (octets < 4) {
        // Parse number (1-3 digits)
        var num_digits: usize = 0;
        var num: u16 = 0;
        while (i < line.len and std.ascii.isDigit(line[i]) and num_digits < 3) {
            num = num * 10 + (line[i] - '0');
            i += 1;
            num_digits += 1;
        }
        if (num_digits == 0 or num > 255) return null;

        octets += 1;

        // Dot separator (except after last octet)
        if (octets < 4) {
            if (i >= line.len or line[i] != '.') return null;
            i += 1;
        }
    }

    // Check word boundary
    if (i < line.len and std.ascii.isAlphanumeric(line[i])) return null;
    if (start > 0 and std.ascii.isDigit(line[start - 1])) return null;

    return i - start;
}

// Match API key pattern: api_key=XXXXX or token:XXXXX
fn matchAPIKey(line: []const u8, start: usize) ?usize {
    if (start >= line.len) return null;

    const prefixes = [_][]const u8{
        "api_key", "api-key", "apikey",
        "token", "secret",
    };

    for (prefixes) |prefix| {
        if (start + prefix.len > line.len) continue;

        const chunk = line[start .. start + prefix.len];
        var matches = true;
        for (chunk, 0..) |c, j| {
            if (std.ascii.toLower(c) != prefix[j]) {
                matches = false;
                break;
            }
        }

        if (!matches) continue;

        var i = start + prefix.len;

        // Skip optional spaces and separator
        while (i < line.len and line[i] == ' ') i += 1;
        if (i < line.len and (line[i] == ':' or line[i] == '=')) {
            i += 1;
        }
        while (i < line.len and line[i] == ' ') i += 1;

        // Skip optional quote
        var had_quote = false;
        if (i < line.len and (line[i] == '"' or line[i] == '\'')) {
            had_quote = true;
            i += 1;
        }

        // Key value (alphanumeric + underscore + hyphen, min 16 chars)
        var key_len: usize = 0;
        while (i < line.len and (std.ascii.isAlphanumeric(line[i]) or line[i] == '_' or line[i] == '-')) {
            i += 1;
            key_len += 1;
        }

        if (key_len < 16) continue;

        // Skip closing quote if we had opening
        if (had_quote and i < line.len and (line[i] == '"' or line[i] == '\'')) {
            i += 1;
        }

        return i - start;
    }

    return null;
}

// Match password in URL: password=XXXX or pwd=XXXX
fn matchPassword(line: []const u8, start: usize) ?usize {
    if (start >= line.len) return null;

    const prefixes = [_][]const u8{ "password", "pwd", "pass" };

    for (prefixes) |prefix| {
        if (start + prefix.len > line.len) continue;

        // Case-insensitive compare
        var matches = true;
        for (0..prefix.len) |j| {
            if (std.ascii.toLower(line[start + j]) != prefix[j]) {
                matches = false;
                break;
            }
        }

        if (!matches) continue;

        var i = start + prefix.len;

        // Must be followed by =
        if (i >= line.len or line[i] != '=') continue;
        i += 1;

        // Password value (until & or space)
        var pass_len: usize = 0;
        while (i < line.len and line[i] != '&' and line[i] != ' ' and line[i] != '\n' and line[i] != '\r') {
            i += 1;
            pass_len += 1;
        }

        if (pass_len == 0) continue;

        return i - start;
    }

    return null;
}

// Match credit card: simple Luhn-like check for common patterns
fn matchCreditCard(line: []const u8, start: usize) ?usize {
    if (start >= line.len) return null;

    // Try to match 13-16 consecutive digits
    var i = start;
    var digits: usize = 0;

    while (i < line.len and std.ascii.isDigit(line[i])) {
        i += 1;
        digits += 1;
    }

    // Credit cards are 13-16 digits
    if (digits < 13 or digits > 16) return null;

    // Check word boundary
    if (i < line.len and std.ascii.isAlphanumeric(line[i])) return null;
    if (start > 0 and std.ascii.isDigit(line[start - 1])) return null;

    return digits;
}

const rules = [_]MaskingRule{
    .{ .name = "email", .pattern = "", .replacement = "[EMAIL_MASKED]", .match_fn = matchEmail },
    .{ .name = "phone", .pattern = "", .replacement = "[PHONE_MASKED]", .match_fn = matchPhone },
    .{ .name = "ssn", .pattern = "", .replacement = "[SSN_MASKED]", .match_fn = matchSSN },
    .{ .name = "credit_card", .pattern = "", .replacement = "[CC_MASKED]", .match_fn = matchCreditCard },
    .{ .name = "ip_address", .pattern = "", .replacement = "[IP_MASKED]", .match_fn = matchIP },
    .{ .name = "api_key", .pattern = "", .replacement = "[API_KEY_MASKED]", .match_fn = matchAPIKey },
    .{ .name = "password", .pattern = "", .replacement = "[PASSWORD_MASKED]", .match_fn = matchPassword },
};

fn maskLine(allocator: std.mem.Allocator, line: []const u8, stats: *Stats) ![]u8 {
    var result = try allocator.dupe(u8, line);
    var offset: usize = 0;

    while (offset < result.len) {
        var longest_match: ?struct { len: usize, replacement: []const u8 } = null;

        // Find the longest match at this position
        for (rules) |rule| {
            if (rule.match_fn(result[offset..], 0)) |match_len| {
                if (longest_match == null or match_len > longest_match.?.len) {
                    longest_match = .{ .len = match_len, .replacement = rule.replacement };
                }
            }
        }

        if (longest_match) |match| {
            stats.matches_found += 1;

            // Replace the matched text with replacement
            const new_len = result.len - match.len + match.replacement.len;
            var new_result = try allocator.alloc(u8, new_len);

            // Copy prefix
            @memcpy(new_result[0..offset], result[0..offset]);

            // Copy replacement
            @memcpy(new_result[offset .. offset + match.replacement.len], match.replacement);

            // Copy suffix
            const suffix_start = offset + match.len;
            const new_suffix_start = offset + match.replacement.len;
            if (suffix_start < result.len) {
                @memcpy(new_result[new_suffix_start..new_result.len], result[suffix_start..result.len]);
            }

            allocator.free(result);
            result = new_result;
            offset += match.replacement.len;
        } else {
            offset += 1;
        }
    }

    return result;
}

fn processFile(allocator: std.mem.Allocator, input_file: ?[]const u8, output_file: ?[]const u8, stats: *Stats) !void {
    // Open input file (required)
    const in_path = input_file orelse {
        std.debug.print("Error: input file required\n", .{});
        return error.InputRequired;
    };
    
    // Open output file (required for benchmark)
    const out_path = output_file orelse {
        std.debug.print("Error: output file required\n", .{});
        return error.OutputRequired;
    };
    
    // Read entire file (for files up to a few hundred MB)
    const content = std.fs.cwd().readFileAlloc(allocator, in_path, 1024 * 1024 * 500) catch |err| {
        std.debug.print("Error reading file: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(content);
    
    stats.start_time_ms = std.time.milliTimestamp();
    
    // Process line by line
    var lines = std.mem.splitScalar(u8, content, '\n');
    var output_buf = try allocator.alloc(u8, content.len * 2);
    defer allocator.free(output_buf);
    var output_pos: usize = 0;
    
    while (lines.next()) |line| {
        // Skip empty last line
        if (lines.index == null and line.len == 0) break;
        
        stats.lines_processed += 1;
        stats.bytes_read += line.len + 1; // +1 for newline
        
        const masked = try maskLine(allocator, line, stats);
        defer allocator.free(masked);
        
        // Copy to output buffer
        @memcpy(output_buf[output_pos..output_pos + masked.len], masked);
        output_pos += masked.len;
        output_buf[output_pos] = '\n';
        output_pos += 1;
        stats.bytes_written += masked.len + 1;
    }
    
    // Write output
    try std.fs.cwd().writeFile(.{ .sub_path = out_path, .data = output_buf[0..output_pos] });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next(); // skip program name

    var input_file: ?[]const u8 = null;
    var output_file: ?[]const u8 = null;
    var show_stats = true;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--input")) {
            input_file = args.next();
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            output_file = args.next();
        } else if (std.mem.eql(u8, arg, "--no-stats")) {
            show_stats = false;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            std.debug.print("Usage: custom-log-masker [options]\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -i, --input <file>     Input log file (default: stdin)\n", .{});
            std.debug.print("  -o, --output <file>    Output file (default: stdout)\n", .{});
            std.debug.print("  --no-stats             Disable statistics output\n", .{});
            std.debug.print("  -h, --help             Show this help\n", .{});
            return;
        }
    }

    var stats = Stats{};

    try processFile(allocator, input_file, output_file, &stats);

    if (show_stats) {
        const elapsed_ms = if (stats.start_time_ms) |t| std.time.milliTimestamp() - t else 0;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ms)) / 1000.0;

        std.debug.print("\n--- Statistics ---\n", .{});
        std.debug.print("Lines processed: {d}\n", .{stats.lines_processed});
        std.debug.print("Bytes read: {d}\n", .{stats.bytes_read});
        std.debug.print("Matches found: {d}\n", .{stats.matches_found});
        std.debug.print("Processing time: {d:.3}s\n", .{elapsed_s});
        std.debug.print("Throughput: {d:.2} MB/s\n", .{stats.throughputMBps()});
        std.debug.print("Lines/sec: {d:.0}\n", .{stats.linesPerSec()});
    }
}
