use anyhow::{anyhow, Result};
use ffmpeg_sys_next::*;
use std::env;
use std::ffi::CString;
use std::fs::File;
use std::io::Write;
use std::ptr;
use std::time::Instant;

fn main() -> Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!("Usage: {} <input_video> <output_dir> <segment_duration_sec>", args[0]);
        std::process::exit(1);
    }

    let input_file = &args[1];
    let output_dir = &args[2];
    let segment_duration: f64 = args[3].parse()?;

    let start = Instant::now();
    unsafe { segment_video(input_file, output_dir, segment_duration)? };
    println!("Segmented in {:?}", start.elapsed());

    Ok(())
}

unsafe fn segment_video(input_file: &str, output_dir: &str, segment_duration: f64) -> Result<()> {
    let c_input = CString::new(input_file)?;

    let mut fmt_ctx: *mut AVFormatContext = ptr::null_mut();
    if avformat_open_input(&mut fmt_ctx, c_input.as_ptr(), ptr::null(), ptr::null_mut()) < 0 {
        return Err(anyhow!("Could not open input file"));
    }

    let result = segment_video_inner(fmt_ctx, output_dir, segment_duration);
    avformat_close_input(&mut fmt_ctx);
    result
}

unsafe fn segment_video_inner(
    fmt_ctx: *mut AVFormatContext,
    output_dir: &str,
    segment_duration: f64,
) -> Result<()> {
    if avformat_find_stream_info(fmt_ctx, ptr::null_mut()) < 0 {
        return Err(anyhow!("Could not find stream info"));
    }

    // Find video stream
    let nb_streams = (*fmt_ctx).nb_streams as usize;
    let mut video_stream_idx: i32 = -1;
    for i in 0..nb_streams {
        let stream = *(*fmt_ctx).streams.add(i);
        if (*(*stream).codecpar).codec_type == AVMediaType::AVMEDIA_TYPE_VIDEO {
            video_stream_idx = i as i32;
            break;
        }
    }
    if video_stream_idx < 0 {
        return Err(anyhow!("No video stream found"));
    }

    // Create output directory
    std::fs::create_dir_all(output_dir)?;

    // Initialize segmenter
    let mut segmenter = HLSegmenter::new(fmt_ctx, video_stream_idx, output_dir, segment_duration)?;
    segmenter.segment()?;

    Ok(())
}

struct HLSegmenter {
    input_fmt_ctx: *mut AVFormatContext,
    video_stream_idx: i32,
    output_dir: String,
    segment_duration: f64,

    // Decoding
    codec_ctx: *mut AVCodecContext,
    packet: *mut AVPacket,
    frame: *mut AVFrame,

    // Segmenting
    current_segment: i32,
    segment_start: i64,
    time_base: f64,
    playlist: File,
    segment_file: Option<File>,
}

impl HLSegmenter {
    unsafe fn new(
        fmt_ctx: *mut AVFormatContext,
        video_stream_idx: i32,
        output_dir: &str,
        segment_duration: f64,
    ) -> Result<Self> {
        let stream = *(*fmt_ctx).streams.add(video_stream_idx as usize);
        let codec = avcodec_find_decoder((*(*stream).codecpar).codec_id);
        if codec.is_null() {
            return Err(anyhow!("Unsupported codec"));
        }

        let mut codec_ctx = avcodec_alloc_context3(codec);
        if codec_ctx.is_null() {
            return Err(anyhow!("Could not allocate codec context"));
        }

        if avcodec_parameters_to_context(codec_ctx, (*stream).codecpar) < 0 {
            avcodec_free_context(&mut codec_ctx);
            return Err(anyhow!("Could not copy codec params"));
        }

        if avcodec_open2(codec_ctx, codec, ptr::null_mut()) < 0 {
            avcodec_free_context(&mut codec_ctx);
            return Err(anyhow!("Could not open codec"));
        }

        let mut packet = av_packet_alloc();
        if packet.is_null() {
            avcodec_free_context(&mut codec_ctx);
            return Err(anyhow!("Could not allocate packet"));
        }

        let mut frame = av_frame_alloc();
        if frame.is_null() {
            av_packet_free(&mut packet);
            avcodec_free_context(&mut codec_ctx);
            return Err(anyhow!("Could not allocate frame"));
        }

        // Calculate time base
        let time_base = (*stream).time_base.num as f64 / (*stream).time_base.den as f64;

        // Create playlist file
        let playlist_path = format!("{}/playlist.m3u8", output_dir);
        let playlist = File::create(&playlist_path)?;

        Ok(HLSegmenter {
            input_fmt_ctx: fmt_ctx,
            video_stream_idx,
            output_dir: output_dir.to_string(),
            segment_duration,
            codec_ctx,
            packet,
            frame,
            current_segment: 0,
            segment_start: 0,
            time_base,
            playlist,
            segment_file: None,
        })
    }

    unsafe fn segment(&mut self) -> Result<()> {
        // Write playlist header
        self.playlist.write_all(b"#EXTM3U\n")?;
        self.playlist.write_all(b"#EXT-X-VERSION:3\n")?;
        self.playlist.write_fmt(format_args!("#EXT-X-TARGETDURATION:{:.0}\n", self.segment_duration))?;
        self.playlist.write_all(b"#EXT-X-MEDIA-SEQUENCE:0\n")?;

        self.segment_start = 0;
        self.current_segment = 0;

        while av_read_frame(self.input_fmt_ctx, self.packet) >= 0 {
            if (*self.packet).stream_index == self.video_stream_idx {
                if avcodec_send_packet(self.codec_ctx, self.packet) == 0 {
                    while avcodec_receive_frame(self.codec_ctx, self.frame) == 0 {
                        let pts = if (*self.frame).pts != AV_NOPTS_VALUE {
                            (*self.frame).pts
                        } else {
                            (*self.frame).best_effort_timestamp
                        };

                        let frame_time = pts as f64 * self.time_base;

                        // Check if we need to start a new segment
                        if self.current_segment == 0 || frame_time - (self.segment_start as f64 * self.time_base) >= self.segment_duration {
                            if self.current_segment > 0 {
                                self.finish_segment()?;
                            }
                            self.start_segment()?;
                        }

                        // Write frame to current segment
                        self.write_frame()?;
                    }
                }
            }
            av_packet_unref(self.packet);
        }

        // Finish last segment
        if self.current_segment > 0 {
            self.finish_segment()?;
        }

        // Write playlist end
        self.playlist.write_all(b"#EXT-X-ENDLIST\n")?;

        Ok(())
    }

    unsafe fn start_segment(&mut self) -> Result<()> {
        self.segment_start = (*self.frame).pts;
        self.current_segment += 1;
        let seg_path = format!("{}/segment_{:03}.ts", self.output_dir, self.current_segment);
        self.segment_file = Some(File::create(&seg_path)?);
        Ok(())
    }

    unsafe fn write_frame(&mut self) -> Result<()> {
        let file = self.segment_file.as_mut()
            .ok_or_else(|| anyhow!("No segment file open"))?;

        let width = (*self.codec_ctx).width as usize;
        let height = (*self.codec_ctx).height as usize;
        let uv_width = width / 2;
        let uv_height = height / 2;

        // Write Y plane
        let y_stride = (*self.frame).linesize[0] as usize;
        let y_data = (*self.frame).data[0];
        for row in 0..height {
            let slice = std::slice::from_raw_parts(y_data.add(row * y_stride), width);
            file.write_all(slice)?;
        }

        // Write U plane
        let u_stride = (*self.frame).linesize[1] as usize;
        let u_data = (*self.frame).data[1];
        for row in 0..uv_height {
            let slice = std::slice::from_raw_parts(u_data.add(row * u_stride), uv_width);
            file.write_all(slice)?;
        }

        // Write V plane
        let v_stride = (*self.frame).linesize[2] as usize;
        let v_data = (*self.frame).data[2];
        for row in 0..uv_height {
            let slice = std::slice::from_raw_parts(v_data.add(row * v_stride), uv_width);
            file.write_all(slice)?;
        }

        Ok(())
    }

    unsafe fn finish_segment(&mut self) -> Result<()> {
        self.segment_file = None;
        let segment_duration = ((*self.frame).pts - self.segment_start) as f64 * self.time_base;
        let segment_name = format!("segment_{:03}.ts", self.current_segment);
        self.playlist.write_fmt(format_args!("#EXTINF:{:.3},\n", segment_duration))?;
        self.playlist.write_fmt(format_args!("{}\n", segment_name))?;
        Ok(())
    }
}

impl Drop for HLSegmenter {
    fn drop(&mut self) {
        unsafe {
            if !self.packet.is_null() {
                av_packet_free(&mut self.packet);
            }
            if !self.frame.is_null() {
                av_frame_free(&mut self.frame);
            }
            if !self.codec_ctx.is_null() {
                avcodec_free_context(&mut self.codec_ctx);
            }
        }
    }
}
