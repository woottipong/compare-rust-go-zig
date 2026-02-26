package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"hash/crc32"
	"os"
	"strconv"
	"strings"
	"time"
)

type stats struct {
	totalProcessed uint64
	processingNs   int64
}

func (s stats) avgLatencyMs() float64 {
	if s.totalProcessed == 0 {
		return 0
	}
	return float64(s.processingNs) / 1e6 / float64(s.totalProcessed)
}

func (s stats) throughput() float64 {
	if s.processingNs == 0 {
		return 0
	}
	return float64(s.totalProcessed) * 1e9 / float64(s.processingNs)
}

func parseArgs() (string, string, int, error) {
	input := "/data/sample.ppm"
	output := "/tmp/output.png"
	repeats := 30
	if len(os.Args) > 1 {
		input = os.Args[1]
	}
	if len(os.Args) > 2 {
		output = os.Args[2]
	}
	if len(os.Args) > 3 {
		n, err := strconv.Atoi(os.Args[3])
		if err != nil || n < 1 {
			return "", "", 0, errors.New("repeats must be positive integer")
		}
		repeats = n
	}
	return input, output, repeats, nil
}

func readToken(data []byte, idx *int) (string, error) {
	for *idx < len(data) {
		if data[*idx] == '#' {
			for *idx < len(data) && data[*idx] != '\n' {
				*idx = *idx + 1
			}
		} else if strings.ContainsRune(" \t\r\n", rune(data[*idx])) {
			*idx = *idx + 1
		} else {
			break
		}
	}
	if *idx >= len(data) {
		return "", errors.New("unexpected eof")
	}
	start := *idx
	for *idx < len(data) && !strings.ContainsRune(" \t\r\n", rune(data[*idx])) {
		*idx = *idx + 1
	}
	return string(data[start:*idx]), nil
}

func parsePPM(data []byte) (int, int, []byte, error) {
	idx := 0
	magic, err := readToken(data, &idx)
	if err != nil {
		return 0, 0, nil, err
	}
	if magic != "P6" {
		return 0, 0, nil, errors.New("only P6 ppm supported")
	}
	wTok, err := readToken(data, &idx)
	if err != nil {
		return 0, 0, nil, err
	}
	hTok, err := readToken(data, &idx)
	if err != nil {
		return 0, 0, nil, err
	}
	mTok, err := readToken(data, &idx)
	if err != nil {
		return 0, 0, nil, err
	}
	w, err := strconv.Atoi(wTok)
	if err != nil || w < 1 {
		return 0, 0, nil, errors.New("invalid width")
	}
	h, err := strconv.Atoi(hTok)
	if err != nil || h < 1 {
		return 0, 0, nil, errors.New("invalid height")
	}
	maxVal, err := strconv.Atoi(mTok)
	if err != nil || maxVal != 255 {
		return 0, 0, nil, errors.New("max value must be 255")
	}
	for idx < len(data) && strings.ContainsRune(" \t\r\n", rune(data[idx])) {
		idx++
	}
	expected := w * h * 3
	if len(data[idx:]) < expected {
		return 0, 0, nil, errors.New("ppm payload too short")
	}
	return w, h, data[idx : idx+expected], nil
}

func adler32Sum(data []byte) uint32 {
	const mod uint32 = 65521
	var s1 uint32 = 1
	var s2 uint32 = 0
	for _, b := range data {
		s1 = (s1 + uint32(b)) % mod
		s2 = (s2 + s1) % mod
	}
	return (s2 << 16) | s1
}

func zlibStored(raw []byte) []byte {
	out := make([]byte, 0, len(raw)+len(raw)/65535*5+6)
	out = append(out, 0x78, 0x01)
	remaining := len(raw)
	off := 0
	for remaining > 0 {
		block := remaining
		if block > 65535 {
			block = 65535
		}
		final := byte(0)
		if block == remaining {
			final = 1
		}
		out = append(out, final)
		lenBytes := []byte{byte(block), byte(block >> 8)}
		nlen := ^uint16(block)
		nlenBytes := []byte{byte(nlen), byte(nlen >> 8)}
		out = append(out, lenBytes...)
		out = append(out, nlenBytes...)
		out = append(out, raw[off:off+block]...)
		off += block
		remaining -= block
	}
	ad := adler32Sum(raw)
	out = binary.BigEndian.AppendUint32(out, ad)
	return out
}

func appendChunk(buf *bytes.Buffer, chunkType string, payload []byte) {
	binary.Write(buf, binary.BigEndian, uint32(len(payload)))
	buf.WriteString(chunkType)
	buf.Write(payload)
	crc := crc32.ChecksumIEEE(append([]byte(chunkType), payload...))
	binary.Write(buf, binary.BigEndian, crc)
}

func encodePNG(width, height int, rgb []byte) ([]byte, error) {
	if len(rgb) != width*height*3 {
		return nil, errors.New("invalid rgb payload")
	}
	stride := width * 3
	raw := make([]byte, 0, height*(stride+1))
	for y := 0; y < height; y++ {
		raw = append(raw, 0)
		start := y * stride
		raw = append(raw, rgb[start:start+stride]...)
	}
	idat := zlibStored(raw)

	var out bytes.Buffer
	out.Write([]byte{137, 80, 78, 71, 13, 10, 26, 10})
	ihdr := make([]byte, 13)
	binary.BigEndian.PutUint32(ihdr[0:4], uint32(width))
	binary.BigEndian.PutUint32(ihdr[4:8], uint32(height))
	ihdr[8] = 8
	ihdr[9] = 2
	appendChunk(&out, "IHDR", ihdr)
	appendChunk(&out, "IDAT", idat)
	appendChunk(&out, "IEND", nil)
	return out.Bytes(), nil
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	input, output, repeats, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	raw, err := os.ReadFile(input)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: read %s: %v\n", input, err)
		os.Exit(1)
	}
	w, h, rgb, err := parsePPM(raw)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	start := time.Now()
	var png []byte
	for i := 0; i < repeats; i++ {
		png, err = encodePNG(w, h, rgb)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
	}
	if err := os.WriteFile(output, png, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Error: write %s: %v\n", output, err)
		os.Exit(1)
	}

	total := uint64(w * h * repeats)
	printStats(stats{totalProcessed: total, processingNs: time.Since(start).Nanoseconds()})
}
