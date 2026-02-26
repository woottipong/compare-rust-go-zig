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

func parseArgs() (string, int, int, int, error) {
	host := "host.docker.internal"
	startPort := 54000
	endPort := 54009
	repeats := 200
	if len(os.Args) > 1 { host = os.Args[1] }
	if len(os.Args) > 2 { v, e := strconv.Atoi(os.Args[2]); if e != nil { return "",0,0,0,e }; startPort=v }
	if len(os.Args) > 3 { v, e := strconv.Atoi(os.Args[3]); if e != nil { return "",0,0,0,e }; endPort=v }
	if len(os.Args) > 4 { v, e := strconv.Atoi(os.Args[4]); if e != nil || v < 1 { return "",0,0,0,errors.New("invalid repeats") }; repeats=v }
	if endPort < startPort { return "",0,0,0,errors.New("end port must be >= start port") }
	return host, startPort, endPort, repeats, nil
}

func scan(host string, startPort, endPort int) int {
	open := 0
	for p := startPort; p <= endPort; p++ {
		conn, err := net.DialTimeout("tcp", fmt.Sprintf("%s:%d", host, p), 50*time.Millisecond)
		if err == nil {
			open++
			_ = conn.Close()
		}
	}
	return open
}

func printStats(s stats) {
	fmt.Println("--- Statistics ---")
	fmt.Printf("Total processed: %d\n", s.totalProcessed)
	fmt.Printf("Processing time: %.3fs\n", float64(s.processingNs)/1e9)
	fmt.Printf("Average latency: %.6fms\n", s.avgLatencyMs())
	fmt.Printf("Throughput: %.2f items/sec\n", s.throughput())
}

func main() {
	host, sp, ep, repeats, err := parseArgs()
	if err != nil { fmt.Fprintln(os.Stderr, "Error:", err); os.Exit(1) }
	portsPerRun := ep - sp + 1
	start := time.Now()
	open := 0
	for i := 0; i < repeats; i++ { open = scan(host, sp, ep) }
	fmt.Printf("Open ports: %d\n", open)
	printStats(stats{totalProcessed: uint64(portsPerRun * repeats), processingNs: time.Since(start).Nanoseconds()})
}
