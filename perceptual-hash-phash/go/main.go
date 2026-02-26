package main

import (
	"errors"
	"fmt"
	"math"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const size = 32
const lowFreq = 8

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
	input := "/data/sample.jpg"
	repeats := 20
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

func runFfmpeg(input, output string) error {
	cmd := exec.Command("ffmpeg", "-loglevel", "error", "-y", "-i", input, "-vf", "scale=32:32,format=gray", "-frames:v", "1", output)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("ffmpeg failed: %w: %s", err, string(out))
	}
	return nil
}

func nextToken(data []byte, idx *int) (string, error) {
	for *idx < len(data) {
		if data[*idx] == '#' {
			for *idx < len(data) && data[*idx] != '\n' {
				*idx++
			}
		} else if strings.ContainsRune(" \t\r\n", rune(data[*idx])) {
			*idx++
		} else {
			break
		}
	}
	if *idx >= len(data) {
		return "", errors.New("unexpected eof")
	}
	start := *idx
	for *idx < len(data) && !strings.ContainsRune(" \t\r\n", rune(data[*idx])) {
		*idx++
	}
	return string(data[start:*idx]), nil
}

func parsePGM(data []byte) ([size][size]float64, error) {
	var matrix [size][size]float64
	idx := 0
	magic, err := nextToken(data, &idx)
	if err != nil {
		return matrix, err
	}
	if magic != "P5" {
		return matrix, errors.New("expected P5 pgm")
	}
	wTok, _ := nextToken(data, &idx)
	hTok, _ := nextToken(data, &idx)
	mTok, _ := nextToken(data, &idx)
	w, _ := strconv.Atoi(wTok)
	h, _ := strconv.Atoi(hTok)
	maxv, _ := strconv.Atoi(mTok)
	if w != size || h != size || maxv != 255 {
		return matrix, errors.New("invalid pgm header")
	}
	for idx < len(data) && strings.ContainsRune(" \t\r\n", rune(data[idx])) {
		idx++
	}
	if len(data[idx:]) < size*size {
		return matrix, errors.New("pgm payload too short")
	}
	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			matrix[y][x] = float64(data[idx+y*size+x])
		}
	}
	return matrix, nil
}

func dct2D(input [size][size]float64) [size][size]float64 {
	var out [size][size]float64
	for u := 0; u < size; u++ {
		for v := 0; v < size; v++ {
			sum := 0.0
			for x := 0; x < size; x++ {
				for y := 0; y < size; y++ {
					sum += input[y][x] *
						math.Cos((float64(2*x+1)*float64(u)*math.Pi)/64.0) *
						math.Cos((float64(2*y+1)*float64(v)*math.Pi)/64.0)
				}
			}
			cu := 1.0
			cv := 1.0
			if u == 0 {
				cu = 1.0 / math.Sqrt2
			}
			if v == 0 {
				cv = 1.0 / math.Sqrt2
			}
			out[v][u] = 0.25 * cu * cv * sum
		}
	}
	return out
}

func phash(matrix [size][size]float64) uint64 {
	dct := dct2D(matrix)
	vals := make([]float64, 0, lowFreq*lowFreq)
	for y := 0; y < lowFreq; y++ {
		for x := 0; x < lowFreq; x++ {
			vals = append(vals, dct[y][x])
		}
	}
	sum := 0.0
	for _, v := range vals {
		sum += v
	}
	avg := sum / float64(len(vals))
	var hash uint64
	for i, v := range vals {
		if v > avg {
			hash |= 1 << uint(i)
		}
	}
	return hash
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
	if _, err := os.Stat(input); err != nil {
		fmt.Fprintln(os.Stderr, "Error: input not found")
		os.Exit(1)
	}

	tmp := "/tmp/phash.pgm"
	start := time.Now()
	var last uint64
	for i := 0; i < repeats; i++ {
		if err := runFfmpeg(input, tmp); err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
		data, err := os.ReadFile(tmp)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
		img, err := parsePGM(data)
		if err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
		last = phash(img)
	}
	_ = os.Remove(tmp)
	fmt.Printf("pHash: %016x\n", last)
	printStats(stats{totalProcessed: uint64(repeats), processingNs: time.Since(start).Nanoseconds()})
}
