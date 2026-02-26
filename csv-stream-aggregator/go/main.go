package main

import (
	"bufio"
	"errors"
	"fmt"
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

type aggregate struct {
	count uint64
	sum   float64
}

func parseArgs() (string, int, error) {
	input := "/data/sales.csv"
	repeats := 30
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

func processFile(path string) (uint64, map[string]aggregate, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, nil, fmt.Errorf("open input: %w", err)
	}
	defer f.Close()

	aggs := map[string]aggregate{}
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	var lineNo uint64
	var rows uint64
	for s.Scan() {
		line := s.Text()
		lineNo++
		if lineNo == 1 && strings.HasPrefix(line, "category,") {
			continue
		}
		parts := strings.Split(line, ",")
		if len(parts) < 2 {
			continue
		}
		amount, err := strconv.ParseFloat(parts[1], 64)
		if err != nil {
			continue
		}
		key := parts[0]
		a := aggs[key]
		a.count++
		a.sum += amount
		aggs[key] = a
		rows++
	}
	if err := s.Err(); err != nil {
		return 0, nil, fmt.Errorf("scan input: %w", err)
	}
	return rows, aggs, nil
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

	var rows uint64
	var aggs map[string]aggregate
	start := time.Now()
	for i := 0; i < repeats; i++ {
		rows, aggs, err = processFile(input)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
	}
	_ = aggs
	printStats(stats{totalProcessed: rows * uint64(repeats), processingNs: time.Since(start).Nanoseconds()})
}
