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
        eprintln!("Usage: {} <input_video> <timestamp_sec> <output_image.ppm>", args[0]);
        std::process::exit(1);
    }

    let input_file = &args[1];
    let timestamp: f64 = args[2].parse()?;
    let output_file = &args[3];

    let start = Instant::now();
    unsafe { extract_frame(input_file, timestamp, output_file)? };
    println!("Extracted in {:?}", start.elapsed());

    Ok(())
}

unsafe fn extract_frame(input_file: &str, target_seconds: f64, output_file: &str) -> Result<()> {
    let c_input = CString::new(input_file)?;

    let mut fmt_ctx: *mut AVFormatContext = ptr::null_mut();
    if avformat_open_input(&mut fmt_ctx, c_input.as_ptr(), ptr::null(), ptr::null_mut()) < 0 {
        return Err(anyhow!("Could not open input file"));
    }

    let result = extract_frame_inner(fmt_ctx, target_seconds, output_file);
    avformat_close_input(&mut fmt_ctx);
    result
}

unsafe fn extract_frame_inner(
    fmt_ctx: *mut AVFormatContext,
    target_seconds: f64,
    output_file: &str,
) -> Result<()> {
    if avformat_find_stream_info(fmt_ctx, ptr::null_mut()) < 0 {
        return Err(anyhow!("Could not find stream info"));
    }

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

    let target_pts = (target_seconds * AV_TIME_BASE as f64) as i64;
    if av_seek_frame(fmt_ctx, -1, target_pts, AVSEEK_FLAG_BACKWARD as i32) < 0 {
        avcodec_free_context(&mut codec_ctx);
        return Err(anyhow!("Could not seek"));
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

    let time_base = (*stream).time_base.num as f64 / (*stream).time_base.den as f64;
    let mut found = false;

    while av_read_frame(fmt_ctx, packet) >= 0 {
        if (*packet).stream_index == video_stream_idx {
            if avcodec_send_packet(codec_ctx, packet) == 0 {
                while avcodec_receive_frame(codec_ctx, frame) == 0 {
                    let pts = if (*frame).pts != AV_NOPTS_VALUE {
                        (*frame).pts
                    } else {
                        (*frame).best_effort_timestamp
                    };

                    if pts as f64 * time_base >= target_seconds {
                        let result = save_frame_ppm(frame, (*codec_ctx).width, (*codec_ctx).height, output_file);
                        av_packet_unref(packet);
                        av_frame_free(&mut frame);
                        av_packet_free(&mut packet);
                        avcodec_free_context(&mut codec_ctx);
                        return result;
                    }
                }
            }
        }
        av_packet_unref(packet);
        if found { break; }
    }

    av_frame_free(&mut frame);
    av_packet_free(&mut packet);
    avcodec_free_context(&mut codec_ctx);

    Err(anyhow!("Frame not found at timestamp {}", target_seconds))
}

unsafe fn save_frame_ppm(frame: *mut AVFrame, width: i32, height: i32, filename: &str) -> Result<()> {
    let src_fmt: AVPixelFormat = std::mem::transmute((*frame).format);
    let sws_ctx = sws_getContext(
        width, height, src_fmt,
        width, height, AVPixelFormat::AV_PIX_FMT_RGB24,
        2, // SWS_BILINEAR
        ptr::null_mut(), ptr::null_mut(), ptr::null(),
    );
    if sws_ctx.is_null() {
        return Err(anyhow!("Could not create sws context"));
    }
    let _sws_guard = scopeguard::guard(sws_ctx, |p| {
        sws_freeContext(p);
    });

    let rgb_frame = av_frame_alloc();
    if rgb_frame.is_null() {
        return Err(anyhow!("Could not allocate rgb frame"));
    }
    let _rgb_guard = scopeguard::guard(rgb_frame, |mut p| {
        av_frame_free(&mut p);
    });

    (*rgb_frame).format = AVPixelFormat::AV_PIX_FMT_RGB24 as i32;
    (*rgb_frame).width = width;
    (*rgb_frame).height = height;
    av_frame_get_buffer(rgb_frame, 0);

    sws_scale(
        sws_ctx,
        (*frame).data.as_ptr() as *const *const u8,
        (*frame).linesize.as_ptr(),
        0,
        height,
        (*rgb_frame).data.as_ptr() as *const *mut u8,
        (*rgb_frame).linesize.as_ptr(),
    );

    let mut file = File::create(filename)
        .map_err(|e| anyhow!("Could not create output file: {}", e))?;

    writeln!(file, "P6\n{} {}\n255", width, height)?;

    let linesize = (*rgb_frame).linesize[0] as usize;
    let data_ptr = (*rgb_frame).data[0];
    let row_bytes = width as usize * 3;

    for y in 0..height as usize {
        let row = std::slice::from_raw_parts(data_ptr.add(y * linesize), row_bytes);
        file.write_all(row)?;
    }

    Ok(())
}
