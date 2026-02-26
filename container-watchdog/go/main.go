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

type sample struct {
	cpu float64
	mem float64
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

func parseArgs() (string, int, error) {
	input := "/data/metrics.csv"
	loops := 200
	if len(os.Args) > 1 {
		input = os.Args[1]
	}
	if len(os.Args) > 2 {
		n, err := strconv.Atoi(os.Args[2])
		if err != nil || n < 1 {
			return "", 0, errors.New("loops must be positive integer")
		}
		loops = n
	}
	return input, loops, nil
}

func parseLine(line string) (sample, error) {
	parts := strings.Split(line, ",")
	if len(parts) != 3 {
		return sample{}, errors.New("invalid csv line")
	}
	cpu, err := strconv.ParseFloat(parts[1], 64)
	if err != nil {
		return sample{}, err
	}
	mem, err := strconv.ParseFloat(parts[2], 64)
	if err != nil {
		return sample{}, err
	}
	return sample{cpu: cpu, mem: mem}, nil
}

func loadSamples(path string) ([]sample, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open input: %w", err)
	}
	defer file.Close()

	items := make([]sample, 0, 1024)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		s, parseErr := parseLine(line)
		if parseErr != nil {
			return nil, fmt.Errorf("parse line %q: %w", line, parseErr)
		}
		items = append(items, s)
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan input: %w", err)
	}
	if len(items) == 0 {
		return nil, errors.New("no samples found")
	}
	return items, nil
}

func process(samples []sample, loops int) uint64 {
	const cpuThreshold = 85.0
	const memThreshold = 90.0
	const streakLimit = 3
	const cooldownTicks = 20

	var cpuStreak int
	var memStreak int
	var cooldown int
	var actions uint64
	var processed uint64

	for i := 0; i < loops; i++ {
		for _, s := range samples {
			processed++
			if cooldown > 0 {
				cooldown--
			}

			if s.cpu > cpuThreshold {
				cpuStreak++
			} else {
				cpuStreak = 0
			}
			if s.mem > memThreshold {
				memStreak++
			} else {
				memStreak = 0
			}

			if memStreak >= streakLimit && cooldown == 0 {
				actions++
				cooldown = cooldownTicks
				memStreak = 0
				cpuStreak = 0
				continue
			}
			if cpuStreak >= streakLimit {
				actions++
				cpuStreak = 0
			}
		}
	}

	return processed + actions
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	input, loops, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	samples, err := loadSamples(input)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	start := time.Now()
	total := process(samples, loops)
	printStats(stats{totalProcessed: total, processingNs: time.Since(start).Nanoseconds()})
}
