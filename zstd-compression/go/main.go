package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"strconv"
	"time"

	"github.com/klauspost/compress/zstd"
)

type stats struct {
	inputBytes    int64
	compressNs    int64
	decompressNs  int64
	compressedBytes int64
}

func (s stats) compressThroughputMBs() float64 {
	if s.compressNs == 0 {
		return 0
	}
	return float64(s.inputBytes) / 1e6 / (float64(s.compressNs) / 1e9)
}

func (s stats) decompressThroughputMBs() float64 {
	if s.decompressNs == 0 {
		return 0
	}
	return float64(s.inputBytes) / 1e6 / (float64(s.decompressNs) / 1e9)
}

func (s stats) compressionRatio() float64 {
	if s.compressedBytes == 0 {
		return 0
	}
	return float64(s.inputBytes) / float64(s.compressedBytes)
}

func parseArgs() (string, int) {
	inputPath := "/data/logs.txt"
	repeats := 1
	if len(os.Args) > 1 {
		inputPath = os.Args[1]
	}
	if len(os.Args) > 2 {
		n, err := strconv.Atoi(os.Args[2])
		if err == nil && n > 0 {
			repeats = n
		}
	}
	return inputPath, repeats
}

func processFile(path string) (stats, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return stats{}, fmt.Errorf("read file: %w", err)
	}

	// Compress
	var compressed bytes.Buffer
	enc, err := zstd.NewWriter(&compressed, zstd.WithEncoderLevel(zstd.SpeedDefault))
	if err != nil {
		return stats{}, fmt.Errorf("create encoder: %w", err)
	}

	compressStart := time.Now()
	if _, err := enc.Write(data); err != nil {
		return stats{}, fmt.Errorf("compress: %w", err)
	}
	if err := enc.Close(); err != nil {
		return stats{}, fmt.Errorf("close encoder: %w", err)
	}
	compressNs := time.Since(compressStart).Nanoseconds()
	compressedBytes := int64(compressed.Len())

	// Decompress
	dec, err := zstd.NewReader(&compressed)
	if err != nil {
		return stats{}, fmt.Errorf("create decoder: %w", err)
	}
	defer dec.Close()

	decompressStart := time.Now()
	decompressed, err := io.ReadAll(dec)
	if err != nil {
		return stats{}, fmt.Errorf("decompress: %w", err)
	}
	decompressNs := time.Since(decompressStart).Nanoseconds()

	// Verify round-trip
	if int64(len(decompressed)) != int64(len(data)) {
		return stats{}, fmt.Errorf("round-trip size mismatch: %d != %d", len(decompressed), len(data))
	}

	return stats{
		inputBytes:      int64(len(data)),
		compressNs:      compressNs,
		decompressNs:    decompressNs,
		compressedBytes: compressedBytes,
	}, nil
}

func printStats(s stats) {
	inputMB := float64(s.inputBytes) / 1e6
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.inputBytes)
	fmt.Printf("Processing time: %.3fs\n", float64(s.compressNs+s.decompressNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", float64(s.compressNs+s.decompressNs)/1e6)
	fmt.Printf("Throughput: %.2f items/sec\n", s.compressThroughputMBs())
	fmt.Printf("Input size: %.2f MB\n", inputMB)
	fmt.Printf("Compressed size: %.2f MB\n", float64(s.compressedBytes)/1e6)
	fmt.Printf("Compression ratio: %.2fx\n", s.compressionRatio())
	fmt.Printf("Compress speed: %.2f MB/s\n", s.compressThroughputMBs())
	fmt.Printf("Decompress speed: %.2f MB/s\n", s.decompressThroughputMBs())
}

func main() {
	inputPath, repeats := parseArgs()

	var best stats
	for i := 0; i < repeats; i++ {
		s, err := processFile(inputPath)
		if err != nil {
			fmt.Fprintf(os.Stderr, "error: %v\n", err)
			os.Exit(1)
		}
		if i == 0 || (s.compressNs+s.decompressNs) < (best.compressNs+best.decompressNs) {
			best = s
		}
	}

	printStats(best)
}
