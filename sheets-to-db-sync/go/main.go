package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
)

type record struct {
	id         string
	name       string
	email      string
	updatedAt  string
}

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
	sheetPath := "/data/sheet.csv"
	dbPath := "/data/db.csv"
	repeats := 1000
	args := os.Args[1:]
	if len(args) > 0 {
		sheetPath = args[0]
	}
	if len(args) > 1 {
		dbPath = args[1]
	}
	if len(args) > 2 {
		_, err := fmt.Sscanf(args[2], "%d", &repeats)
		if err != nil || repeats < 1 {
			return "", "", 0, errors.New("invalid repeats")
		}
	}
	return sheetPath, dbPath, repeats, nil
}

func parseCSV(path string) ([]record, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open csv: %w", err)
	}
	defer f.Close()

	rows := make([]record, 0, 1024)
	s := bufio.NewScanner(f)
	lineNo := 0
	for s.Scan() {
		lineNo++
		line := strings.TrimSpace(s.Text())
		if line == "" {
			continue
		}
		if lineNo == 1 && strings.HasPrefix(line, "id,") {
			continue
		}
		parts := strings.Split(line, ",")
		if len(parts) != 4 {
			return nil, fmt.Errorf("invalid csv row at line %d", lineNo)
		}
		rows = append(rows, record{id: parts[0], name: parts[1], email: parts[2], updatedAt: parts[3]})
	}
	if err := s.Err(); err != nil {
		return nil, fmt.Errorf("scan csv: %w", err)
	}
	return rows, nil
}

func toMap(rows []record) map[string]record {
	m := make(map[string]record, len(rows))
	for _, r := range rows {
		m[r.id] = r
	}
	return m
}

func syncRows(sheetRows []record, db map[string]record) {
	for _, r := range sheetRows {
		db[r.id] = r
	}
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	sheetPath, dbPath, repeats, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	sheetRows, err := parseCSV(sheetPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	dbRows, err := parseCSV(dbPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	dbMap := toMap(dbRows)
	start := time.Now()
	for i := 0; i < repeats; i++ {
		syncRows(sheetRows, dbMap)
	}
	printStats(stats{totalProcessed: uint64(len(sheetRows) * repeats), processingNs: time.Since(start).Nanoseconds()})
}
