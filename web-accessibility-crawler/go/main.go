package main

import (
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
	inputPath := "/data/pages.html"
	repeats := 100000
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

func loadPages(path string) ([]string, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read input: %w", err)
	}
	parts := strings.Split(string(content), "\n===\n")
	pages := make([]string, 0, len(parts))
	for _, p := range parts {
		trimmed := strings.TrimSpace(p)
		if trimmed != "" {
			pages = append(pages, trimmed)
		}
	}
	if len(pages) == 0 {
		return nil, errors.New("no pages found")
	}
	return pages, nil
}

func countIssues(page string) int {
	issues := 0
	lower := strings.ToLower(page)
	if !strings.Contains(lower, "<html") || !strings.Contains(lower, "lang=") {
		issues++
	}
	if !strings.Contains(lower, "<title") {
		issues++
	}
	imgCount := strings.Count(lower, "<img")
	altCount := strings.Count(lower, "alt=")
	if altCount < imgCount {
		issues += imgCount - altCount
	}
	if strings.Contains(lower, "<a ") && !strings.Contains(lower, "aria-label=") {
		issues++
	}
	return issues
}

func runBenchmark(pages []string, repeats int) uint64 {
	var processed uint64
	for i := 0; i < repeats; i++ {
		for _, p := range pages {
			_ = countIssues(p)
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
	pages, err := loadPages(inputPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	start := time.Now()
	processed := runBenchmark(pages, repeats)
	printStats(stats{totalProcessed: processed, processingNs: time.Since(start).Nanoseconds()})
}
