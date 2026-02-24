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
        std.debug.print("Usage: hls-stream-segmenter <input_video> <output_dir> <segment_duration_sec>\n", .{});
        std.process.exit(1);
    };
    const output_dir = args.next() orelse {
        std.debug.print("Missing output directory\n", .{});
        std.process.exit(1);
    };
    const duration_str = args.next() orelse {
        std.debug.print("Missing segment duration\n", .{});
        std.process.exit(1);
    };

    const segment_duration = try std.fmt.parseFloat(f64, duration_str);

    var timer = try std.time.Timer.start();
    try segmentVideo(input_file, output_dir, segment_duration);
    std.debug.print("Segmented in {d}ms\n", .{timer.read() / std.time.ns_per_ms});
}

fn segmentVideo(input_file: []const u8, output_dir: []const u8, segment_duration: f64) !void {
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

    // Find video stream
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

    // Create output directory
    try std.fs.cwd().makePath(output_dir);

    // Initialize segmenter
    var segmenter = try HLSegmenter.init(fmt_ctx.?, video_stream_idx, output_dir, segment_duration, allocator);
    defer segmenter.deinit();
    try segmenter.segment();
}

const HLSegmenter = struct {
    input_fmt_ctx: *c.AVFormatContext,
    video_stream_idx: i32,
    output_dir: []const u8,
    segment_duration: f64,
    allocator: std.mem.Allocator,

    // Decoding
    codec_ctx: ?*c.AVCodecContext,
    packet: ?*c.AVPacket,
    frame: ?*c.AVFrame,

    // Segmenting
    current_segment: i32,
    segment_start: i64,
    time_base: f64,
    playlist: std.fs.File,

    fn init(
        fmt_ctx: *c.AVFormatContext,
        video_stream_idx: i32,
        output_dir: []const u8,
        segment_duration: f64,
        allocator: std.mem.Allocator,
    ) !HLSegmenter {
        const stream = fmt_ctx.streams[@intCast(video_stream_idx)];
        const codec = c.avcodec_find_decoder(stream.*.codecpar.*.codec_id) orelse {
            return error.UnsupportedCodec;
        };

        var codec_ctx = c.avcodec_alloc_context3(codec) orelse {
            return error.CouldNotAllocCodecContext;
        };

        if (c.avcodec_parameters_to_context(codec_ctx, stream.*.codecpar) < 0) {
            c.avcodec_free_context(@constCast(&codec_ctx));
            return error.CouldNotCopyCodecParams;
        }

        if (c.avcodec_open2(codec_ctx, codec, null) < 0) {
            c.avcodec_free_context(@constCast(&codec_ctx));
            return error.CouldNotOpenCodec;
        }

        const packet = c.av_packet_alloc() orelse {
            c.avcodec_free_context(@constCast(&codec_ctx));
            return error.CouldNotAllocPacket;
        };

        const frame = c.av_frame_alloc() orelse {
            c.av_packet_free(@constCast(&packet));
            c.avcodec_free_context(@constCast(&codec_ctx));
            return error.CouldNotAllocFrame;
        };

        const time_base = @as(f64, @floatFromInt(stream.*.time_base.num)) /
            @as(f64, @floatFromInt(stream.*.time_base.den));

        const playlist_path = try std.fmt.allocPrint(allocator, "{s}/playlist.m3u8", .{output_dir});
        defer allocator.free(playlist_path);
        const playlist = try std.fs.createFileAbsolute(playlist_path, .{});

        return HLSegmenter{
            .input_fmt_ctx = fmt_ctx,
            .video_stream_idx = video_stream_idx,
            .output_dir = output_dir,
            .segment_duration = segment_duration,
            .allocator = allocator,
            .codec_ctx = codec_ctx,
            .packet = packet,
            .frame = frame,
            .current_segment = 0,
            .segment_start = 0,
            .time_base = time_base,
            .playlist = playlist,
        };
    }

    fn deinit(self: *HLSegmenter) void {
        c.av_packet_free(@ptrCast(&self.packet));
        c.av_frame_free(@ptrCast(&self.frame));
        if (self.codec_ctx) |_| {
            c.avcodec_free_context(@ptrCast(&self.codec_ctx));
        }
        self.playlist.close();
    }

    fn segment(self: *HLSegmenter) !void {
        try self.playlist.writeAll("#EXTM3U\n");
        try self.playlist.writeAll("#EXT-X-VERSION:3\n");
        const target_dur = try std.fmt.allocPrint(self.allocator, "#EXT-X-TARGETDURATION:{d:.0}\n", .{self.segment_duration});
        defer self.allocator.free(target_dur);
        try self.playlist.writeAll(target_dur);
        try self.playlist.writeAll("#EXT-X-MEDIA-SEQUENCE:0\n");

        self.segment_start = 0;
        self.current_segment = 0;

        while (c.av_read_frame(self.input_fmt_ctx, self.packet) >= 0) {
            defer c.av_packet_unref(self.packet);

            if (self.packet.?.*.stream_index == self.video_stream_idx) {
                if (c.avcodec_send_packet(self.codec_ctx, self.packet) == 0) {
                    while (c.avcodec_receive_frame(self.codec_ctx, self.frame) == 0) {
                        var pts = self.frame.?.pts;
                        if (pts == c.AV_NOPTS_VALUE) {
                            pts = self.frame.?.best_effort_timestamp;
                        }

                        const frame_time = @as(f64, @floatFromInt(pts)) * self.time_base;
                        const seg_elapsed = frame_time - @as(f64, @floatFromInt(self.segment_start)) * self.time_base;

                        if (self.current_segment == 0 or seg_elapsed >= self.segment_duration) {
                            if (self.current_segment > 0) {
                                try self.finishSegment();
                            }
                            try self.startSegment();
                        }

                        try self.writeFrame();
                    }
                }
            }
        }

        if (self.current_segment > 0) {
            try self.finishSegment();
        }
        try self.playlist.writeAll("#EXT-X-ENDLIST\n");
    }

    fn startSegment(self: *HLSegmenter) !void {
        self.segment_start = self.frame.?.pts;
        self.current_segment += 1;
    }

    fn writeFrame(self: *HLSegmenter) !void {
        const segment_file = try std.fmt.allocPrint(
            self.allocator,
            "{s}/segment_{d:0>3}.ts",
            .{ self.output_dir, self.current_segment },
        );
        defer self.allocator.free(segment_file);

        var file = try std.fs.createFileAbsolute(segment_file, .{});
        defer file.close();

        const linesize: usize = @intCast(self.frame.?.linesize[0]);
        const height: usize = @intCast(self.codec_ctx.?.height);
        const data: [*]const u8 = @ptrCast(self.frame.?.data[0]);

        var y: usize = 0;
        while (y < height) : (y += 1) {
            try file.writeAll(data[y * linesize .. y * linesize + linesize]);
        }
    }

    fn finishSegment(self: *HLSegmenter) !void {
        const dur = (@as(f64, @floatFromInt(self.frame.?.pts)) -
            @as(f64, @floatFromInt(self.segment_start))) * self.time_base;
        const extinf = try std.fmt.allocPrint(self.allocator, "#EXTINF:{d:.3},\nsegment_{d:0>3}.ts\n", .{ dur, self.current_segment });
        defer self.allocator.free(extinf);
        try self.playlist.writeAll(extinf);
    }
};
