package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"os"
	"strconv"
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

func parseArgs() (string, int, error) {
	input := "/data/sample.parquet"
	repeats := 40
	if len(os.Args) > 1 {
		input = os.Args[1]
	}
	if len(os.Args) > 2 {
		n, err := strconv.Atoi(os.Args[2])
		if err != nil || n < 1 {
			return "", 0, errors.New("repeats must be positive integer")
		}
		repeats = n
	}
	return input, repeats, nil
}

func readUvarint(data []byte, idx *int) (uint64, error) {
	var x uint64
	var s uint
	for i := 0; i < 10; i++ {
		if *idx >= len(data) {
			return 0, errors.New("unexpected eof in varint")
		}
		b := data[*idx]
		*idx = *idx + 1
		if b < 0x80 {
			return x | uint64(b)<<s, nil
		}
		x |= uint64(b&0x7f) << s
		s += 7
	}
	return 0, errors.New("varint overflow")
}

func unpackBitpacked(src []byte, bitWidth, count int, out *[]uint32) {
	var bitPos int
	for i := 0; i < count; i++ {
		var v uint32
		for b := 0; b < bitWidth; b++ {
			byteIdx := (bitPos + b) / 8
			bitIdx := (bitPos + b) % 8
			if byteIdx < len(src) && ((src[byteIdx]>>bitIdx)&1) == 1 {
				v |= 1 << b
			}
		}
		*out = append(*out, v)
		bitPos += bitWidth
	}
}

func decodeHybrid(encoded []byte, bitWidth int, expected int) ([]uint32, error) {
	values := make([]uint32, 0, expected)
	idx := 0
	for idx < len(encoded) && len(values) < expected {
		h, err := readUvarint(encoded, &idx)
		if err != nil {
			return nil, err
		}
		if h&1 == 0 {
			run := int(h >> 1)
			byteWidth := (bitWidth + 7) / 8
			if idx+byteWidth > len(encoded) {
				return nil, errors.New("invalid rle payload")
			}
			var v uint32
			for i := 0; i < byteWidth; i++ {
				v |= uint32(encoded[idx+i]) << (8 * i)
			}
			idx += byteWidth
			for i := 0; i < run && len(values) < expected; i++ {
				values = append(values, v)
			}
		} else {
			numGroups := int(h >> 1)
			n := numGroups * 8
			byteCount := numGroups * bitWidth
			if idx+byteCount > len(encoded) {
				return nil, errors.New("invalid bitpack payload")
			}
			unpackBitpacked(encoded[idx:idx+byteCount], bitWidth, n, &values)
			idx += byteCount
		}
	}
	if len(values) > expected {
		values = values[:expected]
	}
	if len(values) != expected {
		return nil, errors.New("decoded size mismatch")
	}
	return values, nil
}

func processFile(path string) (int, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return 0, fmt.Errorf("read input: %w", err)
	}
	if len(data) < 17 {
		return 0, errors.New("file too small")
	}
	if string(data[:4]) != "PAR1" || string(data[len(data)-4:]) != "PAR1" {
		return 0, errors.New("invalid parquet magic")
	}
	metaLen := int(binary.LittleEndian.Uint32(data[len(data)-8 : len(data)-4]))
	if metaLen < 0 || len(data)-8-metaLen < 13 {
		return 0, errors.New("invalid metadata length")
	}
	bitWidth := int(data[4])
	numValues := int(binary.LittleEndian.Uint32(data[5:9]))
	encodedLen := int(binary.LittleEndian.Uint32(data[9:13]))
	if 13+encodedLen > len(data)-8-metaLen {
		return 0, errors.New("invalid encoded section")
	}
	_, err = decodeHybrid(data[13:13+encodedLen], bitWidth, numValues)
	if err != nil {
		return 0, err
	}
	return numValues, nil
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	input, repeats, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	start := time.Now()
	num := 0
	for i := 0; i < repeats; i++ {
		num, err = processFile(input)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
	}

	printStats(stats{totalProcessed: uint64(num * repeats), processingNs: time.Since(start).Nanoseconds()})
}
