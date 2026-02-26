package main

import (
	"crypto/sha1"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"time"
)

const (
	protocolName = "BitTorrent protocol"
	handshakeLen = 68
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
	port := 6881
	repeats := 2000
	if len(os.Args) > 1 {
		host = os.Args[1]
	}
	if len(os.Args) > 2 {
		v, err := strconv.Atoi(os.Args[2])
		if err != nil || v < 1 || v > 65535 {
			return "", 0, 0, errors.New("invalid port")
		}
		port = v
	}
	if len(os.Args) > 3 {
		v, err := strconv.Atoi(os.Args[3])
		if err != nil || v < 1 {
			return "", 0, 0, errors.New("invalid repeats")
		}
		repeats = v
	}
	return host, port, repeats, nil
}

func buildHandshake() [handshakeLen]byte {
	var hs [handshakeLen]byte
	hs[0] = byte(len(protocolName))
	copy(hs[1:20], protocolName)
	infoHash := sha1.Sum([]byte("compare-rust-go-zig-demo-torrent"))
	copy(hs[28:48], infoHash[:])
	copy(hs[48:68], []byte("-GO0001-123456789012"))
	return hs
}

func doHandshake(address string, handshake [handshakeLen]byte) error {
	conn, err := net.DialTimeout("tcp", address, 200*time.Millisecond)
	if err != nil {
		return fmt.Errorf("connect: %w", err)
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(500 * time.Millisecond)); err != nil {
		return fmt.Errorf("set deadline: %w", err)
	}
	if _, err := conn.Write(handshake[:]); err != nil {
		return fmt.Errorf("write handshake: %w", err)
	}
	var resp [handshakeLen]byte
	if _, err := io.ReadFull(conn, resp[:]); err != nil {
		return fmt.Errorf("read handshake: %w", err)
	}
	if resp[0] != byte(len(protocolName)) || string(resp[1:20]) != protocolName {
		return errors.New("invalid handshake response")
	}
	return nil
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
	address := net.JoinHostPort(host, strconv.Itoa(port))
	handshake := buildHandshake()
	start := time.Now()
	for i := 0; i < repeats; i++ {
		if err := doHandshake(address, handshake); err != nil {
			fmt.Fprintln(os.Stderr, "Error:", err)
			os.Exit(1)
		}
	}
	printStats(stats{totalProcessed: uint64(repeats), processingNs: time.Since(start).Nanoseconds()})
}
