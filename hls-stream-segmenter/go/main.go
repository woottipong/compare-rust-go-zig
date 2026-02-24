package main

/*
#cgo pkg-config: libavformat libavcodec libavutil libswscale
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libswscale/swscale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
*/
import "C"
import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"
	"unsafe"
)

func main() {
	if len(os.Args) != 4 {
		fmt.Fprintf(os.Stderr, "Usage: %s <input_video> <output_dir> <segment_duration_sec>\n", os.Args[0])
		os.Exit(1)
	}

	inputFile := os.Args[1]
	outputDir := os.Args[2]
	segmentDuration, err := strconv.ParseFloat(os.Args[3], 64)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Invalid segment duration: %s\n", os.Args[3])
		os.Exit(1)
	}

	start := time.Now()
	err = segmentVideo(inputFile, outputDir, segmentDuration)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Segmented in %v\n", time.Since(start))
}

func segmentVideo(inputFile, outputDir string, segmentDuration float64) error {
	cInput := C.CString(inputFile)
	defer C.free(unsafe.Pointer(cInput))

	var fmtCtx *C.AVFormatContext
	if C.avformat_open_input(&fmtCtx, cInput, nil, nil) != 0 {
		return fmt.Errorf("could not open input file")
	}
	defer C.avformat_close_input(&fmtCtx)

	if C.avformat_find_stream_info(fmtCtx, nil) < 0 {
		return fmt.Errorf("could not find stream info")
	}

	// Find video stream
	var videoStreamIdx int32 = -1
	for i := 0; i < int(fmtCtx.nb_streams); i++ {
		stream := *(**C.AVStream)(unsafe.Pointer(uintptr(unsafe.Pointer(fmtCtx.streams)) + uintptr(i)*unsafe.Sizeof(*fmtCtx.streams)))
		if stream.codecpar.codec_type == C.AVMEDIA_TYPE_VIDEO {
			videoStreamIdx = int32(i)
			break
		}
	}
	if videoStreamIdx < 0 {
		return fmt.Errorf("no video stream found")
	}

	// Create output directory
	if err := os.MkdirAll(outputDir, 0755); err != nil {
		return fmt.Errorf("could not create output directory: %v", err)
	}

	// Initialize segmenter
	segmenter := &HLSegmenter{
		inputFmtCtx:     fmtCtx,
		videoStreamIdx:  videoStreamIdx,
		outputDir:       outputDir,
		segmentDuration: segmentDuration,
	}

	if err := segmenter.initialize(); err != nil {
		return err
	}
	defer segmenter.cleanup()

	return segmenter.segment()
}

type HLSegmenter struct {
	inputFmtCtx     *C.AVFormatContext
	videoStreamIdx  int32
	outputDir       string
	segmentDuration float64

	// Decoding
	codecCtx *C.AVCodecContext
	packet   *C.AVPacket
	frame    *C.AVFrame

	// Scaling
	swsCtx   *C.SwsContext
	rgbFrame *C.AVFrame

	// Segmenting
	currentSegment int
	segmentPts     int64
	segmentStart   int64
	timeBase       float64
}

func (h *HLSegmenter) initialize() error {
	// Setup decoder
	stream := *(**C.AVStream)(unsafe.Pointer(uintptr(unsafe.Pointer(h.inputFmtCtx.streams)) + uintptr(h.videoStreamIdx)*unsafe.Sizeof(*h.inputFmtCtx.streams)))
	codec := C.avcodec_find_decoder(stream.codecpar.codec_id)
	if codec == nil {
		return fmt.Errorf("unsupported codec")
	}

	h.codecCtx = C.avcodec_alloc_context3(codec)
	if h.codecCtx == nil {
		return fmt.Errorf("could not allocate codec context")
	}

	if C.avcodec_parameters_to_context(h.codecCtx, stream.codecpar) < 0 {
		return fmt.Errorf("could not copy codec params")
	}

	if C.avcodec_open2(h.codecCtx, codec, nil) < 0 {
		return fmt.Errorf("could not open codec")
	}

	// Allocate packet and frame
	h.packet = C.av_packet_alloc()
	h.frame = C.av_frame_alloc()

	// Setup scaling context
	width := h.codecCtx.width
	height := h.codecCtx.height
	h.swsCtx = C.sws_getContext(
		width, height, h.codecCtx.pix_fmt,
		width, height, C.AV_PIX_FMT_YUV420P,
		C.SWS_BILINEAR, nil, nil, nil,
	)
	if h.swsCtx == nil {
		return fmt.Errorf("could not create sws context")
	}

	h.rgbFrame = C.av_frame_alloc()
	h.rgbFrame.format = C.int(C.AV_PIX_FMT_YUV420P)
	h.rgbFrame.width = width
	h.rgbFrame.height = height
	C.av_frame_get_buffer(h.rgbFrame, 0)

	// Calculate time base
	h.timeBase = float64(stream.time_base.num) / float64(stream.time_base.den)

	return nil
}

func (h *HLSegmenter) cleanup() {
	if h.swsCtx != nil {
		C.sws_freeContext(h.swsCtx)
	}
	if h.rgbFrame != nil {
		C.av_frame_free(&h.rgbFrame)
	}
	if h.frame != nil {
		C.av_frame_free(&h.frame)
	}
	if h.packet != nil {
		C.av_packet_free(&h.packet)
	}
	if h.codecCtx != nil {
		C.avcodec_free_context(&h.codecCtx)
	}
}

func (h *HLSegmenter) segment() error {
	// Create playlist file
	playlistPath := filepath.Join(h.outputDir, "playlist.m3u8")
	playlist, err := os.Create(playlistPath)
	if err != nil {
		return fmt.Errorf("could not create playlist: %v", err)
	}
	defer playlist.Close()

	// Write playlist header
	playlist.WriteString("#EXTM3U\n")
	playlist.WriteString("#EXT-X-VERSION:3\n")
	playlist.WriteString(fmt.Sprintf("#EXT-X-TARGETDURATION:%.0f\n", h.segmentDuration))
	playlist.WriteString("#EXT-X-MEDIA-SEQUENCE:0\n")

	h.segmentStart = 0
	h.currentSegment = 0

	for C.av_read_frame(h.inputFmtCtx, h.packet) >= 0 {
		if int32(h.packet.stream_index) == h.videoStreamIdx {
			if C.avcodec_send_packet(h.codecCtx, h.packet) == 0 {
				for C.avcodec_receive_frame(h.codecCtx, h.frame) == 0 {
					pts := h.frame.pts
					if pts == C.AV_NOPTS_VALUE {
						pts = h.frame.best_effort_timestamp
					}

					frameTime := float64(pts) * h.timeBase

					// Check if we need to start a new segment
					if h.currentSegment == 0 || frameTime-float64(h.segmentStart)*h.timeBase >= h.segmentDuration {
						if h.currentSegment > 0 {
							// Finish current segment
							if err := h.finishSegment(playlist); err != nil {
								return err
							}
						}
						// Start new segment
						if err := h.startSegment(); err != nil {
							return err
						}
					}

					// Write frame to current segment
					if err := h.writeFrame(); err != nil {
						return err
					}
				}
			}
		}
		C.av_packet_unref(h.packet)
	}

	// Finish last segment
	if h.currentSegment > 0 {
		if err := h.finishSegment(playlist); err != nil {
			return err
		}
	}

	// Write playlist end
	playlist.WriteString("#EXT-X-ENDLIST\n")

	return nil
}

func (h *HLSegmenter) startSegment() error {
	h.segmentStart = int64(h.frame.pts)
	h.segmentPts = int64(h.frame.pts)
	h.currentSegment++
	return nil
}

func (h *HLSegmenter) writeFrame() error {
	// Scale frame to YUV420P
	C.sws_scale(h.swsCtx,
		(**C.uint8_t)(unsafe.Pointer(&h.frame.data[0])),
		(*C.int)(unsafe.Pointer(&h.frame.linesize[0])),
		0,
		h.codecCtx.height,
		(**C.uint8_t)(unsafe.Pointer(&h.rgbFrame.data[0])),
		(*C.int)(unsafe.Pointer(&h.rgbFrame.linesize[0])),
	)

	// Write frame to segment file (simplified - actual TS muxing would be more complex)
	segmentFile := filepath.Join(h.outputDir, fmt.Sprintf("segment_%03d.ts", h.currentSegment))
	file, err := os.OpenFile(segmentFile, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return fmt.Errorf("could not open segment file: %v", err)
	}
	defer file.Close()

	// For simplicity, we're just writing raw frame data
	// In a real implementation, you'd use avformat_write_header() and av_interleaved_write_frame()
	data := C.GoBytes(unsafe.Pointer(&h.rgbFrame.data[0]), C.int(h.rgbFrame.linesize[0]*h.codecCtx.height))
	_, err = file.Write(data)
	return err
}

func (h *HLSegmenter) finishSegment(playlist *os.File) error {
	segmentDuration := float64(int64(h.frame.pts)-h.segmentStart) * h.timeBase
	segmentFile := fmt.Sprintf("segment_%03d.ts", h.currentSegment)

	playlist.WriteString(fmt.Sprintf("#EXTINF:%.3f,\n", segmentDuration))
	playlist.WriteString(segmentFile + "\n")

	return nil
}
