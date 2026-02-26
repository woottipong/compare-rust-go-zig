package main

import (
	"errors"
	"fmt"
	"net"
	"os"
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

func parseArgs() (string, int, int, error) {
	host := "host.docker.internal"
	port := 56000
	repeats := 3000
	if len(os.Args) > 1 {
		host = os.Args[1]
	}
	if len(os.Args) > 2 {
		v, e := strconv.Atoi(os.Args[2])
		if e != nil || v < 1 {
			return "", 0, 0, errors.New("invalid port")
		}
		port = v
	}
	if len(os.Args) > 3 {
		v, e := strconv.Atoi(os.Args[3])
		if e != nil || v < 1 {
			return "", 0, 0, errors.New("invalid repeats")
		}
		repeats = v
	}
	return host, port, repeats, nil
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	host, port, repeats, err := parseArgs()
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	conn, err := net.Dial("udp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))
	buf := make([]byte, 64)
	start := time.Now()
	for i := 0; i < repeats; i++ {
		if _, err := conn.Write([]byte("PING")); err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
		n, err := conn.Read(buf)
		if err != nil || string(buf[:n]) != "PONG" {
			fmt.Fprintln(os.Stderr, "Error: invalid response")
			os.Exit(1)
		}
	}
	printStats(stats{totalProcessed: uint64(repeats), processingNs: time.Since(start).Nanoseconds()})
}
