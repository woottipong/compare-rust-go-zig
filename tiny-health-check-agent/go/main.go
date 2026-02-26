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

type target struct {
	expectedUp bool
	baseMs     int
	jitterMs   int
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
	input := "/data/targets.csv"
	loops := 5000
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

func parseTarget(line string) (target, error) {
	parts := strings.Split(line, ",")
	if len(parts) != 5 {
		return target{}, errors.New("invalid csv line")
	}
	up, err := strconv.ParseBool(strings.TrimSpace(parts[2]))
	if err != nil {
		return target{}, err
	}
	base, err := strconv.Atoi(strings.TrimSpace(parts[3]))
	if err != nil {
		return target{}, err
	}
	jitter, err := strconv.Atoi(strings.TrimSpace(parts[4]))
	if err != nil {
		return target{}, err
	}
	if base < 0 || jitter < 0 {
		return target{}, errors.New("base/jitter must be >= 0")
	}
	return target{expectedUp: up, baseMs: base, jitterMs: jitter}, nil
}

func loadTargets(path string) ([]target, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("open input: %w", err)
	}
	defer file.Close()

	items := make([]target, 0, 128)
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		t, parseErr := parseTarget(line)
		if parseErr != nil {
			return nil, fmt.Errorf("parse line %q: %w", line, parseErr)
		}
		items = append(items, t)
	}
	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("scan input: %w", err)
	}
	if len(items) == 0 {
		return nil, errors.New("no targets found")
	}
	return items, nil
}

func evaluateStatus(t target, iteration int, idx int) (bool, int) {
	seed := (iteration+1)*31 + (idx+1)*17
	latency := t.baseMs + (seed % (t.jitterMs + 1))
	flap := (seed%97 == 0)
	isUp := t.expectedUp
	if flap {
		isUp = !isUp
	}
	return isUp, latency
}

func runChecks(targets []target, loops int) uint64 {
	const failLimit = 3
	const recoverLimit = 2
	const alertCooldownTicks = 8

	failStreak := make([]int, len(targets))
	recoverStreak := make([]int, len(targets))
	cooldown := make([]int, len(targets))

	var alerts uint64
	var processed uint64

	for i := 0; i < loops; i++ {
		for idx, t := range targets {
			processed++
			if cooldown[idx] > 0 {
				cooldown[idx]--
			}
			up, latency := evaluateStatus(t, i, idx)
			if latency > 0 && !up {
				failStreak[idx]++
				recoverStreak[idx] = 0
			} else {
				recoverStreak[idx]++
				failStreak[idx] = 0
			}

			if failStreak[idx] >= failLimit && cooldown[idx] == 0 {
				alerts++
				cooldown[idx] = alertCooldownTicks
				continue
			}
			if recoverStreak[idx] >= recoverLimit && cooldown[idx] == 0 {
				alerts++
			}
		}
	}
	return processed + alerts
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f checks/sec\n", s.throughput())
}

func main() {
	input, loops, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	targets, err := loadTargets(input)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}

	start := time.Now()
	total := runChecks(targets, loops)
	printStats(stats{totalProcessed: total, processingNs: time.Since(start).Nanoseconds()})
}
