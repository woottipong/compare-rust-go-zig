use anyhow::Result;
use ffmpeg_sys_next::*;
use regex::Regex;
use scopeguard::guard;
use std::ffi::CString;
use std::ptr;

#[derive(Debug, Clone)]
struct Subtitle {
    start_time: f64,
    end_time: f64,
    text: String,
}

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() != 4 {
        eprintln!("Usage: {} <input_video> <subtitle_file> <output_video>", args[0]);
        std::process::exit(1);
    }

    let start = std::time::Instant::now();
    burn_subtitles(&args[1], &args[2], &args[3])?;
    println!("Burned in {:?}", start.elapsed());
    Ok(())
}

fn burn_subtitles(input_file: &str, subtitle_file: &str, output_file: &str) -> Result<()> {
    let subtitles = parse_srt(subtitle_file)?;

    unsafe {
        // ── Open input ────────────────────────────────────────────────────────
        let mut fmt_ctx: *mut AVFormatContext = ptr::null_mut();
        let input_cstr = CString::new(input_file)?;
        if avformat_open_input(&mut fmt_ctx, input_cstr.as_ptr(), ptr::null(), ptr::null_mut()) < 0 {
            return Err(anyhow::anyhow!("could not open input file"));
        }
        let _fmt_guard = guard(fmt_ctx, |mut ctx| { avformat_close_input(&mut ctx); });

        if avformat_find_stream_info(fmt_ctx, ptr::null_mut()) < 0 {
            return Err(anyhow::anyhow!("could not find stream info"));
        }

        // ── Find video stream ─────────────────────────────────────────────────
        let video_idx = find_video_stream(fmt_ctx)?;
        let stream = *(*fmt_ctx).streams.add(video_idx as usize);
        let time_base = (*stream).time_base;

        // ── Setup decoder ─────────────────────────────────────────────────────
        let codec = avcodec_find_decoder((*(*stream).codecpar).codec_id);
        if codec.is_null() { return Err(anyhow::anyhow!("unsupported codec")); }

        let mut codec_ctx = avcodec_alloc_context3(codec);
        if codec_ctx.is_null() { return Err(anyhow::anyhow!("could not alloc codec ctx")); }
        let _codec_guard = guard(codec_ctx, |mut ctx| { avcodec_free_context(&mut ctx); });

        if avcodec_parameters_to_context(codec_ctx, (*stream).codecpar) < 0 {
            return Err(anyhow::anyhow!("could not copy codec params"));
        }
        if avcodec_open2(codec_ctx, codec, ptr::null_mut()) < 0 {
            return Err(anyhow::anyhow!("could not open decoder"));
        }

        let width = (*codec_ctx).width;
        let height = (*codec_ctx).height;

        // ── Setup output ──────────────────────────────────────────────────────
        let mut out_ctx: *mut AVFormatContext = ptr::null_mut();
        let output_cstr = CString::new(output_file)?;
        if avformat_alloc_output_context2(&mut out_ctx, ptr::null_mut(), ptr::null(), output_cstr.as_ptr()) < 0 {
            return Err(anyhow::anyhow!("could not create output context"));
        }
        let _out_guard = guard(out_ctx, |ctx| { avformat_free_context(ctx); });

        let encoder = avcodec_find_encoder(AVCodecID::AV_CODEC_ID_H264);
        if encoder.is_null() { return Err(anyhow::anyhow!("could not find H264 encoder")); }

        let mut enc_ctx = avcodec_alloc_context3(encoder);
        if enc_ctx.is_null() { return Err(anyhow::anyhow!("could not alloc encoder ctx")); }
        let _enc_guard = guard(enc_ctx, |mut ctx| { avcodec_free_context(&mut ctx); });

        (*enc_ctx).width = width;
        (*enc_ctx).height = height;
        (*enc_ctx).pix_fmt = AVPixelFormat::AV_PIX_FMT_YUV420P;
        (*enc_ctx).time_base = time_base;
        (*enc_ctx).framerate = (*stream).r_frame_rate;

        if avcodec_open2(enc_ctx, encoder, ptr::null_mut()) < 0 {
            return Err(anyhow::anyhow!("could not open encoder"));
        }

        let out_stream = avformat_new_stream(out_ctx, encoder);
        if out_stream.is_null() { return Err(anyhow::anyhow!("could not create output stream")); }
        if avcodec_parameters_from_context((*out_stream).codecpar, enc_ctx) < 0 {
            return Err(anyhow::anyhow!("could not copy encoder params"));
        }

        if avio_open(&mut (*out_ctx).pb, output_cstr.as_ptr(), AVIO_FLAG_WRITE) < 0 {
            return Err(anyhow::anyhow!("could not open output file"));
        }
        if avformat_write_header(out_ctx, ptr::null_mut()) < 0 {
            return Err(anyhow::anyhow!("could not write header"));
        }

        // ── Alloc working buffers ─────────────────────────────────────────────
        let pkt = av_packet_alloc();
        if pkt.is_null() { return Err(anyhow::anyhow!("could not alloc packet")); }
        let _pkt_guard = guard(pkt, |mut p| { av_packet_free(&mut p); });

        let frame = av_frame_alloc();
        if frame.is_null() { return Err(anyhow::anyhow!("could not alloc frame")); }
        let _frame_guard = guard(frame, |mut f| { av_frame_free(&mut f); });

        let enc_pkt = av_packet_alloc();
        if enc_pkt.is_null() { return Err(anyhow::anyhow!("could not alloc enc packet")); }
        let _enc_pkt_guard = guard(enc_pkt, |mut p| { av_packet_free(&mut p); });

        // ── Decode → overlay → encode loop ───────────────────────────────────
        let mut sub_idx: usize = 0;
        while av_read_frame(fmt_ctx, pkt) >= 0 {
            if (*pkt).stream_index == video_idx {
                if avcodec_send_packet(codec_ctx, pkt) == 0 {
                    while avcodec_receive_frame(codec_ctx, frame) == 0 {
                        let pts = if (*frame).pts == AV_NOPTS_VALUE {
                            (*frame).best_effort_timestamp
                        } else {
                            (*frame).pts
                        };
                        let frame_time = pts as f64 * time_base.num as f64 / time_base.den as f64;

                        // Advance subtitle index past expired subs
                        while sub_idx < subtitles.len() && subtitles[sub_idx].end_time <= frame_time {
                            sub_idx += 1;
                        }

                        // Burn subtitle if current time is within sub window
                        if sub_idx < subtitles.len()
                            && frame_time >= subtitles[sub_idx].start_time
                            && frame_time <= subtitles[sub_idx].end_time
                        {
                            add_text_overlay(frame, width, height);
                        }

                        (*frame).pts = pts;
                        if avcodec_send_frame(enc_ctx, frame) == 0 {
                            while avcodec_receive_packet(enc_ctx, enc_pkt) == 0 {
                                (*enc_pkt).stream_index = (*out_stream).index;
                                (*enc_pkt).pts = av_rescale_q((*enc_pkt).pts, time_base, (*out_stream).time_base);
                                (*enc_pkt).dts = av_rescale_q((*enc_pkt).dts, time_base, (*out_stream).time_base);
                                av_interleaved_write_frame(out_ctx, enc_pkt);
                            }
                        }
                    }
                }
            }
            av_packet_unref(pkt);
        }

        // ── Flush encoder ─────────────────────────────────────────────────────
        while avcodec_send_frame(enc_ctx, ptr::null()) == 0 {
            while avcodec_receive_packet(enc_ctx, enc_pkt) == 0 {
                (*enc_pkt).stream_index = (*out_stream).index;
                av_interleaved_write_frame(out_ctx, enc_pkt);
            }
        }

        av_write_trailer(out_ctx);
    }

    Ok(())
}

fn find_video_stream(fmt_ctx: *mut AVFormatContext) -> Result<i32> {
    unsafe {
        for i in 0..(*fmt_ctx).nb_streams as usize {
            let stream = *(*fmt_ctx).streams.add(i);
            if (*(*stream).codecpar).codec_type == AVMediaType::AVMEDIA_TYPE_VIDEO {
                return Ok(i as i32);
            }
        }
    }
    Err(anyhow::anyhow!("no video stream found"))
}

fn parse_srt(filename: &str) -> Result<Vec<Subtitle>> {
    let content = std::fs::read_to_string(filename)?;
    // Ensure file ends with double newline so regex matches last block
    let content = format!("{}\n\n", content.trim());
    let re = Regex::new(r"(?m)^\d+\s*\n([\d:,]+)\s*-->\s*([\d:,]+)\s*\n([\s\S]+?)\n\n")?;

    let mut subtitles = Vec::new();
    for caps in re.captures_iter(&content) {
        let start = parse_time(caps[1].trim())?;
        let end = parse_time(caps[2].trim())?;
        let text = caps[3].trim().to_string();
        subtitles.push(Subtitle { start_time: start, end_time: end, text });
    }
    Ok(subtitles)
}

fn parse_time(s: &str) -> Result<f64> {
    // Format: HH:MM:SS,mmm
    let parts: Vec<&str> = s.splitn(3, ':').collect();
    if parts.len() != 3 {
        return Err(anyhow::anyhow!("invalid time: {}", s));
    }
    let h: f64 = parts[0].parse()?;
    let m: f64 = parts[1].parse()?;
    let sec_ms: Vec<&str> = parts[2].splitn(2, ',').collect();
    let sec: f64 = sec_ms[0].parse()?;
    let ms: f64 = if sec_ms.len() == 2 { sec_ms[1].parse::<f64>()? / 1000.0 } else { 0.0 };
    Ok(h * 3600.0 + m * 60.0 + sec + ms)
}

fn add_text_overlay(frame: *mut AVFrame, width: i32, height: i32) {
    // Draw a white horizontal bar near the bottom as subtitle placeholder
    unsafe {
        let bar_h = 36i32;
        let margin = 20i32;
        let y_start = height - bar_h - margin;
        let y_data = (*frame).data[0];
        let stride = (*frame).linesize[0];

        for row in y_start..y_start + bar_h {
            for col in margin..width - margin {
                *y_data.add((row * stride + col) as usize) = 235; // near-white luma
            }
        }
    }
}
