package main

/*
#cgo pkg-config: libavformat libavcodec libavutil libswscale
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/imgutils.h>
#include <libswscale/swscale.h>
#include <stdlib.h>
*/
import "C"
import (
	"fmt"
	"os"
	"time"
	"unsafe"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Printf("Usage: %s <input_video> <timestamp_sec> <output_image.ppm>\n", os.Args[0])
		os.Exit(1)
	}

	inputFile := os.Args[1]
	timestamp := os.Args[2]
	outputFile := os.Args[3]

	sec, err := parseTimestamp(timestamp)
	if err != nil {
		fmt.Printf("Invalid timestamp: %v\n", err)
		os.Exit(1)
	}

	start := time.Now()
	err = extractFrame(inputFile, sec, outputFile)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Extracted in %v\n", time.Since(start))
}

func parseTimestamp(ts string) (float64, error) {
	var f float64
	_, err := fmt.Sscanf(ts, "%f", &f)
	return f, err
}

func extractFrame(inputFile string, targetSeconds float64, outputFile string) error {
	cInputFile := C.CString(inputFile)
	defer C.free(unsafe.Pointer(cInputFile))

	var fmtCtx *C.AVFormatContext
	if C.avformat_open_input(&fmtCtx, cInputFile, nil, nil) < 0 {
		return fmt.Errorf("could not open input file")
	}
	defer C.avformat_close_input(&fmtCtx)

	if C.avformat_find_stream_info(fmtCtx, nil) < 0 {
		return fmt.Errorf("could not find stream info")
	}

	videoStreamIdx := -1
	for i := 0; i < int(fmtCtx.nb_streams); i++ {
		// Workaround for C array access in Go
		stream := *(**C.AVStream)(unsafe.Pointer(uintptr(unsafe.Pointer(fmtCtx.streams)) + uintptr(i)*unsafe.Sizeof(*fmtCtx.streams)))
		if stream.codecpar.codec_type == C.AVMEDIA_TYPE_VIDEO {
			videoStreamIdx = i
			break
		}
	}

	if videoStreamIdx == -1 {
		return fmt.Errorf("no video stream found")
	}

	stream := *(**C.AVStream)(unsafe.Pointer(uintptr(unsafe.Pointer(fmtCtx.streams)) + uintptr(videoStreamIdx)*unsafe.Sizeof(*fmtCtx.streams)))
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

	// Seek
	targetPts := C.int64_t(targetSeconds * float64(C.AV_TIME_BASE))
	if C.av_seek_frame(fmtCtx, -1, targetPts, C.AVSEEK_FLAG_BACKWARD) < 0 {
		return fmt.Errorf("could not seek")
	}

	packet := C.av_packet_alloc()
	defer C.av_packet_free(&packet)
	frame := C.av_frame_alloc()
	defer C.av_frame_free(&frame)

	for C.av_read_frame(fmtCtx, packet) >= 0 {
		if packet.stream_index == C.int(videoStreamIdx) {
			if C.avcodec_send_packet(codecCtx, packet) == 0 {
				for C.avcodec_receive_frame(codecCtx, frame) == 0 {
					// Frame decoded
					pts := frame.pts
					if pts == C.AV_NOPTS_VALUE {
						pts = frame.best_effort_timestamp
					}
					timeBase := float64(stream.time_base.num) / float64(stream.time_base.den)
					frameTime := float64(pts) * timeBase

					if frameTime >= targetSeconds {
						err := saveFramePPM(frame, codecCtx.width, codecCtx.height, outputFile)
						C.av_packet_unref(packet)
						return err
					}
				}
			}
		}
		C.av_packet_unref(packet)
	}

	return fmt.Errorf("frame not found")
}

func saveFramePPM(frame *C.AVFrame, width, height C.int, filename string) error {
	swsCtx := C.sws_getContext(
		width, height, C.enum_AVPixelFormat(frame.format),
		width, height, C.AV_PIX_FMT_RGB24,
		C.SWS_BILINEAR, nil, nil, nil,
	)
	if swsCtx == nil {
		return fmt.Errorf("could not init sws context")
	}
	defer C.sws_freeContext(swsCtx)

	rgbFrame := C.av_frame_alloc()
	defer C.av_frame_free(&rgbFrame)
	rgbFrame.format = C.AV_PIX_FMT_RGB24
	rgbFrame.width = width
	rgbFrame.height = height
	C.av_frame_get_buffer(rgbFrame, 0)

	C.sws_scale(swsCtx,
		&frame.data[0], &frame.linesize[0], 0, height,
		&rgbFrame.data[0], &rgbFrame.linesize[0],
	)

	cFilename := C.CString(filename)
	defer C.free(unsafe.Pointer(cFilename))
	f := C.fopen(cFilename, C.CString("wb"))
	if f == nil {
		return fmt.Errorf("could not open output file")
	}
	defer C.fclose(f)

	header := fmt.Sprintf("P6\n%d %d\n255\n", width, height)
	cHeader := C.CString(header)
	defer C.free(unsafe.Pointer(cHeader))
	C.fwrite(unsafe.Pointer(cHeader), 1, C.size_t(len(header)), f)

	// RGB24 has 3 bytes per pixel
	lineSize := int(rgbFrame.linesize[0])
	data := (*[1 << 30]byte)(unsafe.Pointer(rgbFrame.data[0]))

	for y := 0; y < int(height); y++ {
		start := y * lineSize
		C.fwrite(unsafe.Pointer(&data[start]), 1, C.size_t(int(width)*3), f)
	}

	return nil
}
