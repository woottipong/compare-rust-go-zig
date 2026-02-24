const std = @import("std");
const c = @cImport({
    @cInclude("libavformat/avformat.h");
    @cInclude("libavcodec/avcodec.h");
    @cInclude("libavutil/avutil.h");
    @cInclude("libavutil/imgutils.h");
    @cInclude("libswscale/swscale.h");
});

pub fn main() !void {
    var args = std.process.args();
    _ = args.next(); // skip program name

    const input_file = args.next() orelse {
        std.debug.print("Usage: video-frame-extractor <input_video> <timestamp_sec> <output_image.ppm>\n", .{});
        std.process.exit(1);
    };
    const timestamp_str = args.next() orelse {
        std.debug.print("Missing timestamp\n", .{});
        std.process.exit(1);
    };
    const output_file = args.next() orelse {
        std.debug.print("Missing output file\n", .{});
        std.process.exit(1);
    };

    const target_seconds = try std.fmt.parseFloat(f64, timestamp_str);

    var timer = try std.time.Timer.start();
    try extractFrame(input_file, target_seconds, output_file);
    const elapsed = timer.read();
    std.debug.print("Extracted in {d}ms\n", .{elapsed / std.time.ns_per_ms});
}

fn extractFrame(input_file: []const u8, target_seconds: f64, output_file: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const c_input = try allocator.dupeZ(u8, input_file);
    defer allocator.free(c_input);

    var fmt_ctx: ?*c.AVFormatContext = null;
    if (c.avformat_open_input(&fmt_ctx, c_input.ptr, null, null) < 0) {
        return error.CouldNotOpenInput;
    }
    defer c.avformat_close_input(&fmt_ctx);

    if (c.avformat_find_stream_info(fmt_ctx, null) < 0) {
        return error.CouldNotFindStreamInfo;
    }

    var video_stream_idx: i32 = -1;
    var i: usize = 0;
    while (i < fmt_ctx.?.nb_streams) : (i += 1) {
        const stream = fmt_ctx.?.streams[i];
        if (stream.*.codecpar.*.codec_type == c.AVMEDIA_TYPE_VIDEO) {
            video_stream_idx = @intCast(i);
            break;
        }
    }

    if (video_stream_idx < 0) {
        return error.NoVideoStream;
    }

    const stream = fmt_ctx.?.streams[@intCast(video_stream_idx)];
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

    // Seek to target timestamp
    const target_pts: i64 = @intFromFloat(target_seconds * @as(f64, c.AV_TIME_BASE));
    if (c.av_seek_frame(fmt_ctx, -1, target_pts, c.AVSEEK_FLAG_BACKWARD) < 0) {
        return error.CouldNotSeek;
    }

    const packet = c.av_packet_alloc() orelse return error.CouldNotAllocPacket;
    defer c.av_packet_free(@constCast(&packet));

    var frame: ?*c.AVFrame = c.av_frame_alloc();
    defer c.av_frame_free(@constCast(&frame));

    while (c.av_read_frame(fmt_ctx, packet) >= 0) {
        defer c.av_packet_unref(packet);

        if (packet.*.stream_index == video_stream_idx) {
            if (c.avcodec_send_packet(codec_ctx, packet) == 0) {
                while (c.avcodec_receive_frame(codec_ctx, frame) == 0) {
                    var pts = frame.?.pts;
                    if (pts == c.AV_NOPTS_VALUE) {
                        pts = frame.?.best_effort_timestamp;
                    }

                    const time_base = @as(f64, @floatFromInt(stream.*.time_base.num)) /
                        @as(f64, @floatFromInt(stream.*.time_base.den));
                    const frame_time = @as(f64, @floatFromInt(pts)) * time_base;

                    if (frame_time >= target_seconds) {
                        try saveFramePPM(frame.?, codec_ctx.*.width, codec_ctx.*.height, output_file);
                        return;
                    }
                }
            }
        }
    }

    return error.FrameNotFound;
}

fn saveFramePPM(frame: *c.AVFrame, width: i32, height: i32, filename: []const u8) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const sws_ctx = c.sws_getContext(
        width, height, @intCast(frame.*.format),
        width, height, c.AV_PIX_FMT_RGB24,
        c.SWS_BILINEAR, null, null, null,
    ) orelse return error.CouldNotCreateSwsContext;
    defer c.sws_freeContext(sws_ctx);

    const rgb_frame = c.av_frame_alloc() orelse return error.CouldNotAllocFrame;
    defer c.av_frame_free(@constCast(&rgb_frame));

    rgb_frame.*.format = c.AV_PIX_FMT_RGB24;
    rgb_frame.*.width = width;
    rgb_frame.*.height = height;
    _ = c.av_frame_get_buffer(rgb_frame, 0);

    _ = c.sws_scale(
        sws_ctx,
        &frame.*.data[0], &frame.*.linesize[0], 0, height,
        &rgb_frame.*.data[0], &rgb_frame.*.linesize[0],
    );

    const c_filename = try allocator.dupeZ(u8, filename);
    defer allocator.free(c_filename);

    const f = c.fopen(c_filename.ptr, "wb") orelse return error.CouldNotOpenOutput;
    defer _ = c.fclose(f);

    // Write PPM header
    const header = try std.fmt.allocPrint(allocator, "P6\n{d} {d}\n255\n", .{ width, height });
    defer allocator.free(header);
    _ = c.fwrite(header.ptr, 1, header.len, f);

    // Write pixel data row by row
    const linesize = rgb_frame.*.linesize[0];
    const data = rgb_frame.*.data[0];
    var y: i32 = 0;
    while (y < height) : (y += 1) {
        const row_start: usize = @intCast(y * linesize);
        _ = c.fwrite(@ptrCast(&data[row_start]), 1, @intCast(width * 3), f);
    }
}
