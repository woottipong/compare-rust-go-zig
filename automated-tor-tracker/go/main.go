package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
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

func parseArgs() (string, int, error) {
	inputPath := "/data/tor.txt"
	repeats := 20000
	if len(os.Args) > 1 {
		inputPath = os.Args[1]
	}
	if len(os.Args) > 2 {
		_, err := fmt.Sscanf(os.Args[2], "%d", &repeats)
		if err != nil || repeats < 1 {
			return "", 0, errors.New("invalid repeats")
		}
	}
	return inputPath, repeats, nil
}

func loadLines(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open input: %w", err)
	}
	defer f.Close()
	lines := make([]string, 0, 1024)
	s := bufio.NewScanner(f)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line != "" {
			lines = append(lines, line)
		}
	}
	if err := s.Err(); err != nil {
		return nil, fmt.Errorf("scan input: %w", err)
	}
	if len(lines) == 0 {
		return nil, errors.New("empty input")
	}
	return lines, nil
}

func extractStatus(line string) string {
	lower := strings.ToLower(line)
	switch {
	case strings.Contains(lower, "done"), strings.Contains(lower, "completed"):
		return "done"
	case strings.Contains(lower, "in progress"), strings.Contains(lower, "ongoing"):
		return "in_progress"
	case strings.Contains(lower, "blocked"), strings.Contains(lower, "risk"):
		return "blocked"
	default:
		return "todo"
	}
}

func runBenchmark(lines []string, repeats int) uint64 {
	var processed uint64
	for i := 0; i < repeats; i++ {
		for _, line := range lines {
			_ = extractStatus(line)
			processed++
		}
	}
	return processed
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	inputPath, repeats, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	lines, err := loadLines(inputPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	start := time.Now()
	processed := runBenchmark(lines, repeats)
	printStats(stats{totalProcessed: processed, processingNs: time.Since(start).Nanoseconds()})
}
