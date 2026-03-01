package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"time"
)

type record struct {
	ID     int     `json:"id"`
	Name   string  `json:"name"`
	Score  float64 `json:"score"`
	Active bool    `json:"active"`
}

type stats struct {
	totalProcessed int64
	processingNs   int64
	scoreSum       float64
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

func parseArgs() (string, int) {
	inputPath := "/data/records.jsonl"
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
	f, err := os.Open(path)
	if err != nil {
		return stats{}, fmt.Errorf("open file: %w", err)
	}
	defer f.Close()

	var s stats
	start := time.Now()

	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 1024*1024), 1024*1024)
	var rec record
	for scanner.Scan() {
		line := scanner.Bytes()
		if len(line) == 0 {
			continue
		}
		if err := json.Unmarshal(line, &rec); err != nil {
			continue
		}
		s.scoreSum += rec.Score
		s.totalProcessed++
	}

	s.processingNs = time.Since(start).Nanoseconds()
	return s, scanner.Err()
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
	fmt.Printf("Score sum: %.2f\n", s.scoreSum)
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
		if i == 0 || s.processingNs < best.processingNs {
			best = s
		}
	}

	printStats(best)
}
