package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
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

func parseArgs() (string, string, int, int, int, error) {
	input := "/data/sample.jpg"
	output := "/tmp/output.jpg"
	width := 160
	height := 90
	repeats := 20
	if len(os.Args) > 1 {
		input = os.Args[1]
	}
	if len(os.Args) > 2 {
		output = os.Args[2]
	}
	if len(os.Args) > 3 {
		v, err := strconv.Atoi(os.Args[3])
		if err != nil || v < 1 {
			return "", "", 0, 0, 0, errors.New("width must be positive integer")
		}
		width = v
	}
	if len(os.Args) > 4 {
		v, err := strconv.Atoi(os.Args[4])
		if err != nil || v < 1 {
			return "", "", 0, 0, 0, errors.New("height must be positive integer")
		}
		height = v
	}
	if len(os.Args) > 5 {
		v, err := strconv.Atoi(os.Args[5])
		if err != nil || v < 1 {
			return "", "", 0, 0, 0, errors.New("repeats must be positive integer")
		}
		repeats = v
	}
	return input, output, width, height, repeats, nil
}

func runFfmpeg(input, output string, width, height int) error {
	scale := fmt.Sprintf("scale=%d:%d:flags=bilinear", width, height)
	cmd := exec.Command("ffmpeg", "-loglevel", "error", "-y", "-i", input, "-vf", scale, "-frames:v", "1", output)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg failed: %w: %s", err, string(out))
	}
	return nil
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	input, output, width, height, repeats, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	if _, err := os.Stat(input); err != nil {
		fmt.Fprintf(os.Stderr, "Error: input not found: %s\n", input)
		os.Exit(1)
	}

	start := time.Now()
	for i := 0; i < repeats; i++ {
		if err := runFfmpeg(input, output, width, height); err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
	}

	total := uint64(width * height * repeats)
	printStats(stats{totalProcessed: total, processingNs: time.Since(start).Nanoseconds()})
}
