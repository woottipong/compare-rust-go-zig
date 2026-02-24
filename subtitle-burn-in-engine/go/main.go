package main

/*
#cgo pkg-config: libavformat libavcodec libavutil libswscale
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <stdlib.h>
#include <string.h>
*/
import "C"
import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
	"unsafe"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Printf("Usage: %s <input_video> <subtitle_file> <output_video>\n", os.Args[0])
		os.Exit(1)
	}

	inputFile := os.Args[1]
	subtitleFile := os.Args[2]
	outputFile := os.Args[3]

	start := time.Now()
	err := burnSubtitles(inputFile, subtitleFile, outputFile)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Burned in %v\n", time.Since(start))
}

func burnSubtitles(inputFile, subtitleFile, outputFile string) error {
	// Parse subtitle file first
	subtitles, err := parseSRT(subtitleFile)
	if err != nil {
		return fmt.Errorf("could not parse subtitle: %v", err)
	}

	// Open input video
	cInput := C.CString(inputFile)
	defer C.free(unsafe.Pointer(cInput))

	var fmtCtx *C.AVFormatContext
	if C.avformat_open_input(&fmtCtx, cInput, nil, nil) < 0 {
		return fmt.Errorf("could not open input file")
	}
	defer C.avformat_close_input(&fmtCtx)

	if C.avformat_find_stream_info(fmtCtx, nil) < 0 {
		return fmt.Errorf("could not find stream info")
	}

	// Find video stream
	videoStreamIdx := -1
	for i := 0; i < int(fmtCtx.nb_streams); i++ {
		stream := *(**C.AVStream)(unsafe.Pointer(uintptr(unsafe.Pointer(fmtCtx.streams)) + uintptr(i)*unsafe.Sizeof(*fmtCtx.streams)))
		if stream.codecpar.codec_type == C.AVMEDIA_TYPE_VIDEO {
			videoStreamIdx = i
			break
		}
	}
	if videoStreamIdx < 0 {
		return fmt.Errorf("no video stream found")
	}

	stream := *(**C.AVStream)(unsafe.Pointer(uintptr(unsafe.Pointer(fmtCtx.streams)) + uintptr(videoStreamIdx)*unsafe.Sizeof(*fmtCtx.streams)))

	// Setup decoder
	codec := C.avcodec_find_decoder(stream.codecpar.codec_id)
	if codec == nil {
		return fmt.Errorf("unsupported codec")
	}

	codecCtx := C.avcodec_alloc_context3(codec)
	if codecCtx == nil {
		return fmt.Errorf("could not allocate codec context")
	}
	defer C.avcodec_free_context(&codecCtx)

	if C.avcodec_parameters_to_context(codecCtx, stream.codecpar) < 0 {
		return fmt.Errorf("could not copy codec params")
	}

	if C.avcodec_open2(codecCtx, codec, nil) < 0 {
		return fmt.Errorf("could not open codec")
	}

	// Setup output format
	var outFmtCtx *C.AVFormatContext
	if C.avformat_alloc_output_context2(&outFmtCtx, nil, nil, C.CString(outputFile)) < 0 {
		return fmt.Errorf("could not create output context")
	}
	defer C.avformat_free_context(outFmtCtx)

	// Find encoder
	encoder := C.avcodec_find_encoder(C.AV_CODEC_ID_H264)
	if encoder == nil {
		return fmt.Errorf("could not find H264 encoder")
	}

	encoderCtx := C.avcodec_alloc_context3(encoder)
	if encoderCtx == nil {
		return fmt.Errorf("could not allocate encoder context")
	}
	defer C.avcodec_free_context(&encoderCtx)

	// Setup encoder parameters
	encoderCtx.width = codecCtx.width
	encoderCtx.height = codecCtx.height
	encoderCtx.pix_fmt = C.AV_PIX_FMT_YUV420P
	encoderCtx.time_base = stream.time_base
	encoderCtx.framerate = stream.r_frame_rate

	if C.avcodec_open2(encoderCtx, encoder, nil) < 0 {
		return fmt.Errorf("could not open encoder")
	}

	// Create output stream
	outStream := C.avformat_new_stream(outFmtCtx, encoder)
	if outStream == nil {
		return fmt.Errorf("could not create output stream")
	}

	if C.avcodec_parameters_from_context(outStream.codecpar, encoderCtx) < 0 {
		return fmt.Errorf("could not copy encoder params")
	}

	// Open output file
	if C.avio_open(&outFmtCtx.pb, C.CString(outputFile), C.AVIO_FLAG_WRITE) < 0 {
		return fmt.Errorf("could not open output file")
	}

	if C.avformat_write_header(outFmtCtx, nil) < 0 {
		return fmt.Errorf("could not write header")
	}

	// Setup scaling context
	swsCtx := C.sws_getContext(
		codecCtx.width, codecCtx.height, C.enum_AVPixelFormat(codecCtx.pix_fmt),
		codecCtx.width, codecCtx.height, C.AV_PIX_FMT_YUV420P,
		C.SWS_BILINEAR, nil, nil, nil,
	)
	if swsCtx == nil {
		return fmt.Errorf("could not create sws context")
	}
	defer C.sws_freeContext(swsCtx)

	// Process frames
	packet := C.av_packet_alloc()
	defer C.av_packet_free(&packet)

	frame := C.av_frame_alloc()
	defer C.av_frame_free(&frame)

	encodedPacket := C.av_packet_alloc()
	defer C.av_packet_free(&encodedPacket)

	currentSubIndex := 0
	for C.av_read_frame(fmtCtx, packet) >= 0 {
		if packet.stream_index == C.int(videoStreamIdx) {
			if C.avcodec_send_packet(codecCtx, packet) == 0 {
				for C.avcodec_receive_frame(codecCtx, frame) == 0 {
					// Get frame time
					pts := frame.pts
					if pts == C.AV_NOPTS_VALUE {
						pts = frame.best_effort_timestamp
					}
					frameTime := float64(pts) * float64(stream.time_base.num) / float64(stream.time_base.den)

					// Find subtitle for current time
					var currentSub *Subtitle
					for currentSubIndex < len(subtitles) && subtitles[currentSubIndex].endTime <= frameTime {
						currentSubIndex++
					}
					if currentSubIndex < len(subtitles) && frameTime >= subtitles[currentSubIndex].startTime && frameTime <= subtitles[currentSubIndex].endTime {
						currentSub = &subtitles[currentSubIndex]
					}

					// Add simple text overlay (without libass for now)
					if currentSub != nil {
						addTextOverlay(frame, currentSub.text, codecCtx.width, codecCtx.height)
					}

					// Encode frame
					frame.pts = pts
					if C.avcodec_send_frame(encoderCtx, frame) == 0 {
						for C.avcodec_receive_packet(encoderCtx, encodedPacket) == 0 {
							encodedPacket.stream_index = outStream.index
							encodedPacket.pts = C.av_rescale_q(encodedPacket.pts, codecCtx.time_base, outStream.time_base)
							encodedPacket.dts = C.av_rescale_q(encodedPacket.dts, codecCtx.time_base, outStream.time_base)
							C.av_interleaved_write_frame(outFmtCtx, encodedPacket)
						}
					}
				}
			}
		}
		C.av_packet_unref(packet)
	}

	// Flush encoder
	for {
		if C.avcodec_send_frame(encoderCtx, nil) != 0 {
			break
		}
		for C.avcodec_receive_packet(encoderCtx, encodedPacket) == 0 {
			encodedPacket.stream_index = outStream.index
			C.av_interleaved_write_frame(outFmtCtx, encodedPacket)
		}
	}

	// Write trailer
	C.av_write_trailer(outFmtCtx)

	return nil
}

type Subtitle struct {
	startTime float64
	endTime   float64
	text      string
}

func parseSRT(filename string) ([]Subtitle, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	lines := strings.Split(strings.ReplaceAll(string(data), "\r\n", "\n"), "\n")
	var subtitles []Subtitle
	i := 0
	for i < len(lines) {
		// Skip blank lines and index numbers
		line := strings.TrimSpace(lines[i])
		if line == "" {
			i++
			continue
		}
		// Try to parse as subtitle index (digits only)
		if _, err := strconv.Atoi(line); err != nil {
			i++
			continue
		}
		i++
		if i >= len(lines) {
			break
		}
		// Timestamp line
		timeLine := strings.TrimSpace(lines[i])
		if !strings.Contains(timeLine, "-->") {
			continue
		}
		parts := strings.SplitN(timeLine, "-->", 2)
		if len(parts) != 2 {
			i++
			continue
		}
		start, err := parseTime(strings.TrimSpace(parts[0]))
		if err != nil {
			i++
			continue
		}
		end, err := parseTime(strings.TrimSpace(parts[1]))
		if err != nil {
			i++
			continue
		}
		i++
		// Read text lines until blank
		var textLines []string
		for i < len(lines) && strings.TrimSpace(lines[i]) != "" {
			textLines = append(textLines, strings.TrimSpace(lines[i]))
			i++
		}
		subtitles = append(subtitles, Subtitle{
			startTime: start,
			endTime:   end,
			text:      strings.Join(textLines, " "),
		})
	}

	return subtitles, nil
}

func parseTime(s string) (float64, error) {
	// Format: HH:MM:SS,mmm
	parts := strings.SplitN(s, ":", 3)
	if len(parts) != 3 {
		return 0, fmt.Errorf("invalid time: %s", s)
	}
	h, err := strconv.Atoi(parts[0])
	if err != nil {
		return 0, err
	}
	m, err := strconv.Atoi(parts[1])
	if err != nil {
		return 0, err
	}
	secMs := strings.SplitN(parts[2], ",", 2)
	sec, err := strconv.Atoi(secMs[0])
	if err != nil {
		return 0, err
	}
	ms := 0
	if len(secMs) == 2 {
		ms, _ = strconv.Atoi(secMs[1])
	}
	return float64(h)*3600 + float64(m)*60 + float64(sec) + float64(ms)/1000.0, nil
}

func addTextOverlay(frame *C.AVFrame, text string, width, height C.int) {
	// Simple text overlay - draw text in the bottom center
	// This is a very basic implementation, real subtitle rendering would use libass
	yData := (*[1 << 30]byte)(unsafe.Pointer(frame.data[0]))
	yStride := int(frame.linesize[0])

	// Draw a simple white rectangle at bottom
	textHeight := 40
	margin := 20
	startY := int(height) - textHeight - margin

	for y := startY; y < startY+textHeight; y++ {
		for x := margin; x < int(width)-margin; x++ {
			pixelIndex := y*yStride + x
			if pixelIndex < len(yData) {
				yData[pixelIndex] = 255 // White color for Y
			}
		}
	}
}
