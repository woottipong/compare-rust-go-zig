const std = @import("std");
const c = @cImport({
    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavutil/avutil.h");
    @cInclude("libswscale/swscale.h");
});

const Subtitle = struct {
    start_time: f64,
    end_time: f64,
    text: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    _ = args.next(); // skip program name

    const input_file = args.next() orelse {
        std.debug.print("Usage: subtitle-burn-in-engine <input_video> <subtitle_file> <output_video>\n", .{});
        std.process.exit(1);
    };
    const subtitle_file = args.next() orelse {
        std.debug.print("Usage: subtitle-burn-in-engine <input_video> <subtitle_file> <output_video>\n", .{});
        std.process.exit(1);
    };
    const output_file = args.next() orelse {
        std.debug.print("Usage: subtitle-burn-in-engine <input_video> <subtitle_file> <output_video>\n", .{});
        std.process.exit(1);
    };

    const start = std.time.nanoTimestamp();
    try burnSubtitles(allocator, input_file, subtitle_file, output_file);
    const elapsed = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start)) / 1_000_000.0;
    std.debug.print("Burned in {d:.2}ms\n", .{elapsed});
}

fn burnSubtitles(allocator: std.mem.Allocator, input_file: []const u8, subtitle_file: []const u8, output_file: []const u8) !void {
    // Parse subtitle file
    const subtitles = try parseSRT(allocator, subtitle_file);
    defer allocator.free(subtitles);

    // Open input video
    var fmt_ctx: ?*c.AVFormatContext = null;
    const input_cstr = try allocator.dupeZ(u8, input_file);
    defer allocator.free(input_cstr);

    if (c.avformat_open_input(&fmt_ctx, input_cstr.ptr, null, null) < 0) {
        return error.CouldNotOpenInput;
    }
    defer c.avformat_close_input(&fmt_ctx);

    if (c.avformat_find_stream_info(fmt_ctx, null) < 0) {
        return error.CouldNotFindStreamInfo;
    }

    // Find video stream
    const video_stream_idx = findVideoStream(fmt_ctx) orelse return error.NoVideoStream;
    const stream = fmt_ctx.?.*.streams[@intCast(video_stream_idx)];

    // Setup decoder
    const codec = c.avcodec_find_decoder(stream.*.codecpar.*.codec_id) orelse {
        return error.UnsupportedCodec;
    };

    var codec_ctx = c.avcodec_alloc_context3(codec) orelse {
        return error.CouldNotAllocCodecContext;
    };
    defer c.avcodec_free_context(@constCast(&codec_ctx));

    if (c.avcodec_parameters_to_context(codec_ctx, stream.*.codecpar) < 0) {
        return error.CouldNotCopyCodecParams;
    }

    if (c.avcodec_open2(codec_ctx, codec, null) < 0) {
        return error.CouldNotOpenCodec;
    }

    // Setup output format
    var out_fmt_ctx: ?*c.AVFormatContext = null;
    const output_cstr = try allocator.dupeZ(u8, output_file);
    defer allocator.free(output_cstr);

    if (c.avformat_alloc_output_context2(&out_fmt_ctx, null, null, output_cstr.ptr) < 0) {
        return error.CouldNotCreateOutputContext;
    }
    defer c.avformat_free_context(out_fmt_ctx);

    // Find encoder
    const encoder = c.avcodec_find_encoder(c.AV_CODEC_ID_H264) orelse {
        return error.CouldNotFindEncoder;
    };

    var encoder_ctx = c.avcodec_alloc_context3(encoder) orelse {
        return error.CouldNotAllocEncoderContext;
    };
    defer c.avcodec_free_context(@constCast(&encoder_ctx));

    // Setup encoder parameters
    encoder_ctx.*.width = codec_ctx.*.width;
    encoder_ctx.*.height = codec_ctx.*.height;
    encoder_ctx.*.pix_fmt = c.AV_PIX_FMT_YUV420P;
    encoder_ctx.*.time_base = stream.*.time_base;
    encoder_ctx.*.framerate = stream.*.r_frame_rate;

    if (c.avcodec_open2(encoder_ctx, encoder, null) < 0) {
        return error.CouldNotOpenEncoder;
    }

    // Create output stream
    const out_stream = c.avformat_new_stream(out_fmt_ctx, encoder) orelse {
        return error.CouldNotCreateOutputStream;
    };

    if (c.avcodec_parameters_from_context(out_stream.*.codecpar, encoder_ctx) < 0) {
        return error.CouldNotCopyEncoderParams;
    }

    // Open output file
    if (c.avio_open(&out_fmt_ctx.?.*.pb, output_cstr.ptr, c.AVIO_FLAG_WRITE) < 0) {
        return error.CouldNotOpenOutputFile;
    }

    if (c.avformat_write_header(out_fmt_ctx, null) < 0) {
        return error.CouldNotWriteHeader;
    }

    // Setup scaling context
    const sws_ctx = c.sws_getContext(
        codec_ctx.*.width,
        codec_ctx.*.height,
        @intCast(codec_ctx.*.pix_fmt),
        codec_ctx.*.width,
        codec_ctx.*.height,
        c.AV_PIX_FMT_YUV420P,
        c.SWS_BILINEAR,
        null,
        null,
        null,
    ) orelse {
        return error.CouldNotCreateSwsContext;
    };
    defer c.sws_freeContext(sws_ctx);

    // Process frames
    const packet = c.av_packet_alloc() orelse {
        return error.CouldNotAllocPacket;
    };
    defer c.av_packet_free(@constCast(&packet));

    const frame = c.av_frame_alloc() orelse {
        return error.CouldNotAllocFrame;
    };
    defer c.av_frame_free(@constCast(&frame));

    const encoded_packet = c.av_packet_alloc() orelse {
        return error.CouldNotAllocEncodedPacket;
    };
    defer c.av_packet_free(@constCast(&encoded_packet));

    var current_sub_index: usize = 0;
    while (c.av_read_frame(fmt_ctx, packet) >= 0) {
        defer c.av_packet_unref(packet);

        if (packet.*.stream_index == video_stream_idx) {
            if (c.avcodec_send_packet(codec_ctx, packet) == 0) {
                while (c.avcodec_receive_frame(codec_ctx, frame) == 0) {
                    // Get frame time
                    var pts = frame.*.pts;
                    if (pts == c.AV_NOPTS_VALUE) {
                        pts = frame.*.best_effort_timestamp;
                    }
                    
                    const frame_time = @as(f64, @floatFromInt(pts)) * 
                        @as(f64, @floatFromInt(stream.*.time_base.num)) / 
                        @as(f64, @floatFromInt(stream.*.time_base.den));

                    // Find subtitle for current time
                    var current_sub: ?*const Subtitle = null;
                    while (current_sub_index < subtitles.len and subtitles[current_sub_index].end_time <= frame_time) {
                        current_sub_index += 1;
                    }
                    if (current_sub_index < subtitles.len and 
                        frame_time >= subtitles[current_sub_index].start_time and 
                        frame_time <= subtitles[current_sub_index].end_time) {
                        current_sub = &subtitles[current_sub_index];
                    }

                    // Add simple text overlay
                    if (current_sub) |sub| {
                        addTextOverlay(frame, sub.text, codec_ctx.*.width, codec_ctx.*.height);
                    }

                    // Encode frame
                    frame.*.pts = pts;
                    if (c.avcodec_send_frame(encoder_ctx, frame) == 0) {
                        while (c.avcodec_receive_packet(encoder_ctx, encoded_packet) == 0) {
                            encoded_packet.*.stream_index = out_stream.*.index;
                            encoded_packet.*.pts = c.av_rescale_q(
                                encoded_packet.*.pts,
                                codec_ctx.*.time_base,
                                out_stream.*.time_base,
                            );
                            encoded_packet.*.dts = c.av_rescale_q(
                                encoded_packet.*.dts,
                                codec_ctx.*.time_base,
                                out_stream.*.time_base,
                            );
                            _ = c.av_interleaved_write_frame(out_fmt_ctx, encoded_packet);
                        }
                    }
                }
            }
        }
    }

    // Flush encoder
    while (c.avcodec_send_frame(encoder_ctx, null) == 0) {
        while (c.avcodec_receive_packet(encoder_ctx, encoded_packet) == 0) {
            encoded_packet.*.stream_index = out_stream.*.index;
            _ = c.av_interleaved_write_frame(out_fmt_ctx, encoded_packet);
        }
    }

    // Write trailer
    _ = c.av_write_trailer(out_fmt_ctx);
}

fn findVideoStream(fmt_ctx: ?*c.AVFormatContext) ?i32 {
    if (fmt_ctx) |ctx| {
        var i: i32 = 0;
        while (i < ctx.*.nb_streams) : (i += 1) {
            const stream = ctx.*.streams[@intCast(i)];
            if (stream.*.codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
                return i;
            }
        }
    }
    return null;
}

fn parseSRT(allocator: std.mem.Allocator, filename: []const u8) ![]Subtitle {
    const content = try std.fs.cwd().readFileAlloc(allocator, filename, 1024 * 1024);
    defer allocator.free(content);

    var subtitles: std.ArrayList(Subtitle) = .empty;
    defer subtitles.deinit(allocator);

    var lines = std.mem.tokenizeScalar(u8, content, '\n');
    while (lines.next()) |line| {
        // Look for subtitle number
        _ = std.fmt.parseInt(u32, line, 10) catch continue;
        
        // Next line should be timestamp
        const time_line = lines.next() orelse break;
        if (std.mem.indexOf(u8, time_line, "-->") == null) continue;
        
        // Parse timestamp
        var time_parts = std.mem.tokenizeScalar(u8, time_line, ' ');
        const start_time_str = time_parts.next() orelse break;
        const end_time_str = time_parts.rest(); // Everything after " --> "
        
        const start_time = parseTime(start_time_str) catch continue;
        const end_time = parseTime(end_time_str) catch continue;
        
        // Read subtitle text until empty line
        var text_parts: std.ArrayList([]const u8) = .empty;
        defer text_parts.deinit(allocator);
        
        while (lines.next()) |text_line| {
            if (text_line.len == 0) break;
            try text_parts.append(allocator, text_line);
        }
        
        const text = try std.mem.join(allocator, " ", text_parts.items);
        
        try subtitles.append(allocator, Subtitle{
            .start_time = start_time,
            .end_time = end_time,
            .text = text,
        });
    }

    return subtitles.toOwnedSlice(allocator);
}

fn parseTime(time_str: []const u8) !f64 {
    const trimmed = std.mem.trim(u8, time_str, " \t\r\n");
    var parts = std.mem.tokenizeScalar(u8, trimmed, ':');
    const hours_str = parts.next() orelse return error.InvalidTimeFormat;
    const minutes_str = parts.next() orelse return error.InvalidTimeFormat;
    const sec_ms_str = parts.next() orelse return error.InvalidTimeFormat;

    const hours = try std.fmt.parseFloat(f64, hours_str);
    const minutes = try std.fmt.parseFloat(f64, minutes_str);

    // sec_ms_str is like "09,000"
    const comma_pos = std.mem.indexOf(u8, sec_ms_str, ",") orelse sec_ms_str.len;
    const sec_str = sec_ms_str[0..comma_pos];
    const ms_str = if (comma_pos < sec_ms_str.len) sec_ms_str[comma_pos + 1 ..] else "0";
    const seconds = try std.fmt.parseFloat(f64, sec_str);
    const millis = try std.fmt.parseFloat(f64, ms_str);

    return hours * 3600.0 + minutes * 60.0 + seconds + millis / 1000.0;
}

fn addTextOverlay(frame: *c.AVFrame, text: []const u8, width: c_int, height: c_int) void {
    _ = text; // Not used in simple implementation

    // Simple text overlay - draw a white rectangle at bottom
    const text_height: c_int = 40;
    const margin: c_int = 20;
    const start_y = height - text_height - margin;

    const y_data = frame.*.data[0];
    const y_stride = frame.*.linesize[0];

    var y: c_int = start_y;
    while (y < start_y + text_height) : (y += 1) {
        var x: c_int = margin;
        while (x < width - margin) : (x += 1) {
            const pixel_index = y * y_stride + x;
            if (pixel_index >= 0) {
                y_data[@intCast(pixel_index)] = 255; // White color for Y
            }
        }
    }
}
